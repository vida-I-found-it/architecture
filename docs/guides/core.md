# Guía de arranque · `core`

> Para el agente o la persona que implementará este repositorio. Todo lo que la documentación no define figura como «pendiente de decisión» con un enlace a la pregunta abierta. No inventes endpoints, campos ni variables: si falta algo, pregunta.

## Repositorio

- **GitHub:** [vida-I-found-it/core-service](https://github.com/vida-I-found-it/core-service)
- **Local:** [`../core-service/`](../../../core-service/), en la carpeta que contiene este repositorio de arquitectura (un nivel arriba de su raíz).

> Estado al 2026-11-24: el repositorio solo tiene `LICENSE` y `README.md`; el código está por escribir.

## Qué es el servicio

`core` es la API pública de la versión y dueño de los datos: alertas, URLs, suscripciones, chequeos, análisis y vistas de lectura. Recibe los resultados de `schedule` en los endpoints internos, pide los jobs a `schedule` y los avisos a `notify`. La responsabilidad y el mapa de piezas están en [`architecture.md`](../architecture/architecture.md#comunicación-entre-piezas); aquí no se repiten.

## Historias y criterios, en orden de implementación

El orden sigue las dependencias de cada historia (ver [`README`](../requirements/user-stories/README.md) de historias). Las historias de `schedule`, `scraper`, `notify` o frontend solo se mencionan cuando `core` tiene una parte.

| Orden | Historia | Criterios que toca `core` | Nota |
|---|---|---|---|
| 1 | [CU-02](../requirements/user-stories/CU-02.md) · alta de alerta | US-02-01-AC1 a AC14; US-02-02-AC1 a AC5; US-02-03-AC4; US-02-04-AC2 a AC4 y AC4 de `GET /api/alert-modes`; US-02-05-AC2 | Base de datos y `POST /api/alerts`. Ver [pregunta 4](../requirements/user-stories/CU-02.md#preguntas-abiertas) (cuerpo de la respuesta). |
| 2 | [CU-03](../requirements/user-stories/CU-03.md) · programar la captura | US-03-01-AC1 a AC9; US-03-02-AC1 a AC6 | Cliente de `schedule` tras una interfaz, fuera de la transacción del alta. |
| 3 | [CU-04](../requirements/user-stories/CU-04.md) · `job-detail` | US-04-01-AC1 (lado de `core`) | Endpoint que pide `schedule` para saber qué URLs capturar. Cuerpo sin definir. |
| 4 | [CU-05](../requirements/user-stories/CU-05.md) · procesar y almacenar | US-05-01-AC1 a AC12; US-05-02-AC1 a AC9; US-05-03-AC1 a AC8; US-05-04-AC1 a AC5; US-05-05-AC1 a AC10 | Normalizador y validador como funciones puras. `POST /api/internal/prices`. |
| 5 | [CU-06](../requirements/user-stories/CU-06.md) · análisis | US-06-01-AC1 a AC16; US-06-02-AC1 a AC7; US-06-03 (AC5 y AC7 de backend); US-06-04-AC1 a AC8; US-06-05-AC1 a AC5 | `POST /api/alerts/{alert_id}/analysis` y `POST /api/internal/run-completed`. |
| 6 | [CU-10](../requirements/user-stories/CU-10.md) · aviso desde `core` | US-10-01-AC1 a AC13 | Llamada a `notify`, después del commit del análisis. |
| 7 | [CU-07](../requirements/user-stories/CU-07.md) · dashboard (lectura) | US-07-01-AC1 a AC7; US-07-02-AC1 a AC11 y AC14; US-07-03-AC1 a AC6; US-07-04-AC1 a AC6; US-07-05-AC1 a AC5; US-07-06-AC1 a AC14 (prototipo) | Solo lectura. Enmascarado de correos en el backend. |
| 8 | [CU-08](../requirements/user-stories/CU-08.md) · histórico (lectura) | US-08-01-AC1 a AC11; US-08-04-AC1, AC6 y AC7 (backend) | `GET /api/alerts/{alert_id}/price-history`. |
| 9 | [CU-11](../requirements/user-stories/CU-11.md) · baja | US-11-02-AC1 a AC10; US-11-03-AC1 a AC9; US-11-04-AC3 a AC6 | Token HMAC; respuesta uniforme. |

Los criterios de presentación (la mayoría de `US-07-*`, `US-08-*`, `US-11-01`) son del frontend; `core` solo debe cumplir lo que dice el backend.

## Endpoints

### Que expone

| Método y ruta | Historia | Estado |
|---|---|---|
| `POST /api/alerts` | US-02-01, US-02-02, US-02-04 | Ruta según la historia; cuerpo y respuesta pendientes ([CU-02, pregunta 4](../requirements/user-stories/CU-02.md#preguntas-abiertas)). |
| `GET /api/alert-modes` | US-02-04-AC4 | Responde los modos y marca solo `url`. Formato pendiente. |
| `GET /api/alerts` | US-07-01 | Lista. Cuerpo y paginación pendientes ([CU-07, preguntas 1 y 2](../requirements/user-stories/CU-07.md#preguntas-abiertas)). |
| `GET /api/alerts/{alert_id}` | US-07-02, US-07-03, US-07-04, US-07-06 | Detalle. Cuerpo pendiente (CU-07, pregunta 1). |
| `GET /api/alerts/{alert_id}/price-history` | US-08-01, US-08-04 | Histórico. Cuerpo pendiente ([CU-08, pregunta 1](../requirements/user-stories/CU-08.md#preguntas-abiertas)). |
| `POST /api/alerts/{alert_id}/analysis` | US-06-03 | Análisis manual. Respuesta pendiente ([CU-06, pregunta 1](../requirements/user-stories/CU-06.md#preguntas-abiertas)). |
| `POST /api/subscriptions/{subscription_id}/unsubscribe` | US-11-02, US-11-03 | Dónde viaja el token: pendiente ([CU-11, pregunta 2](../requirements/user-stories/CU-11.md#preguntas-abiertas)). |
| `POST /api/internal/prices` | US-05-01 a US-05-05 | Llamado por `schedule`. Cuerpo pendiente ([CU-05, pregunta 1](../requirements/user-stories/CU-05.md#preguntas-abiertas)). |
| `POST /api/internal/run-completed` | US-06-02 | Llamado por `schedule`. Cuerpo: `job_id` y `run_id`. Respuesta pendiente. |
| `GET /api/internal/job-detail` | US-04-01-AC1 | Llamado por `schedule`. Parámetros y cuerpo pendientes ([CU-04, pregunta 1](../requirements/user-stories/CU-04.md#preguntas-abiertas)). |

Ninguna ruta de escritura sobre `/api/alerts/{alert_id}`: la alerta es inmutable (US-02-03-AC4). Los endpoints `/api/internal/*` no tienen autenticación en esta versión; solo se publican en `127.0.0.1` ([`architecture.md`](../architecture/architecture.md#configuración)).

Health: la arquitectura pide `GET /<prefijo>/health` en cada pieza, pero ninguna historia fija la ruta de `core`. **Pendiente de decisión** (prefijo).

### Que consume

| Destino | Ruta | Historia | Estado |
|---|---|---|---|
| `schedule` | `POST /schedule/internal/jobs` | US-03-01, US-03-02 | Ruta definida en las historias; cuerpo pendiente ([CU-03, pregunta 1](../requirements/user-stories/CU-03.md#preguntas-abiertas)). |
| `schedule` | `GET /schedule/internal/jobs/{job_id}` | US-03-03-AC8 | Qué consulta `core` con él: pendiente (CU-03, pregunta 1). |
| `notify` | `POST /notify/notifications` | US-10-01 | Cuerpo y códigos pendientes ([CU-10, preguntas 2 y 4](../requirements/user-stories/CU-10.md#preguntas-abiertas)). |

## Tablas que posee

Fuente: [`data/scripts/core/schema.sql`](../data/scripts/core/schema.sql). Las historias usan estos nombres en minúsculas.

- Alta y configuración: `alert`, `alert_url`, `subscription`. Índice único `UX_ALERT_SCHEDULE_JOB` sobre `alert.schedule_job_id`.
- Chequeos: `alert_snapshot` (particionada por `checked_at`; hoy solo existe `alert_snapshot_2026`, ver [CU-05, pregunta 3](../requirements/user-stories/CU-05.md#preguntas-abiertas)).
- Análisis: `alert_analysis`, `price_anomaly`.
- Vistas: `v_alert_url_last_check`, `v_alert_best_price`, `v_site_stats_daily`.
- `alert_snapshot` no tiene columna `error_code`: pendiente de decidir ([CU-05, pregunta 4](../requirements/user-stories/CU-05.md#preguntas-abiertas)).
- Hay también tablas de catálogo (`currency`, `tag`, `alert_tag`, `site_adapter`) que las historias no usan; no implementar sin una historia que las pida.

Mongo: [`data/scripts/core/mongo-setup.js`](../data/scripts/core/mongo-setup.js). Las historias no nombran colecciones de `core`; `exchange_rate` aparece solo como fuera de alcance (US-05-01).

## Variables de entorno

Solo nombres que aparecen en la documentación. Ningún valor.

| Variable | Uso | Fuente |
|---|---|---|
| `ALERT_CREATION_MODES` | Modos de alta; por defecto `url`. Valor desconocido o `keyword`: pendiente. | [CU-02, pregunta 7](../requirements/user-stories/CU-02.md#preguntas-abiertas) |
| `ANOMALY_STRATEGY` | Estrategia de anomalía activa; nombre desconocido debe fallar al arrancar (propuesta). | [ADR-0005](../architecture/adr/0005-anomaly-detection-as-strategy.md), [CU-06, pregunta 7](../requirements/user-stories/CU-06.md#preguntas-abiertas) |

Sin nombre definido (pendiente): URL base de `schedule`, UUID del usuario fijo y `system` del proyecto (INF-3), URL de `notify`, orígenes permitidos (CORS), secreto HMAC del enlace de baja (solo aquí, DEC-13). Ver [`architecture.md`, Configuración](../architecture/architecture.md#configuración) y [CU-10, pregunta 19](../requirements/user-stories/CU-10.md#preguntas-abiertas).

## Contratos con otros servicios

| Contrato | Con quién | Estado |
|---|---|---|
| Crear job de captura | `schedule` | Ruta y códigos definidos en criterios (201/200, 400, 5xx); cuerpo **pendiente de decisión** ([CU-03, pregunta 1](../requirements/user-stories/CU-03.md#preguntas-abiertas)). |
| Detalle del job para la captura | `schedule` → `core` | **Pendiente de decisión** ([CU-04, pregunta 1](../requirements/user-stories/CU-04.md#preguntas-abiertas)). |
| Resultado por URL | `schedule` → `core` | **Pendiente de decisión** ([CU-05, pregunta 1](../requirements/user-stories/CU-05.md#preguntas-abiertas)). |
| Corrida terminada | `schedule` → `core` | Ruta y cuerpo (`job_id`, `run_id`) definidos; respuesta **pendiente** ([CU-06, pregunta 1](../requirements/user-stories/CU-06.md#preguntas-abiertas)). |
| Aviso de baja de precio | `core` → `notify` | Ruta definida; cuerpo y campos del `payload` **pendientes** ([CU-10, preguntas 2 y 4](../requirements/user-stories/CU-10.md#preguntas-abiertas)). |
| Error de contrato | todos | Formato de error común **pendiente** (no hay formato único en la documentación). |

## Preguntas abiertas que bloquean este repositorio

Las que impiden cerrar un criterio sin inventar. Ver cada historia para el detalle.

- **Contratos:** cuerpos de `POST /api/alerts` y de las rutas internas (CU-02 p. 4; CU-03 p. 1; CU-04 p. 1; CU-05 p. 1; CU-06 p. 1).
- **Carrera** entre el alta y el disparo del job (CU-03 p. 2 y CU-04 p. 2). Propuesta: `alert_id` en el `payload`.
- **Primera corrida fuera de franja** y su cuenta en el tope de 2 (CU-03 p. 3).
- **Zona horaria y minuto del cron** (CU-03 pp. 7 y 8): `core` calcula el cron.
- **Validación de datos del sitio:** formato del precio, moneda ausente, página de error (CU-05 pp. 8 a 10).
- **Token de baja:** dependencia con el `id` al insertar (CU-11 p. 1) y respuesta uniforme (CU-11 p. 4).
- **Mejor precio:** vista o último análisis (CU-07 p. 13). Pendiente de decisión antes del dashboard.
- **Formato del correo enmascarado** (CU-02 p. 3 y CU-07 p. 5).
- **Token de baja en el `payload` de `notify`** (CU-10 p. 1, 🔒): contradice SUB-3; hay que decidir antes de implementar el aviso.

## Seguridad

- No registrar correos, `payload`, enlace de baja ni token en logs (US-10-01-AC13, US-11-04-AC2).
- Enmascarar el correo en el backend antes de serializar (US-07-05).
- `POST /api/internal/prices` y `run-completed` sin autenticación en esta versión: riesgo aceptado por «solo local», a documentar en el README del repo (CU-03 y CU-06, pregunta 11).
- Entradas no confiables: consultas parametrizadas; el texto del sitio se guarda saneado y nunca se interpreta como HTML (US-05-05).
