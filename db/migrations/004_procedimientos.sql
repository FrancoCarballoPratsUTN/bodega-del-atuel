-- Procedimiento: sp_procesar_ingreso
-- Propósito: Procesa un ingreso terminado, suma al depósito y pasa a 'procesado' (RN-10).
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_cod_ingreso INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado estado_enum;
    r RECORD;
BEGIN
    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = p_cod_ingreso FOR UPDATE;
    IF v_estado IS DISTINCT FROM 'terminado' THEN
        RAISE EXCEPTION 'El ingreso % no existe o no está en estado "terminado" (RN-10).', p_cod_ingreso;
    END IF;

    PERFORM set_config('bda.procesar', 'on', true);

    FOR r IN SELECT cod_vino, cantidad FROM renglon_ingreso WHERE cod_ingreso = p_cod_ingreso LOOP
        INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (r.cod_vino, r.cantidad)
        ON CONFLICT (cod_vino) DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;
    END LOOP;

    UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = p_cod_ingreso;
END $$;


-- Procedimiento: sp_procesar_transferencia
-- Propósito: Descuenta los vinos del depósito central y los suma a la 
--            sala de ventas destino, cambiando el estado a 'procesado' (RN-11).
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro_transferencia INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado estado_enum;
    v_id_sala INTEGER;
    r RECORD;
    v_stock INTEGER;
BEGIN
    SELECT estado, id_sala INTO v_estado, v_id_sala
    FROM transferencia
    WHERE nro_transferencia = p_nro_transferencia FOR UPDATE;

    IF v_estado IS DISTINCT FROM 'terminado' THEN
        RAISE EXCEPTION 'La transferencia % no existe o no está en estado "terminado" (RN-11).', p_nro_transferencia;
    END IF;

    FOR r IN SELECT cod_vino, cantidad FROM renglon_transferencia WHERE nro_transferencia = p_nro_transferencia LOOP
        SELECT cantidad INTO v_stock FROM stock_deposito WHERE cod_vino = r.cod_vino FOR UPDATE;
        IF v_stock IS NULL OR v_stock < r.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente en el depósito central para el vino % (RN-11). Disponible: %, Solicitado: %',
                r.cod_vino, COALESCE(v_stock, 0), r.cantidad;
        END IF;
    END LOOP;

    PERFORM set_config('bda.procesar', 'on', true);

    FOR r IN SELECT cod_vino, cantidad FROM renglon_transferencia WHERE nro_transferencia = p_nro_transferencia LOOP
        UPDATE stock_deposito SET cantidad = cantidad - r.cantidad WHERE cod_vino = r.cod_vino;

        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (v_id_sala, r.cod_vino, r.cantidad)
        ON CONFLICT (id_sala, cod_vino)
        DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;
    END LOOP;

    UPDATE transferencia SET estado = 'procesado' WHERE nro_transferencia = p_nro_transferencia;
END $$;


-- Procedimiento: sp_actualizar_precios_cepa
-- Propósito: Aumenta masivamente el precio de todos los vinos que contengan
--            una cepa específica en su composición (ej. Malbec).
CREATE OR REPLACE PROCEDURE sp_actualizar_precios_cepa(
    p_id_cepa INTEGER, 
    p_porcentaje_aumento NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_porcentaje_aumento <= 0 THEN
        RAISE EXCEPTION 'El porcentaje de aumento debe ser mayor a 0.';
    END IF;

    UPDATE vino
    SET precio = precio + (precio * (p_porcentaje_aumento / 100.0))
    WHERE cod_vino IN (
        SELECT cod_vino 
        FROM composicion 
        WHERE id_cepa = p_id_cepa
    );
END $$;