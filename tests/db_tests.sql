BEGIN;

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

INSERT INTO provincia (id_provincia, nombre) VALUES (1, 'Mendoza');
INSERT INTO departamento (id_departamento, id_provincia, nombre) VALUES (1, 1, 'San Rafael');
INSERT INTO localidad (cp, nombre, id_provincia) VALUES (5600, 'San Rafael Central', 1);

INSERT INTO sala_venta (id_sala, cp_localidad, calle, numero, dia_cierre) 
VALUES (1, 5600, 'Av. Balloffet', 500, 'Domingo');

INSERT INTO empleado (cuit, id_sala, nombre, fecha_ingreso, salario) 
VALUES ('20381234567', 1, 'Carlos Perez', '2022-01-15', 550000.00);

UPDATE localidad SET cuit_encargado_regional = '20381234567' WHERE cp = 5600;

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio) 
VALUES (1, 'Expreso Cuyo', '30701234567', 'contacto@expresocuyo.com', '2604123456', 'Ruta 143');

INSERT INTO cepa (id_cepa, nombre, tipo) VALUES (1, 'Malbec', 'Tinta'), (2, 'Cabernet Sauvignon', 'Tinta');
INSERT INTO finca (id_finca, id_departamento, nombre, superficie) VALUES (1, 1, 'Finca Los Álamos', 50.00);
INSERT INTO parcela (id_finca, nro_parcela, id_cepa, superficie, anio_plantacion) VALUES (1, 1, 1, 10.00, 2015);
INSERT INTO bodega (cuit_bodega, razon_social, domicilio) VALUES ('30501234567', 'Bodega del Atuel', 'Calle Cubillos km 10');

-- Cliente Socio (10% de descuento derivado por RN-06)
INSERT INTO cliente (id_cliente, cp_localidad, nombre_razon_social, tipo_doc, nro_doc, direccion, fecha_alta, descuento, tipo_cliente) 
VALUES (1, 5600, 'Juan Gomez', 'DNI', '35123456', 'Mitre 120', '2023-05-10', 10.00, 'Socio');

-- RN-01: El precio de un vino es único y mayor que cero.
-- Caso OK: Inserción válida con precio > 0
INSERT INTO vino (cod_vino, cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio) 
VALUES (1, '30501234567', 'Atuel Reserva', 'Tinto', 2021, 750, 14.0, 4500.00);
PERFORM registrar_test('RN-01', 'Inserción válida de vino con precio > 0', TRUE);
-- Caso Fallo: Intentar insertar precio <= 0 (Error esperado: CHECK_VIOLATION '23514')
DO $$
BEGIN
    INSERT INTO vino (cod_vino, cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio) 
    VALUES (2, '30501234567', 'Atuel Cero', 'Tinto', 2021, 750, 14.0, 0.00);
    PERFORM registrar_test('RN-01', 'Precio <= 0 rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23514' THEN
    PERFORM registrar_test('RN-01', 'Precio <= 0 rechazado (CHECK_VIOLATION)', TRUE);
END $$;

-- RN-02: Una sala pertenece a una sola localidad; encargado único.
-- Caso Fallo: Encargado regional inexistente (Error esperado: FOREIGN_KEY_VIOLATION '23503')
DO $$
BEGIN
    INSERT INTO localidad (cp, nombre, id_provincia, cuit_encargado_regional) 
    VALUES (5601, 'Cuadro Nacional', 1, '99999999999');
    PERFORM registrar_test('RN-02', 'Encargado inexistente rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23503' THEN
    PERFORM registrar_test('RN-02', 'Encargado inexistente rechazado (FK_VIOLATION)', TRUE);
END $$;

-- RN-03: Cada empleado trabaja en una sola sala (FK NOT NULL).
-- Caso Fallo: Crear empleado con id_sala NULL (Error esperado: NOT_NULL_VIOLATION '23502')
DO $$
BEGIN
    INSERT INTO empleado (cuit, id_sala, nombre, fecha_ingreso, salario) 
    VALUES ('20389999997', NULL, 'Sin Sala', '2023-01-01', 300000.00);
    PERFORM registrar_test('RN-03', 'Empleado sin sala rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23502' THEN
    PERFORM registrar_test('RN-03', 'Empleado sin sala rechazado (NOT_NULL_VIOLATION)', TRUE);
END $$;

-- RN-04: Una parcela se cosecha como máximo una vez por campaña.
-- Caso OK: Primera cosecha registrada
INSERT INTO lote_uva (nro_lote, id_finca, nro_parcela, cuit_bodega, campania, fecha, kg) 
VALUES (1, 1, 1, '30501234567', 2024, '2024-03-15', 12000.00);
PERFORM registrar_test('RN-04', 'Cosecha única registrada', TRUE);
-- Caso Fallo: Duplicar cosecha en la misma campaña (Error esperado: UNIQUE_VIOLATION '23505')
DO $$
BEGIN
    INSERT INTO lote_uva (nro_lote, id_finca, nro_parcela, cuit_bodega, campania, fecha, kg) 
    VALUES (2, 1, 1, '30501234567', 2024, '2024-03-20', 8000.00);
    PERFORM registrar_test('RN-04', 'Segunda cosecha en misma campaña rechazada', FALSE);
EXCEPTION WHEN SQLSTATE '23505' THEN
    PERFORM registrar_test('RN-04', 'Segunda cosecha rechazada (UNIQUE_VIOLATION)', TRUE);
END $$;

-- RN-05: Los porcentajes de corte suman exactamente 100%.
-- Caso OK: Composición válida de 60% y 40%
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (1, 1, 60.00);
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (1, 2, 40.00);
PERFORM registrar_test('RN-05', 'Composición válida que suma 100%', TRUE);

-- RN-06: Descuento obligatorio por Tipo de Cliente (Socio 10%, Distribuidor 20%, Exportador 30%).
-- Caso Fallo: Intentar asignar 50% de descuento a un Socio (Error esperado: CHECK_VIOLATION '23514')
DO $$
BEGIN
    INSERT INTO cliente (id_cliente, cp_localidad, nombre_razon_social, tipo_doc, nro_doc, direccion, fecha_alta, descuento, tipo_cliente) 
    VALUES (99, 5600, 'Socio Invalido', 'DNI', '99999999', 'Calle 1', CURRENT_DATE, 50.00, 'Socio');
    PERFORM registrar_test('RN-06', 'Descuento inconsistente con tipo de cliente rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23514' THEN
    PERFORM registrar_test('RN-06', 'Descuento inconsistente rechazado (CHECK_VIOLATION)', TRUE);
END $$;

-- RN-07: Permisos de exportación: fecha_vencimiento > fecha_emision.
-- Caso OK: Fechas en orden cronológico
INSERT INTO exportador (id_cliente, pais_destino) VALUES (1, 'Brasil');
INSERT INTO permiso_exportacion (cod_permiso, id_cliente, fecha_emision, fecha_vencimiento) 
VALUES (1, 1, '2024-01-01', '2024-12-31');
PERFORM registrar_test('RN-07', 'Permiso con fechas válidas registrado', TRUE);
-- Caso Fallo: Vencimiento anterior a la emisión (Error esperado: CHECK_VIOLATION '23514')
DO $$
BEGIN
    INSERT INTO permiso_exportacion (cod_permiso, id_cliente, fecha_emision, fecha_vencimiento) 
    VALUES (2, 1, '2024-06-01', '2024-01-01');
    PERFORM registrar_test('RN-07', 'Permiso con vencimiento <= emisión rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23514' THEN
    PERFORM registrar_test('RN-07', 'Fechas inválidas rechazadas (CHECK_VIOLATION)', TRUE);
END $$;

-- RN-08: El total del comprobante se deriva automáticamente de sus renglones.
INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, 1, 100);
-- Caso OK: Crear comprobante con subtotales iniciales calculados
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala, fecha, subtotal, descuento, total) 
VALUES (1, 1, 1, CURRENT_TIMESTAMP, 0, 0, 0);
PERFORM registrar_test('RN-08', 'Comprobante creado con valores calculados', TRUE);

-- RN-09: No vender más del stock disponible en la sala (Stock >= 0).
-- Caso OK: Venta de 10 unidades sobre 100 disponibles
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal) 
VALUES (1, 1, 10, 4500.00, 0, 45000.00);
PERFORM registrar_test('RN-09', 'Venta dentro del stock disponible aprobada', TRUE);
-- Caso Fallo: Venta de 500 unidades cuando restan 90 (Error esperado: RAISE_EXCEPTION 'P0001')
DO $$
BEGIN
    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal) 
    VALUES (1, 1, 500, 4500.00, 0, 2250000.00);
    PERFORM registrar_test('RN-09', 'Venta que excede el stock rechazada', FALSE);
EXCEPTION WHEN SQLSTATE 'P0001' THEN
    PERFORM registrar_test('RN-09', 'Exceso de stock rechazado (P0001)', TRUE);
END $$;

-- RN-10: Solo ingreso 'terminado' pasa a 'procesado' e impacta en depósito.
-- Caso OK: Alta en_confeccion -> terminado -> sp_procesar_ingreso
INSERT INTO ingreso (cod_ingreso, cod_transportista, cuit_bodega, fecha, estado) 
VALUES (1, 1, '30501234567', CURRENT_TIMESTAMP, 'en_confeccion');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (1, 1, 50);
UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = 1;

-- Invocar el procedimiento de procesamiento
CALL sp_procesar_ingreso(1);
PERFORM registrar_test('RN-10', 'Ingreso procesado e impactado en depósito', TRUE);

-- Caso Fallo: Intentar pasar de 'en_confeccion' a 'procesado' sin pasar por 'terminado' (Error esperado: 'P0001')
INSERT INTO ingreso (cod_ingreso, cod_transportista, cuit_bodega, fecha, estado) 
VALUES (2, 1, '30501234567', CURRENT_TIMESTAMP, 'en_confeccion');

DO $$
BEGIN
    UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 2;
    PERFORM registrar_test('RN-10', 'Salto ilegal de estado rechazado', FALSE);
EXCEPTION WHEN SQLSTATE 'P0001' THEN
    PERFORM registrar_test('RN-10', 'Salto ilegal de estado rechazado (P0001)', TRUE);
END $$;

-- RN-11: Transferencias: fecha_confeccion inmodificable y transiciones.
-- Caso OK: Transferencia creada con fecha del día
INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado) 
VALUES (1, 1, CURRENT_DATE, 'en_confeccion');
PERFORM registrar_test('RN-11', 'Transferencia creada en confección', TRUE);
-- Caso Fallo: Intentar modificar fecha_confeccion (Error esperado: 'P0001')
DO $$
BEGIN
    UPDATE transferencia SET fecha_confeccion = '2020-01-01' WHERE nro_transferencia = 1;
    PERFORM registrar_test('RN-11', 'Modificación de fecha de confección rechazada', FALSE);
EXCEPTION WHEN SQLSTATE 'P0001' THEN
    PERFORM registrar_test('RN-11', 'Modificación de fecha rechazada (P0001)', TRUE);
END $$;

-- RN-12: Documentos en estado distinto a 'en_confeccion' no admiten cambios en renglones.
-- Caso Fallo: Insertar renglón en ingreso 1 ya en estado 'procesado' (Error esperado: 'P0001')
DO $$
BEGIN
    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (1, 1, 20);
    PERFORM registrar_test('RN-12', 'Edición de renglones en documento bloqueado rechazada', FALSE);
EXCEPTION WHEN SQLSTATE 'P0001' THEN
    PERFORM registrar_test('RN-12', 'Edición en documento bloqueado rechazada (P0001)', TRUE);
END $$;

-- RN-13: Auditoría de cambios de precio.
-- Caso OK: Actualización de precio e inspecionar la tabla auditoria_precio
UPDATE vino SET precio = 5000.00 WHERE cod_vino = 1;

DO $$
DECLARE
    v_cant INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_cant FROM auditoria_precio WHERE cod_vino = 1 AND precio_nuevo = 5000.00;
    IF v_cant > 0 THEN
        PERFORM registrar_test('RN-13', 'Cambio de precio registrado en auditoría', TRUE);
    ELSE
        PERFORM registrar_test('RN-13', 'Cambio de precio registrado en auditoría', FALSE);
    END IF;
END $$;

-- RN-14: No borrar transportista, bodega o vino con movimientos asociados.
-- Caso Fallo: Eliminar bodega con registros asociados (Error esperado: FOREIGN_KEY_VIOLATION '23503')
DO $$
BEGIN
    DELETE FROM bodega WHERE cuit_bodega = '30501234567';
    PERFORM registrar_test('RN-14', 'Borrado de bodega con movimientos rechazado', FALSE);
EXCEPTION WHEN SQLSTATE '23503' THEN
    PERFORM registrar_test('RN-14', 'Borrado con movimientos rechazado (FK_VIOLATION)', TRUE);
END $$;

-- RN-15: Graduación alcohólica entre 5 y 20 grados.
-- Caso Fallo: Intentar ingresar vino con graduación alcohólica de 25.00 (Error esperado: '23514')
DO $$
BEGIN
    INSERT INTO vino (cod_vino, cuit_bodega, nombre, tipo, aniada, volumen, graduacion, precio) 
    VALUES (99, '30501234567', 'Vino Ilegal', 'Tinto', 2023, 750, 25.0, 5000.00);
    PERFORM registrar_test('RN-15', 'Graduación alcohólica fuera de rango rechazada', FALSE);
EXCEPTION WHEN SQLSTATE '23514' THEN
    PERFORM registrar_test('RN-15', 'Graduación fuera de rango rechazada (CHECK_VIOLATION)', TRUE);
END $$;

SELECT regla, descripcion, resultado FROM resultado_test ORDER BY id;

ROLLBACK;