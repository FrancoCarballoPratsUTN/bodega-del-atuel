
-- Índice compuesto para S8:
-- la consulta filtra primero por fecha y luego agrupa por sala.
CREATE INDEX IF NOT EXISTS idx_comprobante_fecha_sala
    ON comprobante (fecha, id_sala);

-- Índice sobre una FK para S4:
-- PostgreSQL no crea índices automáticamente sobre cod_vino en esta tabla.
CREATE INDEX IF NOT EXISTS idx_renglon_transferencia_vino
    ON renglon_transferencia (cod_vino);

-- Índice parcial para reportes de transferencias pendientes:
-- evita indexar transferencias ya procesadas, que no participan en ese reporte.
CREATE INDEX IF NOT EXISTS idx_transferencia_pendientes_fecha_sala
    ON transferencia (fecha_confeccion, id_sala)
    WHERE estado <> 'procesado';

-- Variante INCLUDE para S8:
-- permite recuperar id_sala y total desde el índice cuando el planificador
-- puede usar un recorrido de solo índice.
CREATE INDEX IF NOT EXISTS idx_comprobante_fecha_include_total
    ON comprobante (fecha) INCLUDE (id_sala, total);

-- Índice compuesto para S3 y S11:
-- id_sala es la igualdad más selectiva y fecha restringe el período consultado.
CREATE INDEX IF NOT EXISTS idx_comprobante_sala_fecha
    ON comprobante (id_sala, fecha) INCLUDE (id_cliente, total);

-- Índice sobre la FK usada por S1/S12:
-- permite localizar rápidamente los renglones de un vino sin recorrer todos
-- los renglones de comprobantes cuando la consulta filtra por cod_vino.
CREATE INDEX IF NOT EXISTS idx_renglon_comprobante_vino
    ON renglon_comprobante (cod_vino) INCLUDE (nro_comprobante, cantidad);

-- Índice de expresión para búsquedas de catálogo sin distinguir mayúsculas.
CREATE INDEX IF NOT EXISTS idx_vino_nombre_lower
    ON vino ((lower(nombre)));
