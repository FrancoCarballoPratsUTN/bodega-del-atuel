-- Procedimiento 1: sp_procesar_transferencia
-- Propósito: Descuenta los vinos del depósito central y los suma a la 
--            sala de ventas destino, cambiando el estado a 'Procesado'.

CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro_transferencia INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado VARCHAR;
    v_id_sala INTEGER;
    r_renglon RECORD;
BEGIN
    SELECT estado, id_sala INTO v_estado, v_id_sala 
    FROM transferencia 
    WHERE nro_transferencia = p_nro_transferencia;
    
    IF v_estado = 'Procesado' THEN
        RAISE EXCEPTION 'La transferencia % ya ha sido procesada previamente.', p_nro_transferencia;
    END IF;
    

    FOR r_renglon IN (SELECT cod_vino, cantidad FROM renglon_transferencia WHERE nro_transferencia = p_nro_transferencia) 
    LOOP

        UPDATE stock_deposito 
        SET cantidad = cantidad - r_renglon.cantidad
        WHERE cod_vino = r_renglon.cod_vino;
        

        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (v_id_sala, r_renglon.cod_vino, r_renglon.cantidad)
        ON CONFLICT (id_sala, cod_vino) 
        DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;
    END LOOP;
    

    UPDATE transferencia 
    SET estado = 'procesado' 
    WHERE nro_transferencia = p_nro_transferencia;
    
END;
$$;



-- Procedimiento: sp_actualizar_precios_cepa
-- Propósito: Aumenta masivamente el precio de todos los vinos que contengan
--            una cepa específica en su composición (ej. Malbec).

CREATE OR REPLACE PROCEDURE sp_actualizar_precios_cepa(
    p_id_cepa INTEGER, 
    p_porcentaje_aumento NUMERIC
)
LANGUAGE plpgsql
AS $$
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
    

END;
$$;
