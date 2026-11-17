// =====================================================================
// notify · colección MongoDB (TTL 180 días)
// Base de datos propia de `notify` (rol `notify_service`). `core` NO se
// conecta aquí: solo le pasa `notification.id` al pedir el envío
// (mecanismo exacto pendiente — ver docs/deliverables/db/README.md).
// El esquema `notify` en PostgreSQL (notify/schema.sql) hoy está vacío;
// este es el único estado persistente real de `notify`.
// =====================================================================

const zstd = { storageEngine: { wiredTiger: { configString: "block_compressor=zstd" } } };

// notification_log — sin HTML ni email (PII); _id = notification.id (core).
db.createCollection("notification_log", zstd);
db.notification_log.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 180 });
