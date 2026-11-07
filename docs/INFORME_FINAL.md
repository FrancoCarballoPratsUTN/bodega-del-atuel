# Informe final: Bodegas del Atuel

Trabajo Práctico Integrador de Bases de Datos — UTN Facultad Regional San
Rafael.

## 1. Introducción y alcance

Bodegas del Atuel modela una bodega vitivinícola integrada: producción de uva,
elaboración de vino, stock por sala y depósito, clientes con distintos tipos,
ventas, ingresos, transferencias y reportes. El objetivo del trabajo no fue
construir una aplicación comercial completa, sino demostrar que **la base de
datos puede ser el centro del sistema**: que las reglas de negocio vivan en
constraints, funciones, procedimientos y triggers, y que la API y el front las
consuman sin reimplementarlas.

### 1.1. Alcance entregado

| Componente | Estado |
|---|---|
| Modelo relacional normalizado hasta 3FN | 30 tablas, 3 vistas, 2 tipos enumerados y 1 dominio. |
| Migraciones reproducibles | `db/migrations/001_esquema.sql` a `008_indices.sql`. |
| Reglas de negocio en la base | 19 `CHECK`, 4 `UNIQUE`, 37 FKs, 8 funciones, 3 procedimientos y 17 triggers. |
| Volumen de datos | 150.021 comprobantes, 500.022 renglones, 20.000 clientes, 1.007 vinos. |
| Consultas del enunciado | U1–U6, I1–I6, D1–D6 y S1–S12 resueltas y probadas. |
| API REST | 22 paths y 30 operaciones; 81 pruebas automáticas. |
| Front | Cinco pantallas contra la API real. |
| Despliegue | Supabase + Render + Cloudflare Workers, con HTTPS, CORS, backup y restauración. |
| Documentación | README, este informe, carpetas de Etapa 1 y Etapa 2, rendimiento y Etapa 8. |

### 1.2. Fuera de alcance

- Autenticación y autorización de usuarios finales. La API se protege a nivel de
  rol de base de datos, no con login HTTP.
- Diseño visual sofisticado. El front prioriza mostrar el dato y los errores de
  la base.
- Alta disponibilidad, monitoreo y backups automáticos. El despliegue usa planes
  gratuitos con las limitaciones documentadas en la Etapa 8.

### 1.3. URLs públicas

| Componente | URL |
|---|---|
| Front | <https://bodega-del-atuel-front.franco11carballo.workers.dev/> |
| API | <https://bodega-del-atuel-back.onrender.com/> |
| Salud | <https://bodega-del-atuel-back.onrender.com/salud> |
| Swagger | <https://bodega-del-atuel-back.onrender.com/docs> |

### 1.4. Stack

- PostgreSQL 17 (local en Docker y en Supabase).
- Python 3.14/3.15 + FastAPI + `psycopg` 3, sin ORM.
- React + Vite + TypeScript para el front.
- Docker Compose para el entorno local; nginx para servir el front y proxyar
  `/api`.
- Cloudflare Workers para el front y Render para la API en la nube.

## 2. Modelo de datos

El modelado completo está en la carpeta de la **Etapa 1**, que contiene los
diagramas, el diccionario y las decisiones de diseño definitivas:

| Documento | Contenido |
|---|---|
| [`Diagramas/2.Modelo Entidad Relación.pdf`](<Etapa 1_ Modelado (MER, DER, DICCIONARIO, DISEÑO)/Diagramas/2.Modelo Entidad Relación.pdf>) | Modelo entidad-relación. |
| [`Diagramas/4.Modelo Relacional.drawio.pdf`](<Etapa 1_ Modelado (MER, DER, DICCIONARIO, DISEÑO)/Diagramas/4.Modelo Relacional.drawio.pdf>) | Modelo relacional. |
| [`Diccionario de Datos - Bodegas del Atuel.xlsx`](<Etapa 1_ Modelado (MER, DER, DICCIONARIO, DISEÑO)/Diccionario de Datos - Bodegas del Atuel.xlsx>) | Diccionario de datos. |
| [`Decisones de Diseño.docx`](<Etapa 1_ Modelado (MER, DER, DICCIONARIO, DISEÑO)/Decisones de Diseño.docx>) | Decisiones de diseño justificadas por escrito. |

Los archivos editables de los diagramas son `1.ModeloEntidadRelación.drawio` y
`3.Modelo Relacional.drawio`, en la misma carpeta `Diagramas`.

## 3. Integridad y lógica en la base

La definición completa está en la carpeta de la **Etapa 2**, con la tabla de
trazabilidad regla de negocio → mecanismo → caso de prueba y la demostración de
concurrencia:

| Documento | Contenido |
|---|---|
| [`Tabla de Trazabilidad.docx`](<Etapa 2. Integridad y lógica en la base de datos /Tabla de Trazabilidad.docx>) | Trazabilidad RN → mecanismo → prueba. |
| [`Concurrencia.docx`](<Etapa 2. Integridad y lógica en la base de datos /Concurrencia.docx>) | Demostración con y sin `FOR UPDATE`. |

Los casos de prueba citados en la tabla se ejecutan con
`./tests/run_db_tests.sh` sobre `tests/db_tests.sql`.

## 4. Carga masiva

### 4.1. Catálogos y orden de carga

Los catálogos pequeños viven en `db/seed/csv/`: provincias, departamentos,
localidades, cepas, tipos de vino, presentaciones, maridajes y campañas. El
script `db/seed/seed.py` los lee y genera el resto con `Faker` y una semilla
fija (`SEED = 12345`), de modo que dos ejecuciones producen los mismos datos.

Orden de carga:

1. Geografía: provincias, departamentos y localidades.
2. Catálogos: cepas, salas, transportistas, bodegas, maridajes.
3. Producción: fincas, parcelas, lotes de uva y análisis.
4. Productos: vinos, composición y maridaje.
5. Clientes: clientes, distribuidores, exportadores y permisos.
6. Movimientos: ingresos, transferencias y comprobantes con sus renglones.
7. Stock inicial y auditoría.

El script usa `execute_values` en lotes de hasta 1.000 filas para las tablas
grandes.

### 4.2. Estrategia frente a los triggers

La carga reproducible con `seed.py` se ejecuta **con los triggers activos**. No
usa `ALTER TABLE ... DISABLE TRIGGER`. Así, si un dato generado viola una regla,
la transacción falla y se corrige el generador en lugar de cargar datos
inválidos.

La excepción es la restauración del dump (`db/seed/dump_datos.sql.gz`), que
representa datos ya validados. Ese archivo usa
`session_replication_role = replica` para restaurar sin depender del orden de
las claves foráneas y sin recalcular triggers. No es una carga de producción: es
una restauración de un estado consistente.

### 4.3. Tiempos y comparación

| Método | 2.000 registros |
|---|---:|
| Fila por fila con `cursor.execute` | 0,3166 s |
| Lote con `execute_values` | 0,1125 s |

La carga por lotes fue aproximadamente **2,8 veces más rápida**. El tiempo total
de la carga completa con triggers activos fue de aproximadamente **101,59 s**.

### 4.4. Volumen y controles

| Tabla | Filas |
|---|---:|
| `comprobante` | 150.021 |
| `renglon_comprobante` | 500.022 |
| `cliente` | 20.000 |
| `vino` | 1.007 |
| `ingreso` | 1.000 |
| `transferencia` | 1.009 |
| `lote_uva` | 600 |
| `analisis_calidad` | 1.200 |

El requisito de más de 100.000 filas se cumple en `comprobante` y en
`renglon_comprobante`.

Consultas de control ejecutadas al finalizar:

- Conteo de todas las tablas públicas, sin tablas vacías.
- Stock negativo en `stock_sala` y `stock_deposito`.
- Renglones huérfanos de comprobantes, ingresos y transferencias.
- Composiciones cuya suma no sea 100.
- Comprobantes cuyo total no coincida con la suma de sus renglones.

En la ejecución verificada, todos los controles devolvieron cero
inconsistencias.

## 5. Índices y rendimiento

### 5.1. Índices creados

`db/migrations/008_indices.sql` crea siete índices:

| Índice | Tipo | Uso |
|---|---|---|
| `idx_comprobante_fecha_sala` | Compuesto | Filtrar por fecha y agrupar por sala. |
| `idx_renglon_transferencia_vino` | FK | Filtrar renglones por vino en S4. |
| `idx_transferencia_pendientes_fecha_sala` | Parcial | Transferencias no procesadas. |
| `idx_comprobante_fecha_include_total` | `INCLUDE` | S8 con `Index Only Scan`. |
| `idx_comprobante_sala_fecha` | Compuesto + `INCLUDE` | S3 y S11. |
| `idx_renglon_comprobante_vino` | FK + `INCLUDE` | S1/S12 filtradas por vino. |
| `idx_vino_nombre_lower` | Expresión | Búsquedas `lower(nombre)`. |

Se cumplen los tipos pedidos: compuesto, parcial, sobre FK y de expresión /
`INCLUDE`.

### 5.2. Comparativa antes y después

Medición con `ANALYZE` y `EXPLAIN (ANALYZE, BUFFERS)` sobre el dataset completo:

| Consulta | Antes | Después | Mejora |
|---|---|---:|---:|
| S3: clientes por tipo en una sala | `Parallel Seq Scan` — 20,029 ms | `Index Only Scan` — 8,621 ms | 56,9 % |
| S4: salas que solicitaron un vino | `Seq Scan` — 0,557 ms | `Bitmap Index Scan` — 0,346 ms | 37,9 % |
| S8: ventas por sala del trimestre | `Parallel Seq Scan` — 18,878 ms | `Index Only Scan` — 10,535 ms | 44,2 % |

Los planes completos están en
[`docs/RENDIMIENTO_INDICES.md`](RENDIMIENTO_INDICES.md).

### 5.3. Costo de escritura

Se copió `renglon_comprobante` (500.000 filas) a una tabla temporal, con y sin
el índice por `cod_vino`:

| Configuración | Tiempo |
|---|---:|
| Solo PK | 415,757 ms |
| PK + índice por `cod_vino` | 1.010,135 ms |

El índice adicional incrementó la escritura aproximadamente **143 %**. Se
conserva porque las consultas selectivas por vino mejoran y porque el enunciado
exige medir explícitamente el costo.

### 5.4. Índice descartado y caso sin índice

- **Descartado:** `idx_comprobante_sala` (solo `id_sala`). S8 filtra por fecha,
  no por una sala concreta; el índice simple no evita el recorrido temporal.
- **No usado por el planificador:** en S1, que necesita agrupar los 500.000
  renglones para el ranking completo, PostgreSQL mantiene un `Parallel Seq
  Scan`. Leer toda la tabla es más barato que miles de búsquedas indexadas. El
  índice por vino sí se usa cuando la consulta filtra un vino específico (S4).

## 6. Consultas SQL

### 6.1. Archivos

| Archivo | Consignas | Contenido |
|---|---|---|
| `consultas/update.sql` | U1–U6 | Recalculos, aumentos, intercambio de días y descuentos. |
| `consultas/insert.sql` | I1–I6 | Coberturas, maridajes, comprobantes, bodegas, salas e ingresos. |
| `consultas/delete.sql` | D1–D6 | Borrados con `NOT EXISTS`, `CASCADE` y protección de triggers. |
| `consultas/select.sql` | S1–S12 | Rankings, divisiones, CTE, funciones de ventana y anti-joins. |

Cada archivo tiene encabezados con el código, el enunciado y la estrategia. Las
sentencias que modifican datos se prueban con `BEGIN` / control / sentencia /
`ROLLBACK`; las que no tienen candidatos en el dataset se documentan como tales.

### 6.2. Consultas más interesantes

- **S2 — división relacional:** vinos vendidos en todas las salas. Se resuelve
  contando salas distintas y comparando con el total de salas activas.
- **S10 — CTE y subconsulta correlacionada:** rendimiento kg/ha por parcela y
  campaña, comparado contra el promedio de su finca.
- **S11 — funciones de ventana:** `RANK() OVER (PARTITION BY id_sala ...)` y
  suma acumulada mensual por sala.
- **S12 — `NOT EXISTS`:** clientes que compraron todos los vinos de una bodega,
  con anti-join para detectar los que no.
- **U6 — excepción de descuento:** sube al 35 % a los exportadores con más de
  tres permisos. El `CHECK` de RN-06 admite 30 % base y 35 % para esta
  excepción.
- **D5 — borrado histórico:** usa `set_config('bda.eliminar_ingreso_procesado',
  'on', true)` dentro de la transacción para habilitar únicamente el borrado de
  ingresos procesados antiguos. El trigger sigue bloqueando cualquier otro
  borrado.
- **I3 — venta transaccional:** crea cabecera y tres renglones usando
  `fn_descuento_cliente` y `fn_calcular_subtotal`; los triggers calculan
  importes y stock. La prueba produjo 3.642,00 de subtotal, 364,20 de descuento
  y 3.277,80 de total.

### 6.3. Resultados de las pruebas

| Caso | Resultado |
|---|---|
| U1 | 150.000 comprobantes recalculados. |
| U2 | 11 empleados con más de 5 años, salario × 1,20. |
| U3 | 50 vinos de una bodega con +13 %. |
| U4 | 0 filas: la carga solo tenía salas con cierre domingo. |
| U5 | 10 vinos menos vendidos con −15 %. |
| U6 | Exportadores con más de 3 permisos al 35 %. |
| I1 | 0 inserciones: la cobertura ya existía; se verificó `ON CONFLICT`. |
| I2 | Maridaje y 80 asociaciones verificadas sin duplicados. |
| I3 | Comprobante temporal con 3 renglones y totales calculados. |
| I4 | Bodega `30999999999` creada y revertida. |
| I5 | Sala 19 en General Alvear creada y revertida. |
| I6 | Ingreso en confección de 120 botellas creado y revertido. |
| D1–D6 | Sin candidatos en la carga; sentencias ejecutadas sin error y rutas probadas dentro de la transacción. |

El detalle está en [`docs/ETAPA5_CONSULTAS.md`](ETAPA5_CONSULTAS.md).

## 7. API y front

### 7.1. Arquitectura de la API

```text
HTTP → router (Pydantic) → pool psycopg → DAO (SQL parametrizado)
     → PostgreSQL (constraints, funciones, triggers)
     → JSON
```

La API no contiene SQL en los routers ni cálculos de negocio en Python. Cada
recurso tiene su DAO; cada operación de escritura usa una transacción explícita.
Al crear un comprobante, la API inserta importes en cero y deja que PostgreSQL
los complete con sus triggers.

### 7.2. Endpoints

22 paths y 30 operaciones:

| Recurso | Rutas |
|---|---|
| Salud | `GET /salud`, `GET /health` |
| Catálogos | `GET /catalogos` |
| Vinos | `GET/POST /vinos`, `GET/PUT/DELETE /vinos/{cod}` |
| Clientes | `GET/POST /clientes`, `GET/PUT/DELETE /clientes/{id}` |
| Comprobantes | `POST /comprobantes`, `GET /comprobantes/{nro}` |
| Transferencias | `POST /transferencias`, `POST /{cod}/renglones`, `/terminar`, `/procesar` |
| Ingresos | `POST /ingresos`, `POST /{cod}/renglones`, `/terminar`, `/procesar` |
| Reportes | `top-vinos`, `ventas-por-sala`, `vinos-sin-stock`, `transportista-activo`, `trazabilidad/{cod}` |

OpenAPI está disponible en `/docs`, `/redoc` y `/openapi.json`.

### 7.3. Traducción de errores

| SQLSTATE | Situación | HTTP |
|---|---|---:|
| `23502` | `NOT NULL` violado | 422 |
| `23503` | FK violada | 409 |
| `23505` | Unique/PK duplicada | 409 |
| `23514` | `CHECK` violado | 422 |
| `22P02` | Texto inválido para un tipo | 400 |
| `P0001` | Regla de negocio (`RAISE EXCEPTION`) | 409 |
| `40001` / `40P01` | Serialización / deadlock | 503 |

Los errores `503` incluyen `"reintentar": true`. Los errores `500` no exponen
credenciales ni la cadena de conexión.

### 7.4. Pruebas

```text
81 passed (55 unitarias + 26 de integración)
Ruff: All checks passed!
```

Las pruebas de integración usan PostgreSQL real y revierten todo al finalizar.
Cubren, entre otras cosas:

- Composición que no suma 100 % → `23514` → 422.
- Descuento de cliente fuera de rango → `23514` → 422.
- Documento de cliente duplicado → `23505` → 409.
- Vino duplicado por identidad → `23505` → 409.
- Venta sin stock → rollback completo.
- Transferencia procesada sin estado terminado → `P0001` → 409.

Durante la validación se encontraron y corrigieron dos bugs reales en ambos
repositorios:

1. `list_tipos_vino` usaba `row[0]` con `dict_row`, lo que rompía
   `/catalogos`. Se cambió a `row["tipo"]`.
2. `update_cliente` actualizaba `tipo_cliente` antes de borrar el subtipo
   anterior, lo que violaba la herencia disjunta. Ahora borra el subtipo primero
   y luego actualiza el tipo, dentro de la misma transacción.

### 7.5. Inyección SQL fallida

```bash
curl --get "https://bodega-del-atuel-back.onrender.com/vinos" \
  --data-urlencode "tipo=tinto' OR 1=1 --" \
  --data-urlencode "por_pagina=10"
# {"items":[],"pagina":1,"por_pagina":10,"cantidad":0}
```

El valor se trata como texto y no devuelve filas fuera del filtro. Además, una
prueba recorre los archivos del DAO y falla si aparece `execute(f"`,
`execute(f'`, `execute(query %` o `execute(query +`.

### 7.6. Front

| Pantalla | Qué muestra |
|---|---|
| Catálogo | Listado paginado con filtros por tipo, cepa, bodega y añada; detalle con composición y maridajes. |
| Alta / Edición | Formulario con composición de cepas; muestra el error cuando los porcentajes no suman 100. |
| Nueva venta | Cliente, sala, vinos y total calculado por el backend; muestra el error de stock insuficiente. |
| Transferencias | Crear, cargar renglones y avanzar de estado con botones habilitados según el estado. |
| Tablero | Top 10 de vinos, ventas por sala del trimestre y vinos sin stock en una sala. |

El front no calcula totales, descuentos ni stock: solo formatea lo que devuelve
la API y muestra los mensajes de error tal como llegan. La URL base se configura
con `VITE_API_URL` en Cloudflare y con el proxy `/api` de nginx en local.

### 7.7. Docker Compose

Un solo comando levanta los tres servicios:

```bash
docker compose up --build
```

| Servicio | Imagen | Puerto |
|---|---|---:|
| `db` | PostgreSQL 17 | 5433 |
| `api` | FastAPI + Uvicorn | 8000 |
| `front` | nginx + build de Vite | 8080 |

La base aplica las migraciones `001`–`008` en orden y luego carga
`db/seed/dump_datos.sql.gz`. El healthcheck espera a que los datos estén
disponibles antes de arrancar la API.

## 8. Despliegue en la nube

### 8.1. Proveedores elegidos

| Componente | Elegido | Alternativa evaluada | Motivo |
|---|---|---|---|
| Base | Supabase Free | Neon Free | Ya tenía el modelo y el dump en PostgreSQL 17; 107 MB entran en 500 MB. |
| API | Render Free | Railway Free | 750 h/mes sin vencer a los 30 días; Railway da USD 1/mes tras el trial. |
| Front | Cloudflare Workers | Render Static | Sin cold start, 100.000 req/día y assets estáticos suficientes. |

Los límites verificados están en [`docs/ETAPA8_DESPLIEGUE.md`](ETAPA8_DESPLIEGUE.md).

### 8.2. Seguridad

- Conexión a Supabase con `sslmode=require` por session pooler; el puerto de la
  base no se expone directamente.
- La API usa `rol_api_lectura_escritura`, no el propietario. Prueba real: lee
  1.007 vinos y al intentar `CREATE TABLE` recibe `SQLSTATE 42501`.
- Los roles `anon` y `authenticated` de Supabase no tienen acceso a `public`.
- Secretos solo en variables de entorno del proveedor y en `.env` ignorado.
- CORS restringido al origen del front desplegado.
- Historial Git limpiado con `git-filter-repo`; no quedan contraseñas en
  commits.

### 8.3. Migraciones y datos en la nube

La base de validación `bodega_migraciones` se construyó desde cero aplicando
`001`–`008` en orden. Resultado: 30 tablas, 3 vistas, 7 índices `idx_*`, 17
triggers y 26 rutinas. Los conteos de datos coinciden con la carga local:

| Tabla | Filas |
|---|---:|
| `comprobante` | 150.021 |
| `renglon_comprobante` | 500.022 |
| `cliente` | 20.000 |
| `vino` | 1.007 |
| `ingreso` | 1.000 |
| `transferencia` | 1.009 |

### 8.4. Backup y restauración

- Backup: `pg_dump` comprimido, 8,4 MB, SHA-256
  `ab78e26f3b813a86d402c210f2d357aa4e780808a0e0695e8b4365f655cb2138`.
- Restauración: en una base nueva (`restore`) sobre PostgreSQL 17.
- Conteos origen vs. restauración: idénticos en todas las tablas verificadas
  (150.021 / 500.022 / 20.000 / 1.007 / 1.000 / 1.009 / 600 / 1.200).

### 8.5. Regla comprobada en la nube

Un bloque PL/pgSQL intentó vender una botella de un vino con stock 0 en la sala
1 de `bodega_migraciones`:

```text
NOTICE:  OK: trigger rechazo venta sin stock
         (SQLSTATE P0001, sala 1, vino 1):
         Stock insuficiente en la sala 1 para el vino 1.
         Disponible: 0, Solicitado: 1
```

La misma regla funciona en local y en la nube.

### 8.6. CORS y URLs

Preflight real contra la API desplegada:

```text
HTTP/2 200
access-control-allow-origin: https://bodega-del-atuel-front.franco11carballo.workers.dev
access-control-allow-methods: DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT, QUERY
access-control-allow-headers: content-type
```

`GET /salud` responde `200` con `{"status":"ok","database":"available"}` y el
front responde `200`.

## 9. Conclusiones

### 9.1. Dificultades encontradas

1. **Herencia disjunta de clientes.** Mantener sincronizados `cliente`,
   `distribuidor` y `exportador` exigió triggers de consistencia y un orden
   cuidadoso en el `UPDATE`. El bug de `update_cliente` apareció justamente al
   probar el cambio de tipo.
2. **Constraints diferidas.** La composición que debe sumar 100 % no puede
   validarse fila por fila: se resolvió con un constraint trigger diferido y
   `SET CONSTRAINTS ALL IMMEDIATE` antes de responder desde la API.
3. **Orden de triggers.** El trigger que descuenta stock y el que valida stock
   deben ejecutarse en el orden correcto (`BEFORE` valida, `AFTER` descuenta).
   La concurrencia se resolvió con `FOR UPDATE`.
4. **Restauración del dump.** Cargar 500.000 renglones con triggers activos es
   lento y sensible al orden de FKs. Para la restauración se usó
   `session_replication_role = replica`, manteniendo los triggers activos en la
   carga reproducible.
5. **Secretos en el historial.** No alcanzaba con borrar los archivos: hubo que
   reescribir el historial con `git-filter-repo` y verificar con `git log -S`.
6. **Planes gratuitos.** El cold start de Render y la pausa de Supabase son
   limitaciones reales que se documentaron y se mitigan abriendo el front antes
   de la defensa.

### 9.2. Decisiones que cambiarían

- **Separar producción de validación desde el inicio.** Tener dos bases en
  Supabase funcionó, pero complicó la evidencia. Un proyecto de staging
  separado habría sido más limpio.
- **Usar una herramienta de migraciones.** Los archivos SQL en orden funcionan,
  pero un runner con tabla de versiones evitaría depender de recordar el orden.
- **Agregar autenticación.** El alcance del TPI no la exige, pero una API
  pública sin login solo es aceptable en un contexto académico.
- **Automatizar backups.** El backup se generó y validó manualmente; un cron con
  retención sería el siguiente paso.
- **Corregir el trigger de borrado en cascada.** `trg_actualizar_venta` falla si
  se borra una cabecera antes que sus renglones porque no encuentra la fila
  padre. La API nunca borra comprobantes, pero el trigger podría hacerse más
  robusto.

### 9.3. Aprendizajes

- Las reglas de negocio en la base no son un obstáculo para la API: son su red
  de seguridad. La API puede confiar en que PostgreSQL nunca va a aceptar un
  total inconsistente o un stock negativo.
- Un `CHECK` y un trigger no son intercambiables: el `CHECK` protege siempre,
  el trigger da el mensaje de negocio y serializa la operación.
- Medir con `EXPLAIN (ANALYZE, BUFFERS)` cambia decisiones. Índices que parecían
  obvios no se usan en consultas de baja selectividad, y el costo de escritura
  es real.
- La reproducibilidad es parte del trabajo: migraciones en orden, semilla fija,
  dump restaurable y Compose con un solo comando.
- Documentar los límites de los planes gratuitos es tan importante como
  desplegar: el sistema funciona, pero con cold starts y pausas previsibles.

## Anexo: lista de control de la entrega

| Ítem | Estado |
|---|---|
| Repositorio con commits y sin secretos | Cumplido; historial reescrito y verificado. |
| `docker compose up` levanta base, API y front | Cumplido. |
| Migraciones en orden sobre base vacía | Cumplido en local y en `bodega_migraciones`. |
| Mínimos de constraints, funciones, procedimientos, triggers, vistas e índices | Cumplido. |
| Más de 100.000 filas y carga reproducible | Cumplido (150.021 comprobantes). |
| Consultas de la sección 8 resueltas y probadas | Cumplido. |
| Versión en la nube activa con HTTPS | Cumplido. |
| Backup restaurado en base nueva | Cumplido con conteos idénticos. |
| Informe final y README completos | Cumplido. |
| Defensa oral preparada | Pendiente de cada integrante. |
