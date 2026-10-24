-- Etapa 5 - Consultas de inserción (INSERT)
-- Los ejemplos usan valores obtenidos del dataset actual.
-- Cada caso se prueba dentro de una transacción y termina con ROLLBACK.

BEGIN;

-- I1. Cubrir General Alvear con el transportista que menos ingresos trasladó
-- durante el último trimestre.
-- Parámetro del dataset: General Alvear tiene código postal 5602.
-- Estrategia: COUNT de ingresos por transportista, incluyendo transportistas
-- sin ingresos mediante LEFT JOIN; se evita duplicar la cobertura existente.
SELECT t.cod_transportista, t.razon_social,
       COUNT(i.cod_ingreso) AS ingresos_ultimo_trimestre
  FROM transportista t
  LEFT JOIN ingreso i
    ON i.cod_transportista = t.cod_transportista
   AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY t.cod_transportista, t.razon_social
 ORDER BY ingresos_ultimo_trimestre, t.cod_transportista
 LIMIT 1;

INSERT INTO transportista_cubre_localidad (cod_transportista, cp_localidad)
SELECT t.cod_transportista, 5602
  FROM transportista t
  LEFT JOIN ingreso i
    ON i.cod_transportista = t.cod_transportista
   AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY t.cod_transportista
 ORDER BY COUNT(i.cod_ingreso), t.cod_transportista
 LIMIT 1
ON CONFLICT (cod_transportista, cp_localidad) DO NOTHING;

SELECT t.razon_social, l.nombre AS localidad
  FROM transportista_cubre_localidad tc
  JOIN transportista t ON t.cod_transportista = tc.cod_transportista
  JOIN localidad l ON l.cp = tc.cp_localidad
 WHERE tc.cp_localidad = 5602;

-- I2. Crear el maridaje "cordero al disco" si existe algún tinto de 14° o más
-- y asociarlo a todos los vinos que cumplen la condición.
-- La selección se hace por tipo sin distinguir mayúsculas.
DO $$
DECLARE
    v_id_maridaje INTEGER;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM vino
         WHERE lower(tipo) = 'tinto'
           AND graduacion >= 14
    ) THEN
        SELECT id_maridaje
          INTO v_id_maridaje
          FROM maridaje
         WHERE lower(nombre) = 'cordero al disco'
         ORDER BY id_maridaje
         LIMIT 1;

        IF v_id_maridaje IS NULL THEN
            INSERT INTO maridaje (nombre, temp_servicio)
            VALUES ('cordero al disco', 16)
            RETURNING id_maridaje INTO v_id_maridaje;
        END IF;

        INSERT INTO vino_maridaje (cod_vino, id_maridaje)
        SELECT v.cod_vino, v_id_maridaje
          FROM vino v
         WHERE lower(v.tipo) = 'tinto'
           AND v.graduacion >= 14
        ON CONFLICT DO NOTHING;
    END IF;
END
$$;

SELECT m.nombre, COUNT(vm.cod_vino) AS vinos_asociados
  FROM maridaje m
  LEFT JOIN vino_maridaje vm ON vm.id_maridaje = m.id_maridaje
 WHERE lower(m.nombre) = 'cordero al disco'
 GROUP BY m.id_maridaje, m.nombre;

-- I3. Crear un comprobante con tres renglones para el cliente 3 en la sala 1.
-- Las cantidades y precios se calculan dentro de la transacción; el trigger
-- vuelve a calcular descuento y subtotal y se invoca explícitamente la función.
-- Si el dataset no tiene tres vinos con stock en sala 1, el bloque falla
-- explícitamente en lugar de crear una venta inválida.
DO $$
DECLARE
    v_nro_comprobante INTEGER;
    v_id_cliente INTEGER := 3;
    v_id_sala INTEGER := 1;
    v_pct NUMERIC;
    v_vino RECORD;
    v_cantidad INTEGER := 1;
    v_descuento NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = v_id_cliente) THEN
        RAISE EXCEPTION 'I3: no existe el cliente %', v_id_cliente;
    END IF;

    SELECT fn_descuento_cliente(v_id_cliente) INTO v_pct;

    INSERT INTO comprobante (id_cliente, id_sala, fecha, subtotal, descuento, total)
    VALUES (v_id_cliente, v_id_sala, CURRENT_TIMESTAMP, 0, 0, 0)
    RETURNING nro_comprobante INTO v_nro_comprobante;

    FOR v_vino IN
        SELECT v.cod_vino, v.precio
          FROM vino v
          JOIN stock_sala ss
            ON ss.cod_vino = v.cod_vino
           AND ss.id_sala = v_id_sala
         WHERE ss.cantidad >= v_cantidad
         ORDER BY v.cod_vino
         LIMIT 3
    LOOP
        v_descuento := ROUND(v_cantidad * v_vino.precio * v_pct / 100.0, 2);
        INSERT INTO renglon_comprobante
            (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
        VALUES
            (v_nro_comprobante, v_vino.cod_vino, v_cantidad, v_vino.precio,
             v_descuento,
             fn_calcular_subtotal(v_cantidad, v_vino.precio, v_descuento));
    END LOOP;

    IF (SELECT COUNT(*) FROM renglon_comprobante
         WHERE nro_comprobante = v_nro_comprobante) <> 3 THEN
        RAISE EXCEPTION 'I3: no fue posible seleccionar tres vinos con stock';
    END IF;

    RAISE NOTICE 'I3 creó comprobante %', v_nro_comprobante;
END
$$;

SELECT c.nro_comprobante, c.id_cliente, c.id_sala, COUNT(r.cod_vino) AS renglones,
       c.subtotal, c.descuento, c.total
  FROM comprobante c
  JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
 WHERE c.id_cliente = 3
   AND c.id_sala = 1
 GROUP BY c.nro_comprobante, c.id_cliente, c.id_sala,
          c.subtotal, c.descuento, c.total
 ORDER BY c.nro_comprobante DESC
 LIMIT 1;

-- I4. Insertar una nueva bodega.
-- CUIT elegido: se comprueba antes que no exista en el dataset.
SELECT COUNT(*) AS bodega_existente
  FROM bodega
 WHERE cuit_bodega = '30999999999';

INSERT INTO bodega (cuit_bodega, razon_social, domicilio)
VALUES ('30999999999', 'Bodega Nueva del Atuel', 'Ruta Provincial 173 km 12');

SELECT cuit_bodega, razon_social
  FROM bodega
 WHERE cuit_bodega = '30999999999';

-- I5. Insertar una nueva sala de venta en General Alvear (CP 5602).
-- El ID se toma como MAX + 1 para no colisionar con el dataset cargado.
SELECT COALESCE(MAX(id_sala), 0) + 1 AS nuevo_id_sala,
       5602 AS cp_localidad
  FROM sala_venta;

INSERT INTO sala_venta (id_sala, cp_localidad, calle, numero, dia_cierre)
SELECT COALESCE(MAX(id_sala), 0) + 1, 5602, 'Av. Libertador', 1200, 'Lunes'
  FROM sala_venta;

SELECT id_sala, cp_localidad, calle, numero, dia_cierre
  FROM sala_venta
 WHERE calle = 'Av. Libertador'
   AND numero = 1200;

-- I6. Crear un ingreso en confección de 120 botellas de un vino del dataset.
-- Se elige el primer vino ordenado por nombre, junto con su bodega y el primer
-- transportista. El trigger fuerza estado en_confeccion si se omite estado.
DO $$
DECLARE
    v_cod_ingreso INTEGER;
    v_cod_vino INTEGER;
BEGIN
    SELECT cod_vino INTO v_cod_vino
      FROM vino
     ORDER BY nombre, cod_vino
     LIMIT 1;

    INSERT INTO ingreso (cod_transportista, cuit_bodega, fecha)
    SELECT t.cod_transportista, v.cuit_bodega, CURRENT_TIMESTAMP
      FROM transportista t
      CROSS JOIN vino v
     WHERE t.cod_transportista = (
         SELECT cod_transportista FROM transportista ORDER BY cod_transportista LIMIT 1
     )
       AND v.cod_vino = v_cod_vino
    RETURNING cod_ingreso INTO v_cod_ingreso;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_cod_ingreso, v_cod_vino, 120);

    RAISE NOTICE 'I6 creó ingreso % para vino %', v_cod_ingreso, v_cod_vino;
END
$$;

SELECT i.cod_ingreso, i.estado, i.fecha, ri.cod_vino, ri.cantidad
  FROM ingreso i
  JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
 WHERE i.cod_ingreso = (SELECT MAX(cod_ingreso) FROM ingreso);

ROLLBACK;
