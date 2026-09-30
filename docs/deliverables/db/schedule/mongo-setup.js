// =====================================================================
// schedule · colecciones MongoDB (TTL + compresión zstd)
// Base de datos propia de `schedule`, dueño EXCLUSIVO de esta base (rol
// `schedule_service`). `core` NO se conecta aquí: si necesita este
// detalle (p. ej. el panel "Detalle del scraper", SCR-17), lo pide por
// API a `schedule` — nunca lee esta Mongo directamente.
//
// `job_state`, `run_summary` y `raw_capture` se mudaron aquí desde la
// Mongo de `core` (2026-09-30): son detalle de una corrida (`run`), y
// `run` ya vivía en el esquema PostgreSQL de `schedule` — quedaban
// separadas de su propio dueño sin motivo. `scrape_result` es nueva:
// el scraper YA NO llama a `core` (SCR-20); entrega aquí su resultado,
// en la misma llamada de reporte de estado del run. `schedule` reenvía
// el precio a `core` llamando a la URL de `api_call` configurada al
// crear el job (SCH-14) — desacoplado, `schedule` no conoce a `core`.
//
// Los TTL requieren un campo `createdAt` (Date) en cada documento; el
// servicio lo escribe al insertar. `raw_capture` usa además el _id
// (ObjectId) para el tope de 3 por dominio, que aplica la app.
// =====================================================================

const zstd = { storageEngine: { wiredTiger: { configString: "block_compressor=zstd" } } };

// run_summary — TTL 90 días. _id = run.transaction_id (UUID binario).
db.createCollection("run_summary", zstd);
db.run_summary.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 90 });

// job_state — TTL 30 días. _id = { transaction_id, alert_url_id }.
db.createCollection("job_state", zstd);
db.job_state.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 30 });

// raw_capture — TTL 14 días + máx. 3 por dominio (lo aplica la app al insertar).
db.createCollection("raw_capture", zstd);
db.raw_capture.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 14 });
db.raw_capture.createIndex({ domain: 1, createdAt: -1 });

// scrape_result — resultado crudo del scraper (precio original, stock, título,
// metadata), comprimido; puente hacia `core` vía el callback de SCH-14, no
// vía lectura directa. TTL 30 días: una vez entregado a `core` (que lo
// persiste en `price_snapshot`), solo sirve para depurar entregas fallidas.
// _id = { transaction_id, alert_url_id } — igual que job_state.
db.createCollection("scrape_result", zstd);
db.scrape_result.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 30 });
db.scrape_result.createIndex({ delivered: 1 }); // localizar entregas pendientes/fallidas al callback
