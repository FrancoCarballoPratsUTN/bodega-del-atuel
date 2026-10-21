-- Vista: stock_total_vino
CREATE OR REPLACE VIEW stock_total_vino AS
SELECT
    v.cod_vino AS codigo_vino,
    v.nombre AS nombre_vino,
    v.tipo AS tipo_vino,
    v.aniada AS anio_cosecha_vino,
    v.volumen AS volumen_contenido_vino,
    b.razon_social AS razon_social_bodega,
    COALESCE(sd.cantidad, 0) AS cantidad_stock_deposito_central,
    COALESCE(SUM(ss.cantidad), 0) AS cantidad_stock_todas_las_salas,
    COALESCE(sd.cantidad, 0) + COALESCE(SUM(ss.cantidad), 0) AS cantidad_stock_total_general
FROM vino v
JOIN bodega b ON b.cuit_bodega = v.cuit_bodega
LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
LEFT JOIN stock_sala ss ON ss.cod_vino = v.cod_vino
GROUP BY v.cod_vino, v.nombre, v.tipo, v.aniada, v.volumen, b.razon_social, sd.cantidad;

-- Vista: ventas_mensuales_sala
CREATE OR REPLACE VIEW ventas_mensuales_sala AS
SELECT
    sv.id_sala AS id_sala_venta,
    loc.nombre AS nombre_localidad_sala,
    EXTRACT(YEAR FROM c.fecha)::INTEGER AS anio_facturacion_venta,
    EXTRACT(MONTH FROM c.fecha)::INTEGER AS mes_facturacion_venta,
    COUNT(DISTINCT c.nro_comprobante) AS cantidad_ventas_concretadas,
    COALESCE(SUM(rc.cantidad), 0) AS cantidad_botellas_vendidas,
    SUM(c.total) AS monto_total_recaudado
FROM comprobante c
JOIN sala_venta sv ON sv.id_sala = c.id_sala
JOIN localidad loc ON loc.cp = sv.cp_localidad
LEFT JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
GROUP BY sv.id_sala, loc.nombre, EXTRACT(YEAR FROM c.fecha), EXTRACT(MONTH FROM c.fecha);


-- Vista: documentos_pendientes
CREATE OR REPLACE VIEW documentos_pendientes AS
SELECT
    'Ingreso'::TEXT AS tipo_documento_pendiente,
    i.cod_ingreso AS numero_documento_pendiente,
    i.fecha::DATE AS fecha_creacion_documento,
    i.estado AS estado_actual_documento,
    (CURRENT_DATE - i.fecha::DATE) AS dias_pendientes,
    t.razon_social AS contraparte_documento,
    b.razon_social AS destino_documento,
    COALESCE(SUM(ri.cantidad), 0) AS cantidad_unidades,
    COUNT(DISTINCT ri.cod_vino) AS cantidad_vinos_distintos
FROM ingreso i
JOIN transportista t ON t.cod_transportista = i.cod_transportista
JOIN bodega b ON b.cuit_bodega = i.cuit_bodega
LEFT JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
WHERE i.estado <> 'procesado'
GROUP BY i.cod_ingreso, i.fecha, i.estado, t.razon_social, b.razon_social

UNION ALL

SELECT
    'Transferencia'::TEXT AS tipo_documento_pendiente,
    tr.nro_transferencia AS numero_documento_pendiente,
    tr.fecha_confeccion AS fecha_creacion_documento,
    tr.estado AS estado_actual_documento,
    (CURRENT_DATE - tr.fecha_confeccion) AS dias_pendientes,
    NULL::TEXT AS contraparte_documento,
    CONCAT(sv.calle, ' ', sv.numero, ' - ', loc.nombre) AS destino_documento,
    COALESCE(SUM(rt.cantidad), 0) AS cantidad_unidades,
    COUNT(DISTINCT rt.cod_vino) AS cantidad_vinos_distintos
FROM transferencia tr
JOIN sala_venta sv ON sv.id_sala = tr.id_sala
JOIN localidad loc ON loc.cp = sv.cp_localidad
LEFT JOIN renglon_transferencia rt ON rt.nro_transferencia = tr.nro_transferencia
WHERE tr.estado <> 'procesado'
GROUP BY tr.nro_transferencia, tr.fecha_confeccion, tr.estado, sv.calle, sv.numero, loc.nombre;