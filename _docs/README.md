# _docs · Documentación del proyecto (docs-as-code)

> **Estado:** estructura piloto. Se trabaja **solo con la versión de `use-cases/`** (CU-02..CU-08, CU-10, CU-11). El original en `docs/` **no se modifica**: aquí viven **copias** organizadas por este marco. La carpeta `use-cases/` ya se migró aquí y se eliminó (sigue en el historial de git, commit `b1b0db5`).

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
| [`architecture/`](architecture/) | [Arquitectura de la versión](architecture/architecture.md), [general](architecture/general-architecture.md), [flujo de scraping](architecture/scraping-flow.md) y [`adr/`](architecture/adr/) | `architect`, `backend-developer` |
| [`data/`](data/) | [Modelo de datos](data/data-model.md) y [esquemas SQL/Mongo](data/db/) | `dba`, `backend-developer` |
| [`api/`](api/) | Contratos OpenAPI por pieza (pendiente) | `backend-developer`, `qa` |
| [`testing/`](testing/) | [Estrategia](testing/strategy.md), [casos de prueba](testing/test-cases/) y [trazabilidad](testing/traceability.md) | `qa` |
| [`guides/`](guides/) | Cómo se hace (setup local, correr pruebas, runbooks) | `devops` |
| [`tools/`](tools/) | [Stack tecnológico](tools/tech-stack.md) y convenciones | `devops` |
| [`templates/`](templates/) | Formato de [historia](templates/user-story.md), [caso de prueba](templates/test-case.md) y [ADR](templates/adr.md) | todos |

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
