# 09 · Pendientes de arquitectura e infraestructura

> Backlog de **decisiones abiertas o por validar** que salieron de las conversaciones de arquitectura (modelo de datos, repos, despliegue). No son preguntas de alcance de producto (eso vive en [doc 08](08-alcance-1-preguntas.md)): son puntos técnicos que **ya tienen una dirección aprobada** pero les falta el detalle final, una prueba de concepto (PoC) o una elección concreta de proveedor.
>
> **Regla de uso:** nada de aquí se decide por iniciativa propia (sección 2 de `CLAUDE.md`). Se retoma un punto cuando el usuario lo priorice; al cerrarlo, se actualiza el doc correspondiente (02/03/04/deliverables) y se marca `✅` aquí.

Estado: `⬜ abierto` · `🔄 con dirección aprobada, falta cerrar el detalle` · `✅ cerrado`

**Prioridad** (misma escala que [`requerimientos.md`](deliverables/requerimientos.md), para no tener dos vocabularios distintos): `🔴 P0` bloquea trabajo activo o un requerimiento P0 ya aprobado · `🟡 P1` importante, no bloquea hoy · `🟢 P2` deseable, sin urgencia · `⚠️` marca adicional para riesgos que no dependen de nosotros (p. ej. que un proveedor cambie sus términos) y que conviene vigilar aunque no sean accionables todavía.

## Tabla de contenido

- [A · ADR](#a--adr)
- [B · Persistencia](#b--persistencia)
- [C · Infraestructura y despliegue](#c--infraestructura-y-despliegue)
- [D · Auth multi-sistema y contratos](#d--auth-multi-sistema-y-contratos)
- [Pendientes homologados (mismo problema, distintos sitios)](#pendientes-homologados-mismo-problema-distintos-sitios)
- [Ya decidido (para no reabrir sin motivo)](#ya-decidido-para-no-reabrir-sin-motivo)

## A · ADR

| # | Pendiente | Dirección aprobada | Estado | Prioridad |
|---|-----------|---------------------|--------|-----------|
| A1 | **ADR-0001 · Estructura de repos y servicios** | `frontend`, `core` (incluye scheduling), `auth`, `notify`, `scraper`; disparadores para separar más (`ai-service`, otro `core` con 3er consumidor) | ✅ Redactado: [docs/adr/0001-estructura-repos-servicios.md](adr/0001-estructura-repos-servicios.md) | — |
| A3 | ~~¿`schedule` es esquema propio dentro de `core`, o repo/servicio propio?~~ | **Resuelto (2026-09-29): repo propio.** [ADR-0001](adr/0001-estructura-repos-servicios.md), [doc 02](02-arquitectura.md) y [doc 04](04-stack-tecnologico.md) ya sincronizados con este sexto repo | ✅ | — |
| A2 | **ADR-0002 · Despliegue y propiedad de datos** (Cloudflare/GCP/Oracle, proveedor de BD, contratos entre servicios) | Deliberadamente **pendiente**: la dirección de trabajo está en el [doc 02](02-arquitectura.md#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle), pero no se redacta el ADR hasta cerrar B1, C1, C3 y C4 | ⬜ | 🟡 P1 — bloqueado por B1/C1/C3/C4, no accionable todavía |

## B · Persistencia

| # | Pendiente | Notas | Prioridad |
|---|-----------|-------|-----------|
| B1 | **Proveedor gratuito concreto de PostgreSQL/MongoDB por servicio** (`auth`, `core`, `notify`) | Catálogo evaluado: Neon, Supabase, Aiven, Atlas M0. Ninguno elegido aún; cada uno tiene límites distintos (0,5–1 GB, pausas por inactividad) | 🔴 P0 — sin esto no hay dónde desplegar nada |
| B2 | **¿Sigue haciendo falta Redis + Arq?** | Con el scraper haciendo *pull* HTTPS sobre `core`, es posible que la cola ya no necesite Redis: `core` podría exponer el trabajo pendiente directo desde `schedule`/`job` en PostgreSQL. Afecta al [doc 04](04-stack-tecnologico.md) (`Cola/workers`, `Scheduler`) si se confirma | 🟢 P2 |
| B3 | **Medir con datos reales** | Tamaño real de fila de `price_snapshot`, tasa real de cambio de precio/stock (supuesto actual: 10–30 %), tamaño de `job_execution_result` sin comprimir vs. con `zstd`. **Si la medición lo exige:** evaluar compresión de series temporales (extensión tipo TimescaleDB; verificar licencia) o *rollup* diario para `price_snapshot` | 🟢 P2 — necesita tráfico real, no se puede hacer antes de desplegar |
| B4 | **Backups** (`pg_dump` / `mongodump` hacia almacenamiento externo) | Aún no es un requerimiento formal en `requerimientos.md`; falta darle un ID (candidato: `INF-16`) y definir destino (ninguno de los free tiers de BD incluye backups) | 🟡 P1 |
| B5 | **Umbral exacto de `is_anomalous`** | Lo define el motor de decisión (PRO-5/PRO-6); no está cuantificado todavía (¿% de caída? ¿respecto a qué ventana?) | 🟡 P1 — un valor default razonable desbloquea el resto mientras se afina |

## C · Infraestructura y despliegue

| # | Pendiente | Notas | Prioridad |
|---|-----------|-------|-----------|
| C1 | **Crear y validar la VM Ampere en Oracle** | Confirmar que la cuenta puede provisionarla (a veces no hay capacidad); es el único componente que va en Oracle | 🔴 P0 |
| C2 | **Imágenes multi-arquitectura** | El scraper corre en `arm64` (Ampere); un plan B en x86 exige build multi-arch en CI. Validar Playwright/Chromium y dependencias Python en `arm64` | 🔴 P0 — mismo bloque que C1, nada corre en Oracle sin esto |
| C3 | **Medir RAM real del scraper** en la Ampere (2 OCPU / 12 GB, ver C7) | Con Chromium activo; define cuánto margen queda y si el resto del stack (incluido el sandbox de D14) podría convivir ahí sin problema | 🔴 P0 — subió de prioridad: la VM ya tiene la mitad de la capacidad que se asumía antes de C7 |
| C4 | **Restringir el *ingress* de Cloud Run** para que solo Cloudflare pueda llamar a `auth`/`core`/`schedule`/`notify` | Mecanismo concreto por decidir: token de servicio compartido, Cloud Armor, o restricción de *ingress* nativa de Cloud Run. Crítico para `schedule` (SCH-11): no debe ser alcanzable salvo por el Gateway | 🔴 P0 — SCH-11 es un requerimiento P0 ya aprobado |
| C5 | **Medir el arranque en frío de `auth`** en Cloud Run | Decidir si vale el costo de `--min-instances=1` (deja de ser 100 % gratis) o si el impacto en UX es aceptable | 🟢 P2 |
| C6 | **Actualizar INF-15** (`requerimientos.md`) | Su nota todavía describe la topología antigua (una VM con todo); reescribir cuando se cierren C1–C5 | 🟢 P2 — bloqueado por los anteriores, es solo redacción |
| C7 | ⚠️ **Sostenibilidad del *Always Free* de Oracle — no tiene fecha de vencimiento, pero sí precedente de cambio** | Verificado 2026-10-01: *Always Free* no expira como el *Free Trial* (300 USD/30 días), pero Oracle **ya redujo** las specs de Ampere A1 una vez (4 OCPU/24 GB → 2 OCPU/12 GB, efectivo 15-jun-2026, instancias excedentes terminadas desde 18-ago-2026). Riesgo adicional de "úsalo o piérdelo": instancia inactiva (<10 % CPU y red, 7 días) puede detenerse; cuenta sin uso de *Always Free* en 60 días arriesga la elegibilidad. **No es accionable hoy** (no depende de nosotros), pero condiciona cuánto podemos apilar sobre esa VM (ver C3, D14) y debería pesar en ADR-0002 (A2) | 🟡 P1 ⚠️ — importante como riesgo a vigilar, no bloquea trabajo activo |

## D · Auth multi-sistema y contratos

| # | Pendiente | Notas | Prioridad |
|---|-----------|-------|-----------|
| D1 | **Diseño detallado de `system`/`app` en `auth`** | Tabla `system` (código, nombre, estado); tokens de servicio con claim `aud=system` para las llamadas `core`→`notify` y `auth`→`notify` | 🔴 P0 — `schedule` y `notify` ya dependen de `system` en su esquema físico; sin esto no hay JWT de servicio válido |
| D2 | **Autenticación del scraper hacia la API de *pull* de `schedule`** | Token de servicio propio, con rotación; el scraper no tiene BD ni credenciales de usuario | 🔴 P0 |
| D3 | **Auth: casero vs. proveedor existente** | Se aprobó construirlo delgado sobre estándares por ahora; evaluar un proveedor (p. ej. uno con soporte OIDC) queda abierto para cuando el sistema multi-proyecto lo exija | 🟢 P2 — deferred a propósito |
| D4 | **Contratos versionados entre servicios** | Cliente TypeScript generado desde el OpenAPI de `auth`/`core` (`openapi-typescript`) + `oasdiff` en CI; esquema formal del `payload`/resultado de un `job` (aún no escrito) | 🟡 P1 |
| D5 | **Repo plantilla para servicios Python** | CI, lint, reglas de IA comunes a `core`/`auth`/`notify`, para que no se desalineen entre repos | 🟢 P2 |
| D6 | **Contrato `core` → `notify` para el envío** | Cómo llama `core` a `notify` (síncrono vía Gateway + reintentos, o cola propia) y qué datos de la decisión le pasa (`system`, `alert_id`, `run_id`, `app_user_id`, precio disparador). Desde que `notification` vive en `notify` (2026-09-30), es `notify` quien genera su propio `notification.id` — ya no es `core` quien se lo pasa — ver [doc 03](03-modelo-datos.md#d-notify-notificaciones). **Mismo patrón que D7/D12** (ver homologación abajo) | 🔴 P0 — sin este contrato, `notify` no tiene cómo recibir nada |
| D7 | **Consistencia `core` ↔ `schedule` para ALE-8** | Ya existe la API a llamar (`JOBAPI`, SCH-12), pero crear una alerta (`core`) y darla de alta en `schedule` (ALE-8) siguen siendo dos escrituras, no una transacción. Falta elegir cómo cubrir el fallo de la segunda: reintento sobre la misma llamada síncrona, patrón outbox/saga, o que `schedule` la cree perezosamente en su primer *pull*. Mientras no se cierre, existe una ventana donde una alerta puede quedar sin schedule. **Mismo patrón que D6/D12** | 🟡 P1 |
| D8 | ~~Consulta `core` → `schedule` para el panel de salud (SCR-17)~~ | **Resuelto en dirección (2026-09-30):** `core` consulta a `schedule` **por API** (no lee su Mongo). **Corrección (2026-10-01):** el detalle que faltaba ("qué endpoint, qué forma de respuesta") **no** quedó cubierto por D10 pese a lo que decía esta nota antes — D10 resolvió otra cosa (la inversión scraper↔schedule). Ese detalle sigue abierto, sin dueño claro | 🟢 P2 — detalle de implementación, la dirección ya está resuelta |
| D9 | ~~Reconciliar el esquema físico de `schedule` con la API genérica de jobs~~ | **Resuelto (2026-10-01):** `schedule`/`run` (atados a `alert_id`) se reemplazaron por `execution_type`/`job`/`job_script`/`job_execution`/`job_callback_sent`/`job_callback_outbox` — motor de jobs genérico, sin ningún concepto de `core`; `system` + `execution_type` (catálogo abierto) + `payload` (opaco) como única entrada, `schedule_cron` en vez de `runs_per_day`/`windows`. Soporta además ejecución serverless (`execution_type='script'`, Python/JavaScript) — ver [doc 03](03-modelo-datos.md#c-schedule-motor-de-jobs-genérico) y [schedule/schema.sql](deliverables/db/schedule/schema.sql) | ✅ |
| D10 | ~~Aplicar a diagramas/BD la inversión scraper↔schedule~~ | **Resuelto (2026-09-30):** los 3 diagramas del [doc 02](02-arquitectura.md), la sección de colecciones del [doc 03](03-modelo-datos.md) y los scripts (`schedule/mongo-setup.js` nuevo, `core/mongo-setup.js` recortado a `exchange_rate`) ya reflejan el scraper entregando a `schedule` (SCR-20) y el callback configurable hacia `core` (SCH-14) | ✅ |
| D11 | **Mecanismo `core` → `frontend` para el progreso en tiempo real (SCH-9)** | La consulta `core`→`schedule` (etapa actual del *run*) ya está decidida — es la misma API de jobs (SCH-12). Falta solo el último tramo: cómo se lo entrega `core` al navegador. Propuesta sin aprobar: SSE sobre HTTPS (sin agregar proveedor nuevo). **Recordar:** no hay ETA posible, solo la etapa actual. **Bloqueado por D15:** la fuente de esa etapa (`job_state`) se quedó sin hogar al genericizar `schedule` — no se puede cerrar D11 sin resolver D15 primero | 🟡 P1 — bloqueado por D15 |
| D12 | **Entrega confiable `core` → `notify` tras mover el outbox (2026-09-30)** | Al pasar `notification` de `core` a `notify` ([ADR-0001](adr/0001-estructura-repos-servicios.md), [doc 03](03-modelo-datos.md#d-notify-notificaciones)), el motor de decisión de `core` ya no puede insertar el outbox en la misma transacción donde actualiza `best_price_*`: son dos escrituras en dos servicios. Falta elegir el mecanismo (llamada síncrona con reintento, outbox propio de `core` hacia esa llamada, o patrón saga) que evite una decisión sin aviso si la llamada a `notify` falla. **Mismo patrón que D6/D7** | 🟡 P1 — depende de que D6 cierre primero (el contrato) |
| D13 | ~~Reconciliar `core.subscription`/SUB-1 con `notification` exigiendo `app_user_id`~~ | **Resuelto (2026-09-30):** `core.subscription.created_by` pasa a ser **obligatorio** — toda suscripción exige cuenta, igual que el resto del sistema ([core/schema.sql](deliverables/db/core/schema.sql), [doc 03](03-modelo-datos.md#d-notify-notificaciones)). `app_user_id` en `NOTIFICATION` es ese mismo valor. El cabo suelto que dejó (correo distinto al de la cuenta sin mecanismo de entrega) se separó a **D16** | ✅ |
| D14 | **Sandbox de ejecución para jobs serverless (`execution_type='script'`)** | `job_script` (2026-10-01) guarda código Python/JavaScript enviado por el cliente, pero **quién lo ejecuta y con qué aislamiento no está decidido**: ejecutar código arbitrario sin sandbox real es una puerta abierta a RCE. **Dirección en evaluación (2026-10-01):** entre Oracle (VM del scraper) + Docker + gVisor, operado por nosotros, vs. GCP Cloud Run Jobs (gVisor gestionado por Google) — condicionado a que C3 confirme que hay margen de RAM para sumarlo a la misma VM que el scraper. No decidido todavía | 🟡 P1 — no bloquea el flujo scrape+notificación de Fase 1; sí bloquea habilitar `execution_type='script'` |
| D16 | **Catálogo de proveedores por canal en `notify`** | Hoy `provider` es texto libre en `notification_sent`/`notification_outbox` (sin FK) — se dejó así a propósito (2026-10-0X): una tabla `PROVIDER` normalizada (con sus credenciales **fuera** de la base, por variable de entorno) solo gana su lugar el día que haya **2+ proveedores reales** para el mismo canal (failover/A-B). Mientras tanto, un solo proveedor por canal basta |
| D17 | **Tope de costo/reintentos para canales de pago (SMS/WhatsApp/llamada)** | A diferencia del email (SMTP propio, costo ~0), estos canales suelen cobrar por mensaje. Si `notification_outbox` reintenta sin límite de costo ante un proveedor caído, puede generar una factura inesperada. Falta decidir el tope (máx. reintentos, o aprobación explícita para activar un canal de pago en producción) antes de implementar el primer sender pago (Fase 2+) |
| D18 | **Redundancia `notification_log` (Mongo de `notify`) tras mover `payload` a PostgreSQL (2026-10-0X)** | Antes era la única fuente para re-renderizar un aviso; ahora `notification.payload` + `notification.template_id` ya tienen ese dato, de forma atómica con la fila. Falta decidir si `notification_log` se recorta a solo archivo/auditoría de lo enviado, o se elimina — ver [doc 03](03-modelo-datos.md#d-notify-notificaciones) |
| D15 | **Nuevo hogar para el detalle de scraping tras genericizar `schedule`** | Al rediseñar `schedule` como motor de jobs genérico (2026-10-01, D9), `job_state`/`raw_capture`/`scrape_result` (progreso por sitio, HTML crudo para adapters, precio extraído — todo con `alert_url_id`) **dejaron de tener dónde vivir**. Candidato natural: la Mongo de `core`, que es quien conoce "sitios" y "adapters". **Esto es una regresión introducida por D9, no una mejora opcional:** SCR-12, SCR-15 y SCR-16 son requerimientos 🔴 P0 ya aprobados que dependían de ese detalle — D9 no se puede dar por completamente cerrado hasta que esto tenga un hogar | 🔴 P0 — restaura capacidad que sostenía requerimientos P0 ya aprobados |
| D16 | **`subscription.email` distinto al de la cuenta, sin mecanismo de entrega** *(separado de D13, 2026-10-01)* | SUB-1 permite suscribir un correo que no es el de la cuenta, pero `notify.notification` solo recibe `app_user_id` — no hay forma de avisarle a ese correo. Decidir: volver a llevar un email hasta `notify`, o limitar `subscription.email` al de la propia cuenta y ajustar SUB-1 | 🟢 P2 — función de borde, no bloquea el flujo principal de notificación |

## Pendientes homologados (mismo problema, distintos sitios)

> Para no resolver tres veces el mismo problema de maneras distintas. No se fusionan los IDs (cada uno es un punto de integración real y distinto) pero conviene decidirlos **juntos**, con un solo patrón.

- **"Dos escrituras entre servicios, sin transacción, necesitan reintento" — D6, D7, D12.** Las tres son la misma forma de problema (A escribe en su base, necesita que B se entere, y si la llamada a B falla hoy no hay red de seguridad) en tres puntos distintos: `core`→`schedule` (ALE-8, D7), `core`→`notify` contrato (D6) y `core`→`notify` confiabilidad (D12). Conviene definir **un solo patrón** (p. ej. outbox transaccional del lado de `core` para cualquier llamada saliente post-commit) y aplicarlo a los tres, no inventar un mecanismo por caso.
- **D11 ↔ D15.** D11 (progreso en tiempo real) consume `job_state`, que D15 dejó sin hogar. No se puede cerrar D11 sin decidir D15 primero.
- **D8, corrección de referencia cruzada.** D8 apuntaba a D10 como el lugar donde se cerraría su detalle pendiente; D10 se resolvió, pero resolvió otra cosa. El detalle de D8 sigue abierto — se corrige aquí para no perderlo de vista.

## Ya decidido (para no reabrir sin motivo)

> Registrado aquí solo como referencia rápida; el detalle y el "por qué" están en los docs citados.

- Repos: `frontend`, `auth`, `core`, `schedule`, `notify`, `scraper` (6 repos) — [ADR-0001](adr/0001-estructura-repos-servicios.md).
- Gateway único: **Worker de Cloudflare**; JWT validado en cada servicio, no en el gateway — [doc 02](02-arquitectura.md#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle).
- Frontend: **Cloudflare Workers Static Assets** (plan B: Netlify).
- Despliegue: `auth`/`core`/`schedule`/`notify` en **GCP Cloud Run**; **solo** el scraper en la **VM Ampere de Oracle** (por ser el más pesado en recursos) — sujeto al riesgo de sostenibilidad de C7.
- Base de datos: **una sola instancia PostgreSQL, 4 esquemas** (`auth`/`core`/`schedule`/`notify`), un rol por esquema sin acceso al de los demás — [docs/deliverables/db](deliverables/db/README.md).
- Scraper sin estado, sin BD, y accede por *pull* (sin puertos entrantes en Oracle).
- Modelo de datos, retención y semántica de "mejor precio" — [doc 03](03-modelo-datos.md).
- Requerimientos de seguridad SCR-18 (anti-SSRF) y SCR-19 (visualización segura de contenido no confiable) — [requerimientos.md](deliverables/requerimientos.md).
