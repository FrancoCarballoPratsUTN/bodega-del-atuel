-- RN-05: Los porcentajes de corte de un vino suman exactamente 100.
CREATE OR REPLACE FUNCTION trg_validar_composicion() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    suma_porcentajes_composicion NUMERIC;
    codigo_vino_evaluado INTEGER;
BEGIN
    codigo_vino_evaluado := COALESCE(NEW.cod_vino, OLD.cod_vino);
    
    SELECT COALESCE(SUM(porcentaje), 0) 
    INTO suma_porcentajes_composicion 
    FROM composicion 
    WHERE cod_vino = codigo_vino_evaluado;
    
    IF suma_porcentajes_composicion != 100 THEN
        RAISE EXCEPTION 'La composición del vino % debe sumar exactamente 100. Suma actual: %', 
            codigo_vino_evaluado, suma_porcentajes_composicion;
    END IF;
    
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_composicion_porcentaje
AFTER INSERT OR UPDATE OR DELETE ON composicion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_validar_composicion();

-- RN-08: El total del comprobante es la suma de sus renglones con descuento.
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


CREATE OR REPLACE FUNCTION trg_validar_totales_comprobante() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    monto_total_esperado_comprobante NUMERIC;
BEGIN
    monto_total_esperado_comprobante := fn_total_comprobante(NEW.nro_comprobante);

    IF NEW.total IS DISTINCT FROM monto_total_esperado_comprobante THEN
        RAISE EXCEPTION 'El total del comprobante % no se carga a mano. Calculado: %, Ingresado: %',
            NEW.nro_comprobante, monto_total_esperado_comprobante, NEW.total;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comprobante_valida_totales
BEFORE INSERT OR UPDATE ON comprobante
FOR EACH ROW EXECUTE FUNCTION trg_validar_totales_comprobante();

-- RN-09: No se puede vender más de lo que hay en stock de la sala.
CREATE OR REPLACE FUNCTION trg_validar_stock_venta() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    id_sala_origen INTEGER;
    cantidad_stock_disponible_en_sala INTEGER;
BEGIN
    SELECT id_sala INTO id_sala_origen 
    FROM comprobante 
    WHERE nro_comprobante = NEW.nro_comprobante;

    cantidad_stock_disponible_en_sala := fn_stock_sala(id_sala_origen, NEW.cod_vino);

    IF cantidad_stock_disponible_en_sala < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente en la sala % para el vino %. Disponible: %, Solicitado: %',
            id_sala_origen, NEW.cod_vino, cantidad_stock_disponible_en_sala, NEW.cantidad;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_validar_stock
BEFORE INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_validar_stock_venta();


CREATE OR REPLACE FUNCTION trg_actualizar_venta() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    id_sala_origen INTEGER;
BEGIN
    SELECT id_sala INTO id_sala_origen 
    FROM comprobante 
    WHERE nro_comprobante = NEW.nro_comprobante;

    UPDATE stock_sala
    SET cantidad = cantidad - NEW.cantidad
    WHERE id_sala = id_sala_origen AND cod_vino = NEW.cod_vino;

    UPDATE comprobante
    SET total = fn_total_comprobante(NEW.nro_comprobante)
    WHERE nro_comprobante = NEW.nro_comprobante;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_actualizar_venta
AFTER INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_actualizar_venta();

-- RN-10 y RN-11: Control de transiciones de estado y alta en "en_confeccion"
CREATE OR REPLACE FUNCTION trg_documento_nace_en_confeccion() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado != 'en_confeccion' THEN
        RAISE EXCEPTION 'Los documentos deben iniciar en "en_confeccion".';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ingreso_alta_estado
BEFORE INSERT ON ingreso
FOR EACH ROW EXECUTE FUNCTION trg_documento_nace_en_confeccion();

CREATE TRIGGER trg_transferencia_alta_estado
BEFORE INSERT ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_documento_nace_en_confeccion();


CREATE OR REPLACE FUNCTION trg_control_estados() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.estado = 'en_confeccion' AND NEW.estado NOT IN ('en_confeccion', 'terminado') THEN
        RAISE EXCEPTION 'Transición inválida. De "en_confeccion" solo pasa a "terminado"';
    ELSIF OLD.estado = 'terminado' AND NEW.estado NOT IN ('terminado', 'procesado') THEN
        RAISE EXCEPTION 'Transición inválida. De "terminado" solo pasa a "procesado"';
    ELSIF OLD.estado = 'procesado' AND NEW.estado != 'procesado' THEN
        RAISE EXCEPTION 'Un documento "procesado" no puede cambiar de estado';
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


-- RN-11: Fecha de confección actual e inmodificable para transferencias
CREATE OR REPLACE FUNCTION trg_fecha_transferencia() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
            RAISE EXCEPTION 'La fecha de confección no se puede modificar.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_fecha_transferencia();


-- RN-12: Un documento que no está en confección no admite modificaciones
CREATE OR REPLACE FUNCTION trg_bloqueo_renglones_ingreso() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    estado_actual_del_ingreso estado_enum;
BEGIN
    SELECT estado INTO estado_actual_del_ingreso 
    FROM ingreso 
    WHERE cod_ingreso = COALESCE(NEW.cod_ingreso, OLD.cod_ingreso);

    IF estado_actual_del_ingreso != 'en_confeccion' THEN
        RAISE EXCEPTION 'Solo se permiten cambios en renglones cuando el ingreso está en "en_confeccion"';
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
    estado_actual_de_la_transferencia estado_enum;
BEGIN
    SELECT estado INTO estado_actual_de_la_transferencia 
    FROM transferencia 
    WHERE nro_transferencia = COALESCE(NEW.nro_transferencia, OLD.nro_transferencia);

    IF estado_actual_de_la_transferencia != 'en_confeccion' THEN
        RAISE EXCEPTION 'Solo se permiten cambios en renglones cuando la transferencia está en "en_confeccion"';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_renglon_transferencia_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW EXECUTE FUNCTION trg_bloqueo_renglones_transfer();

-- RN-13: Auditoría de cambios de precio de vinos
CREATE OR REPLACE FUNCTION trg_auditar_precio_vino() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.precio IS DISTINCT FROM OLD.precio THEN
        INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
        VALUES (NEW.cod_vino, OLD.precio, NEW.precio, CURRENT_TIMESTAMP, current_user);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_vino_auditoria
AFTER UPDATE ON vino
FOR EACH ROW EXECUTE FUNCTION trg_auditar_precio_vino();