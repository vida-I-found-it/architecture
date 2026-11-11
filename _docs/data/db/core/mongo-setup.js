// =====================================================================
// core · colecciones MongoDB (solo consulta, TTL + compresión zstd)
// Base de datos propia de `core`, dueño EXCLUSIVO de esta base (rol
// `core_service`). MongoDB no tiene "esquemas" como PostgreSQL: aquí el
// aislamiento es una BASE separada por completo.
//
// `job_state`/`run_summary`/`raw_capture` YA NO viven aquí: se mudaron
// a la Mongo de `schedule` (2026-09-30, ver ../schedule/mongo-setup.js)
// porque son detalle de una corrida (`run`), y `run` ya vivía en el
// esquema de `schedule`. `core` solo conserva `exchange_rate`, que es
// suya (se referencia desde `price_snapshot.exchange_rate_date`).
// =====================================================================

const zstd = { storageEngine: { wiredTiger: { configString: "block_compressor=zstd" } } };

// exchange_rate — sin TTL (volumen ínfimo, ~1 doc/día).
db.createCollection("exchange_rate", zstd);
db.exchange_rate.createIndex({ date: 1, pair: 1 }, { unique: true });
