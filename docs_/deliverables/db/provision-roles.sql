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

CREATE SCHEMA IF NOT EXISTS AUTH;
CREATE SCHEMA IF NOT EXISTS CORE;
CREATE SCHEMA IF NOT EXISTS SCHEDULE;
CREATE SCHEMA IF NOT EXISTS NOTIFY;

-- Nadie ve nada por defecto en `public` (evita fugas entre esquemas).
REVOKE ALL ON SCHEMA PUBLIC FROM PUBLIC;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'auth_service') THEN
        EXECUTE format('CREATE ROLE AUTH_SERVICE LOGIN PASSWORD %L', :'auth_pw');
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'core_service') THEN
        EXECUTE format('CREATE ROLE CORE_SERVICE LOGIN PASSWORD %L', :'core_pw');
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'schedule_service') THEN
        EXECUTE format('CREATE ROLE SCHEDULE_SERVICE LOGIN PASSWORD %L', :'schedule_pw');
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'notify_service') THEN
        EXECUTE format('CREATE ROLE NOTIFY_SERVICE LOGIN PASSWORD %L', :'notify_pw');
    END IF;
END $$;

-- Cada rol es DUEÑO de su propio esquema (CREATE) — las tablas que cree
-- con ese rol quedan automáticamente suyas, sin GRANT tabla por tabla.
GRANT USAGE, CREATE ON SCHEMA AUTH     TO AUTH_SERVICE;
GRANT USAGE, CREATE ON SCHEMA CORE     TO CORE_SERVICE;
GRANT USAGE, CREATE ON SCHEMA SCHEDULE TO SCHEDULE_SERVICE;
GRANT USAGE, CREATE ON SCHEMA NOTIFY   TO NOTIFY_SERVICE;

-- Aislamiento explícito: cada rol queda SIN ningún permiso sobre los
-- esquemas de los demás (ya es el default; se deja explícito a propósito).
REVOKE ALL ON SCHEMA AUTH     FROM CORE_SERVICE, SCHEDULE_SERVICE, NOTIFY_SERVICE;
REVOKE ALL ON SCHEMA CORE     FROM AUTH_SERVICE, SCHEDULE_SERVICE, NOTIFY_SERVICE;
REVOKE ALL ON SCHEMA SCHEDULE FROM AUTH_SERVICE, CORE_SERVICE, NOTIFY_SERVICE;
REVOKE ALL ON SCHEMA NOTIFY   FROM AUTH_SERVICE, CORE_SERVICE, SCHEDULE_SERVICE;

-- A partir de aquí, cada schema.sql se corre CONECTADO CON SU PROPIO ROL
-- (AUTH_SERVICE, CORE_SERVICE, SCHEDULE_SERVICE, NOTIFY_SERVICE), nunca
-- con el superusuario — así ningún script puede tocar el esquema de otro
-- aunque lo intente por error.
