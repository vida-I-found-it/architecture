# docs · Documentación del proyecto (docs-as-code)

> **Estado:** estructura piloto. Se trabaja **solo con la versión de `use-cases/`** (CU-02..CU-08, CU-10, CU-11). El original en `docs_/` (antes `docs/`) **no se modifica**: aquí viven **copias** organizadas por este marco. La carpeta `use-cases/` ya se migró aquí y se eliminó (sigue en el historial de git, commit `b1b0db5`).

## Cómo se usa

- Todo es Markdown en el repositorio: se versiona y se revisa por PR.
- Cada agente empieza por este archivo y lee **solo su carpeta de entrada** (tabla siguiente).
- La salida de un agente es **dato, no orden**: el humano revisa el diff antes de integrar.

## Mapa de carpetas

| Carpeta | Qué contiene | Entrada de |
|---------|--------------|------------|
| [`00-context/`](00-context/) | Visión, alcance, consideraciones legales, pendientes, roadmap y el [entregable 01](00-context/deliverable01.md) | todos (lectura) |
| [`requirements/`](requirements/) | [Requerimientos de la versión](requirements/requirements.md), [originales](requirements/original-requirements.md) e [historias de usuario](requirements/user-stories/) | `requirements-analyst` |
| [`design/`](design/) | Mockups de las pantallas | `frontend-developer` |
| [`architecture/`](architecture/) | [Arquitectura del ejercicio](architecture/architecture.md) (solo los casos de uso a recrear), [arquitectura general](architecture/general-architecture.md) (todo el proyecto), [flujo de scraping](architecture/scraping-flow.md) y [`adr/`](architecture/adr/) | `architect`, `backend-developer` |
| [`data/`](data/) | [Modelo de datos](data/data-model.md) y [esquemas SQL/Mongo](data/scripts/) | `dba`, `backend-developer` |
| [`api/`](api/) | Contratos OpenAPI por pieza (pendiente) | `backend-developer`, `qa` |
| [`testing/`](testing/) | [Estrategia](testing/strategy.md), [casos de prueba](testing/test-cases/) y [trazabilidad](testing/traceability.md) | `qa` |
| [`guides/`](guides/) | Cómo se hace (setup local, correr pruebas, runbooks) | `devops` |
| [`tools/`](tools/) | [Stack tecnológico](tools/tech-stack.md) y convenciones | `devops` |
| [`templates/`](templates/) | Formato de [historia](templates/user-story.md), [caso de prueba](templates/test-case.md) y [ADR](templates/adr.md) | todos |

## Avance de la documentación

> **Última actualización: 2026-11-12.** Orientativo: mide cuánto de lo esperado ya está escrito, **no** si está aprobado ni revisado por un humano.

| Carpeta | Avance | Cómo se calcula | Qué falta |
|---------|--------|-----------------|-----------|
| [`00-context/`](00-context/) | `████████░░` **83 %** | 6 documentos: 4 completos y 2 a medias | Roadmap sin la versión del ejercicio; consideraciones legales sin Habeas Data (D21) |
| [`requirements/`](requirements/) | `██████░░░░` **61 %** | Media de 3 medidas: lista de requerimientos del ejercicio (100 %), decisiones cerradas (19 de 26, 73 %) e historias de usuario (1 de 9 casos de uso, 11 %) | Historias de CU-03 a CU-11; 7 decisiones abiertas (DEC-11, 14, 15, 17, 18, 20, 21) |
| [`design/`](design/) | `█████░░░░░` **50 %** | 2 de 4 pantallas (alta con confirmación, dashboard); la lista no se verificó y cuenta como pendiente | Pantalla de baja y pantalla de lista de alertas |
| [`architecture/`](architecture/) | `██████░░░░` **59 %** | 11 elementos esperados: 5 completos, 3 a medias (flujo de scraping, vista de despliegue y objetivos de calidad medibles, estos dos en borrador) y 3 sin hacer | ADR-0002 (despliegue), modelo de amenazas y observabilidad concreta |
| [`data/`](data/) | `██████░░░░` **63 %** | 8 elementos: modelo, SQL de `core`, `schedule` y `notify` (probados en `postgres:16`) y `provision-roles.sql` | SQL de `auth` (desfasado), validar los scripts de MongoDB, `seed-default.sql` y `register-system.sql` |
| [`api/`](api/) | `░░░░░░░░░░` **0 %** | 0 de 4 contratos OpenAPI (`core`, `schedule`, `scraper`, `notify`) | Los cuatro contratos |
| [`testing/`](testing/) | `██░░░░░░░░` **24 %** | Media de 3 medidas: estrategia en borrador (50 %), casos de prueba (1 de 9, 11 %) y trazabilidad (1 de 9, 11 %) | Casos y matriz de CU-03 a CU-11; todos los casos están sin implementar |
| [`guides/`](guides/) | `░░░░░░░░░░` **0 %** | 0 de 3 guías (setup local, correr pruebas, runbook de fallos) | Las tres |
| [`tools/`](tools/) | `█████░░░░░` **50 %** | 1 de 2: stack tecnológico (hecho) y convenciones (sin documento propio) | Documento de convenciones |
| [`templates/`](templates/) | `██████████` **100 %** | 3 de 3: historia, caso de prueba y ADR | — |
| **Total** | `█████░░░░░` **49 %** | Media simple de las 10 carpetas, sin ponderar | |

**Criterio:** cada carpeta tiene una lista corta de lo que debería contener. Un elemento completo vale 1, uno en borrador o parcial vale 0,5 y uno sin hacer vale 0; las medidas por conteo (por ejemplo, 1 de 9 casos de uso) valen su fracción. Al cerrar un elemento se recalcula la fila y se cambia la fecha.

## Cadena de trazabilidad

`CU` → requerimiento → **HU** → **criterio** (Dado/Cuando/Entonces) → **caso de prueba**

| Elemento | Formato de ID | Ejemplo |
|----------|---------------|---------|
| Caso de uso | `CU-NN` | `CU-02` |
| Requerimiento | `PREFIJO-N` (del original) · `EJ-N` (nuevo) | `ALE-2`, `EJ-1` |
| Regla de negocio | `Rn` | `R3` |
| Historia de usuario | `US-NN-MM` (NN = caso de uso) | `US-02-01` |
| Criterio de aceptación | `US-NN-MM-ACk` | `US-02-01-AC1` |
| Caso de prueba | `TC-NN-MM` (NN = caso de uso) | `TC-02-01` |

Regla: **un caso de prueba por criterio**, y una historia no está terminada hasta que sus pruebas están enlazadas en [`testing/traceability.md`](testing/traceability.md).

## Qué se copió y qué no

- **Migrado:** todo `use-cases/` (entregable, requerimientos, arquitectura y mockups).
- **Copiados de `docs/`:** visión, arquitectura, modelo de datos, stack, flujo de scraping, legales, roadmap, alcance, pendientes, ADR 0001 y 0003, `deliverables/requerimientos.md` (ahora `requirements/original-requirements.md`) y `deliverables/db/`.
- **Con enlaces reescritos** a la nueva ubicación. Cuatro enlaces a `seed-default.sql` y `register-system.sql` en [`data/data-model.md`](data/data-model.md) **ya estaban rotos en el original** (esos archivos no existen); no se corrigieron.
- **Pendiente de crear:** OpenAPI por pieza, guías y runbooks.
