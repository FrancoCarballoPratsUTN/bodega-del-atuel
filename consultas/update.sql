-- Etapa 5 - Consultas de modificación (UPDATE)
-- Todas las pruebas están encapsuladas en una transacción y terminan con ROLLBACK.

BEGIN;

-- U1. Recalcular el total de todos los comprobantes aplicando el descuento
-- correspondiente al tipo de cliente.
-- Estrategia: la función fn_importes_comprobante usa los descuentos calculados
-- en los renglones; se actualizan las tres columnas monetarias de cada comprobante.
SELECT COUNT(*) AS comprobantes_antes,
       COALESCE(SUM(total), 0) AS total_antes
  FROM comprobante;

UPDATE comprobante c
   SET subtotal = i.subtotal_bruto,
       descuento = i.descuento_total,
       total = i.total_neto
  FROM (
      SELECT c2.nro_comprobante, i.subtotal_bruto, i.descuento_total, i.total_neto
        FROM comprobante c2
        CROSS JOIN LATERAL fn_importes_comprobante(c2.nro_comprobante) AS i
  ) AS i
 WHERE i.nro_comprobante = c.nro_comprobante;

SELECT COUNT(*) AS comprobantes_despues,
       COALESCE(SUM(total), 0) AS total_despues
  FROM comprobante;

-- U2. Aumentar un 20 % el salario de los empleados con más de 5 años.
-- Se usa fn_antiguedad_anios para que el corte dependa de CURRENT_DATE.
SELECT COUNT(*) AS empleados_candidatos,
       COALESCE(SUM(salario), 0) AS salarios_antes
  FROM empleado
 WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

UPDATE empleado
   SET salario = ROUND(salario * 1.20, 2)
 WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

SELECT COUNT(*) AS empleados_afectados,
       COALESCE(SUM(salario), 0) AS salarios_despues
  FROM empleado
 WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

-- U3. Incrementar un 13 % el precio de los vinos elaborados por una bodega.
-- Parámetro elegido del dataset: la primera bodega ordenada por CUIT.
SELECT b.razon_social AS bodega_elegida,
       COUNT(v.cod_vino) AS vinos_afectados_antes,
       COALESCE(SUM(v.precio), 0) AS precios_antes
  FROM bodega b
  JOIN vino v ON v.cuit_bodega = b.cuit_bodega
 WHERE b.cuit_bodega = (SELECT cuit_bodega FROM bodega ORDER BY cuit_bodega LIMIT 1)
 GROUP BY b.razon_social;

UPDATE vino v
   SET precio = ROUND(v.precio * 1.13, 2)
 WHERE v.cuit_bodega = (
     SELECT cuit_bodega FROM bodega ORDER BY cuit_bodega LIMIT 1
 );

SELECT b.razon_social AS bodega_elegida,
       COUNT(v.cod_vino) AS vinos_afectados_despues,
       COALESCE(SUM(v.precio), 0) AS precios_despues
  FROM bodega b
  JOIN vino v ON v.cuit_bodega = b.cuit_bodega
 WHERE b.cuit_bodega = (SELECT cuit_bodega FROM bodega ORDER BY cuit_bodega LIMIT 1)
 GROUP BY b.razon_social;

-- U4. Cambiar lunes por miércoles y miércoles por lunes en una sola sentencia.
-- CASE evita una segunda actualización y conserva los demás días.
SELECT dia_cierre, COUNT(*) AS cantidad_antes
  FROM sala_venta
 GROUP BY dia_cierre
 ORDER BY dia_cierre;

UPDATE sala_venta
   SET dia_cierre = CASE dia_cierre
       WHEN 'Lunes' THEN 'Miércoles'::dia_semana_enum
       WHEN 'Miércoles' THEN 'Lunes'::dia_semana_enum
       ELSE dia_cierre
   END
 WHERE dia_cierre IN ('Lunes', 'Miércoles');

SELECT dia_cierre, COUNT(*) AS cantidad_despues
  FROM sala_venta
 GROUP BY dia_cierre
 ORDER BY dia_cierre;

-- U5. Aplicar un 15 % de descuento de precio a los 10 vinos menos vendidos.
-- Se incluyen vinos sin ventas mediante LEFT JOIN; en empate se usa cod_vino
-- como desempate reproducible.
SELECT v.cod_vino, v.nombre, COALESCE(SUM(r.cantidad), 0) AS botellas_antes
  FROM vino v
  LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
 GROUP BY v.cod_vino, v.nombre
 ORDER BY botellas_antes, v.cod_vino
 LIMIT 10;

WITH ventas AS (
    SELECT v.cod_vino,
           COALESCE(SUM(r.cantidad), 0) AS botellas_vendidas
      FROM vino v
      LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
     GROUP BY v.cod_vino
),
menos_vendidos AS (
    SELECT cod_vino
      FROM ventas
     ORDER BY botellas_vendidas, cod_vino
     LIMIT 10
)
UPDATE vino v
   SET precio = ROUND(v.precio * 0.85, 2)
 WHERE v.cod_vino IN (SELECT cod_vino FROM menos_vendidos);

SELECT v.cod_vino, v.nombre, v.precio AS precio_despues
  FROM vino v
 WHERE v.cod_vino IN (
     SELECT cod_vino
       FROM (
           SELECT v2.cod_vino,
                  COALESCE(SUM(r.cantidad), 0) AS botellas_vendidas
             FROM vino v2
             LEFT JOIN renglon_comprobante r ON r.cod_vino = v2.cod_vino
            GROUP BY v2.cod_vino
            ORDER BY botellas_vendidas, v2.cod_vino
            LIMIT 10
       ) seleccion
 );

-- U6. Aplicar un descuento de 30 % a los exportadores con más de 3 permisos.
-- 30 % es el valor válido para Exportador según RN-06.
SELECT c.id_cliente,
       c.nombre_razon_social,
       COUNT(p.cod_permiso) AS permisos,
       c.descuento AS descuento_antes
  FROM cliente c
  JOIN exportador e ON e.id_cliente = c.id_cliente
  JOIN permiso_exportacion p ON p.id_cliente = e.id_cliente
 GROUP BY c.id_cliente, c.nombre_razon_social, c.descuento
HAVING COUNT(p.cod_permiso) > 3;

UPDATE cliente c
   SET descuento = 30.00
 WHERE c.tipo_cliente = 'Exportador'
   AND c.id_cliente IN (
       SELECT p.id_cliente
         FROM permiso_exportacion p
        GROUP BY p.id_cliente
       HAVING COUNT(*) > 3
   );

SELECT c.id_cliente, c.tipo_cliente, c.descuento AS descuento_despues
  FROM cliente c
 WHERE c.tipo_cliente = 'Exportador'
   AND c.id_cliente IN (
       SELECT p.id_cliente
         FROM permiso_exportacion p
        GROUP BY p.id_cliente
       HAVING COUNT(*) > 3
   );

ROLLBACK;
