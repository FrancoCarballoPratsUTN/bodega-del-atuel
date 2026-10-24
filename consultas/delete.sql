
-- Las operaciones se prueban en una única transacción y se revierten.

BEGIN;

-- D1. Borrar comprobantes de socios con más de 5 años de antigüedad.
-- ON DELETE CASCADE elimina sus renglones; los triggers de venta restituyen
-- el stock de la sala antes del ROLLBACK.
SELECT COUNT(*) AS comprobantes_candidatos
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo_cliente = 'Socio'
   AND c.fecha < CURRENT_TIMESTAMP - INTERVAL '5 years';

DELETE FROM comprobante c
 USING cliente cl
 WHERE c.id_cliente = cl.id_cliente
   AND cl.tipo_cliente = 'Socio'
   AND c.fecha < CURRENT_TIMESTAMP - INTERVAL '5 years';

SELECT COUNT(*) AS comprobantes_restantes_en_criterio
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo_cliente = 'Socio'
   AND c.fecha < CURRENT_TIMESTAMP - INTERVAL '5 years';

-- D2. Eliminar cepas que no componen ningún vino ni están plantadas.
-- Se protegen las dos relaciones de uso con NOT EXISTS.
SELECT COUNT(*) AS cepas_candidatas
  FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

DELETE FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

SELECT COUNT(*) AS cepas_huerfanas_restantes
  FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

-- D3. Eliminar empleados de la sala de General Alvear que trabajaron menos
-- de dos años. El NOT EXISTS sobre localidad evita romper la FK del encargado
-- regional; si fuera encargado, la regla de integridad prevalece.
SELECT COUNT(*) AS empleados_candidatos
  FROM empleado e
  JOIN sala_venta s ON s.id_sala = e.id_sala
  JOIN localidad l ON l.cp = s.cp_localidad
 WHERE l.nombre = 'General Alvear'
   AND fn_antiguedad_anios(e.fecha_ingreso) < 2
   AND NOT EXISTS (
       SELECT 1
         FROM localidad l2
        WHERE l2.cuit_encargado_regional = e.cuit
   );

DELETE FROM empleado e
 USING sala_venta s, localidad l
 WHERE s.id_sala = e.id_sala
   AND l.cp = s.cp_localidad
   AND l.nombre = 'General Alvear'
   AND fn_antiguedad_anios(e.fecha_ingreso) < 2
   AND NOT EXISTS (
       SELECT 1
         FROM localidad l2
        WHERE l2.cuit_encargado_regional = e.cuit
   );

SELECT COUNT(*) AS empleados_restantes_en_criterio
  FROM empleado e
  JOIN sala_venta s ON s.id_sala = e.id_sala
  JOIN localidad l ON l.cp = s.cp_localidad
 WHERE l.nombre = 'General Alvear'
   AND fn_antiguedad_anios(e.fecha_ingreso) < 2
   AND NOT EXISTS (
       SELECT 1
         FROM localidad l2
        WHERE l2.cuit_encargado_regional = e.cuit
   );

-- D4. Borrar socios sin compras y dados de alta hace más de 5 años.
-- NOT EXISTS implementa la condición de "nunca compraron".
SELECT COUNT(*) AS clientes_candidatos
  FROM cliente c
 WHERE c.tipo_cliente = 'Socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (
       SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente
   );

DELETE FROM cliente c
 WHERE c.tipo_cliente = 'Socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (
       SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente
   );

SELECT COUNT(*) AS clientes_restantes_en_criterio
  FROM cliente c
 WHERE c.tipo_cliente = 'Socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (
       SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente
   );

-- D5. Borrar ingresos procesados de hace más de 365 días.
-- Se habilita únicamente dentro de esta transacción el borrado histórico
-- explícito; la cascada elimina sus renglones sin desactivar el trigger.
SELECT COUNT(*) AS ingresos_candidatos
  FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_TIMESTAMP - INTERVAL '365 days';

SELECT set_config('bda.eliminar_ingreso_procesado', 'on', true);

DELETE FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_TIMESTAMP - INTERVAL '365 days';

SELECT COUNT(*) AS ingresos_procesados_antiguos_restantes
  FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_TIMESTAMP - INTERVAL '365 days';

-- D6. Borrar socios sin compras de General Alvear.
-- El parámetro localidad está identificado por nombre y se puede sustituir.
SELECT COUNT(*) AS clientes_candidatos
  FROM cliente c
  JOIN localidad l ON l.cp = c.cp_localidad
 WHERE c.tipo_cliente = 'Socio'
   AND l.nombre = 'General Alvear'
   AND NOT EXISTS (
       SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente
   );

DELETE FROM cliente c
 USING localidad l
 WHERE l.cp = c.cp_localidad
   AND c.tipo_cliente = 'Socio'
   AND l.nombre = 'General Alvear'
   AND NOT EXISTS (
       SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente
   );

SELECT COUNT(*) AS clientes_restantes_en_criterio
  FROM cliente c
  JOIN localidad l ON l.cp = c.cp_localidad
 WHERE c.tipo_cliente = 'Socio'
   AND l.nombre = 'General Alvear'
   AND NOT EXISTS (
       SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente
   );

ROLLBACK;
