# I Found It

Sistema **académico** que vigila el precio de productos en tiendas online, guarda su **historial por sitio** y avisa por **email a los suscritos** cuando aparece una bajada de precio real, apoyándose en datos y no en el marketing de la tienda.

> **Estado:** 📐 Fase de diseño / documentación (aún no se ha escrito código de la aplicación). Fase 0 casi cerrada; pendiente definir la topología de despliegue ([INF-15](docs/deliverables/requerimientos.md)).

## ¿Qué es esto?

Tres conceptos que no hay que confundir (detalle en [01 · Visión](docs/01-vision-objetivos.md)):

| Concepto | Qué es |
|----------|--------|
| 🔔 **Alerta** | Un proceso: scraping de los sitios que ofrecen el producto + notificación. Corre solo, **2 veces al día** en background. |
| 📧 **Suscripción** | Una persona suscrita a una alerta para recibir sus novedades por email. |
| 📈 **Histórico de precios** *(antes "consumo")* | Vista de la evolución del precio en el tiempo y entre sitios, para saber cuándo ofrece su mejor precio. |

**Modos de monitoreo:** por **URL directa** (Fase 1) y por **tema descubierto con IA** (Fase 2).

**Roles:** administrador (único que crea cuentas), usuario con cuenta y usuario incógnito (inactivo en Fase 1).

## Cómo funciona (Fase 1)

1. El usuario crea una **alerta** con una o varias URLs de producto (las alertas son inmutables; solo se pausan o reactivan).
2. Un scheduler encola corridas **2×/día**, escalonadas en ventanas horarias, y los workers hacen el scraping en background.
3. La extracción es genérica: **JSON-LD / schema.org + `og:price`**, con cascada HTTP → Playwright → IA solo si lo anterior falla.
4. Cada captura se guarda como snapshot histórico (moneda original + equivalente en COP).
5. Un motor de decisión de **"mejor precio móvil"** detecta cuándo se rompe el mínimo observado.
6. Se envía un **email** a los suscritos a esa alerta.

## Documentación

La documentación vive en [`docs/`](docs/) y está pensada para leerse en orden:

| # | Documento | Contenido |
|---|-----------|-----------|
| 01 | [Visión y objetivos](docs/01-vision-objetivos.md) | Problema, glosario, roles, módulos, no-objetivos |
| 02 | [Arquitectura](docs/02-arquitectura.md) | Componentes, diagramas y despliegue |
| 03 | [Modelo de datos](docs/03-modelo-datos.md) | Entidades, diagrama ER, historial de precios |
| 04 | [Stack tecnológico](docs/04-stack-tecnologico.md) | Tecnologías y por qué; organización polyrepo |
| 05 | [Flujo de scraping](docs/05-flujo-scraping.md) | Secuencia de una corrida de alerta |
| 06 | [Roadmap](docs/06-roadmap.md) | Fases e hitos |
| 07 | [Consideraciones legales y éticas](docs/07-consideraciones-legales.md) | robots.txt, ToS, rate limiting |
| 08 | [Preguntas de Alcance 1](docs/08-alcance-1-preguntas.md) | Decisiones que acotaron el MVP |
| — | [**Requerimientos Fase 1**](docs/deliverables/requerimientos.md) | Requerimientos con ID, prioridad, track y estado |

Las reglas para trabajar con IA en este proyecto están en [`CLAUDE.md`](CLAUDE.md) (se copia a cada repositorio).

## Agentes de Claude Code

Este repo trae agentes especializados en `.claude/agents/` (ficha completa y roster en [`CLAUDE.local.md`](CLAUDE.local.md)). No son un comando aparte: se piden en el chat y Claude Code los ejecuta como subagente, con su propio contexto, herramientas y modelo.

| Agente | Para qué | Cómo invocarlo |
|--------|----------|-----------------|
| **`arquitecto`** | Analiza un componente o una decisión y propone mejoras de arquitectura —más rápida, abierta, segura, flexible y confiable—, con lenguaje técnico y opinión propia. Generalista y **portable** a cualquier repo. | *"Usa el agente arquitecto para revisar/evaluar `<alcance concreto>`."* |
| `revisor-seguridad` | Busca brechas de seguridad en un diff o configuración (solo lectura). | *"Lanza revisor-seguridad sobre `<archivos/diff>`."* |
| `qa` | Escribe/ejecuta tests y valida criterios de aceptación. | *"Que qa valide `<requerimiento>`."* |

Con `arquitecto`, dale un alcance concreto (un componente, un ADR, una pregunta de [doc 09](docs/09-pendientes.md)) — no le pidas "revisa toda la arquitectura" de una vez. Propone con un ADR en estado **🟡 Propuesta** cuando amerita; nunca aplica un cambio a una decisión ya cerrada sin que el humano lo apruebe.

> Si acabas de crear o editar un agente, abre `/hooks` (o reinicia la sesión) para que Claude Code lo cargue.

## Decisiones vigentes

- **Backend:** Python 3.12+ · FastAPI · SQLAlchemy + Alembic · Playwright/httpx · Redis + Arq · APScheduler.
- **Datos:** PostgreSQL (+ JSONB) y MongoDB (estado de jobs, log de notificaciones, capturas).
- **Frontend:** React + Vite + TypeScript + shadcn/ui, en español con andamiaje i18n.
- **Organización:** **polyrepo**, contenedores con Docker Compose, portable a free tier (Oracle Cloud / GCP) sin lock-in.
- **Email:** SMTP propio con plantilla única.

> Si algo cambia, se actualiza aquí y en el doc correspondiente.

---
*Proyecto en construcción — la documentación evoluciona con cada nuevo requerimiento.*
