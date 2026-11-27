# Decisiones de arquitectura (ADR)

Formato en [`templates/adr.md`](../../templates/adr.md). Un ADR por decisión; el número no se reutiliza.

| ADR | Título | Estado |
|-----|--------|--------|
| [0001](0001-repo-and-service-structure.md) | Estructura de repos y servicios | ✅ Aceptada |
| [0002](0002-deployment-and-data-ownership.md) | Despliegue y propiedad de datos: principios fijos y combinaciones de proveedores a costo $0 | 📝 **Propuesta (borrador)** |
| [0003](0003-per-system-scope-in-auth.md) | Alcance por `system` en `auth` | ✅ Aceptada |
| [0004](0004-schedule-dispatches-work-to-scraper.md) | `schedule` envía el trabajo al scraper (HTTP asíncrono) con callback configurable; reemplaza el *pull* del ADR-0001 | ✅ Aceptada |
| [0005](0005-anomaly-detection-as-strategy.md) | La detección de caídas anómalas es una estrategia intercambiable (`price_anomaly`, sin tocar los chequeos) | ✅ Aceptada |

**Sobre el 0002:** se redactó como borrador el 2026-11-25 y se reescribió el 2026-11-26 por combinaciones de proveedores; sus condiciones de aceptación están en «Qué falta»; seguimiento en el pendiente A2 de [pendientes](../../00-context/pending.md).
