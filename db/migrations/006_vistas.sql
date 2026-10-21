--Vista: Stock total por vino
CREATE OR REPLACE VIEW stock_total_vino AS
SELECT 
    tabla_vino.cod_vino AS codigo_vino,
    tabla_vino.nombre AS nombre_vino,
    tabla_vino.aniada AS anio_cosecha_vino,
    tabla_vino.volumen AS volumen_contenido_vino,
    COALESCE(tabla_stock_deposito.cantidad, 0) AS cantidad_stock_deposito_central,
    COALESCE(SUM(tabla_stock_sala.cantidad), 0) AS cantidad_stock_todas_las_salas,
    COALESCE(tabla_stock_deposito.cantidad, 0) + COALESCE(SUM(tabla_stock_sala.cantidad), 0) AS cantidad_stock_total_general
FROM 
    vino AS tabla_vino
LEFT JOIN stock_deposito AS tabla_stock_deposito 
    ON tabla_vino.cod_vino = tabla_stock_deposito.cod_vino
LEFT JOIN stock_sala AS tabla_stock_sala 
    ON tabla_vino.cod_vino = tabla_stock_sala.cod_vino
GROUP BY 
    tabla_vino.cod_vino, 
    tabla_vino.nombre, 
    tabla_vino.aniada, 
    tabla_vino.volumen, 
    tabla_stock_deposito.cantidad;


--Vista Materializada: Ventas mensuales por sala
CREATE MATERIALIZED VIEW ventas_mensuales_sala AS
SELECT 
    tabla_sala_venta.id_sala AS id_sala_venta,
    tabla_localidad.nombre AS nombre_localidad_sala,
    EXTRACT(YEAR FROM tabla_comprobante.fecha) AS anio_facturacion_venta,
    EXTRACT(MONTH FROM tabla_comprobante.fecha) AS mes_facturacion_venta,
    COUNT(tabla_comprobante.nro_comprobante) AS cantidad_ventas_concretadas,
    SUM(tabla_comprobante.total) AS monto_total_recaudado
FROM 
    sala_venta AS tabla_sala_venta
JOIN localidad AS tabla_localidad 
    ON tabla_sala_venta.cp_localidad = tabla_localidad.cp
JOIN comprobante AS tabla_comprobante 
    ON tabla_sala_venta.id_sala = tabla_comprobante.id_sala
WHERE 
    tabla_comprobante.estado = 'procesado'
GROUP BY 
    tabla_sala_venta.id_sala, 
    tabla_localidad.nombre, 
    EXTRACT(YEAR FROM tabla_comprobante.fecha), 
    EXTRACT(MONTH FROM tabla_comprobante.fecha)
ORDER BY 
    anio_facturacion_venta DESC, 
    mes_facturacion_venta DESC, 
    monto_total_recaudado DESC
WITH DATA;

--Vista: Documentos pendientes
CREATE OR REPLACE VIEW documentos_pendientes AS
SELECT 
    'Ingreso' AS tipo_documento_pendiente,
    ingreso.cod_ingreso AS numero_documento_pendiente,
    ingreso.fecha::DATE AS fecha_creacion_documento,
    ingreso.estado AS estado_actual_documento
FROM ingreso
WHERE ingreso.estado != 'procesado'

UNION ALL

SELECT 
    'Transferencia' AS tipo_documento_pendiente,
    transferencia.nro_transferencia AS numero_documento_pendiente,
    transferencia.fecha_confeccion AS fecha_creacion_documento,
    transferencia.estado AS estado_actual_documento
FROM transferencia
WHERE transferencia.estado != 'procesado';