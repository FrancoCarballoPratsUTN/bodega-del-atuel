-- Actualiza en el contenedor la función de trigger vigente en el repositorio.
-- El dump de la Etapa 5 se generó antes del ajuste de D5 (borrado histórico).
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
