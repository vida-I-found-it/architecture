# Guía de arranque · `frontend`

> Para quien implementará este repositorio. Lo que la documentación no define figura como «pendiente de decisión» con enlace a la pregunta abierta. No inventes endpoints, campos ni variables.

## Repositorio

- **GitHub:** [vida-I-found-it/foundit-web-app](https://github.com/vida-I-found-it/foundit-web-app)
- **Local:** [`../foundit-web-app/`](../../../foundit-web-app/), en la carpeta que contiene este repositorio de arquitectura (un nivel arriba de su raíz).

> Estado al 2026-11-24: el repositorio ya tiene 32 archivos versionados, 19 de ellos en TypeScript. Revísalos antes de empezar y sigue su estructura.

## Qué es el servicio

Interfaz web de la versión: crear alertas, ver la lista y el dashboard de cada una, el histórico con gráfico, lanzar el análisis a mano y la página pública de baja. No tiene sesión ni usuarios: el usuario es fijo de la versión. No guarda datos; todo viene de `core`. El stack está en [`tech-stack.md`](../tools/tech-stack.md) (React, Vite, TypeScript, shadcn/ui, TanStack Query, Recharts, react-i18next, vitest). Los mockups están en [`design/mockups`](../design/mockups/alert-dashboard.html). Las decisiones de UI no se reabren aquí.

## Historias y criterios, en orden de implementación

Solo los criterios de presentación. El orden sigue las dependencias de las historias.

| Orden | Historia | Criterios de frontend | Nota |
|---|---|---|---|
| 1 | [CU-02](../requirements/user-stories/CU-02.md) · alta | US-02-01-AC1, AC2, AC13, AC14 (validación visible); US-02-03-AC1 a AC3 (modal); US-02-04-AC1 (selector «Modo»); US-02-05-AC1 (correo enmascarado) | Primera pantalla. El modal es de frontend. |
| 2 | [CU-03](../requirements/user-stories/CU-03.md) · aviso | US-03-05-AC1 a AC5 | Aviso tras crear. Sin *polling*. |
| 3 | [CU-07](../requirements/user-stories/CU-07.md) · lista y dashboard | US-07-01-AC1 a AC6; US-07-02-AC1, AC3, AC6, AC8, AC9, AC12, AC13; US-07-03-AC1 a AC7; US-07-04-AC1 a AC3, AC6; US-07-05-AC1; US-07-06-AC15 a AC24 (vista de detalle por número, prototipo) | Estados vacío, carga, error y marcas. |
| 4 | [CU-06](../requirements/user-stories/CU-06.md) · análisis manual | US-06-03-AC1 a AC4, AC6 | Botón «Analizar ahora» (rótulo propuesto, sin aprobar). |
| 5 | [CU-08](../requirements/user-stories/CU-08.md) · histórico | US-08-01-AC3 a AC5 (transformación de la serie); US-08-02-AC1 a AC8; US-08-03-AC1 a AC6; US-08-04-AC1 a AC5 | Gráfico escalonado con huecos y tabla equivalente. |
| 6 | [CU-11](../requirements/user-stories/CU-11.md) · página de baja | US-11-01-AC1 a AC6; US-11-02-AC6, AC7 | Sin petición que modifique al abrir la página. |

[CU-10](../requirements/user-stories/CU-10.md) no tiene pantalla. Solo necesita la ruta de la página de baja que abre el enlace del correo.

## Pantallas y rutas

- Pantallas: alta de alerta, lista de alertas, dashboard de la alerta (con el gráfico y la tabla de sitios), página de baja. Ver [FE-4](../requirements/requirements.md).
- **Rutas del navegador: pendiente de decisión** ([CU-07, pregunta 14](../requirements/user-stories/CU-07.md#preguntas-abiertas)). Propuesta sin aprobar: `/alerts` y `/alerts/:alertId`.
- **Ruta y forma del enlace de baja: pendiente** ([CU-11, pregunta 2](../requirements/user-stories/CU-11.md#preguntas-abiertas)). Propuesta sin aprobar: `/unsubscribe` con id y token en el fragmento (`#`).

## Endpoints

### Que consume (todos de `core`)

| Método y ruta | Historia | Estado |
|---|---|---|
| `POST /api/alerts` | US-02-01 | Cuerpo y respuesta pendientes ([CU-02, pregunta 4](../requirements/user-stories/CU-02.md#preguntas-abiertas)). |
| `GET /api/alert-modes` | US-02-04-AC4 | Formato pendiente. |
| `GET /api/alerts` | US-07-01 | Cuerpo pendiente ([CU-07, pregunta 1](../requirements/user-stories/CU-07.md#preguntas-abiertas)). |
| `GET /api/alerts/{alert_id}` | US-07-02 a US-07-05; US-07-06 (prototipo) | Cuerpo pendiente (CU-07, pregunta 1). |
| `GET /api/alerts/{alert_id}/price-history` | US-08-01, US-08-04 | Cuerpo pendiente ([CU-08, pregunta 1](../requirements/user-stories/CU-08.md#preguntas-abiertas)). |
| `POST /api/alerts/{alert_id}/analysis` | US-06-03 | Respuesta pendiente ([CU-06, pregunta 1](../requirements/user-stories/CU-06.md#preguntas-abiertas)). |
| `POST /api/subscriptions/{subscription_id}/unsubscribe` | US-11-02 | Dónde viaja el token: pendiente (CU-11, pregunta 2). |

El frontend no llama a `schedule`, `notify` ni `scraper`.

**Reglas de refresco:** solo al cargar o recargar. Sin `refetchInterval`, SSE ni WebSocket (DEC-31; US-07-02-AC12, US-08-04-AC4).

## Tablas y colecciones que posee

Ninguna. El frontend no tiene base de datos.

## Variables de entorno

**Ninguna nombrada en la documentación.** Pendiente de decisión:

- URL base de la API de `core`.
- URL base de la página de baja, que usa el enlace del correo ([CU-11, pregunta 2](../requirements/user-stories/CU-11.md#preguntas-abiertas)).

## Contratos con otros servicios

| Contrato | Estado |
|---|---|
| Lectura de alertas, detalle, histórico y análisis (`core`) | Rutas definidas; cuerpos **pendientes**. Propuesta: acordar primero el OpenAPI de `core` (D4) y trabajar contra un servidor simulado. |
| Mejor precio | Fuente **pendiente**: vista `v_alert_best_price` o último `alert_analysis` ([CU-07, pregunta 13](../requirements/user-stories/CU-07.md#preguntas-abiertas)). |
| Mejor precio por sitio | **Sin definir** ([CU-07, pregunta 17](../requirements/user-stories/CU-07.md#preguntas-abiertas)). |
| Formato del correo enmascarado | **Pendiente** ([CU-02, pregunta 3](../requirements/user-stories/CU-02.md#preguntas-abiertas)). |
| Mockups | El del dashboard contradice DEC-22 en la fila «Agotado» ([CU-07, pregunta 16](../requirements/user-stories/CU-07.md#preguntas-abiertas)) y no muestra el botón de análisis ([CU-06, pregunta 14](../requirements/user-stories/CU-06.md#preguntas-abiertas)). No modificar el mockup desde aquí. |

## Preguntas abiertas que bloquean este repositorio

- Cuerpos y formato de error de los endpoints de `core` (CU-07 p. 1; CU-08 p. 1; CU-06 p. 1).
- Rutas del navegador (CU-07 p. 14).
- Andamiaje i18n: estructura de claves, espacios de nombres y formato de fechas y moneda (CU-07 p. 15). **Definir antes de escribir textos.**
- Formato de precio y moneda (CU-07 p. 9).
- Accesibilidad: nivel WCAG y herramienta de revisión automática (CU-08 p. 8). La herramienta no está en el stack; instalarla requiere aprobación.
- Presentación de alertas o URLs inactivas (CU-07 pp. 6 y 7).
- Estado de la página de baja y texto mínimo (CU-11 p. 9).

## Seguridad

- Todo dato del sitio o del usuario se pinta como texto. No usar `dangerouslySetInnerHTML` (US-07-01-AC6, US-07-02-AC9, US-08-02-AC8).
- El frontend no oculta nada como seguridad: la autorización va en el backend.
- No registrar el token de baja en consola ni en analítica. Propuesta sin aprobar: `Referrer-Policy: no-referrer` en la página de baja (CU-11 p. 8).
- Los correos se muestran siempre enmascarados (US-07-05, US-11-04-AC1).
