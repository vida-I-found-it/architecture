-- =====================================================================
-- notify · esquema `notify` (reservado)
-- Se corre con el rol `notify_service` (provision-roles.sql), que es
-- dueño EXCLUSIVO de este esquema.
--
-- `notify` no tiene hoy ninguna tabla relacional: su único estado
-- persistente es `notification_log` en su propia base MongoDB (ver
-- ../notify/mongo-setup.js). Este esquema queda creado y aislado desde
-- ya para que, si `notify` necesita una tabla en el futuro (p. ej.
-- límites de envío por `system`), ya tenga su espacio propio y sus
-- permisos — sin tocar a `auth`/`core`/`schedule`.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS notify;
