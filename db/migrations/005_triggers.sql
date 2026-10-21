-- Requiere: 003_funciones.sql (fn_stock_sala, fn_total_comprobante, fn_calcular_subtotal) --


-- Cálculo del subtotal del renglón (reutiliza fn_calcular_subtotal de 003) --

CREATE OR REPLACE FUNCTION trg_calcular_subtotal_renglon() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.subtotal := fn_calcular_subtotal(NEW.cantidad, NEW.precio_unitario, NEW.descuento);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_calcula_subtotal
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_calcular_subtotal_renglon();


-- Validación de stock en venta (RN-09) --

CREATE OR REPLACE FUNCTION trg_validar_stock_venta() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    sala_del_comprobante INTEGER;
BEGIN
    SELECT id_sala INTO sala_del_comprobante FROM comprobante WHERE nro_comprobante = NEW.nro_comprobante;

    IF fn_stock_sala(sala_del_comprobante, NEW.cod_vino) < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente del vino % en la sala % (RN-09)', NEW.cod_vino, sala_del_comprobante;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_valida_stock
BEFORE INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_validar_stock_venta();


-- Descuento de stock y cálculo de totales (RN-08, RN-09) --

CREATE OR REPLACE FUNCTION trg_actualizar_venta() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    sala_del_comprobante INTEGER;
BEGIN
    SELECT id_sala INTO sala_del_comprobante FROM comprobante WHERE nro_comprobante = NEW.nro_comprobante;

    -- Actualiza inventario
    UPDATE stock_sala
    SET cantidad = cantidad - NEW.cantidad
    WHERE id_sala = sala_del_comprobante AND cod_vino = NEW.cod_vino;

    -- Actualiza cabecera del comprobante.
    -- El descuento de cabecera es el descuento general y no se modifica por renglón.
    UPDATE comprobante
    SET subtotal = subtotal + NEW.subtotal
    WHERE nro_comprobante = NEW.nro_comprobante;

    -- Recalcula el total con la misma fórmula de 003 (fuente única de verdad):
    -- GREATEST(subtotal - descuento, 0)
    UPDATE comprobante
    SET total = fn_total_comprobante(NEW.nro_comprobante)
    WHERE nro_comprobante = NEW.nro_comprobante;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_actualiza_venta
AFTER INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_actualizar_venta();


-- Control de estados de ingreso y transferencia (RN-10, RN-11) --

CREATE OR REPLACE FUNCTION trg_control_estados() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.estado = 'En confección' AND NEW.estado NOT IN ('En confección', 'Terminado') THEN
        RAISE EXCEPTION 'Transición inválida. De "En confección" solo pasa a "Terminado" (RN-10/11)';
    ELSIF OLD.estado = 'Terminado' AND NEW.estado NOT IN ('Terminado', 'Procesado') THEN
        RAISE EXCEPTION 'Transición inválida. De "Terminado" solo pasa a "Procesado" (RN-10/11)';
    ELSIF OLD.estado = 'Procesado' AND NEW.estado != 'Procesado' THEN
        RAISE EXCEPTION 'Un documento "Procesado" no puede cambiar de estado (RN-10/11)';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ingreso_estados
BEFORE UPDATE ON ingreso
FOR EACH ROW EXECUTE FUNCTION trg_control_estados();

CREATE TRIGGER trg_transferencia_estados
BEFORE UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_control_estados();


-- Bloqueo de renglones (RN-12) --

CREATE OR REPLACE FUNCTION trg_bloqueo_renglones_ingreso() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    estado_actual_ingreso estado_enum;
BEGIN
    SELECT estado INTO estado_actual_ingreso FROM ingreso WHERE cod_ingreso = COALESCE(NEW.cod_ingreso, OLD.cod_ingreso);
    IF estado_actual_ingreso != 'En confección' THEN
        RAISE EXCEPTION 'Solo se permiten cambios de renglones en estado "En confección" (RN-12)';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_renglon_ingreso_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION trg_bloqueo_renglones_ingreso();

CREATE OR REPLACE FUNCTION trg_bloqueo_renglones_transfer() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    estado_actual_transferencia estado_enum;
BEGIN
    SELECT estado INTO estado_actual_transferencia FROM transferencia WHERE nro_transferencia = COALESCE(NEW.nro_transferencia, OLD.nro_transferencia);
    IF estado_actual_transferencia != 'En confección' THEN
        RAISE EXCEPTION 'Solo se permiten cambios de renglones en estado "En confección" (RN-12)';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_renglon_transferencia_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW EXECUTE FUNCTION trg_bloqueo_renglones_transfer();


-- Fecha de confección inmutable (RN-11) --

CREATE OR REPLACE FUNCTION trg_fecha_transferencia() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.fecha_confeccion != OLD.fecha_confeccion THEN
            RAISE EXCEPTION 'La fecha de confección no puede ser modificada (RN-11)';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_fecha_transferencia();


-- Auditoría de precio de vino (RN-13) --

CREATE OR REPLACE FUNCTION trg_auditar_precio_vino() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.precio != OLD.precio THEN
        INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
        VALUES (NEW.cod_vino, OLD.precio, NEW.precio, CURRENT_TIMESTAMP, current_user);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_vino_auditoria
AFTER UPDATE ON vino
FOR EACH ROW EXECUTE FUNCTION trg_auditar_precio_vino();


-- Restricción diferida para porcentajes de corte (RN-05) --

CREATE OR REPLACE FUNCTION trg_validar_composicion() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    suma_total_porcentajes NUMERIC;
    codigo_del_vino INTEGER;
BEGIN
    codigo_del_vino := COALESCE(NEW.cod_vino, OLD.cod_vino);
    SELECT SUM(porcentaje) INTO suma_total_porcentajes FROM composicion WHERE cod_vino = codigo_del_vino;
    
    IF suma_total_porcentajes != 100 THEN
        RAISE EXCEPTION 'La composición del vino % debe sumar 100 por ciento (RN-05). Actual: %', codigo_del_vino, COALESCE(suma_total_porcentajes, 0);
    END IF;
    
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_composicion_porcentaje
AFTER INSERT OR UPDATE OR DELETE ON composicion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_validar_composicion();