-- =====================================================================
-- CORE · esquema `CORE`
-- Se corre con el rol `CORE_SERVICE` (provision-roles.sql), que es dueño
-- EXCLUSIVO de este esquema. Un campo `*_BY` es un `uuid` de solo valor
-- hacia AUTH.APP_USER, y `RUN_ID` es un `bigint` de solo valor hacia
-- SCHEDULE.RUN — SIN FK real entre esquemas; la integridad la garantiza
-- `CORE` al escribir, no la base de datos. Ver ../README.md.
-- =====================================================================

-- El esquema lo crea provision-roles.sql (el rol de servicio no tiene CREATE sobre la base).
SET search_path TO CORE;


-- A) Referencia (informativa, sin FK) -----------------------------------

CREATE TABLE CURRENCY (
    CODE    text PRIMARY KEY,  -- ISO 4217: COP, USD, EUR…
    NAME_ES text NOT NULL
);
INSERT INTO CURRENCY (CODE, NAME_ES) VALUES ('COP', 'Peso colombiano'), ('USD', 'Dólar'), ('EUR', 'Euro');

-- Estados de negocio: código directo + CHECK, sin tabla catálogo:
--   ALERT.STATUS         'active' | 'inactive'
--   SUBSCRIPTION.STATUS  'active' | 'unsubscribed'
--   RUN.STATUS           'queued' | 'running' | 'completed' | 'failed' (vive en SCHEDULE)
--   SITE_ADAPTER.STATUS  'active' | 'broken'
--   NOTIFICATION.STATUS  'queued' | 'sent' | 'failed' (vive en NOTIFY, no aquí)

-- C) Alertas, etiquetas y adapters ----------------------------------------

CREATE TABLE ALERT (
    ID                      int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TITLE                   text NOT NULL,
    PRODUCT_NAME            text NOT NULL,
    NOTES                   text CHECK (char_length(NOTES) <= 500), -- opcional, la escribe el usuario al crear (DEC-28)
    STATUS                  text NOT NULL DEFAULT 'active' CHECK (STATUS IN ('active', 'inactive')),
    CREATED_BY              uuid NOT NULL,        -- id de auth.app_user, sin FK
    CREATED_AT              timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT              timestamptz NOT NULL DEFAULT now(),
    BEST_PRICE_COP          numeric(14,2),         -- mejor precio GLOBAL vigente (materializado)
    BEST_PRICE_AT           timestamptz,
    BEST_PRICE_ALERT_URL_ID int,                   -- FK compuesta, ver abajo
    SCHEDULE_JOB_ID         int                    -- id de schedule.job, sin FK (otro esquema); NULL = «sin schedule», pendiente de crear el job (DEC-15)
);

CREATE TABLE ALERT_URL (
    ID              int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ALERT_ID        int NOT NULL REFERENCES ALERT(ID),
    URL             text NOT NULL CHECK (char_length(URL) <= 2048), -- validada anti-SSRF (SCR-18); largo DEC-20
    DOMAIN          text NOT NULL,           -- normalizado, lookup de adapter
    IS_ACTIVE       boolean NOT NULL DEFAULT true,
    BEST_PRICE_COP  numeric(14,2),           -- mejor precio POR SITIO (materializado)
    BEST_PRICE_AT   timestamptz,
    LAST_PRICE_COP  numeric(14,2),           -- último precio vigente (VIS-1 sin escanear snapshots)
    LAST_IN_STOCK   boolean,                 -- último stock informado; null si el sitio no lo informa (DEC-21). No se usa en el análisis (DEC-22)
    LAST_CHECKED_AT timestamptz,             -- último chequeo, cambie o no el precio
    LAST_TITLE      text,                    -- no se historiza
    -- Último dato completo que devolvió el scraper (D38): se sobrescribe en cada chequeo exitoso, no se historiza.
    LAST_LIST_PRICE_COP   numeric(14,2),     -- precio antes de la promoción; solo si > LAST_PRICE_COP
    LAST_PRICE_VALID_UNTIL date,             -- fin de la promoción
    LAST_BRAND      text,
    LAST_SKU        text,                    -- referencia del vendedor
    LAST_GTIN       text,                    -- código de barras (EAN/UPC)
    LAST_MPN        text,                    -- referencia del fabricante
    LAST_IMAGES     text[] CHECK (cardinality(LAST_IMAGES) <= 10), -- solo URLs http/https; el scraper no las descarga y vienen del sitio (no confiables)
    LAST_METADATA   jsonb,                   -- vendedor, envío… (no se historiza)
    CREATED_AT      timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (ALERT_ID, ID),                   -- soporta la FK compuesta de `ALERT`
    UNIQUE (ALERT_ID, URL)                   -- una URL no se repite dentro de la alerta (DEC-20)
);
CREATE INDEX IX_ALERT_URL_ALERT ON ALERT_URL(ALERT_ID);
CREATE INDEX IX_ALERT_URL_DOMAIN ON ALERT_URL(DOMAIN);

-- Garantiza que el "mejor sitio" pertenece a esa misma alerta (evita la
-- referencia circular ingenua).
ALTER TABLE ALERT
    ADD CONSTRAINT FK_ALERT_BEST_PRICE_URL
    FOREIGN KEY (ID, BEST_PRICE_ALERT_URL_ID) REFERENCES ALERT_URL (ALERT_ID, ID);

CREATE TABLE TAG (
    ID   int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    NAME text UNIQUE NOT NULL   -- normalizada: minúscula, sin tildes
);

CREATE TABLE ALERT_TAG (
    ALERT_ID int NOT NULL REFERENCES ALERT(ID),
    TAG_ID   int NOT NULL REFERENCES TAG(ID),
    PRIMARY KEY (ALERT_ID, TAG_ID)
);

-- `SCHEDULE` y `RUN` viven en el esquema `SCHEDULE` (schedule/schema.sql),
-- no aquí — ver ../README.md.

CREATE TABLE SITE_ADAPTER (
    ID              int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    DOMAIN          text UNIQUE NOT NULL,
    DEFINITION      jsonb NOT NULL,     -- DECLARATIVO (selectores/JSONPath); nunca código ejecutable
    VERSION         int NOT NULL DEFAULT 1,
    STATUS          text NOT NULL DEFAULT 'active' CHECK (STATUS IN ('active', 'broken')),
    LAST_SUCCESS_AT timestamptz,
    CREATED_BY      uuid NOT NULL,      -- id de auth.app_user, sin FK
    CREATED_AT      timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE SITE_STATS_DAILY (
    DOMAIN       text NOT NULL,
    DAY          date NOT NULL,
    OK_COUNT     int NOT NULL DEFAULT 0,
    FAILED_COUNT int NOT NULL DEFAULT 0,
    BY_STRATEGY  jsonb,               -- conteo por estrategia ganadora
    PRIMARY KEY (DOMAIN, DAY)
);

-- D) Corridas y snapshots --------------------------------------------------
-- (la tabla `RUN` vive en el esquema `SCHEDULE`, no aquí — ver ../README.md)

-- Particionada por año. Solo se inserta un snapshot cuando cambia el
-- precio respecto al último (idempotencia por diseño, SCR-7); un
-- job crea la partición del año siguiente (pendiente, ver docs/deliverables/db/README.md).
CREATE TABLE PRICE_SNAPSHOT (
    ALERT_URL_ID        int NOT NULL REFERENCES ALERT_URL(ID),
    CAPTURED_AT         timestamptz NOT NULL,   -- clave de partición
    RUN_ID              bigint NOT NULL,        -- id de schedule.job_execution, sin FK (otro esquema)
    PRICE_COP           numeric(14,2) NOT NULL CHECK (PRICE_COP > 0),
    PRICE_ORIGINAL      numeric(14,2),          -- null si ya es COP
    LIST_PRICE_COP      numeric(14,2),          -- precio antes de la promoción (null si no hay); CHECK > PRICE_COP
    PRICE_VALID_UNTIL   date,                   -- fin de la promoción (null si no la publica)
    CURRENCY            text REFERENCES CURRENCY(CODE), -- null si COP
    EXCHANGE_RATE_DATE  date,                   -- 🔗 Mongo exchange_rate (null si COP)
    IN_STOCK            boolean,                -- stock informado; null si el sitio no lo informa (DEC-21). El análisis no lo usa (DEC-22)
    CHECK (LIST_PRICE_COP IS NULL OR LIST_PRICE_COP > PRICE_COP),
    PRIMARY KEY (ALERT_URL_ID, CAPTURED_AT)
) PARTITION BY RANGE (CAPTURED_AT);

CREATE TABLE PRICE_SNAPSHOT_2026 PARTITION OF PRICE_SNAPSHOT
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

-- Veredicto de «caída anómala» (R9, DEC-18, ADR-0005). Append-only y aparte del
-- snapshot: cambiar de estrategia agrega filas, nunca reescribe las anteriores.
-- El dashboard y el aviso leen las filas de la estrategia activa.
CREATE TABLE PRICE_ANOMALY (
    ALERT_URL_ID     int NOT NULL,
    CAPTURED_AT      timestamptz NOT NULL,
    STRATEGY         text NOT NULL,           -- nombre en el registro de estrategias, p.ej. 'peer_robust_outlier'
    STRATEGY_VERSION int NOT NULL,
    IS_ANOMALOUS     boolean NOT NULL,
    REASON           text NOT NULL CHECK (REASON IN ('ok', 'first_capture', 'insufficient_sample', 'no_dispersion', 'outlier')),
    SCORE            numeric,                 -- p.ej. modified z-score; null si no aplica
    PARAMS           jsonb NOT NULL DEFAULT '{}'::jsonb, -- parámetros usados (ventana, umbral, muestra)
    EVALUATED_AT     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ALERT_URL_ID, CAPTURED_AT, STRATEGY, STRATEGY_VERSION),
    FOREIGN KEY (ALERT_URL_ID, CAPTURED_AT) REFERENCES PRICE_SNAPSHOT (ALERT_URL_ID, CAPTURED_AT)
);

-- CREATED_BY es obligatorio (2026-09-30, D13): toda suscripción exige
-- cuenta — se retiró el rol incógnito y notify.notification exige
-- app_user_id, así que ya no existe la suscripción "solo por email".
CREATE TABLE SUBSCRIPTION (
    ID                     int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ALERT_ID               int NOT NULL REFERENCES ALERT(ID),
    EMAIL                  text NOT NULL CHECK (EMAIL = lower(EMAIL) AND char_length(EMAIL) <= 254), -- normalizado a minúsculas (lo exige la base); se precarga con el de la cuenta (SUB-1)
    STATUS                 text NOT NULL DEFAULT 'active' CHECK (STATUS IN ('active', 'unsubscribed')),
    CREATED_BY             uuid NOT NULL,       -- id de auth.app_user, sin FK — usuario dueño de la suscripción
    UNSUBSCRIBE_TOKEN_HASH bytea NOT NULL,       -- nunca en claro
    CREATED_AT             timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT             timestamptz NOT NULL DEFAULT now(),
    UNIQUE (ALERT_ID, EMAIL)
);
CREATE INDEX IX_SUBSCRIPTION_ALERT ON SUBSCRIPTION(ALERT_ID);

-- `NOTIFICATION` (outbox transaccional) YA NO vive aquí: se movió al
-- esquema `NOTIFY` (2026-09-30) — la notificación es el dato que `NOTIFY`
-- posee de punta a punta, no `CORE`. Ver notify/schema.sql y
-- docs/03-modelo-datos.md#d2-notificaciones-servicio-notify.
