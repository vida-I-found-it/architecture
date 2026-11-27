# API

> Contratos disponibles:
> - [`core-dashboard.yaml`](core-dashboard.yaml): lecturas del dashboard y del histórico de `core` (CU-07, CU-08).
>
> Desde el [ADR-0006](../architecture/adr/0006-openapi-generated-from-code.md) los contratos **OpenAPI** se **generan desde el código** de cada pieza (`core`, `schedule`, `scraper`, `notify`) y se versionan en su repo; aquí no se escriben contratos nuevos. `core-dashboard.yaml` queda como referencia hasta que `core` genere el suyo. Antes del código, el contrato son los criterios de cada CU y sus DEC. Los 19 endpoints de la versión (15 de negocio y 4 de salud) están listados en [`architecture.md`](../architecture/architecture.md) y en [`requirements.md`](../requirements/requirements.md) (columna «API»).
