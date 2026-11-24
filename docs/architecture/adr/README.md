# Decisiones de arquitectura (ADR)

Formato en [`templates/adr.md`](../../templates/adr.md). Un ADR por decisión; el número no se reutiliza.

| ADR | Título | Estado |
|-----|--------|--------|
| [0001](0001-repo-and-service-structure.md) | Estructura de repos y servicios | ✅ Aceptada |
| 0002 | Despliegue y propiedad de datos (Cloudflare/GCP/Oracle, proveedor de BD, contratos entre servicios) | ⏳ **Reservado, aún no redactado** |
| [0003](0003-per-system-scope-in-auth.md) | Alcance por `system` en `auth` | ✅ Aceptada |
| [0004](0004-schedule-dispatches-work-to-scraper.md) | `schedule` envía el trabajo al scraper (HTTP asíncrono) con callback configurable; reemplaza el *pull* del ADR-0001 | ✅ Aceptada |
| [0005](0005-anomaly-detection-as-strategy.md) | La detección de caídas anómalas es una estrategia intercambiable (`price_anomaly`, sin tocar los chequeos) | ✅ Aceptada |

**Por qué falta el 0002:** no se descartó ni se perdió. Se reservó el número a propósito y no se redacta hasta cerrar B1, C1, C3 y C4; seguimiento en el pendiente A2 de [pendientes](../../00-context/pending.md). Verificado en el historial de git: nunca existió un archivo con ese número.
