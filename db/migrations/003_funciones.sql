-- Función: fn_total_comprobante
-- Propósito: Calcula el importe total de un comprobante sumando los 
--            subtotales de sus renglones y restando el descuento general.
-- Parámetros: p_nro_comprobante (INTEGER)
-- Volatilidad: STABLE (Lee datos de las tablas. El resultado es estable
--              durante la misma consulta, pero puede cambiar si la base se actualiza).

CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro_comprobante INTEGER) 
RETURNS NUMERIC AS $$
DECLARE
    v_suma_renglones NUMERIC;
    v_descuento_cabecera NUMERIC;
BEGIN

    SELECT COALESCE(descuento, 0) INTO v_descuento_cabecera
    FROM comprobante
    WHERE nro_comprobante = p_nro_comprobante;


    SELECT COALESCE(SUM(subtotal), 0) INTO v_suma_renglones
    FROM renglon_comprobante
    WHERE nro_comprobante = p_nro_comprobante;
    

    RETURN GREATEST(v_suma_renglones - v_descuento_cabecera, 0);
END;
$$ LANGUAGE plpgsql STABLE;



-- Función: fn_stock_sala
-- Propósito: Devuelve la cantidad de stock actual de un vino específico
--            en una sala de ventas determinada.
-- Parámetros: p_id_sala (INTEGER), p_cod_vino (INTEGER)
-- Volatilidad: STABLE (Lee de la tabla stock_sala).

CREATE OR REPLACE FUNCTION fn_stock_sala(p_id_sala INTEGER, p_cod_vino INTEGER) 
RETURNS INTEGER AS $$
DECLARE
    v_stock INTEGER;
BEGIN
    SELECT cantidad INTO v_stock
    FROM stock_sala
    WHERE id_sala = p_id_sala AND cod_vino = p_cod_vino;
    

    RETURN COALESCE(v_stock, 0);
END;
$$ LANGUAGE plpgsql STABLE;



-- Función: fn_descuento_cliente
-- Propósito: Obtiene el porcentaje de descuento asignado a un cliente.
-- Parámetros: p_id_cliente (INTEGER)
-- Volatilidad: STABLE (Lee de la tabla cliente).

CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente INTEGER) 
RETURNS NUMERIC AS $$
DECLARE
    v_descuento NUMERIC;
BEGIN
    SELECT descuento INTO v_descuento
    FROM cliente
    WHERE id_cliente = p_id_cliente;
    
    RETURN COALESCE(v_descuento, 0);
END;
$$ LANGUAGE plpgsql STABLE;


-- Función: fn_antiguedad_anios
-- Propósito: Calcula los años de antigüedad de una persona (empleado o cliente)
--            comparando su fecha de alta con la fecha actual del sistema.
-- Parámetros: p_fecha_inicio (DATE)
-- Volatilidad: STABLE (Depende de CURRENT_DATE, por lo que no es inmutable 
--              a lo largo de los años, pero es estable dentro de una transacción).

CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha_inicio DATE) 
RETURNS INTEGER AS $$
BEGIN

    RETURN EXTRACT(YEAR FROM age(CURRENT_DATE, p_fecha_inicio))::INTEGER;
END;
$$ LANGUAGE plpgsql STABLE;



-- Función: fn_calcular_subtotal
-- Propósito: Calcula matemáticamente el subtotal de un renglón.
-- Parámetros: p_cantidad (INT), p_precio (NUMERIC), p_descuento (NUMERIC)
-- Volatilidad: IMMUTABLE (Al no tocar ninguna tabla ni fechas del sistema, 
--              los mismos parámetros siempre arrojarán el mismo resultado exacto).

CREATE OR REPLACE FUNCTION fn_calcular_subtotal(
    p_cantidad INTEGER, 
    p_precio NUMERIC, 
    p_descuento NUMERIC
) 
RETURNS NUMERIC AS $$
BEGIN
    RETURN GREATEST((p_cantidad * p_precio) - p_descuento, 0);
END;
$$ LANGUAGE plpgsql IMMUTABLE;
