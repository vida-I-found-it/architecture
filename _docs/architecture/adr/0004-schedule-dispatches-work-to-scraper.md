# ADR 0004 · `schedule` envía el trabajo al scraper, una URL a la vez, y este responde por un callback configurable

- **Estado:** Aceptada
- **Fecha:** 2026-11-11 · **Revisión:** 2026-11-12 (unidad de trabajo por URL, tres estados de resultado, análisis separado del scraping y barrido diario de errores) · 2026-11-17 (alineado con el README de `scraper-service`, que manda sobre el contrato del scraper)
- **Reemplaza (en parte):** el modelo de *pull* del [ADR-0001](0001-repo-and-service-structure.md) («el scraper es un cliente, no un servidor») y la forma de entrega de SCR-20
- **Requerimientos / casos de uso afectados:** SCR-1, SCR-8, SCR-20, CU-03, CU-04, CU-05, CU-06, CU-10 · eventos EV-17, EV-18, EV-26 y EV-27 del [flujo de scraping](../scraping-flow.md)

> **Enmienda (2026-11-22, DEC-33):** el análisis ya no es un job agendado ni corre a horas propias: arranca por alerta cuando `schedule` avisa «corrida terminada» (`job.run_callback_config`, tabla `job_run`), o a mano desde la interfaz; sale `SCHEDULE_ANALYSIS_TIMES`. `job.callback_type` es opcional. La plantilla del barrido se llama `admin-alert-email`.

> **Enmienda (2026-11-22, DEC-32):** el resultado de cada URL no se repite en el PostgreSQL de `schedule` (solo `completed`/`failed`); el documento de Mongo guarda un array `attempts` con un elemento por intento. El barrido es un job `error_sweep` creado al arrancar, que también reporta los callbacks a `core` agotados.

> **Enmienda (2026-11-22, DEC-29):** `price_snapshot` (por cambio) se reemplazó por `alert_snapshot`, una fila por chequeo con su estado; el último precio, el mejor precio y las estadísticas por sitio ya no se materializan, son vistas. Donde este ADR dice «snapshot», léase «chequeo `ok`». Ver [modelo de datos](../../data/data-model.md).

## Contexto

Hasta ahora el scraper hacía *pull*: preguntaba a `schedule` si había trabajo y le entregaba el resultado en la misma llamada. Eso lo dejaba sin puertos entrantes, pero tenía un costo: nadie sabía si estaba vivo y, si caía, no había una forma natural de detectarlo ni de reintentar el trabajo. Las tareas de scraping son asíncronas y el objetivo final del flujo es el scraper, así que conviene que quien las dispara (`schedule`) sea quien lo invoque.

## Decisión

1. **`schedule` inicia el trabajo.** Al dispararse el job de una alerta, pide a `core` el detalle (la lista de URLs) y **crea una ejecución por URL** (`job_execution`, con su propio `transaction_id`). Cada URL es una unidad de trabajo independiente; `schedule` la trata como un elemento opaco de la lista.
2. **Las URLs se envían una tras otra, no en paralelo.** `schedule` envía la primera con `POST /scraper/internal/jobs` (una URL por petición) junto con la **función callback**, **espera su callback** y recién entonces envía la siguiente. La espera es asíncrona: queda como estado guardado, no como un hilo bloqueado. Por rendimiento y para no cargar al scraper, una corrida usa un solo hilo del scraper.
3. **El scraper responde de inmediato «recibido» (202)** y trabaja en segundo plano. No retiene la conexión.
4. **El resultado de una URL es uno de tres estados:**

   | Estado | Qué significa | Qué hace `schedule` |
   |--------|---------------|---------------------|
   | `ok` | Se obtuvo un precio válido | Entrega **de inmediato** ese resultado a `core` (callback propio, SCH-14); no acumula ni espera a las demás |
   | `no_price` | Resultado **definitivo**: sin precio (`not_found`), producto retirado (`gone`), exige sesión (`login_required`), otro 4xx (`http_4xx`) o bloqueo del sitio o de la URL (`blocked_ssrf`, `blocked_403`, `blocked_captcha`) | Lo entrega a `core`; **no se reintenta** |
   | `error` | No se obtuvo una respuesta fiable: `timeout`, `network`, `http_5xx`, `http_429` o `internal` (excepción del scraper) | **Reinyecta** esa URL, hasta 3 veces (parametrizable, SCR-8) con espera de 10–15 min. Agotados, entrega `error` a `core` y la ejecución queda `failed` |

   El scraper **no reintenta**: hace una pasada por URL y devuelve el estado con lo que logró. Quien administra todos los reintentos es `schedule`.
5. **El destino del callback es configuración que viaja con el trabajo**, no una dirección fija en el scraper. En el ejercicio el callback del scraper apunta a `schedule` (`POST /schedule/internal/results`) y el de `schedule` a `core` (`POST /api/internal/prices`). Así se mantiene la regla de que el scraper no llama a `core`, ahora **por configuración** y no por diseño rígido.
6. **El envío va detrás de una interfaz** (`ScraperDispatcher`). Hoy es HTTP; si el volumen o la disponibilidad lo exigen, puede sustituirse por una cola (Redis + Arq) sin reescribir `schedule`.
7. **El scraping solo guarda datos; el análisis decide los avisos.** Son dos procesos distintos (desde DEC-33, el análisis arranca al terminar la corrida de la alerta; ver la enmienda). Al recibir un resultado, `core` solo **sanea, normaliza, valida y guarda el snapshot** si cambió el precio (CU-05); no calcula el mejor precio ni avisa. El **análisis** (CU-06 y CU-10) es otro proceso de `core`: calcula el mejor precio, marca las caídas anómalas, compara con el mejor precio anterior y pide el aviso a `notify`. La primera vez no hay contra qué comparar, así que no avisa. Se lanza de dos formas: desde la interfaz de usuario, o por un job agendado en `schedule` (`api_call`). Un análisis genera a lo más un aviso por alerta.
8. **Frecuencia parametrizable.** Por día hay **2 capturas y 2 análisis** por defecto, cada análisis un tiempo después de su captura; es configuración y puede reducirse a 1 y 1 (R2 mantiene el tope de 2 capturas al día).
9. **Los errores se avisan al administrador en un barrido diario, no uno por uno.** Enlazar cada ejecución con su alerta para armar un correo por alerta es costoso, así que una **tarea agendada interna de `schedule` corre todos los días sin falta**, reúne las ejecuciones que quedaron `failed` en el día y pide **un solo correo** a `notify` (`POST /notify/notifications`, el mismo endpoint que usa `core`), agrupado por alerta. Se reutilizan el envío por correo y el outbox de reintento de `notify`; a `schedule` no se le añade SMTP. La dirección del administrador es configuración por entorno.
10. **El contrato del scraper lo define el README de `scraper-service`** y este ADR lo adopta (ver «Contrato con el scraper»). Consecuencia: el scraper **no conoce** nuestro `transaction_id` ni la unidad de trabajo; `schedule` correlaciona cada callback por el `scraper_id` que el scraper devuelve en el `202`.

## Contrato con el scraper

La fuente es el [README de `scraper-service`](https://github.com/vida-I-found-it/scraper-service#readme); aquí se resume lo que `schedule` y `core` necesitan.

**Petición** `POST /scraper/internal/jobs`: `{ "url", "callback_url" }`. Respuestas: `202 {scraper_id}`, `400` (callback fuera de la lista blanca, o ausente en producción), `422` (cuerpo mal formado), `503` (sin cupo de concurrencia).

**Callback** `POST <callback_url>`:

| Campo | Contenido |
|-------|-----------|
| `scraper_id` | Identificador que el scraper dio en el `202`; es la llave de correlación |
| `status` | `ok`, `no_price` o `error` |
| `strategy` | Estrategia ganadora: `structured_data`, `microdata_regex`, `browser`, `xhr` o `custom:<nombre>` (nulo si no hubo precio) |
| `error_code` | Motivo (tabla de abajo); nulo en `ok` |
| `started_at`, `duration_ms` | Inicio y duración de la pasada |
| `data` | `price` (**crudo**, texto), `list_price`, `currency`, `price_valid_until`, `in_stock`, `title`, `brand`, `sku`, `gtin`, `mpn`, `images` (máx. 10, solo URLs, nunca descargadas). Todo opcional salvo el precio en `ok`; `core` normaliza |

| `status` | `error_code` posibles |
|----------|-----------------------|
| `no_price` | `not_found`, `gone`, `login_required`, `http_4xx`, `blocked_ssrf`, `blocked_403`, `blocked_captcha` |
| `error` | `timeout`, `network`, `http_5xx`, `http_429`, `internal` |

**Correlación y carrera:** `schedule` marca la ejecución `running` antes de enviar y guarda el `scraper_id` del `202` en `job_execution.SCRAPER_ID`. Si el callback llega antes de ese guardado, `schedule` no conoce aún el `scraper_id` y responde **503**: el scraper reintenta (1, 2 y 4 s) y la carrera se resuelve sola. Si sigue desconocido tras los reintentos, el plazo del callback convierte la URL en `error` (EV-17).

**Cascada:** un fallo de descarga (404, 403, captcha, *timeout*) **no corta** la cascada; se sigue con la siguiente estrategia y, si al final no hubo precio, el motivo es el del **primer** fallo. La excepción es `blocked_ssrf`, que siempre corta. Una estrategia que lanza una excepción no corta; si nada acierta y no hubo fallo de descarga, el resultado es `error · internal`.

**Entrega del callback:** si falla por red, *timeout* o 5xx, el scraper reintenta con backoff exponencial (1, 2 y 4 s, tope de 5 s por envío). Es un mecanismo propio del scraper y distinto del reintento de `schedule` a `core`. Sin `callback_url`, y fuera de producción, el scraper imprime el resultado por consola (solo para pruebas).

## Seguridad: qué cambia

- El principio «el scraper no tiene puertos entrantes» se reinterpreta como **«no tiene puertos expuestos fuera de la red interna»**. En el ejercicio solo es alcanzable dentro de la red de docker-compose, sin publicar su puerto al equipo. En producción se restringe por firewall a `schedule`.
- **Sin autenticación en el ejercicio, el control es la red.** Es coherente con «sin login ni token entre piezas». En el proyecto completo se usa el JWT de servicio (`aud=system`) como en el resto de las llamadas internas.
- **El destino del callback es una lista blanca de backends registrados**, definida en la configuración de entorno de quien recibe el trabajo (no en el cuerpo de la petición). Si fuera libre, quien pudiera enviar un trabajo haría que el scraper entregue lo recopilado a una dirección arbitraria. Un destino fuera de la lista se rechaza con 400; se compara esquema, host y puerto exactos (la lista guarda **orígenes completos**, p. ej. `http://schedule:8000`), sin seguir redirecciones. En el ejercicio la lista del scraper tiene solo `schedule`, y la de `schedule` solo `core`; cualquier backend nuevo se registra añadiéndolo a la lista, sin tocar código.
- El scraper sigue validando cada URL contra SSRF (SCR-18).

## Manejo de fallos

- **El envío falla** (500, 404 o *timeout*) → `schedule` reintenta con **backoff exponencial** hasta *n* veces. Si el scraper no está disponible, el trabajo queda **bloqueado**: las URLs pendientes siguen en cola y se retoman cuando vuelve (EV-26, EV-27).
- **El scraper recibió la URL pero no llega el callback dentro del plazo** → se trata como `error` de esa URL (EV-17). El plazo es **por URL**, no por corrida.
- **Todo fallo agotado deja la ejecución `failed`** y entra en el barrido diario de errores; no se envía un correo en el momento.
- **Contrapartida aceptada:** el administrador se entera como máximo al día siguiente. La detección inmediata de una caída la cubren las rutas de salud (`health`, EJ-4) y los healthchecks de la infraestructura.
- **Un resultado repetido no duplica datos:** cada resultado se identifica por `transaction_id` (uno por URL) e intento; `schedule` procesa a lo más uno por intento y el snapshot es idempotente (R7).
- **Un `transaction_id` por URL.** La corrida se agrupa con un identificador de correlación que aparece en los logs. El aviso de precio usa el `transaction_id` del **análisis, uno por alerta analizada**, porque la llave de idempotencia de `notify` es `(transaction_id, app_user_id, channel)` y compartirlo entre alertas suprimiría avisos.

## Parámetros (variables de entorno)

Ningún valor va fijo en el código (INF-3): todos son variables de entorno con un **valor por defecto**. Los valores son estimaciones **sin medir** y se ajustan con los fixtures de las 4 estrategias. Los nombres son una propuesta y se confirman al crear el código de cada pieza.

**`schedule`**

| Variable | Defecto | Qué controla |
|----------|---------|--------------|
| `SCHEDULE_DELIVERY_MAX_RETRIES` | `3` | Reintentos del **envío** de una URL (500, 404, *timeout* o 503) |
| `SCHEDULE_DELIVERY_BACKOFF_BASE_SECONDS` | `60` | Espera base del backoff exponencial (1, 2 y 4 min) |
| `SCHEDULE_DELIVERY_BACKOFF_CAP_SECONDS` | `300` | Tope de la espera del backoff |
| `SCHEDULE_ERROR_MAX_RETRIES` | `3` | Reintentos de una URL que devolvió `error` (SCR-8) |
| `SCHEDULE_ERROR_RETRY_MIN_SECONDS` / `_MAX_SECONDS` | `600` / `900` | Rango de la espera entre reintentos de `error`; se elige un valor al azar |
| `SCHEDULE_CALLBACK_DEADLINE_SECONDS` | `120` | Plazo del callback **por URL**; vencido, la URL cuenta como `error` |
| `SCHEDULE_MAX_ACTIVE_RUNS` | `2` | Corridas activas a la vez entre alertas distintas |
| `SCHEDULE_SCRAPE_WINDOWS` | `04:00-06:00,18:00-20:00` | Franjas de captura (SCH-7); con una sola franja, 1 captura al día |
| `SCHEDULE_SWEEP_TIME` | `23:00` | Hora del barrido diario de errores |
| `SCHEDULE_CALLBACK_ALLOWLIST` | solo `core` | Lista blanca de destinos de callback de `schedule` |
| `ADMIN_ALERT_EMAIL` | sin defecto, obligatoria | Dirección del administrador para el barrido |

**`scraper`**

| Variable | Defecto | Qué controla |
|----------|---------|--------------|
| `SCRAPER_URL_TIMEOUT_SECONDS` | `90` | Tope de tiempo por URL (toda la cascada); superado, `error · timeout` |
| `SCRAPER_HTTP_TIMEOUT_SECONDS` | `10` | Tope de cada estrategia HTTP (1 y 2) |
| `SCRAPER_BROWSER_TIMEOUT_SECONDS` | `30` | Tope de la estrategia con navegador (3) |
| `SCRAPER_XHR_TIMEOUT_SECONDS` | `20` | Tope de la estrategia que intercepta el XHR (4) |
| `SCRAPER_MAX_CONCURRENCY` | `2` | URLs en proceso a la vez; la siguiente recibe 503 |
| `SCRAPER_MAX_RESPONSE_BYTES` | `5000000` | Bytes leídos por página; el resto se descarta |
| `SCRAPER_CALLBACK_ALLOWLIST` | `http://schedule:8000` | Orígenes permitidos para el callback, separados por comas |
| `SCRAPER_CALLBACK_MAX_RETRIES` | `3` | Reintentos del callback ante red, *timeout* o 5xx (`0` los desactiva) |
| `SCRAPER_CALLBACK_BACKOFF_BASE_SECONDS` | `1` | Base del backoff exponencial: 1, 2 y 4 s |
| `SCRAPER_CALLBACK_TIMEOUT_SECONDS` | `5` | Tope de cada envío del callback |
| `SCRAPER_STRATEGY_ORDER` | `structured_data,microdata_regex,browser,xhr` | Orden de las estrategias genéricas |
| `SCRAPER_LOGIN_PATHS` | `/login,/signin,…,/iniciar-sesion` | Rutas que marcan `login_required` |
| `SCRAPER_HOST` / `SCRAPER_PORT` | `127.0.0.1` / `8001` | Dónde escucha; en docker-compose `0.0.0.0` **sin publicar** el puerto |
| `SCRAPER_ENV` | `development` | Con `production` se ocultan `/scraper/docs` y el log de accesos, y el `callback_url` es obligatorio |
| `SCRAPER_LOG_LEVEL` / `SCRAPER_LOG_FORMAT` | `INFO` / `json` | Nivel y formato de logs (una línea JSON con `scraper_id`) |
| `SCRAPER_USER_AGENT` | `scraper-service/1.0` | User-Agent honesto de las peticiones |

Los nombres y los valores del scraper son los de su README (ya implementados); los de `schedule` siguen siendo propuesta.

**Reglas entre parámetros** (no las puede validar una sola pieza, se documentan):
- `SCHEDULE_CALLBACK_DEADLINE_SECONDS` debe ser mayor que `SCRAPER_URL_TIMEOUT_SECONDS` **más** el peor caso de entrega del callback (3 reintentos de 5 s más 1 + 2 + 4 s de espera, unos 22 s): por defecto 120 frente a 90 + 22 = 112.
- `SCHEDULE_MAX_ACTIVE_RUNS` no debe superar `SCRAPER_MAX_CONCURRENCY`, para que el 503 sea la excepción.
- `SCHEDULE_SWEEP_TIME` debe caer después de la última hora de análisis.

**Cálculo de referencia (por defecto):** con 10 URLs, una pasada dura ~15 min en el peor caso (10 × 90 s). Un `error` vuelve a la cola con su espera sin frenar a las demás; con 3 reintentos, la corrida más lenta termina en ~1 h.

## Decisiones de diseño cerradas el 2026-11-16

- **`job_execution` en el SQL:** `RUN_ID`, `SEQ`, `ITEM` (la unidad de trabajo es de `schedule`: **no viaja al scraper**), `SCRAPER_ID` (el id que el scraper devuelve en el `202`), `ATTEMPT` y `NEXT_ATTEMPT_AT`, con una sola ejecución en curso por disparo. Probado en `postgres:16` el 2026-11-12 (ver [modelo de datos](../../data/data-model.md)); no se midió rendimiento con volumen.
- **El análisis es único para todas las alertas**, con un `alert_id` opcional para que la interfaz pueda pedirlo de una sola.
- **El tope de corridas activas entre alertas** es `SCHEDULE_MAX_ACTIVE_RUNS`, más el escalonado que fija `core` (DEC-20).
- **El barrido** reúne lo que falló **desde su última ejecución** (marcador en `job.last_run_at`), no «las últimas 24 h».
- **Aviso al administrador:** plantilla `admin-alert-email` en `notify`, agrupada por alerta, solo con identificadores y códigos de error (nunca contenido del sitio sin sanear); `app_user_id` es el usuario fijo por entorno de las demás piezas; un día sin errores no envía correo (EV-29).

- **`core` guarda todo lo que devuelve el scraper (D38, 2026-11-17):** precio de lista y vigencia en el snapshot; precio de lista, vigencia, marca, SKU, GTIN, MPN e imágenes como último valor en `alert_url.last_*`.

## Pendientes

- Confirmar los nombres de las variables al crear el código de cada pieza.
- Medir los tiempos reales por estrategia con los fixtures y ajustar los valores.
- `robots.txt`: el README lo declara como principio del scraper («no fuerza un `robots.txt` que lo prohíba») pero no define código de motivo ni verificación; confirmar con el equipo del scraper.
- Estrategias `custom:<nombre>` por dominio: el mecanismo existe, sin ninguna concreta (alcance en pausa).
- Imagen Docker del scraper y su servicio en docker-compose (pendiente en su README).
- Escribir la plantilla `admin-alert-email` y sembrarla con la migración de `notify` (EJ-3).

## Alternativas descartadas

| Alternativa | Por qué no |
|-------------|------------|
| Mantener el *pull* | No se sabe si el scraper está vivo y no hay un punto natural de reintento |
| Cola con Redis + Arq | Cuesta un componente más y reabre B2. Queda como evolución futura detrás de `ScraperDispatcher` |
| Kafka o RabbitMQ | Excesivo para este volumen y costoso de operar |
| Cola en la base de `schedule` | El scraper no tiene acceso a bases de datos; dárselo rompe el aislamiento por esquema y rol |

## Consecuencias

- **Positivas:** una caída del scraper se nota en el propio envío (un 500, un 404 o un *timeout*); cada URL se resuelve y se entrega sola, sin acumular ni esperar a las demás; el plazo del callback es por URL y fácil de vigilar; el scraper sigue sin estado y es reutilizable desde otros sistemas; separar scraping y análisis evita avisos duplicados; sin infraestructura nueva.
- **Negativas / costo:** la corrida es más lenta porque el tiempo es la suma de sus URLs (con 10 URLs y 60 s cada una, unos 10 min por pasada; estimación sin medir); el scraper expone un endpoint interno; `schedule` guarda estado por URL e intento; el mejor precio que ve el dashboard puede estar atrasado hasta el siguiente análisis; el administrador se entera de los errores como máximo al día siguiente.
- **Riesgos y cómo se mitigan:** exposición del endpoint (red interna, firewall y lista blanca de destinos de callback); varias alertas a la misma hora compitiendo por el scraper (escalonado y 503 con reintento); el trabajo en vuelo se pierde si el scraper se reinicia (el plazo por URL lo convierte en `error` y se reintenta).
