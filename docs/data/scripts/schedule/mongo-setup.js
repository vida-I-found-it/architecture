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
// Para un `scrape`, el documento es el resultado COMPLETO del scraper
// para una URL (DEC-19); `core` guarda en alert_snapshot solo lo que
// consulta (DEC-29). Forma (DEC-32):
//   { _id: <transaction_id>, createdAt: Date, alert_url_id,
//     attempts: [ { attempt, scraper_id, status, error_code, strategy,
//                   started_at, duration_ms } ],   // $push por intento, máx. 4
//     data: { ...datos del intento final } }
// El estado final es el del último elemento de `attempts`; no se repite. Sigue sin hogar el HTML crudo para construir
// adapters (solo proyecto, ver ../../../00-context/pending.md, D15).
//
// Los TTL requieren un campo `createdAt` (Date) en cada documento; el
// servicio lo escribe al insertar.
// =====================================================================

const zstd = { storageEngine: { wiredTiger: { configString: "block_compressor=zstd" } } };

// job_execution_result — resultado/detalle de UNA corrida, forma libre
// según execution_type (p.ej. filas afectadas de un db_query, stdout de
// un script, resultado completo de un scrape). TTL 90 días: una vez
// entregado por el callback, solo sirve para depurar entregas fallidas.
// _id = job_execution.transaction_id (UUID binario).
db.createCollection("job_execution_result", zstd);
db.job_execution_result.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 90 });
