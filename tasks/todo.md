# Etapa 6 - API REST

## Phase 1: Foundation

- [x] Task 1: Crear el proyecto Python con uv
- [x] Task 2: Implementar configuración, pool y salud

## Checkpoint: Foundation

- [x] La aplicación arranca localmente.
- [x] `/salud` responde contra PostgreSQL.
- [x] No hay secretos versionados.

## Phase 2: Data Access and Error Boundaries

- [x] Task 3: Crear modelos HTTP y traductor SQLSTATE
- [x] Task 4: Implementar DAO parametrizado

## Checkpoint: Data boundary

- [x] El DAO usa consultas parametrizadas.
- [x] Los errores SQLSTATE tienen traducción HTTP.
- [x] No hay SQL en routers.

## Phase 3: Resource Endpoints

- [x] Task 5: Implementar catálogo y CRUD de vinos
- [x] Task 6: Implementar CRUD de clientes
- [x] Task 7: Implementar comprobantes transaccionales

## Checkpoint: Core resources

- [x] Vinos, clientes y comprobantes funcionan contra PostgreSQL.
- [x] La venta sin stock revierte datos parciales.
- [x] El catálogo pagina y filtra.

## Phase 4: Workflows and Reports

- [x] Task 8: Implementar transferencias e ingresos
- [x] Task 9: Exponer reportes de la sección 8

## Checkpoint: Workflows

- [x] Estados y procedimientos de base se respetan.
- [x] Los reportes responden con datos reales.

## Phase 5: Delivery, Security, and Acceptance

- [x] Task 10: Agregar pruebas automáticas y demostración de parametrización
- [x] Task 11: Documentar OpenAPI y configurar Docker Compose

## Checkpoint: Complete

- [x] `docker compose up` levanta base y API.
- [x] Todas las pruebas pasan.
- [x] OpenAPI coincide con las rutas reales.
