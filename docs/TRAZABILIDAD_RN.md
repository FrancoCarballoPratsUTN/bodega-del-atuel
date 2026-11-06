# Trazabilidad: regla de negocio → mecanismo → prueba

Este documento vincula cada regla de negocio (RN) con el mecanismo que la
implementa y el caso de prueba que la verifica. Los casos se ejecutan con
`./tests/run_db_tests.sh`; el resultado esperado es `PASSED` en las 21 filas.

## Resumen

| Mecanismo | Cantidad | Archivo principal |
|---|---:|---|
| Tablas | 30 | `db/migrations/001_esquema.sql` |
| Constraints `UNIQUE` | 4 | `db/migrations/002_constraints.sql` |
| Constraints `CHECK` | 17 | `db/migrations/002_constraints.sql` |
| Funciones | 8 | `db/migrations/003_funciones.sql` |
| Procedimientos | 3 | `db/migrations/004_procedimientos.sql` |
| Triggers | 17 | `db/migrations/005_triggers.sql` |
| Vistas | 3 | `db/migrations/006_vistas.sql` |
| Índices adicionales | 7 | `db/migrations/008_indices.sql` |

## Tabla principal

| RN | Regla | Mecanismo | Archivo / línea | Caso de prueba | Estado |
|---|---|---|---|---|---|
| RN-01 | Precio de vino único y mayor que cero. | `UNIQUE (nombre, aniada, volumen)` + `CHECK (precio > 0)` | `002_constraints.sql:18,29` | `RN-01` (inserción válida y precio ≤ 0) | PASSED |
| RN-02 | Una sala pertenece a una localidad; encargado regional existente. | FK `sala_venta.cp_localidad` y FK diferida `localidad.cuit_encargado_regional` | `001_esquema.sql:55,70` | `RN-02` (encargado inexistente) | PASSED |
| RN-03 | Cada empleado trabaja en una sola sala. | `empleado.id_sala NOT NULL` + FK | `001_esquema.sql:58-66` | `RN-03` (empleado sin sala) | PASSED |
| RN-04 | Una parcela se cosecha como máximo una vez por campaña. | `UNIQUE (id_finca, nro_parcela, campania)` | `002_constraints.sql:15` | `RN-04` (segunda cosecha) | PASSED |
| RN-05 | Los porcentajes de composición suman 100 %. | Constraint trigger diferido `trg_composicion_porcentaje` + `trg_vino_composicion_obligatoria` | `005_triggers.sql:24,47` | `RN-05` (composición válida) | PASSED |
| RN-06 | Descuento según tipo de cliente (Socio 10 %, Distribuidor 20 %, Exportador 30 %). | `CHECK chk_cliente_descuento` | `002_constraints.sql:63-67` | `RN-06` (descuento inconsistente) | PASSED |
| RN-07 | Vencimiento del permiso posterior a la emisión. | `CHECK chk_permiso_fechas` | `002_constraints.sql:58` | `RN-07` (fechas inválidas) | PASSED |
| RN-08 | El total del comprobante se deriva de sus renglones. | Triggers `trg_renglon_calcula_subtotal`, `trg_comprobante_calcula_importes` + `fn_importes_comprobante` | `005_triggers.sql:74,89`; `003_funciones.sql:5` | `RN-08` (comprobante calculado) | PASSED |
| RN-09 | No vender más que el stock de la sala. | Trigger `trg_renglon_validar_stock` + `trg_renglon_actualizar_venta` | `005_triggers.sql:132,177` | `RN-09` (venta dentro y fuera de stock) | PASSED |
| RN-10 | Solo un ingreso `terminado` pasa a `procesado` e impacta depósito. | Triggers `trg_ingreso_estados` + procedimiento `sp_procesar_ingreso` | `005_triggers.sql:219`; `004_procedimientos.sql:3` | `RN-10` (procesar y salto ilegal) | PASSED |
| RN-11 | La fecha de confección de transferencia es inmodificable y las transiciones son válidas. | Trigger `trg_transferencia_fecha` + `trg_transferencia_estados` | `005_triggers.sql:223,243` | `RN-11` (modificación de fecha) | PASSED |
| RN-12 | Documentos fuera de `en_confeccion` no admiten cambios en renglones. | Triggers `trg_renglon_ingreso_bloqueo`, `trg_renglon_transferencia_bloqueo` | `005_triggers.sql:274,294` | `RN-12` (edición bloqueada) | PASSED |
| RN-13 | Auditoría de cambios de precio. | Trigger `trg_vino_auditoria` | `005_triggers.sql:311` | `RN-13` (cambio auditado) | PASSED |
| RN-14 | No borrar transportista, bodega o vino con movimientos asociados. | FKs `ON DELETE RESTRICT` | `001_esquema.sql:127,128,151,236,249,258,268,285,296,303` | `RN-14` (borrado de bodega con movimientos) | PASSED |
| RN-15 | Graduación alcohólica entre 5 y 20 grados. | `CHECK chk_vino_graduacion` | `002_constraints.sql:38` | `RN-15` (graduación fuera de rango) | PASSED |

## Reglas complementarias

| Regla | Mecanismo | Archivo | Prueba |
|---|---|---|---|
| Herencia disjunta de cliente / distribuidor / exportador. | Triggers `trg_distribuidor_consistente`, `trg_exportador_consistente`, `trg_cliente_tipo_consistente` | `005_triggers.sql:340,368,401` | Cobertura indirecta en RN-06 y en la carga masiva. |
| Documento nace en `en_confeccion`. | Triggers `trg_ingreso_alta_estado`, `trg_transferencia_alta_estado` | `005_triggers.sql:193,197` | Cobertura indirecta en RN-10 y RN-11. |
| Stock no negativo. | `CHECK chk_stock_sala_positivo`, `chk_stock_deposito_positivo` | `002_constraints.sql:41,43` | Cobertura indirecta en RN-09. |
| U6: exportadores con más de 3 permisos al 35 %. | `UPDATE` U6 + `CHECK` que admite 30 % y 35 % | `consultas/update.sql:131`; `002_constraints.sql:63` | Verificación manual con `BEGIN`/`ROLLBACK`. |

## Nota sobre RN-14 y el borrado lógico

La base implementa RN-14 con `ON DELETE RESTRICT`: un borrado físico de una
bodega, vino o transportista con movimientos falla con SQLSTATE `23503`. La API
expone `DELETE` sobre vinos y clientes como **baja lógica** (`activo = FALSE`),
de modo que nunca ejecuta un borrado físico y conserva el historial. La regla
sigue vigente para cualquier borrado directo o para un futuro endpoint de baja
definitiva. Esta decisión está documentada en `docs/ETAPA6_API.md`.

Las tablas con baja lógica son: `vino`, `cliente`, `sala_venta`, `empleado`,
`finca`, `parcela`, `bodega` y `transportista`. La API expone baja lógica
únicamente para vinos y clientes; el resto se gestiona directamente en la base.
Los listados filtran por `activo = TRUE` y el detalle de un recurso inactivo
devuelve `404`. No hay endpoint de reactivación.

## Cómo reproducir

```bash
./tests/run_db_tests.sh
```

Salida esperada:

```text
 regla |                      descripcion                      | resultado
-------+-------------------------------------------------------+-----------
 RN-01 | Inserción válida de vino con precio > 0               | PASSED
 ...
 RN-15 | Graduación fuera de rango rechazada (CHECK_VIOLATION) | PASSED
(21 rows)
```
