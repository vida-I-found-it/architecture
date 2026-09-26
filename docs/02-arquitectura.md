# 02 · Arquitectura

> Consolidado con el [Alcance 1](08-alcance-1-preguntas.md) y los [requerimientos](deliverables/requerimientos.md). Refleja roles/RBAC, ejecución background con cola+workers, la **cascada de scraping con adapters aprendidos**, la máquina de estados del job, persistencia políglota, observabilidad y despliegue polyrepo portable a la nube.

## Principios de diseño

- **Modular y desacoplado:** las piezas que cambiarán —proveedor de IA, tasa de cambio, estrategia de "mejor precio", canal de notificación— viven **tras una interfaz**, reemplazables sin tocar el core.
- **Scraping en background, no en el request:** el trabajo pesado corre en **workers** alimentados por una **cola**, **escalonados** en ventanas horarias.
- **Scraping que aprende:** extractor genérico (JSON-LD/schema.org) + cascada de fallbacks; los sitios difíciles obtienen un **adapter guardado por dominio** que se **reutiliza** (sin re-trabajo).
- **Observable de punta a punta:** cada corrida lleva un `transactionId` que atraviesa API, workers y logs; máquina de estados granular por job.
- **Polyrepo, portable, sin lock-in:** cada componente en su repo, empaquetado en contenedores + config por entorno (12-factor). Corre igual local que en free tier.
- **Idempotente y append-only:** las corridas se reintentan sin duplicar ni corromper el historial.

## Vista general (de un vistazo)

```mermaid
graph TB
    subgraph Usuarios
        ADM([🛡️ Admin])
        USR([🙍 Usuario])
        INC([👤 Incógnito · inactivo F1])
    end

    subgraph Frontend
        PWA[⚛️ React PWA<br/>Vite + TS + shadcn/ui]
    end

    subgraph Backend
        API[🔌 API · FastAPI<br/>JWT + RBAC + módulos]
        SCH[⏰ Scheduler<br/>2×/día · ventanas]
        Q[[📥 Cola]]
        WK[⚙️ Workers background<br/>escalonados]
        EXTR[🧩 Cascada de extracción<br/>+ adapters aprendidos]
        DEC[🧠 Motor de decisión<br/>mejor precio · Strategy]
        NOT[📣 Notificador email · SMTP]
    end

    subgraph "Servicios externos"
        SITES[(🌐 Sitios e-commerce)]
        FX[💱 API tasa de cambio]
        SMTP[✉️ SMTP]
        OBS[📡 Observabilidad<br/>Sentry / OTel]
        AI[🤖 Gemini · Fase 2]
    end

    subgraph Datos
        PG[(🐘 PostgreSQL + JSONB)]
        NOSQL[(🍃 NoSQL documental)]
    end

    ADM & USR --> PWA
    INC -.Fase 2.-> PWA
    PWA <--> API
    API --> PG
    SCH --> Q --> WK --> EXTR
    EXTR --> SITES
    WK --> FX
    EXTR --> DEC
    DEC --> PG
    DEC --> NOT --> SMTP
    WK --> NOSQL
    API & WK -.traza.-> OBS
    API -.Fase 2.-> AI
    EXTR -.Fase 2.-> AI
```

## Diagrama de contexto (C4 · nivel 1)

```mermaid
graph TB
    ADM([🛡️ Administrador])
    USR([🙍 Usuario con cuenta])
    INC([👤 Incógnito · inactivo en Fase 1])

    subgraph Sistema I Found It
        APP[Plataforma de seguimiento<br/>de precios]
    end

    SITES[(🌐 Sitios de e-commerce)]
    FX[💱 API de tasa de cambio]
    SMTP[✉️ Servidor SMTP]
    OBS[📡 Observabilidad · Sentry/OTel]
    AI[🤖 API de IA · Gemini · Fase 2]

    ADM -->|gestiona usuarios, schedules, adapters| APP
    USR -->|crea/consulta alertas, se suscribe| APP
    APP -->|scrapea precios| SITES
    APP -->|convierte USD→COP| FX
    APP -->|envía novedades / avisos admin| SMTP
    APP -->|trazas y errores| OBS
    APP -.descubre links.-> AI
    SMTP -->|email| USR
```

## Diagrama de componentes (C4 · nivel 2)

```mermaid
graph TB
    subgraph Presentación
        PWA[⚛️ React PWA]
        API[🔌 API FastAPI]
    end

    subgraph "Seguridad y cuentas"
        AUTH[🔐 Auth · login JWT<br/>access+refresh]
        RBAC[🌳 RBAC · rol/permiso<br/>árbol de accesos]
        PWDR[🔁 Reset · código 6 díg]
        USERS[👥 Gestión usuarios<br/>solo admin]
    end

    subgraph "Dominio"
        ALERT[🔔 Servicio de Alertas<br/>inmutables + estado]
        SUBS[📧 Suscripciones]
        SCHED[🗓️ Servicio de Schedules<br/>admin: ver/editar/lanzar]
        ADAPT[🧩 Registro de adapters<br/>+ constructor manual]
    end

    subgraph "Ingesta · background"
        SCH[⏰ Scheduler · ventanas]
        Q[[📥 Cola]]
        WK[⚙️ Workers escalonados]
        CASC[🪜 Cascada de extracción<br/>adapter→genérico→fallbacks]
        JOBS[📍 Máquina de estados<br/>granular por job]
    end

    subgraph "Procesamiento"
        NORM[📐 Normalizador]
        FXP[💱 Tasa de cambio<br/>tarea liviana · parametrizable]
        VALID[🔁 Validador / dedupe<br/>marca desplome anómalo]
        DEC[🧠 Motor de decisión<br/>mejor precio · Strategy]
    end

    subgraph "Salida"
        NOTF[📣 Notificador email<br/>plantilla única · unsubscribe]
        STATS[📊 Comparador / estadísticas]
        HEALTH[🩺 Detalle del scraper · admin]
    end

    subgraph "Persistencia políglota"
        PG[(🐘 PostgreSQL + JSONB)]
        NOSQL[(🍃 NoSQL documental)]
    end

    OBS[📡 Observabilidad · transactionId]

    PWA <--> API
    API --> AUTH --> RBAC
    AUTH --> PWDR
    API --> USERS
    API --> ALERT --> SUBS
    ALERT --> SCHED
    API --> ADAPT
    SCHED --> SCH --> Q --> WK --> CASC
    CASC --> ADAPT
    WK --> JOBS --> NOSQL
    CASC --> NORM --> FXP
    NORM --> VALID --> PG
    PG --> DEC --> NOTF --> SMTP2[✉️ SMTP]
    NOTF --> NOSQL
    API --> STATS --> PG
    API --> HEALTH --> NOSQL
    ALERT --> PG
    API & WK -.-> OBS
```

## La cascada de scraping (el "cerebro")

```mermaid
graph TD
    START[Job de un sitio] --> A0{¿Adapter<br/>guardado para<br/>el dominio?}
    A0 -->|sí| USE[Usar adapter guardado]
    A0 -->|no| C1[1 · JSON-LD / og:price]
    C1 -->|falla| C2[2 · Microdata/RDFa/meta + regex]
    C2 -->|falla| C3[3 · Playwright render]
    C3 -->|falla| C4[4 · Interceptar XHR/JSON]
    C4 -->|falla| RT{Reintentos<br/>controlados<br/>máx 3}
    RT -->|reintenta 10-15m| C1
    RT -->|agotados| N7[7 · Email al admin]
    N7 --> BUILD[Admin construye adapter<br/>manual · guarda por dominio]
    BUILD -.reutiliza siempre.-> A0
    USE --> OK[✅ Precio capturado]
    C1 & C2 & C3 & C4 -->|éxito| OK
```

> **Fase 2:** entre el paso 4 y el aviso al admin se sumará el **extractor con IA** (#5), y el constructor de adapters tendrá **asistencia de IA** (evaluar API de Claude).

## Responsabilidad de cada componente

| Componente | Responsabilidad |
|------------|-----------------|
| **React PWA** | Menú/módulos para usuarios con cuenta. Español, i18n listo. (Incógnito inactivo en Fase 1.) |
| **API (FastAPI)** | Expone módulos; valida JWT; aplica RBAC; orquesta el dominio. |
| **Auth** | Login con access token (~15 min) + refresh (~7 días, rotación/revocación). |
| **RBAC** | Roles/permisos dinámicos; arma el **árbol de accesos** en login. 3 roles sembrados (incógnito inactivo). |
| **Reset contraseña** | Código de 6 dígitos por email, válido 15 min + throttle 15 min. |
| **Gestión de usuarios** | Alta/gestión **solo admin**; admin sembrado por seed. |
| **Servicio de Alertas** | Crear (URL, 1..N) **inmutables** con `estado`; consultar todas (lectura); pausar/reactivar. |
| **Suscripciones** | Persona↔alerta por email; unsubscribe por enlace. |
| **Servicio de Schedules** | Schedule por alerta (2×/día por defecto); admin ve/edita/lanza y ve progreso. |
| **Registro de adapters** | Guarda adapters por dominio; constructor manual del admin; reutilización. |
| **Scheduler + Cola + Workers** | Encolan y ejecutan corridas en **background escalonado** dentro de ventanas (04–06 / 18–20, env). |
| **Cascada de extracción** | Adapter guardado → JSON-LD → microdata/regex → Playwright → XHR; reintentos controlados; robots.txt + rate limit. |
| **Máquina de estados** | Registra **cada etapa del job con su hora** (NoSQL); alimenta la vista de progreso. |
| **Normalizador** | Formato canónico: precio, moneda, stock, título, metadata. |
| **Tasa de cambio** | Tarea liviana; convierte USD→COP; guarda tasa+fecha en NoSQL; parametrizable. |
| **Validador / dedupe** | Descarta lo inválido (≤0, HTML error); **marca** desplomes anómalos (no los descarta). |
| **Motor de decisión** | "Mejor precio móvil" **global** de la alerta; **Strategy** reemplazable; dispara email. |
| **Notificador** | Email SMTP, plantilla única (con marca de anomalía y enlace de baja); registra en NoSQL. |
| **Comparador / estadísticas** | Histórico y comparación **por sitio** en el tiempo. |
| **Detalle del scraper (admin)** | Adapters rotos, tasa de éxito, sitios sin precio, últimas corridas. |
| **Observabilidad** | `transactionId` end-to-end; trazas/errores (OpenTelemetry + Sentry). |
| **PostgreSQL** | Transaccional: RBAC, usuarios, alertas, urls, schedules, snapshots, suscripciones, adapters. |
| **NoSQL** | Documental (solo consulta): estados del job, resúmenes de corrida, capturas crudas, log de notificaciones, tasa de cambio. |

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
    I4 -.mañana.-> D2[Telegram / Slack / SMS]
```

## Persistencia políglota

| Store | Qué guarda | Por qué |
|-------|-----------|---------|
| **PostgreSQL (+ JSONB)** | RBAC, usuarios, alertas, urls, etiquetas, schedules, `price_snapshot` (append-only), suscripciones, adapters | Relaciones fuertes, consistencia, series temporales; JSONB para metadata de captura |
| **NoSQL** (documental) | `job_estado`, `corrida_resumen`, `captura_cruda` (solo fallo), `notificacion_log`, `tasa_cambio` | Alto volumen de escritura, esquema flexible, **solo consulta**; mantiene PostgreSQL liviano |

> Detalle de entidades y colecciones en el [doc 03 · Modelo de datos](03-modelo-datos.md).

## Concerns transversales

- **🧼 Saneamiento de datos (DoD crítico):** **todo dato se limpia y normaliza antes de persistir** (trim, sin caracteres de control/invisibles, Unicode NFC, precios→numérico, fechas→UTC). Autoridad en BE; el **Normalizador** lo aplica a lo scrapeado y la **validación de entrada** a lo del usuario. Objetivo: análisis congruente (RNF-6).
- **Observabilidad:** `transactionId` generado por corrida/request, propagado por API y workers; OpenTelemetry (vendor-neutral) + Sentry free en prod.
- **Seguridad (dev):** SAST (Bandit/Semgrep), escaneo de dependencias (pip-audit/Trivy), secretos (Gitleaks), Dependabot; corren en CI de cada repo.
- **Calidad:** lint + tipos + tests unitarios + **E2E (Playwright)**; *quality gates* en CI.
- **Auditoría:** actor + acción + timestamp de operaciones sensibles.

## Vista de despliegue (polyrepo · local → nube)

```mermaid
graph TB
    subgraph Repos["📦 Polyrepo (un repo por pieza)"]
        r1[repo frontend]
        r2[repo api]
        r3[repo workers/scraper]
    end
    r1 & r2 & r3 -->|CI: build+lint+tests+seguridad| IMG[(Registry de imágenes)]

    subgraph LOCAL["🖥️ Desarrollo · Docker Compose"]
        L[PWA · API · Workers · PostgreSQL · NoSQL · Redis]
    end

    subgraph PROD["☁️ Producción · free tier (⏳ provider por decidir)"]
        FEP[Frontend · CDN estático o VM]
        VMP[VM: API · Workers · PostgreSQL · NoSQL · Redis]
    end

    IMG --> LOCAL
    IMG --> PROD
    EXT[Servicios externos: SMTP · tasa cambio · Sentry] -.-> PROD
```

> **Mismas imágenes** local y prod; solo cambia la config por entorno. **INF-15**: frontend en CDN estático o servido por la VM; backend + datos + cola en una VM free tier (Oracle/GCP). **Provider y host del frontend: decisión pendiente.**

## Notas

- La **cola** es Redis + un runner de tareas ligero — se detalla en el [doc 04](04-stack-tecnologico.md).
- El **flujo diario** paso a paso está en el [doc 05](05-flujo-scraping.md).
- El **modelo de datos** (entidades y colecciones) en el [doc 03](03-modelo-datos.md).
