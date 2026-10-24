from collections.abc import Sequence
from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def top_vinos(connection: Connection) -> Sequence[dict[str, Any]]:
    return _fetch_all(
        connection,
        """
        SELECT v.cod_vino, v.nombre,
               COALESCE(SUM(r.cantidad), 0) AS botellas_vendidas
          FROM vino v
          LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
         GROUP BY v.cod_vino, v.nombre
         ORDER BY botellas_vendidas DESC, v.cod_vino
         LIMIT 10
        """,
    )


def ventas_por_sala(connection: Connection) -> Sequence[dict[str, Any]]:
    return _fetch_all(
        connection,
        """
        SELECT c.id_sala, SUM(c.total) AS monto_total_ventas
          FROM comprobante c
         WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
         GROUP BY c.id_sala
         ORDER BY monto_total_ventas DESC, c.id_sala
        """,
    )


def vinos_sin_stock(connection: Connection, id_sala: int) -> Sequence[dict[str, Any]]:
    return _fetch_all(
        connection,
        """
        SELECT v.cod_vino, v.nombre,
               COALESCE(ss.cantidad, 0) AS stock_sala,
               COALESCE(sd.cantidad, 0) AS stock_deposito
          FROM vino v
          LEFT JOIN stock_sala ss
            ON ss.cod_vino = v.cod_vino AND ss.id_sala = %s
          JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
         WHERE COALESCE(ss.cantidad, 0) = 0
           AND sd.cantidad > 0
         ORDER BY v.cod_vino
        """,
        (id_sala,),
    )


def transportista_activo(connection: Connection) -> Sequence[dict[str, Any]]:
    return _fetch_all(
        connection,
        """
        SELECT t.cod_transportista, t.razon_social,
               COUNT(i.cod_ingreso) AS ingresos_trasladados
          FROM transportista t
          JOIN ingreso i ON i.cod_transportista = t.cod_transportista
         WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
         GROUP BY t.cod_transportista, t.razon_social
         ORDER BY ingresos_trasladados DESC, t.cod_transportista
         LIMIT 1
        """,
    )


def trazabilidad(connection: Connection, cod_vino: int) -> dict[str, Any] | None:
    query = """
        SELECT st.codigo_vino,
               st.nombre_vino,
               st.tipo_vino,
               st.anio_cosecha_vino,
               st.razon_social_bodega,
               STRING_AGG(
                   DISTINCT (ce.nombre || ' (' || co.porcentaje || '%%' || ')'),
                   ', '
                   ORDER BY (ce.nombre || ' (' || co.porcentaje || '%%' || ')')
               ) AS cepas,
               STRING_AGG(DISTINCT m.nombre, ', ' ORDER BY m.nombre) AS maridajes,
               st.cantidad_stock_total_general AS stock_total
          FROM stock_total_vino st
          JOIN composicion co ON co.cod_vino = st.codigo_vino
          JOIN cepa ce ON ce.id_cepa = co.id_cepa
          LEFT JOIN vino_maridaje vm ON vm.cod_vino = st.codigo_vino
          LEFT JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
         WHERE st.codigo_vino = %s
         GROUP BY st.codigo_vino, st.nombre_vino, st.tipo_vino,
                  st.anio_cosecha_vino, st.razon_social_bodega,
                  st.cantidad_stock_total_general
    """
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(query, (cod_vino,))
        return cursor.fetchone()


def _fetch_all(
    connection: Connection,
    query: str,
    parameters: tuple[Any, ...] = (),
) -> Sequence[dict[str, Any]]:
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(query, parameters)
        return cursor.fetchall()
