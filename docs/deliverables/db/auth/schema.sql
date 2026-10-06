-- =====================================================================
-- AUTH · esquema `AUTH`
-- Se corre con el rol `AUTH_SERVICE` (provision-roles.sql), que es dueño
-- EXCLUSIVO de este esquema. Ningún otro rol/servicio tiene acceso.
-- `CORE`/`SCHEDULE`/`NOTIFY` referencian un APP_USER solo por `uuid` en
-- SU PROPIO esquema (p. ej. ALERT.CREATED_BY), sin FK real entre
-- esquemas — ver ../README.md y docs/03-modelo-datos.md.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS AUTH;
SET search_path TO AUTH;

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- A) Referencia (informativa, sin FK) -----------------------------------

CREATE TABLE GENDER (
    CODE    text PRIMARY KEY,   -- 'H', 'M', … código mínimo representativo
    NAME_ES text NOT NULL
);
INSERT INTO GENDER (CODE, NAME_ES) VALUES ('H', 'Hombre'), ('M', 'Mujer');

-- B) Seguridad y cuentas -------------------------------------------------

CREATE TABLE PERSON (
    ID         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    FIRST_NAME text NOT NULL,
    LAST_NAME  text NOT NULL,
    BIRTH_DATE date NOT NULL,
    GENDER     text REFERENCES GENDER(CODE), -- código informativo (opcional)
    PHONE      text,
    CREATED_AT timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ROLE (
    ID          smallint PRIMARY KEY,
    CODE        text UNIQUE NOT NULL,          -- admin | user
    NAME_ES     text NOT NULL,
    IS_ACTIVE   boolean NOT NULL DEFAULT true,
    DESCRIPTION text
);

CREATE TABLE PERMISSION (
    ID          smallint PRIMARY KEY,
    CODE        text UNIQUE NOT NULL,           -- p.ej. alert.create
    DESCRIPTION text
);

CREATE TABLE ROLE_PERMISSION (
    ROLE_ID       smallint NOT NULL REFERENCES ROLE(ID),
    PERMISSION_ID smallint NOT NULL REFERENCES PERMISSION(ID),
    PRIMARY KEY (ROLE_ID, PERMISSION_ID)
);

CREATE TABLE APP_USER (
    ID            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    PERSON_ID     uuid NOT NULL UNIQUE REFERENCES PERSON(ID), -- 1:1
    EMAIL         citext NOT NULL UNIQUE,        -- normalizado, case-insensitive
    PASSWORD_HASH text NOT NULL,                 -- argon2/bcrypt
    ROLE_ID       smallint NOT NULL REFERENCES ROLE(ID),
    IS_ACTIVE     boolean NOT NULL DEFAULT true,
    CREATED_AT    timestamptz NOT NULL DEFAULT now(),
    UPDATED_AT    timestamptz NOT NULL DEFAULT now()
);

-- Sistemas/apps que consumen `AUTH`/`NOTIFY` (aud=system en el JWT de
-- servicio). Diseño mínimo; detalle completo pendiente — doc 09, D1.
CREATE TABLE SYSTEM (
    CODE       text PRIMARY KEY,   -- p.ej. 'ifoundit'
    NAME       text NOT NULL,
    IS_ACTIVE  boolean NOT NULL DEFAULT true,
    CREATED_AT timestamptz NOT NULL DEFAULT now()
);
INSERT INTO SYSTEM (CODE, NAME) VALUES ('ifoundit', 'I Found It');

CREATE TABLE REFRESH_TOKEN (
    ID          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    USER_ID     uuid NOT NULL REFERENCES APP_USER(ID),
    FAMILY_ID   uuid NOT NULL,               -- cadena de rotación
    REPLACED_BY uuid,                        -- token que lo sustituyó (null si vigente)
    TOKEN_HASH  bytea NOT NULL UNIQUE,        -- SHA-256 (32 bytes)
    EXPIRES_AT  timestamptz NOT NULL,         -- ~7 días
    IS_REVOKED  boolean NOT NULL DEFAULT false, -- rotación/logout/reutilización detectada
    CREATED_AT  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IX_REFRESH_TOKEN_USER ON REFRESH_TOKEN(USER_ID);

CREATE TABLE PASSWORD_RESET (
    USER_ID      uuid PRIMARY KEY REFERENCES APP_USER(ID), -- 1 fila por usuario
    CODE_HASH    bytea NOT NULL,
    EXPIRES_AT   timestamptz NOT NULL,        -- 15 min
    IS_USED      boolean NOT NULL DEFAULT false,
    REQUESTED_AT timestamptz NOT NULL DEFAULT now() -- throttle 15 min
);

CREATE TABLE AUDIT_LOG (
    ID             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ACTOR_USER_ID  uuid NOT NULL REFERENCES APP_USER(ID),
    ACTION         text NOT NULL,
    ENTITY         text NOT NULL,
    ENTITY_ID      text NOT NULL,
    TRANSACTION_ID uuid,                      -- correlación con la solicitud/corrida (opcional)
    OCCURRED_AT    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IX_AUDIT_LOG_ACTOR ON AUDIT_LOG(ACTOR_USER_ID, OCCURRED_AT);

-- Seed de roles (AUTH-10). Solo 2 roles: toda funcionalidad exige usuario
-- registrado — se retiró el rol incógnito (2026-09-30).
INSERT INTO ROLE (ID, CODE, NAME_ES, IS_ACTIVE, DESCRIPTION) VALUES
    (1, 'admin', 'Administrador', true, 'Gestión completa del sistema'),
    (2, 'user',  'Usuario',       true, 'Crea/consulta alertas, se suscribe');
