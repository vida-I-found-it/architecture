-- =====================================================================
-- SCHEDULE · esquema `SCHEDULE`
-- Se corre con el rol `SCHEDULE_SERVICE` (provision-roles.sql), que es
-- dueño EXCLUSIVO de este esquema. `SYSTEM` es un `text` de solo valor
-- hacia `AUTH.SYSTEM` — SIN FK real entre esquemas; la integridad la
-- garantiza quien escribe, no la base de datos — ver ../README.md.
--
-- Rediseño genérico (2026-10-01, resuelve D9): `SCHEDULE`/`RUN` dejaron
-- de existir. `JOB` ya NO conoce `alert_id` ni ningún concepto de
-- `CORE` — es un motor de tareas programadas de propósito general,
-- reutilizable por cualquier `SYSTEM`. Lo único que `JOB` sabe de su
-- contenido es lo que el propio `EXECUTION_TYPE` interpreta; para
-- `SCHEDULE` el `PAYLOAD` es opaco.
--
-- Tres ideas, tres tablas (o pares de tablas) separadas:
--   JOB               la tarea configurada: cómo se ejecuta, con qué
--                      entrada, cuándo (cron) y a quién avisar al final
--   JOB_SCRIPT         código fuente — SOLO si execution_type='script'
--                      (serverless, lenguaje acotado por CHECK)
--   JOB_EXECUTION      una corrida: trazabilidad de inicio/fin/estado
--   JOB_CALLBACK_SENT / JOB_CALLBACK_OUTBOX
--                      igual patrón que NOTIFICATION_SENT/OUTBOX en
--                      `notify`: "callback entregado" y "callback en
--                      reintento por fallo" son cosas distintas, no un
--                      status que muta en el sitio.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS SCHEDULE;
SET search_path TO SCHEDULE;

-- Catálogo ABIERTO (con FK real desde JOB, a diferencia de un CHECK):
-- agregar un tipo de ejecución nuevo es un INSERT, no una migración.
-- REQUIRES_SANDBOX marca los tipos que ejecutan código del cliente
-- (hoy solo 'script') y por tanto exigen runtime aislado — pendiente de
-- diseñar, ver docs/09-pendientes.md.
CREATE TABLE EXECUTION_TYPE (
    CODE             text PRIMARY KEY,       -- p.ej. 'scrape', 'db_query', 'http_call', 'script'
    DESCRIPTION      text NOT NULL,
    REQUIRES_SANDBOX boolean NOT NULL DEFAULT false,
    IS_ACTIVE        boolean NOT NULL DEFAULT true
);
INSERT INTO EXECUTION_TYPE (CODE, DESCRIPTION, REQUIRES_SANDBOX) VALUES
    ('scrape',   'Cascada de extracción de precios (conector interno de confianza)', false),
    ('db_query', 'Consulta/mantenimiento parametrizado sobre una base de datos',      false),
    ('http_call','Llamada HTTP saliente genérica',                                   false),
    ('script',   'Código serverless enviado por el cliente (Python/JavaScript)',     true);

-- La tarea CONFIGURADA. Sin alert_id, sin nada de core: PAYLOAD es la
-- única entrada de negocio, y es opaca para SCHEDULE.
CREATE TABLE JOB (
    ID              int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SYSTEM          text NOT NULL,            -- código de auth.system, sin FK — dueño del job (multi-proyecto)
    NAME            text NOT NULL,            -- etiqueta legible, p.ej. 'Limpieza semanal de snapshots'
    EXECUTION_TYPE  text NOT NULL REFERENCES EXECUTION_TYPE(CODE), -- FK real, misma esquema
    PAYLOAD         jsonb NOT NULL DEFAULT '{}'::jsonb, -- entrada específica del execution_type; opaca aquí
    SCHEDULE_CRON   text NOT NULL,            -- expresión cron estándar (soportada nativa por APScheduler)
    IS_ACTIVE       boolean NOT NULL DEFAULT true,
    CALLBACK_TYPE   text NOT NULL CHECK (CALLBACK_TYPE IN ('api_call', 'python_script', 'topic_message')), -- SCH-13
    CALLBACK_CONFIG jsonb NOT NULL DEFAULT '{}'::jsonb, -- p.ej. {"url": "..."} si CALLBACK_TYPE='api_call'
    NEXT_RUN_AT     timestamptz,
    LAST_RUN_AT     timestamptz,
    CREATED_AT      timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT      timestamptz NOT NULL DEFAULT now()
);
-- El scheduler toma lo vencido con FOR UPDATE SKIP LOCKED sobre este índice.
CREATE INDEX IX_JOB_NEXT_RUN ON JOB(NEXT_RUN_AT) WHERE IS_ACTIVE;
CREATE INDEX IX_JOB_SYSTEM ON JOB(SYSTEM); -- toda consulta multi-proyecto filtra primero por system

-- Código fuente — 1:1 con JOB, SOLO existe cuando execution_type='script'.
-- LANGUAGE va acotado por CHECK a propósito: ampliar la lista de
-- lenguajes soportados es una decisión de seguridad explícita (requiere
-- migración), no un INSERT libre como EXECUTION_TYPE.
CREATE TABLE JOB_SCRIPT (
    JOB_ID          int PRIMARY KEY REFERENCES JOB(ID), -- FK real, misma esquema
    LANGUAGE        text NOT NULL CHECK (LANGUAGE IN ('python', 'javascript')),
    SOURCE          text NOT NULL,            -- código fuente completo
    ENTRYPOINT      text,                     -- función/handler a invocar (opcional, ej. 'handler')
    RUNTIME_VERSION text,                     -- versión fijada del runtime (ej. '3.12', '20') — opcional
    VERSION         int NOT NULL DEFAULT 1,   -- mismo patrón que core.site_adapter.version
    CREATED_AT      timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT      timestamptz NOT NULL DEFAULT now()
);

-- Una CORRIDA de un JOB. Trazabilidad: cuándo empieza, cuándo termina,
-- en qué estado está. El resultado/detalle (de forma y tamaño variables
-- según execution_type) NO vive aquí — va a la Mongo de schedule,
-- puente por transaction_id (ver ../schedule/mongo-setup.js).
-- JOB_EXECUTION lleva DOS estados independientes en la misma fila
-- (2026-10-0X, reemplaza a JOB_CALLBACK_SENT): STATUS es el trabajo
-- PROPIO del job (queued→running→completed/failed); CALLBACK_STATUS es
-- si se logró AVISAR el resultado — dos cosas distintas (un job puede
-- terminar 'completed' y su callback seguir fallando). Se fusionan en
-- una sola fila porque CALLBACK_SENT nunca mutaba (se escribía UNA vez,
-- al éxito): no había motivo de espacio/rendimiento para una tabla
-- aparte. Lo que SÍ sigue aparte es JOB_CALLBACK_OUTBOX, porque eso sí
-- muta en cada reintento — ver su comentario abajo.
CREATE TABLE JOB_EXECUTION (
    ID                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    JOB_ID            int NOT NULL REFERENCES JOB(ID), -- FK real, misma esquema
    SYSTEM            text NOT NULL,             -- código de auth.system, sin FK (denormalizado, lookup rápido)
    TRANSACTION_ID    uuid NOT NULL UNIQUE,      -- trazabilidad end-to-end; _id del resultado en Mongo
    STATUS            text NOT NULL DEFAULT 'queued'
                          CHECK (STATUS IN ('queued', 'running', 'completed', 'failed')),
    STARTED_AT        timestamptz,
    FINISHED_AT       timestamptz,
    CALLBACK_STATUS   text NOT NULL DEFAULT 'pending'
                          CHECK (CALLBACK_STATUS IN ('pending', 'sent', 'failed')), -- 'pending' = aún no se intentó o se está reintentando (ver JOB_CALLBACK_OUTBOX)
    CALLBACK_SENT_AT  timestamptz,               -- solo si CALLBACK_STATUS='sent'
    CALLBACK_ATTEMPTS smallint NOT NULL DEFAULT 0, -- total de intentos hasta resolverse (éxito o agotado)
    CALLBACK_ERROR    varchar(500),               -- motivo del fallo final — solo si CALLBACK_STATUS='failed'; nunca se expone al usuario
    CREATED_AT        timestamptz NOT NULL DEFAULT now(), -- momento de encolado
    UPDATED_AT        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IX_JOB_EXECUTION_JOB_STARTED ON JOB_EXECUTION(JOB_ID, STARTED_AT);
CREATE INDEX IX_JOB_EXECUTION_STATUS_ACTIVE ON JOB_EXECUTION(STATUS) WHERE STATUS IN ('queued', 'running');
CREATE INDEX IX_JOB_EXECUTION_SYSTEM ON JOB_EXECUTION(SYSTEM);
CREATE INDEX IX_JOB_EXECUTION_CALLBACK_FAILED ON JOB_EXECUTION(ID) WHERE CALLBACK_STATUS = 'failed'; -- panel de salud, D8

-- Cola de reintento del callback — SOLO contiene lo que está ACTIVAMENTE
-- programado para reintentarse; es deliberadamente angosta (sin PAYLOAD
-- ni nada de JOB_EXECUTION) porque ESTA sí se reescribe en cada
-- intento, y conviene que esa reescritura repetida toque una fila
-- pequeña, no la fila ancha de JOB_EXECUTION. Un worker toma lo vencido
-- (NEXT_RETRY_AT) con FOR UPDATE SKIP LOCKED; al resolverse —por éxito
-- o por agotar los intentos— escribe el resultado final en
-- JOB_EXECUTION (CALLBACK_STATUS/CALLBACK_SENT_AT/CALLBACK_ATTEMPTS/
-- CALLBACK_ERROR) y BORRA esta fila. Por eso no necesita un IS_EXHAUSTED
-- ni ningún status propio: si la fila existe, se sigue reintentando: si
-- ya no existe, el resultado (éxito o fallo definitivo) está en
-- JOB_EXECUTION.
CREATE TABLE JOB_CALLBACK_OUTBOX (
    JOB_EXECUTION_ID bigint PRIMARY KEY REFERENCES JOB_EXECUTION(ID), -- FK real, misma esquema
    ATTEMPTS         smallint NOT NULL DEFAULT 1,
    LAST_ERROR       varchar(500),            -- motivo del último fallo — uso interno/ops, nunca se expone al usuario; acotado para no guardar un stack trace completo por accidente
    NEXT_RETRY_AT    timestamptz NOT NULL,
    CREATED_AT       timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IX_JOB_CALLBACK_OUTBOX_RETRY ON JOB_CALLBACK_OUTBOX(NEXT_RETRY_AT);
