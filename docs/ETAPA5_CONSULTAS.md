# Etapa 5: consultas SQL

## Objetivo y alcance

Se resolvieron las 30 consignas de la sección 8 del TPI en PostgreSQL:

- `consultas/update.sql`: U1-U6.
- `consultas/insert.sql`: I1-I6.
- `consultas/delete.sql`: D1-D6.
- `consultas/select.sql`: S1-S12.

Las consultas están comentadas dentro de los archivos SQL. Este documento
explica las elecciones, los parámetros tomados del dataset, los efectos de
triggers y restricciones, y las verificaciones realizadas.

La base utilizada fue `bodega_del_atuel`, con el contenedor `postgresql` y el
usuario `postgresql`. Las consultas que modifican datos se ejecutaron con:

```bash
cat consultas/update.sql | docker exec -i postgresql \
  psql -U postgresql -d bodega_del_atuel -v ON_ERROR_STOP=1
```

El mismo patrón se utilizó para `insert.sql` y `delete.sql`. Cada archivo
comienza con `BEGIN` y termina con `ROLLBACK`, por lo que las pruebas no
alteran permanentemente la carga.

## Parámetros concretos elegidos

| Parámetro | Valor utilizado | Motivo |
|---|---:|---|
| Sala | `id_sala = 1` | La consigna de I3 y S3 pide una sala concreta y la sala 1 existe. |
| Localidad | `cp = 5602`, `General Alvear` | Es la localidad solicitada explícitamente por I1. |
| Cliente de I3 | `id_cliente = 3` | Existe en el dataset y es un cliente Socio. |
| Vino de I6 y S4 | `cod_vino = 1` | Es un vino existente; se evita depender de un nombre que puede cambiar. |
| Bodega de U3 y S12 | Primera bodega por `cuit_bodega` | Hace reproducible la selección sin fijar una razón social artificial. |
| Nueva bodega | `30999999999` | CUIT válido y no existente en la carga verificada. |
| Nueva sala | General Alvear, Av. Libertador 1200 | Localidad existente; el ID se calcula como `MAX(id_sala) + 1`. |

Los valores que pueden cambiarse están indicados en comentarios dentro de los
archivos SQL.

## Estrategias y justificaciones

### Modificaciones

- **U1:** se reutiliza `fn_importes_comprobante`, que suma los renglones y sus
  descuentos derivados del tipo de cliente. Se actualizan `subtotal`,
  `descuento` y `total` en una sola sentencia.
- **U2:** se usa `fn_antiguedad_anios(fecha_ingreso) > 5`, de modo que el
  criterio depende de `CURRENT_DATE`.
- **U3:** se seleccionan los vinos de una bodega concreta mediante su CUIT y
  se redondea el nuevo precio a dos decimales. El trigger de auditoría registra
  cada modificación.
- **U4:** un `CASE` intercambia `Lunes` y `Miércoles` en una única sentencia;
  los demás días quedan sin cambios.
- **U5:** un CTE calcula ventas con `LEFT JOIN`, por lo que también considera
  vinos sin ventas. `LIMIT 10` y `cod_vino` como desempate hacen reproducible
  la selección.
- **U6:** se adaptó la consigna para aplicar el 30 % válido de RN-06 a los
  Exportadores con más de tres permisos.

### Inserciones

- **I1:** `LEFT JOIN` y `COUNT` permiten incluir transportistas sin ingresos en
  el último trimestre. Se ordena por cantidad ascendente y se evita duplicar
  una cobertura con `ON CONFLICT DO NOTHING`.
- **I2:** un bloque PL/pgSQL crea el maridaje solo si existe al menos un vino
  tinto de 14 grados o más, y luego inserta las asociaciones faltantes.
- **I3:** se crea el comprobante, se seleccionan tres vinos con stock en la
  sala 1 y se insertan los renglones usando `fn_descuento_cliente` y
  `fn_calcular_subtotal`. Los triggers calculan nuevamente los importes y
  actualizan el stock.
- **I4:** inserta una bodega con CUIT válido y no repetido.
- **I5:** inserta una sala en General Alvear; el nuevo ID se calcula dentro de
  la sentencia para no colisionar.
- **I6:** crea un ingreso en `en_confeccion` y su renglón de 120 botellas.
  El transportista, la bodega y el vino se toman del dataset.

### Borrados

- **D1:** elimina comprobantes de Socios antiguos. Sus renglones se eliminan
  por `ON DELETE CASCADE`; el trigger de venta puede restituir el stock.
- **D2:** usa dos `NOT EXISTS` para conservar cepas usadas en composiciones o
  parcelas.
- **D3:** usa General Alvear como localidad concreta y excluye encargados
  regionales para no violar la FK `localidad.cuit_encargado_regional`.
- **D4:** usa `NOT EXISTS` para encontrar Socios sin compras.
- **D5:** habilita mediante una configuración local de la transacción el
  borrado histórico explícito. La FK elimina los renglones en cascada y el
  trigger sigue activo para impedir modificaciones ordinarias.
- **D6:** combina localidad, tipo Socio y ausencia de comprobantes.

### Consultas de lectura

- **S1:** agregación de cantidades vendidas por vino.
- **S2:** división relacional mediante dos `NOT EXISTS`: no debe existir una
  sala para la cual falte una venta del vino.
- **S3:** `CURRENT_DATE - INTERVAL '7 days'`.
- **S4:** suma de renglones de transferencias del vino 1 en los últimos 15 días.
- **S5:** `LEFT JOIN` para incluir salas sin transferencias pendientes.
- **S6:** diferencia entre stock de sala y stock de depósito mediante
  `COALESCE`.
- **S7:** cuenta ingresos trasladados en el último mes, que es la actividad
  asociada al transportista en el modelo actual.
- **S8:** suma de comprobantes del último trimestre.

## Consultas avanzadas S9-S12

### S9

Usa la vista `stock_total_vino` para obtener el stock total y combina
`composicion`, `cepa`, `vino_maridaje` y `maridaje`. `STRING_AGG(DISTINCT ...)`
evita repetir cepas o maridajes provocados por el producto cartesiano de las
dos relaciones de detalle.

### S10

El CTE `rendimiento` calcula kilogramos por hectárea para cada parcela y
campaña. Dos subconsultas correlacionadas calculan el promedio de la finca
correspondiente y marcan si la parcela está por debajo de ese promedio.

### S11

El CTE `ventas_mensuales` consolida ventas por sala, mes y vino. Luego:

- `RANK() OVER (PARTITION BY id_sala ...)` genera el ranking dentro de cada
  sala.
- `SUM(...) OVER (PARTITION BY id_sala, mes ORDER BY cod_vino ...)` genera la
  suma acumulada mensual.

### S12

La primera parte aplica división relacional con `NOT EXISTS` anidados: para
cada cliente no debe existir un vino de la bodega objetivo que no haya
comprado. La segunda parte es un anti-join con `NOT EXISTS` para clientes que
nunca compraron un vino de tipo tinto.

En `select.sql`, S9, S10, S11 y S12 incluyen `EXPLAIN (ANALYZE, BUFFERS)`
antes de su consulta, tal como pide la Etapa 5.

En la ejecución sobre la carga actual se observaron estos tiempos:

| Consulta | Planning time | Execution time |
|---|---:|---:|
| S9 | 1,933 ms | 21,421 ms |
| S10 | 1,318 ms | 74,837 ms |
| S11 | 0,732 ms | 1.199,791 ms |
| S12 | 1,113 ms | 21.650,465 ms |

S12 es deliberadamente una división relacional sobre 20.000 clientes y todos
los vinos de la bodega elegida; por eso su plan ejecuta muchas comprobaciones
correlacionadas. La medición queda registrada para que pueda compararse con
los índices de la Etapa 4.

## Resultados de las pruebas transaccionales

Las siguientes cantidades corresponden a la instancia cargada al momento de
la validación. Como las transacciones terminan en `ROLLBACK`, los IDs
generados durante la prueba se reutilizan en ejecuciones posteriores.

| Caso | Resultado observado |
|---|---|
| U1 | 150.000 comprobantes recalculados; el total global permaneció consistente. |
| U2 | 11 empleados superaban cinco años; sus salarios se multiplicaron por 1,20. |
| U3 | 50 vinos de la primera bodega recibieron el aumento del 13 %. |
| U4 | 0 filas afectadas porque la carga actual solo tenía salas con cierre domingo. |
| U5 | 10 vinos seleccionados y actualizados con reducción del 15 %. |
| U6 | Se aplica 30 % a los Exportadores con más de tres permisos; la operación queda dentro de RN-06. |
| I1 | 0 filas insertadas porque General Alvear ya tenía cobertura del transportista elegido; se verificó `ON CONFLICT`. |
| I2 | Maridaje existente y 80 asociaciones verificadas; no se duplicaron relaciones. |
| I3 | Se creó un comprobante temporal con 3 renglones; los triggers calcularon 3.642,00 de subtotal, 364,20 de descuento y 3.277,80 de total. |
| I4 | Se creó temporalmente la bodega `30999999999`. |
| I5 | Se creó temporalmente la sala 19 en General Alvear. |
| I6 | Se creó temporalmente un ingreso en confección de 120 botellas. |
| D1-D4 | No hubo candidatos en la carga actual; las sentencias se ejecutaron sin error. |
| D5 | No hubo candidatos antiguos; la ruta de borrado histórico quedó probada sintácticamente y habilitada solo dentro de la transacción. |
| D6 | No hubo candidatos en General Alvear. |

## Restricciones y triggers observados

### U6: descuento de Exportador

La migración `002_constraints.sql` define:

```sql
CHECK (
    (tipo_cliente = 'Socio' AND descuento = 10.00) OR
    (tipo_cliente = 'Distribuidor' AND descuento = 20.00) OR
    (tipo_cliente = 'Exportador' AND descuento IN (30.00, 35.00))
)
```

Se conserva la migración original: RN-06 exige 30 % para Exportadores. Por
eso U6 se implementa aplicando 30 % a los clientes que tienen más de tres
permisos, sin relajar constraints ni agregar excepciones.

### D5: borrado de ingresos procesados

El ingreso tiene renglones con `ON DELETE CASCADE`, y el trigger sigue
bloqueando inserciones y actualizaciones fuera de `en_confeccion`. Para D5 se
usa una variable local de transacción (`bda.eliminar_ingreso_procesado=on`)
antes del `DELETE`; el trigger permite entonces únicamente la eliminación
histórica explícita. No se deshabilitan triggers y el permiso desaparece al
terminar la transacción.

### Auditoría de precios

U3 y U5 disparan `trg_vino_auditoria`. Cada cambio de precio genera una fila en
`auditoria_precio`, lo que permite auditar la operación aun cuando la prueba
se revierta al final de la transacción.

## Validación ejecutada

Se ejecutaron correctamente:

```bash
cat consultas/update.sql | docker exec -i postgresql psql -U postgresql \
  -d bodega_del_atuel -v ON_ERROR_STOP=1
cat consultas/insert.sql | docker exec -i postgresql psql -U postgresql \
  -d bodega_del_atuel -v ON_ERROR_STOP=1
cat consultas/delete.sql | docker exec -i postgresql psql -U postgresql \
  -d bodega_del_atuel -v ON_ERROR_STOP=1
cat consultas/select.sql | docker exec -i postgresql psql -U postgresql \
  -d bodega_del_atuel -v ON_ERROR_STOP=1
```

La ejecución de `select.sql` completó S1-S12 y produjo planes para S9-S12.
La salida de S11 es grande porque devuelve el ranking mensual de todos los
vinos y salas; esto es esperado para una consulta de informe y no altera la
base.

## Limitaciones conocidas y decisiones

1. Los datos de prueba actuales no tienen filas para algunos períodos móviles
   muy recientes, por lo que S3 puede devolver cero filas. La consulta sigue
   calculando correctamente la última semana desde `CURRENT_DATE`.
2. U6 conserva la restricción original de 30 % para Exportador y aplica un
   valor compatible con la integridad.
3. D5 se resuelve con una habilitación local y transaccional, sin desactivar
   triggers ni alterar permanentemente su comportamiento. Una prueba
   adicional confirmó que el borrado directo sigue bloqueado y que solo se
   habilita después de `set_config(..., true)`.
4. Se modificaron únicamente `002_constraints.sql`, `003_funciones.sql` y
   `005_triggers.sql`; no se modificaron seed ni CSV. Las pruebas de consultas
   siguen terminando con `ROLLBACK`.

## Reparación aplicada

Las reparaciones quedaron integradas en las migraciones originales y dejan:

- `chk_cliente_descuento` permitiendo solo 10 % para Socio, 20 % para
  Distribuidor y 30 % para Exportador.
- `fn_descuento_cliente` usando la regla original por tipo de cliente.
- D5 habilitado únicamente mediante una configuración local de transacción.

La prueba específica con un Exportador temporal y un ingreso procesado
temporal confirmó que U6 y D5 funcionan y que toda la operación se revierte
con `ROLLBACK`.
