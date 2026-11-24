// =====================================================================
// notify · colección MongoDB (TTL 180 días)
// Base de datos propia de `notify` (rol `notify_service`). `core` NO se
// conecta aquí: pide el aviso por REST (DEC-10). La notificación vive en
// el esquema `notify` de PostgreSQL (notify/schema.sql); esta colección es
// solo el archivo de lo enviado (solo proyecto; utilidad en revisión, D18).
// =====================================================================

const zstd = { storageEngine: { wiredTiger: { configString: "block_compressor=zstd" } } };

// notification_log — sin HTML ni email (PII); _id = notification.id (notify).
db.createCollection("notification_log", zstd);
db.notification_log.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 180 });
