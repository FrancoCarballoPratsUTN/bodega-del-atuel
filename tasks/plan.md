# Implementation Plan: Etapa 6 - API REST

## Overview

Construir una API REST en `api/` con Python 3.14, `uv` y FastAPI para exponer
la base PostgreSQL cargada. La API usará `psycopg` como driver nativo, un pool
de conexiones, SQL explícito y parametrizado en una capa de acceso a datos,
transacciones explícitas para operaciones multi-sentencia y las funciones,
procedimientos, triggers y restricciones existentes como fuente única de las
reglas de negocio.

## Architecture Decisions

- **Python 3.14 + uv + FastAPI:** cumple la decisión solicitada y mantiene una
  estructura pequeña, tipada y fácil de ejecutar.
- **`psycopg` 3 con `ConnectionPool`:** driver nativo PostgreSQL y pool sin
  introducir ORM ni una abstracción innecesaria.
- **DAO/repository explícito:** cada consulta SQL vivirá en una función del
  módulo de acceso a datos; los routers solo validan entrada, coordinan la
  transacción y serializan respuestas.
- **SQL parametrizado:** los valores del usuario siempre se pasarán como
  parámetros; los filtros opcionales se construirán desde una lista cerrada de
  fragmentos SQL constantes, nunca concatenando valores.
- **Base como fuente de verdad:** la API no recalculará totales, descuentos ni
  stock; llamará a funciones/procedimientos existentes y propagará errores
  SQLSTATE.
- **Pydantic para contratos HTTP, no para reglas de negocio:** los modelos
  validarán forma y tipos de entrada/salida, mientras PostgreSQL validará
  consistencia relacional y reglas del dominio.
- **OpenAPI nativo de FastAPI:** se documentarán rutas, parámetros, cuerpos y
  respuestas mediante tipos y metadatos de FastAPI; no se agregará Swagger
  externo.
- **Pruebas de integración con PostgreSQL real:** se probarán rutas contra la
  instancia levantada para verificar triggers, procedimientos, SQLSTATE y
  rollback real.
- **Configuración por entorno:** `.env.example` contendrá nombres de variables
  sin secretos; las credenciales reales no se versionarán.

## Dependency Graph

```text
Migraciones 001-008 + rol API
    ├── Configuración y pool psycopg
    │       ├── Salud y manejo de errores
    │       └── Capa DAO parametrizada
    │               ├── Catálogo de vinos y clientes
    │               ├── Operaciones transaccionales
    │               └── Reportes
    ├── Contratos Pydantic
    └── Routers FastAPI
            └── Pruebas HTTP + OpenAPI + Docker Compose
```

## Task List

### Phase 1: Foundation

- [x] **Task 1: Crear el proyecto Python con uv**
  - **Description:** Definir `pyproject.toml`, versión mínima Python 3.14,
    dependencias de runtime y pruebas, configuración Ruff/mypy si aporta
    valor y un punto de entrada FastAPI mínimo.
  - **Acceptance criteria:**
    - [x] `uv sync` resuelve dependencias con Python 3.14.
    - [x] La aplicación puede importarse sin conectarse a PostgreSQL.
    - [x] No se agrega ORM ni dependencia innecesaria.
  - **Verification:** `uv run python --version`, `uv run pytest` y una prueba
    de importación.
  - **Dependencies:** None.
  - **Files likely touched:** `api/pyproject.toml`, `api/src/bodega_api/__init__.py`.
  - **Estimated scope:** Small.

- [x] **Task 2: Implementar configuración, pool y salud**
  - **Description:** Leer variables de entorno, configurar `psycopg_pool`,
    conectar con `rol_api_lectura_escritura` y exponer `GET /salud`.
  - **Acceptance criteria:**
    - [x] Credenciales y host/puerto/base se obtienen del entorno.
    - [x] `/salud` devuelve estado HTTP claro cuando la base responde.
    - [x] El pool se abre y cierra en el ciclo de vida de FastAPI.
  - **Verification:** prueba de salud contra PostgreSQL y prueba de error de
    conexión sin filtrar secretos.
  - **Dependencies:** Task 1.
  - **Files likely touched:** `api/src/bodega_api/config.py`,
    `api/src/bodega_api/db.py`, `api/src/bodega_api/main.py`, `.env.example`.
  - **Estimated scope:** Medium.

### Checkpoint: Foundation

- [x] La aplicación arranca localmente.
- [x] `/salud` responde contra la base real.
- [x] Las credenciales reales no aparecen en Git ni en `.env.example`.

### Phase 2: Data Access and Error Boundaries

- [x] **Task 3: Crear modelos HTTP y traductor SQLSTATE**
  - **Description:** Definir DTOs Pydantic y un manejador central que traduzca
    `23505`, `23503`, `23514`, `23502`, `P0001`, `22P02`, `40001` y `40P01`
    a las respuestas HTTP requeridas.
  - **Acceptance criteria:**
    - [x] Los errores tienen formato JSON consistente.
    - [x] El mensaje de reglas `P0001` se conserva sin exponer credenciales.
    - [x] Deadlock/serialization failure devuelven 503 y sugieren reintento.
  - **Verification:** pruebas unitarias del mapeo para cada SQLSTATE.
  - **Dependencies:** Task 1.
  - **Files likely touched:** `api/src/bodega_api/errors.py`,
    `api/src/bodega_api/schemas.py`, `api/tests/test_errors.py`.
  - **Estimated scope:** Medium.

- [x] **Task 4: Implementar DAO parametrizado**
  - **Description:** Crear una función por consulta para vinos, clientes,
    comprobantes, transferencias, ingresos y reportes. Las consultas usarán
    parámetros y reutilizarán funciones, procedimientos y vistas SQL existentes.
  - **Acceptance criteria:**
    - [x] Ninguna consulta concatena valores recibidos por HTTP.
    - [x] Los filtros de vinos solo usan columnas permitidas y parámetros.
    - [x] El DAO permite recibir una conexión existente para transacciones.
  - **Verification:** revisión automatizada que detecte interpolación SQL y
    pruebas DAO contra la base cargada.
  - **Dependencies:** Tasks 2-3.
  - **Files likely touched:** `api/src/bodega_api/dao/`, `api/tests/test_dao.py`.
  - **Estimated scope:** Large, dividido por recursos dentro del DAO.

### Checkpoint: Data boundary

- [x] El DAO ejecuta consultas parametrizadas contra el rol API.
- [x] Los errores de base se transforman centralmente.
- [x] No hay SQL en routers.

### Phase 3: Resource Endpoints

- [x] **Task 5: Implementar catálogo y CRUD de vinos**
  - **Description:** Exponer listado paginado con filtros por tipo, cepa,
    bodega y añada; detalle con composición y maridajes; alta, modificación y
    baja delegando auditoría y reglas a PostgreSQL.
  - **Acceptance criteria:**
    - [x] `GET /vinos` pagina y filtra sin concatenar valores.
    - [x] `GET /vinos/{cod}` devuelve cepas, porcentajes y maridajes.
    - [x] POST/PUT/DELETE traducen correctamente conflictos de FK, CHECK y
      composición.
  - **Verification:** pruebas HTTP de listado, filtros, detalle y errores de
    precio/composición.
  - **Dependencies:** Tasks 3-4.
  - **Files likely touched:** `api/src/bodega_api/routers/vinos.py`,
    `api/src/bodega_api/schemas.py`, DAO de vinos y pruebas.
  - **Estimated scope:** Medium.

- [x] **Task 6: Implementar CRUD de clientes**
  - **Description:** Exponer clientes y sus subtipos existentes
    (`distribuidor`/`exportador`) sin rediseñar la herencia ni duplicar las
    restricciones de `cliente`.
  - **Acceptance criteria:**
    - [x] GET/POST/PUT/DELETE `/clientes` funcionan con los tres tipos.
    - [x] Los datos específicos del subtipo se guardan en sus tablas.
    - [x] Los errores de documento/FK/CHECK devuelven el código HTTP previsto.
  - **Verification:** pruebas CRUD y violación de descuento/tipo.
  - **Dependencies:** Tasks 3-4.
  - **Files likely touched:** `api/src/bodega_api/routers/clientes.py`,
    DAO de clientes, schemas y pruebas.
  - **Estimated scope:** Medium.

- [x] **Task 7: Implementar comprobantes transaccionales**
  - **Description:** Crear y consultar comprobantes; la venta completa se
    insertará con una única conexión y `BEGIN/COMMIT/ROLLBACK`, dejando que los
    triggers calculen importes y descuenten stock.
  - **Acceptance criteria:**
    - [x] POST `/comprobantes` crea cabecera y renglones en una sola
      transacción.
    - [x] Un fallo de stock revierte cabecera y renglones.
    - [x] La API no calcula total ni stock.
  - **Verification:** prueba exitosa y prueba de venta sin stock con HTTP 409 y
    conteo posterior sin datos parciales.
  - **Dependencies:** Tasks 3-4.
  - **Files likely touched:** router/DAO/schemas de comprobantes y pruebas.
  - **Estimated scope:** Medium.

### Checkpoint: Core resources

- [x] Vinos, clientes y comprobantes funcionan contra la base real.
- [x] La venta sin stock revierte completamente.
- [x] El listado de vinos tiene paginación y los cuatro filtros.

### Phase 4: Workflows and Reports

- [x] **Task 8: Implementar transferencias e ingresos**
  - **Description:** Exponer altas, renglones, terminación y procesamiento,
    invocando `sp_procesar_transferencia` y `sp_procesar_ingreso`.
  - **Acceptance criteria:**
    - [x] Solo se agregan renglones mientras el documento está en confección.
    - [x] Los endpoints de procesar llaman al procedimiento de base.
    - [x] Las transiciones inválidas devuelven HTTP 409 con el mensaje de regla.
  - **Verification:** pruebas de circuito válido, estado inválido y stock
    insuficiente en transferencia.
  - **Dependencies:** Tasks 3-4.
  - **Files likely touched:** routers/DAO/schemas de transferencias e ingresos.
  - **Estimated scope:** Large, dividido en dos módulos simétricos.

- [x] **Task 9: Exponer reportes de la sección 8**
  - **Description:** Implementar `/reportes/top-vinos`,
    `/ventas-por-sala`, `/vinos-sin-stock`, `/transportista-activo` y
    `/trazabilidad/{cod}` como endpoints de solo lectura.
  - **Acceptance criteria:**
    - [x] Cada ruta usa una función DAO propia.
    - [x] Las fechas relativas usan `CURRENT_DATE` en SQL.
    - [x] Las respuestas coinciden con las consultas S1-S9 existentes.
  - **Verification:** pruebas de respuesta y comparación con consultas SQL de
    `consultas/select.sql`.
  - **Dependencies:** Task 4.
  - **Files likely touched:** router/DAO de reportes, schemas y pruebas.
  - **Estimated scope:** Medium.

### Checkpoint: Workflows

- [x] Transferencias e ingresos respetan sus triggers y procedimientos.
- [x] Los cinco reportes devuelven datos de la carga real.
- [x] Ningún router contiene SQL inline.

### Phase 5: Delivery, Security, and Acceptance

- [x] **Task 10: Agregar pruebas automáticas y demostración de parametrización**
  - **Description:** Completar al menos 8 pruebas automáticas, incluyendo tres
    violaciones de reglas de base y una prueba de intento de inyección SQL
    tratado como texto.
  - **Acceptance criteria:**
    - [x] Hay al menos 8 pruebas ejecutables.
    - [x] Al menos 3 verifican respuestas por reglas de PostgreSQL.
    - [x] El filtro malicioso no altera la consulta ni devuelve datos fuera del
      filtro.
  - **Verification:** `uv run pytest` contra base de prueba/carga controlada;
    guardar resultado de la demostración en el informe.
  - **Dependencies:** Tasks 5-9.
  - **Files likely touched:** `api/tests/`, `docs/ETAPA6_API.md`.
  - **Estimated scope:** Medium.

- [x] **Task 11: Documentar OpenAPI y configurar Docker Compose**
  - **Description:** Completar la documentación OpenAPI generada por FastAPI,
    `.env.example`, Dockerfile y `docker-compose.yml` para levantar base y API
    con un comando.
  - **Acceptance criteria:**
    - [x] `/docs` y `/openapi.json` describen las rutas reales.
    - [x] `docker compose up` levanta PostgreSQL y API en orden correcto.
    - [x] La API usa el rol `rol_api_lectura_escritura`, no el propietario.
  - **Verification:** `docker compose config`, `docker compose up`, `/salud`,
    `/docs` y apagado limpio.
  - **Dependencies:** Tasks 2-10.
  - **Files likely touched:** `api/Dockerfile`, `docker-compose.yml`,
    `.env.example`, documentación y scripts de arranque.
  - **Estimated scope:** Medium.

### Checkpoint: Complete

- [x] `docker compose up` levanta base y API.
- [x] Todas las pruebas pasan.
- [x] Hay al menos 8 pruebas y tres violaciones de reglas.
- [x] SQL parametrizado y DAO centralizado verificados.
- [x] OpenAPI coincide con las rutas reales.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| PostgreSQL no está disponible al ejecutar pruebas | High | Usar fixture explícito de conexión y documentar el prerrequisito Docker. |
| El rol API no puede ejecutar una operación | High | Verificar privilegios reales antes de implementar routers y ajustar solo migraciones de permisos si es necesario. |
| Triggers calculan valores en momentos inesperados | High | No recalcular en Python; probar cada flujo en transacción real. |
| SQL dinámico para filtros introduce inyección | Critical | Lista blanca de columnas/fragmentos constantes y parámetros para todos los valores. |
| Docker Compose inicia API antes de migraciones | High | Healthcheck de PostgreSQL y comando de inicialización reproducible. |
| Python 3.14 aún no está disponible en el entorno | Medium | Fallar explícitamente en `uv sync`; no degradar silenciosamente a otra versión. |
| API demasiado grande para una sola entrega | Medium | Implementar por checkpoints: salud/DAO, vinos/clientes, workflows/reportes, entrega. |

## Resolved Questions

- El `docker-compose.yml` crea un servicio PostgreSQL autocontenido con volumen
  propio (`bodega_db_data`) y puerto host `5433`, para no depender del
  contenedor local de desarrollo.
- La inicialización de Compose es automática mediante
  `docker-entrypoint-initdb.d`: dump, roles, índices, triggers vigentes y
  contraseña del rol API. En arranques posteriores se reutiliza el volumen.
- Las pruebas de integración usan la carga completa y aíslan cada caso con una
  transacción revertida al finalizar, por lo que no modifican el dataset y no
  requieren un dataset mínimo separado.
