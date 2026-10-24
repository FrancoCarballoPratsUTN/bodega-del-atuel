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


-- RN-05: Todo vino debe tener al menos una fila de composicion que sume 100.
CREATE OR REPLACE FUNCTION trg_validar_composicion_vino() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_suma NUMERIC;
BEGIN
    SELECT COALESCE(SUM(porcentaje), 0) INTO v_suma
    FROM composicion
    WHERE cod_vino = NEW.cod_vino;

    IF v_suma != 100 THEN
        RAISE EXCEPTION 'El vino % debe tener una composición que sume exactamente 100 (RN-05). Suma actual: %', NEW.cod_vino, v_suma;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_vino_composicion_obligatoria
AFTER INSERT ON vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_validar_composicion_vino();


-- RN-08: El total del comprobante se calcula a partir de los renglones. No se carga a mano.
CREATE OR REPLACE FUNCTION trg_calcular_subtotal_renglon() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_pct NUMERIC;
BEGIN
    IF NEW.descuento < 0 THEN
        RAISE EXCEPTION 'El descuento del renglón no puede ser negativo (RN-15)' USING ERRCODE = '23514';
    END IF;
    -- RN-06: el descuento del renglón se deriva del tipo de cliente.
    SELECT fn_descuento_cliente(c.id_cliente) INTO v_pct
    FROM comprobante c
    WHERE c.nro_comprobante = NEW.nro_comprobante;

    v_pct := COALESCE(v_pct, 0);
    NEW.descuento := ROUND((NEW.cantidad * NEW.precio_unitario) * v_pct / 100.0, 2);
    NEW.subtotal := fn_calcular_subtotal(NEW.cantidad, NEW.precio_unitario, NEW.descuento);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_calcula_subtotal
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_calcular_subtotal_renglon();


CREATE OR REPLACE FUNCTION trg_comprobante_calcula_importes() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.subtotal := COALESCE((SELECT SUM(cantidad * precio_unitario) FROM renglon_comprobante WHERE nro_comprobante = NEW.nro_comprobante), 0);
    NEW.descuento := COALESCE((SELECT SUM(descuento) FROM renglon_comprobante WHERE nro_comprobante = NEW.nro_comprobante), 0);
    NEW.total     := COALESCE((SELECT SUM(subtotal) FROM renglon_comprobante WHERE nro_comprobante = NEW.nro_comprobante), 0);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comprobante_calcula_importes
BEFORE INSERT OR UPDATE ON comprobante
FOR EACH ROW EXECUTE FUNCTION trg_comprobante_calcula_importes();


-- RN-09: No se puede vender más de lo que hay en stock de la sala.
CREATE OR REPLACE FUNCTION trg_validar_stock_venta() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_id_sala INTEGER;
    v_stock INTEGER;
    v_disponible INTEGER;
BEGIN
    SELECT id_sala INTO v_id_sala
    FROM comprobante
    WHERE nro_comprobante = NEW.nro_comprobante;

    SELECT cantidad INTO v_stock
    FROM stock_sala
    WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino
    FOR UPDATE;

    v_stock := COALESCE(v_stock, 0);

    IF TG_OP = 'INSERT' THEN
        IF v_stock < NEW.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente en la sala % para el vino %. Disponible: %, Solicitado: %',
                v_id_sala, NEW.cod_vino, v_stock, NEW.cantidad;
        END IF;
    ELSE
        -- En UPDATE no se puede aumentar la cantidad si no hay stock suficiente
        IF NEW.cantidad > OLD.cantidad THEN
            IF v_stock < (NEW.cantidad - OLD.cantidad) THEN
                RAISE EXCEPTION 'Stock insuficiente en la sala % para el vino %. Disponible: %, Solicitado: %',
                    v_id_sala, NEW.cod_vino, v_stock, (NEW.cantidad - OLD.cantidad);
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_validar_stock
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_validar_stock_venta();


CREATE OR REPLACE FUNCTION trg_actualizar_venta() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_id_sala INTEGER;
    v_delta INTEGER;
    v_vino INTEGER;
    v_comp INTEGER;
BEGIN
    v_comp := COALESCE(NEW.nro_comprobante, OLD.nro_comprobante);
    v_vino := COALESCE(NEW.cod_vino, OLD.cod_vino);

    SELECT id_sala INTO v_id_sala
    FROM comprobante
    WHERE nro_comprobante = v_comp;

    IF TG_OP = 'INSERT' THEN
        v_delta := -NEW.cantidad;
    ELSIF TG_OP = 'UPDATE' THEN
        v_delta := OLD.cantidad - NEW.cantidad;
    ELSE
        v_delta := OLD.cantidad;
    END IF;

    IF v_delta <> 0 THEN
        UPDATE stock_sala
        SET cantidad = cantidad + v_delta
        WHERE id_sala = v_id_sala AND cod_vino = v_vino;

        IF NOT FOUND THEN
            INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
            VALUES (v_id_sala, v_vino, v_delta);
        END IF;
    END IF;

    PERFORM fn_actualizar_importes_comprobante(v_comp);

    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_renglon_actualizar_venta
AFTER INSERT OR UPDATE OR DELETE ON renglon_comprobante
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
        RAISE EXCEPTION 'Transición inválida (RN-10/RN-11): de "en_confeccion" solo se pasa a "terminado"';
    ELSIF OLD.estado = 'terminado' AND NEW.estado NOT IN ('terminado', 'procesado') THEN
        RAISE EXCEPTION 'Transición inválida (RN-10/RN-11): de "terminado" solo se pasa a "procesado"';
    ELSIF OLD.estado = 'procesado' AND NEW.estado != 'procesado' THEN
        RAISE EXCEPTION 'Transición inválida (RN-10/RN-11): un documento "procesado" no puede cambiar de estado';
    ELSIF OLD.estado = 'terminado' AND NEW.estado = 'procesado'
          AND current_setting('bda.procesar', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'El paso a "procesado" solo puede realizarse mediante sp_procesar_ingreso / sp_procesar_transferencia (RN-10/RN-11)';
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
    borrado_historico_permitido BOOLEAN;
BEGIN
    SELECT estado INTO estado_actual_del_ingreso
    FROM ingreso
    WHERE cod_ingreso = COALESCE(NEW.cod_ingreso, OLD.cod_ingreso);

    borrado_historico_permitido :=
        current_setting('bda.eliminar_ingreso_procesado', true) = 'on';

    IF TG_OP = 'DELETE' THEN
        IF NOT borrado_historico_permitido
           AND estado_actual_del_ingreso IS DISTINCT FROM 'en_confeccion' THEN
            RAISE EXCEPTION 'Solo se permiten cambios en renglones cuando el ingreso está en "en_confeccion"';
        END IF;
    ELSIF estado_actual_del_ingreso IS DISTINCT FROM 'en_confeccion' THEN
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
