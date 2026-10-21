-- Función: fn_importes_comprobante
-- Propósito: Obtiene los importes calculados de un comprobante (bruto, descuento, neto).
-- Parámetros: p_nro_comprobante (INTEGER)
-- Volatilidad: STABLE
CREATE OR REPLACE FUNCTION fn_importes_comprobante(p_nro_comprobante INTEGER)
RETURNS TABLE (subtotal_bruto NUMERIC, descuento_total NUMERIC, total_neto NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(r.cantidad * r.precio_unitario), 0),
           COALESCE(SUM(r.descuento), 0),
           COALESCE(SUM(r.subtotal), 0)
      FROM renglon_comprobante r
     WHERE r.nro_comprobante = p_nro_comprobante;
$$;


-- Función: fn_total_comprobante
-- Propósito: Calcula el importe total (neto) de un comprobante sumando los 
--            subtotales de sus renglones.
-- Parámetros: p_nro_comprobante (INTEGER)
-- Volatilidad: STABLE
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro_comprobante INTEGER) 
RETURNS NUMERIC AS $$
DECLARE v_total NUMERIC;
BEGIN
    SELECT total_neto INTO v_total FROM fn_importes_comprobante(p_nro_comprobante);
    RETURN COALESCE(v_total, 0);
END;
$$ LANGUAGE plpgsql STABLE;


-- Función: fn_actualizar_importes_comprobante
-- Propósito: Recalcula y actualiza subtotal/descuento/total del comprobante.
CREATE OR REPLACE FUNCTION fn_actualizar_importes_comprobante(p_nro_comprobante INTEGER)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE comprobante c
       SET subtotal = i.subtotal_bruto,
           descuento = i.descuento_total,
           total    = i.total_neto
      FROM fn_importes_comprobante(p_nro_comprobante) i
     WHERE c.nro_comprobante = p_nro_comprobante;
END $$;



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



-- Función: fn_descuento_por_tipo
-- Propósito: Devuelve el porcentaje de descuento según el tipo de cliente (RN-06).
-- Volatilidad: IMMUTABLE
CREATE OR REPLACE FUNCTION fn_descuento_por_tipo(p_tipo_cliente TEXT)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_tipo_cliente
        WHEN 'Socio' THEN 10.00
        WHEN 'Distribuidor' THEN 20.00
        WHEN 'Exportador' THEN 30.00
        ELSE NULL
    END;
$$;


-- Función: fn_descuento_cliente
-- Propósito: Obtiene el porcentaje de descuento asignado a un cliente (RN-06).
-- Parámetros: p_id_cliente (INTEGER)
-- Volatilidad: STABLE
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente INTEGER) 
RETURNS NUMERIC AS $$
DECLARE
    v_tipo_cliente TEXT;
BEGIN
    SELECT tipo_cliente INTO v_tipo_cliente
    FROM cliente
    WHERE id_cliente = p_id_cliente;
    
    RETURN COALESCE(fn_descuento_por_tipo(v_tipo_cliente), 0);
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
