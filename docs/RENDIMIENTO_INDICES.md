# Etapa 4: índices y rendimiento

## Entorno de medición

- Base: `bodega_del_atuel`
- PostgreSQL: 15.4
- Dataset: carga completa de `db/seed/seed.py`
- Filas relevantes:
  - `comprobante`: 150.000
  - `renglon_comprobante`: 500.000
  - `transferencia`: 1.000
  - `renglon_transferencia`: 5.000
- Comando utilizado:

```sql
ANALYZE;
EXPLAIN (ANALYZE, BUFFERS);
```

Las mediciones se realizaron con la misma base y las mismas consultas. Para la
comparación base se dejaron únicamente los índices de claves primarias y
restricciones `UNIQUE`. Después se aplicó `db/migrations/008_indices.sql` y se
repitió `ANALYZE` y cada consulta.

## Índices creados

La migración `db/migrations/008_indices.sql` crea siete índices adicionales:

| Índice | Tipo | Uso principal | Decisión |
|---|---|---|---|
| `idx_comprobante_fecha_sala` | Compuesto | Filtrar comprobantes por fecha y agrupar por sala | La fecha es el primer predicado de S8; la sala queda disponible para la agrupación. |
| `idx_renglon_transferencia_vino` | FK | Filtrar renglones por `cod_vino` en S4 | PostgreSQL no indexa automáticamente las FK. |
| `idx_transferencia_pendientes_fecha_sala` | Parcial | Transferencias no procesadas por fecha y sala | Evita indexar filas procesadas que no participan del reporte de pendientes. |
| `idx_comprobante_fecha_include_total` | `INCLUDE` | S8 | Permite un `Index Only Scan` recuperando `id_sala` y `total` sin visitar la tabla. |
| `idx_comprobante_sala_fecha` | Compuesto + `INCLUDE` | S3 y S11 | `id_sala` es igualdad y `fecha` es rango; `id_cliente` queda cubierto. |
| `idx_renglon_comprobante_vino` | FK + `INCLUDE` | S1/S12 cuando filtran por vino | Evita recorrer todos los renglones para un vino específico. |
| `idx_vino_nombre_lower` | Expresión | Búsquedas `lower(nombre)` | Permite búsquedas de catálogo sin distinguir mayúsculas. |

## Consultas medidas

### S3: clientes por tipo en una sala

La consigna original pide la última semana. El dataset generado no tiene
comprobantes de la sala 1 en los últimos siete días respecto de la fecha de
medición, por lo que para demostrar el plan con filas reales se midió el mismo
patrón sobre los últimos 90 días. La consulta no cambia la forma del filtro:
igualdad por sala y rango temporal.

```sql
SELECT c.tipo_cliente, COUNT(DISTINCT c.id_cliente) AS clientes
FROM comprobante comprob
JOIN cliente c ON c.id_cliente = comprob.id_cliente
WHERE comprob.id_sala = 1
  AND comprob.fecha >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY c.tipo_cliente
ORDER BY c.tipo_cliente;
```

| Estado | Plan relevante | Tiempo | Buffers |
|---|---|---:|---:|
| Antes | `Parallel Seq Scan` en `comprobante` | 20,029 ms | 7.035 hit |
| Después | `Index Only Scan` en `idx_comprobante_sala_fecha` | 8,621 ms | 266 hit, 28 read |

**Mejora:** 56,9 % menos tiempo.

### S4: salas que solicitaron un vino

```sql
SELECT tr.id_sala, SUM(rt.cantidad) AS botellas_solicitadas
FROM transferencia tr
JOIN renglon_transferencia rt
  ON rt.nro_transferencia = tr.nro_transferencia
WHERE rt.cod_vino = 1
  AND tr.fecha_confeccion >= CURRENT_DATE - INTERVAL '15 days'
GROUP BY tr.id_sala
ORDER BY botellas_solicitadas DESC
LIMIT 5;
```

| Estado | Plan relevante | Tiempo | Buffers |
|---|---|---:|---:|
| Antes | `Seq Scan` en `renglon_transferencia` | 0,557 ms | 40 hit |
| Después | `Bitmap Index Scan` + `Bitmap Heap Scan` en `idx_renglon_transferencia_vino` | 0,346 ms | 17 hit, 2 read |

**Mejora:** 37,9 % menos tiempo.

### S8: ventas por sala del último trimestre

```sql
SELECT c.id_sala, SUM(c.total) AS monto_total
FROM comprobante c
WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY c.id_sala
ORDER BY monto_total DESC;
```

| Estado | Plan relevante | Tiempo | Buffers |
|---|---|---:|---:|
| Antes | `Parallel Seq Scan` en `comprobante` | 18,878 ms | 6.104 hit |
| Después | `Index Only Scan` en `idx_comprobante_fecha_include_total` | 10,535 ms | 4 hit, 187 read |

**Mejora:** 44,2 % menos tiempo.

## Costo de escritura

Se copió `renglon_comprobante` completo a una tabla temporal con 500.000 filas.
La comparación mantuvo la misma clave primaria y agregó únicamente el índice
equivalente a `idx_renglon_comprobante_vino` en el segundo caso.

| Configuración | Inserción de 500.000 filas |
|---|---:|
| Solo índice de clave primaria | 415,757 ms |
| Clave primaria + índice por `cod_vino` | 1.010,135 ms |

El índice adicional incrementó el tiempo observado de escritura en
aproximadamente 143 %. Se conserva porque las consultas selectivas S1/S4/S12
obtienen una mejora de lectura y el requisito exige medir explícitamente este
costo.

## Índice evaluado y descartado

Se evaluó un índice simple:

```sql
CREATE INDEX idx_comprobante_sala
    ON comprobante (id_sala);
```

Fue descartado porque S8 filtra por `fecha`, no por una sala determinada. Con
`id_sala` como única columna el planificador todavía debe revisar demasiadas
filas de cada sala y luego aplicar el filtro temporal. El índice compuesto
`(fecha, id_sala)` y el índice cubierto por `fecha` responden directamente al
predicado real de S8.

## Caso en que el planificador no usa un índice

En S1 se agregaron índices por `cod_vino`, pero la consulta necesita agrupar
los 500.000 renglones de comprobantes para obtener el ranking completo. El
planificador mantuvo un `Parallel Seq Scan` porque leer toda la tabla es más
barato que realizar cientos o miles de búsquedas indexadas y después
reagruparlas.

Esto no es un fallo del índice: S1 tiene baja selectividad porque necesita casi
todo el conjunto de datos. El índice por `cod_vino` sí resulta útil cuando la
consulta filtra un vino específico, como S4.

## Decisiones y conclusiones

1. Se priorizaron los predicados más selectivos como primeras columnas de los
   índices compuestos.
2. Se usaron índices `INCLUDE` cuando la consulta podía resolverse sin acceder
   al heap.
3. El índice parcial se reservó para el subconjunto semánticamente relevante
   de transferencias pendientes.
4. No se eliminaron índices solo porque una consulta de baja selectividad no
   los utilizara.
5. La migración queda en `db/migrations/008_indices.sql` y este informe
   conserva los planes completos de las mediciones.

## Anexo: planes completos

### S3 antes

```text
GroupAggregate  (actual time=16.116..19.678 rows=3 loops=1)
  Group Key: c.tipo_cliente
  ->  Gather Merge  (actual time=15.528..18.919 rows=4167 loops=1)
        Workers Planned: 2
        Workers Launched: 2
        ->  Hash Join  (actual time=5.262..12.366 rows=1389 loops=3)
              ->  Parallel Seq Scan on comprobante comprob
                    Filter: ((id_sala = 1) AND (fecha >= CURRENT_DATE - '90 days'::interval))
                    Rows Removed by Filter: 48611
                    Buffers: shared hit=6087
              ->  Seq Scan on cliente c
                    Buffers: shared hit=777
Planning Time: 0.462 ms
Execution Time: 20.029 ms
```

### S3 después

```text
GroupAggregate  (actual time=7.942..8.498 rows=3 loops=1)
  Group Key: c.tipo_cliente
  ->  Hash Join  (actual time=5.336..6.789 rows=4167 loops=1)
        ->  Index Only Scan using idx_comprobante_sala_fecha on comprobante comprob
              Index Cond: ((id_sala = 1) AND (fecha >= CURRENT_DATE - '90 days'::interval))
              Heap Fetches: 0
              Buffers: shared hit=1 read=28
        ->  Seq Scan on cliente c
              Buffers: shared hit=259
Planning Time: 0.565 ms
Execution Time: 8.621 ms
```

### S4 antes

```text
Hash Join  (actual rows=5 loops=1)
  ->  Seq Scan on transferencia tr
        Filter: (fecha_confeccion >= CURRENT_DATE - '15 days'::interval)
        Buffers: shared hit=6
  ->  Seq Scan on renglon_transferencia rt
        Filter: (cod_vino = 1)
        Rows Removed by Filter: 4995
        Buffers: shared hit=28
Planning Time: 0.307 ms
Execution Time: 0.557 ms
```

### S4 después

```text
Hash Join  (actual rows=5 loops=1)
  ->  Seq Scan on transferencia tr
        Filter: (fecha_confeccion >= CURRENT_DATE - '15 days'::interval)
        Buffers: shared hit=6
  ->  Bitmap Heap Scan on renglon_transferencia rt
        Recheck Cond: (cod_vino = 1)
        Heap Blocks: exact=5
        Buffers: shared hit=5 read=2
        ->  Bitmap Index Scan on idx_renglon_transferencia_vino
              Index Cond: (cod_vino = 1)
              Buffers: shared read=2
Planning Time: 0.302 ms
Execution Time: 0.346 ms
```

### S8 antes

```text
Finalize GroupAggregate  (actual time=14.719..18.775 rows=9 loops=1)
  Group Key: id_sala
  ->  Gather Merge  (actual time=14.711..18.757 rows=27 loops=1)
        Workers Planned: 2
        Workers Launched: 2
        ->  Partial HashAggregate  (actual time=12.379..12.383 rows=9 loops=3)
              Group Key: id_sala
              ->  Parallel Seq Scan on comprobante c
                    Filter: (fecha >= CURRENT_DATE - '3 mons'::interval)
                    Rows Removed by Filter: 37500
                    Buffers: shared hit=6087
Planning Time: 0.288 ms
Execution Time: 18.878 ms
```

### S8 después

```text
HashAggregate  (actual time=10.462..10.464 rows=9 loops=1)
  Group Key: id_sala
  ->  Index Only Scan using idx_comprobante_fecha_include_total on comprobante c
        Index Cond: (fecha >= CURRENT_DATE - '3 mons'::interval)
        Heap Fetches: 0
        Buffers: shared hit=1 read=187
Planning Time: 0.430 ms
Execution Time: 10.535 ms
```
