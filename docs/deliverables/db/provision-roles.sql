-- =====================================================================
-- provision-roles.sql · aprovisiona los 4 esquemas y un rol por esquema
-- con acceso EXCLUSIVO al suyo, sobre UNA sola base de datos.
--
-- Se ejecuta una única vez, como superusuario/administrador de la base,
-- ANTES de correr auth/schema.sql, core/schema.sql, schedule/schema.sql
-- y notify/schema.sql (esos cuatro son independientes entre sí y se
-- pueden correr en cualquier orden — no hay FK entre esquemas, ver
-- README.md).
--
-- Las contraseñas NUNCA van en este archivo: se pasan por variable al
-- invocar psql, p. ej.:
--   psql "$ADMIN_DATABASE_URL" \
--        -v auth_pw="'$AUTH_SERVICE_PASSWORD'" \
--        -v core_pw="'$CORE_SERVICE_PASSWORD'" \
--        -v schedule_pw="'$SCHEDULE_SERVICE_PASSWORD'" \
--        -v notify_pw="'$NOTIFY_SERVICE_PASSWORD'" \
--        -f provision-roles.sql
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS schedule;
CREATE SCHEMA IF NOT EXISTS notify;

-- Nadie ve nada por defecto en `public` (evita fugas entre esquemas).
REVOKE ALL ON SCHEMA public FROM PUBLIC;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'auth_service') THEN
        EXECUTE format('CREATE ROLE auth_service LOGIN PASSWORD %L', :'auth_pw');
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'core_service') THEN
        EXECUTE format('CREATE ROLE core_service LOGIN PASSWORD %L', :'core_pw');
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'schedule_service') THEN
        EXECUTE format('CREATE ROLE schedule_service LOGIN PASSWORD %L', :'schedule_pw');
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'notify_service') THEN
        EXECUTE format('CREATE ROLE notify_service LOGIN PASSWORD %L', :'notify_pw');
    END IF;
END $$;

-- Cada rol es DUEÑO de su propio esquema (CREATE) — las tablas que cree
-- con ese rol quedan automáticamente suyas, sin GRANT tabla por tabla.
GRANT USAGE, CREATE ON SCHEMA auth     TO auth_service;
GRANT USAGE, CREATE ON SCHEMA core     TO core_service;
GRANT USAGE, CREATE ON SCHEMA schedule TO schedule_service;
GRANT USAGE, CREATE ON SCHEMA notify   TO notify_service;

-- Aislamiento explícito: cada rol queda SIN ningún permiso sobre los
-- esquemas de los demás (ya es el default; se deja explícito a propósito).
REVOKE ALL ON SCHEMA auth     FROM core_service, schedule_service, notify_service;
REVOKE ALL ON SCHEMA core     FROM auth_service, schedule_service, notify_service;
REVOKE ALL ON SCHEMA schedule FROM auth_service, core_service, notify_service;
REVOKE ALL ON SCHEMA notify   FROM auth_service, core_service, schedule_service;

-- A partir de aquí, cada schema.sql se corre CONECTADO CON SU PROPIO ROL
-- (auth_service, core_service, schedule_service, notify_service), nunca
-- con el superusuario — así ningún script puede tocar el esquema de otro
-- aunque lo intente por error.
