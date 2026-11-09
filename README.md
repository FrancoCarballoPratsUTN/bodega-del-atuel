# Bodegas del Atuel

Trabajo Práctico Integrador de **Bases de Datos** (UTN Facultad Regional San
Rafael). El proyecto modela una bodega vitivinícola: producción de uva, vinos,
stock por sala, clientes, ventas, ingresos, transferencias y reportes.

La base PostgreSQL es el centro del sistema. La API y el front no reimplementan
reglas de negocio: los totales, descuentos, stock, estados, auditoría y
validaciones viven en constraints, funciones, procedimientos y triggers.

## URLs públicas

| Componente | URL |
|---|---|
| Front | <https://bodega-del-atuel-front.franco11carballo.workers.dev/> |
| API | <https://bodega-del-atuel-back.onrender.com/> |
| Salud de la API | <https://bodega-del-atuel-back.onrender.com/salud> |
| Documentación OpenAPI | <https://bodega-del-atuel-back.onrender.com/docs> |
| Base de datos | PostgreSQL gestionado en Supabase (conexión TLS por session pooler) |

## Arquitectura

```text
┌──────────────────────────────┐
│ Front (React + Vite)         │
│ Cloudflare Workers           │
│ https://...workers.dev       │
└──────────────┬───────────────┘
               │ HTTPS / JSON
┌──────────────▼───────────────┐
│ API REST (FastAPI + psycopg) │
│ Render                       │
│ https://...onrender.com      │
└──────────────┬───────────────┘
               │ TLS (sslmode=require)
┌──────────────▼───────────────┐
│ PostgreSQL 17                │
│ Supabase                     │
│ Rol: rol_api_lectura_escritura│
└──────────────────────────────┘
```

En local, Docker Compose levanta los tres servicios: PostgreSQL, API y front
(nginx). El front proxya `/api` hacia la API, por lo que no hace falta CORS en
ese entorno.

## Requisitos

- Docker Engine 24 o superior.
- Docker Compose v2.
- `openssl` (para generar contraseñas locales).
- Opcional: Python 3 y `uv` para correr la API sin Docker.
- Opcional: Node.js 22 y `pnpm` para correr el front sin Docker.

## Puesta en marcha local

1. Copiar el archivo de ejemplo y completar las contraseñas:

   ```bash
   cp .env.example .env
   ```

   Generar cada valor con, por ejemplo:

   ```bash
   openssl rand -base64 24
   ```

   Variables obligatorias en `.env`:

   | Variable | Uso |
   |---|---|
   | `POSTGRES_PASSWORD` | Superusuario `postgresql` del contenedor. |
   | `BDA_OWNER_PASSWORD` | Rol `propietario_base_datos`. |
   | `BDA_DATABASE_PASSWORD` | Rol `rol_api_lectura_escritura` (API). |
   | `BDA_REPORTES_PASSWORD` | Rol `rol_reportes_solo_lectura`. |

   `.env` está en `.gitignore`; no se versiona.

2. Levantar todo:

   ```bash
   docker compose up --build
   ```

   El primer arranque tarda porque aplica las migraciones y carga los datos.

3. Abrir:

   | Servicio | URL local |
   |---|---|
   | Front | <http://localhost:8080> |
   | API | <http://localhost:8000> |
   | Salud | <http://localhost:8000/salud> |
   | Swagger | <http://localhost:8000/docs> |
   | PostgreSQL | `localhost:5433` |

4. Verificar el estado:

   ```bash
   docker compose ps
   curl http://localhost:8000/salud
   curl "http://localhost:8080/api/vinos?pagina=1&por_pagina=5"
   ```

Para reiniciar desde cero, incluido el volumen de datos:

```bash
docker compose down -v
docker compose up --build
```

## Base de datos

### Migraciones en orden

El esquema se construye exclusivamente con los archivos de `db/migrations/`:

| Orden | Archivo | Contenido |
|---:|---|---|
| 1 | `001_esquema.sql` | Dominios, tipos, tablas y claves. |
| 2 | `002_constraints.sql` | UNIQUE, CHECK y DEFAULT. |
| 3 | `003_funciones.sql` | Funciones de importes, stock y descuentos. |
| 4 | `004_procedimientos.sql` | Procedimientos de ingreso, transferencia y precios. |
| 5 | `005_triggers.sql` | Reglas de negocio, herencia y composición diferida. |
| 6 | `006_vistas.sql` | Vistas de stock, ventas y documentos pendientes. |
| 7 | `007_roles.sql` | Roles y privilegios mínimos. |
| 8 | `008_indices.sql` | Índices de rendimiento. |

Docker Compose monta esos archivos en `/docker-entrypoint-initdb.d/` y luego
carga `db/seed/dump_datos.sql.gz` (solo datos). El dump usa
`session_replication_role = replica` para restaurar datos ya validados sin
depender del orden de las claves foráneas.

Para aplicar las migraciones manualmente sobre una base vacía:

```bash
export BDA_OWNER_PASSWORD='...'
export BDA_DATABASE_PASSWORD='...'
export BDA_REPORTES_PASSWORD='...'

for archivo in db/migrations/*.sql; do
  psql -h localhost -p 5433 -U postgresql -d bodega_del_atuel \
    -v ON_ERROR_STOP=1 -f "$archivo"
done
```

### Datos

- `db/seed/dump_datos.sql.gz`: datos actuales (solo `COPY` y secuencias). Es el
  archivo que carga Docker Compose después de las migraciones.
- `db/seed/seed.py`: carga reproducible desde los CSV de `db/seed/csv/`.
  Requiere `Faker` y `psycopg2-binary`. Ver `db/seed/README.md`.

Conteos principales del dataset:

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

### Restaurar los datos manualmente

Con el esquema ya migrado (por ejemplo, tras `docker compose up` o aplicando
`db/migrations/*.sql`):

```bash
gzip -dc db/seed/dump_datos.sql.gz | \
  psql -h localhost -p 5433 -U postgresql -d bodega_del_atuel
```

## Pruebas

### Pruebas de reglas de negocio en la base

```bash
./tests/run_db_tests.sh
```

El script crea un contenedor PostgreSQL descartable, aplica las ocho
migraciones en orden y ejecuta `tests/db_tests.sql`. Cubre 21 casos de las
reglas RN-01 a RN-15. Al finalizar muestra una tabla con `PASSED` o `FAILED` y
elimina el contenedor.

> Los archivos de prueba viven en `tests/` (raíz) porque `run_db_tests.sh`
> necesita acceder a `db/migrations/` y `tests/db_tests.sql` con rutas
> relativas al repositorio. Moverlos a `db/tests/` rompería esos paths sin
> beneficio funcional.

### Pruebas de la API

```bash
cd api
export BDA_DATABASE_PASSWORD='...'
uv sync
uv run pytest
```

Las pruebas de integración se saltan si no hay una base disponible o si falta
`BDA_DATABASE_PASSWORD`.

## Consultas SQL

Los archivos pedidos por el enunciado están en `consultas/`:

| Archivo | Contenido |
|---|---|
| `insert.sql` | Inserciones I1 a I5. |
| `update.sql` | Modificaciones U1 a U6. |
| `delete.sql` | Borrados D1 a D5. |
| `select.sql` | Consultas S1 a S12; S9-S12 incluyen indicación para medir con `EXPLAIN`. |

Cada archivo está comentado y encapsulado en transacciones con `ROLLBACK`
cuando corresponde.

## Documentación

| Documento | Contenido |
|---|---|
| `docs/INFORME_FINAL.md` | Informe final según la estructura 10.2 del enunciado. |
| `docs/Etapa 1_ Modelado (MER, DER, DICCIONARIO, DISEÑO)/` | MER, DER, modelo relacional, diccionario de datos y decisiones de diseño. |
| `docs/Etapa 2. Integridad y lógica en la base de datos /` | Tabla de trazabilidad RN → mecanismo → prueba y demostración de concurrencia. |
| `docs/ETAPA8_DESPLIEGUE.md` | Despliegue en la nube, proveedores, backup y evidencias. |
| `docs/ETAPA6_API.md` | Arquitectura, endpoints y errores de la API. |
| `docs/ETAPA5_CONSULTAS.md` | Decisiones de las consultas SQL. |
| `docs/RENDIMIENTO_INDICES.md` | Comparativas `EXPLAIN (ANALYZE, BUFFERS)`. |
| `db/seed/README.md` | Carga masiva y controles. |

## Seguridad

- Las contraseñas se leen de variables de entorno; no hay secretos en el
  repositorio ni en su historial.
- La API se conecta con `rol_api_lectura_escritura`, no con el propietario.
- El rol de la API no puede crear tablas, roles ni bases.
- La conexión a Supabase usa TLS (`sslmode=require`).
- Los roles `anon` y `authenticated` de Supabase no tienen acceso a `public`.
- La API valida la entrada con Pydantic y usa SQL parametrizado en la capa DAO.

## Estructura del repositorio

```text
.
├── README.md
├── docker-compose.yml
├── .env.example
├── db/
│   ├── migrations/          # 001 a 008
│   ├── seed/                # CSV, seed.py y dumps
│   └── supabase/            # scripts locales de migración (gitignore)
├── consultas/               # INSERT, UPDATE, DELETE y SELECT
├── api/                     # FastAPI + psycopg
├── front/                   # React + Vite + nginx
├── tests/                   # db_tests.sql y runner
└── docs/                    # informes y documentación
```

## Problemas frecuentes

- **`docker compose up` falla por variables faltantes**: completar `.env` a
  partir de `.env.example`.
- **El front no encuentra la API**: en local se usa el proxy de nginx
  (`/api`). En Cloudflare se define `VITE_API_URL` con la URL de Render.
- **La API responde 503**: revisar `docker compose ps` y los logs de `db` y
  `api`. El healthcheck espera a que los datos estén cargados.
- **Puerto ocupado**: cambiar `FRONT_PORT`, `API_PORT` o `POSTGRES_PORT` en
  `.env`.
- **Render free duerme el servicio**: la primera petición después de 15
  minutos sin tráfico puede tardar cerca de un minuto.
