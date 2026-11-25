-- =====================================================================
-- NOTIFY · esquema `NOTIFY`
-- Se corre con el rol `NOTIFY_SERVICE` (provision-roles.sql), que es
-- dueño EXCLUSIVO de este esquema. Un campo `*_ID`/`SYSTEM` hacia otro
-- esquema es un valor de solo referencia — SIN FK real entre esquemas;
-- la integridad la garantiza `NOTIFY` al escribir, no la base de datos.
-- Ver ../README.md y docs/03-modelo-datos.md.
--
-- Rediseño genérico (2026-10-0X): `NOTIFY` deja de conocer CUALQUIER
-- concepto de `core` (sin ALERT_ID, RUN_ID, TRIGGER_*) — mismo giro que
-- ya tomó `schedule` con JOB/JOB_EXECUTION (D9). Lo único que sabe de
-- "para qué es" este aviso es TRANSACTION_ID (correlación opaca) y
-- PAYLOAD (dato de negocio, opaco, interpretado solo por quien arma el
-- envío) — igual patrón que JOB.PAYLOAD en `schedule`.
--
-- Multicanal desde el modelo (aunque Fase 1 solo implementa email):
--   CHANNEL    catálogo ABIERTO (email | sms | whatsapp | call…), FK
--              real — agregar un canal nuevo es un INSERT, no migración
--   TEMPLATE   contenido versionado por canal (nunca se sobrescribe);
--              NOTIFICATION.TEMPLATE_ID fija la versión EXACTA usada
--
-- NOTIFICATION lleva su propio STATUS (2026-10-0X, reemplaza a
-- NOTIFICATION_SENT): antes había una tabla aparte solo para el log de
-- éxito, pero esa tabla NUNCA mutaba (una fila, escrita una sola vez) —
-- no había motivo de espacio/rendimiento para separarla, y mezclarla de
-- vuelta además deja el estado VISIBLE con un simple SELECT, sin join.
-- Lo que sí sigue aparte es NOTIFICATION_OUTBOX, porque esa tabla SÍ se
-- reescribe en cada reintento — separarla evita reescribir la fila
-- ancha de NOTIFICATION (con su PAYLOAD) en cada intento fallido. Ver
-- el comentario de NOTIFICATION_OUTBOX más abajo.
--
-- Cuatro tablas, cuatro responsabilidades, todas en el mismo esquema
-- (SÍ llevan FK real entre ellas, a diferencia de las referencias a
-- otros esquemas):
--   CHANNEL              catálogo de canales soportados
--   TEMPLATE             contenido versionado de cada canal
--   NOTIFICATION         la notificación, configurada Y resuelta: qué
--                        se debe enviar, con qué, y en qué quedó
--                        (pending | sent | failed)
--   NOTIFICATION_OUTBOX  cola de reintento ACTIVO — solo lo que se está
--                        reintentando ahora mismo, nada más
--
-- PAYLOAD vive en la fila de NOTIFICATION desde el momento en que se
-- crea (no solo tras un envío exitoso): así un reintento desde
-- NOTIFICATION_OUTBOX tiene exactamente los mismos datos que el primer
-- intento. `notification_log` (Mongo de `notify`) queda como posible
-- redundancia a revisar — ver docs/09-pendientes.md.
--
-- Amarrada a APP_USER_ID + SYSTEM, no a SUBSCRIPTION_ID: toda
-- funcionalidad exige usuario registrado (se retiró el rol incógnito),
-- así que `NOTIFY` no necesita conocer el concepto "subscription" de
-- `core` — queda genéricamente reutilizable por SYSTEM, igual que
-- `auth`/`schedule`.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS NOTIFY;
SET search_path TO NOTIFY;

-- Catálogo ABIERTO de canales, con FK real desde TEMPLATE/NOTIFICATION
-- (a diferencia de un CHECK): agregar un canal nuevo es un INSERT, no
-- una migración. Fase 1 solo usa 'email'; sms/whatsapp/call quedan
-- listos en el modelo para cuando entren (Fase 2+, ver doc06).
CREATE TABLE CHANNEL (
    CODE        text PRIMARY KEY,       -- 'email' | 'sms' | 'whatsapp' | 'call'…
    DESCRIPTION text NOT NULL,
    IS_ACTIVE   boolean NOT NULL DEFAULT true
);
INSERT INTO CHANNEL (CODE, DESCRIPTION) VALUES
    ('email', 'Correo electrónico — SMTP propio (Fase 1)');

-- Contenido versionado de un canal. Una fila por VERSIÓN: el contenido
-- nunca se sobrescribe (mismo patrón que CORE.SITE_ADAPTER.VERSION /
-- SCHEDULE.JOB_SCRIPT.VERSION) — así NOTIFICATION.TEMPLATE_ID siempre
-- apunta al contenido exacto que se usó, aunque la plantilla cambie
-- después. BODY lleva COMPRESSION lz4 (PostgreSQL 16): es el campo que
-- más puede pesar (HTML de email); TOAST ya lo comprimía solo con el
-- compresor por defecto, lz4 es más rápido para el mismo propósito.
CREATE TABLE TEMPLATE (
    ID         int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CODE       text NOT NULL,           -- identifica la plantilla lógica (ej. 'price-drop-email'); no es única sola, ver VERSION
    VERSION    smallint NOT NULL DEFAULT 1,
    CHANNEL_ID text NOT NULL REFERENCES CHANNEL(CODE), -- FK real, misma esquema
    SYSTEM     text,                    -- código de auth.system, sin FK; NULL = compartida entre proyectos
    SUBJECT    text,                    -- asunto — solo aplica a canales con asunto (email)
    BODY       text NOT NULL COMPRESSION lz4, -- huecos para variables: Jinja2 en email, texto pre-aprobado en WhatsApp, guion TTS en llamada
    IS_ACTIVE  boolean NOT NULL DEFAULT true, -- si es la versión vigente para usarse en NUEVOS envíos
    CREATED_AT timestamptz NOT NULL DEFAULT now(),
    UNIQUE (CODE, VERSION)
);
CREATE INDEX IX_TEMPLATE_ACTIVE ON TEMPLATE(CODE) WHERE IS_ACTIVE; -- lookup de "la versión vigente de esta plantilla"

-- La notificación: quien llama (cualquier SYSTEM) le pasa a `notify`
-- TRANSACTION_ID (correlación con lo que la originó), APP_USER_ID
-- (destinatario), CHANNEL_ID + DESTINATION (a dónde entregarla) y
-- TEMPLATE_ID + PAYLOAD (con qué contenido). Nada de esto es FK hacia
-- otro esquema salvo APP_USER_ID/CREATED_BY (valor, sin FK real).
-- STATUS/SENT_AT/PROVIDER/ATTEMPTS/LAST_ERROR se escriben UNA sola vez
-- al resolverse (éxito o fallo definitivo) — mientras está reintentando,
-- el detalle vivo vive en NOTIFICATION_OUTBOX, no aquí.
CREATE TABLE NOTIFICATION (
    ID             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- es el _id de notification_log en la Mongo de notify
    TRANSACTION_ID uuid NOT NULL,      -- correlación end-to-end con quien la originó — OPACA, no sabemos si es un job_execution u otra cosa
    SYSTEM         text NOT NULL,      -- código de auth.system, sin FK — dueño del aviso (multi-proyecto)
    APP_USER_ID    uuid NOT NULL,      -- id de auth.app_user, sin FK — destinatario (siempre registrado)
    CREATED_BY     uuid,               -- id de auth.app_user, sin FK — quién la creó a mano; NULL = creada automáticamente por el sistema que la originó
    CHANNEL_ID     text NOT NULL REFERENCES CHANNEL(CODE),   -- FK real, misma esquema
    DESTINATION    text NOT NULL,      -- email o teléfono E.164 — lo entrega quien llama a notify; notify no lo resuelve
    TEMPLATE_ID    int NOT NULL REFERENCES TEMPLATE(ID),     -- FK real, misma esquema — versión EXACTA usada
    PAYLOAD        jsonb NOT NULL DEFAULT '{}', -- TODO el dato de negocio del aviso (variables de plantilla + lo que el dominio de quien llama necesite) — OPACO para notify, igual que JOB.PAYLOAD en schedule
    STATUS         text NOT NULL DEFAULT 'pending'
                       CHECK (STATUS IN ('pending', 'sent', 'failed')), -- 'pending' = aún no se intentó o se está reintentando (ver NOTIFICATION_OUTBOX)
    SENT_AT        timestamptz,        -- solo si STATUS='sent'
    PROVIDER       text,               -- proveedor que logró la entrega — solo si STATUS='sent'; texto libre, sin catálogo normalizado todavía (ver docs/09-pendientes.md)
    ATTEMPTS       smallint NOT NULL DEFAULT 0, -- total de intentos hasta resolverse (éxito o agotado)
    LAST_ERROR     varchar(500),       -- motivo del fallo final — solo si STATUS='failed'; nunca se expone al usuario
    CREATED_AT     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (TRANSACTION_ID, APP_USER_ID, CHANNEL_ID) -- no duplica el aviso al mismo usuario/canal por la misma transacción
);
CREATE INDEX IX_NOTIFICATION_USER ON NOTIFICATION(APP_USER_ID);
CREATE INDEX IX_NOTIFICATION_SYSTEM ON NOTIFICATION(SYSTEM);
CREATE INDEX IX_NOTIFICATION_FAILED ON NOTIFICATION(ID) WHERE STATUS = 'failed'; -- ver notificaciones fallidas sin escanear todo

-- Cola de reintento — SOLO contiene lo que está ACTIVAMENTE programado
-- para reintentarse; es deliberadamente angosta (sin PAYLOAD ni nada de
-- NOTIFICATION) porque ESTA sí se reescribe en cada intento, y conviene
-- que esa reescritura repetida toque una fila pequeña, no la fila ancha
-- de NOTIFICATION. Un worker toma lo vencido (NEXT_RETRY_AT) con FOR
-- UPDATE SKIP LOCKED; al resolverse —por éxito o por agotar los
-- intentos— escribe el resultado final en NOTIFICATION
-- (STATUS/SENT_AT/PROVIDER/ATTEMPTS/LAST_ERROR) y BORRA esta fila. Por
-- eso no necesita un IS_EXHAUSTED ni ningún status propio: si la fila
-- existe, se sigue reintentando; si ya no existe, el resultado (éxito o
-- fallo definitivo) está en NOTIFICATION.STATUS.
CREATE TABLE NOTIFICATION_OUTBOX (
    NOTIFICATION_ID bigint PRIMARY KEY REFERENCES NOTIFICATION(ID), -- FK real, misma esquema
    ATTEMPTS        smallint NOT NULL DEFAULT 1,  -- intentos fallidos hasta ahora en este ciclo
    LAST_ERROR      varchar(500),         -- motivo del último fallo — uso interno/ops, nunca se expone al usuario; acotado para no guardar un stack trace completo por accidente
    PROVIDER        text,                 -- último proveedor intentado — texto libre
    NEXT_RETRY_AT   timestamptz NOT NULL,
    CREATED_AT      timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IX_NOTIFICATION_OUTBOX_RETRY ON NOTIFICATION_OUTBOX(NEXT_RETRY_AT);
