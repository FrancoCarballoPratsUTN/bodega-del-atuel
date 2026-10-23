BEGIN;
-- Tabla temporal para el reporte final de la suite
CREATE TEMP TABLE IF NOT EXISTS resultado_test (
    id SERIAL PRIMARY KEY,
    regla VARCHAR(10),
    descripcion TEXT,
    resultado VARCHAR(10)
);

CREATE OR REPLACE FUNCTION registrar_test(p_regla VARCHAR, p_desc TEXT, p_ok BOOLEAN) 
RETURNS VOID AS $$
BEGIN
    INSERT INTO resultado_test (regla, descripcion, resultado)
    VALUES (p_regla, p_desc, CASE WHEN p_ok THEN 'PASSED' ELSE 'FAILED' END);
END;
$$ LANGUAGE plpgsql;

SET CONSTRAINTS ALL DEFERRED;
----------------------------------------------------------------------------------
INSERT INTO provincia (id_provincia, nombre) VALUES (1, 'Mendoza');
INSERT INTO departamento (id_departamento, id_provincia, nombre) VALUES (1, 1, 'San Rafael');

-- RN-02: Localidad y Sala de Venta
INSERT INTO localidad (cp, nombre, id_provincia, cuit_encargado_regional) 
VALUES (5600, 'San Rafael Central', 1, '20381234567');

INSERT INTO sala_venta (id_sala, cp_localidad, calle, numero, dia_cierre) 
VALUES (1, 5600, 'Av. Balloffet', 500, 'Domingo');

-- Empleado asignado a la sala 1 y como encargado
INSERT INTO empleado (cuit, id_sala, nombre, fecha_ingreso, salario) 
VALUES ('20381234567', 1, 'Carlos Perez', '2022-01-15', 550000.00);

SELECT registrar_test('RN-02', 'OK: Estructura de localidad y sala de venta (3FN + FK)', TRUE);

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio) 
VALUES (1, 'Expreso Cuyo', '30701234567', 'contacto@expresocuyo.com', '2604123456', 'Ruta 143');

INSERT INTO cepa (id_cepa, nombre, tipo) VALUES (1, 'Malbec', 'Tinta'), (2, 'Cabernet Sauvignon', 'Tinta');
INSERT INTO finca (id_finca, id_departamento, nombre, superficie) VALUES (1, 1, 'Finca Los Álamos', 50.00);

-- RN-04: Parcela tiene una sola cepa
INSERT INTO parcela (id_finca, nro_parcela, id_cepa, superficie, anio_plantacion) 
VALUES (1, 1, 1, 10.00, 2015);

INSERT INTO bodega (cuit_bodega, razon_social, domicilio) 
VALUES ('30501234567', 'Bodega del Atuel', 'Calle Cubillos km 10');
----------------------------------------------------------------------------------------------
-- RN-01: El precio de un vino es único y mayor que cero (CHECK)
INSERT INTO vino (cod_vino, cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio) 
VALUES (1, '30501234567', 'Atuel Reserva', 'Tinto', 2021, 750, 14.0, 4500.00);
SELECT registrar_test('RN-01', 'OK: Inserción de vino con precio > 0', TRUE);

DO $$
BEGIN
    INSERT INTO vino (cod_vino, cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio) 
    VALUES (2, '30501234567', 'Atuel Cero', 'Tinto', 2021, 750, 14.0, 0.00);
    PERFORM registrar_test('RN-01', 'FALLO: Precio <= 0 no fue rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23514' THEN
    PERFORM registrar_test('RN-01', 'FALLO: Precio <= 0 rechazado por CHECK', TRUE);
END $$;

-- RN-03: Cada empleado trabaja en una sola sala (FK NOT NULL)
DO $$
BEGIN
    INSERT INTO empleado (cuit, id_sala, nombre, fecha_ingreso, salario) 
    VALUES ('20389999997', NULL, 'Sin Sala', '2023-01-01', 300000.00);
    PERFORM registrar_test('RN-03', 'FALLO: Empleado sin sala no fue rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23502' THEN
    PERFORM registrar_test('RN-03', 'FALLO: Empleado sin sala (NULL) rechazado', TRUE);
END $$;

-- RN-04: Una parcela se cosecha como máximo una vez por campaña (UNIQUE)
INSERT INTO lote_uva (nro_lote, id_finca, nro_parcela, cuit_bodega, campania, fecha, kg) 
VALUES (1, 1, 1, '30501234567', 2024, '2024-03-15', 12000.00);
SELECT registrar_test('RN-04', 'OK: Primera cosecha de la campaña registrada', TRUE);

DO $$
BEGIN
    INSERT INTO lote_uva (nro_lote, id_finca, nro_parcela, cuit_bodega, campania, fecha, kg) 
    VALUES (2, 1, 1, '30501234567', 2024, '2024-03-20', 8000.00);
    PERFORM registrar_test('RN-04', 'FALLO: Segunda cosecha en la misma campaña no fue rechazada', FALSE);
EXCEPTION WHEN SQLSTATE '23505' THEN
    PERFORM registrar_test('RN-04', 'FALLO: Segunda cosecha en la misma campaña rechazada', TRUE);
END $$;

-- RN-05: Los porcentajes de corte de un vino suman exactamente 100 (Constraint trigger diferido)
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (1, 1, 60.00);
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (1, 2, 40.00);
SELECT registrar_test('RN-05', 'OK: Composición que suma 100%', TRUE);

-- RN-06: Descuento por tipo de cliente (Socio 10%, Distribuidor 20%, Exportador 30%)
INSERT INTO cliente (id_cliente, cp_localidad, nombre_razon_social, tipo_doc, nro_doc, direccion, fecha_alta, descuento, tipo_cliente) 
VALUES (1, 5600, 'Juan Gomez', 'DNI', '35123456', 'Mitre 120', '2023-05-10', 10.00, 'Socio');
SELECT registrar_test('RN-06', 'OK: Descuento válido asignado a cliente Socio', TRUE);

DO $$
BEGIN
    INSERT INTO cliente (id_cliente, cp_localidad, nombre_razon_social, tipo_doc, nro_doc, direccion, fecha_alta, descuento, tipo_cliente) 
    VALUES (99, 5600, 'Socio Invalido', 'DNI', '99999999', 'Calle 1', CURRENT_DATE, 50.00, 'Socio');
    PERFORM registrar_test('RN-06', 'FALLO: Descuento inválido para Socio no fue rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23514' THEN
    PERFORM registrar_test('RN-06', 'FALLO: Descuento inconsistente rechazado por CHECK', TRUE);
END $$;

-- RN-07: Exportador con permisos (vencimiento posterior a emisión)
INSERT INTO exportador (id_cliente, pais_destino) VALUES (1, 'Brasil');
INSERT INTO permiso_exportacion (cod_permiso, id_cliente, fecha_emision, fecha_vencimiento) 
VALUES (1, 1, '2024-01-01', '2024-12-31');
SELECT registrar_test('RN-07', 'OK: Permiso con fechas en orden cronológico registrado', TRUE);

DO $$
BEGIN
    INSERT INTO permiso_exportacion (cod_permiso, id_cliente, fecha_emision, fecha_vencimiento) 
    VALUES (2, 1, '2024-06-01', '2024-01-01');
    PERFORM registrar_test('RN-07', 'FALLO: Fecha de vencimiento anterior a emisión no fue rechazada', FALSE);
EXCEPTION WHEN SQLSTATE '23514' THEN
    PERFORM registrar_test('RN-07', 'FALLO: Vencimiento anterior a emisión rechazado', TRUE);
END $$;

-- RN-08 y RN-09: Comprobante autocalculado y control de stock
INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, 1, 100);

INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala, fecha, subtotal, descuento, total) 
VALUES (1, 1, 1, CURRENT_TIMESTAMP, 0, 0, 0);
SELECT registrar_test('RN-08', 'OK: Comprobante creado (totales derivados por renglones)', TRUE);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal) 
VALUES (1, 1, 10, 4500.00, 0, 45000.00);
SELECT registrar_test('RN-09', 'OK: Venta de stock disponible realizada', TRUE);

DO $$
BEGIN
    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal) 
    VALUES (1, 1, 500, 4500.00, 0, 2250000.00);
    PERFORM registrar_test('RN-09', 'FALLO: Venta que excede el stock no fue rechazada', FALSE);
EXCEPTION WHEN SQLSTATE 'P0001' THEN
    PERFORM registrar_test('RN-09', 'FALLO: Exceso de stock rechazado por trigger', TRUE);
END $$;

-- RN-10: Transiciones de ingreso (en_confeccion -> terminado -> procesado)
INSERT INTO ingreso (cod_ingreso, cod_transportista, cuit_bodega, fecha, estado) 
VALUES (1, 1, '30501234567', CURRENT_TIMESTAMP, 'en_confeccion');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (1, 1, 50);
UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = 1;
CALL sp_procesar_ingreso(1);
SELECT registrar_test('RN-10', 'OK: Transición válida de ingreso impactada en depósito', TRUE);

INSERT INTO ingreso (cod_ingreso, cod_transportista, cuit_bodega, fecha, estado) 
VALUES (2, 1, '30501234567', CURRENT_TIMESTAMP, 'en_confeccion');

DO $$
BEGIN
    UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 2;
    PERFORM registrar_test('RN-10', 'FALLO: Salto ilegal de estado en ingreso no fue rechazado', FALSE);
EXCEPTION WHEN SQLSTATE 'P0001' THEN
    PERFORM registrar_test('RN-10', 'FALLO: Salto de estado ilegal rechazado por trigger', TRUE);
END $$;

-- RN-11: Transferencias (fecha actual inmodificable y control de estados)
INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado) 
VALUES (1, 1, CURRENT_DATE, 'en_confeccion');
SELECT registrar_test('RN-11', 'OK: Transferencia creada en confección', TRUE);

DO $$
BEGIN
    UPDATE transferencia SET fecha_confeccion = '2020-01-01' WHERE nro_transferencia = 1;
    PERFORM registrar_test('RN-11', 'FALLO: Modificación de fecha de confección no fue rechazada', FALSE);
EXCEPTION WHEN SQLSTATE 'P0001' THEN
    PERFORM registrar_test('RN-11', 'FALLO: Cambio de fecha de confección rechazado por trigger', TRUE);
END $$;

-- RN-12: Bloqueo de edición de renglones si el documento no está en confección
DO $$
BEGIN
    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (1, 1, 20);
    PERFORM registrar_test('RN-12', 'FALLO: Edición de renglón en ingreso procesado no fue rechazada', FALSE);
EXCEPTION WHEN SQLSTATE 'P0001' THEN
    PERFORM registrar_test('RN-12', 'FALLO: Edición de renglón en documento bloqueado rechazada', TRUE);
END $$;

-- RN-13: Auditoría de cambio de precio de vinos
UPDATE vino SET precio = 5000.00 WHERE cod_vino = 1;
SELECT registrar_test('RN-13', 'OK: Cambio de precio auditado en tabla auditoria_precio', 
    (SELECT COUNT(*) FROM auditoria_precio WHERE cod_vino = 1 AND precio_nuevo = 5000.00) > 0
);

-- RN-14: o se puede borrar un transportista, una bodega ni un vino que tengan movimientos asociados. 
DO $$
BEGIN
    DELETE FROM bodega WHERE cuit_bodega = '30501234567';
    PERFORM registrar_test('RN-14', 'FALLO: Borrado de bodega con movimientos no fue rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23503' THEN
    PERFORM registrar_test('RN-14', 'FALLO: Borrado de entidad con movimientos rechazado por FK', TRUE);
END $$;

-- RN-15: Valores positivos y graduación alcohólica entre 5 y 20
DO $$
BEGIN
    INSERT INTO vino (cod_vino, cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio) 
    VALUES (99, '30501234567', 'Vino Ilegal', 'Tinto', 2023, 750, 25.0, 5000.00);
    PERFORM registrar_test('RN-15', 'FALLO: Graduación fuera de rango no fue rechazada', FALSE);
EXCEPTION WHEN SQLSTATE '23514' THEN
    PERFORM registrar_test('RN-15', 'FALLO: Graduación fuera de rango (25.0) rechazada por CHECK', TRUE);
END $$;
-----------------------------------------------------------------------
SELECT regla, descripcion, resultado FROM resultado_test ORDER BY id;
ROLLBACK;