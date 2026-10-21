-- ============================================================================
-- tests/db_tests.sql — Pruebas de reglas de negocio RN-01 a RN-15
-- ----------------------------------------------------------------------------
-- Requisitos : base recién migrada (db/migrations/001 a 007 en orden).
--              001_esquema.sql dropea el esquema public, así que siempre
--              se parte de una base limpia.
-- Ejecución   : psql -v ON_ERROR_STOP=1 -f tests/db_tests.sql
-- Diseño      : todo corre dentro de UNA transacción que termina en ROLLBACK,
--              por eso el script es re-ejecutable y no deja datos residuales.
--              Cada caso se registra en la tabla temporal _test_resultados
--              y el resumen final se emite antes del ROLLBACK.
--
-- Convención de resultados:
--   PASS = el caso se comportó como se espera (funciona, o falla con el
--          SQLSTATE y el mensaje esperados).
--   FALLA = el caso no se comportó como se espera (no falló, falló con otro
--           error, o directamente falló el caso que debía funcionar).
-- ============================================================================

\echo '=== TPI Bodegas del Atuel — suite de pruebas de reglas de negocio ==='

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Andamiaje: tabla de resultados y helpers
--    KISS: 3 helpers, uno por tipo de caso. Cada uno escribe una fila en
--    _test_resultados y nunca propaga errores (los errores "esperados" se
--    capturan en el sub-bloque EXCEPTION de la propia función).
-- ----------------------------------------------------------------------------

CREATE TEMP TABLE _test_resultados (
    orden   SERIAL,
    regla   TEXT NOT NULL,
    caso    TEXT NOT NULL,
    ok      BOOLEAN NOT NULL,
    detalle TEXT NOT NULL
);

-- Caso que DEBE FUNCIONAR: si alguna sentencia produce error, el caso FALLA.
CREATE FUNCTION _test_ok(p_regla TEXT, p_caso TEXT, p_sentencias TEXT[])
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE s TEXT;
BEGIN
    FOREACH s IN ARRAY p_sentencias LOOP
        EXECUTE s;
    END LOOP;
    INSERT INTO _test_resultados (regla, caso, ok, detalle)
    VALUES (p_regla, p_caso, TRUE, 'OK: sentencias ejecutadas sin error');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO _test_resultados (regla, caso, ok, detalle)
    VALUES (p_regla, p_caso, FALSE, format('FALLA: error inesperado [%s] %s', SQLSTATE, SQLERRM));
END;
$$;

-- Caso que DEBE FALLAR: exige el SQLSTATE y un fragmento del mensaje esperados.
-- p_patron se usa como patrón LIKE (el % del mensaje de PG actúa como comodín).
CREATE FUNCTION _test_falla(
    p_regla TEXT, p_caso TEXT, p_sentencias TEXT[],
    p_sqlstate TEXT, p_patron TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE s TEXT;
BEGIN
    FOREACH s IN ARRAY p_sentencias LOOP
        EXECUTE s;
    END LOOP;
    INSERT INTO _test_resultados (regla, caso, ok, detalle)
    VALUES (p_regla, p_caso, FALSE,
            format('FALLA: no se produjo el error esperado [%s] ~ %s', p_sqlstate, p_patron));
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = p_sqlstate AND SQLERRM LIKE p_patron THEN
        INSERT INTO _test_resultados (regla, caso, ok, detalle)
        VALUES (p_regla, p_caso, TRUE, format('OK: falló como se esperaba [%s] %s', SQLSTATE, SQLERRM));
    ELSE
        INSERT INTO _test_resultados (regla, caso, ok, detalle)
        VALUES (p_regla, p_caso, FALSE,
                format('FALLA: error esperado [%s] ~ %s, llegó [%s] %s',
                       p_sqlstate, p_patron, SQLSTATE, SQLERRM));
    END IF;
END;
$$;

-- Aserción sobre el estado: p_consulta debe devolver una única fila booleana.
CREATE FUNCTION _test_assert(p_regla TEXT, p_caso TEXT, p_consulta TEXT, p_detalle TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_ok BOOLEAN;
BEGIN
    EXECUTE p_consulta INTO v_ok;
    INSERT INTO _test_resultados (regla, caso, ok, detalle)
    VALUES (p_regla, p_caso, COALESCE(v_ok, FALSE),
            CASE WHEN COALESCE(v_ok, FALSE) THEN 'OK: ' || p_detalle
                 ELSE 'FALLA: aserción cumplida? no — ' || p_detalle END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO _test_resultados (regla, caso, ok, detalle)
    VALUES (p_regla, p_caso, FALSE, format('FALLA: la aserción rompió [%s] %s', SQLSTATE, SQLERRM));
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. Fixtures: datos base con prefijo "TEST" / CUITs 99… (FK-safe).
--    No son casos de prueba: son el escenario sobre el que se apoyan.
-- ----------------------------------------------------------------------------

INSERT INTO provincia (id_provincia, nombre) VALUES (99, 'TEST Provincia');
INSERT INTO departamento (id_departamento, id_provincia, nombre) VALUES (99, 99, 'TEST Departamento');
INSERT INTO localidad (cp, nombre, id_provincia, cuit_encargado_regional)
VALUES (99999, 'TEST Localidad', 99, NULL);

INSERT INTO sala_venta (id_sala, cp_localidad, calle, numero, dia_cierre)
VALUES (99, 99999, 'TEST Calle', 123, 'Lunes');

INSERT INTO empleado (cuit, id_sala, nombre, fecha_ingreso, salario)
VALUES ('99000000001', 99, 'TEST Empleado Uno', DATE '2020-01-01', 100000.00);

INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
VALUES ('TEST Transportista', '99000000002', 'test@transportista.com', '2655000000', 'TEST 123');

INSERT INTO bodega (cuit_bodega, razon_social, domicilio)
VALUES ('99000000003', 'TEST Bodega', 'TEST 456');

INSERT INTO cepa (nombre, tipo) VALUES ('TEST Malbec', 'Tinto'), ('TEST Cabernet', 'Tinto');

INSERT INTO finca (id_departamento, nombre, superficie)
VALUES (99, 'TEST Finca', 100.00);

INSERT INTO parcela (id_finca, nro_parcela, id_cepa, superficie, anio_plantacion)
SELECT f.id_finca, 1, c.id_cepa, 10.00, 2020
FROM finca f, cepa c
WHERE f.nombre = 'TEST Finca' AND c.nombre = 'TEST Malbec';

INSERT INTO vino (cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio)
VALUES ('99000000003', 'TEST Vino Uno', 'Tinto', 2024, 750.00, 13.00, 1000.00),
       ('99000000003', 'TEST Vino Dos', 'Tinto', 2023, 750.00, 12.50, 800.00);

-- RN-05: composición válida (100 %) de los fixtures; el constraint trigger
-- diferido la valida al forzar SET CONSTRAINTS en el caso RN-05 OK.
INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
SELECT v.cod_vino, c.id_cepa, 100
FROM vino v, cepa c
WHERE v.nombre = 'TEST Vino Uno' AND c.nombre = 'TEST Malbec';

INSERT INTO stock_deposito (cod_vino, cantidad)
SELECT cod_vino,
       CASE WHEN nombre = 'TEST Vino Uno' THEN 100 ELSE 5 END
FROM vino WHERE nombre IN ('TEST Vino Uno', 'TEST Vino Dos');

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
SELECT 99, cod_vino, 10 FROM vino WHERE nombre = 'TEST Vino Uno';

INSERT INTO cliente (cp_localidad, nombre_razon_social, tipo_doc, nro_doc,
                     direccion, fecha_alta, descuento, tipo_cliente)
VALUES (99999, 'TEST Socio', 'DNI', '9000001', 'TEST 1', DATE '2024-01-01', 10.00, 'socio'),
       (99999, 'TEST Distribuidor', 'DNI', '9000002', 'TEST 2', DATE '2024-01-01', 20.00, 'distribuidor'),
       (99999, 'TEST Exportador', 'DNI', '9000003', 'TEST 3', DATE '2024-01-01', 30.00, 'exportador');

INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
SELECT id_cliente, 'TEST Zona', 'HAB-1' FROM cliente WHERE nro_doc = '9000002';

INSERT INTO exportador (id_cliente, pais_destino)
SELECT id_cliente, 'TEST País' FROM cliente WHERE nro_doc = '9000003';

INSERT INTO permiso_exportacion (id_cliente, fecha_emision, fecha_vencimiento)
SELECT id_cliente, DATE '2026-01-01', DATE '2026-12-31'
FROM cliente WHERE nro_doc = '9000003';

-- Ingreso A (En confección) con un renglón de 10 und. de "TEST Vino Uno".
WITH nuevo AS (
    INSERT INTO ingreso (cod_transportista, cuit_bodega, fecha, estado)
    VALUES ((SELECT cod_transportista FROM transportista WHERE razon_social = 'TEST Transportista'),
            '99000000003', now(), 'En confección')
    RETURNING cod_ingreso
)
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT n.cod_ingreso, v.cod_vino, 10
FROM nuevo n, vino v WHERE v.nombre = 'TEST Vino Uno';

-- Transferencia X (En confección) con un renglón de 3 und. de "TEST Vino Uno".
WITH nueva AS (
    INSERT INTO transferencia (id_sala, fecha_confeccion, estado)
    VALUES (99, DATE '2026-01-01', 'En confección')
    RETURNING nro_transferencia
)
INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
SELECT t.nro_transferencia, v.cod_vino, 3
FROM nueva t, vino v WHERE v.nombre = 'TEST Vino Uno';

-- ============================================================================
-- 3. CASOS POR REGLA: primero los que deben funcionar, después los que deben
--    fallar (agrupados por regla para poder leer la trazabilidad RN → caso).
-- ============================================================================

-- ---------------------------------------------------------------- RN-01 -----
-- Precio de vino único en la red (atributo de vino) y siempre mayor que cero.

SELECT _test_ok('RN-01', 'vino con precio positivo se da de alta',
    ARRAY['INSERT INTO vino (cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio)
           VALUES (''99000000003'', ''TEST Vino Tres'', ''Tinto'', 2022, 750.00, 12.00, 3000.00)']);

-- DEBE FALLAR: precio = 0 → CHECK chk_vino_precio [23514]
SELECT _test_falla('RN-01', 'precio 0 rechazado',
    ARRAY['INSERT INTO vino (cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio)
           VALUES (''99000000003'', ''TEST Vino Precio Cero'', ''Tinto'', 2022, 750.00, 12.00, 0)'],
    '23514', '%chk_vino_precio%');

-- ---------------------------------------------------------------- RN-02 -----
-- Sala → una sola localidad; localidad → un único encargado regional.

SELECT _test_ok('RN-02', 'sala en localidad existente y encargado regional asignado',
    ARRAY['INSERT INTO sala_venta (id_sala, cp_localidad, calle, numero, dia_cierre)
           VALUES (98, 99999, ''TEST Calle 2'', 456, ''Martes'')',
          'UPDATE localidad SET cuit_encargado_regional = ''99000000001'' WHERE cp = 99999']);

SELECT _test_assert('RN-02', 'la localidad queda con un solo encargado',
    'SELECT cuit_encargado_regional = ''99000000001'' FROM localidad WHERE cp = 99999',
    'el encargado regional es el empleado TEST 99000000001');

-- DEBE FALLAR: sala en localidad inexistente → FK fk_sala_loc [23503]
SELECT _test_falla('RN-02', 'sala con localidad inexistente rechazada',
    ARRAY['INSERT INTO sala_venta (id_sala, cp_localidad, calle, numero, dia_cierre)
           VALUES (97, 99998, ''TEST Calle 3'', 789, ''Miércoles'')'],
    '23503', '%fk_sala_loc%');

-- DEBE FALLAR: encargado regional inexistente → FK fk_loc_empleado [23503]
SELECT _test_falla('RN-02', 'encargado regional inexistente rechazado',
    ARRAY['UPDATE localidad SET cuit_encargado_regional = ''99000000099'' WHERE cp = 99999'],
    '23503', '%fk_loc_empleado%');

-- ---------------------------------------------------------------- RN-03 -----
-- Cada empleado trabaja en una sola sala (FK NOT NULL).

SELECT _test_ok('RN-03', 'segundo empleado en la misma sala',
    ARRAY['INSERT INTO empleado (cuit, id_sala, nombre, fecha_ingreso, salario)
           VALUES (''99000000004'', 99, ''TEST Empleado Dos'', DATE ''2021-01-01'', 90000.00)']);

-- DEBE FALLAR: id_sala NULL → NOT NULL [23502]
SELECT _test_falla('RN-03', 'empleado sin sala rechazado',
    ARRAY['INSERT INTO empleado (cuit, id_sala, nombre, fecha_ingreso, salario)
           VALUES (''99000000005'', NULL, ''TEST Empleado Sin Sala'', DATE ''2022-01-01'', 80000.00)'],
    '23502', '%"id_sala"%');

-- DEBE FALLAR: sala inexistente → FK fk_emp_sala [23503]
SELECT _test_falla('RN-03', 'empleado en sala inexistente rechazado',
    ARRAY['INSERT INTO empleado (cuit, id_sala, nombre, fecha_ingreso, salario)
           VALUES (''99000000006'', 9999, ''TEST Empleado Raro'', DATE ''2022-01-01'', 80000.00)'],
    '23503', '%fk_emp_sala%');

-- ---------------------------------------------------------------- RN-04 -----
-- Una parcela se cosecha como máximo una vez por campaña.

SELECT _test_ok('RN-04', 'lote de la parcela en campaña distinta',
    ARRAY['INSERT INTO lote_uva (id_finca, nro_parcela, cuit_bodega, campania, fecha, kg)
           SELECT f.id_finca, 1, ''99000000003'', 2030, DATE ''2030-03-15'', 500.00
           FROM finca f WHERE f.nombre = ''TEST Finca''']);

-- DEBE FALLAR: repetir (parcela, campaña) → UNIQUE uq_cosecha_parcela [23505]
SELECT _test_falla('RN-04', 'segunda cosecha en la misma campaña rechazada',
    ARRAY['INSERT INTO lote_uva (id_finca, nro_parcela, cuit_bodega, campania, fecha, kg)
           SELECT f.id_finca, 1, ''99000000003'', 2030, DATE ''2030-04-01'', 400.00
           FROM finca f WHERE f.nombre = ''TEST Finca'''],
    '23505', '%uq_cosecha_parcela%');

-- ---------------------------------------------------------------- RN-05 -----
-- La composición de cada vino suma exactamente 100 (CONSTRAINT TRIGGER diferido).

-- La composición válida de fixtures (100 %) pasa la validación diferida.
-- SET CONSTRAINTS dispara el trigger diferido dentro de la llamada; se restaura
-- DEFERRED para que los casos siguientes se comporten como en tiempo real.
SELECT _test_ok('RN-05', 'composición que suma 100 pasa el control diferido',
    ARRAY['SET CONSTRAINTS ALL IMMEDIATE', 'SET CONSTRAINTS ALL DEFERRED']);

-- DEBE FALLAR: composición 60 + 30 = 90 → trigger diferido RN-05 [P0001].
-- Al forzar SET CONSTRAINTS ALL IMMEDIATE el error aparece adentro de la
-- llamada; sin esa línea aparecería recién en el COMMIT de la transacción.
SELECT _test_falla('RN-05', 'composición que suma 90 rechazada al forzar el commit diferido',
    ARRAY['INSERT INTO vino (cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio)
           VALUES (''99000000003'', ''TEST Vino Corte'', ''Tinto'', 2021, 750.00, 13.00, 900.00)',
          'INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
           SELECT v.cod_vino, c.id_cepa, 60 FROM vino v, cepa c
           WHERE v.nombre = ''TEST Vino Corte'' AND c.nombre = ''TEST Malbec''',
          'INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
           SELECT v.cod_vino, c.id_cepa, 30 FROM vino v, cepa c
           WHERE v.nombre = ''TEST Vino Corte'' AND c.nombre = ''TEST Cabernet''',
          'SET CONSTRAINTS ALL IMMEDIATE'],
    'P0001', '%sumar 100 por ciento%');

-- ---------------------------------------------------------------- RN-06 -----
-- Descuento por tipo de cliente (socio 10 %, distribuidor 20 %, exportador 30 %)
-- con CHECK de rango en cliente.descuento.

SELECT _test_assert('RN-06', 'descuento según tipo de cliente',
    'SELECT fn_descuento_cliente((SELECT id_cliente FROM cliente WHERE nro_doc = ''9000001'')) = 10
     AND fn_descuento_cliente((SELECT id_cliente FROM cliente WHERE nro_doc = ''9000002'')) = 20
     AND fn_descuento_cliente((SELECT id_cliente FROM cliente WHERE nro_doc = ''9000003'')) = 30',
    'socio 10 %, distribuidor 20 %, exportador 30 % (fixtures dados de alta sin error)');

-- DEBE FALLAR: descuento fuera del rango 0..100 → CHECK chk_cliente_descuento [23514]
SELECT _test_falla('RN-06', 'descuento 150 % rechazado',
    ARRAY['INSERT INTO cliente (cp_localidad, nombre_razon_social, tipo_doc, nro_doc,
                                direccion, fecha_alta, descuento, tipo_cliente)
           VALUES (99999, ''TEST Descuento Inválido'', ''DNI'', ''9000004'', ''TEST 4'',
                   DATE ''2024-01-01'', 150.00, ''socio'')'],
    '23514', '%chk_cliente_descuento%');

-- ---------------------------------------------------------------- RN-07 -----
-- Permiso de exportación: el vencimiento es posterior a la emisión.

SELECT _test_ok('RN-07', 'permiso con vencimiento posterior a la emisión',
    ARRAY['INSERT INTO permiso_exportacion (id_cliente, fecha_emision, fecha_vencimiento)
           SELECT id_cliente, DATE ''2027-01-01'', DATE ''2027-06-30''
           FROM cliente WHERE nro_doc = ''9000003''']);

-- DEBE FALLAR: vencimiento anterior a la emisión → CHECK chk_permiso_fechas [23514]
SELECT _test_falla('RN-07', 'permiso vencido antes de emitirse rechazado',
    ARRAY['INSERT INTO permiso_exportacion (id_cliente, fecha_emision, fecha_vencimiento)
           SELECT id_cliente, DATE ''2026-06-01'', DATE ''2026-05-01''
           FROM cliente WHERE nro_doc = ''9000003'''],
    '23514', '%chk_permiso_fechas%');

-- ---------------------------------------------------------------- RN-08 -----
-- El total del comprobante es la suma de sus renglones con descuento;
-- no se carga a mano (función de cálculo + triggers).

SELECT _test_ok('RN-08', 'venta: subtotal y total calculados por la base',
    ARRAY['INSERT INTO comprobante (id_cliente, id_sala, fecha, subtotal, descuento, total)
           SELECT id_cliente, 99, now(), 0, 0, 0 FROM cliente WHERE nro_doc = ''9000001''',
          'INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
           SELECT (SELECT max(nro_comprobante) FROM comprobante), v.cod_vino, 4, 1000.00, 0, 0
           FROM vino v WHERE v.nombre = ''TEST Vino Uno''']);

SELECT _test_assert('RN-08', 'el subtotal del renglón lo calcula el trigger',
    'SELECT r.subtotal = 4000.00
     FROM renglon_comprobante r
     WHERE r.nro_comprobante = (SELECT max(nro_comprobante) FROM comprobante)',
    '4 und. x 1000 = 4000, cargado 0 a mano y corregido solo');

SELECT _test_assert('RN-08', 'la cabecera refleja la suma de renglones',
    'SELECT c.subtotal = 4000.00 AND c.total = 4000.00
        AND c.total = fn_total_comprobante(c.nro_comprobante)
     FROM comprobante c
     WHERE c.nro_comprobante = (SELECT max(nro_comprobante) FROM comprobante)',
    'subtotal 4000 y total 4000 calculados por trigger/fn_total_comprobante');

SELECT _test_ok('RN-08', 'venta con descuento de cabecera',
    ARRAY['INSERT INTO comprobante (id_cliente, id_sala, fecha, subtotal, descuento, total)
           SELECT id_cliente, 99, now(), 0, 500, 0 FROM cliente WHERE nro_doc = ''9000001''',
          'INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
           SELECT (SELECT max(nro_comprobante) FROM comprobante), v.cod_vino, 2, 1000.00, 0, 0
           FROM vino v WHERE v.nombre = ''TEST Vino Uno''']);

SELECT _test_assert('RN-08', 'total = suma de renglones - descuento de cabecera',
    'SELECT c.subtotal = 2000.00 AND c.total = 1500.00
        AND c.total = fn_total_comprobante(c.nro_comprobante)
     FROM comprobante c
     WHERE c.nro_comprobante = (SELECT max(nro_comprobante) FROM comprobante)',
    '2000 - 500 de descuento = 1500 (fórmula GREATEST de fn_total_comprobante)');

-- DEBE FALLAR: cargar el total a mano → trigger RN-08 [P0001]
SELECT _test_falla('RN-08', 'total cargado a mano rechazado',
    ARRAY['UPDATE comprobante SET total = 999999.00
           WHERE nro_comprobante = (SELECT max(nro_comprobante) FROM comprobante)'],
    'P0001', '%no se cargan a mano%');

-- ---------------------------------------------------------------- RN-09 -----
-- No se vende más que el stock de la sala; el stock nunca es negativo.
-- Estado del stock de "TEST Vino Uno" en sala 99: 10 - 4 - 2 = 4 und.

SELECT _test_ok('RN-09', 'venta dentro del stock disponible',
    ARRAY['INSERT INTO comprobante (id_cliente, id_sala, fecha, subtotal, descuento, total)
           SELECT id_cliente, 99, now(), 0, 0, 0 FROM cliente WHERE nro_doc = ''9000001''',
          'INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
           SELECT (SELECT max(nro_comprobante) FROM comprobante), v.cod_vino, 4, 1000.00, 0, 0
           FROM vino v WHERE v.nombre = ''TEST Vino Uno''']);

SELECT _test_assert('RN-09', 'la venta descuenta el stock de la sala',
    'SELECT fn_stock_sala(99, v.cod_vino) = 0 FROM vino v WHERE v.nombre = ''TEST Vino Uno''',
    '4 und. vendidas sobre 4 disponibles = 0 restantes');

-- DEBE FALLAR: vender 1 und. sin stock → trigger RN-09 [P0001]
SELECT _test_falla('RN-09', 'venta sin stock rechazada',
    ARRAY['INSERT INTO comprobante (id_cliente, id_sala, fecha, subtotal, descuento, total)
           SELECT id_cliente, 99, now(), 0, 0, 0 FROM cliente WHERE nro_doc = ''9000001''',
          'INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
           SELECT (SELECT max(nro_comprobante) FROM comprobante), v.cod_vino, 1, 1000.00, 0, 0
           FROM vino v WHERE v.nombre = ''TEST Vino Uno'''],
    'P0001', '%Stock insuficiente%');

-- DEBE FALLAR: stock negativo → CHECK chk_stock_sala_positivo [23514]
SELECT _test_falla('RN-09', 'stock negativo rechazado',
    ARRAY['UPDATE stock_sala SET cantidad = -1
           WHERE id_sala = 99
             AND cod_vino = (SELECT cod_vino FROM vino WHERE nombre = ''TEST Vino Uno'')'],
    '23514', '%chk_stock_sala_positivo%');

SELECT _test_assert('RN-09', 'el intento de dejar stock negativo no tuvo efecto',
    'SELECT fn_stock_sala(99, v.cod_vino) = 0 FROM vino v WHERE v.nombre = ''TEST Vino Uno''',
    'el stock sigue en 0 después del intento rechazado');

-- ---------------------------------------------------------------- RN-10 -----
-- Sólo un ingreso Terminado impacta en el depósito y pasa a Procesado;
-- transiciones En confección → Terminado → Procesado, sin retrocesos.

SELECT _test_ok('RN-10', 'transición válida En confección → Terminado',
    ARRAY['UPDATE ingreso SET estado = ''Terminado''
           WHERE cod_ingreso = (SELECT max(cod_ingreso) FROM ingreso)']);

SELECT _test_ok('RN-10', 'sp_procesar_ingreso impacta en el depósito',
    ARRAY['DO $$ DECLARE v int; BEGIN v := (SELECT max(cod_ingreso) FROM ingreso); CALL sp_procesar_ingreso(v); END $$']);

SELECT _test_assert('RN-10', 'el ingreso terminado pasa a Procesado',
    'SELECT estado = ''Procesado'' FROM ingreso WHERE cod_ingreso = (SELECT max(cod_ingreso) FROM ingreso)',
    'el ingreso TEST quedó en estado Procesado');

SELECT _test_assert('RN-10', 'el depósito recibió los 10 kg/botellas del ingreso',
    'SELECT sd.cantidad = 110 FROM stock_deposito sd JOIN vino v ON v.cod_vino = sd.cod_vino
     WHERE v.nombre = ''TEST Vino Uno''',
    'stock_deposito: 100 + 10 del ingreso = 110');

-- DEBE FALLAR: re-procesar el mismo ingreso → sp_procesar_ingreso [P0001]
SELECT _test_falla('RN-10', 'reprocesar un ingreso ya procesado',
    ARRAY['DO $$ DECLARE v int; BEGIN v := (SELECT max(cod_ingreso) FROM ingreso); CALL sp_procesar_ingreso(v); END $$'],
    'P0001', '%ya ha sido procesado%');

-- DEBE FALLAR: procesar un ingreso aún En confección → sp_procesar_ingreso [P0001]
SELECT _test_falla('RN-10', 'procesar un ingreso en confección',
    ARRAY['INSERT INTO ingreso (cod_transportista, cuit_bodega, fecha)
           VALUES ((SELECT cod_transportista FROM transportista WHERE razon_social = ''TEST Transportista''),
                   ''99000000003'', now())',
          'DO $$ DECLARE v int; BEGIN v := (SELECT max(cod_ingreso) FROM ingreso); CALL sp_procesar_ingreso(v); END $$'],
    'P0001', '%debe estar en estado%');

-- DEBE FALLAR: retroceso Terminado → En confección → trigger de estados [P0001]
SELECT _test_falla('RN-10', 'retroceso de estado en ingreso',
    ARRAY['INSERT INTO ingreso (cod_transportista, cuit_bodega, fecha)
           VALUES ((SELECT cod_transportista FROM transportista WHERE razon_social = ''TEST Transportista''),
                   ''99000000003'', now())',
          'UPDATE ingreso SET estado = ''Terminado'' WHERE cod_ingreso = (SELECT max(cod_ingreso) FROM ingreso)',
          'UPDATE ingreso SET estado = ''En confección'' WHERE cod_ingreso = (SELECT max(cod_ingreso) FROM ingreso)'],
    'P0001', '%Transición inválida%');

-- DEBE FALLAR: crear un ingreso directamente Procesado → trigger de alta [P0001]
SELECT _test_falla('RN-10', 'alta de ingreso directamente Procesado',
    ARRAY['INSERT INTO ingreso (cod_transportista, cuit_bodega, fecha, estado)
           VALUES ((SELECT cod_transportista FROM transportista WHERE razon_social = ''TEST Transportista''),
                   ''99000000003'', now(), ''Procesado'')'],
    'P0001', '%se inician en estado%');

-- ---------------------------------------------------------------- RN-11 -----
-- Igual que RN-10 para transferencias; la fecha de confección es la actual
-- y no se puede modificar.

SELECT _test_ok('RN-11', 'transición válida En confección → Terminado',
    ARRAY['UPDATE transferencia SET estado = ''Terminado''
           WHERE nro_transferencia = (SELECT min(nro_transferencia) FROM transferencia)']);

SELECT _test_ok('RN-11', 'sp_procesar_transferencia mueve stock depósito → sala',
    ARRAY['DO $$ DECLARE v int; BEGIN v := (SELECT min(nro_transferencia) FROM transferencia); CALL sp_procesar_transferencia(v); END $$']);

SELECT _test_assert('RN-11', 'la transferencia terminada pasa a Procesado',
    'SELECT estado = ''Procesado'' FROM transferencia
     WHERE nro_transferencia = (SELECT min(nro_transferencia) FROM transferencia)',
    'la transferencia TEST quedó en estado Procesado');

SELECT _test_assert('RN-11', 'el stock se movió completo (3 und.)',
    'SELECT (SELECT sd.cantidad FROM stock_deposito sd JOIN vino v ON v.cod_vino = sd.cod_vino
      WHERE v.nombre = ''TEST Vino Uno'') = 107
     AND fn_stock_sala(99, (SELECT cod_vino FROM vino WHERE nombre = ''TEST Vino Uno'')) = 3',
    'depósito 110 - 3 = 107 y sala 0 + 3 = 3');

SELECT _test_ok('RN-11', 'la fecha de confección se fuerza a la actual al dar de alta',
    ARRAY['INSERT INTO transferencia (id_sala, fecha_confeccion, estado)
           VALUES (99, DATE ''2000-01-01'', ''En confección'')']);

SELECT _test_assert('RN-11', 'fecha de confección = CURRENT_DATE',
    'SELECT fecha_confeccion = CURRENT_DATE FROM transferencia
     WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)',
    'la fecha cargada a mano (2000-01-01) fue reemplazada por la de hoy');

-- DEBE FALLAR: modificar la fecha de confección → trigger de fecha [P0001]
SELECT _test_falla('RN-11', 'modificación de la fecha de confección',
    ARRAY['UPDATE transferencia SET fecha_confeccion = DATE ''1999-01-01''
           WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)'],
    'P0001', '%no puede ser modificada%');

-- DEBE FALLAR: procesar una transferencia En confección → sp_procesar_transferencia [P0001]
SELECT _test_falla('RN-11', 'procesar una transferencia en confección',
    ARRAY['DO $$ DECLARE v int; BEGIN v := (SELECT max(nro_transferencia) FROM transferencia); CALL sp_procesar_transferencia(v); END $$'],
    'P0001', '%debe estar en estado%');

-- DEBE FALLAR: retroceso Terminado → En confección → trigger de estados [P0001]
SELECT _test_falla('RN-11', 'retroceso de estado en transferencia',
    ARRAY['INSERT INTO transferencia (id_sala, estado) VALUES (99, ''En confección'')',
          'UPDATE transferencia SET estado = ''Terminado''
           WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)',
          'UPDATE transferencia SET estado = ''En confección''
           WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)'],
    'P0001', '%Transición inválida%');

-- DEBE FALLAR: reprocesar una transferencia ya procesada → sp [P0001]
SELECT _test_falla('RN-11', 'reprocesar una transferencia ya procesada',
    ARRAY['DO $$ DECLARE v int; BEGIN v := (SELECT min(nro_transferencia) FROM transferencia); CALL sp_procesar_transferencia(v); END $$'],
    'P0001', '%ya ha sido procesada%');

-- DEBE FALLAR: transferir más de lo que hay en depósito → CHECK
-- chk_stock_deposito_positivo [23514] y ROLLBACK completo de la llamada.
SELECT _test_falla('RN-11', 'transferencia sin stock en depósito',
    ARRAY['INSERT INTO transferencia (id_sala, estado) VALUES (99, ''En confección'')',
          'INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
           SELECT (SELECT max(nro_transferencia) FROM transferencia), v.cod_vino, 50
           FROM vino v WHERE v.nombre = ''TEST Vino Dos''',
          'UPDATE transferencia SET estado = ''Terminado''
           WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)',
          'DO $$ DECLARE v int; BEGIN v := (SELECT max(nro_transferencia) FROM transferencia); CALL sp_procesar_transferencia(v); END $$'],
    '23514', '%chk_stock_deposito_positivo%');

-- Criterio de aceptación: no queda ningún cambio a medias.
SELECT _test_assert('RN-11', 'sin stock: el depósito no se tocó',
    'SELECT sd.cantidad = 5 FROM stock_deposito sd JOIN vino v ON v.cod_vino = sd.cod_vino
     WHERE v.nombre = ''TEST Vino Dos''',
    'stock_deposito del vino TEST sigue en 5');
SELECT _test_assert('RN-11', 'sin stock: la sala no recibió nada',
    'SELECT fn_stock_sala(99, (SELECT cod_vino FROM vino WHERE nombre = ''TEST Vino Uno'')) = 3',
    'stock_sala de la sala 99 sigue en 3');
SELECT _test_assert('RN-11', 'sin stock: no quedó la transferencia a medias',
    'SELECT count(*) = 2 FROM transferencia',
    'sólo existen las transferencias TEST creadas antes del intento fallido');

-- ---------------------------------------------------------------- RN-12 -----
-- Un documento que no está En confección no admite cambios en sus renglones.

SELECT _test_ok('RN-12', 'agregar renglón a una transferencia En confección',
    ARRAY['INSERT INTO transferencia (id_sala, estado) VALUES (99, ''En confección'')',
          'INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
           SELECT (SELECT max(nro_transferencia) FROM transferencia), v.cod_vino, 2
           FROM vino v WHERE v.nombre = ''TEST Vino Uno''']);

SELECT _test_ok('RN-12', 'agregar renglón a un ingreso En confección',
    ARRAY['INSERT INTO ingreso (cod_transportista, cuit_bodega, fecha)
           VALUES ((SELECT cod_transportista FROM transportista WHERE razon_social = ''TEST Transportista''),
                   ''99000000003'', now())',
          'INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
           SELECT (SELECT max(cod_ingreso) FROM ingreso), v.cod_vino, 2
           FROM vino v WHERE v.nombre = ''TEST Vino Uno''']);

-- DEBE FALLAR: agregar un renglón a un ingreso Terminado → trigger RN-12 [P0001]
SELECT _test_falla('RN-12', 'agregar renglón a ingreso Terminado',
    ARRAY['INSERT INTO ingreso (cod_transportista, cuit_bodega, fecha)
           VALUES ((SELECT cod_transportista FROM transportista WHERE razon_social = ''TEST Transportista''),
                   ''99000000003'', now())',
          'INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
           SELECT (SELECT max(cod_ingreso) FROM ingreso), v.cod_vino, 1
           FROM vino v WHERE v.nombre = ''TEST Vino Uno''',
          'UPDATE ingreso SET estado = ''Terminado'' WHERE cod_ingreso = (SELECT max(cod_ingreso) FROM ingreso)',
          'INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
           SELECT (SELECT max(cod_ingreso) FROM ingreso), v.cod_vino, 1
           FROM vino v WHERE v.nombre = ''TEST Vino Dos'''],
    'P0001', '%Solo se permiten cambios%');

-- DEBE FALLAR: modificar un renglón de una transferencia Terminada → RN-12 [P0001]
SELECT _test_falla('RN-12', 'modificar renglón de transferencia Terminada',
    ARRAY['INSERT INTO transferencia (id_sala, estado) VALUES (99, ''En confección'')',
          'INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
           SELECT (SELECT max(nro_transferencia) FROM transferencia), v.cod_vino, 1
           FROM vino v WHERE v.nombre = ''TEST Vino Uno''',
          'UPDATE transferencia SET estado = ''Terminado''
           WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)',
          'UPDATE renglon_transferencia SET cantidad = 99
           WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)'],
    'P0001', '%Solo se permiten cambios%');

-- DEBE FALLAR: quitar un renglón de una transferencia Terminada → RN-12 [P0001]
SELECT _test_falla('RN-12', 'borrar renglón de transferencia Terminada',
    ARRAY['INSERT INTO transferencia (id_sala, estado) VALUES (99, ''En confección'')',
          'INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
           SELECT (SELECT max(nro_transferencia) FROM transferencia), v.cod_vino, 1
           FROM vino v WHERE v.nombre = ''TEST Vino Dos''',
          'UPDATE transferencia SET estado = ''Terminado''
           WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)',
          'DELETE FROM renglon_transferencia
           WHERE nro_transferencia = (SELECT max(nro_transferencia) FROM transferencia)'],
    'P0001', '%Solo se permiten cambios%');

-- ---------------------------------------------------------------- RN-13 -----
-- Todo cambio de precio queda auditado (fecha, usuario, precio anterior/nuevo).

SELECT _test_ok('RN-13', 'cambio de precio de un vino',
    ARRAY['UPDATE vino SET precio = 1200.00 WHERE nombre = ''TEST Vino Uno''']);

SELECT _test_assert('RN-13', 'el cambio de precio quedó auditado',
    'SELECT EXISTS (
        SELECT 1 FROM auditoria_precio a JOIN vino v ON v.cod_vino = a.cod_vino
        WHERE v.nombre = ''TEST Vino Uno''
          AND a.precio_anterior = 1000.00 AND a.precio_nuevo = 1200.00
          AND a.usuario = current_user)',
    'fila en auditoria_precio con precio anterior, nuevo y usuario actual');

-- DEBE FUNCIONAR sin efectos: un UPDATE que no toca el precio no debe
-- generar ninguna fila de auditoría (esperado: 0 filas, sin error).
SELECT _test_ok('RN-13', 'UPDATE que no modifica el precio',
    ARRAY['UPDATE vino SET activo = NOT activo WHERE nombre = ''TEST Vino Dos''']);

SELECT _test_assert('RN-13', 'sin cambio de precio no hay auditoría',
    'SELECT NOT EXISTS (
        SELECT 1 FROM auditoria_precio a JOIN vino v ON v.cod_vino = a.cod_vino
        WHERE v.nombre = ''TEST Vino Dos'')',
    '0 filas de auditoría para el vino cuyo precio no cambió');

-- ---------------------------------------------------------------- RN-14 -----
-- No se borra un transportista, una bodega ni un vino con movimientos (RESTRICT).

SELECT _test_ok('RN-14', 'borrar transportista sin movimientos',
    ARRAY['INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
           VALUES (''TEST Transportista Libre'', ''99000000004'', ''libre@test.com'', ''2655000001'', ''TEST 789'')',
          'DELETE FROM transportista WHERE razon_social = ''TEST Transportista Libre''']);

SELECT _test_ok('RN-14', 'borrar bodega sin vinos ni lotes',
    ARRAY['INSERT INTO bodega (cuit_bodega, razon_social, domicilio)
           VALUES (''99000000005'', ''TEST Bodega Libre'', ''TEST 999'')',
          'DELETE FROM bodega WHERE razon_social = ''TEST Bodega Libre''']);

SELECT _test_ok('RN-14', 'borrar vino sin movimientos asociados',
    ARRAY['DELETE FROM vino WHERE nombre = ''TEST Vino Tres''']);

-- DEBE FALLAR: borrar un vino vendido → FK RESTRICT [23503]
SELECT _test_falla('RN-14', 'borrar vino con movimientos',
    ARRAY['DELETE FROM vino WHERE nombre = ''TEST Vino Uno'''],
    '23503', '%on table "vino"%');

-- DEBE FALLAR: borrar una bodega con vinos → FK RESTRICT [23503]
SELECT _test_falla('RN-14', 'borrar bodega con vinos',
    ARRAY['DELETE FROM bodega WHERE cuit_bodega = ''99000000003'''],
    '23503', '%on table "bodega"%');

-- DEBE FALLAR: borrar un transportista con ingresos → FK RESTRICT [23503]
SELECT _test_falla('RN-14', 'borrar transportista con ingresos',
    ARRAY['DELETE FROM transportista WHERE razon_social = ''TEST Transportista'''],
    '23503', '%on table "transportista"%');

-- ---------------------------------------------------------------- RN-15 -----
-- Cantidades, superficies, kilos y precios siempre positivos; graduación 5..20.

SELECT _test_ok('RN-15', 'valores válidos: lote con kg positivos y vino con graduación en rango',
    ARRAY['INSERT INTO lote_uva (id_finca, nro_parcela, cuit_bodega, campania, fecha, kg)
           SELECT f.id_finca, 1, ''99000000003'', 2031, DATE ''2031-03-15'', 100.00
           FROM finca f WHERE f.nombre = ''TEST Finca''',
          'INSERT INTO vino (cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio)
           VALUES (''99000000003'', ''TEST Vino Cuatro'', ''Blanco'', 2024, 750.00, 5.00, 500.00)']);

-- DEBE FALLAR: kg negativos → CHECK chk_lote_kg [23514]
SELECT _test_falla('RN-15', 'lote con kg negativos',
    ARRAY['INSERT INTO lote_uva (id_finca, nro_parcela, cuit_bodega, campania, fecha, kg)
           SELECT f.id_finca, 1, ''99000000003'', 2032, DATE ''2032-03-15'', -5.00
           FROM finca f WHERE f.nombre = ''TEST Finca'''],
    '23514', '%chk_lote_kg%');

-- DEBE FALLAR: superficie de finca 0 → CHECK chk_finca_superficie [23514]
SELECT _test_falla('RN-15', 'finca con superficie 0',
    ARRAY['INSERT INTO finca (id_departamento, nombre, superficie)
           VALUES (99, ''TEST Finca Cero'', 0)'],
    '23514', '%chk_finca_superficie%');

-- DEBE FALLAR: graduación fuera del rango legal → CHECK chk_vino_graduacion [23514]
SELECT _test_falla('RN-15', 'vino con graduación 25 %',
    ARRAY['INSERT INTO vino (cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio)
           VALUES (''99000000003'', ''TEST Vino Fuera de Rango'', ''Tinto'', 2024, 750.00, 25.00, 1000.00)'],
    '23514', '%chk_vino_graduacion%');

-- DEBE FALLAR: renglón con cantidad 0 → CHECK chk_rcomp_cantidad [23514]
SELECT _test_falla('RN-15', 'renglón de comprobante con cantidad 0',
    ARRAY['INSERT INTO comprobante (id_cliente, id_sala, fecha, subtotal, descuento, total)
           SELECT id_cliente, 99, now(), 0, 0, 0 FROM cliente WHERE nro_doc = ''9000001''',
          'INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
           SELECT (SELECT max(nro_comprobante) FROM comprobante), v.cod_vino, 0, 1000.00, 0, 0
           FROM vino v WHERE v.nombre = ''TEST Vino Uno'''],
    '23514', '%chk_rcomp_cantidad%');

-- ============================================================================
-- 4. RESUMEN (se emite antes del ROLLBACK: los datos de prueba no persisten)
-- ============================================================================

\echo ''
\echo '=== Totales ==='
SELECT CASE WHEN ok THEN 'PASS' ELSE 'FALLA' END AS resultado,
       count(*) AS casos
FROM _test_resultados
GROUP BY ok
ORDER BY ok DESC;

\echo '=== Detalle (si la lista de FALLAS está vacía, la suite está verde) ==='
SELECT lpad(regla, 6) AS regla,
       CASE WHEN ok THEN 'PASS' ELSE 'FALLA' END AS res,
       caso,
       detalle
FROM _test_resultados
ORDER BY orden;

ROLLBACK;
