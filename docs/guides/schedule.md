# Guía de arranque · `schedule`

> Para quien implementará este repositorio. Lo que la documentación no define figura como «pendiente de decisión» con enlace a la pregunta abierta. No inventes endpoints, campos ni variables.

## Repositorio

- **GitHub:** [vida-I-found-it/schedule-service](https://github.com/vida-I-found-it/schedule-service)
- **Local:** [`../schedule-service/`](../../../schedule-service/), en la carpeta que contiene este repositorio de arquitectura (un nivel arriba de su raíz).

> Estado al 2026-11-24: el repositorio solo tiene `LICENSE` y `README.md`; el código está por escribir.

## Qué es el servicio

`schedule` es el motor de disparo (APScheduler en memoria, cargado desde la tabla `job` al arrancar, en un solo proceso: [ADR-0007](../architecture/adr/0007-schedule-apscheduler-loaded-from-postgres.md)): guarda los jobs de captura de cada alerta, los dispara dentro de las franjas horarias con tope diario, envía cada URL al `scraper`, recoge sus resultados y los entrega a `core` con reintentos (outbox). También avisa el fin de cada corrida a `core` y, en EJ-6, envía el correo diario de errores al administrador a través de `notify`. La arquitectura y el ADR que lo explican: [`ADR-0004`](../architecture/adr/0004-schedule-dispatches-work-to-scraper.md) y [`architecture.md`](../architecture/architecture.md#comunicación-entre-piezas). Aquí no se repiten.

## Historias y criterios, en orden de implementación

Orden tomado de las secciones de dependencias de cada historia.

| Orden | Historia | Criterios que toca `schedule` | Nota |
|---|---|---|---|
| 1 | [CU-03](../requirements/user-stories/CU-03.md) · US-03-03 | US-03-03-AC1 a AC12 | Tabla `job`, `POST /schedule/internal/jobs` (idempotente, lista blanca) y `GET /schedule/internal/jobs/{job_id}`. Hacer primero: lo usan `core` y el resto. |
| 2 | [CU-03](../requirements/user-stories/CU-03.md) · US-03-04 | US-03-04-AC1 a AC10 | Motor de franjas, tope de 2 al día, reloj inyectable. |
| 3 | [CU-04](../requirements/user-stories/CU-04.md) · US-04-01 | US-04-01-AC1 a AC12 | Ejecución por URL, envío secuencial al scraper, `POST /schedule/internal/results`, plazo por URL. |
| 4 | [CU-04](../requirements/user-stories/CU-04.md) · US-04-04 | US-04-04-AC1 a AC9 | Reintentos de `error` (4 intentos en total). |
| 5 | [CU-05](../requirements/user-stories/CU-05.md) · US-05-06 | US-05-06-AC1 a AC9 | Entrega a `core` con outbox y estado final por URL. |
| 6 | [CU-06](../requirements/user-stories/CU-06.md) · US-06-02 | US-06-02-AC1, AC6 y AC7 (lado emisor) | Aviso «corrida terminada» a `core`. |
| 7 | [CU-10](../requirements/user-stories/CU-10.md) · US-10-05 | US-10-05-AC1 a AC3 (lado emisor) y US-10-02-AC11 | Correo diario de errores. No envía nada si no hubo fallos. |

Para el paso 1 también aplica el orden de [CU-03](../requirements/user-stories/CU-03.md#dependencias-y-orden-de-implementación-sugerido): la historia se puede probar con un `core` simulado.

## Endpoints

### Que expone

| Método y ruta | Historia | Estado |
|---|---|---|
| `POST /schedule/internal/jobs` | US-03-03 | Cuerpo mínimo con las URLs en `payload.items`; `schedule` calcula el cron y lanza la primera corrida sin bloquear la respuesta. Códigos 201, 200, 400, 422 ([CU-03, D12 a D22](../requirements/user-stories/CU-03.md#decisiones-aprobadas-2026-11-24)). |
| `GET /schedule/internal/jobs/{job_id}` | US-03-03-AC8, AC9 | Devuelve el job sin `payload` ni *callbacks*; 404 si no existe (CU-03, D16 y D21). |
| `POST /schedule/internal/results` | US-04-01-AC5 a AC8 | Recibe el callback del `scraper`. Respuesta (200/204/503) y cuerpo: pendiente ([CU-04, pregunta 1](../requirements/user-stories/CU-04.md#preguntas-abiertas)). |
| `GET /schedule/health` | [CU-03](../requirements/user-stories/CU-03.md) US-03-03-AC11 | Ruta del prefijo mencionada en un criterio; el resto de rutas deben colgar de `/schedule/internal/*` o `/schedule/health`. |

Ninguna ruta pública (SCH-11). Sin `PUT`, `PATCH` ni `DELETE` sobre jobs (US-03-03-AC10).

### Que consume

| Destino | Ruta | Historia | Estado |
|---|---|---|---|
| `core` | `POST /api/internal/prices` | US-05-06 | Cuerpo en [CU-05, D5-1](../requirements/user-stories/CU-05.md#preguntas-abiertas); `alert_id` sale de `job.payload`. |
| `core` | `POST /api/internal/run-completed` | US-06-02 | Cuerpo `job_id`, `run_id`, `payload` (CU-03, D21). Respuesta pendiente. |
| `scraper` | `POST /scraper/internal/jobs` | US-04-01-AC2 | Cuerpo `{"url", "callback_url"}` (solo esos dos campos). |
| `notify` | `POST /notify/notifications` | US-10-05 | Plantilla `admin-alert-email`. Códigos: pendiente ([CU-10, pregunta 2](../requirements/user-stories/CU-10.md#preguntas-abiertas)). |

## Tablas y colecciones que posee

Fuente: [`data/scripts/schedule/schema.sql`](../data/scripts/schedule/schema.sql).

- `job` (índice `UX_JOB_EXTERNAL_KEY`; `last_run_at` manda tras un reinicio, [ADR-0007](../architecture/adr/0007-schedule-apscheduler-loaded-from-postgres.md)), `execution_type`, `job_run`, `job_execution` (`IX_JOB_EXECUTION_DUE`, `UX_JOB_EXECUTION_ONE_RUNNING_PER_RUN`), `job_callback_outbox` (`IX_JOB_CALLBACK_OUTBOX_RETRY`).
- `job_script` existe en el esquema, pero `python_script` queda fuera de alcance (US-03-03). No implementarlo sin una historia que lo pida.

Mongo: [`data/scripts/schedule/mongo-setup.js`](../data/scripts/schedule/mongo-setup.js). Según [CU-04](../requirements/user-stories/CU-04.md): `job_execution_result` (`_id` = `transaction_id`, `attempts` máximo 4, TTL de 90 días).

## Variables de entorno

Solo nombres que aparecen en la documentación. Ningún valor.

| Variable | Uso | Fuente |
|---|---|---|
| `SCHEDULE_SCRAPE_WINDOWS` | Franjas de captura (2 disparos al día). | [ADR-0004](../architecture/adr/0004-schedule-dispatches-work-to-scraper.md), [CU-03](../requirements/user-stories/CU-03.md) |
| `SCHEDULE_MAX_ACTIVE_RUNS` | Corridas activas a la vez. | ADR-0004 |
| `SCHEDULE_CALLBACK_ALLOWLIST` | Orígenes permitidos para `callback_config` y `run_callback_config`. Solo `core`. | ADR-0004; [CU-03, D7](../requirements/user-stories/CU-03.md#decisiones-aprobadas-2026-11-24) |
| `SCHEDULE_CALLBACK_DEADLINE_SECONDS` | Plazo por URL sin callback (120 por defecto). Debe ser mayor que el timeout del scraper más la entrega. | ADR-0004; [CU-04](../requirements/user-stories/CU-04.md) |
| `SCHEDULE_DELIVERY_MAX_RETRIES`, `SCHEDULE_DELIVERY_BACKOFF_BASE_SECONDS`, `SCHEDULE_DELIVERY_BACKOFF_CAP_SECONDS` | Reintentos del envío al scraper (3; 60 s base). | ADR-0004 |
| `SCHEDULE_ERROR_MAX_RETRIES`, `SCHEDULE_ERROR_RETRY_MIN_SECONDS`, `SCHEDULE_ERROR_RETRY_MAX_SECONDS` | Reintentos de `error` (3; entre 600 y 900 s). | ADR-0004 |
| `SCHEDULE_SWEEP_TIME` | Hora del barrido diario. | ADR-0004, [`scraping-flow.md`](../architecture/scraping-flow.md) |
| `ADMIN_ALERT_EMAIL` | Destinatario del correo de administrador. | [`architecture.md`](../architecture/architecture.md#configuración) |

Zona horaria: `SCHEDULE_TIMEZONE` (`America/Bogota` por defecto) para franjas y tope diario, todo en UTC en la base. `SCHEDULE_POLL_INTERVAL_SECONDS` (2): tarea periódica de las colas. La lista blanca valida origen y ruta y sale solo del entorno ([CU-03, D5, D20 y D24](../requirements/user-stories/CU-03.md#decisiones-aprobadas-2026-11-24)). 🔒 Antes de desplegar en proveedores distintos: HTTPS y autenticación entre servicios.

`SCHEDULE_ANALYSIS_TIMES` aparece en el ADR-0004 y en los requerimientos, pero DEC-33 hace que el análisis corra al terminar cada corrida. **No usar hasta resolver la contradicción** ([CU-08, pregunta 11](../requirements/user-stories/CU-08.md#preguntas-abiertas)).

Conexiones (PostgreSQL con el rol de `schedule` y MongoDB): la arquitectura las lista, sin nombre de variable definido.

## Contratos con otros servicios

| Contrato | Estado |
|---|---|
| Entrada de jobs desde `core` | Definida ([CU-03, D13 a D22](../requirements/user-stories/CU-03.md#decisiones-aprobadas-2026-11-24)). El `payload` de `scrape` es un modelo propio en el `openapi.json` (D25). |
| Lista blanca de callbacks | Regla definida: `schedule` solo acepta `core` ([ADR-0004](../architecture/adr/0004-schedule-dispatches-work-to-scraper.md), [CU-03, D7](../requirements/user-stories/CU-03.md#decisiones-aprobadas-2026-11-24)). |
| Envío al scraper | Cuerpo definido (`url`, `callback_url`); la respuesta `202 {scraper_id}` está en [US-04-03](../requirements/user-stories/CU-04.md). |
| Callback del scraper | Estados `ok`, `no_price`, `error` definidos; cuerpo sin formato de errores **pendiente** ([CU-04, pregunta 1](../requirements/user-stories/CU-04.md#preguntas-abiertas)). |
| Entrega a `core` | Política de reintento **pendiente** ([CU-05, pregunta 7](../requirements/user-stories/CU-05.md#preguntas-abiertas)). |
| Correo del administrador | Plantilla `admin-alert-email` definida; nombre `admin_alert` de EJ-6 **contradice** la plantilla ([CU-10, pregunta 16](../requirements/user-stories/CU-10.md#preguntas-abiertas)). |

## Preguntas abiertas que bloquean este repositorio

- Reintentos de `core` ante 4xx y política de entrega (CU-05 p. 7 y CU-06).
- Reintentos del envío agotado frente a «el trabajo queda bloqueado» y `failed` (CU-04 p. 10).

## Seguridad

- La lista blanca se compara por origen exacto, sin seguir redirecciones (US-03-03-AC6).
- El `payload` del job y los logs no llevan correos ni tokens (US-03-01-AC9).
- El secreto HMAC del enlace de baja **no** se configura en `schedule` (DEC-13).
- Sin autenticación entre servicios en esta versión: el control es la red local.
- Los errores no muestran detalles internos ni trazas (US-03-03).
