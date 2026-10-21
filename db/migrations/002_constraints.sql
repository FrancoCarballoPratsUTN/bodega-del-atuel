-- Garantiza que cualquier campo definido como cuit_dom tenga exactamente 11 dígitos.
ALTER DOMAIN cuit_dom ADD CONSTRAINT chk_cuit_formato CHECK (VALUE ~ '^\d{11}$');


--VALORES POR DEFECTO
ALTER TABLE cliente ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;

ALTER TABLE ingreso ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE transferencia ALTER COLUMN estado SET DEFAULT 'en_confeccion';


-- RESTRICCIONES DE UNICIDAD
-- RN-04: Una parcela se cosecha como máximo una vez por campaña.
ALTER TABLE lote_uva ADD CONSTRAINT uq_cosecha_parcela UNIQUE (id_finca, nro_parcela, campania);

-- El vino no puede repetirse en nombre, añada y volumen.
ALTER TABLE vino ADD CONSTRAINT uq_vino_identidad UNIQUE (nombre, aniada, volumen);

-- El CUIT del transportista debe ser único (ya que su PK es un código serial).
ALTER TABLE transportista ADD CONSTRAINT uq_transp_cuit UNIQUE (cuit);

-- Evita clientes duplicados en el sistema mediante su documento natural.
ALTER TABLE cliente ADD CONSTRAINT uq_cliente_doc UNIQUE (tipo_doc, nro_doc);


--RESTRICCIONES DE CHECK
-- RN-15 y RN-01: El precio, volumen, y las superficies deben ser estrictamente positivos.
ALTER TABLE vino ADD CONSTRAINT chk_vino_precio CHECK (precio > 0), ADD CONSTRAINT chk_vino_volumen CHECK (volumen > 0);

ALTER TABLE finca ADD CONSTRAINT chk_finca_superficie CHECK (superficie > 0);

ALTER TABLE parcela ADD CONSTRAINT chk_parcela_superficie CHECK (superficie > 0);

ALTER TABLE lote_uva ADD CONSTRAINT chk_lote_kg CHECK (kg > 0);

-- RN-15: La graduación alcohólica debe estar en el rango legal permitido.
ALTER TABLE vino ADD CONSTRAINT chk_vino_graduacion CHECK (graduacion >= 5 AND graduacion <= 20);

-- RN-09: El stock inventariado jamás puede ser negativo (puede ser cero si se agotó).
ALTER TABLE stock_sala ADD CONSTRAINT chk_stock_sala_positivo CHECK (cantidad >= 0);

ALTER TABLE stock_deposito ADD CONSTRAINT chk_stock_deposito_positivo CHECK (cantidad >= 0);

-- Cantidades de movimiento logístico o ventas siempre deben ser de al menos 1 botella.
ALTER TABLE renglon_comprobante ADD CONSTRAINT chk_rcomp_cantidad CHECK (cantidad > 0);

ALTER TABLE renglon_ingreso ADD CONSTRAINT chk_ring_cantidad CHECK (cantidad > 0);

ALTER TABLE renglon_transferencia ADD CONSTRAINT chk_rtransf_cantidad CHECK (cantidad > 0);

-- Validación lógica para que un porcentaje en la composición no exceda el 100%.
ALTER TABLE composicion ADD CONSTRAINT chk_composicion_porcentaje CHECK (porcentaje > 0 AND porcentaje <= 100);

-- RN-07 (CHECK ENTRE COLUMNAS): El vencimiento debe ser posterior a la fecha de emisión.
ALTER TABLE permiso_exportacion ADD CONSTRAINT chk_permiso_fechas CHECK (fecha_vencimiento > fecha_emision);
