-- =====================================================================
-- core · esquema `core`
-- Se corre con el rol `core_service` (provision-roles.sql), que es dueño
-- EXCLUSIVO de este esquema. Un campo `*_by` es un `uuid` de solo valor
-- hacia auth.app_user, y `run_id` es un `bigint` de solo valor hacia
-- schedule.run — SIN FK real entre esquemas; la integridad la garantiza
-- `core` al escribir, no la base de datos. Ver ../README.md.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS core;
SET search_path TO core;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- A) Referencia (informativa, sin FK) -----------------------------------

CREATE TABLE currency (
    code    text PRIMARY KEY,  -- ISO 4217: COP, USD, EUR…
    name_es text NOT NULL
);
INSERT INTO currency (code, name_es) VALUES ('COP', 'Peso colombiano'), ('USD', 'Dólar'), ('EUR', 'Euro');

-- Estados de negocio: código directo + CHECK, sin tabla catálogo:
--   alert.status         'active' | 'inactive'
--   subscription.status  'active' | 'unsubscribed'
--   run.status           'queued' | 'running' | 'completed' | 'failed'
--   site_adapter.status  'active' | 'broken'
--   notification.status  'queued' | 'sent' | 'failed'

-- C) Alertas, etiquetas, schedules y adapters ----------------------------

CREATE TABLE alert (
    id                      int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title                   text NOT NULL,
    product_name            text NOT NULL,
    notes                   text,
    status                  text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_by              uuid NOT NULL,        -- id de auth.app_user, sin FK
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    best_price_cop          numeric(14,2),         -- mejor precio GLOBAL vigente (materializado)
    best_price_at           timestamptz,
    best_price_alert_url_id int                    -- FK compuesta, ver abajo
);

CREATE TABLE alert_url (
    id              int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    alert_id        int NOT NULL REFERENCES alert(id),
    url             text NOT NULL,           -- validada anti-SSRF (SCR-18)
    domain          text NOT NULL,           -- normalizado, lookup de adapter
    is_active       boolean NOT NULL DEFAULT true,
    best_price_cop  numeric(14,2),           -- mejor precio POR SITIO (materializado)
    best_price_at   timestamptz,
    last_price_cop  numeric(14,2),           -- último precio vigente (VIS-1 sin escanear snapshots)
    last_in_stock   boolean,
    last_checked_at timestamptz,             -- último chequeo, cambie o no el precio
    last_title      text,                    -- no se historiza
    last_metadata   jsonb,                   -- vendedor, envío… (no se historiza)
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (alert_id, id)                    -- soporta la FK compuesta de `alert`
);
CREATE INDEX ix_alert_url_alert ON alert_url(alert_id);
CREATE INDEX ix_alert_url_domain ON alert_url(domain);

-- Garantiza que el "mejor sitio" pertenece a esa misma alerta (evita la
-- referencia circular ingenua).
ALTER TABLE alert
    ADD CONSTRAINT fk_alert_best_price_url
    FOREIGN KEY (id, best_price_alert_url_id) REFERENCES alert_url (alert_id, id);

CREATE TABLE tag (
    id   int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text UNIQUE NOT NULL   -- normalizada: minúscula, sin tildes
);

CREATE TABLE alert_tag (
    alert_id int NOT NULL REFERENCES alert(id),
    tag_id   int NOT NULL REFERENCES tag(id),
    PRIMARY KEY (alert_id, tag_id)
);

-- `schedule` y `run` viven en el esquema `schedule` (schedule/schema.sql),
-- no aquí — ver ../README.md.

CREATE TABLE site_adapter (
    id              int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    domain          text UNIQUE NOT NULL,
    definition      jsonb NOT NULL,     -- DECLARATIVO (selectores/JSONPath); nunca código ejecutable
    version         int NOT NULL DEFAULT 1,
    status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'broken')),
    last_success_at timestamptz,
    created_by      uuid NOT NULL,      -- id de auth.app_user, sin FK
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE site_stats_daily (
    domain       text NOT NULL,
    day          date NOT NULL,
    ok_count     int NOT NULL DEFAULT 0,
    failed_count int NOT NULL DEFAULT 0,
    by_strategy  jsonb,               -- conteo por estrategia ganadora
    PRIMARY KEY (domain, day)
);

-- D) Corridas, snapshots, suscripciones y notificaciones ------------------
-- (la tabla `run` vive en el esquema `schedule`, no aquí — ver ../README.md)

-- Particionada por año. Solo se inserta un snapshot cuando cambia el
-- precio/stock respecto al último (idempotencia por diseño, SCR-7); un
-- job crea la partición del año siguiente (pendiente, ver docs/deliverables/db/README.md).
CREATE TABLE price_snapshot (
    alert_url_id        int NOT NULL REFERENCES alert_url(id),
    captured_at         timestamptz NOT NULL,   -- clave de partición
    run_id              bigint NOT NULL,        -- id de schedule.run, sin FK (otro esquema)
    price_cop           numeric(14,2) NOT NULL CHECK (price_cop > 0),
    price_original      numeric(14,2),          -- null si ya es COP
    currency            text REFERENCES currency(code), -- null si COP
    exchange_rate_date  date,                   -- 🔗 Mongo exchange_rate (null si COP)
    in_stock            boolean NOT NULL,
    is_anomalous        boolean NOT NULL DEFAULT false,
    PRIMARY KEY (alert_url_id, captured_at)
) PARTITION BY RANGE (captured_at);

CREATE TABLE price_snapshot_2026 PARTITION OF price_snapshot
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

CREATE TABLE subscription (
    id                     int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    alert_id               int NOT NULL REFERENCES alert(id),
    email                  citext NOT NULL,     -- normalizado, case-insensitive
    status                 text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'unsubscribed')),
    created_by             uuid,                -- id de auth.app_user, sin FK (nullable)
    unsubscribe_token_hash bytea NOT NULL,       -- nunca en claro
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    UNIQUE (alert_id, email)
);
CREATE INDEX ix_subscription_alert ON subscription(alert_id);

-- Outbox transaccional: el motor de decisión la escribe en la misma
-- transacción que actualiza best_price_*. `core` llama a `notify` con
-- este `id`; `notify` guarda el detalle (sin HTML) en su propio
-- notification_log (Mongo, otro servicio) — mecanismo exacto pendiente,
-- ver docs/deliverables/db/README.md.
CREATE TABLE notification (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    alert_id             int NOT NULL REFERENCES alert(id),
    run_id               bigint NOT NULL,        -- id de schedule.run, sin FK (otro esquema)
    subscription_id      int NOT NULL REFERENCES subscription(id),
    channel              text NOT NULL DEFAULT 'email',
    status               text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'failed')),
    attempts             smallint NOT NULL DEFAULT 0,
    trigger_alert_url_id int NOT NULL REFERENCES alert_url(id),
    trigger_price_cop    numeric(14,2) NOT NULL,
    created_at           timestamptz NOT NULL DEFAULT now(),
    sent_at              timestamptz,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_id, subscription_id)
);
CREATE INDEX ix_notification_queued ON notification(status) WHERE status = 'queued';
CREATE INDEX ix_notification_subscription ON notification(subscription_id);
