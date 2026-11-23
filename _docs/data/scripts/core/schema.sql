-- =====================================================================
-- CORE · esquema `CORE`
-- Se corre con el rol `CORE_SERVICE` (provision-roles.sql), que es dueño
-- EXCLUSIVO de este esquema. Un campo `*_BY` es un `uuid` de solo valor
-- hacia AUTH.APP_USER, y `TRANSACTION_ID` es un `uuid` de solo valor hacia
-- SCHEDULE.JOB_EXECUTION — SIN FK real entre esquemas; la integridad la garantiza
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
    -- El mejor precio NO se guarda: se deriva de ALERT_SNAPSHOT (vista V_ALERT_BEST_PRICE, DEC-29).
    SCHEDULE_JOB_ID         int                    -- id de schedule.job, sin FK (otro esquema); NULL = «sin schedule», pendiente de crear el job (DEC-15)
);

CREATE TABLE ALERT_URL (
    ID              int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ALERT_ID        int NOT NULL REFERENCES ALERT(ID),
    URL             text NOT NULL CHECK (char_length(URL) <= 2048), -- validada anti-SSRF (SCR-18); largo DEC-20
    DOMAIN          text NOT NULL,           -- normalizado, lookup de adapter
    IS_ACTIVE       boolean NOT NULL DEFAULT true,
    -- Precio, stock, fecha y estado de cada chequeo viven SOLO en ALERT_SNAPSHOT (DEC-29);
    -- el último estado es la última fila de ALERT_SNAPSHOT (vista V_ALERT_URL_LAST_CHECK).
    -- Aquí solo queda la descripción del producto en la URL (D38): último valor
    -- informado, se sobrescribe en cada chequeo `ok` y no se historiza.
    LAST_TITLE      text,
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

-- D) Seguimiento de precios ------------------------------------------------
-- (la tabla `RUN` vive en el esquema `SCHEDULE`, no aquí — ver ../README.md)

-- Seguimiento (DEC-29): UNA fila por ejecución y por URL, cada vez que se
-- chequea, sea cual sea el resultado. Es la única fuente del histórico, del
-- último estado, del mejor precio y de las estadísticas por sitio (vistas
-- abajo). El resultado completo del scraper vive en la Mongo de `schedule`
-- (job_execution_result, _id = TRANSACTION_ID); aquí solo va lo que se consulta.
-- Idempotencia (SCR-7): CHECKED_AT es la hora del resultado que reporta
-- `schedule` y es la misma en cada reenvío del callback, así que un reenvío
-- choca con la PK y no duplica.
-- Particionada por año; un job crea la partición del año siguiente (pendiente).
CREATE TABLE ALERT_SNAPSHOT (
    ALERT_URL_ID        int NOT NULL REFERENCES ALERT_URL(ID),
    CHECKED_AT          timestamptz NOT NULL,   -- clave de partición
    TRANSACTION_ID      uuid NOT NULL,          -- transaction_id de schedule.job_execution (= _id del resultado en Mongo), sin FK (otro esquema)
    STATUS              text NOT NULL CHECK (STATUS IN ('ok', 'no_price', 'error')),
    STRATEGY            text,                   -- estrategia ganadora del scraper; solo si `ok`
    PRICE_COP           numeric(14,2) CHECK (PRICE_COP > 0),
    PRICE_ORIGINAL      numeric(14,2),          -- null si ya es COP
    LIST_PRICE_COP      numeric(14,2),          -- precio antes de la promoción (null si no hay); CHECK > PRICE_COP
    PRICE_VALID_UNTIL   date,                   -- fin de la promoción (null si no la publica)
    CURRENCY            text REFERENCES CURRENCY(CODE), -- null si COP
    EXCHANGE_RATE_DATE  date,                   -- 🔗 Mongo exchange_rate (null si COP)
    IN_STOCK            boolean,                -- stock informado; null si el sitio no lo informa (DEC-21). El análisis no lo usa (DEC-22)
    -- Solo un `ok` trae precio; `no_price` y `error` no traen ningún dato de precio.
    CHECK ((STATUS = 'ok') = (PRICE_COP IS NOT NULL)),
    CHECK (STATUS = 'ok' OR (STRATEGY IS NULL AND LIST_PRICE_COP IS NULL AND PRICE_VALID_UNTIL IS NULL
                             AND PRICE_ORIGINAL IS NULL AND CURRENCY IS NULL AND IN_STOCK IS NULL)),
    CHECK (LIST_PRICE_COP IS NULL OR LIST_PRICE_COP > PRICE_COP),
    PRIMARY KEY (ALERT_URL_ID, CHECKED_AT)
) PARTITION BY RANGE (CHECKED_AT);
-- La PK sirve para el histórico y el último chequeo de una URL. Este índice
-- sirve para el último precio `ok` sin recorrer una racha de `no_price`/`error`.
CREATE INDEX IX_ALERT_SNAPSHOT_OK ON ALERT_SNAPSHOT(ALERT_URL_ID, CHECKED_AT DESC) WHERE STATUS = 'ok';

CREATE TABLE ALERT_SNAPSHOT_2026 PARTITION OF ALERT_SNAPSHOT
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

-- Veredicto de «caída anómala» (R9, DEC-18, ADR-0005). Append-only y aparte del
-- chequeo: cambiar de estrategia agrega filas, nunca reescribe las anteriores.
-- Solo se evalúan chequeos `ok`. El dashboard y el aviso leen la estrategia activa.
CREATE TABLE PRICE_ANOMALY (
    ALERT_URL_ID     int NOT NULL,
    CHECKED_AT       timestamptz NOT NULL,
    STRATEGY         text NOT NULL,           -- nombre en el registro de estrategias, p.ej. 'peer_robust_outlier'
    STRATEGY_VERSION int NOT NULL,
    IS_ANOMALOUS     boolean NOT NULL,
    REASON           text NOT NULL CHECK (REASON IN ('ok', 'first_capture', 'insufficient_sample', 'no_dispersion', 'outlier')),
    SCORE            numeric,                 -- p.ej. modified z-score; null si no aplica
    PARAMS           jsonb NOT NULL DEFAULT '{}'::jsonb, -- parámetros usados (ventana, umbral, muestra)
    EVALUATED_AT     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ALERT_URL_ID, CHECKED_AT, STRATEGY, STRATEGY_VERSION),
    FOREIGN KEY (ALERT_URL_ID, CHECKED_AT) REFERENCES ALERT_SNAPSHOT (ALERT_URL_ID, CHECKED_AT)
);

-- Registro del análisis (DEC-30): UNA fila por alerta en cada análisis,
-- append-only. Guarda la decisión tomada, no un dato derivable: el «mejor
-- precio anterior» para DEC-6/DEC-16 es la última fila con chequeo ganador,
-- y no se recalcula (ALERT_URL.IS_ACTIVE no se historiza y el recálculo
-- podría diferir de lo que se decidió). El precio NO se copia: se apunta al
-- chequeo ganador y se lee con un JOIN.
--   OUTCOME 'first'     primer mejor precio de la alerta: no avisa
--           'dropped'   bajó respecto del anterior: avisa (CU-10)
--           'not_lower' igual o más alto: no avisa
--           'no_data'   ninguna URL activa con precio `ok`: no avisa ni cambia el anterior
CREATE TABLE ALERT_ANALYSIS (
    ALERT_ID          int NOT NULL REFERENCES ALERT(ID),
    ANALYZED_AT       timestamptz NOT NULL,
    TRANSACTION_ID    uuid NOT NULL UNIQUE,    -- uno por alerta analizada; si OUTCOME='dropped', es la llave idempotente de la llamada a notify (DEC-12)
    BEST_ALERT_URL_ID int,                     -- URL ganadora; null si 'no_data'
    BEST_CHECKED_AT   timestamptz,             -- chequeo ganador; null si 'no_data'
    OUTCOME           text NOT NULL CHECK (OUTCOME IN ('first', 'dropped', 'not_lower', 'no_data')),
    PRIMARY KEY (ALERT_ID, ANALYZED_AT),       -- repetir el análisis con la misma hora no duplica; la última fila se lee por la PK
    CHECK ((OUTCOME = 'no_data') = (BEST_ALERT_URL_ID IS NULL)),
    CHECK ((BEST_ALERT_URL_ID IS NULL) = (BEST_CHECKED_AT IS NULL)),
    -- La URL ganadora es de esta misma alerta, y el chequeo ganador existe.
    FOREIGN KEY (ALERT_ID, BEST_ALERT_URL_ID) REFERENCES ALERT_URL (ALERT_ID, ID),
    FOREIGN KEY (BEST_ALERT_URL_ID, BEST_CHECKED_AT) REFERENCES ALERT_SNAPSHOT (ALERT_URL_ID, CHECKED_AT)
);

-- Vistas derivadas de ALERT_SNAPSHOT (DEC-29): nada de esto se guarda dos veces.
-- Se materializan solo si una medición lo justifica.

-- Último chequeo de cada URL (cualquier estado) y su último precio `ok`.
-- Alimenta el dashboard (CU-07) y «sin datos recientes» (DEC-17).
CREATE VIEW V_ALERT_URL_LAST_CHECK AS
SELECT u.ID AS ALERT_URL_ID, u.ALERT_ID, u.IS_ACTIVE,
       lc.CHECKED_AT AS LAST_CHECKED_AT, lc.STATUS AS LAST_STATUS,
       lo.CHECKED_AT AS LAST_OK_AT, lo.PRICE_COP AS LAST_PRICE_COP,
       lo.LIST_PRICE_COP AS LAST_LIST_PRICE_COP, lo.PRICE_VALID_UNTIL AS LAST_PRICE_VALID_UNTIL,
       lo.IN_STOCK AS LAST_IN_STOCK
FROM ALERT_URL u
LEFT JOIN LATERAL (SELECT c.CHECKED_AT, c.STATUS FROM ALERT_SNAPSHOT c
                   WHERE c.ALERT_URL_ID = u.ID ORDER BY c.CHECKED_AT DESC LIMIT 1) lc ON true
LEFT JOIN LATERAL (SELECT c.CHECKED_AT, c.PRICE_COP, c.LIST_PRICE_COP, c.PRICE_VALID_UNTIL, c.IN_STOCK
                   FROM ALERT_SNAPSHOT c WHERE c.ALERT_URL_ID = u.ID AND c.STATUS = 'ok'
                   ORDER BY c.CHECKED_AT DESC LIMIT 1) lo ON true;

-- Mejor precio vigente de la alerta (DEC-16): el mínimo de los últimos precios
-- `ok` de sus URLs activas, sin mirar el stock (DEC-22). Empate: la URL más antigua.
CREATE VIEW V_ALERT_BEST_PRICE AS
SELECT DISTINCT ON (l.ALERT_ID)
       l.ALERT_ID, l.ALERT_URL_ID AS BEST_PRICE_ALERT_URL_ID,
       l.LAST_PRICE_COP AS BEST_PRICE_COP, l.LAST_OK_AT AS BEST_PRICE_AT
FROM V_ALERT_URL_LAST_CHECK l
WHERE l.IS_ACTIVE AND l.LAST_PRICE_COP IS NOT NULL
ORDER BY l.ALERT_ID, l.LAST_PRICE_COP, l.ALERT_URL_ID;

-- Estadísticas por sitio y día (antes la tabla SITE_STATS_DAILY).
CREATE VIEW V_SITE_STATS_DAILY AS
SELECT u.DOMAIN, (c.CHECKED_AT AT TIME ZONE 'UTC')::date AS DAY,
       count(*) FILTER (WHERE c.STATUS = 'ok')       AS OK_COUNT,
       count(*) FILTER (WHERE c.STATUS = 'no_price') AS NO_PRICE_COUNT,
       count(*) FILTER (WHERE c.STATUS = 'error')    AS ERROR_COUNT
FROM ALERT_SNAPSHOT c JOIN ALERT_URL u ON u.ID = c.ALERT_URL_ID
GROUP BY u.DOMAIN, (c.CHECKED_AT AT TIME ZONE 'UTC')::date;

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
