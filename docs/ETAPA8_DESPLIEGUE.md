# Etapa 8: despliegue en la nube

## 1. Resumen del despliegue

| Componente | Proveedor | URL / conexión |
|---|---|---|
| Base de datos | Supabase (PostgreSQL 17) | Session pooler con `sslmode=require` |
| API | Render (Web Service, Docker) | <https://bodega-del-atuel-back.onrender.com/> |
| Front | Cloudflare Workers (assets estáticos) | <https://bodega-del-atuel-front.franco11carballo.workers.dev/> |

Verificación rápida:

```bash
curl https://bodega-del-atuel-back.onrender.com/salud
# {"status":"ok","database":"available"}

curl -o /dev/null -w '%{http_code}\n' \
  https://bodega-del-atuel-front.franco11carballo.workers.dev/
# 200
```

## 2. Comparación de proveedores

Los límites de los planes gratuitos cambian con frecuencia. Los valores de esta
tabla se verificaron en la documentación oficial de cada proveedor antes de
cerrar la entrega.

### 2.1. Base de datos: Supabase vs. Neon

| Criterio | Supabase Free | Neon Free |
|---|---|---|
| Almacenamiento | 500 MB | 1 GB por proyecto |
| Cómputo | Instancia compartida (500 MB RAM) | 100 CU-hours/mes, autoscaling hasta 2 CU |
| Inactividad | El proyecto se **pausa** tras 1 semana sin actividad | El cómputo escala a cero a los 5 min y despierta en la próxima consulta; no se pausa el proyecto |
| Proyectos | 2 activos | 100 |
| Conexión | Pooler con TLS | Pooler con TLS |
| Extras | Auth, Storage, Realtime y Edge Functions incluidos | Auth, Object Storage y Functions incluidos |
| Tarjeta | No | No |

**Decisión: Supabase.** El proyecto ya tenía el modelo, los roles y el dump
generados contra PostgreSQL 17 en Supabase, y el volumen completo (≈107 MB)
entra cómodamente en los 500 MB del plan gratuito. La pausa por inactividad es
un riesgo aceptable para una entrega académica y se mitiga abriendo el front
antes de la defensa. Neon era una alternativa válida por su mayor
almacenamiento y su despertar más rápido, pero habría exigido recrear el
proyecto y volver a validar la carga.

### 2.2. API: Render vs. Railway

| Criterio | Render Free | Railway Free |
|---|---|---|
| Horas | 750 instancias-hora/mes | Trial de 30 días con USD 5; luego USD 1/mes de crédito |
| Inactividad | Duerme a los 15 min sin tráfico; despierta en ~1 min | El servicio duerme según consumo |
| Docker | Sí, despliegue desde repositorio | Sí |
| HTTPS | Sí, TLS administrado | Sí |
| Persistencia | Disco efímero | Volumen opcional |

**Decisión: Render.** El plan gratuito no vence a los 30 días y alcanza para un
servicio con poco tráfico. El arranque en frío de ~1 minuto es visible en la
primera petición, pero no afecta la corrección. Railway quedó descartado porque
su crédito gratuito es más chico y variable.

### 2.3. Front: Cloudflare Workers vs. Render Static Site

| Criterio | Cloudflare Workers Free | Render Static Site Free |
|---|---|---|
| Peticiones | 100.000/día | Incluido en bandwidth del workspace |
| Assets estáticos | Hasta 20.000 archivos, 25 MiB por archivo | Sin límite práctico para este proyecto |
| Red | CDN global | CDN de Render |
| HTTPS | Sí | Sí |
| Cold start | No | No para estáticos |

**Decisión: Cloudflare Workers.** El front es una SPA de Vite que solo necesita
servir archivos; Workers Assets lo hace sin cold start y con un límite diario
más que suficiente. La URL pública ya estaba configurada y el despliegue se
repite con `wrangler deploy`.

## 3. Base de datos en Supabase

### 3.1. Rol y conexión

La API no se conecta con el usuario propietario. Usa
`rol_api_lectura_escritura`, creado por `db/migrations/007_roles.sql`. Los tres
roles se crean con contraseñas que llegan por variables de entorno:

| Rol | Uso | Privilegios |
|---|---|---|
| `propietario_base_datos` | Migraciones y carga | Dueño del esquema |
| `rol_api_lectura_escritura` | API | `SELECT`, `INSERT`, `UPDATE`, `DELETE` sobre el esquema; sin DDL |
| `rol_reportes_solo_lectura` | Reportes | Solo `SELECT` |

La conexión usa el session pooler de Supabase con `sslmode=require`. El puerto
de PostgreSQL no se publica: el acceso pasa por el pooler del proveedor y las
credenciales viajan solo en las variables de entorno de Render y en el archivo
local `db/supabase/.env.local`, que está ignorado por Git.

### 3.2. Migraciones en orden

Para demostrar que los archivos SQL del repositorio construyen el esquema desde
cero, se creó una base de validación `bodega_migraciones` en el mismo proyecto
Supabase. No se usó la base `postgres` porque `001_esquema.sql` comienza con
`DROP SCHEMA public CASCADE`, lo que borraría la base productiva.

Las migraciones se aplicaron en orden con el rol propietario:

```bash
for archivo in db/migrations/00*.sql; do
  psql "$SUPABASE_DB_URL/bodega_migraciones?sslmode=require" \
    -v ON_ERROR_STOP=1 -f "$archivo"
done
```

Los archivos `007_roles.sql` leen las contraseñas con `\getenv`, de modo que el
mismo archivo sirve en local y en la nube sin secretos embebidos:

```sql
\getenv bda_owner_password BDA_OWNER_PASSWORD
\getenv bda_database_password BDA_DATABASE_PASSWORD
\getenv bda_reportes_password BDA_REPORTES_PASSWORD
```

Resultado de la validación en `bodega_migraciones`:

| Objeto | Cantidad |
|---|---:|
| Tablas | 30 |
| Vistas | 3 |
| Índices `idx_*` | 7 |
| Triggers | 17 |
| Funciones | 26 |

### 3.3. Datos cargados

Los datos se restauraron desde `db/seed/dump_datos.sql.gz`. Conteos verificados
en la nube:

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

La carga completa entra en el plan gratuito. Tamaño observado:

| Base | Tamaño |
|---|---:|
| `postgres` (base productiva) | 105 MB |
| `bodega_migraciones` (validación) | 107 MB |

### 3.4. Base productiva y base de validación

La base que usa la API (`postgres`) se restauró desde el dump de datos sobre el
esquema existente. La base `bodega_migraciones` es la que prueba el camino
“base vacía → migraciones 001–008 → datos”. Mantener las dos separadas evita
que la validación destruya la base que atiende el front.

Para que la API use la base construida por migraciones alcanza con cambiar en
Render:

```text
BDA_DATABASE_NAME=bodega_migraciones
```

No se hizo en la entrega porque ambas bases tienen el mismo esquema y los
mismos conteos; la base productiva ya estaba verificada y en uso.

## 4. API en Render

### 4.1. Configuración

| Parámetro | Valor |
|---|---|
| Tipo | Web Service (Docker) |
| Repositorio | `bodega-del-atuel-back` |
| Dockerfile | `api/Dockerfile` |
| Puerto | `8000` |
| Salud | `/salud` y `/health` |

Variables de entorno configuradas en el panel de Render (sin valores en el
repositorio):

```text
BDA_DATABASE_HOST
BDA_DATABASE_PORT
BDA_DATABASE_NAME
BDA_DATABASE_USER=rol_api_lectura_escritura
BDA_DATABASE_PASSWORD
BDA_DATABASE_POOL_MIN_SIZE=1
BDA_DATABASE_POOL_MAX_SIZE=10
BDA_CORS_ORIGINS=https://bodega-del-atuel-front.franco11carballo.workers.dev
```

### 4.2. Verificación

```bash
curl https://bodega-del-atuel-back.onrender.com/salud
# {"status":"ok","database":"available"}
```

El endpoint `/salud` es el alias pedido por el enunciado; `/health` se conserva
por compatibilidad con las pruebas y el monitoreo.

### 4.3. CORS

El front y la API están en dominios distintos, por lo que la API habilita el
origen del front con `CORSMiddleware`. Preflight real contra la API desplegada:

```text
HTTP/2 200
access-control-allow-origin: https://bodega-del-atuel-front.franco11carballo.workers.dev
access-control-allow-credentials: true
access-control-allow-methods: DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT, QUERY
access-control-allow-headers: content-type
access-control-max-age: 600
```

Los orígenes se leen de `BDA_CORS_ORIGINS` (lista separada por comas). En local
el front usa el proxy de nginx y no necesita CORS.

## 5. Front en Cloudflare Workers

| Parámetro | Valor |
|---|---|
| Repositorio | `bodega-del-atuel-front` |
| Build | `pnpm build` |
| Salida | `dist/` |
| Variable de build | `VITE_API_URL=https://bodega-del-atuel-back.onrender.com` |
| Runtime | Cloudflare Workers + Assets |

El front no contiene cálculos de importes ni de stock: muestra los totales y
los mensajes de error que devuelve la API. La URL pública responde `200` y
consume la API desplegada.

## 6. Seguridad

| Medida | Evidencia |
|---|---|
| Conexión cifrada | `sslmode=require` en la cadena de Supabase. |
| Rol de privilegios mínimos | La API usa `rol_api_lectura_escritura`; el propietario solo se usa para migrar. |
| Sin DDL para la API | Prueba real: el rol lee 1.007 vinos y al intentar `CREATE TABLE` recibe `SQLSTATE 42501`. |
| Secretos fuera del repositorio | Variables de entorno en Render/Supabase y `.env` ignorado. El historial Git se limpió con `git-filter-repo`. |
| Puerto de base no expuesto | Acceso por session pooler de Supabase, no por IP pública directa. |
| CORS restringido | Solo el origen del front desplegado. |
| SQL parametrizado | Todos los valores viajan como parámetros `%s` en la capa DAO. |

Prueba del rol de la API en la nube:

```text
 current_user             | current_database
--------------------------+------------------
 rol_api_lectura_escritura | bodega_migraciones
 vinos
-------
  1007
NOTICE:  OK: el rol API no puede crear tablas (SQLSTATE 42501)
```

## 7. Backup y restauración

### 7.1. Backup

Se generó un backup lógico completo de la base cloud:

```bash
pg_dump "$SUPABASE_DB_URL" --no-owner --no-privileges \
  | gzip > /tmp/cloud_backup.sql.gz
```

| Dato | Valor |
|---|---|
| Archivo | `/tmp/cloud_backup.sql.gz` |
| Tamaño | 8,4 MB |
| SHA-256 | `ab78e26f3b813a86d402c210f2d357aa4e780808a0e0695e8b4365f655cb2138` |

### 7.2. Restauración en una base nueva

El backup se restauró en un contenedor PostgreSQL 17 nuevo (`bda_restore`,
base `restore`), es decir, en una base distinta de la de origen:

```bash
gzip -dc /tmp/cloud_backup.sql.gz \
  | psql -h 127.0.0.1 -p 5433 -U postgres -d restore -v ON_ERROR_STOP=1
```

Conteos comparados origen vs. restauración:

| Tabla | Origen | Restauración |
|---|---:|---:|
| `comprobante` | 150.021 | 150.021 |
| `renglon_comprobante` | 500.022 | 500.022 |
| `cliente` | 20.000 | 20.000 |
| `vino` | 1.007 | 1.007 |
| `ingreso` | 1.000 | 1.000 |
| `transferencia` | 1.009 | 1.009 |
| `lote_uva` | 600 | 600 |
| `analisis_calidad` | 1.200 | 1.200 |

Los conteos coinciden en todas las tablas verificadas. La restauración se hizo
con `session_replication_role = replica` para cargar datos ya validados sin
depender del orden de las claves foráneas, igual que el dump que usa Compose.

## 8. Trigger comprobado en la nube

Se ejecutó un bloque PL/pgSQL contra `bodega_migraciones` que busca una sala con
stock 0 y intenta vender una botella. Resultado real:

```text
NOTICE:  OK: trigger rechazo venta sin stock
         (SQLSTATE P0001, sala 1, vino 1):
         Stock insuficiente en la sala 1 para el vino 1.
         Disponible: 0, Solicitado: 1
```

Esto confirma que la regla RN-09 no depende del entorno local: el trigger y el
mensaje de negocio funcionan igual en la nube.

## 9. Reproducción del despliegue

1. Crear el proyecto en Supabase y obtener la cadena del session pooler.
2. Exportar `BDA_OWNER_PASSWORD`, `BDA_DATABASE_PASSWORD` y
   `BDA_REPORTES_PASSWORD`.
3. Aplicar `db/migrations/001_esquema.sql` … `008_indices.sql` en orden con el
   rol propietario.
4. Cargar `db/seed/dump_datos.sql.gz`.
5. Crear el Web Service en Render apuntando a `api/Dockerfile` y definir las
   variables `BDA_*`.
6. Verificar `GET /salud`.
7. Compilar el front con `VITE_API_URL` apuntando a Render y desplegarlo con
   `wrangler deploy`.
8. Configurar `BDA_CORS_ORIGINS` con la URL del front.
9. Ejecutar `pg_dump` y restaurar en una base nueva para validar el backup.

## 10. Limitaciones conocidas

- Render free duerme el servicio a los 15 minutos sin tráfico; la primera
  petición puede tardar cerca de un minuto.
- Supabase free pausa el proyecto tras una semana sin actividad. Para la
  defensa conviene abrir el front unos minutos antes.
- El plan gratuito de Supabase no incluye backups automáticos: el backup se
  genera y se valida manualmente.
- La base productiva se restauró desde el dump; la evidencia de migraciones en
  orden se tomó sobre `bodega_migraciones`.
- El front es una SPA sin autenticación, tal como permite el alcance del TPI.
