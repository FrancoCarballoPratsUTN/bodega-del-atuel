-- Etapa 5 - Consultas SELECT S1-S12
-- Los períodos móviles se calculan con CURRENT_DATE, nunca con fechas fijas.

-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas
-- en toda la red de salas.
-- Estrategia: agregación de renglones y orden descendente.
SELECT v.cod_vino,
       v.nombre,
       COALESCE(SUM(r.cantidad), 0) AS botellas_vendidas
  FROM vino v
  LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
 GROUP BY v.cod_vino, v.nombre
 ORDER BY botellas_vendidas DESC, v.cod_vino
 LIMIT 10;

-- S2. Códigos y nombres de vinos vendidos en todas las salas.
-- Estrategia: división relacional con NOT EXISTS correlacionado.
SELECT v.cod_vino, v.nombre
  FROM vino v
 WHERE NOT EXISTS (
     SELECT 1
       FROM sala_venta s
      WHERE NOT EXISTS (
          SELECT 1
            FROM comprobante c
            JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
           WHERE c.id_sala = s.id_sala
             AND r.cod_vino = v.cod_vino
      )
 )
 ORDER BY v.cod_vino;

-- S3. Cantidad de clientes de cada tipo que compraron en la sala 1
-- durante la última semana.
-- El intervalo se calcula desde CURRENT_DATE.
SELECT c.tipo_cliente,
       COUNT(DISTINCT c.id_cliente) AS cantidad_clientes
  FROM comprobante co
  JOIN cliente c ON c.id_cliente = co.id_cliente
 WHERE co.id_sala = 1
   AND co.fecha >= CURRENT_DATE - INTERVAL '7 days'
 GROUP BY c.tipo_cliente
 ORDER BY c.tipo_cliente;

-- S4. Top 5 de salas que solicitaron más unidades del vino 1 por
-- transferencias confeccionadas en los últimos 15 días.
SELECT tr.id_sala,
       SUM(rt.cantidad) AS botellas_solicitadas
  FROM transferencia tr
  JOIN renglon_transferencia rt
    ON rt.nro_transferencia = tr.nro_transferencia
 WHERE rt.cod_vino = 1
   AND tr.fecha_confeccion >= CURRENT_DATE - INTERVAL '15 days'
 GROUP BY tr.id_sala
 ORDER BY botellas_solicitadas DESC, tr.id_sala
 LIMIT 5;

-- S5. Salas con menor cantidad de transferencias pendientes.
-- Se cuentan también salas sin transferencias mediante LEFT JOIN.
SELECT s.id_sala,
       COUNT(tr.nro_transferencia) AS transferencias_pendientes
  FROM sala_venta s
  LEFT JOIN transferencia tr
    ON tr.id_sala = s.id_sala
   AND tr.estado <> 'procesado'
 GROUP BY s.id_sala
 ORDER BY transferencias_pendientes, s.id_sala;

-- S6. Para la sala 1, vinos sin stock en sala pero con stock en el depósito.
SELECT v.cod_vino,
       v.nombre,
       COALESCE(ss.cantidad, 0) AS stock_sala,
       COALESCE(sd.cantidad, 0) AS stock_deposito
  FROM vino v
  LEFT JOIN stock_sala ss
    ON ss.cod_vino = v.cod_vino
   AND ss.id_sala = 1
  JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
 WHERE COALESCE(ss.cantidad, 0) = 0
   AND sd.cantidad > 0
 ORDER BY v.cod_vino;

-- S7. Empresa de transporte con mayor actividad en el último mes.
-- En este esquema el transportista participa en ingresos trasladados; se
-- contabilizan esos ingresos dentro del período móvil.
SELECT t.cod_transportista,
       t.razon_social,
       COUNT(i.cod_ingreso) AS ingresos_trasladados
  FROM transportista t
  JOIN ingreso i ON i.cod_transportista = t.cod_transportista
 WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
 GROUP BY t.cod_transportista, t.razon_social
 ORDER BY ingresos_trasladados DESC, t.cod_transportista
 LIMIT 1;

-- S8. Monto total de ventas por sala durante el último trimestre.
SELECT c.id_sala,
       SUM(c.total) AS monto_total_ventas
  FROM comprobante c
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY c.id_sala
 ORDER BY monto_total_ventas DESC, c.id_sala;

-- S9. Ficha de un vino: composición, bodega, maridajes y stock total.
-- Herramientas: vista stock_total_vino, joins y agregación.
EXPLAIN (ANALYZE, BUFFERS)
SELECT st.codigo_vino,
       st.nombre_vino,
       st.tipo_vino,
       st.anio_cosecha_vino,
       st.razon_social_bodega,
       STRING_AGG(DISTINCT (ce.nombre || ' (' || co.porcentaje || '%)'), ', '
                  ORDER BY (ce.nombre || ' (' || co.porcentaje || '%)')) AS cepas,
       STRING_AGG(DISTINCT m.nombre, ', ' ORDER BY m.nombre) AS maridajes,
       st.cantidad_stock_total_general AS stock_total
  FROM stock_total_vino st
  JOIN composicion co ON co.cod_vino = st.codigo_vino
  JOIN cepa ce ON ce.id_cepa = co.id_cepa
  LEFT JOIN vino_maridaje vm ON vm.cod_vino = st.codigo_vino
  LEFT JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
 WHERE st.codigo_vino = 1
 GROUP BY st.codigo_vino, st.nombre_vino, st.tipo_vino,
          st.anio_cosecha_vino, st.razon_social_bodega,
          st.cantidad_stock_total_general;

SELECT st.codigo_vino,
       st.nombre_vino,
       st.tipo_vino,
       st.anio_cosecha_vino,
       st.razon_social_bodega,
       STRING_AGG(DISTINCT (ce.nombre || ' (' || co.porcentaje || '%)'), ', '
                  ORDER BY (ce.nombre || ' (' || co.porcentaje || '%)')) AS cepas,
       STRING_AGG(DISTINCT m.nombre, ', ' ORDER BY m.nombre) AS maridajes,
       st.cantidad_stock_total_general AS stock_total
  FROM stock_total_vino st
  JOIN composicion co ON co.cod_vino = st.codigo_vino
  JOIN cepa ce ON ce.id_cepa = co.id_cepa
  LEFT JOIN vino_maridaje vm ON vm.cod_vino = st.codigo_vino
  LEFT JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
 WHERE st.codigo_vino = 1
 GROUP BY st.codigo_vino, st.nombre_vino, st.tipo_vino,
          st.anio_cosecha_vino, st.razon_social_bodega,
          st.cantidad_stock_total_general;

-- S10. Rendimiento en kg/ha por parcela y campaña, identificando las parcelas
-- que rinden menos que el promedio de su finca.
-- Herramientas: CTE para el rendimiento y subconsulta correlacionada para el
-- promedio de la finca.
EXPLAIN (ANALYZE, BUFFERS)
WITH rendimiento AS (
    SELECT l.id_finca,
           l.nro_parcela,
           l.campania,
           SUM(l.kg) AS kg_cosechados,
           p.superficie,
           SUM(l.kg) / NULLIF(p.superficie, 0) AS kg_por_hectarea
      FROM lote_uva l
      JOIN parcela p
        ON p.id_finca = l.id_finca
       AND p.nro_parcela = l.nro_parcela
     GROUP BY l.id_finca, l.nro_parcela, l.campania, p.superficie
)
SELECT r.*,
       (
           SELECT AVG(r2.kg_por_hectarea)
             FROM rendimiento r2
            WHERE r2.id_finca = r.id_finca
       ) AS promedio_finca,
       r.kg_por_hectarea < (
           SELECT AVG(r3.kg_por_hectarea)
             FROM rendimiento r3
            WHERE r3.id_finca = r.id_finca
       ) AS rinde_menos_que_promedio
  FROM rendimiento r
 ORDER BY r.id_finca, r.nro_parcela, r.campania;

WITH rendimiento AS (
    SELECT l.id_finca,
           l.nro_parcela,
           l.campania,
           SUM(l.kg) AS kg_cosechados,
           p.superficie,
           SUM(l.kg) / NULLIF(p.superficie, 0) AS kg_por_hectarea
      FROM lote_uva l
      JOIN parcela p
        ON p.id_finca = l.id_finca
       AND p.nro_parcela = l.nro_parcela
     GROUP BY l.id_finca, l.nro_parcela, l.campania, p.superficie
)
SELECT r.*,
       (
           SELECT AVG(r2.kg_por_hectarea)
             FROM rendimiento r2
            WHERE r2.id_finca = r.id_finca
       ) AS promedio_finca,
       r.kg_por_hectarea < (
           SELECT AVG(r3.kg_por_hectarea)
             FROM rendimiento r3
            WHERE r3.id_finca = r.id_finca
       ) AS rinde_menos_que_promedio
  FROM rendimiento r
 ORDER BY r.id_finca, r.nro_parcela, r.campania;

-- S11. Ranking de vinos dentro de cada sala por botellas vendidas y ventas
-- acumuladas mensuales por sala.
-- Herramientas: RANK() OVER (PARTITION BY ...) y suma acumulada con ventana.
EXPLAIN (ANALYZE, BUFFERS)
WITH ventas_mensuales AS (
    SELECT c.id_sala,
           DATE_TRUNC('month', c.fecha)::DATE AS mes,
           r.cod_vino,
           SUM(r.cantidad) AS botellas_vendidas,
           SUM(r.subtotal) AS monto_vendido
      FROM comprobante c
      JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
     GROUP BY c.id_sala, DATE_TRUNC('month', c.fecha)::DATE, r.cod_vino
),
ranking AS (
    SELECT vm.*,
           RANK() OVER (
               PARTITION BY vm.id_sala
               ORDER BY vm.botellas_vendidas DESC
           ) AS ranking_vino_sala,
           SUM(vm.monto_vendido) OVER (
               PARTITION BY vm.id_sala, vm.mes
               ORDER BY vm.cod_vino
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS ventas_acumuladas_mes_sala
      FROM ventas_mensuales vm
)
SELECT r.id_sala,
       r.mes,
       r.cod_vino,
       v.nombre,
       r.botellas_vendidas,
       r.ranking_vino_sala,
       r.monto_vendido,
       r.ventas_acumuladas_mes_sala
  FROM ranking r
  JOIN vino v ON v.cod_vino = r.cod_vino
 ORDER BY r.id_sala, r.mes, r.ranking_vino_sala, r.cod_vino;

WITH ventas_mensuales AS (
    SELECT c.id_sala,
           DATE_TRUNC('month', c.fecha)::DATE AS mes,
           r.cod_vino,
           SUM(r.cantidad) AS botellas_vendidas,
           SUM(r.subtotal) AS monto_vendido
      FROM comprobante c
      JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
     GROUP BY c.id_sala, DATE_TRUNC('month', c.fecha)::DATE, r.cod_vino
),
ranking AS (
    SELECT vm.*,
           RANK() OVER (
               PARTITION BY vm.id_sala
               ORDER BY vm.botellas_vendidas DESC
           ) AS ranking_vino_sala,
           SUM(vm.monto_vendido) OVER (
               PARTITION BY vm.id_sala, vm.mes
               ORDER BY vm.cod_vino
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS ventas_acumuladas_mes_sala
      FROM ventas_mensuales vm
)
SELECT r.id_sala,
       r.mes,
       r.cod_vino,
       v.nombre,
       r.botellas_vendidas,
       r.ranking_vino_sala,
       r.monto_vendido,
       r.ventas_acumuladas_mes_sala
  FROM ranking r
  JOIN vino v ON v.cod_vino = r.cod_vino
 ORDER BY r.id_sala, r.mes, r.ranking_vino_sala, r.cod_vino;

-- S12. Clientes que compraron todos los vinos de una bodega determinada y
-- clientes que nunca compraron ningún vino tinto.
-- Herramientas: NOT EXISTS para división y anti-join para la segunda parte.
EXPLAIN (ANALYZE, BUFFERS)
WITH bodega_objetivo AS (
    SELECT cuit_bodega
      FROM bodega
     ORDER BY cuit_bodega
     LIMIT 1
),
clientes_todos AS (
    SELECT c.id_cliente, c.nombre_razon_social
      FROM cliente c
     WHERE NOT EXISTS (
         SELECT 1
           FROM vino v
          WHERE v.cuit_bodega = (SELECT cuit_bodega FROM bodega_objetivo)
            AND NOT EXISTS (
                SELECT 1
                  FROM comprobante co
                  JOIN renglon_comprobante rc
                    ON rc.nro_comprobante = co.nro_comprobante
                 WHERE co.id_cliente = c.id_cliente
                   AND rc.cod_vino = v.cod_vino
            )
     )
)
SELECT 'compraron_todos_los_vinos_de_bodega' AS resultado,
       id_cliente,
       nombre_razon_social
  FROM clientes_todos
UNION ALL
SELECT 'nunca_compraron_vino_tinto' AS resultado,
       c.id_cliente,
       c.nombre_razon_social
  FROM cliente c
 WHERE NOT EXISTS (
     SELECT 1
       FROM comprobante co
       JOIN renglon_comprobante rc ON rc.nro_comprobante = co.nro_comprobante
       JOIN vino v ON v.cod_vino = rc.cod_vino
      WHERE co.id_cliente = c.id_cliente
        AND lower(v.tipo) = 'tinto'
 );

WITH bodega_objetivo AS (
    SELECT cuit_bodega
      FROM bodega
     ORDER BY cuit_bodega
     LIMIT 1
),
clientes_todos AS (
    SELECT c.id_cliente, c.nombre_razon_social
      FROM cliente c
     WHERE NOT EXISTS (
         SELECT 1
           FROM vino v
          WHERE v.cuit_bodega = (SELECT cuit_bodega FROM bodega_objetivo)
            AND NOT EXISTS (
                SELECT 1
                  FROM comprobante co
                  JOIN renglon_comprobante rc
                    ON rc.nro_comprobante = co.nro_comprobante
                 WHERE co.id_cliente = c.id_cliente
                   AND rc.cod_vino = v.cod_vino
            )
     )
)
SELECT 'compraron_todos_los_vinos_de_bodega' AS resultado,
       id_cliente,
       nombre_razon_social
  FROM clientes_todos
UNION ALL
SELECT 'nunca_compraron_vino_tinto' AS resultado,
       c.id_cliente,
       c.nombre_razon_social
  FROM cliente c
 WHERE NOT EXISTS (
     SELECT 1
       FROM comprobante co
       JOIN renglon_comprobante rc ON rc.nro_comprobante = co.nro_comprobante
       JOIN vino v ON v.cod_vino = rc.cod_vino
      WHERE co.id_cliente = c.id_cliente
        AND lower(v.tipo) = 'tinto'
 );
