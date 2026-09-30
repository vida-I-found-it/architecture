-- =====================================================================
-- schedule · esquema `schedule`
-- Se corre con el rol `schedule_service` (provision-roles.sql), que es
-- dueño EXCLUSIVO de este esquema. `alert_id` es un `int` de solo valor
-- hacia core.alert — SIN FK real entre esquemas (mismo tratamiento que
-- `created_by` hacia auth.app_user). La integridad la garantiza quien
-- escribe, no la base de datos — ver ../README.md.
--
-- `schedule` es repo/servicio PROPIO (ADR-0001 actualizado el
-- 2026-09-29). `system` identifica qué sistema/app es dueño del job
-- (mismo código que auth.system, sin FK) — igual que auth/notify,
-- `schedule` está pensado para que otros proyectos lo reutilicen con
-- sus propios jobs, no solo I Found It.
--
-- Pendiente (docs/09-pendientes.md): estas tablas siguen con la forma
-- "un schedule por alerta" del diseño original; el diseño más genérico
-- de API de jobs (crear/consultar/actualizar/eliminar, con acción
-- api_call/python_script/topic_message — ver doc 02) todavía no se
-- refleja en este esquema físico.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS schedule;
SET search_path TO schedule;

CREATE TABLE schedule (
    id           int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    system       text NOT NULL,           -- código de auth.system, sin FK — dueño del job
    alert_id     int NOT NULL,            -- id de core.alert, sin FK (uso específico de 'ifoundit')
    runs_per_day smallint NOT NULL DEFAULT 2 CHECK (runs_per_day BETWEEN 1 AND 2), -- SCH-6
    windows      jsonb NOT NULL,          -- p.ej. [["04:00","06:00"],["18:00","20:00"]]
    is_active    boolean NOT NULL DEFAULT true,
    next_run_at  timestamptz,
    last_run_at  timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (system, alert_id)
);
-- El scheduler toma lo vencido con FOR UPDATE SKIP LOCKED sobre este índice.
CREATE INDEX ix_schedule_next_run ON schedule(next_run_at) WHERE is_active;
CREATE INDEX ix_schedule_system ON schedule(system); -- toda consulta multi-proyecto filtra primero por system

CREATE TABLE run (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    system         text NOT NULL,         -- código de auth.system, sin FK
    alert_id       int NOT NULL,          -- id de core.alert, sin FK
    schedule_id    int NOT NULL REFERENCES schedule(id), -- FK dentro del mismo esquema, sí aplica
    transaction_id uuid NOT NULL UNIQUE,  -- también _id de run_summary (Mongo, esquema core)
    status         text NOT NULL DEFAULT 'queued'
                       CHECK (status IN ('queued', 'running', 'completed', 'failed')),
    started_at     timestamptz,
    finished_at    timestamptz,
    total_sites    smallint,
    sites_ok       smallint,
    sites_failed   smallint,
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_run_alert_started ON run(alert_id, started_at);
CREATE INDEX ix_run_status_active ON run(status) WHERE status IN ('queued', 'running');
CREATE INDEX ix_run_system ON run(system);
