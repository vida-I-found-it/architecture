# ADR 0005 · La detección de caídas anómalas es una estrategia intercambiable

- **Estado:** ✅ Aceptada · el usuario aprobó el método, pidió encapsularlo como estrategia y aprobó este ADR el 2026-11-19
- **Fecha:** 2026-11-19
- **Requerimientos / casos de uso afectados:** PRO-5, PRO-6, CU-06, CU-07, CU-10, NOT-5; regla R9; decisión DEC-18; pendiente B5

> **Enmienda (2026-11-22, DEC-33):** el análisis ahora es por alerta, al terminar su corrida. `PeerStats` se arma por análisis con una caché corta en memoria (duración por medir), en lugar de una vez por pasada global.

> **Enmienda (2026-11-22, DEC-29):** `price_snapshot` (por cambio) se reemplazó por `alert_snapshot`, una fila por chequeo con su estado; el último precio, el mejor precio y las estadísticas por sitio ya no se materializan, son vistas. Donde este ADR dice «snapshot», léase «chequeo `ok`». Ver [modelo de datos](../../data/data-model.md).

## Contexto

La regla R9 pide marcar una caída sospechosa sin descartarla. No hay un umbral definido, y el usuario no quiere un valor fijo ni una variable de entorno para él: la caída se compara con lo que hacen otros productos. Ese método puede cambiar mañana (otro algoritmo, otra ventana). Hoy el veredicto vive como una columna `price_snapshot.is_anomalous`, atada a un solo algoritmo: cambiar de método obligaría a reescribir snapshots que son append-only.

## Decisión

1. **Puerto `AnomalyStrategy`** (patrón Strategy, igual que PRO-6 y el resto de las interfaces de este repo). Es una función pura: recibe el cambio a evaluar y las estadísticas de comparación, y devuelve un veredicto. No lee la base de datos.
   - Entrada: `price_cop` y precio anterior de la URL (ya vienen del snapshot) más un `PeerStats` (estadísticas de cambio de otros productos) que arma el análisis **una sola vez por pasada**.
   - Salida `AnomalyVerdict`: `is_anomalous`, `reason` (`ok`, `first_capture`, `insufficient_sample`, `no_dispersion`, `outlier`), `score` (puede ser nulo) y `params` (los parámetros usados).
   - Cada estrategia declara `name` y `version`. Cambiar su lógica o sus constantes sube la `version`.
2. **Registro por nombre.** `core` mantiene un diccionario `nombre → clase`. La estrategia activa se elige con **una** variable de entorno `ANOMALY_STRATEGY` (solo el nombre; por defecto `peer_robust_outlier`). Los umbrales y la ventana **no** son variables de entorno: son constantes de la clase, versionadas.
3. **Estrategia inicial `peer_robust_outlier` v1:** el cambio porcentual de la URL se compara con los cambios porcentuales de **otros productos** en los últimos **30 días** (💡 valor de partida mío, sin medición). Es anómala si su *modified z-score* es ≤ **−3,5** (mediana y MAD; también 💡). Con menos de **30** cambios de comparación no marca nada (`insufficient_sample`); con MAD = 0 tampoco (`no_dispersion`). La primera captura de una URL nunca es anómala (`first_capture`, R9).
4. **El veredicto se guarda aparte, no en el snapshot.** La tabla `price_anomaly` es append-only, con PK `(alert_url_id, captured_at, strategy, strategy_version)`. `price_snapshot` pierde `is_anomalous` y queda con los hechos (precio, stock).
5. **Quién lee qué.** El dashboard (CU-07) y el aviso (CU-10) leen el veredicto de la estrategia **activa**. Si un snapshot no tiene veredicto de ella, se muestra como «sin evaluar» (no anómalo). El análisis (CU-06) evalúa los snapshots que aún no tienen veredicto de la estrategia activa.
6. **Cambiar de estrategia:** cambiar el nombre en `ANOMALY_STRATEGY` (o subir la `version`) y reiniciar `core`. No se migra ni se reescribe nada: el análisis siguiente escribe filas nuevas y las anteriores quedan como historial comparable. Un backfill opcional re-evalúa los últimos N días con `INSERT … ON CONFLICT DO NOTHING` (idempotente).

## Alternativas descartadas

| Alternativa | Por qué no |
|-------------|------------|
| Umbral fijo en variable de entorno | El usuario no lo quiere; un % fijo no se adapta a productos con distinta volatilidad |
| Dejar `is_anomalous` en `price_snapshot` | Cambiar de método obligaría a reescribir filas append-only y se perdería con qué algoritmo se marcó cada una |
| Evaluar al guardar el snapshot (CU-05) | Necesita las estadísticas de otros productos; calcularlas por cada snapshot es más caro que una vez por análisis |
| Estrategia elegida por cada alerta | Complejidad sin necesidad en esta versión; se puede añadir después sin romper `price_anomaly` |

## Consecuencias

- Positivas: cambiar de algoritmo es un cambio de nombre y reinicio, sin migrar datos; el historial queda auditable por `strategy` y `strategy_version`; la estrategia es una función pura y se prueba con fixtures; resuelve el choque entre R9 y el snapshot append-only (hallazgo #2 de la revisión del modelo de datos).
- Negativas / costo: una tabla más y un `JOIN` al mostrar el veredicto; con N estrategias evaluadas, N filas por snapshot (en esta versión, una).
- Riesgos y cómo se mitigan: mezclar categorías de producto en la comparación (la variante «solo mismo dominio» queda como estrategia futura); arranque en frío con pocos datos (no marca nada hasta tener muestra, y se declara con `insufficient_sample`).

## Pendientes

- Los valores 30 días, 30 cambios y −3,5 son de partida y sin medición (ver B3 en [pendientes](../../00-context/pending.md)).
- El backfill es opcional y no está diseñado en detalle.
