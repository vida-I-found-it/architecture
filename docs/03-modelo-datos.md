# 03 · Modelo de datos

> Consolidado con el [Alcance 1](08-alcance-1-preguntas.md) y los [requerimientos](deliverables/requerimientos.md). Persistencia **políglota**: PostgreSQL (relacional + JSONB) para lo transaccional, y **MongoDB** (documental) para logs/telemetría de solo consulta.
>
> **Convenciones:** nombres en **inglés**, `snake_case`; PK `id`; FK `<entidad>_id`; booleanos `is_*`; fechas `*_at` en **UTC**. Comentarios de cada campo **en español**. Cada colección NoSQL se alcanza desde el modelo relacional mediante un **puente** (`*_doc_id` / `transaction_id`).

## Principios

- **🧼 Datos limpios (DoD crítico):** **todo dato se persiste saneado y normalizado** (sin espacios sobrantes, sin caracteres de control/invisibles, Unicode NFC, precios numéricos, fechas en UTC, emails/etiquetas normalizados). Ningún registro entra "sucio" → el análisis es congruente (RNF-6).
- **Append-only para precios:** cada corrida inserta snapshots nuevos; nunca se sobrescribe.
- **Políglota por rol:** PostgreSQL para relaciones/consistencia; **MongoDB** para documentos de alto volumen y solo lectura.
- **Puente relacional → NoSQL:** las tablas guardan la referencia al documento para navegar al detalle.
- **Correlación por `transaction_id`:** todo lo de una corrida comparte el mismo id de trazabilidad.
- **Valores controlados sin catálogo:** `gender`/`currency` como código (tablas informativas) y estados con **CHECK/enum** → sin FK innecesarias.
- **Timestamps:** toda **entidad mutable** lleva `created_at` **+** `updated_at` (UTC); las tablas **append-only/log** (`price_snapshot`, `audit_log`, `notification`, `refresh_token`, `password_reset`) solo llevan su timestamp de evento.

## Reparto de la persistencia

```mermaid
graph TB
    subgraph PG["🐘 PostgreSQL · transaccional"]
        A1["referencia / RBAC / persons / users"]
        A2["alerts / urls / tags"]
        A3["schedules / runs"]
        A4["price_snapshots (append-only)"]
        A5["subscriptions / notifications"]
        A6["site_adapters"]
    end
    subgraph NOSQL["🍃 MongoDB · documental · solo consulta"]
        B1["job_state"]
        B2["run_summary"]
        B3["raw_capture (solo fallo)"]
        B4["notification_log"]
        B5["exchange_rate"]
    end
    A3 -.->|"summary_doc_id"| B2
    A3 -.->|"transaction_id"| B1
    A3 -.->|"transaction_id"| B3
    A5 -.->|"log_doc_id"| B4
    A4 -.->|"exchange_rate_date"| B5
```

---

## A) Valores de referencia y estados

> **`gender` y `currency` NO son FK.** Son **tablas informativas** que documentan los códigos válidos; en las tablas de negocio se guarda directamente el **código mínimo representativo**.

### Tablas informativas (referencia, sin FK)

| Tabla informativa | Código (lo que se guarda) | Se usa en |
|-------------------|---------------------------|-----------|
| `gender` | `H`, `M`, … | `person.gender` |
| `currency` | `COP`, `USD`, `EUR`, … (ISO 4217) | `price_snapshot.currency` |

### Estados por código (CHECK/enum, sin FK)

> Los estados se guardan como **código** en la propia tabla, validados por **CHECK/enum** — **sin** tabla catálogo ni FK.

| Campo | Códigos válidos |
|-------|-----------------|
| `alert.status` | `active`, `inactive` |
| `subscription.status` | `active`, `unsubscribed` |
| `run.status` | `queued`, `running`, `completed`, `failed` |
| `site_adapter.status` | `active`, `broken` |

## B) Seguridad y cuentas (RBAC + Auth)

> **Persona vs Usuario:** `person` guarda los **datos de la persona** (identidad/PII); `user` guarda la **cuenta** (credenciales, rol). Relación **1:1**. PK **UUID** generado en ambas.

```mermaid
erDiagram
    PERSON ||--|| APP_USER : "es cuenta de"
    ROLE ||--o{ ROLE_PERMISSION : has
    PERMISSION ||--o{ ROLE_PERMISSION : in
    ROLE ||--o{ APP_USER : classifies
    APP_USER ||--o{ REFRESH_TOKEN : owns
    APP_USER ||--o{ PASSWORD_RESET : requests
    APP_USER ||--o{ AUDIT_LOG : performs

    PERSON {
        uuid id PK "Identificador (UUID generado)"
        string first_name "Nombres"
        string last_name "Apellidos"
        date birth_date "Fecha de nacimiento"
        string gender "Código de género (H/M/…) — ref. informativa"
        string phone "Teléfono (opcional)"
        datetime created_at "Fecha de creación (UTC)"
        datetime updated_at "Última actualización (UTC)"
    }
    APP_USER {
        uuid id PK "Identificador de cuenta (UUID generado)"
        uuid person_id FK "Persona asociada (1:1)"
        string email UK "Correo (único, normalizado en minúscula)"
        string password_hash "Hash de contraseña (bcrypt/argon2)"
        int role_id FK "Rol asignado"
        bool is_active "Cuenta habilitada"
        datetime created_at "Fecha de creación (UTC)"
        datetime updated_at "Última actualización (UTC)"
    }
    ROLE {
        int id PK "Identificador"
        string code UK "admin | user | incognito"
        string name_es "Nombre visible del rol"
        bool is_active "Rol habilitado (incognito=false en Fase 1)"
        string description "Descripción del rol"
    }
    PERMISSION {
        int id PK "Identificador"
        string code UK "Clave del permiso (ej. alert.create)"
        string description "Qué habilita el permiso"
    }
    ROLE_PERMISSION {
        int role_id FK "Rol"
        int permission_id FK "Permiso concedido al rol"
    }
    REFRESH_TOKEN {
        uuid id PK "Identificador (UUID)"
        uuid user_id FK "Usuario dueño del token"
        string token_hash "Hash del refresh token"
        datetime expires_at "Expira (~7 días)"
        bool is_revoked "Revocado (rotación/logout)"
        datetime created_at "Fecha de emisión (UTC)"
    }
    PASSWORD_RESET {
        uuid id PK "Identificador (UUID)"
        uuid user_id FK "Usuario que solicita el reset"
        string code_hash "Hash del código de 6 dígitos"
        datetime expires_at "Expira (15 min)"
        bool is_used "Ya utilizado"
        datetime requested_at "Momento de solicitud (throttle 15 min)"
    }
    AUDIT_LOG {
        uuid id PK "Identificador (UUID)"
        uuid actor_user_id FK "Quién ejecutó la acción"
        string action "Acción realizada"
        string entity "Entidad afectada"
        string entity_id "Id de la entidad afectada"
        datetime occurred_at "Cuándo ocurrió (UTC)"
    }
```

## C) Alertas, etiquetas, schedules y adapters

```mermaid
erDiagram
    APP_USER ||--o{ ALERT : creates
    ALERT ||--o{ ALERT_URL : monitors
    ALERT ||--o{ ALERT_TAG : classified_by
    TAG ||--o{ ALERT_TAG : in
    ALERT ||--|| SCHEDULE : scheduled_by

    ALERT {
        int id PK "Identificador"
        string title "Título de la alerta"
        string product_name "Nombre del producto/servicio"
        string notes "Observaciones"
        string status "Estado: active | inactive (CHECK)"
        uuid created_by FK "Usuario creador"
        datetime created_at "Fecha de creación (UTC)"
        datetime updated_at "Última actualización (UTC)"
        decimal best_price_cop "Mejor precio GLOBAL vigente (materializado, COP)"
        datetime best_price_at "Cuándo se registró ese mejor precio"
        int best_price_alert_url_id FK "Sitio (URL) con el mejor precio"
    }
    ALERT_URL {
        int id PK "Identificador"
        int alert_id FK "Alerta a la que pertenece"
        string url "URL del producto en el sitio"
        string domain "Dominio (para lookup de adapter)"
        bool is_active "URL activa dentro de la alerta"
        decimal best_price_cop "Mejor precio POR SITIO (materializado, COP)"
        datetime best_price_at "Cuándo se registró el mejor precio del sitio"
        datetime created_at "Fecha de creación (UTC)"
        datetime updated_at "Última actualización (UTC)"
    }
    TAG {
        int id PK "Identificador"
        string name UK "Etiqueta normalizada (minúscula, sin tildes)"
    }
    ALERT_TAG {
        int alert_id FK "Alerta"
        int tag_id FK "Etiqueta asociada"
    }
    SCHEDULE {
        int id PK "Identificador"
        int alert_id FK "Alerta programada (1:1)"
        int runs_per_day "Corridas por día (máx 2)"
        json windows "Ventanas horarias (ej. [04-06, 18-20])"
        bool is_active "Programación activa"
        datetime next_run_at "Próxima corrida (UTC)"
        datetime last_run_at "Última corrida (UTC)"
        datetime created_at "Fecha de creación (UTC)"
        datetime updated_at "Última actualización (UTC)"
    }
    SITE_ADAPTER {
        int id PK "Identificador"
        string domain UK "Dominio del sitio (único)"
        json definition "Definición del extractor (selectores/estrategia)"
        string status "Estado: active | broken (CHECK)"
        uuid created_by FK "Admin que lo creó"
        datetime created_at "Fecha de creación (UTC)"
        datetime updated_at "Última actualización (UTC)"
    }
```

## D) Corridas, snapshots, suscripciones y notificaciones (con puentes a NoSQL)

```mermaid
erDiagram
    ALERT ||--o{ RUN : executes
    SCHEDULE ||--o{ RUN : triggers
    RUN ||--o{ PRICE_SNAPSHOT : produces
    ALERT_URL ||--o{ PRICE_SNAPSHOT : captured_at_site
    ALERT ||--o{ SUBSCRIPTION : receives
    ALERT ||--o{ NOTIFICATION : notifies
    RUN ||--o{ NOTIFICATION : originates
    SUBSCRIPTION ||--o{ NOTIFICATION : sent_to

    RUN {
        int id PK "Identificador"
        int alert_id FK "Alerta corrida"
        int schedule_id FK "Schedule que la disparó"
        string transaction_id "Id de trazabilidad end-to-end"
        string status "Estado: queued | running | completed | failed (CHECK)"
        datetime started_at "Inicio (UTC)"
        datetime finished_at "Fin (UTC)"
        int total_sites "Total de sitios procesados"
        int sites_ok "Sitios con precio capturado"
        int sites_failed "Sitios fallidos"
        string summary_doc_id "🔗 Puente → NoSQL run_summary (detalle)"
        datetime updated_at "Última actualización de estado (UTC)"
    }
    PRICE_SNAPSHOT {
        int id PK "Identificador"
        int alert_url_id FK "URL/sitio capturado"
        int run_id FK "Corrida que lo generó"
        string transaction_id "Id de trazabilidad"
        decimal price "Precio en moneda original"
        string currency "Código de moneda original (COP/USD/…) — ref. informativa"
        decimal price_cop "Precio convertido a COP"
        decimal exchange_rate "Tasa aplicada (null si ya es COP)"
        date exchange_rate_date "🔗 Fecha de la tasa → NoSQL exchange_rate"
        bool in_stock "Disponibilidad"
        string title "Título capturado del producto"
        json metadata "Datos útiles (vendedor, envío, etc.)"
        string capture_hash "Hash para dedupe"
        bool is_anomalous "Desplome sospechoso (marca en email)"
        datetime captured_at "Momento de captura (UTC)"
    }
    SUBSCRIPTION {
        int id PK "Identificador"
        int alert_id FK "Alerta suscrita"
        string email "Correo suscriptor (normalizado)"
        string status "Estado: active | unsubscribed (CHECK)"
        uuid created_by FK "Usuario que suscribió (nullable)"
        string unsubscribe_token "Token del enlace de baja"
        datetime created_at "Fecha de suscripción (UTC)"
        datetime updated_at "Última actualización (UTC)"
    }
    NOTIFICATION {
        int id PK "Identificador"
        int alert_id FK "Alerta notificada"
        int run_id FK "Corrida que originó el aviso"
        int subscription_id FK "Suscripción destinataria"
        string channel "Canal (email en Fase 1)"
        datetime sent_at "Envío (UTC)"
        string log_doc_id "🔗 Puente → NoSQL notification_log (contenido)"
    }
```

### Puentes relacional → NoSQL

| Tabla relacional | Campo puente | Colección NoSQL |
|------------------|--------------|-----------------|
| `run` | `summary_doc_id` / `transaction_id` | `run_summary`, `job_state`, `raw_capture` |
| `notification` | `log_doc_id` | `notification_log` |
| `price_snapshot` | `exchange_rate_date` | `exchange_rate` |

> Regla: para ver el **detalle** de algo cuyo grano vive en NoSQL, se parte de la fila relacional y se sigue su campo puente. Así el relacional queda liviano y el detalle voluminoso queda en documentos.

---

## E) MongoDB · colecciones (solo consulta)

| Colección | Contenido (documento) | Clave/puente | Requerimiento |
|-----------|----------------------|--------------|---------------|
| **run_summary** | Resumen de corrida: sitios ok/fallidos, duración, nº snapshots | `_id` = `run.summary_doc_id`; `transaction_id` | SCR-14 |
| **job_state** | Máquina de estados granular por sitio: `[{state, at}]`, estado actual | `transaction_id` + `alert_url_id` | SCR-16 · SCH-9 |
| **raw_capture** | HTML/JSON crudo **solo en fallo total**; insumo del constructor de adapters | `transaction_id` + `domain` | SCR-15 · SCR-12 |
| **notification_log** | Contenido del email enviado por suscriptor | `_id` = `notification.log_doc_id` | NOT-4 · I27 |
| **exchange_rate** | Histórico de tasa: `pair` (USD/COP), `rate`, `captured_at`, `source` | `date` ↔ `price_snapshot.exchange_rate_date` | PRO-3 |

## Decisiones de diseño (registradas)

| Tema | Decisión |
|------|----------|
| **Tabla `run`** | ✅ Sí, en PostgreSQL, con puente `summary_doc_id` al detalle NoSQL |
| **Etiquetas** | Tabla normalizada `tag` + `alert_tag` |
| **Referencia sin FK** | `gender` (H/M/…) y `currency` (COP/USD/…) como **tablas informativas**; se guarda el **código** en la tabla de negocio |
| **Estados** | **Código directo con CHECK/enum** (sin FK): `alert.status`, `subscription.status`, `run.status`, `site_adapter.status` |
| **Persona vs Usuario** | `person` (PII) separado de `user` (cuenta), relación 1:1 |
| **PK de person/user** | **UUID** generado |
| **Mejor precio** | Materializado **global** en `alert` **y por sitio** en `alert_url` |
| **Nombres/idioma** | Tablas y campos en **inglés**; comentarios en **español** |
| **Puentes** | Cada colección NoSQL se alcanza desde el relacional por `*_doc_id` / `transaction_id` |
| **Motor NoSQL** | ✅ **MongoDB** (confirmado; se refleja en el [doc 04 · stack](04-stack-tecnologico.md)) |
| **Timestamps** | Entidades mutables con `created_at` + `updated_at`; tablas append-only/log solo su timestamp de evento |

## Índices sugeridos

- `price_snapshot (alert_url_id, captured_at)` — series temporales y comparador por sitio.
- `price_snapshot (run_id)` y `price_snapshot (transaction_id)` — correlación con la corrida.
- `run (alert_id, started_at)` — historial de corridas por alerta.
- `alert_url (domain)` — lookup de adapter.
- `subscription (alert_id, email)` UK — evitar duplicados.
- `site_adapter (domain)` UK.
- Tablas informativas (`gender`, `currency`): `code` UK. Estados: **CHECK** en cada columna `status` (sin índice de catálogo).

## Pendientes / a validar

- Definir umbral exacto de `is_anomalous` con el motor de decisión.
- Política de retención/purga del histórico y de las colecciones NoSQL (fase futura).
