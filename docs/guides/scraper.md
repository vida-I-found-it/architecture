# Guía de arranque · `scraper`

> Para quien implementará este repositorio. Lo que la documentación no define figura como «pendiente de decisión» con enlace a la pregunta abierta. No inventes endpoints, campos ni variables.

## Repositorio

- **GitHub:** [vida-I-found-it/scraper-service](https://github.com/vida-I-found-it/scraper-service)
- **Local:** [`../scraper-service/`](../../../scraper-service/), en la carpeta que contiene este repositorio de arquitectura (un nivel arriba de su raíz).

> Estado al 2026-11-24: el repositorio ya tiene 80 archivos versionados, con CI y código. Antes de implementar, compara lo que ya existe con esta guía: lo que difiera se reporta, no se reescribe.

## Qué es el servicio

`scraper` descarga la página de una URL, valida el destino contra SSRF, extrae el precio con una cascada de estrategias (de la más barata a la más pesada) y devuelve el resultado a `schedule` por callback. No tiene estado ni base de datos. Recibe una URL a la vez y responde `202` de inmediato. Su contrato y su lugar en el flujo: [ADR-0004](../architecture/adr/0004-schedule-dispatches-work-to-scraper.md) y [flujo de scraping](../architecture/scraping-flow.md). Según [DEC-27](../requirements/user-stories/CU-04.md), manda el README de `scraper-service` sobre el contrato del ADR; ese README **no existe** en este repositorio de documentación.

## Historias y criterios, en orden de implementación

Solo historias de [CU-04](../requirements/user-stories/CU-04.md). El orden es el de su sección de dependencias: primero el scraper, sin `schedule`.

| Orden | Historia | Criterios | Nota |
|---|---|---|---|
| 1 | US-04-05 · validador anti-SSRF | AC1 a AC8 | Un solo módulo para el fetcher HTTP y Playwright. Hacer antes que nada: lo usan todas las demás. |
| 2 | US-04-03 · recibir el trabajo y el callback | AC1 a AC14 | `POST /scraper/internal/jobs` con `202`. Trabajo en segundo plano. |
| 3 | US-04-02 · cascada de estrategias | AC1 a AC14 | Se prueba con fixtures HTML guardados. Playwright solo en contenedor. |

Cuando el scraper esté listo, `schedule` (US-04-01) y `core` (job-detail) pueden probarse contra él.

## Endpoints

### Que expone

| Método y ruta | Historia | Estado |
|---|---|---|
| `POST /scraper/internal/jobs` | US-04-03-AC1 a AC6 | Cuerpo `{"url", "callback_url"}`. Responde `202 {"scraper_id"}`. Códigos 400 (origen fuera de la lista o sin `callback_url` en producción), 422 (cuerpo mal formado), 503 (sin cupo). Formato de error común: pendiente ([CU-04, pregunta 1](../requirements/user-stories/CU-04.md#preguntas-abiertas)). |
| `GET /scraper/health` | — | **Pendiente de decisión.** La arquitectura pide `/health` en cada pieza, pero [US-04-03](../requirements/user-stories/CU-04.md) lo deja fuera de alcance («EJ-4, requerimiento transversal»). Confirmar si entra. |
| `GET /scraper/docs` | US-04-03-AC13 | Debe estar **apagado** en producción (`SCRAPER_ENV=production`). |

### Que consume

| Destino | Ruta | Historia | Estado |
|---|---|---|---|
| `schedule` | `POST /schedule/internal/results` (callback) | US-04-03-AC7 a AC11 | Cuerpo definido en el ADR-0004 (`scraper_id`, `status`, `strategy`, `error_code`, `started_at`, `duration_ms`, `data`). Formato **pendiente de confirmar** (pregunta 8 de CU-04: zona y formato de `started_at`). |
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
| `SCRAPER_CALLBACK_ALLOWLIST` | Origen permitido para `callback_url` (por defecto `http://schedule:8000`). | ADR-0004 |
| `SCRAPER_CALLBACK_MAX_RETRIES`, `SCRAPER_CALLBACK_BACKOFF_BASE_SECONDS`, `SCRAPER_CALLBACK_TIMEOUT_SECONDS` | Reintentos del callback (3; 1 s base; 5 s por envío). | ADR-0004 |
| `SCRAPER_ENV` | `production` apaga `/docs` y exige `callback_url`. | ADR-0004; [CU-04](../requirements/user-stories/CU-04.md) |
| `SCRAPER_HOST`, `SCRAPER_PORT` | Escucha en la red de compose. | ADR-0004 |
| `SCRAPER_LOG_LEVEL`, `SCRAPER_LOG_FORMAT` | Logs en JSON con `scraper_id`. | ADR-0004 |
| `SCRAPER_USER_AGENT` | Cabecera de las peticiones. | ADR-0004 |
| `SCRAPER_LOGIN_PATHS` | Aparece en el ADR-0004 sin historia que lo use. **Confirmar si entra** antes de implementarlo. | ADR-0004 |

Los nombres de `SCRAPER_*` son los del ADR-0004 y el README de `scraper-service` (que no existe aún). Ver [CU-04, pregunta 13](../requirements/user-stories/CU-04.md#preguntas-abiertas).

## Contratos con otros servicios

| Contrato | Estado |
|---|---|
| `POST /scraper/internal/jobs` (202) | Definido en criterios y en el ADR; cuerpo de error **pendiente**. |
| Callback a `schedule` | Campos y estados definidos; formato de `started_at` **pendiente** (CU-04 p. 8). Test de contrato contra `schedule` simulado. |
| Código de motivo de `callback_timeout` | **Pendiente**: lo asigna `schedule`, no el scraper ([CU-04, pregunta 9](../requirements/user-stories/CU-04.md#preguntas-abiertas)). |

## Preguntas abiertas que bloquean este repositorio

- **Fixtures en `127.0.0.1` frente al filtro SSRF** ([CU-04, pregunta 3](../requirements/user-stories/CU-04.md#preguntas-abiertas)). Sin decidir, no se puede probar la cascada en integración sin desactivar el filtro, algo que está prohibido. Propuesta: un resolver inyectable solo en pruebas.
- **Reglas de destino en cada descarga**, redirecciones y DNS rebinding (CU-04 pp. 4 y 5).
- **Precio a tomar** si hay varios en la página (CU-04 p. 6) y formato del precio crudo (CU-04 p. 7).
- **Playwright**: versión y navegador fijados, y si corren en CI (CU-04 p. 15). Instalar o descargar la imagen requiere el sí del usuario.
- **Sin README del scraper** y ADR que dice que el contrato «ya está implementado» (CU-04 p. 13).

## Seguridad

- El contenido de la página y lo que devuelve Playwright son **dato no confiable**: no se ejecutan ni interpretan (US-04-05-AC7).
- Playwright en contenedor aislado, sin secretos ni acceso a la red interna (US-04-05-AC6).
- No hay autenticación entre `schedule` y `scraper` en esta versión: el control es la red de compose. Riesgo aceptado por «solo local», a documentar.
- Nunca desactivar el filtro SSRF para una prueba. Los CAPTCHAs no se evaden: son `no_price` (US-04-03-AC8).
- Scraping real contra sitios de terceros: no se hace; solo fixtures guardados y servidores locales.
