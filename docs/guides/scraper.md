# Guía de arranque · `scraper`

> Para quien implementará este repositorio. Lo que la documentación no define figura como «pendiente de decisión» con enlace a la pregunta abierta. No inventes endpoints, campos ni variables.

## Repositorio

- **GitHub:** [vida-I-found-it/scraper-service](https://github.com/vida-I-found-it/scraper-service)
- **Local:** [`../scraper-service/`](../../../scraper-service/), en la carpeta que contiene este repositorio de arquitectura (un nivel arriba de su raíz).

> Estado al 2026-11-27: el repositorio tiene código, README, CI y Docker. Difiere de esta guía en los puntos de [Brechas del código](#brechas-del-código-frente-a-esta-arquitectura-2026-11-27); esta arquitectura es la fuente de verdad.

## Qué es el servicio

`scraper` descarga la página de una URL, valida el destino contra SSRF, extrae el precio con una cascada de estrategias (de la más barata a la más pesada) y devuelve el resultado a `schedule` por callback. No tiene estado ni base de datos. Recibe una URL a la vez y responde `202` de inmediato. Su contrato y su lugar en el flujo: [ADR-0004](../architecture/adr/0004-schedule-dispatches-work-to-scraper.md) y [flujo de scraping](../architecture/scraping-flow.md). Según [DEC-27](../requirements/user-stories/CU-04.md), manda el README de `scraper-service` sobre el contrato del ADR; ese README **no existe** en este repositorio de documentación.

## Historias y criterios, en orden de implementación

Solo historias de [CU-04](../requirements/user-stories/CU-04.md). El orden es el de su sección de dependencias: primero el scraper, sin `schedule`.

| Orden | Historia | Criterios | Nota |
|---|---|---|---|
| 1 | US-04-05 · validador anti-SSRF | AC1 a AC12 | Un solo módulo para el fetcher HTTP y Playwright. Hacer antes que nada: lo usan todas las demás. |
| 2 | US-04-03 · recibir el trabajo y el callback | AC1 a AC17 | `POST /scraper/internal/jobs` con `202`. Trabajo en segundo plano. |
| 3 | US-04-02 · cascada de estrategias | AC1 a AC15 | Se prueba con fixtures HTML guardados. Playwright solo en contenedor. |
| — | US-04-06 · limpieza de `data` (`clean`) | AC1 a AC8 | Su posición en este orden no está definida en CU-04. AC9 es de `schedule`. |

Cuando el scraper esté listo, `schedule` (US-04-01) puede probarse contra él.

## Endpoints

### Que expone

| Método y ruta | Historia | Estado |
|---|---|---|
| `POST /scraper/internal/jobs` | US-04-03-AC1 a AC6 | Cuerpo `{"url", "callback_url", "clean"}`; `clean` es booleano opcional, `false` por defecto (US-04-06-AC1 a AC3). Responde `202 {"scraper_id"}`. Códigos 400 (origen fuera de la lista o sin `callback_url` en producción), 422 (cuerpo mal formado), 503 (sin cupo). Formato de error común: pendiente ([CU-04, pregunta 1](../requirements/user-stories/CU-04.md#preguntas-abiertas)). |
| `GET /scraper/health` | — | **Pendiente de decisión.** La arquitectura pide `/health` en cada pieza, pero [US-04-03](../requirements/user-stories/CU-04.md) lo deja fuera de alcance («EJ-4, requerimiento transversal»). Confirmar si entra. |
| `GET /scraper/docs` | US-04-03-AC13 | Debe estar **apagado** en producción (`SCRAPER_ENV=production`). |

### Que consume

| Destino | Ruta | Historia | Estado |
|---|---|---|---|
| `schedule` | `POST /schedule/internal/results` (callback) | US-04-03-AC7 a AC11 | Cuerpo definido en el ADR-0004 (`scraper_id`, `status`, `strategy`, `error_code`, `started_at`, `duration_ms`, `data`; con US-04-06, también `clean`). `started_at`: RFC 3339 en UTC con `Z` (CU-04, D27). |
| Sitios de las URLs | GET (HTTP) y navegador (Playwright) | US-04-02, US-04-05 | Solo a los sitios de las URLs y al origen de la lista blanca (AC12). |

## Tablas y colecciones que posee

Ninguna. El scraper no tiene base de datos ni acceso a las de otros servicios (US-04-05-AC6).

## Variables de entorno

Solo nombres que aparecen en la documentación. Ningún valor.

| Variable | Uso | Fuente |
|---|---|---|
| `SCRAPER_STRATEGY_ORDER` | Orden de la cascada. | ADR-0004; [CU-04](../requirements/user-stories/CU-04.md) |
| `SCRAPER_URL_TIMEOUT_SECONDS` | Tope por URL (90 s). | ADR-0004 |
| `SCRAPER_HTTP_TIMEOUT_SECONDS` (10), `SCRAPER_BROWSER_TIMEOUT_SECONDS` (30), `SCRAPER_XHR_TIMEOUT_SECONDS` (20) | Timeouts por estrategia. | ADR-0004 |
| `SCRAPER_MAX_RESPONSE_BYTES` | Lectura máxima de una página (5 000 000). | ADR-0004 |
| `SCRAPER_MAX_CONCURRENCY` | URLs en proceso a la vez (2); más, 503. | ADR-0004 |
| `SCRAPER_CALLBACK_ALLOWLIST` | Origen y ruta permitidos para `callback_url` (CU-04, D19); solo por variable de entorno. | ADR-0004 |
| `SCRAPER_CALLBACK_MAX_RETRIES`, `SCRAPER_CALLBACK_BACKOFF_BASE_SECONDS`, `SCRAPER_CALLBACK_TIMEOUT_SECONDS` | Reintentos del callback (3; 1 s base; 5 s por envío). | ADR-0004 |
| `SCRAPER_ENV` | `production` apaga `/docs` y exige `callback_url`. | ADR-0004; [CU-04](../requirements/user-stories/CU-04.md) |
| `SCRAPER_HOST`, `SCRAPER_PORT` | Escucha en la red de compose. | ADR-0004 |
| `SCRAPER_LOG_LEVEL`, `SCRAPER_LOG_FORMAT` | Logs en JSON con `scraper_id`. | ADR-0004 |
| `SCRAPER_USER_AGENT` | Cabecera de las peticiones. | ADR-0004 |
| `SCRAPER_LOGIN_PATHS` | Aparece en el ADR-0004 sin historia que lo use. **Confirmar si entra** antes de implementarlo. | ADR-0004 |

Los nombres de `SCRAPER_*` son los del ADR-0004.

## Contratos con otros servicios

| Contrato | Estado |
|---|---|
| `POST /scraper/internal/jobs` (202) | Definido en criterios y en el ADR; cuerpo de error **pendiente**. |
| Callback a `schedule` | Campos y estados definidos; `started_at` en RFC 3339 UTC con `Z` (CU-04, D27). Test de contrato contra `schedule` simulado. Con `clean: true`, la limpieza puede producir `no_price` con `invalid_price` (US-04-06-AC4); falta añadir ese código a las listas cerradas. |
| Código de motivo de `callback_timeout` | **Pendiente**: lo asigna `schedule`, no el scraper ([CU-04, pregunta 9](../requirements/user-stories/CU-04.md#preguntas-abiertas)). |

## Preguntas abiertas que bloquean este repositorio

Las de fixtures, reglas de destino, redirecciones, varios precios y navegador quedaron decididas en [CU-04, D13 a D26](../requirements/user-stories/CU-04.md#decisiones-aprobadas-2026-11-24) (incluye `SCRAPER_MAX_CONCURRENCY` = N URLs en paralelo y el proxy de salida, sin probar).

- Las diferencias de la sección de brechas.

## Brechas del código frente a esta arquitectura (2026-11-27)

Revisión de solo lectura de `scraper-service` en `main`, commit `5bc3b8d`. **No se ejecutaron sus pruebas** ni se leyó todo el código (quedan, entre otros, las estrategias custom, `app.py` y parte del cliente HTTP). Manda esta arquitectura ([CU-04, D28](../requirements/user-stories/CU-04.md#decisiones-aprobadas-2026-11-24)).

| Prioridad | Arquitectura | Código hoy |
|---|---|---|
| 🔴 Bloquea la integración | `schedule` envía `clean: true` (US-04-06) | `JobRequest` no tiene `clean` y rechaza campos extra: respondería `422` a **todos** los envíos |
| 🔴 Seguridad | El tráfico del navegador sale por un proxy que valida y fija la IP, incluidos WebSocket y WebRTC (US-04-05-AC10) | Sin proxy: valida cada petición y Chromium resuelve el DNS por su cuenta (riesgo que el propio código declara). La interceptación usada (`page.route`) no cubre WebSocket ni WebRTC según la librería; no se probó |
| 🟠 | `invalid_price` y limpieza de `data` (US-04-06) | No existen |
| 🟠 | Con varios precios, solo la oferta inequívoca (US-04-02-AC15) | En JSON-LD toma la primera oferta válida |
| 🟠 | La lista blanca del callback valida origen y ruta (D19) | Solo origen; la ruta no cuenta |
| 🟡 | Logs sin parámetros de URL, `data` ni correos (US-04-03-AC15) | `httpx` está silenciado; faltan por revisar las trazas de `logger.exception` y de Playwright |
| 🟡 | Callback de 64 KB como máximo, recortando opcionales (US-04-03-AC17) | No se mide; textos e imágenes están acotados, `price` no tiene largo máximo |
| 🟡 | Nombre de la estrategia `microdata_regex` (ADR-0004) | Usa `microdata` |

**Coincide:** `202 {scraper_id}`, `400` y `503`; `SCRAPER_MAX_CONCURRENCY` (2 por defecto); tiempos de 90, 10, 30 y 20 s; callback con 3 reintentos (1, 2 y 4 s), sin reintentar 4xx; los 12 códigos anteriores a `invalid_price`; `started_at` en UTC; solo `http`/`https` e IP públicas, todas las IP validadas, máximo 5 redirecciones en el cliente HTTP, IP fijada en ese cliente y DNS fallido como `error · network`; `service workers` bloqueados; `SCRAPER_LOGIN_PATHS` se usa para `login_required`.

**A decidir (el código y la arquitectura no encajan y conviene ajustar la arquitectura):**
- El código **rechaza URLs con credenciales**; D13 dice que no se revisan. Quitarlo debilitaría la seguridad.
- El navegador deja pasar `data:`, `blob:` y `about:` (no salen a la red); US-04-05-AC1 menciona bloquear `data:`.
- El cupo del scraper sigue ocupado mientras entrega el callback (hasta unos 22 s más), lo que reduce la capacidad.

## Seguridad

- El contenido de la página y lo que devuelve Playwright son **dato no confiable**: no se ejecutan ni interpretan (US-04-05-AC7).
- Playwright en contenedor aislado, sin secretos ni acceso a la red interna (US-04-05-AC6).
- No hay autenticación entre `schedule` y `scraper` en esta versión: el control es la red de compose. Riesgo aceptado por «solo local», a documentar.
- Nunca desactivar el filtro SSRF para una prueba. Los CAPTCHAs no se evaden: son `no_price` (US-04-03-AC8).
- Scraping real contra sitios de terceros: no se hace; solo fixtures guardados y servidores locales.
