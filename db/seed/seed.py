"""Carga reproducible de datos para Bodegas del Atuel.

Uso:
    python3 db/seed/seed.py --validate-only
    python3 db/seed/seed.py --reset

La carga normal no borra datos. ``--reset`` debe solicitarse explícitamente.
Los catálogos se leen desde db/seed/csv y las tablas/columnas coinciden con
db/migrations/001_esquema.sql.
"""

from __future__ import annotations

import argparse
import csv
import os
import random
import shutil
import subprocess
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Iterable, Sequence

import psycopg2
from faker import Faker
from psycopg2 import sql
from psycopg2.extras import execute_values


ROOT = Path(__file__).resolve().parent
CSV_DIR = ROOT / "csv"
SEED = 12345
Faker.seed(SEED)
fake = Faker("es_AR")
random.seed(SEED)

DB_CONFIG = {
    "dbname": os.getenv("BDA_DB_NAME", "bodega_del_atuel"),
    "user": os.getenv("BDA_DB_USER", "postgresql"),
    "password": os.getenv("BDA_DB_PASSWORD", "seed_local_password"),
    "host": os.getenv("BDA_DB_HOST", "localhost"),
    "port": int(os.getenv("BDA_DB_PORT", "5432")),
}

EXPECTED_CSV_HEADERS = {
    "cepas.csv": ("nombre", "tipo"),
    "departamentos.csv": ("nombre",),
    "maridajes.csv": ("nombre", "temp_servicio"),
    "presentaciones.csv": ("volumen_ml",),
    "tipos_vino.csv": ("nombre",),
    "campanas.csv": ("anio",),
}

CATALOG_TABLES = {
    "cepas.csv": ("cepa", ("nombre", "tipo")),
    "maridajes.csv": ("maridaje", ("nombre", "temp_servicio")),
}

TRANSACTIONAL_TABLES = (
    "comprobante",
    "renglon_comprobante",
    "ingreso",
    "renglon_ingreso",
    "transferencia",
    "renglon_transferencia",
    "stock_sala",
    "stock_deposito",
)

# Etapa 3, punto 5: la carga histórica se ejecuta con los triggers activos.
# Decisión: no deshabilitarlos para que la base valide las reglas de negocio
# durante la carga. Riesgo: la carga puede ser más lenta y cualquier dato
# histórico incompatible abortará la transacción; se valida al final con los
# controles de la Etapa 3.

ALL_TABLES = (
    "auditoria_precio",
    "renglon_comprobante",
    "comprobante",
    "permiso_exportacion",
    "exportador",
    "distribuidor",
    "cliente",
    "transportista_cubre_localidad",
    "vino_maridaje",
    "composicion",
    "maridaje",
    "vino",
    "analisis_calidad",
    "lote_uva",
    "bodega",
    "parcela",
    "finca",
    "cepa",
    "transportista",
    "renglon_transferencia",
    "transferencia",
    "renglon_ingreso",
    "ingreso",
    "stock_sala",
    "stock_deposito",
    "empleado",
    "sala_venta",
    "localidad",
    "departamento",
    "provincia",
)


def read_csv(name: str) -> list[dict[str, str]]:
    path = CSV_DIR / name
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        expected = EXPECTED_CSV_HEADERS[name]
        if tuple(reader.fieldnames or ()) != expected:
            raise ValueError(
                f"{path}: cabecera {reader.fieldnames!r}; se esperaba {expected!r}"
            )
        rows = list(reader)
    if not rows:
        raise ValueError(f"{path}: el catálogo no puede estar vacío")
    return rows


def load_catalogs() -> dict[str, list[dict[str, str]]]:
    catalogs = {name: read_csv(name) for name in EXPECTED_CSV_HEADERS}
    if len(catalogs["cepas.csv"]) != 12:
        raise ValueError("cepas.csv debe contener las 12 cepas del Anexo B")
    if len(catalogs["maridajes.csv"]) != 8:
        raise ValueError("maridajes.csv debe contener los 8 maridajes del Anexo B")
    if len(catalogs["departamentos.csv"]) != 18:
        raise ValueError(
            "departamentos.csv debe contener los 18 departamentos del Anexo B"
        )
    if {int(row["volumen_ml"]) for row in catalogs["presentaciones.csv"]} != {
        187,
        375,
        750,
        1500,
        3000,
    }:
        raise ValueError("presentaciones.csv no coincide con el Anexo B")
    if {row["nombre"] for row in catalogs["tipos_vino.csv"]} != {
        "tinto",
        "blanco",
        "rosado",
        "espumante",
    }:
        raise ValueError("tipos_vino.csv no coincide con el Anexo B")
    years = [int(row["anio"]) for row in catalogs["campanas.csv"]]
    if years != list(range(max(years) - 4, max(years) + 1)):
        raise ValueError("campanas.csv debe contener cinco campañas consecutivas")
    return catalogs


def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def batches(rows: Iterable[Sequence], size: int = 1000):
    batch = []
    for row in rows:
        batch.append(row)
        if len(batch) == size:
            yield batch
            batch = []
    if batch:
        yield batch


def insert_rows(cur, table: str, columns: Sequence[str], rows: Iterable[Sequence]):
    query = sql.SQL("INSERT INTO {} ({}) VALUES %s").format(
        sql.Identifier(table),
        sql.SQL(", ").join(sql.Identifier(column) for column in columns),
    )
    for batch in batches(rows):
        execute_values(cur, query.as_string(cur.connection), batch, page_size=1000)


def set_sequence(cur, table: str, column: str):
    cur.execute(
        "SELECT setval(pg_get_serial_sequence(%s, %s), "
        "COALESCE((SELECT MAX({}) FROM {}), 1), true)".format(
            sql.Identifier(column).as_string(cur.connection),
            sql.Identifier(table).as_string(cur.connection),
        ),
        (table, column),
    )


def reset_database(cur):
    cur.execute(
        sql.SQL("TRUNCATE {} RESTART IDENTITY CASCADE").format(
            sql.SQL(", ").join(sql.Identifier(table) for table in ALL_TABLES)
        )
    )


def cuit(prefix: int, number: int) -> str:
    return f"{prefix:02d}{number:09d}"


def campaign_date(year: int, offset: int) -> date:
    return date(year, 2 + (offset % 3), 1 + (offset % 26))


def generate_reference_data(cur, catalogs):
    departments = catalogs["departamentos.csv"]
    cepas = catalogs["cepas.csv"]
    maridajes = catalogs["maridajes.csv"]
    wine_types = [row["nombre"] for row in catalogs["tipos_vino.csv"]]
    presentations = [int(row["volumen_ml"]) for row in catalogs["presentaciones.csv"]]
    campaigns = [int(row["anio"]) for row in catalogs["campanas.csv"]]

    insert_rows(cur, "provincia", ("id_provincia", "nombre"), [(1, "Mendoza")])
    insert_rows(
        cur,
        "departamento",
        ("id_departamento", "id_provincia", "nombre"),
        [(index, 1, row["nombre"]) for index, row in enumerate(departments, 1)],
    )

    employee_rows = [
        (
            cuit(20, 38100000 + index),
            index,
            f"Encargado {index}",
            date(2018 + index % 5, 1, 10),
            350000 + index * 10000,
        )
        for index in range(1, 19)
    ]
    locality_rows = [
        (5600 + index, departments[index - 1]["nombre"], 1, row[0])
        for index, row in enumerate(employee_rows, 1)
    ]
    insert_rows(
        cur,
        "localidad",
        ("cp", "nombre", "id_provincia", "cuit_encargado_regional"),
        locality_rows,
    )
    insert_rows(
        cur,
        "sala_venta",
        ("id_sala", "cp_localidad", "calle", "numero", "dia_cierre"),
        [
            (index, 5600 + index, f"Av. San Martín {index}", 100 + index, "Domingo")
            for index in range(1, 19)
        ],
    )
    insert_rows(
        cur,
        "empleado",
        ("cuit", "id_sala", "nombre", "fecha_ingreso", "salario"),
        employee_rows,
    )

    transportistas = [
        (
            index,
            fake.company(),
            cuit(30, 70000000 + index),
            f"contacto{index}@atuel.test",
            f"260400{index:04d}",
            fake.address().replace("\n", ", "),
        )
        for index in range(1, 21)
    ]
    insert_rows(
        cur,
        "transportista",
        ("cod_transportista", "razon_social", "cuit", "email", "telefono", "domicilio"),
        transportistas,
    )
    insert_rows(
        cur,
        "transportista_cubre_localidad",
        ("cod_transportista", "cp_localidad"),
        [(transportista[0], 5600 + ((transportista[0] + offset) % 18) + 1)
         for transportista in transportistas for offset in range(3)],
    )

    insert_rows(
        cur,
        "cepa",
        ("id_cepa", "nombre", "tipo"),
        [(index, row["nombre"], row["tipo"]) for index, row in enumerate(cepas, 1)],
    )
    insert_rows(
        cur,
        "maridaje",
        ("id_maridaje", "nombre", "temp_servicio"),
        [
            (index, row["nombre"], int(row["temp_servicio"]))
            for index, row in enumerate(maridajes, 1)
        ],
    )

    finca_rows = [
        (index, ((index - 1) % 18) + 1, f"Finca Atuel {index}", 20 + index / 2)
        for index in range(1, 61)
    ]
    insert_rows(
        cur,
        "finca",
        ("id_finca", "id_departamento", "nombre", "superficie"),
        finca_rows,
    )
    parcela_rows = [
        (finca_id, parcela_id, ((finca_id + parcela_id - 2) % 12) + 1,
         2.5 + parcela_id / 10, 2010 + parcela_id % 8)
        for finca_id in range(1, 61)
        for parcela_id in range(1, 6)
    ]
    insert_rows(
        cur,
        "parcela",
        ("id_finca", "nro_parcela", "id_cepa", "superficie", "anio_plantacion"),
        parcela_rows,
    )
    bodega_rows = [
        (cuit(30, 50000000 + index), fake.company(), fake.address().replace("\n", ", "))
        for index in range(1, 21)
    ]
    insert_rows(
        cur,
        "bodega",
        ("cuit_bodega", "razon_social", "domicilio"),
        bodega_rows,
    )

    lotes = [
        (
            index,
            ((index - 1) % 60) + 1,
            (((index - 1) // 60) % 5) + 1,
            bodega_rows[(index - 1) % len(bodega_rows)][0],
            campaigns[((index - 1) // 300) % len(campaigns)],
            campaign_date(campaigns[((index - 1) // 300) % len(campaigns)], index),
            5000 + index * 10,
        )
        for index in range(1, 601)
    ]
    insert_rows(
        cur,
        "lote_uva",
        ("nro_lote", "id_finca", "nro_parcela", "cuit_bodega", "campania", "fecha", "kg"),
        lotes,
    )
    insert_rows(
        cur,
        "analisis_calidad",
        ("id_analisis", "nro_lote", "fecha", "brix", "ph", "acidez"),
        [
            (index, lotes[(index - 1) % len(lotes)][0],
             lotes[(index - 1) % len(lotes)][5] + timedelta(days=10),
             20 + (index % 5) / 10, 3.1 + (index % 4) / 10, 5 + index % 3)
            for index in range(1, 1201)
        ],
    )

    wine_rows = [
        (
            index,
            bodega_rows[(index - 1) % len(bodega_rows)][0],
            f"Vino Atuel {index}",
            wine_types[(index - 1) % len(wine_types)],
            campaigns[(index - 1) % len(campaigns)],
            presentations[(index - 1) % len(presentations)],
            10 + (index % 60) / 10,
            1200 + index * 7,
        )
        for index in range(1, 1001)
    ]
    insert_rows(
        cur,
        "vino",
        ("cod_vino", "cuit_bodega", "nombre", "tipo", "aniada", "volumen",
         "graduacion", "precio"),
        wine_rows,
    )
    compositions = []
    for wine_id in range(1, 1001):
        cepa_a = ((wine_id - 1) % 12) + 1
        cepa_b = (cepa_a % 12) + 1
        if wine_id % 3 == 0:
            compositions.extend([(wine_id, cepa_a, 50), (wine_id, cepa_b, 50)])
        else:
            compositions.append((wine_id, cepa_a, 100))
    insert_rows(cur, "composicion", ("cod_vino", "id_cepa", "porcentaje"), compositions)
    insert_rows(
        cur,
        "vino_maridaje",
        ("cod_vino", "id_maridaje"),
        [(wine_id, ((wine_id - 1) % 8) + 1) for wine_id in range(1, 1001)],
    )

    return {
        "campaigns": campaigns,
        "wine_rows": wine_rows,
        "employee_rows": employee_rows,
        "locality_rows": locality_rows,
        "transportistas": transportistas,
        "bodega_rows": bodega_rows,
    }


def generate_business_data(cur, reference, scale: int):
    wines = reference["wine_rows"]
    localities = reference["locality_rows"]
    transportistas = reference["transportistas"]
    bodegas = reference["bodega_rows"]

    client_count = 20_000 * scale
    client_rows = []
    client_types = {}
    for index in range(1, client_count + 1):
        tipo = ("Socio", "Distribuidor", "Exportador")[index % 3]
        descuento = {"Socio": 10, "Distribuidor": 20, "Exportador": 30}[tipo]
        client_types[index] = tipo
        client_rows.append(
            (
                index,
                localities[(index - 1) % len(localities)][0],
                f"Cliente {index}",
                "DNI",
                f"{index:08d}",
                f"Calle {index} {100 + index % 900}",
                date(2020 + index % 6, 1 + index % 12, 1 + index % 25),
                descuento,
                tipo,
            )
        )
    insert_rows(
        cur,
        "cliente",
        ("id_cliente", "cp_localidad", "nombre_razon_social", "tipo_doc", "nro_doc",
         "direccion", "fecha_alta", "descuento", "tipo_cliente"),
        client_rows,
    )
    benchmark_insert_modes(cur, client_rows[:2000])
    insert_rows(
        cur,
        "distribuidor",
        ("id_cliente", "zona_cobertura", "nro_habilitacion"),
        [
            (client_id, "Mendoza", f"HAB-{client_id:08d}")
            for client_id, tipo in client_types.items()
            if tipo == "Distribuidor"
        ],
    )
    exportador_ids = [
        client_id for client_id, tipo in client_types.items() if tipo == "Exportador"
    ]
    insert_rows(
        cur,
        "exportador",
        ("id_cliente", "pais_destino"),
        [(client_id, "Chile" if client_id % 2 else "Brasil") for client_id in exportador_ids],
    )
    insert_rows(
        cur,
        "permiso_exportacion",
        ("cod_permiso", "id_cliente", "fecha_emision", "fecha_vencimiento"),
        [
            (index, client_id, date(2025, 1, 1), date(2026, 12, 31))
            for index, client_id in enumerate(exportador_ids, 1)
        ],
    )

    wine_count = len(wines)
    stock = 10_000_000
    insert_rows(
        cur,
        "stock_deposito",
        ("cod_vino", "cantidad"),
        [(wine_id, stock) for wine_id in range(1, wine_count + 1)],
    )
    insert_rows(
        cur,
        "stock_sala",
        ("id_sala", "cod_vino", "cantidad"),
        [
            (sala_id, wine_id, stock)
            for sala_id in range(1, 19)
            for wine_id in range(1, wine_count + 1)
        ],
    )

    ingreso_count = 1_000 * scale
    insert_rows(
        cur,
        "ingreso",
        ("cod_ingreso", "cod_transportista", "cuit_bodega", "fecha", "estado"),
        [
            (
                index,
                ((index - 1) % len(transportistas)) + 1,
                bodegas[(index - 1) % len(bodegas)][0],
                datetime(2024 + index % 3, 1 + index % 12, 1 + index % 25),
                "en_confeccion",
            )
            for index in range(1, ingreso_count + 1)
        ],
    )
    insert_rows(
        cur,
        "renglon_ingreso",
        ("cod_ingreso", "cod_vino", "cantidad"),
        [
            (((index - 1) % ingreso_count) + 1,
             (((index - 1) // ingreso_count) * 5 + (index - 1) % ingreso_count)
             % wine_count + 1, 100 + index % 900)
            for index in range(1, ingreso_count * 5 + 1)
        ],
    )

    transfer_count = 1_000 * scale
    insert_rows(
        cur,
        "transferencia",
        ("nro_transferencia", "id_sala", "fecha_confeccion", "estado"),
        [
            (index, ((index - 1) % 18) + 1, date.today(), "en_confeccion")
            for index in range(1, transfer_count + 1)
        ],
    )
    insert_rows(
        cur,
        "renglon_transferencia",
        ("nro_transferencia", "cod_vino", "cantidad"),
        [
            (((index - 1) % transfer_count) + 1,
             (((index - 1) // transfer_count) * 5 + (index - 1) % transfer_count)
             % wine_count + 1, 10 + index % 90)
            for index in range(1, transfer_count * 5 + 1)
        ],
    )

    receipt_count = 150_000 * scale
    line_target = 500_000 * scale
    receipt_rows = []
    line_rows = []
    extra_lines = line_target - (3 * receipt_count)
    for receipt_id in range(1, receipt_count + 1):
        client_id = ((receipt_id - 1) % client_count) + 1
        sala_id = ((receipt_id - 1) % 18) + 1
        line_count = 4 if receipt_id <= extra_lines else 3
        gross = 0
        discount_total = 0
        subtotal = 0
        for offset in range(line_count):
            wine_id = ((receipt_id * 4 + offset) % wine_count) + 1
            quantity = 1 + ((receipt_id + offset) % 5)
            price = float(wines[wine_id - 1][7])
            gross_line = quantity * price
            discount = round(gross_line * {"Socio": 0.10, "Distribuidor": 0.20,
                                           "Exportador": 0.30}[client_types[client_id]], 2)
            net = round(gross_line - discount, 2)
            line_rows.append(
                (receipt_id, wine_id, quantity, price, discount, net)
            )
            gross += gross_line
            discount_total += discount
            subtotal += net
        receipt_rows.append(
            (
                receipt_id,
                client_id,
                sala_id,
                datetime(2025 + receipt_id % 2, 1 + receipt_id % 12,
                         1 + receipt_id % 25, 12, 0),
                round(gross, 2),
                round(discount_total, 2),
                round(subtotal, 2),
            )
        )
        if len(receipt_rows) >= 5000:
            insert_rows(
                cur,
                "comprobante",
                ("nro_comprobante", "id_cliente", "id_sala", "fecha", "subtotal",
                 "descuento", "total"),
                receipt_rows,
            )
            receipt_rows.clear()
            insert_rows(
                cur,
                "renglon_comprobante",
                ("nro_comprobante", "cod_vino", "cantidad", "precio_unitario",
                 "descuento", "subtotal"),
                line_rows,
            )
            line_rows.clear()
    if receipt_rows:
        insert_rows(
            cur,
            "comprobante",
            ("nro_comprobante", "id_cliente", "id_sala", "fecha", "subtotal",
             "descuento", "total"),
            receipt_rows,
        )
        insert_rows(
            cur,
            "renglon_comprobante",
            ("nro_comprobante", "cod_vino", "cantidad", "precio_unitario",
             "descuento", "subtotal"),
            line_rows,
        )

    insert_rows(
        cur,
        "auditoria_precio",
        ("cod_vino", "precio_anterior", "precio_nuevo", "fecha_hora", "usuario"),
        [(1, wines[0][7], wines[0][7] + 100, datetime.now(), "seed")],
    )


def benchmark_insert_modes(cur, rows):
    """Mide inserción fila a fila y por lotes sin conservar datos de prueba."""
    cur.execute(
        """
        CREATE TEMP TABLE seed_benchmark_cliente (
            id_cliente INTEGER,
            cp_localidad INTEGER,
            nombre_razon_social VARCHAR(150),
            tipo_doc VARCHAR(20),
            nro_doc VARCHAR(50),
            direccion VARCHAR(200),
            fecha_alta DATE,
            descuento NUMERIC(5,2),
            tipo_cliente VARCHAR(50)
        ) ON COMMIT DROP
        """
    )
    columns = (
        "id_cliente", "cp_localidad", "nombre_razon_social", "tipo_doc",
        "nro_doc", "direccion", "fecha_alta", "descuento", "tipo_cliente"
    )
    values = sql.SQL(", ").join(sql.Identifier(column) for column in columns)
    query = sql.SQL("INSERT INTO seed_benchmark_cliente ({}) VALUES ({})").format(
        values, sql.SQL(", ").join(sql.Placeholder() for _ in columns)
    ).as_string(cur.connection)
    started = time.perf_counter()
    for row in rows:
        cur.execute(query, row[0:9])
    row_by_row_seconds = time.perf_counter() - started
    cur.execute("TRUNCATE seed_benchmark_cliente")
    started = time.perf_counter()
    execute_values(
        cur,
        "INSERT INTO seed_benchmark_cliente "
        "(id_cliente, cp_localidad, nombre_razon_social, tipo_doc, nro_doc, "
        "direccion, fecha_alta, descuento, tipo_cliente) VALUES %s",
        [row[0:9] for row in rows],
    )
    batch_seconds = time.perf_counter() - started
    print(
        "Comparativa de carga (2000 clientes): "
        f"fila a fila={row_by_row_seconds:.4f} s, "
        f"batch execute_values={batch_seconds:.4f} s"
    )


def validate_database(cur):
    cur.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' "
        "ORDER BY table_name"
    )
    tables = [row[0] for row in cur.fetchall()]
    counts = {}
    for table in tables:
        cur.execute(sql.SQL("SELECT COUNT(*) FROM {}").format(sql.Identifier(table)))
        count = cur.fetchone()[0]
        counts[table] = count
        if count == 0:
            raise RuntimeError(f"la tabla {table} quedó vacía")
    print("Conteo por tabla:")
    for table, count in counts.items():
        print(f"  {table}: {count}")

    cur.execute(
        "SELECT COUNT(*) FROM stock_sala WHERE cantidad < 0 UNION ALL "
        "SELECT COUNT(*) FROM stock_deposito WHERE cantidad < 0"
    )
    if any(row[0] for row in cur.fetchall()):
        raise RuntimeError("se detectó stock negativo")

    orphan_checks = {
        "renglones_comprobante": """
            SELECT COUNT(*) FROM renglon_comprobante r
            LEFT JOIN comprobante c USING (nro_comprobante)
            WHERE c.nro_comprobante IS NULL
        """,
        "renglones_ingreso": """
            SELECT COUNT(*) FROM renglon_ingreso r
            LEFT JOIN ingreso i USING (cod_ingreso)
            WHERE i.cod_ingreso IS NULL
        """,
        "renglones_transferencia": """
            SELECT COUNT(*) FROM renglon_transferencia r
            LEFT JOIN transferencia t USING (nro_transferencia)
            WHERE t.nro_transferencia IS NULL
        """,
    }
    for name, query in orphan_checks.items():
        cur.execute(query)
        if cur.fetchone()[0] != 0:
            raise RuntimeError(f"se detectaron filas huérfanas en {name}")

    cur.execute(
        "SELECT COUNT(*) FROM composicion GROUP BY cod_vino "
        "HAVING SUM(porcentaje) <> 100 OR SUM(porcentaje) IS NULL LIMIT 1"
    )
    if cur.fetchone() is not None:
        raise RuntimeError("se detectó una composición que no suma 100")
    cur.execute(
        """
        SELECT COUNT(*)
        FROM comprobante c
        WHERE c.total <> (
            SELECT COALESCE(SUM(r.subtotal), 0)
            FROM renglon_comprobante r
            WHERE r.nro_comprobante = c.nro_comprobante
        )
        """
    )
    if cur.fetchone()[0] != 0:
        raise RuntimeError("se detectaron comprobantes con total inconsistente")


def create_dump():
    output = ROOT / "dump_completo.sql.gz"
    if shutil.which("pg_dump"):
        command = [
            "pg_dump",
            "--dbname",
            DB_CONFIG["dbname"],
            "--host",
            DB_CONFIG["host"],
            "--port",
            str(DB_CONFIG["port"]),
            "--username",
            DB_CONFIG["user"],
            "--format",
            "plain",
            "--file",
            "-",
        ]
    else:
        command = [
            "docker",
            "exec",
            "postgresql",
            "pg_dump",
            "--dbname",
            DB_CONFIG["dbname"],
            "--username",
            DB_CONFIG["user"],
            "--format",
            "plain",
        ]
    environment = os.environ.copy()
    if DB_CONFIG["password"]:
        environment["PGPASSWORD"] = DB_CONFIG["password"]
    import gzip
    dump = subprocess.run(command, env=environment, check=True, stdout=subprocess.PIPE)
    with gzip.open(output, "wb") as compressed:
        compressed.write(dump.stdout)
    print(f"Volcado generado: {output}")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reset", action="store_true",
                        help="vacía las tablas antes de cargar; requiere PostgreSQL")
    parser.add_argument("--validate-only", action="store_true",
                        help="valida CSV y nombres sin conectarse a PostgreSQL")
    parser.add_argument("--scale", type=int, default=1,
                        help="multiplicador de tablas masivas (por defecto: 1)")
    parser.add_argument("--dump", action="store_true",
                        help="genera dump_completo.sql.gz al finalizar")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.scale < 1:
        raise ValueError("--scale debe ser mayor o igual que 1")
    catalogs = load_catalogs()
    if args.validate_only:
        print("CSV y catálogos válidos para el esquema de Bodegas del Atuel.")
        return

    connection = get_connection()
    try:
        with connection:
            with connection.cursor() as cur:
                if args.reset:
                    reset_database(cur)
                started_at = time.perf_counter()
                reference = generate_reference_data(cur, catalogs)
                generate_business_data(cur, reference, args.scale)
                validate_database(cur)
                for table, column in (
                    ("transportista", "cod_transportista"),
                    ("cepa", "id_cepa"),
                    ("maridaje", "id_maridaje"),
                    ("finca", "id_finca"),
                    ("lote_uva", "nro_lote"),
                    ("analisis_calidad", "id_analisis"),
                    ("vino", "cod_vino"),
                    ("cliente", "id_cliente"),
                    ("permiso_exportacion", "cod_permiso"),
                    ("ingreso", "cod_ingreso"),
                    ("transferencia", "nro_transferencia"),
                    ("comprobante", "nro_comprobante"),
                    ("auditoria_precio", "id_auditoria"),
                ):
                    set_sequence(cur, table, column)
                elapsed = time.perf_counter() - started_at
        print("Carga masiva completada y validada.")
        print(f"Tiempo total de carga por lotes: {elapsed:.2f} s")
        if args.dump:
            create_dump()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    main()
