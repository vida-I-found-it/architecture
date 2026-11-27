# Arquitectura

> **Alcance: el proyecto completo.** Contiene toda la arquitectura (incluye `auth`, administración y despliegue). La arquitectura reducida a los casos de uso del ejercicio está en [`architecture.md`](architecture.md). Es normal que ambos repitan secciones; en unas semanas se unificarán en una sola arquitectura.

> Consolidado con el [Alcance 1](../00-context/scope-1-questions.md), los [requerimientos](../requirements/original-requirements.md), el [modelo de datos](../data/data-model.md) y el [flujo diario](scraping-flow.md). Refleja roles/RBAC, ejecución background asíncrona, la **cascada de scraping con adapters aprendidos**, la máquina de estados del job, persistencia políglota, observabilidad y despliegue polyrepo portable a la nube.

## Tabla de contenido

- [Principios de diseño](#principios-de-diseño)
- [Diagrama de contexto (C4 · nivel 1)](#diagrama-de-contexto-c4--nivel-1)
- [Diagrama de contenedores (C4 · nivel 2)](#diagrama-de-contenedores-c4--nivel-2)
- [Diagrama de componentes (C4 · nivel 3)](#diagrama-de-componentes-c4--nivel-3)
- [Responsabilidad de cada componente](#responsabilidad-de-cada-componente)
  - [Persistencia por servicio](#persistencia-por-servicio)
- [Módulos desacoplados (puntos de extensión)](#módulos-desacoplados-puntos-de-extensión)
- [Persistencia políglota](#persistencia-políglota)
- [Concerns transversales](#concerns-transversales)
- [Vista de despliegue (servicios desacoplados · Cloudflare + GCP + Oracle)](#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle)
  - [Vista mínima](#vista-mínima)
- [Comunicación entre piezas](#comunicación-entre-piezas)
  - [Usuario ↔ Frontend](#usuario--frontend)
  - [Frontend ↔ Backend](#frontend--backend)
  - [Backend ↔ Backend (service-to-service)](#backend--backend-service-to-service)
  - [Backend → Servicios externos](#backend--servicios-externos)
  - [Transversal](#transversal)

## Principios de diseño

- **Modular y desacoplado:** las piezas que cambiarán —proveedor de IA, tasa de cambio, estrategia de "mejor precio", canal de notificación— viven **tras una interfaz**, reemplazables sin tocar el core.
- **Scraping en background, no en el request:** el trabajo pesado corre en el **scraper**; `schedule` se lo envía de forma asíncrona, en corridas que arrancan a las horas de inicio configuradas, y recibe el resultado por un callback ([ADR-0004](adr/0004-schedule-dispatches-work-to-scraper.md)).
- **Scraping que aprende:** lo que se descubre de un sitio se reutiliza en vez de repetir el trabajo. La cascada completa está en el [flujo de scraping](scraping-flow.md).
- **Observable de punta a punta:** cada corrida lleva un `transactionId` que atraviesa los 5 servicios de backend y sus logs; máquina de estados granular por job.
- **6 repos independientes, portables, sin lock-in** ([ADR-0001](adr/0001-repo-and-service-structure.md)): cada uno empaquetado en contenedores + config por entorno (12-factor). Las mismas imágenes corren local (docker-compose) y en producción (Cloudflare/GCP/Oracle).
- **Cloudflare como única puerta de entrada:** ningún servicio expone su origen directamente — todo el tráfico, de usuarios y entre servicios, pasa por el Gateway o la red de Cloudflare (ver [Vista de despliegue](#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle)).
- **Aislamiento de datos por servicio, no por conveniencia:** cada repo es dueño de su propio esquema/base, con sus propios roles de BD y **sin FK ni permisos** sobre el de otro servicio; la integridad entre servicios la garantiza quien escribe, no la base de datos (ver [modelo de datos](../data/data-model.md) y [docs/deliverables/db](../data/scripts/README.md)).
- **Superficie de ataque mínima en el scraper:** sin estado, sin credenciales de negocio y **sin puertos expuestos fuera de la red interna**; solo `schedule` puede enviarle trabajo y el destino de su callback es una lista blanca ([ADR-0004](adr/0004-schedule-dispatches-work-to-scraper.md)).
- **Idempotente y append-only:** las corridas se reintentan sin duplicar ni corromper el historial; el precio se guarda **solo cuando cambia**.
- **Almacenamiento mínimo:** cada dato vive en el almacén que menos cuesta según su ciclo de vida; lo voluminoso o efímero va a NoSQL con **TTL y compresión** (ver [modelo de datos](../data/data-model.md)).

## Diagrama de contexto (C4 · nivel 1)

> Nivel 1: personas y **sistemas externos**, sin entrar en los repos/servicios internos (eso es el [diagrama de contenedores](#diagrama-de-contenedores-c4--nivel-2)). Por eso **no** aparece aquí Cloudflare ni ningún detalle de despliegue — es infraestructura, no un sistema externo con el que el negocio interactúe.

```mermaid
graph TB
    ADM([🛡️ Administrador])
    USR([🙍 Usuario con cuenta])

    subgraph Sistema I Found It
        APP[Plataforma de seguimiento<br/>de precios]
    end

    SITES[(🌐 Sitios de e-commerce)]
    FX[💱 API de tasa de cambio]
    SMTP[✉️ Servidor SMTP]
    OBS[📡 Observabilidad · Sentry/OTel]
    AI[🤖 API de IA · Gemini · Fase 2]
    CLAUDE[🤖 API de Claude · Fase 2]
    OTHER[🏗️ Otro proyecto propio · Fase futura]

    ADM -->|gestiona usuarios, schedules, adapters| APP
    USR -->|crea/consulta alertas, se suscribe| APP
    APP -->|scrapea precios| SITES
    APP -->|convierte USD→COP| FX
    APP -->|envía novedades / avisos| SMTP
    APP -->|trazas y errores| OBS
    APP -.descubre links.-> AI
    APP -.asiste constructor de adapters.-> CLAUDE
    SMTP -->|novedad / suscripción| USR
    SMTP -->|"aviso: construir adapter (SCR-13)"| ADM
    OTHER -.reutiliza auth/notify.-> APP
```

> **`Otro proyecto propio`** representa el motivo por el que `auth` y `notify` se diseñaron como piezas reutilizables ([ADR-0001](adr/0001-repo-and-service-structure.md)): hoy nadie más los consume, pero la relación existe como razón de diseño desde ya.
>
> **Ya no hay suscriptores sin cuenta** (decidido 2026-09-30): se retiró el rol incógnito, `notify.notification` exige `app_user_id` y `core.subscription.created_by` pasó a ser obligatorio (D13) — todo destino de una notificación es un "Usuario con cuenta" real, sin excepción. Queda un cabo suelto (D16 de los [pendientes](../00-context/pending.md)): `subscription.email` (SUB-1) todavía permite suscribir un correo distinto al de la cuenta. `notify` recibe `app_user_id` **y** un `destination` que pone quien lo llama, así que `core` podría pasar ese otro correo como `destination`; sigue sin decidirse si esa función se mantiene.

## Diagrama de contenedores (C4 · nivel 2)

> Las **5 piezas de backend** que se construyen ([ADR-0001](adr/0001-repo-and-service-structure.md)) — cada una su propio repo, su propio deployable y su propia base/esquema. El detalle interno de cada una está en el [diagrama de componentes](#diagrama-de-componentes-c4--nivel-3), más abajo.

```mermaid
graph TB
    PWA[⚛️ frontend]

    subgraph BACKEND["Backend · 5 repos independientes"]
        AUTH2[🔐 auth]
        CORE2[🧠 core]
        SCHED2[🗓️ schedule<br/>interno · sin ruta pública]
        NOTIFY2[📣 notify]
        SCR2[🕷️ scraper<br/>sin estado · sin BD]
    end

    SITES2[(🌐 Sitios e-commerce)]
    SMTP2[✉️ SMTP]
    OBS2[📡 Observabilidad]

    PWA <-->|HTTPS| AUTH2
    PWA <-->|HTTPS| CORE2
    CORE2 -->|"CRUD de jobs (crea/pausa)<br/>interno, service-to-service"| SCHED2
    SCHED2 -->|"envía una URL + callback<br/>HTTP asíncrono"| SCR2
    SCR2 -->|"callback: entrega el resultado"| SCHED2
    SCHED2 -->|"callback: entrega el precio<br/>(api_call configurado al crear el job)"| CORE2
    SCR2 -->|fetch| SITES2
    CORE2 -->|"decide y llama"| NOTIFY2 --> SMTP2
    SCHED2 -->|"barrido diario de errores"| NOTIFY2
    AUTH2 -->|"código de reset"| NOTIFY2
    AUTH2 & CORE2 & SCHED2 & NOTIFY2 & SCR2 -.->|traza| OBS2
```

## Diagrama de componentes (C4 · nivel 3)

> Solo las piezas **de nuestro dominio** y con las que **interactúan entre sí** — sin bases de datos (ya están en ["Persistencia por servicio"](#persistencia-por-servicio) y en el [modelo de datos](../data/data-model.md)) ni servicios externos como SMTP u Observabilidad (ya están en ["Comunicación entre piezas"](#comunicación-entre-piezas) y en la [Vista de despliegue](#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle)). Cada `subgraph` de servicio es un **repo y un deployable distinto**; las flechas que cruzan un `subgraph` son llamadas de red (HTTP), no llamadas de función.

```mermaid
graph TB
    PWA["⚛️ frontend · React PWA"]

    subgraph SVC_AUTH["🔐 auth"]
        AUTH["Login JWT · access+refresh<br/>RBAC · árbol de accesos<br/>Reset · código 6 díg<br/>Gestión usuarios · solo admin<br/>Registro de systems/apps"]
    end

    subgraph SVC_CORE["🧠 core"]
        ALERT["🔔 Alertas<br/>inmutables + estado"]
        SUBS["📧 Suscripciones"]
        ADAPT["🧩 Registro de adapters<br/>+ constructor manual"]
        SCHEDPROXY[["🗓️ Admin de schedules<br/>proxy a schedule, SCH-4/5/8"]]
        CALLBACK[["📩 Ingesta de precio<br/>recibe el callback de schedule, SCH-14"]]
        NORM["📐 Normalizador"]
        FXP["💱 Tasa de cambio<br/>parametrizable"]
        VALID["🔁 Validador / dedupe<br/>marca caída anómala"]
        DEC["🧠 Motor de decisión<br/>mejor precio · Strategy"]
        STATS["📊 Comparador / estadísticas"]
        HEALTH["🩺 Detalle del scraper · admin"]

        ALERT --> SUBS
        CALLBACK --> NORM --> FXP
        NORM --> VALID --> DEC
    end

    subgraph SVC_SCHED["🗓️ schedule — interno, sin ruta pública (SCH-11)"]
        JOBAPI[["🛠️ API de jobs<br/>crear·consultar — SCH-12"]]
        ENGINE["⏱️ Motor APScheduler en memoria<br/>se carga desde la tabla job al arrancar · ADR-0007"]
        ACTION{{"🎯 Acción al disparar · Strategy<br/>api_call · python_script — Fase 1<br/>topic_message — Fase 2 o 3, SCH-13"}}
        RUNAPI[["📥 API de resultados<br/>recibe el callback del scraper"]]

        JOBAPI --> ENGINE
        RUNAPI -->|"run completado → dispara"| ACTION
    end

    subgraph SVC_NOTIFY["📣 notify"]
        INTAKE[["📝 Recepción<br/>recibe la decisión · crea NOTIFICATION"]]
        SEND["✉️ Envío · plantilla versionada por canal<br/>Jinja2 · unsubscribe · actualiza status sent/failed"]
        INTAKE --> SEND
    end

    subgraph SVC_SCR["🕷️ scraper — sin estado, sin BD"]
        CASC["🪜 Cascada de extracción<br/>adapter→genérico→fallbacks"]
        JOBS["📍 Máquina de estados<br/>granular por job"]
        CASC --> JOBS
    end

    PWA <--> AUTH
    PWA <--> ALERT
    PWA <--> SUBS
    PWA <--> SCHEDPROXY
    PWA <--> ADAPT
    PWA <--> STATS
    PWA <--> HEALTH
    ALERT -->|"crea o pausa el job, con callback = CALLBACK<br/>ALE-8/9"| JOBAPI
    SCHEDPROXY -->|"CRUD: ver, editar, lanzar"| JOBAPI
    HEALTH -->|"consulta corridas, D8"| JOBAPI
    ENGINE -->|"envía una URL + callback<br/>ADR-0004"| CASC
    JOBS -->|"callback con ok, no_price o error"| RUNAPI
    ACTION -->|"api_call: entrega el precio<br/>a la URL configurada"| CALLBACK
    DEC -->|"llama a notify<br/>service-to-service"| INTAKE
    ENGINE -->|"barrido diario de errores"| INTAKE
```

> **`schedule` es exclusivamente interno** (SCH-11): no tiene ruta pública en el Gateway, y el admin lo gestiona desde el frontend **a través de `core`** (`SCHEDPROXY`), nunca directo.
>
> **El scraper recibe el trabajo y un callback configurable** ([ADR-0004](adr/0004-schedule-dispatches-work-to-scraper.md), 2026-11-11; antes hacía *pull*): `schedule` le envía **una URL a la vez**, el scraper responde «recibido» y, al terminar, ejecuta el callback con `ok`, `no_price` o `error`. El scraping y el **análisis** (mejor precio y avisos) son procesos separados a horas distintas (revisión del 2026-11-12); los diagramas del motor de decisión de este documento aún no se han re-revisado para reflejarlo. El destino del callback es configuración; en el ejercicio apunta a `schedule`, así que **el scraper no llama a `core`** (SCR-20). Al completarse, `schedule` dispara la acción `api_call` configurada — que es la que finalmente llama a `CALLBACK` en `core`. `schedule` nunca tiene el dato de «cómo llamar a core» *hardcodeado*: viaja como configuración del job (SCH-14).
>
> **Tres llamadas entre servicios que antes eran una sola tabla** ([ADR-0001](adr/0001-repo-and-service-structure.md)): `ALERT → JOBAPI` (crea/pausa el job, ALE-8/9), `ACTION → CALLBACK` (entrega el precio, resuelve cómo `core` se entera) y `HEALTH → JOBAPI` (consulta corridas, D8).
>
> **`notify` tiene dos pasos, no uno** (2026-09-30): `INTAKE` (Recepción) es quien recibe la llamada de `DEC` y crea la fila `NOTIFICATION` — es **la notificación que se debe enviar**. `SEND` es quien la toma, arma el mensaje con la plantilla de su canal y lo entrega (SMTP en Fase 1). Antes el diagrama los mezclaba en un solo nodo ("Envío"), lo que escondía que nadie tenía modelado el paso de creación. El nodo se llamaba `OUTBOX`; se renombró porque en el [modelo de datos](../data/data-model.md#d-notify-notificaciones) `notification_outbox` es otra cosa: la cola de reintento.
>
> **Una tabla con estado, más una cola de reintento** (reemplaza el modelo de "tres tablas" del 2026-09-30): `NOTIFICATION` lleva su propio `status` (`pending`\|`sent`\|`failed`) y, según el caso, `sent_at`, `provider`, `attempts` y `last_error`; `notification_sent` se fusionó en ella porque nunca mutaba. Si `SEND` falla, inserta/actualiza `NOTIFICATION_OUTBOX` — cola de reintento **activo** (`next_retry_at`, `FOR UPDATE SKIP LOCKED`) que se borra al resolverse. `notify` además es genérico y multicanal: `CHANNEL` (catálogo abierto) y `TEMPLATE` (versionada) viven en el mismo esquema. Detalle en [modelo de datos](../data/data-model.md#d-notify-notificaciones). El mecanismo exacto de `INTAKE → SEND` (en el mismo proceso o con una cola interna) sigue sin decidir — ver [pendientes](../00-context/pending.md), D12.

## Responsabilidad de cada componente

| Servicio | Componente | Responsabilidad |
|----------|------------|-----------------|
| `frontend` | **React PWA** | Menú/módulos para usuarios con cuenta. Español, i18n listo. Sin acceso anónimo. |
| `auth` | **Auth** | Login con access token (~15 min) + refresh (~7 días, rotación/revocación); publica el JWKS que validan `core`/`notify`. |
| `auth` | **RBAC** | Roles/permisos dinámicos, **propios de cada `system`**; un usuario tiene **un rol por `system`** ([ADR-0003](adr/0003-per-system-scope-in-auth.md)). Arma en login el **árbol de accesos** (guardado, `permission.parent_id`) del `system` solicitado. Semilla de `ifoundit`: roles `ADMIN` y `USER` y 19 permisos en MAYÚSCULAS; el prefijo `RULE_` marca una regla de servicio ([modelo de datos](../data/data-model.md#catálogo-de-permisos-de-ifoundit-semilla)). Cada system tiene su `SUPER_ADMIN`, dueño solo de ese system, con todos sus permisos presentes y futuros; los systems nuevos se registran con `register-system.sql`, que lo crea. |
| `auth` | **Reset contraseña** | Código de 6 dígitos por email, válido 15 min + throttle 15 min (llama a `notify` para el envío). |
| `auth` | **Gestión de usuarios** | Alta/gestión **solo admin**; admin sembrado por seed. |
| `auth` | **Registro de systems** | Identifica qué sistema/app llama (`aud=system`) y es dueño de sus roles y permisos; base de la reutilización futura de `auth`/`notify` en otros proyectos. |
| `core` | **Servicio de Alertas** | Crear (URL, 1..N) **inmutables** con `estado`; consultar todas (lectura); pausar/reactivar. |
| `core` | **Suscripciones** | Persona↔alerta por email; unsubscribe por enlace. |
| `core` | **Registro de adapters** | Guarda adapters por dominio; constructor manual del admin; reutilización. |
| `core` | **Ingesta de precio (callback)** | Recibe la llamada `api_call` que `schedule` dispara al completar un *run* (SCH-14); es la única puerta de entrada del precio hacia el Normalizador. |
| `schedule` | **Scheduling** | Motor de jobs **genérico**, reutilizable por cualquier `system`: cada `job` lleva su cron, su `execution_type` (catálogo abierto), un `payload` opaco y un callback. `core` crea el job de scraping de cada alerta (2×/día por defecto); admin ve/edita/lanza y ve progreso; dueño de `job`, `job_script` y `job_execution`. |
| `schedule` | **API de jobs (CRUD) y de resultados** | `core` la usa para crear, pausar y consultar jobs (SCH-12). Al disparar un job, `schedule` usa las URLs guardadas en él, **envía el trabajo al scraper** con su callback y recibe el resultado por esa misma API (SCR-20); si no logra entregar el trabajo, reintenta con backoff exponencial y avisa al administrador llamando a `notify`. |
| `schedule` | **Motor de acciones (Strategy)** | Al completar un *run*, dispara la acción configurada al crear el job (`api_call`/`python_script`); nunca conoce el dominio de negocio de quien la configuró (SCH-13/14). |
| `core` | **Normalizador** | Formato canónico: precio, moneda, stock, título, metadata. |
| `core` | **Tasa de cambio** | Tarea liviana; convierte USD→COP; guarda tasa+fecha en su propia NoSQL (~1 doc/día); parametrizable. |
| `core` | **Validador / dedupe** | Descarta lo inválido (≤0, HTML error); **marca** caídas anómalas (no las descarta). |
| `core` | **Motor de decisión** | "Mejor precio móvil" **global** de la alerta; **Strategy** reemplazable; detecta el aviso y le pasa los datos de la decisión a `notify` (la `notification` ya no la crea `core` — ver sección D del [modelo de datos](../data/data-model.md#d-notify-notificaciones)). |
| `core` | **Comparador / estadísticas** | Histórico y comparación **por sitio** en el tiempo. |
| `core` | **Detalle del scraper (admin)** | Adapters rotos y tasa de éxito son suyos; las **últimas corridas** las pide por API a `schedule` (D8). |
| `scraper` | **Extracción de precios** | Obtiene el precio de cada URL y lo reporta a `schedule`. Sin estado, sin BD; recibe el trabajo de `schedule` y responde por un callback (en el ejercicio no llama a `core`, SCR-20). Cascada, estados, reintentos y fallos: ver el [flujo de scraping](scraping-flow.md). |
| `notify` | **Recepción (INTAKE)** | Recibe la llamada de quien origina el aviso (`core`, `auth` y `schedule`, este último para avisar al administrador) con `transaction_id`, `app_user_id`, canal, `destination`, plantilla y `payload` (opaco), y **crea** la fila `notification` (PostgreSQL, movida desde `core` el 2026-09-30) con `status = pending` — es la notificación **que se debe enviar**. Genérica y multicanal: no conoce ningún concepto de `core`. Reutilizable por otros proyectos (`system`). |
| `notify` | **Envío (SEND)** | Toma una `notification`, arma el mensaje con la **plantilla versionada de su canal** (`template`; en email, Jinja2 con marca de anomalía y enlace de baja) y lo entrega (SMTP en Fase 1; el catálogo `channel` admite SMS/WhatsApp/llamada sin migración). Si tiene éxito, actualiza `notification` (`status = sent`, `sent_at`, `provider`); si falla, inserta/actualiza `notification_outbox` (cola de reintento) y, al agotar los intentos, deja `status = failed`. Archiva lo enviado (sin HTML ni PII) en su propia NoSQL (`notification_log`; su utilidad está en revisión, D18). |
| todos | **Observabilidad** | `transactionId` end-to-end; trazas/errores (OpenTelemetry + Sentry). |

### Persistencia por servicio

> **PostgreSQL es UNA sola instancia** con **cuatro esquemas**, uno por servicio, cada uno con sus propios roles (migraciones y servicio) y sin permisos sobre el de los demás (no hay 4 bases físicas separadas — más realista con un proveedor gratuito que solo da una base por proyecto). MongoDB sí es una base separada por servicio, porque ahí el aislamiento natural es la base. Detalle y scripts en [docs/deliverables/db](../data/scripts/README.md).

| Servicio | Store | Qué guarda |
|----------|-------|-----------|
| `auth` | PostgreSQL, esquema `auth` | RBAC, `person`/`app_user`, `refresh_token`, `password_reset`, `audit_log`, `system`. |
| `core` | PostgreSQL, esquema `core` | Alertas, urls, etiquetas, `alert_snapshot` **un chequeo por resultado** (particionado; último estado, mejor precio y estadísticas por sitio son vistas, DEC-29), suscripciones, adapters. |
| `core` | MongoDB (base propia) | Solo `exchange_rate`. |
| `schedule` | PostgreSQL, esquema `schedule` | `execution_type` (catálogo), `job` (tarea configurada), `job_script` (código serverless), `job_execution` (corridas, con `callback_status`) y `job_callback_outbox` (reintento activo del callback). |
| `schedule` | MongoDB (base propia) | Solo `job_execution_result` — resultado de una corrida, forma libre según `execution_type`, **con TTL 90 días y compresión zstd**. El detalle específico de scraping (`job_state`, `raw_capture`, …) ya no vive aquí (2026-10-01); su nuevo hogar está pendiente (D15). |
| `notify` | PostgreSQL, esquema `notify` | `channel` y `template` (catálogos), `notification` (con `status`) y `notification_outbox` (reintento activo) — `notification` movida desde `core` (2026-09-30). |
| `notify` | MongoDB (base propia) | `notification_log` (archivo de lo enviado, sin HTML ni PII; su utilidad está en revisión, D18) — TTL 180 días. |

> Ningún esquema/base tiene FK ni permisos sobre el de otro servicio — detalle completo en el [Modelo de datos](../data/data-model.md).

## Módulos desacoplados (puntos de extensión)

```mermaid
graph LR
    CORE[Core del sistema] --> I1[«interfaz»<br/>ProveedorTasaCambio]
    CORE --> I2[«interfaz»<br/>EstrategiaMejorPrecio]
    CORE --> I3[«interfaz»<br/>ProveedorIA]
    CORE --> I4[«interfaz»<br/>CanalNotificación]

    I1 --> A1[API externa hoy]
    I1 -.mañana.-> A2[otro proveedor]
    I2 --> B1[Running minimum hoy]
    I2 -.mañana.-> B2[algoritmo más óptimo]
    I3 -.Fase 2.-> C1[Gemini / API Claude]
    I4 --> D1[Email SMTP hoy]
    I4 -.mañana.-> D2[SMS / WhatsApp / llamada]
```

> `Core del sistema` es el repo **`core`** específicamente (no un concepto que abarque los 6 repos): estas 4 interfaces son código interno suyo. `CanalNotificación` hoy significa "llamar por HTTP al servicio `notify`", no una llamada en el mismo proceso — ver [stack tecnológico](../tools/tech-stack.md#interfaces-reemplazables-contratos). Del lado de `notify`, agregar un canal es un `INSERT` en el catálogo `channel` (más su `template`), no una migración.

## Persistencia políglota

> Por qué **PostgreSQL** para lo transaccional y **MongoDB** para lo voluminoso/efímero: relaciones fuertes y consistencia en el primero; alto volumen de escritura, esquema flexible y **solo consulta** en el segundo (mantiene cada PostgreSQL liviano y acotado). El reparto **por servicio** (quién es dueño de qué base, sin FK entre servicios) está en la tabla ["Persistencia por servicio"](#persistencia-por-servicio) de la sección anterior, y el detalle de entidades y colecciones en el [Modelo de datos](../data/data-model.md).

## Concerns transversales

- **🧼 Saneamiento de datos (DoD crítico):** **todo dato se limpia y normaliza antes de persistir** (trim, sin caracteres de control/invisibles, Unicode NFC, precios→numérico, fechas→UTC). Autoridad en BE; el **Normalizador** lo aplica a lo scrapeado y la **validación de entrada** a lo del usuario. Objetivo: análisis congruente (RNF-6).
- **Observabilidad:** `transactionId` generado por corrida/request, propagado entre los 5 servicios de backend (cabecera HTTP en cada llamada); OpenTelemetry (vendor-neutral) + Sentry free en prod.
- **Seguridad (dev):** SAST (Bandit/Semgrep), escaneo de dependencias (pip-audit/Trivy), secretos (Gitleaks), Dependabot; corren en CI de cada repo.
- **Calidad:** lint + tipos + tests unitarios + **E2E (Playwright)**; *quality gates* en CI.
- **Auditoría:** actor + acción + timestamp de operaciones sensibles.

## Vista de despliegue (servicios desacoplados · Cloudflare + GCP + Oracle)

> **Reemplaza** la vista anterior de "polyrepo en una sola VM" (INF-1/INF-15). Cada pieza es su **propio repo y servicio**, con presupuesto $0: **Cloudflare** es la única puerta de entrada; **GCP Cloud Run** aloja los servicios sin estado; la **VM Ampere de Oracle** aloja **únicamente** el scraper (por ser el más pesado en recursos); las bases de datos van en un proveedor gestionado gratuito. Decisión y alternativas evaluadas: ver [ADR-0001](adr/0001-repo-and-service-structure.md).

```mermaid
graph TB
    subgraph USERS["👥 Usuarios"]
        ADM([🛡️ Admin])
        USR([🙍 Usuario])
    end

    subgraph CF["🌩️ Cloudflare · edge — única puerta de entrada"]
        FE[⚛️ frontend<br/>Workers Static Assets]
        GW{{🚦 Worker Gateway<br/>enruta por ruta}}
    end

    subgraph GCP["☁️ GCP · Cloud Run — gratis, escala a cero"]
        AUTH[🔐 auth]
        CORE[🧠 core]
        SCHED[🗓️ schedule]
        NOTIFY[📣 notify]
    end

    subgraph ORACLE["🖥️ Oracle Cloud · VM Ampere — Always Free"]
        SCR[🕷️ scraper<br/>sin estado · sin acceso a BD<br/>solo red interna]
    end

    subgraph DATA["🗄️ Persistencia gestionada — gratis"]
        PG[(🐘 PostgreSQL · 1 instancia<br/>esquemas: auth·core·schedule·notify)]
        MGC[(🍃 MongoDB<br/>core · solo exchange_rate)]
        MGS[(🍃 MongoDB<br/>schedule · detalle de corridas)]
        MGN[(🍃 MongoDB<br/>notify)]
    end

    subgraph EXT["🌐 Servicios externos"]
        SITES[(🛒 Sitios e-commerce)]
        SMTP[✉️ SMTP]
        FX[💱 API tasa de cambio]
        OBS[📡 Observabilidad<br/>Sentry / OTel]
    end

    ADM & USR --> FE
    FE -->|"HTTPS, mismo origen"| GW
    GW -->|"/auth/*"| AUTH
    GW -->|"/api/*"| CORE
    CORE & SCHED & NOTIFY -.->|"JWKS (cacheado)"| GW
    GW -.->|"/auth/.well-known/jwks.json"| AUTH

    CORE -->|"llama a notify<br/>(service-to-service, aud=system)"| GW
    AUTH -->|"código de reset"| GW
    GW -->|"/notify/*"| NOTIFY
    SCHED -->|"barrido diario de errores<br/>(service-to-service)"| GW
    CORE -->|"CRUD de jobs: crea/pausa/consulta<br/>(service-to-service, ALE-8/9, SCH-4/5/8/9)"| GW
    GW -->|"/schedule/internal/jobs"| SCHED

    SCHED -->|"envía una URL + callback<br/>acceso restringido a schedule"| SCR
    SCR -->|"callback: entrega el resultado"| GW
    GW -->|"/schedule/internal/results"| SCHED
    SCHED -->|"callback: entrega el precio<br/>api_call configurado, SCH-14"| GW
    GW -->|"/api/internal/prices"| CORE
    SCR -->|"fetch de precios<br/>(anti-SSRF, SCR-18)"| SITES

    AUTH --> PG
    CORE --> PG
    CORE --> MGC
    SCHED --> PG
    SCHED --> MGS
    NOTIFY --> PG
    NOTIFY --> MGN

    CORE --> FX
    NOTIFY --> SMTP
    AUTH & CORE & SCHED & NOTIFY -.->|"trazas/errores"| OBS
    SCR -.->|"trazas/errores"| OBS
```

**Cómo leerlo:**

- **Cloudflare es la única puerta.** Ningún origen (Cloud Run ni la VM de Oracle) se llama directo; todo pasa por el Worker Gateway o por la red de Cloudflare.
- **El scraper solo es alcanzable por `schedule`** y su callback tiene un destino de lista blanca ([ADR-0004](adr/0004-schedule-dispatches-work-to-scraper.md)). En la VM de Oracle el puerto del scraper se restringe por firewall al origen de `schedule` y no se publica a internet; el mecanismo exacto de red está por definir. `schedule` es quien reenvía el precio a `core`.
- **`schedule` no tiene ninguna ruta pública** (SCH-11): sus rutas bajo `/schedule/internal/*` solo aceptan JWT de servicio (`aud=system`), nunca un token de usuario. El admin lo gestiona desde el frontend, pero la llamada real es `core` la que habla con `schedule`.
- **La validación de JWT vive en cada servicio** (no en el Gateway): `auth` publica su JWKS y `core`/`schedule`/`notify` lo cachean y validan localmente. El Gateway solo enruta y aplica límite de tasa.
- **Una sola base PostgreSQL, aislada por esquema y rol** — no por FK: `core` referencia usuarios de `auth` solo por `uuid` y guarda el `transaction_id` de `schedule.job_execution` solo por valor; `schedule` y `notify` son genéricos y ya no referencian nada de `core` — solo `auth` (`system` por código, usuarios por `uuid`) y un `transaction_id` de correlación opaco. Detalle en [docs/deliverables/db](../data/scripts/README.md).
- **El callback de `schedule` a `core` es configuración, no un conocimiento fijo** (SCH-14): la URL a la que llamar viaja como parte del job creado por `core`, así que `schedule` puede reutilizarse por otro sistema sin tocarle el código.

### Vista mínima

> La misma foto, sin rutas ni etiquetas: solo las piezas, la **red/proveedor** a la que pertenecen y cómo se relacionan. **El Gateway solo enruta tráfico de navegador** (`auth`, `core`); `schedule` y `notify` se alcanzan por llamada directa entre servicios, nunca desde el Gateway.

```mermaid
graph TB
    ADM([🛡️ Admin])
    USR([🙍 Usuario])

    subgraph CF["🌩️ Cloudflare"]
        FE[frontend]
        GW{{Gateway}}
    end

    subgraph GCP["☁️ GCP · Cloud Run"]
        AUTH[auth]
        CORE[core]
        SCHED[schedule]
        NOTIFY[notify]
    end

    subgraph ORACLE["🖥️ Oracle Cloud"]
        SCR[scraper]
    end

    subgraph DATAPROV["🗄️ Proveedor de base de datos"]
        PG[(PostgreSQL)]
        MG[(MongoDB)]
    end

    subgraph WEB["🌐 Internet"]
        SITES[(Sitios e-commerce)]
        SMTPX[(SMTP)]
        FX[(API tasa de cambio)]
    end

    ADM & USR --> FE
    FE --> GW
    GW --> AUTH
    GW --> CORE

    CORE <--> SCHED
    CORE --> NOTIFY
    AUTH --> NOTIFY
    SCHED --> NOTIFY
    SCHED <--> SCR

    AUTH --> PG
    CORE --> PG
    CORE --> MG
    SCHED --> PG
    SCHED --> MG
    NOTIFY --> PG
    NOTIFY --> MG

    SCR --> SITES
    NOTIFY --> SMTPX
    CORE --> FX
```

> **`notify` también vive en PostgreSQL desde el 2026-09-30:** su esquema aloja `channel`, `template`, `notification` (movida desde `core`, ahora con estado propio) y `notification_outbox` (cola de reintento) — ver [modelo de datos](../data/data-model.md#d-notify-notificaciones); su archivo de envíos (`notification_log`) sigue en Mongo. Por eso ahora tiene flecha hacia `PG` y hacia `MG`, igual que `auth`/`core`/`schedule`.

## Comunicación entre piezas

> Protocolo elegido: **REST sobre HTTPS con JSON**, en todas partes (frontend↔backend y backend↔backend). Se evaluaron gRPC, GraphQL y SOAP: gRPC exige un cliente `gRPC-Web` en el navegador (peso de bundle, doble sistema de contratos junto al OpenAPI ya elegido) sin beneficio para nuestro volumen; GraphQL se reconsidera si el comparador/estadísticas (VIS-3/VIS-4) necesitan consultas muy flexibles; SOAP se descarta sin ambigüedad. Todas las filas pasan primero por el **Worker Gateway de Cloudflare**, salvo la fila de Usuario↔Frontend; no se repite en cada una.

### Usuario ↔ Frontend

| Origen | Destino | Qué comunica | Protocolo | Tecnología |
|---|---|---|---|---|
| Admin / Usuario | `frontend` | Navegación de la SPA | HTTPS | Cloudflare Workers Static Assets |

### Frontend ↔ Backend

| Origen | Destino | Qué comunica | Ruta | Protocolo | Tecnología / Auth |
|---|---|---|---|---|---|
| `frontend` | `auth` | Login, reset, gestión de usuarios | `/auth/*` | REST/HTTPS+JSON | FastAPI (OpenAPI) · JWT de usuario |
| `frontend` | `core` | Alertas, suscripciones, adapters, comparador, panel de scraper, y schedules (vía `SCHEDPROXY`) | `/api/*` | REST/HTTPS+JSON | FastAPI (OpenAPI) · JWT de usuario. El frontend **nunca** llega directo a `schedule` (SCH-11) |

### Backend ↔ Backend (service-to-service)

| Origen | Destino | Qué comunica | Ruta | Protocolo | Tecnología / Auth |
|---|---|---|---|---|---|
| `core` | `schedule` | CRUD de jobs: crea/pausa/consulta (ALE-8/9, SCH-4/5/8/9/12, D8) — la consulta incluye la **etapa actual** del *run* en curso, nunca un tiempo estimado¹ | `/schedule/internal/jobs` | REST/HTTPS+JSON | JWT de servicio (`aud=system`) |
| `schedule` | `scraper` | Envía **una URL** con su callback, de forma asíncrona y una tras otra; el scraper responde «recibido» (ADR-0004) | `/scraper/internal/jobs` | REST/HTTPS+JSON | JWT de servicio |
| `scraper` | `schedule` | Callback: entrega el resultado de la URL (`ok`, `no_price` o `error`, SCR-20). Destino configurable, de lista blanca | `/schedule/internal/results` | REST/HTTPS+JSON | JWT de servicio |
| `schedule` | `core` | Callback: entrega el resultado de cada URL de inmediato, en la URL de `api_call` configurada al crear el job (SCH-14). Solo guarda el chequeo; no avisa | `/api/internal/prices` | REST/HTTPS+JSON | JWT de servicio |
| `core` | `notify` | Entrega los datos de la decisión (mejor precio: `transaction_id`, `app_user_id`, canal, `destination`, plantilla y `payload`) para que `notify` cree su propia `notification` y la envíe (`notification` vive en `notify`, no en `core`, desde 2026-09-30) | `/notify/*` | REST/HTTPS+JSON | JWT de servicio |
| `schedule` | `notify` | Pide, una vez al día, un solo correo al administrador con los errores del día (barrido diario, ADR-0004, EJ-6): `transaction_id`, canal, `destination` (dirección del administrador, por entorno), plantilla y `payload` | `/notify/*` | REST/HTTPS+JSON | JWT de servicio |
| `auth` | `notify` | Pide el envío del código de reset | `/notify/*` | REST/HTTPS+JSON | JWT de servicio |
| `core` / `schedule` / `notify` | `auth` | Descarga y cachea el JWKS (valida JWT localmente) | `/auth/.well-known/jwks.json` | REST/HTTPS+JSON | Sin credencial (endpoint público de claves) |

> ¹ No es posible calcular cuánto falta ni "a qué velocidad va" un job de scraping (depende del sitio, de si cae en fallback Playwright, de reintentos) — lo único observable es la etapa actual (`job_state`, SCR-16). Cómo llega esa etapa hasta el navegador sigue sin decidir — ver [pendientes](../00-context/pending.md), D11.

### Backend → Servicios externos

| Origen | Destino | Qué comunica | Protocolo | Tecnología |
|---|---|---|---|---|
| `scraper` | Sitios e-commerce | Extrae el precio (cascada) | HTTP(S) | httpx (HTTP-first) / Playwright — validado anti-SSRF (SCR-18) |
| `core` | API de tasa de cambio | Convierte USD→COP | REST/HTTPS | Cliente HTTP; proveedor aún por definir (ver stack tecnológico) |
| `notify` | Servidor SMTP | Envía el correo | SMTP | aiosmtplib |

### Transversal

| Origen | Destino | Qué comunica | Protocolo | Tecnología |
|---|---|---|---|---|
| Los 5 servicios de backend | Observabilidad | Trazas y errores, con `transactionId` | OTLP / HTTPS | OpenTelemetry + Sentry SDK |

