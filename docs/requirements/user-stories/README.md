# Historias de usuario

Un archivo por caso de uso, con la [plantilla](../../templates/user-story.md).

| CU | Título | Historias | Criterios | Repos que toca | Archivo | Estado |
|----|--------|-----------|-----------|----------------|---------|--------|
| CU-02 | Registrar una alerta con URLs | 5 | 29 | frontend, core | [`CU-02.md`](CU-02.md) | Borrador |
| CU-03 | Programar la captura | 5 | 42 | core, schedule, frontend | [`CU-03.md`](CU-03.md) | Borrador |
| CU-04 | Capturar el precio de un sitio | 5 | 57 | schedule, scraper, core | [`CU-04.md`](CU-04.md) | Borrador |
| CU-05 | Procesar y almacenar | 6 | 54 | core, schedule, scraper | [`CU-05.md`](CU-05.md) | Borrador |
| CU-06 | Analizar el mejor precio | 5 | 43 | core, schedule, frontend | [`CU-06.md`](CU-06.md) | Borrador |
| CU-07 | Ver el dashboard de una alerta | 6 | 63 | frontend, core | [`CU-07.md`](CU-07.md) | Borrador |
| CU-08 | Ver histórico y comparar sitios | 4 | 32 | frontend, core | [`CU-08.md`](CU-08.md) | Borrador |
| CU-10 | Notificar a los correos registrados | 5 | 46 | core, notify, schedule, frontend | [`CU-10.md`](CU-10.md) | Borrador |
| CU-11 | Darse de baja de una alerta | 4 | 31 | frontend, core | [`CU-11.md`](CU-11.md) | Borrador |

Total: 9 historias de CU (CU-02 a CU-08, CU-10 y CU-11; no existe CU-09 en [`requirements.md`](../requirements.md)), 45 historias de usuario y 397 criterios (`US-NN-MM-ACn`). Todos los criterios están en estado borrador: sin aprobar. Las preguntas abiertas de cada CU, marcadas 💡 cuando son propuestas, bloquean o precisan los criterios y no son decisiones.

## Orden de implementación sugerido

Derivado de las secciones «Dependencias y orden de implementación sugerido» de cada historia. Es un orden de referencia; los pasos marcados «en paralelo» se pueden hacer a la vez.

1. **CU-02** · alta de alerta (`core` y frontend). Base de datos y `POST /api/alerts`.
2. **CU-03** (`schedule` y cliente de `core`) y **CU-10** US-10-02 y US-10-03 (`notify` solo, con SMTP de prueba): en paralelo, cada uno probado con un doble del siguiente.
3. **CU-04**: primero el scraper (US-04-05, US-04-03, US-04-02, con fixtures), luego `core` (`job-detail`) y `schedule` (US-04-01, US-04-04).
4. **CU-05**: normalizador y `POST /api/internal/prices` en `core`, luego la entrega con outbox en `schedule` (US-05-06).
5. **CU-06**: análisis en `core`; después se cierra el aviso con **CU-10** US-10-01 (`core` → `notify`), US-10-04 y US-10-05.
6. **CU-11**: endpoint de baja en `core` (US-11-02, US-11-03), luego la página (US-11-01, US-11-04). Requiere decidir la página de baja (CU-10, pregunta 1).
7. **CU-07** y **CU-08**: lista, dashboard e histórico. Pueden empezar contra datos sembrados en `alert_snapshot` antes de que CU-03 a CU-06 estén completos. El prototipo universitario adelanta **US-07-06** (detalle de la alerta por número): solo depende de CU-02 y va antes que US-07-02.

Antes de implementar cualquier historia, revisar sus preguntas abiertas: muchos contratos (`POST /api/internal/prices`, `job-detail`, `price-history`, errores) no tienen cuerpo definido todavía.
