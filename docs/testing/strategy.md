# Estrategia de pruebas

> **Estado: borrador para CU-02.** Se completa a medida que se agregan casos de uso. Herramientas según [`tech-stack.md`](../tools/tech-stack.md); donde el stack no define algo, se marca *por definir*.

## Niveles

| Nivel | Qué verifica | Herramienta |
|-------|--------------|-------------|
| Unitaria | Validadores, normalizadores, reglas puras | `pytest` (backend), `vitest` (frontend) |
| Integración | Endpoint + base de datos real | `pytest` con PostgreSQL en contenedor |
| E2E | Flujo de pantalla a base de datos | *por definir* |

Calidad estática: `ruff`, `mypy`, `eslint` (INF-6, fuera de esta versión pero útil en local).

## Entorno de pruebas

- **Contenedores desechables** para PostgreSQL, MongoDB, SMTP de prueba y navegadores: imagen oficial con **versión fijada** (la del entorno objetivo, p. ej. `postgres:16`), `--rm`, puertos solo en `127.0.0.1`, datos en `tmpfs`, credenciales de prueba generadas al vuelo.
- **Sin red real:** fixtures HTML guardados, uno por estrategia de extracción y uno que las haga fallar todas, servidos por un servidor local.
- **Correos:** solo a un SMTP de prueba local; nunca a internet.
- **Reloj inyectable** para probar las ventanas horarias sin esperar al horario real.

## Cobertura por criterio

- Cada criterio de aceptación tiene **un** caso de prueba, y la relación vive en [`traceability.md`](traceability.md).
- Cada funcionalidad cubre el caso feliz y los bordes: vacío, duplicado, unicode, valores enormes, errores de red.
- Definition of Done: tests en verde, validación en dos capas, saneamiento (RNF-6), logs con `transactionId`.

## Estados de un caso

`Sin implementar` → `Escrito` → `Automatizado` → `Verde`.
