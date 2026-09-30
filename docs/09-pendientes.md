# 09 · Pendientes de arquitectura e infraestructura

> Backlog de **decisiones abiertas o por validar** que salieron de las conversaciones de arquitectura (modelo de datos, repos, despliegue). No son preguntas de alcance de producto (eso vive en [doc 08](08-alcance-1-preguntas.md)): son puntos técnicos que **ya tienen una dirección aprobada** pero les falta el detalle final, una prueba de concepto (PoC) o una elección concreta de proveedor.
>
> **Regla de uso:** nada de aquí se decide por iniciativa propia (sección 2 de `CLAUDE.md`). Se retoma un punto cuando el usuario lo priorice; al cerrarlo, se actualiza el doc correspondiente (02/03/04/deliverables) y se marca `✅` aquí.

Estado: `⬜ abierto` · `🔄 con dirección aprobada, falta cerrar el detalle` · `✅ cerrado`

## A · ADR

| # | Pendiente | Dirección aprobada | Estado |
|---|-----------|---------------------|--------|
| A1 | **ADR-0001 · Estructura de repos y servicios** | `frontend`, `core` (incluye scheduling), `auth`, `notify`, `scraper`; disparadores para separar más (`ai-service`, otro `core` con 3er consumidor) | ✅ Redactado: [docs/adr/0001-estructura-repos-servicios.md](adr/0001-estructura-repos-servicios.md) |
| A3 | ~~¿`schedule` es esquema propio dentro de `core`, o repo/servicio propio?~~ | **Resuelto (2026-09-29): repo propio.** [ADR-0001](adr/0001-estructura-repos-servicios.md), [doc 02](02-arquitectura.md) y [doc 04](04-stack-tecnologico.md) ya sincronizados con este sexto repo | ✅ |
| A2 | **ADR-0002 · Despliegue y propiedad de datos** (Cloudflare/GCP/Oracle, proveedor de BD, contratos entre servicios) | Deliberadamente **pendiente**: la dirección de trabajo está en el [doc 02](02-arquitectura.md#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle), pero no se redacta el ADR hasta cerrar los bloques B y C de este doc (proveedor de BD, PoC de Oracle, *ingress* de Cloud Run) | ⬜ |

## B · Persistencia

| # | Pendiente | Notas |
|---|-----------|-------|
| B1 | **Proveedor gratuito concreto de PostgreSQL/MongoDB por servicio** (`auth`, `core`, `notify`) | Catálogo evaluado: Neon, Supabase, Aiven, Atlas M0. Ninguno elegido aún; cada uno tiene límites distintos (0,5–1 GB, pausas por inactividad) |
| B2 | **¿Sigue haciendo falta Redis + Arq?** | Con el scraper haciendo *pull* HTTPS sobre `core`, es posible que la cola ya no necesite Redis: `core` podría exponer el trabajo pendiente directo desde `schedule`/`run` en PostgreSQL. Afecta al [doc 04](04-stack-tecnologico.md) (`Cola/workers`, `Scheduler`) si se confirma |
| B3 | **Medir con datos reales** | Tamaño real de fila de `price_snapshot`, tasa real de cambio de precio/stock (supuesto actual: 10–30 %), tamaño de `job_state`/`run_summary` sin comprimir vs. con `zstd`. **Si la medición lo exige:** evaluar compresión de series temporales (extensión tipo TimescaleDB; verificar licencia) o *rollup* diario para `price_snapshot` |
| B4 | **Backups** (`pg_dump` / `mongodump` hacia almacenamiento externo) | Aún no es un requerimiento formal en `requerimientos.md`; falta darle un ID (candidato: `INF-16`) y definir destino (ninguno de los free tiers de BD incluye backups) |
| B5 | **Umbral exacto de `is_anomalous`** | Lo define el motor de decisión (PRO-5/PRO-6); no está cuantificado todavía (¿% de caída? ¿respecto a qué ventana?) |

## C · Infraestructura y despliegue

| # | Pendiente | Notas |
|---|-----------|-------|
| C1 | **Crear y validar la VM Ampere en Oracle** | Confirmar que la cuenta puede provisionarla (a veces no hay capacidad); es el único componente que va en Oracle |
| C2 | **Imágenes multi-arquitectura** | El scraper corre en `arm64` (Ampere); un plan B en x86 exige build multi-arch en CI. Validar Playwright/Chromium y dependencias Python en `arm64` |
| C3 | **Medir RAM real del scraper** en la Ampere (12 GB disponibles) | Con Chromium activo; define cuánto margen queda y si el resto del stack podría convivir ahí sin problema |
| C4 | **Restringir el *ingress* de Cloud Run** para que solo Cloudflare pueda llamar a `auth`/`core`/`schedule`/`notify` | Mecanismo concreto por decidir: token de servicio compartido, Cloud Armor, o restricción de *ingress* nativa de Cloud Run. Crítico para `schedule` (SCH-11): no debe ser alcanzable salvo por el Gateway |
| C5 | **Medir el arranque en frío de `auth`** en Cloud Run | Decidir si vale el costo de `--min-instances=1` (deja de ser 100 % gratis) o si el impacto en UX es aceptable |
| C6 | **Actualizar INF-15** (`requerimientos.md`) | Su nota todavía describe la topología antigua (una VM con todo); reescribir cuando se cierren C1–C5 |

## D · Auth multi-sistema y contratos

| # | Pendiente | Notas |
|---|-----------|-------|
| D1 | **Diseño detallado de `system`/`app` en `auth`** | Tabla `system` (código, nombre, estado); tokens de servicio con claim `aud=system` para las llamadas `core`→`notify` y `auth`→`notify` |
| D2 | **Autenticación del scraper hacia `/api/internal/jobs`** | Token de servicio propio, con rotación; el scraper no tiene BD ni credenciales de usuario |
| D3 | **Auth: casero vs. proveedor existente** | Se aprobó construirlo delgado sobre estándares por ahora; evaluar un proveedor (p. ej. uno con soporte OIDC) queda abierto para cuando el sistema multi-proyecto lo exija |
| D4 | **Contratos versionados entre servicios** | Cliente TypeScript generado desde el OpenAPI de `auth`/`core` (`openapi-typescript`) + `oasdiff` en CI; esquema formal del mensaje `job`/`resultado` del scraper (aún no escrito) |
| D5 | **Repo plantilla para servicios Python** | CI, lint, reglas de IA comunes a `core`/`auth`/`notify`, para que no se desalineen entre repos |
| D6 | **Contrato `core` → `notify` para el envío** | Cómo llama `core` a `notify` (síncrono vía Gateway + reintentos, o cola propia), y cómo `notify` escribe `notification_log` con el mismo `notification.id` que le pasa `core` — ver [doc 03](03-modelo-datos.md#puentes-relacional--nosql) |
| D7 | **Consistencia `core` ↔ `schedule` para ALE-8** | Ya existe la API a llamar (`JOBAPI`, SCH-12), pero crear una alerta (`core`) y darla de alta en `schedule` (ALE-8) siguen siendo dos escrituras, no una transacción. Falta elegir cómo cubrir el fallo de la segunda: reintento sobre la misma llamada síncrona, patrón outbox/saga, o que `schedule` la cree perezosamente en su primer *pull*. Mientras no se cierre, existe una ventana donde una alerta puede quedar sin schedule |
| D8 | ~~Consulta `core` → `schedule` para el panel de salud (SCR-17)~~ | **Resuelto en dirección (2026-09-30):** `core` consulta a `schedule` **por API** (no lee su Mongo). Falta el contrato exacto de esa consulta (qué endpoint, qué forma de respuesta) — parte del trabajo de D10 |
| D9 | **Reconciliar el esquema físico de `schedule` con la API genérica de jobs** | El [doc 02](02-arquitectura.md#diagrama-de-componentes-c4--nivel-3) ya describe `schedule` como un motor genérico (CRUD de `jobs`, acción `api_call`/`python_script`/`topic_message`, SCH-12/13), pero las tablas reales ([docs/deliverables/db/schedule/schema.sql](deliverables/db/schedule/schema.sql) y [doc 03](03-modelo-datos.md#c2-scheduling-servicio-schedule)) todavía tienen la forma antigua "un schedule por alerta". Falta diseñar la tabla `job` genérica (trigger + acción configurables) que reemplace/generalice `schedule`/`run` |
| D10 | ~~Aplicar a diagramas/BD la inversión scraper↔schedule~~ | **Resuelto (2026-09-30):** los 3 diagramas del [doc 02](02-arquitectura.md), la sección de colecciones del [doc 03](03-modelo-datos.md) y los scripts (`schedule/mongo-setup.js` nuevo, `core/mongo-setup.js` recortado a `exchange_rate`) ya reflejan el scraper entregando a `schedule` (SCR-20) y el callback configurable hacia `core` (SCH-14) |
| D11 | **Mecanismo `core` → `frontend` para el progreso en tiempo real (SCH-9)** | La consulta `core`→`schedule` (etapa actual del *run*) ya está decidida — es la misma API de jobs (SCH-12). Falta solo el último tramo: cómo se lo entrega `core` al navegador. Propuesta sin aprobar: SSE sobre HTTPS (sin agregar proveedor nuevo). **Recordar:** no hay ETA posible, solo la etapa actual (`job_state`, SCR-16) |

## Ya decidido (para no reabrir sin motivo)

> Registrado aquí solo como referencia rápida; el detalle y el "por qué" están en los docs citados.

- Repos: `frontend`, `auth`, `core`, `schedule`, `notify`, `scraper` (6 repos) — [ADR-0001](adr/0001-estructura-repos-servicios.md).
- Gateway único: **Worker de Cloudflare**; JWT validado en cada servicio, no en el gateway — [doc 02](02-arquitectura.md#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle).
- Frontend: **Cloudflare Workers Static Assets** (plan B: Netlify).
- Despliegue: `auth`/`core`/`schedule`/`notify` en **GCP Cloud Run**; **solo** el scraper en la **VM Ampere de Oracle** (por ser el más pesado en recursos).
- Base de datos: **una sola instancia PostgreSQL, 4 esquemas** (`auth`/`core`/`schedule`/`notify`), un rol por esquema sin acceso al de los demás — [docs/deliverables/db](deliverables/db/README.md).
- Scraper sin estado, sin BD, y accede por *pull* (sin puertos entrantes en Oracle).
- Modelo de datos, retención y semántica de "mejor precio" — [doc 03](03-modelo-datos.md).
- Requerimientos de seguridad SCR-18 (anti-SSRF) y SCR-19 (visualización segura de contenido no confiable) — [requerimientos.md](deliverables/requerimientos.md).
