# Demostración de concurrencia: la última botella

## Objetivo

Mostrar qué ocurre cuando dos sesiones intentan vender al mismo tiempo la única
unidad disponible de un vino en una sala, y por qué el trigger
`trg_renglon_validar_stock` usa `SELECT ... FOR UPDATE`.

La prueba se ejecuta dos veces sobre la misma base:

1. Con la implementación real (`FOR UPDATE`).
2. Con una variante equivalente sin bloqueo, solo para comparar.

En ambos casos el stock inicial es 1 y las dos sesiones intentan insertar un
renglón de una botella. El resultado correcto es **una sola venta confirmada**.

## Archivos

| Archivo | Función |
|---|---|
| `tests/concurrencia_demo.py` | Abre dos conexiones, las sincroniza con una barrera y ejecuta la venta. |
| `tests/run_concurrencia.sh` | Prepara la última botella, ejecuta los dos modos y restaura el trigger original. |

## Mecanismo bajo prueba

El trigger de la migración `005_triggers.sql` hace:

```sql
SELECT cantidad INTO v_stock
FROM stock_sala
WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino
FOR UPDATE;
```

`FOR UPDATE` bloquea la fila de `stock_sala` hasta que la transacción que la
leyó termina. La segunda sesión no puede leer el mismo valor: espera, y cuando
obtiene el lock ya ve el stock descontado por la primera.

Además, la tabla tiene `CHECK (cantidad >= 0)` (`chk_stock_sala_positivo`). Ese
CHECK actúa como última barrera: aun si el trigger no bloqueara, la base no
acepta stock negativo. La diferencia es el mensaje y el momento en que se
detecta el problema.

## Salida real

Ejecutada sobre el Compose local con el dataset completo:

```text
== Con FOR UPDATE (implementación real) ==
modo=with-lock sala=1 vino=1 stock_inicial=1
sesion_A: COMMIT | comprobante=150038
sesion_B: ROLLBACK | SQLSTATE=P0001 | Stock insuficiente en la sala 1 para el vino 1. Disponible: 0, Solicitado: 1
stock_final=0 comprobantes_confirmados=1

== Sin FOR UPDATE (variante de comparación) ==
modo=without-lock sala=1 vino=1 stock_inicial=1
sesion_A: COMMIT | comprobante=150040
sesion_B: ROLLBACK | SQLSTATE=23514 | new row for relation "stock_sala" violates check constraint "chk_stock_sala_positivo"
stock_final=0 comprobantes_confirmados=1

Trigger original restaurado.
```

## Lectura de los resultados

### Con `FOR UPDATE`

- La primera sesión obtiene el lock, valida que hay 1 unidad y confirma.
- La segunda espera el lock. Cuando lo obtiene, el stock ya es 0 y el trigger
  lanza una excepción de negocio: `SQLSTATE P0001`.
- La API traduce `P0001` a **409 Conflict** y devuelve el mensaje de la regla.
- Queda exactamente una venta y el stock termina en 0.

### Sin `FOR UPDATE`

- Las dos sesiones leen el mismo stock (1) antes de que la otra escriba.
- Ambas intentan descontar. La primera confirma.
- La segunda intenta dejar el stock en -1 y la restricción
  `chk_stock_sala_positivo` la rechaza con `SQLSTATE 23514`.
- La base sigue sin sobrevender: una venta confirmada, stock final 0.
- El mensaje es menos claro (`check constraint`) y el error se detecta más
  tarde, después de haber intentado escribir.

## Conclusión

El `FOR UPDATE` no es lo único que impide el oversell: el `CHECK` también lo
haría. Su valor es **serializar la decisión** y producir un error de negocio
claro (`P0001`, “Stock insuficiente…”) antes de llegar a la restricción física.
La combinación de ambos mecanismos es deliberada:

| Capa | Rol |
|---|---|
| `FOR UPDATE` en el trigger | Evita la carrera y da un mensaje de negocio. |
| `CHECK (cantidad >= 0)` | Última defensa ante cualquier camino que omita el trigger. |
| Transacción de la API | Revierte cabecera y renglones si falla la validación. |

## Cómo reproducir

Requiere el Compose principal levantado y un `.env` completo:

```bash
docker compose up -d
./tests/run_concurrencia.sh
```

El script:

1. Lee las credenciales de `.env`.
2. Fija el stock de la sala 1 / vino 1 en 1.
3. Ejecuta el modo `with-lock`.
4. Reemplaza temporalmente el trigger por `trg_validar_stock_venta_sin_lock`,
   ejecuta el modo `without-lock` y restaura el trigger original con un `trap`.
5. Limpia los comprobantes generados y restituye el stock original.

El script es idempotente: puede ejecutarse varias veces y deja la base como la
encontró.

## Nota sobre la limpieza

El trigger `trg_actualizar_venta` necesita la cabecera del comprobante para
saber a qué sala devolver el stock. Por eso la limpieza borra primero
`renglon_comprobante` y después `comprobante`. Si se borra la cabecera primero,
el `ON DELETE CASCADE` dispara el trigger sin fila padre y falla. Este
comportamiento no afecta a la operación normal de la API, que nunca borra
comprobantes emitidos.
