# Carga masiva de datos

Esta carpeta contiene los catálogos CSV y el script `seed.py` para cargar datos
reproducibles en la base PostgreSQL de Bodegas del Atuel.

## Requisitos

- PostgreSQL con el esquema y las migraciones del proyecto aplicados.
- Python 3.
- Dependencias Python:

```bash
pip install Faker psycopg2-binary
```

La conexión puede configurarse mediante estas variables de entorno:

| Variable | Valor predeterminado |
|---|---|
| `BDA_DB_NAME` | `bodega_del_atuel` |
| `BDA_DB_USER` | `postgresql` |
| `BDA_DB_PASSWORD` | `seed_local_password` |
| `BDA_DB_HOST` | `localhost` |
| `BDA_DB_PORT` | `5432` |

## Ejecución

Validar solamente los CSV y sus nombres de columnas:

```bash
python3 db/seed/seed.py --validate-only
```

Ejecutar la carga conservando los datos existentes:

```bash
python3 db/seed/seed.py
```

Vaciar las tablas y ejecutar una carga reproducible desde cero:

```bash
python3 db/seed/seed.py --reset
```

Generar también el dump comprimido:

```bash
python3 db/seed/seed.py --reset --dump
```

El archivo generado es `db/seed/dump_completo.sql.gz`.

## Etapa 3, punto 5: triggers durante la carga histórica

### Decisión

La carga se ejecuta con los triggers activos. El script **no** utiliza
`ALTER TABLE ... DISABLE TRIGGER` ni `ALTER TABLE ... ENABLE TRIGGER`.

Esta decisión permite que las reglas de negocio se apliquen durante la carga,
en lugar de cargar datos potencialmente inválidos y validarlos después. Por
ejemplo, se mantienen activas las validaciones relacionadas con composición de
vinos, estados de movimientos, stock y cálculo de comprobantes.

### Riesgos y mitigaciones

- **Mayor tiempo de carga:** los triggers agregan validaciones y operaciones
  adicionales. Se mitiga usando inserciones por lotes con `execute_values`.
- **Datos históricos incompatibles:** una fila que viole una regla aborta la
  transacción. Esto evita dejar una carga parcialmente válida y obliga a
  corregir el dato de origen.
- **Carga no repetible sobre datos existentes:** para una carga desde cero se
  debe utilizar `--reset`, que ejecuta `TRUNCATE ... RESTART IDENTITY CASCADE`.
- **Consistencia posterior:** al finalizar se ejecutan consultas de control
  sobre conteos, filas huérfanas, stock, composiciones y totales.

## Etapa 3, punto 6: carga por lotes y medición

El script utiliza `execute_values` en lotes de hasta 1.000 filas para las
cargas masivas. Además, mide 2.000 inserciones de clientes en una tabla
temporal:

1. Inserción fila por fila con `cursor.execute`.
2. Inserción por lotes con `execute_values`.

La comparación se imprime al ejecutar el script. En la ejecución verificada:

| Método | Tiempo |
|---|---:|
| Fila por fila, 2.000 registros | 0,3166 s |
| `execute_values`, 2.000 registros | 0,1125 s |

El tiempo total observado de la carga con los triggers activos fue de
aproximadamente 101,59 segundos.

## Etapa 3, punto 7: consultas de control

Al finalizar, `seed.py` verifica:

- Conteo de filas de todas las tablas públicas.
- Que ninguna tabla quede vacía.
- Stock negativo en `stock_sala` y `stock_deposito`.
- Filas huérfanas en renglones de comprobantes, ingresos y transferencias.
- Composiciones cuya suma de porcentajes no sea 100.
- Comprobantes cuyo total no coincida con la suma de sus renglones.

En la ejecución verificada, todos los controles devolvieron cero
inconsistencias.

## Etapa 3, punto 8: volcado restaurable

La opción `--dump` ejecuta `pg_dump` y comprime su salida en:

```text
db/seed/dump_completo.sql.gz
```

Si `pg_dump` no está instalado en el sistema local, el script utiliza
`docker exec postgresql pg_dump`. El archivo generado fue validado con:

```bash
gzip -t db/seed/dump_completo.sql.gz
```

Para restaurarlo en una base PostgreSQL vacía:

```bash
gzip -dc db/seed/dump_completo.sql.gz | \
  psql -U postgresql -d bodega_del_atuel
```
