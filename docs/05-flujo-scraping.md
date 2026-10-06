# 05 · Flujo de scraping (corrida de una alerta)

> Consolidado con la [arquitectura](02-arquitectura.md), el [modelo de datos](03-modelo-datos.md) y los [requerimientos](deliverables/requerimientos.md). Cada alerta **activa** se ejecuta **2×/día** en ventanas horarias (04–06 / 18–20, env), en **background escalonado**. Todo lo de una corrida comparte un `transaction_id`.

## Tabla de contenido

- [Diagrama de secuencia](#diagrama-de-secuencia)
- [Máquina de estados del job (por sitio)](#máquina-de-estados-del-job-por-sitio)
- [La cascada de extracción (resumen)](#la-cascada-de-extracción-resumen)
- [Motor de decisión — "mejor precio móvil" (global)](#motor-de-decisión--mejor-precio-móvil-global)
- [Manejo de fallos y buenas prácticas](#manejo-de-fallos-y-buenas-prácticas)
- [Idempotencia y trazabilidad](#idempotencia-y-trazabilidad)
- [Qué se persiste y dónde](#qué-se-persiste-y-dónde)

## Diagrama de secuencia

```mermaid
sequenceDiagram
    autonumber
    participant SCH as ⏰ Scheduler
    participant Q as 📥 Cola (Redis/Arq)
    participant WK as ⚙️ Worker
    participant EXT as 🪜 Cascada extracción
    participant WEB as 🌍 Sitio
    participant PROC as 📐 Proc. (normaliza/convierte/valida)
    participant PG as 🐘 PostgreSQL
    participant MG as 🍃 MongoDB
    participant DEC as 🧠 Motor decisión
    participant NOT as 📣 Notificador

    SCH->>PG: Cargar alertas con status=active (ventana actual)
    loop por cada alerta (escalonada)
        SCH->>Q: Encolar corrida (transaction_id)
    end
    Q->>WK: Tomar corrida
    WK->>PG: INSERT run (status=running)
    loop por cada alert_url
        WK->>MG: job_state: queued/resolving_adapter… (con hora)
        WK->>EXT: extraer precio del sitio
        EXT->>WEB: fetch (robots.txt + rate limit)
        WEB-->>EXT: HTML / JSON
        alt precio obtenido
            EXT-->>PROC: dato crudo
            PROC->>PROC: normaliza · convierte USD→COP · valida · marca anómalo
            PROC->>PG: INSERT price_snapshot (append-only)
            WK->>MG: job_state: completed
        else falla toda la cascada (tras reintentos)
            WK->>MG: raw_capture (HTML crudo) + job_state: failed
            WK->>NOT: email al admin (construir adapter)
        end
    end
    WK->>DEC: evaluar "mejor precio móvil" (global de la alerta)
    alt nuevo mínimo global
        DEC->>PG: UPDATE alert.best_price_cop (+ url, fecha)
        DEC->>NOT: email a suscriptores (badge si anómalo)
        NOT->>MG: notification_log
    end
    WK->>MG: run_summary (ok/fallidos, duración)
    WK->>PG: UPDATE run (status=completed)
```

## Máquina de estados del job (por sitio)

> Cada transición se registra **con su hora** en MongoDB (`job_state`, SCR-16). Cuanto más granular, mejor — alimenta la vista de progreso en tiempo real (SCH-9).

```mermaid
stateDiagram-v2
    [*] --> queued
    queued --> resolving_adapter
    resolving_adapter --> downloading_http
    downloading_http --> extracting: precio en HTML/JSON-LD
    downloading_http --> playwright_render: requiere JS
    playwright_render --> intercept_xhr: precio por API interna
    playwright_render --> extracting
    intercept_xhr --> extracting
    extracting --> normalizing: precio hallado
    extracting --> retry: no se pudo
    retry --> downloading_http: espera 10-15 min (máx 3)
    retry --> failed: reintentos agotados
    normalizing --> converting_currency
    converting_currency --> validating
    validating --> persisting: válido (o anómalo marcado)
    validating --> failed: inválido (≤0 / HTML error)
    persisting --> analyzing
    analyzing --> completed
    failed --> notify_admin
    notify_admin --> [*]
    completed --> [*]
```

## La cascada de extracción (resumen)

El orden que sigue `EXT` por cada sitio (detalle en [doc 02](02-arquitectura.md#la-cascada-de-scraping-el-cerebro)):

```mermaid
graph LR
    A0{¿adapter<br/>guardado?} -->|sí| USE[usar adapter]
    A0 -->|no| C1[JSON-LD / og:price]
    C1 -->|falla| C2[microdata/regex]
    C2 -->|falla| C3[Playwright]
    C3 -->|falla| C4[interceptar XHR]
    C4 -->|falla| RT[reintentos máx 3]
    RT -->|agotados| ADM[email admin → construir adapter]
```

## Motor de decisión — "mejor precio móvil" (global)

```mermaid
graph TD
    S[Fin de corrida] --> MIN[Calcular mínimo de HOY<br/>entre TODOS los sitios · en COP]
    MIN --> C{¿mínimo_hoy < best_price_cop<br/>de la alerta?}
    C -->|sí| U[UPDATE best_price_cop + url + fecha]
    U --> AN{¿snapshot anómalo?}
    AN -->|sí| B[📧 Email con badge<br/>'validar manualmente']
    AN -->|no| E[📧 Email de novedad]
    C -->|no| X[No notificar]
    B & E --> L[notification_log]
```

> **Regla:** se mantiene un **mejor precio global** por alerta (running minimum). Solo se notifica cuando el mínimo del día **rompe** ese mejor precio, y ese valor pasa a ser el nuevo punto de comparación. La estrategia va detrás de un **patrón Strategy** (reemplazable).

## Manejo de fallos y buenas prácticas

| Situación | Estrategia |
|-----------|-----------|
| Timeout / error de red | Reintentos **controlados**: máx 3 (parametrizable), espera 10–15 min. |
| Falla toda la cascada | Guardar `raw_capture` + **email al admin** → construye adapter (se reutiliza) |
| Bloqueo / 403 / 429 / captcha | **No forzar.** Backoff, bajar frecuencia; respetar la [política legal](07-consideraciones-legales.md). |
| Precio inválido (≤0 / HTML error) | Descartar el snapshot (no contamina el historial). |
| **Desplome anómalo** | **NO se descarta:** se guarda y se **marca** (`is_anomalous`) → badge en el email. |
| Rate limiting | Delay por dominio (aiolimiter) + concurrencia limitada + `Crawl-delay`. |

## Idempotencia y trazabilidad

- El snapshot se inserta **solo si cambia** el precio/stock respecto al último (bloqueo de fila en `alert_url`); evita duplicados sin `capture_hash` (ver [doc 03](03-modelo-datos.md)).
- Snapshots **append-only**: el historial nunca se corrompe.
- Si la corrida se cae, se reintenta sin duplicar (los sitios ya completados no se reprocesan).
- Todo se correlaciona por `transaction_id` (PG ↔ MongoDB) y se observa vía OpenTelemetry/Sentry.

## Qué se persiste y dónde

| Momento | PostgreSQL | MongoDB |
|---------|-----------|---------|
| Inicio/fin de corrida | `run` (status) | `run_summary` |
| Cada etapa del job | — | `job_state` (con hora) |
| Precio capturado | `price_snapshot` (append-only) | — |
| Fallo total de un sitio | — | `raw_capture` |
| Notificación enviada | `notification` | `notification_log` |
| Tasa de cambio del día | — (se referencia en snapshot) | `exchange_rate` |
