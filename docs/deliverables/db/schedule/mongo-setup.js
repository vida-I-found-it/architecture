// =====================================================================
// schedule · colecciones MongoDB (TTL + compresión zstd)
// Base de datos propia de `schedule`, dueño EXCLUSIVO de esta base (rol
// `schedule_service`).
//
// Rediseño genérico (2026-10-01, resuelve D9): `job_state`, `run_summary`
// y `scrape_result` (con granularidad "por sitio", `alert_url_id`) y
// `raw_capture` (HTML crudo para el constructor de adapters) DEJARON DE
// EXISTIR aquí — eran detalle específico de scraping, y `schedule` ya no
// conoce ese dominio (JOB_EXECUTION es genérico, sin alert_url_id).
//
// En su lugar, UNA sola colección genérica: el resultado/detalle de
// CUALQUIER ejecución, con forma libre según el `execution_type` del job
// — opaca para `schedule`, igual que `payload` lo es en PostgreSQL.
//
// PENDIENTE (no resuelto aquí, ver docs/09-pendientes.md): el detalle
// específico de scraping que antes vivía en `job_state`/`raw_capture`/
// `scrape_result` (progreso por sitio, HTML crudo para adapters, precio
// extraído) necesita un nuevo dueño — candidato natural: la Mongo de
// `core`, que es quien de verdad conoce "sitios" y "adapters". No se
// decide en este cambio.
//
// Los TTL requieren un campo `createdAt` (Date) en cada documento; el
// servicio lo escribe al insertar.
// =====================================================================

const zstd = { storageEngine: { wiredTiger: { configString: "block_compressor=zstd" } } };

// job_execution_result — resultado/detalle de UNA corrida, forma libre
// según execution_type (p.ej. filas afectadas de un db_query, stdout de
// un script, resultado crudo de un scrape). TTL 90 días: una vez
// entregado por el callback, solo sirve para depurar entregas fallidas.
// _id = job_execution.transaction_id (UUID binario).
db.createCollection("job_execution_result", zstd);
db.job_execution_result.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 90 });
