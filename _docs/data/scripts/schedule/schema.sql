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
--   JOB_CALLBACK_OUTBOX
--                      cola angosta de reintento del callback; el
--                      resultado final del callback queda en
--                      JOB_EXECUTION (CALLBACK_*).
-- El resultado de cada ejecución (ok/no_price/error, error_code, intentos)
-- NO se repite aquí (DEC-32): vive completo en la Mongo de `schedule`
-- (job_execution_result) y lo consultable en `core.alert_snapshot`. Aquí
-- basta el estado del motor: completed | failed.
-- =====================================================================

-- El esquema lo crea provision-roles.sql (el rol de servicio no tiene CREATE sobre la base).
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
    IS_ACTIVE        boolean NOT NULL DEFAULT true,
    CREATED_AT       timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT       timestamptz NOT NULL DEFAULT now()
);
INSERT INTO EXECUTION_TYPE (CODE, DESCRIPTION, REQUIRES_SANDBOX) VALUES
    ('scrape',   'Cascada de extracción de precios (conector interno de confianza)', false),
    ('db_query', 'Consulta/mantenimiento parametrizado sobre una base de datos',      false),
    ('http_call','Llamada HTTP saliente genérica',                                   false),
    ('script',   'Código serverless enviado por el cliente (Python/JavaScript)',     true),
    ('error_sweep', 'Barrido diario interno: reúne lo fallido y pide un correo a notify (DEC-26, DEC-32)', false);

-- La tarea CONFIGURADA. Sin alert_id, sin nada de core: PAYLOAD es la
-- única entrada de negocio, y es opaca para SCHEDULE.
CREATE TABLE JOB (
    ID              int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SYSTEM          text NOT NULL,            -- código de auth.system, sin FK — dueño del job (multi-proyecto)
    NAME            text NOT NULL,            -- etiqueta legible, p.ej. 'Limpieza semanal de snapshots'
    EXTERNAL_KEY    text,                     -- llave de idempotencia que manda quien crea el job, p.ej. 'alert-17' (DEC-15)
    EXECUTION_TYPE  text NOT NULL REFERENCES EXECUTION_TYPE(CODE), -- FK real, misma esquema
    PAYLOAD         jsonb NOT NULL DEFAULT '{}'::jsonb, -- entrada específica del execution_type; opaca aquí
    SCHEDULE_CRON   text NOT NULL,            -- expresión cron estándar (soportada nativa por APScheduler)
    IS_ACTIVE       boolean NOT NULL DEFAULT true,
    CALLBACK_TYPE   text CHECK (CALLBACK_TYPE IN ('api_call', 'python_script', 'topic_message')), -- SCH-13; NULL = sin callback por ejecución (p.ej. error_sweep, DEC-33)
    CALLBACK_CONFIG jsonb NOT NULL DEFAULT '{}'::jsonb, -- p.ej. {"url": "..."} si CALLBACK_TYPE='api_call'
    -- Aviso de «corrida terminada» (DEC-33): una llamada por corrida, no por
    -- ejecución, cuando TODAS las ejecuciones del RUN_ID quedaron resueltas y
    -- sus callbacks también. Genérico: lleva job_id y run_id. NULL = sin aviso.
    -- Destino validado contra la misma lista blanca de SCH-14.
    RUN_CALLBACK_CONFIG jsonb,                -- p.ej. {"url": ".../api/internal/run-completed"}
    NEXT_RUN_AT     timestamptz,
    LAST_RUN_AT     timestamptz,
    CREATED_AT      timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT      timestamptz NOT NULL DEFAULT now()
);
-- El scheduler toma lo vencido con FOR UPDATE SKIP LOCKED sobre este índice.
CREATE INDEX IX_JOB_NEXT_RUN ON JOB(NEXT_RUN_AT) WHERE IS_ACTIVE;
-- La misma llave nunca crea dos jobs: repetir la creación devuelve el existente.
CREATE UNIQUE INDEX UX_JOB_EXTERNAL_KEY ON JOB(SYSTEM, EXTERNAL_KEY) WHERE EXTERNAL_KEY IS NOT NULL;
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
-- Una corrida (un disparo del job): agrupa sus ejecuciones y lleva el
-- estado del aviso de «corrida terminada» (DEC-33). No guarda inicio ni fin:
-- se derivan de sus ejecuciones. Al resolver la última ejecución y su
-- callback, el worker bloquea esta fila (FOR UPDATE), confirma que no queda
-- nada pendiente y programa el aviso; un reenvío es inocuo (core vuelve a
-- analizar y da not_lower).
CREATE TABLE JOB_RUN (
    RUN_ID                uuid PRIMARY KEY,
    JOB_ID                int NOT NULL REFERENCES JOB(ID),
    RUN_CALLBACK_STATUS   text NOT NULL DEFAULT 'waiting'
                              CHECK (RUN_CALLBACK_STATUS IN ('none', 'waiting', 'pending', 'sent', 'failed')),
                              -- none: el job no tiene RUN_CALLBACK_CONFIG · waiting: faltan ejecuciones ·
                              -- pending: listo para enviar o reintentando · sent / failed: resuelto
    RUN_CALLBACK_ATTEMPTS smallint NOT NULL DEFAULT 0,
    RUN_CALLBACK_NEXT_AT  timestamptz,       -- cuándo toca enviar o reintentar; solo si 'pending'
    RUN_CALLBACK_SENT_AT  timestamptz,       -- solo si 'sent'
    CREATED_AT            timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT            timestamptz NOT NULL DEFAULT now(),
    CHECK ((RUN_CALLBACK_STATUS = 'pending') = (RUN_CALLBACK_NEXT_AT IS NOT NULL)),
    CHECK ((RUN_CALLBACK_STATUS = 'sent') = (RUN_CALLBACK_SENT_AT IS NOT NULL))
);
CREATE INDEX IX_JOB_RUN_CALLBACK_DUE ON JOB_RUN(RUN_CALLBACK_NEXT_AT) WHERE RUN_CALLBACK_STATUS = 'pending';
CREATE INDEX IX_JOB_RUN_JOB ON JOB_RUN(JOB_ID);

CREATE TABLE JOB_EXECUTION (
    ID                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    JOB_ID            int NOT NULL REFERENCES JOB(ID), -- FK real, misma esquema
    SYSTEM            text NOT NULL,             -- código de auth.system, sin FK (denormalizado, lookup rápido)
    TRANSACTION_ID    uuid NOT NULL UNIQUE,      -- trazabilidad end-to-end; _id del resultado en Mongo
    -- ADR-0004 (2026-11-12): una ejecución = UNA unidad de trabajo (p.ej. una URL).
    -- Un disparo del job crea N ejecuciones que comparten RUN_ID y se procesan
    -- de una en una, en orden de SEQ.
    RUN_ID            uuid NOT NULL REFERENCES JOB_RUN(RUN_ID), -- corrida a la que pertenece (id de correlación en los logs)
    SEQ               smallint NOT NULL CHECK (SEQ >= 1), -- orden dentro del disparo
    ITEM              jsonb NOT NULL DEFAULT '{}'::jsonb, -- la unidad de trabajo, opaca para schedule (p.ej. {"alert_url_id": 7, "url": "..."}); NO viaja al scraper; se reenvía tal cual al reintentar
    SCRAPER_ID        uuid,                      -- id que el scraper devolvió en el 202 del intento en curso; correlaciona su callback (cambia en cada reintento)
    ATTEMPT           smallint NOT NULL DEFAULT 1 CHECK (ATTEMPT >= 1), -- intento en curso: sube al reinyectar tras un `error`
    NEXT_ATTEMPT_AT   timestamptz,               -- cuándo toca enviar o reintentar; NULL si ya no hay nada pendiente
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
    UPDATED_AT        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT UQ_JOB_EXECUTION_RUN_SEQ UNIQUE (RUN_ID, SEQ)
);
-- Procesamiento SECUENCIAL: a lo más una ejecución en curso por disparo.
CREATE UNIQUE INDEX UX_JOB_EXECUTION_ONE_RUNNING_PER_RUN ON JOB_EXECUTION(RUN_ID) WHERE STATUS = 'running';
-- Correlación del callback: se busca por el scraper_id del intento en curso.
CREATE UNIQUE INDEX UX_JOB_EXECUTION_SCRAPER_ID ON JOB_EXECUTION(SCRAPER_ID) WHERE SCRAPER_ID IS NOT NULL;
-- El worker toma lo vencido (envíos y reintentos por `error`) con FOR UPDATE SKIP LOCKED.
CREATE INDEX IX_JOB_EXECUTION_DUE ON JOB_EXECUTION(NEXT_ATTEMPT_AT) WHERE STATUS = 'queued';
CREATE INDEX IX_JOB_EXECUTION_JOB_STARTED ON JOB_EXECUTION(JOB_ID, STARTED_AT);
CREATE INDEX IX_JOB_EXECUTION_STATUS_ACTIVE ON JOB_EXECUTION(STATUS) WHERE STATUS IN ('queued', 'running');
CREATE INDEX IX_JOB_EXECUTION_SYSTEM ON JOB_EXECUTION(SYSTEM);
CREATE INDEX IX_JOB_EXECUTION_CALLBACK_FAILED ON JOB_EXECUTION(ID) WHERE CALLBACK_STATUS = 'failed'; -- panel de salud, D8
-- Barrido diario (DEC-32): lo que quedó `failed` desde job.last_run_at del barrido.
CREATE INDEX IX_JOB_EXECUTION_FAILED_FINISHED ON JOB_EXECUTION(FINISHED_AT) WHERE STATUS = 'failed';

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
