# Guías

> Pendiente. Aquí van los *cómo se hace*: levantar el entorno local, correr las pruebas, runbooks. Una guía por tarea, con pasos verificables.

## Guías de arranque por repositorio

Una guía por repo, para el agente o la persona que lo implementa. Cada una enlaza las historias y criterios que le tocan, sus endpoints, tablas, variables y contratos, y las preguntas abiertas que lo bloquean. Lo que la documentación no define aparece como «pendiente de decisión».

- [`core.md`](core.md): API pública, datos y análisis (FastAPI, PostgreSQL).
- [`schedule.md`](schedule.md): motor de disparo y entrega a `core` (FastAPI, PostgreSQL y MongoDB).
- [`scraper.md`](scraper.md): descarga y extracción de precio (sin base de datos).
- [`notify.md`](notify.md): avisos por correo con outbox (FastAPI, PostgreSQL y MongoDB).
- [`frontend.md`](frontend.md): interfaz web (React).

Las historias son la fuente de los criterios: [`requirements/user-stories`](../requirements/user-stories/README.md). Las guías no las copian.
