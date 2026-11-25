# ADR-0001 · Estructura de repos y servicios

- **Estado:** ✅ Aceptada · **actualizada 2026-09-29** (`schedule` pasa de "dentro de `core`" a **repo propio**)
- **Fecha:** 2026-09-27
- **Alcance:** qué piezas existen y qué es dueño de qué. **No** cubre *dónde* se despliega cada una (Cloudflare/GCP/Oracle, proveedor de BD, etc.) — eso queda deliberadamente **pendiente** en el [doc 09 · Pendientes](../09-pendientes.md) hasta cerrar la PoC de infraestructura.

## Tabla de contenido

- [Contexto](#contexto)
- [Decisión](#decisión)
- [Disparadores para separar más adelante (no se hacen ahora)](#disparadores-para-separar-más-adelante-no-se-hacen-ahora)
- [Consecuencias](#consecuencias)
- [Referencias](#referencias)

## Contexto

El proyecto arranca con presupuesto $0 y va a **crecer**: nuevos módulos en I Found It y, más adelante, **otros proyectos** que van a necesitar autenticación y notificaciones propias. Eso cambia el cálculo frente a un monolito modular único:

- **`auth` y `notify` se van a reutilizar fuera de este proyecto.** Conviene que sean piezas independientes desde ya, aunque hoy solo las use I Found It.
- **El scraper es la pieza más costosa en recursos** (Playwright/Chromium) y la que corre código sobre contenido de terceros no confiable — el mayor riesgo de seguridad (SSRF, XSS) y el candidato más claro a escalar con dinero cuando haga falta.
- El resto del dominio (alertas, scheduling, precios, decisión, comparador) cambia junto y comparte transacciones sobre la misma base — separarlo en más piezas solo agrega contratos sin beneficio hoy.

Se descartaron dos alternativas antes de llegar a esta:

| Alternativa | Por qué se descartó |
|---|---|
| Monolito modular único (`backend` con módulos internos) | No sirve para reutilizar `auth`/`notify` en otros proyectos sin extraerlos después |
| `core` + `api` + `workers` en 3 repos (propuesta inicial del [doc 04](../04-stack-tecnologico.md)) | Un paquete `core` compartido entre dos repos que ya viven pegados a la misma BD es papeleo de versión sin beneficio real |

## Decisión

**Seis repos**, cada uno dueño de sus propios datos, sin FK entre servicios:

| Repo | Contenido | Por qué es su propia pieza |
|---|---|---|
| **`frontend`** | React PWA (todas las rutas, incluidas las de admin, con carga diferida) | Un solo cliente para todos los roles; separar un frontend de admin solo si algún día tiene su propio ciclo de vida |
| **`auth`** | Identidad: `person`, `app_user`, `role`/`permission`, `refresh_token`, `password_reset`, tabla `system` (multi-proyecto) | Reutilizable por futuros proyectos; emite JWT (JWKS) que los demás validan localmente |
| **`core`** | Alertas, urls, tags, `price_snapshot`, suscripciones, registro de adapters, procesamiento y motor de decisión | Concentra el dominio de negocio que cambia junto y comparte transacciones sobre una misma BD |
| **`schedule`** | `schedule` (config por alerta) y `run` (corridas); expone la API de *pull* que consulta el scraper | Aislado del resto de `core` a nivel de esquema/rol de BD desde el diseño de los [scripts de base de datos](../deliverables/db/README.md); se formaliza aquí como repo propio |
| **`notify`** | Plantillas, envío, reintentos, outbox transaccional (`notification`), `notification_log` | Reutilizable por futuros proyectos; sin conocer el dominio de negocio de quien lo llama (`system`) |
| **`scraper`** | Fetch, cascada de extracción, Playwright | **Sin estado y sin acceso a BD**; recibe `job`, devuelve `resultado`. Aislado por ser el de mayor riesgo y mayor consumo de recursos |

> **Revisión del 2026-09-29:** la versión original de este ADR dejaba el scheduler **dentro de `core`** ("es 1:1 con la alerta, se crea en la misma transacción que la crea — ALE-8 — y separarlo no traía beneficio"). Al diseñar los scripts de base de datos se le dio a `schedule` su propio esquema y rol, sin FK hacia `core`; confirmado eso, se decidió llevar el mismo corte al repositorio, no solo a la base. La consecuencia que esto trae — ALE-8 deja de ser una sola transacción — se admite explícitamente abajo y queda registrada como pendiente en el [doc 09](../09-pendientes.md) (D7).
>
> **Revisión del 2026-09-30:** `notification` (el outbox transaccional que antes escribía el motor de decisión de `core` en su propia transacción) se movió al esquema/rol de `notify` — la notificación es el dato que `notify` posee de punta a punta, no `core`. Misma lógica que la revisión anterior, y misma consecuencia: `core` ya no puede insertar el outbox atómicamente junto con `best_price_*`; ahora le pasa los datos de la decisión a `notify` por HTTP, y falta el mecanismo de entrega confiable entre ambos — ver [doc 09](../09-pendientes.md) (D12).

## Disparadores para separar más adelante (no se hacen ahora)

- **`ai-service`** aparece cuando llegue la Fase 2 (Gemini/Claude), con sus propias dependencias y costos.
- Un paquete **`core` compartido** (librería, no servicio) solo si aparece un **tercer** consumidor del dominio; con dos no compensa.

## Consecuencias

- **Contratos entre servicios, no llamadas directas a la BD de otro.** `core` referencia usuarios de `auth` solo por `uuid`; `core` y `schedule` se referencian mutuamente (`alert_id`, `run_id`) solo por valor, sin FK — el nombre/estado se resuelve consultando al otro servicio, no por FK.
- **Auth entre servicios:** `auth` publica JWKS; `core`/`schedule`/`notify` validan el JWT localmente (sin llamar a `auth` en cada request).
- **El scraper es un cliente, no un servidor:** hace *pull* de trabajo sobre `schedule` y le reporta, en esa misma llamada, el avance y el resultado (precio extraído); el scraper **nunca llama a `core`** (SCR-20, 2026-09-30) — es `schedule` quien reenvía el precio a `core` vía el callback `api_call` configurado al crear el job (SCH-14). El scraper no necesita exponer ningún puerto.
- **ALE-8 ya no es una sola transacción:** crear la alerta (`core`) y darla de alta en el scheduler con su config por defecto (`schedule`) son ahora dos escrituras en dos servicios distintos. Falta definir el mecanismo que evite un alerta sin schedule (llamada síncrona con reintento, outbox/saga, o que `schedule` la cree perezosamente en su primer *pull*) — ver [doc 09](../09-pendientes.md), D7.
- **La decisión de "mejor precio" tampoco es ya una sola transacción con su aviso:** actualizar `best_price_*` (`core`) y encolar la notificación (`notify`, dueña de su propio outbox desde 2026-09-30) son dos escrituras en dos servicios distintos. Mismo tipo de ventana que ALE-8, ahora para el aviso — ver [doc 09](../09-pendientes.md), D12.
- Quedan más contratos que mantener versionados (OpenAPI de `auth`, `core` y `schedule`, API de `notify`, mensaje `job`/`resultado` del scraper) — detalle en el [doc 09 · Pendientes](../09-pendientes.md) (D4).
- Un repo plantilla para los servicios Python evita que los 4 backends se desalineen en CI/lint (doc 09, D5).

## Referencias

- [Doc 02 · Arquitectura](../02-arquitectura.md) — vista de despliegue (dirección de trabajo, aún sujeta a la PoC).
- [Doc 04 · Stack tecnológico](../04-stack-tecnologico.md) — sección "Organización polyrepo", a actualizar para reflejar esta decisión.
- [Doc 09 · Pendientes](../09-pendientes.md) — A2 (ADR de propiedad de datos y contratos) y todo el bloque C (infraestructura/despliegue) siguen abiertos.
