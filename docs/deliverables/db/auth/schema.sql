-- =====================================================================
-- auth · esquema `auth`
-- Se corre con el rol `auth_service` (provision-roles.sql), que es dueño
-- EXCLUSIVO de este esquema. Ningún otro rol/servicio tiene acceso.
-- `core`/`schedule`/`notify` referencian un app_user solo por `uuid` en
-- SU PROPIO esquema (p. ej. alert.created_by), sin FK real entre
-- esquemas — ver ../README.md y docs/03-modelo-datos.md.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS auth;
SET search_path TO auth;

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- A) Referencia (informativa, sin FK) -----------------------------------

CREATE TABLE gender (
    code    text PRIMARY KEY,   -- 'H', 'M', … código mínimo representativo
    name_es text NOT NULL
);
INSERT INTO gender (code, name_es) VALUES ('H', 'Hombre'), ('M', 'Mujer');

-- B) Seguridad y cuentas -------------------------------------------------

CREATE TABLE person (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name text NOT NULL,
    last_name  text NOT NULL,
    birth_date date NOT NULL,
    gender     text REFERENCES gender(code), -- código informativo (opcional)
    phone      text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE role (
    id          smallint PRIMARY KEY,
    code        text UNIQUE NOT NULL,          -- admin | user | incognito
    name_es     text NOT NULL,
    is_active   boolean NOT NULL DEFAULT true,  -- incognito=false en Fase 1
    description text
);

CREATE TABLE permission (
    id          smallint PRIMARY KEY,
    code        text UNIQUE NOT NULL,           -- p.ej. alert.create
    description text
);

CREATE TABLE role_permission (
    role_id       smallint NOT NULL REFERENCES role(id),
    permission_id smallint NOT NULL REFERENCES permission(id),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE app_user (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id     uuid NOT NULL UNIQUE REFERENCES person(id), -- 1:1
    email         citext NOT NULL UNIQUE,        -- normalizado, case-insensitive
    password_hash text NOT NULL,                 -- argon2/bcrypt
    role_id       smallint NOT NULL REFERENCES role(id),
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Sistemas/apps que consumen `auth`/`notify` (aud=system en el JWT de
-- servicio). Diseño mínimo; detalle completo pendiente — doc 09, D1.
CREATE TABLE system (
    code       text PRIMARY KEY,   -- p.ej. 'ifoundit'
    name       text NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO system (code, name) VALUES ('ifoundit', 'I Found It');

CREATE TABLE refresh_token (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES app_user(id),
    family_id   uuid NOT NULL,               -- cadena de rotación
    replaced_by uuid,                        -- token que lo sustituyó (null si vigente)
    token_hash  bytea NOT NULL UNIQUE,        -- SHA-256 (32 bytes)
    expires_at  timestamptz NOT NULL,         -- ~7 días
    is_revoked  boolean NOT NULL DEFAULT false, -- rotación/logout/reutilización detectada
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_refresh_token_user ON refresh_token(user_id);

CREATE TABLE password_reset (
    user_id      uuid PRIMARY KEY REFERENCES app_user(id), -- 1 fila por usuario
    code_hash    bytea NOT NULL,
    expires_at   timestamptz NOT NULL,        -- 15 min
    is_used      boolean NOT NULL DEFAULT false,
    requested_at timestamptz NOT NULL DEFAULT now() -- throttle 15 min
);

CREATE TABLE audit_log (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id  uuid NOT NULL REFERENCES app_user(id),
    action         text NOT NULL,
    entity         text NOT NULL,
    entity_id      text NOT NULL,
    transaction_id uuid,                      -- correlación con la solicitud/corrida (opcional)
    occurred_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_audit_log_actor ON audit_log(actor_user_id, occurred_at);

-- Seed de roles (AUTH-10) ------------------------------------------------
INSERT INTO role (id, code, name_es, is_active, description) VALUES
    (1, 'admin',     'Administrador', true,  'Gestión completa del sistema'),
    (2, 'user',      'Usuario',       true,  'Crea/consulta alertas, se suscribe'),
    (3, 'incognito', 'Incógnito',     false, 'Definido pero inactivo en Fase 1');
