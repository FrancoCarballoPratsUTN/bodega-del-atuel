-- 1. Vista de Stock total por vino
-- Combina el stock del depósito central con el stock sumado de todas las salas de venta.
CREATE OR REPLACE VIEW v_stock_total_vino AS
SELECT 
    v.cod_vino,
    v.nombre,
    v.aniada,
    v.volumen,
    COALESCE(sd.cantidad, 0) AS stock_deposito,
    COALESCE(SUM(ss.cantidad), 0) AS stock_salas,
    COALESCE(sd.cantidad, 0) + COALESCE(SUM(ss.cantidad), 0) AS stock_total
FROM 
    vino v
LEFT JOIN stock_deposito sd ON v.cod_vino = sd.cod_vino
LEFT JOIN stock_sala ss ON v.cod_vino = ss.cod_vino
GROUP BY 
    v.cod_vino, v.nombre, v.aniada, v.volumen, sd.cantidad;


-- 2. Vista Materializada de Ventas mensuales por sala 
-- Como los datos viejos de meses anteriores no cambian,mejora
-- el rendimiento cuando la API solicite reportes estadísticos.
CREATE MATERIALIZED VIEW mv_ventas_mensuales_sala AS
SELECT 
    s.id_sala,
    l.nombre AS localidad,
    EXTRACT(YEAR FROM c.fecha) AS anio,
    EXTRACT(MONTH FROM c.fecha) AS mes,
    COUNT(c.nro_comprobante) AS cantidad_ventas,
    SUM(c.total) AS total_recaudado
FROM 
    sala_venta s
JOIN localidad l ON s.cp_localidad = l.cp
JOIN comprobante c ON s.id_sala = c.id_sala
GROUP BY 
    s.id_sala, l.nombre, EXTRACT(YEAR FROM c.fecha), EXTRACT(MONTH FROM c.fecha)
ORDER BY 
    anio DESC, mes DESC, total_recaudado DESC;


-- 3. Vista de Documentos pendientes
-- Unifica los ingresos y las transferencias que aún no han sido procesados 
-- (es decir, los que están "En confección" o "Terminados") usando UNION ALL para armar un panel de control.
CREATE OR REPLACE VIEW v_documentos_pendientes AS
SELECT 
    'Ingreso' AS tipo_documento,
    cod_ingreso AS numero_documento,
    fecha::DATE AS fecha_creacion,
    estado
FROM ingreso
WHERE estado != 'Procesado'
UNION ALL
SELECT 
    'Transferencia' AS tipo_documento,
    nro_transferencia AS numero_documento,
    fecha_confeccion AS fecha_creacion,
    estado
FROM transferencia
WHERE estado != 'Procesado';