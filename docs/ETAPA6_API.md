# Etapa 6: API REST

## 1. Objetivo y alcance

Se implementó una API REST sobre la base PostgreSQL de Bodegas del Atuel con:

- Python 3.14 y `uv`.
- FastAPI para rutas, validación de contratos y OpenAPI.
- `psycopg` 3 con pool de conexiones.
- SQL explícito y parametrizado en una capa DAO.
- PostgreSQL como fuente única de verdad para totales, descuentos, stock,
  auditoría, estados y validaciones de negocio.

La API expone el catálogo de vinos y clientes, la emisión de comprobantes, los
circuitos de transferencias e ingresos, y los reportes solicitados en la
sección 8 del TPI. No reimplementa en Python ninguna regla que ya viva en
triggers, funciones, procedimientos o restricciones de la base.

## 2. Arquitectura

```text
api/
├── Dockerfile
├── pyproject.toml
├── uv.lock
├── .env.example
└── src/bodega_api/
    ├── config.py              # Variables BDA_* y cadena de conexión
    ├── db.py                  # Pool psycopg y cierre en el lifespan
    ├── errors.py              # Traducción SQLSTATE -> HTTP
    ├── main.py                # App, routers, handlers y /health
    ├── schemas.py             # Contratos Pydantic de entrada
    ├── dao/
    │   ├── catalogos.py
    │   ├── vinos.py
    │   ├── clientes.py
    │   ├── comprobantes.py
    │   ├── movimientos.py
    │   └── reportes.py
    └── routers/
        ├── catalogos.py
        ├── vinos.py
        ├── clientes.py
        ├── comprobantes.py
        ├── movimientos.py
        └── reportes.py
```

Flujo de una petición:

```text
HTTP -> router (validación Pydantic)
     -> conexión del pool
     -> función DAO (SQL parametrizado)
     -> PostgreSQL (triggers/funciones/restricciones)
     -> serialización JSON
```

Decisiones relevantes:

- **DAO por recurso:** los routers no contienen SQL. Solo validan la entrada,
  abren una conexión y coordinan la transacción.
- **Transacciones explícitas:** toda operación de escritura usa
  `connection.transaction()`. Si PostgreSQL rechaza una operación, se revierte
  el bloque completo.
- **Sin ORM:** se usan cursores `dict_row` de `psycopg` y consultas legibles.
- **Sin cálculos de negocio en Python:** por ejemplo, al crear un comprobante se
  insertan importes en cero y PostgreSQL los completa mediante sus triggers y
  funciones. La respuesta se lee después dentro de la misma transacción.
- **Restricciones diferidas de composición:** después de reemplazar cepas o
  maridajes se ejecuta `SET CONSTRAINTS ALL IMMEDIATE` y luego
  `SET CONSTRAINTS ALL DEFERRED`, para que la validación de que la composición
  suma 100 % ocurra antes de confirmar y responder.
- **Pool global:** se crea perezosamente en `db.get_pool()` y se cierra en el
  `lifespan` de FastAPI.

## 3. Puesta en marcha

### 3.1. Local con `uv`

Requisitos: Python 3.14, `uv` y una instancia PostgreSQL con el esquema, los
datos y el rol `rol_api_lectura_escritura`.

```bash
cd api
cp .env.example .env
uv sync
uv run uvicorn bodega_api.main:app --reload
```

Comprobaciones:

```bash
uv run python --version          # Python 3.14.x
curl http://localhost:8000/health
# {"status":"ok","database":"available"}
```

Documentación interactiva:

- Swagger UI: <http://localhost:8000/docs>
- ReDoc: <http://localhost:8000/redoc>
- OpenAPI JSON: <http://localhost:8000/openapi.json>

### 3.2. Docker Compose

El `docker-compose.yml` de la raíz levanta PostgreSQL 15.4 y la API. La base se
inicializa desde `db/seed/dump_completo.sql.gz`, luego aplica roles, índices, la
versión vigente de los triggers y la contraseña del rol API.

```bash
cp .env.example .env
docker compose up -d --build
docker compose ps
curl http://localhost:8000/health
```

Servicios y puertos por defecto:

| Servicio | Contenedor | Puerto host | Puerto interno |
|---|---|---:|---:|
| `db` | PostgreSQL 15.4 | `5433` | `5432` |
| `api` | Uvicorn + FastAPI | `8000` | `8000` |

La API espera el `healthcheck` de PostgreSQL antes de arrancar. El primer
arranque tarda más porque restaura el dump completo.

Para reiniciar desde cero, incluido el volumen de datos:

```bash
docker compose down -v
docker compose up -d --build
```

Para detener sin borrar datos:

```bash
docker compose down
```

### 3.3. Front temporal de pruebas

El front se puede levantar junto con la base y la API usando el override de
pruebas. Es una configuración temporal con Vite en modo desarrollo; el
despliegue definitivo se resolverá más adelante.

```bash
docker compose -f docker-compose.yml -f docker-compose.test.yml up --build
```

| Servicio | Contenedor | Puerto host | Puerto interno |
|---|---|---:|---:|
| `front` | Node 22 + Vite | `8443` | `8443` |

El front queda disponible en <http://localhost:8443>. Vite proxya `/api` hacia
`http://api:8000` y elimina el prefijo `/api`, por lo que no se necesita CORS.
El código fuente de `front/` se monta como bind mount y `node_modules` se
conserva en un volumen nombrado (`front_node_modules`), de modo que los cambios
del front se reflejan con HMR sin reconstruir la imagen.

### 3.4. Variables de entorno

La API lee variables con prefijo `BDA_`. Los valores de `.env.example` son
locales de desarrollo.

| Variable | Default | Descripción |
|---|---|---|
| `BDA_DATABASE_HOST` | `localhost` | Host PostgreSQL. En Compose: `db`. |
| `BDA_DATABASE_PORT` | `5432` | Puerto PostgreSQL. En Compose: `5432`. |
| `BDA_DATABASE_NAME` | `bodega_del_atuel` | Nombre de la base. |
| `BDA_DATABASE_USER` | `rol_api_lectura_escritura` | Rol de aplicación. |
| `BDA_DATABASE_PASSWORD` | sin default | Obligatoria; no se versiona. |
| `BDA_DATABASE_POOL_MIN_SIZE` | `1` | Conexiones mínimas del pool. |
| `BDA_DATABASE_POOL_MAX_SIZE` | `10` | Conexiones máximas del pool. |

El Compose usa además `POSTGRES_PASSWORD`, `POSTGRES_PORT` y `API_PORT` para
parametrizar el contenedor de base y los puertos publicados.

## 4. Endpoints

Total: 21 paths y 27 operaciones HTTP (sin contar `/docs`, `/redoc` y
`/openapi.json`).

### 4.1. Salud

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/health` | Verifica que el pool puede ejecutar `SELECT 1`. |

Respuesta `200`:

```json
{"estado": "ok", "base_de_datos": "disponible"}
```

Si la base no responde, devuelve `503` con `{"error": "..."}`.

### 4.2. Catálogos

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/catalogos` | Salas, cepas y bodegas para selectores del front. |

Respuesta `200`:

```json
{
  "salas": [
    {
      "id_sala": 1,
      "calle": "San Martín",
      "numero": 100,
      "cp_localidad": 5600,
      "localidad": "San Rafael",
      "dia_cierre": "lunes",
      "activo": true
    }
  ],
  "cepas": [
    {"id_cepa": 1, "nombre": "Malbec", "tipo": "Tinta"}
  ],
  "bodegas": [
    {
      "cuit_bodega": "30050000001",
      "razon_social": "Bodega Atuel",
      "activo": true
    }
  ]
}
```

El endpoint es de solo lectura y no reemplaza los listados paginados. El front
lo usa para completar selectores sin hardcodear salas, cepas ni bodegas.

### 4.3. Vinos

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/vinos` | Listado paginado y filtrable. |
| `GET` | `/vinos/{cod_vino}` | Detalle con cepas y maridajes. |
| `POST` | `/vinos` | Alta con composición y maridajes. |
| `PUT` | `/vinos/{cod_vino}` | Modificación total. |
| `DELETE` | `/vinos/{cod_vino}` | Baja lógica (`activo = FALSE`). |

Parámetros de `GET /vinos`:

| Parámetro | Tipo | Default | Regla |
|---|---|---|---|
| `pagina` | entero | `1` | `>= 1` |
| `por_pagina` | entero | `20` | entre `1` y `100` |
| `tipo` | texto | — | Comparación sin distinguir mayúsculas. |
| `cepa` | texto | — | Debe existir en la composición del vino. |
| `bodega` | texto | — | Razón social, sin distinguir mayúsculas. |
| `aniada` | entero | — | Entre `1900` y `2100`. |

Ejemplo:

```bash
curl "http://localhost:8000/vinos?tipo=tinto&cepa=Malbec&aniada=2022&pagina=1"
```

Respuesta:

```json
{
  "items": [
    {
      "cod_vino": 1,
      "nombre": "Vino Atuel 1",
      "tipo": "tinto",
      "aniada": 2022,
      "volumen": "187.00",
      "graduacion": "10.10",
      "precio": "1207.00",
      "bodega": "Gomez, Diaz and Rios"
    }
  ],
  "pagina": 1,
  "por_pagina": 20,
  "cantidad": 1
}
```

Alta:

```json
{
  "cuit_bodega": "30050000001",
  "nombre": "Malbec Reserva",
  "tipo": "tinto",
  "aniada": 2023,
  "volumen": "750.00",
  "graduacion": "13.50",
  "precio": "8500.00",
  "cepas": [
    {"id_cepa": 1, "porcentaje": "100.00"}
  ],
  "maridajes": [1]
}
```

La respuesta `201` incluye el `cod_vino` generado y el detalle completo. En
`PUT`, `cepas` y `maridajes` son opcionales: si se omiten, no se reemplazan; si
se envían, reemplazan la composición o los maridajes actuales. La composición
debe sumar exactamente 100 %, regla validada por PostgreSQL.

El detalle de `GET /vinos/{cod_vino}` incluye `cuit_bodega`, `cepas[].id_cepa`
y `maridajes[].id_maridaje` para que el front pueda precargar el formulario de
edición sin inferir identidades por nombre.

### 4.4. Clientes

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/clientes` | Listado paginado de clientes activos. |
| `GET` | `/clientes/{id_cliente}` | Detalle con datos del subtipo. |
| `POST` | `/clientes` | Alta de Socio, Distribuidor o Exportador. |
| `PUT` | `/clientes/{id_cliente}` | Modificación, incluso cambio de subtipo. |
| `DELETE` | `/clientes/{id_cliente}` | Baja lógica. |

`GET /clientes` acepta `pagina`, `por_pagina` (máximo 100) y `busqueda`
opcional. La búsqueda compara el texto contra `nombre_razon_social` y
`nro_doc`; el front la usa porque la base contiene 20.000 clientes. El detalle
agrega `zona_cobertura` y `nro_habilitacion` para distribuidores, o
`pais_destino` para exportadores.

Ejemplo de alta de distribuidor:

```json
{
  "cp_localidad": 5601,
  "nombre_razon_social": "Distribuidora Andes S.A.",
  "tipo_doc": "CUIT",
  "nro_doc": "30712345678",
  "direccion": "Av. San Martín 100",
  "fecha_alta": "2026-10-22",
  "descuento": "10.00",
  "tipo_cliente": "Distribuidor",
  "zona_cobertura": "Mendoza",
  "nro_habilitacion": "HAB-000123"
}
```

Reglas de subtipo:

- `Distribuidor` exige `zona_cobertura` y `nro_habilitacion`.
- `Exportador` exige `pais_destino`.
- `Socio` no usa campos de subtipo.
- Al cambiar de tipo, el DAO elimina la fila del subtipo anterior y crea la
  nueva, dentro de la misma transacción.

### 4.5. Comprobantes

| Método | Ruta | Descripción |
|---|---|---|
| `POST` | `/comprobantes` | Emite una venta completa. |
| `GET` | `/comprobantes/{nro_comprobante}` | Cabecera y renglones. |

Ejemplo:

```json
{
  "id_cliente": 1,
  "id_sala": 1,
  "renglones": [
    {"cod_vino": 5, "cantidad": 2},
    {"cod_vino": 6, "cantidad": 3}
  ]
}
```

La API inserta la cabecera y los renglones; los triggers de PostgreSQL
calculan precio unitario, descuento, subtotal, total y descuento de stock. La
respuesta `201` se obtiene releyendo el comprobante dentro de la transacción:

```json
{
  "nro_comprobante": 150001,
  "id_cliente": 1,
  "id_sala": 1,
  "fecha": "2026-10-22T12:00:00",
  "subtotal": "8500.00",
  "descuento": "850.00",
  "total": "7650.00",
  "renglones": [
    {
      "cod_vino": 5,
      "cantidad": 2,
      "precio_unitario": "1235.00",
      "descuento": "494.00",
      "subtotal": "1976.00"
    }
  ]
}
```

Si un vino no existe o no hay stock suficiente, la transacción se revierte por
completo: no quedan cabecera ni renglones parciales.

### 4.6. Transferencias

| Método | Ruta | Descripción |
|---|---|---|
| `POST` | `/transferencias` | Crea una transferencia en confección. |
| `POST` | `/transferencias/{codigo}/renglones` | Agrega un renglón. |
| `POST` | `/transferencias/{codigo}/terminar` | Pasa a `terminado`. |
| `POST` | `/transferencias/{codigo}/procesar` | Ejecuta `sp_procesar_transferencia`. |

Alta:

```json
{"id_sala": 1}
```

Renglón:

```json
{"cod_vino": 5, "cantidad": 10}
```

Los endpoints de renglón, terminado y procesado devuelven `204` sin cuerpo.
Los triggers impiden agregar renglones fuera de `en_confeccion`; el
procedimiento valida el estado y el stock. Una transición inválida devuelve
`409` con el mensaje de la regla.

### 4.7. Ingresos

| Método | Ruta | Descripción |
|---|---|---|
| `POST` | `/ingresos` | Crea un ingreso en confección. |
| `POST` | `/ingresos/{codigo}/renglones` | Agrega un renglón. |
| `POST` | `/ingresos/{codigo}/terminar` | Pasa a `terminado`. |
| `POST` | `/ingresos/{codigo}/procesar` | Ejecuta `sp_procesar_ingreso`. |

Alta:

```json
{"cod_transportista": 1, "cuit_bodega": "30050000001"}
```

Renglón:

```json
{"cod_vino": 5, "cantidad": 100}
```

El procedimiento `sp_procesar_ingreso` incrementa el stock de depósito y deja
la auditoría correspondiente. La API no modifica stock directamente.

### 4.8. Reportes

| Método | Ruta | Consigna | Respuesta |
|---|---|---|---|
| `GET` | `/reportes/top-vinos` | S5 | Top 10 por botellas vendidas. |
| `GET` | `/reportes/ventas-por-sala` | S8 | Ventas de los últimos 3 meses por sala. |
| `GET` | `/reportes/vinos-sin-stock` | S6 | Vinos sin stock en una sala y con stock en depósito. |
| `GET` | `/reportes/transportista-activo` | S7 | Transportista con más ingresos en el último mes. |
| `GET` | `/reportes/trazabilidad/{cod_vino}` | S9 | Ficha completa del vino, cepas, maridajes y stock total. |

`/reportes/vinos-sin-stock` requiere `id_sala` entero positivo. Las fechas
relativas se calculan con `CURRENT_DATE` dentro de SQL, no en Python.

Ejemplo de trazabilidad:

```json
{
  "codigo_vino": 1,
  "nombre_vino": "Vino Atuel 1",
  "tipo_vino": "tinto",
  "anio_cosecha_vino": 2022,
  "razon_social_bodega": "Gomez, Diaz and Rios",
  "cepas": "Malbec (100.00%)",
  "maridajes": "Carnes rojas",
  "stock_total": 189999400
}
```

## 5. Errores y códigos HTTP

Formato uniforme:

```json
{
  "error": "Mensaje legible",
  "codigo_sqlstate": "23505"
}
```

Los errores de validación de FastAPI agregan `detalles`:

```json
{
  "error": "Datos de entrada inválidos.",
  "detalles": [
    {"type": "greater_than", "loc": ["body", "id_sala"], "msg": "..."}
  ]
}
```

Traducción de SQLSTATE:

| SQLSTATE | Significado | HTTP |
|---|---|---:|
| `23502` | `NOT NULL` violado | `422` |
| `23503` | FK violada | `409` |
| `23505` | Unique/PK duplicada | `409` |
| `23514` | `CHECK` violado | `422` |
| `22P02` | Texto inválido para un tipo | `400` |
| `P0001` | `RAISE EXCEPTION` de una regla | `409` |
| `40001` | Fallo de serialización | `503` |
| `40P01` | Deadlock detectado | `503` |
| otro | Error no clasificado | `500` |

Las respuestas `503` incluyen `"reintentar": true`. En errores `500` no se
expone la cadena de conexión ni credenciales: solo el mensaje primario de
PostgreSQL o un texto genérico.

Códigos usados por la API:

- `200`: lectura correcta.
- `201`: recurso creado.
- `204`: operación correcta sin cuerpo.
- `400`: parámetro con formato inválido.
- `404`: recurso inexistente o inactivo.
- `409`: conflicto de unicidad, FK o regla de negocio.
- `422`: validación de entrada o restricción `CHECK`/`NOT NULL`.
- `503`: base no disponible, deadlock o fallo de serialización.

## 6. SQL parametrizado

Todos los valores enviados por HTTP se pasan como parámetros de `psycopg`. Los
filtros opcionales se construyen únicamente con fragmentos SQL constantes:

```python
filters = ["v.activo = TRUE"]
parameters: list[Any] = []

if tipo is not None:
    filters.append("lower(v.tipo) = lower(%s)")
    parameters.append(tipo)
if cepa is not None:
    filters.append(
        "EXISTS (SELECT 1 FROM composicion c "
        "JOIN cepa ce ON ce.id_cepa = c.id_cepa "
        "WHERE c.cod_vino = v.cod_vino AND lower(ce.nombre) = lower(%s))"
    )
    parameters.append(cepa)

query = f"""
    SELECT ...
      FROM vino v
      JOIN bodega b ON b.cuit_bodega = v.cuit_bodega
     WHERE {' AND '.join(filters)}
     ORDER BY v.cod_vino
     LIMIT %s OFFSET %s
"""
parameters.extend([limit, offset])
cursor.execute(query, parameters)
```

El único texto interpolado con f-string es la unión de fragmentos constantes.
Ningún valor, nombre de columna ni ordenamiento proviene del usuario.

Demostración incluida en las pruebas:

```bash
curl --get "http://localhost:8000/vinos" \
  --data-urlencode "tipo=tinto' OR 1=1 --" \
  --data-urlencode "por_pagina=10"
# {"items":[],"pagina":1,"por_pagina":10,"cantidad":0}
```

El intento se trata como un valor de texto y no devuelve filas fuera del
filtro. Además, una prueba recorre los archivos del DAO y falla si aparece
`execute(f"`, `execute(f'`, `execute(query %` o `execute(query +`.

## 7. Pruebas

### 7.1. Ejecución

```bash
cd api
uv sync
uv run ruff check src tests
uv run pytest -q
```

Las pruebas de integración requieren PostgreSQL real y usan las mismas
variables `BDA_DATABASE_*`. Contra la base de Compose:

```bash
cd api
BDA_DATABASE_PORT=5433 BDA_DATABASE_PASSWORD=api_password_secreta \
  uv run pytest -q
```

Cada prueba de integración abre una conexión, ejecuta la petición HTTP y
revierte todo al finalizar. El `StaticPool` inyecta esa conexión en
`bodega_api.db._pool`, de modo que la API y el fixture comparten la misma
transacción y la carga original no se altera.

### 7.2. Cobertura funcional

| Área | Casos |
|---|---:|
| Catálogos: salas, cepas y bodegas | 2 |
| Vinos: listado, filtros, detalle, CRUD, composición, duplicados | 12 |
| Clientes: búsqueda, subtipos, cambio de tipo, descuento, duplicados, baja lógica | 12 |
| Comprobantes: totales, stock, rollback sin stock | 6 |
| Movimientos: circuitos de transferencia e ingreso, estado inválido | 13 |
| Reportes S5-S9, inyección SQL y análisis estático del DAO | 13 |
| Transversales: salud, errores, validación, OpenAPI y rutas | 23 |

Resultado verificado:

```text
81 passed (55 unitarios + 26 de integración) in ~2.6s
```

La suite no emite warnings. Ruff finaliza con `All checks passed!`.

### 7.3. Violaciones de reglas cubiertas

- Composición de vino que no suma 100 %: `23514` -> `422`.
- Descuento de cliente fuera de rango: `23514` -> `422`.
- Documento de cliente duplicado: `23505` -> `409`.
- Vino duplicado por identidad de negocio: `23505` -> `409`.
- Venta sin stock: rollback completo de cabecera y renglones.
- Transferencia procesada sin estado `terminado`: `P0001` -> `409`.
- Filtro con intento de inyección: tratado como texto.

## 8. OpenAPI

FastAPI genera el contrato automáticamente desde los routers, los parámetros
`Query` y los modelos Pydantic:

- `/docs`: Swagger UI.
- `/redoc`: ReDoc.
- `/openapi.json`: especificación OpenAPI 3.

La prueba `test_openapi_contains_all_delivered_routes` verifica que estén los
21 paths entregados, agrupados por tags `Healthy`, `Catálogos`, `Vinos`,
`Clientes`, `Comprobantes`, `Transferencias`, `Ingresos` y `Reportes`.

Los cuerpos de entrada tienen modelos Pydantic con restricciones (`gt`, `ge`,
`le`, `min_length`, `pattern`, `Literal`). Las respuestas se documentan con
tipos genéricos porque el DAO devuelve filas dinámicas de PostgreSQL; los
campos concretos están descritos en este documento y en los ejemplos.

## 9. Seguridad

- La API se conecta con `rol_api_lectura_escritura`, no con el propietario de
  la base. Los permisos están definidos en `db/migrations/007_roles.sql`.
- Las credenciales se leen del entorno y no están versionadas. Los valores de
  `.env.example` son exclusivamente locales.
- Todo el SQL de valores usa placeholders `%s`.
- Los mensajes de error no incluyen la cadena de conexión.
- Los recursos se dan de baja de forma lógica; no se borran físicamente desde
  la API.

Fuera del alcance de esta etapa: autenticación de usuarios, autorización por
rol HTTP, TLS, CORS, rate limiting y rotación de secretos. Para un despliegue
real deben agregarse antes de exponer la API fuera de la red local.

## 10. Limitaciones conocidas

- No hay endpoint de listado de comprobantes; solo alta y consulta por número.
- No se permite modificar ni borrar comprobantes emitidos, coherencia con el
  circuito comercial.
- Los clientes se paginan y permiten búsqueda por nombre o documento; no hay
  filtros por tipo, localidad ni otros campos.
- Los reportes no se paginan. Sus resultados son acotados por las consignas
  (`TOP 10`, `LIMIT 1`) salvo `vinos-sin-stock`, que puede crecer con el
  catálogo.
- La baja lógica no tiene endpoint de reactivación.
- No hay claves de idempotencia para reintentos de escritura.
- Los campos monetarios y porcentajes pueden llegar como número o string según
  el encoder de FastAPI; el front tolera ambos y solo los formatea.
- Las fechas y timestamps se devuelven tal como los entrega PostgreSQL, sin
  normalización de zona horaria.
- El pool es global por proceso; un despliegue con varios workers crea un pool
  por worker.

## 11. Verificación de entrega

| Verificación | Comando | Resultado |
|---|---|---|
| Dependencias y Python | `cd api && uv sync` | OK, Python 3.14 |
| Lint | `uv run ruff check src tests` | `All checks passed!` |
| Pruebas unitarias | `uv run pytest -q -m "not integration"` | `55 passed, 26 deselected` |
| OpenAPI | `curl localhost:8000/openapi.json` | 21 paths / 27 operaciones |
| Salud | `curl localhost:8000/health` | `200` |
| Swagger | `curl localhost:8000/docs` | `200` |
| Compose | `docker compose up -d --build` | DB healthy + API arriba |
| Rol de conexión | `\du` / `007_roles.sql` | `rol_api_lectura_escritura` |
