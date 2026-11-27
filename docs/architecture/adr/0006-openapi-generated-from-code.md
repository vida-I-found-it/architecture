# ADR 0006 · Los contratos OpenAPI se generan desde el código

- **Estado:** ✅ Aceptada · el usuario eligió generar los contratos desde el código el 2026-11-26 (revisión de CU-02, bloque C)
- **Fecha:** 2026-11-26
- **Requerimientos / casos de uso afectados:** todos los endpoints de `core`, `schedule`, `scraper` y `notify`; CU-02 a CU-11; pendiente D4

> **Ampliación (2026-11-26, [CU-03 D25](../../requirements/user-stories/CU-03.md#decisiones-aprobadas-2026-11-24)) · contratos entre servicios:**
> - El proveedor declara como modelo propio, con `extra="forbid"`, los datos que su base guarda como `jsonb` pero que otro servicio envía. En `schedule`, el `payload` de un job `scrape`: así aparece en su `openapi.json` y `oasdiff` detecta sus cambios. `schedule` sigue sin interpretar los datos de negocio fuera de ese modelo.
> - El consumidor guarda una **copia de versión fijada** del `openapi.json` del proveedor, anotando de qué versión sale, y sus pruebas validan contra ella lo que envía. Las pruebas no descargan nada de la red.
> - **Límite:** la copia no se actualiza sola; un cambio del proveedor no se ve en el consumidor hasta actualizarla. Se mitiga con `oasdiff` en el CI del proveedor y declarando el cambio en la sección «Impacto entre repos» del PR.

## Contexto

La arquitectura pide un contrato OpenAPI por pieza que expone endpoints ([`architecture.md`](../architecture.md), [entregable 1](../../00-context/deliverable01.md)). Hasta ahora se escribían a mano en `docs/api/` antes del código: existe [`core-dashboard.yaml`](../../api/core-dashboard.yaml) (CU-07, CU-08), pero `POST /api/alerts`, `GET /api/alert-modes` y las rutas internas no tienen contrato. Mantener un YAML a mano y, además, el código que lo implementa crea dos fuentes que se separan con el tiempo.

Todas las piezas con endpoints usan FastAPI, que construye el OpenAPI a partir de las rutas y de los modelos pydantic (`app.openapi()`).

## Decisión

1. **El código es la fuente del contrato.** Cada repo de servicio define rutas y modelos pydantic, y el OpenAPI se **genera** de ellos. No se escribe ni se edita OpenAPI a mano.
2. **El contrato se versiona en el repo del servicio.** CI exporta `openapi.json` y falla si el archivo versionado no coincide con el generado, así cualquier cambio de contrato aparece en el diff del PR.
3. **Cambios que rompen, detectados en CI** con `oasdiff` contra el contrato de `main` (pendiente D4). Un cambio que rompe se declara en el PR, en la sección «Impacto entre repos».
4. **El frontend genera su cliente** TypeScript desde ese `openapi.json` con `openapi-typescript` (pendiente D4), en lugar de escribir los tipos a mano.
5. **Antes de que exista el código**, el contrato acordado son los criterios de cada CU y sus decisiones (p. ej. [DEC-34](../../requirements/requirements.md) para el alta). Para que el frontend no espere al backend, `core` arranca cada historia con sus modelos y rutas esqueleto (respuesta `501`), lo que ya produce el OpenAPI.
6. **`docs/api/` deja de recibir contratos nuevos.** `core-dashboard.yaml` queda como referencia de lo acordado para CU-07 y CU-08 hasta que `core` genere el suyo; entonces se reemplaza por un enlace al contrato generado.

## Alternativas descartadas

| Alternativa | Por qué no |
|-------------|------------|
| Contrato primero, a mano en `docs/api/` | Dos fuentes (YAML y código) que se separan; hay que revisar a mano que coincidan |
| Contrato a mano y generar el código desde él | Los generadores de servidor para FastAPI producen código que luego se edita, y se vuelve a tener dos fuentes |
| Sin contrato versionado (solo `/docs` en vivo) | No se ven los cambios en el PR ni se pueden detectar cambios que rompen en CI |

## Consecuencias

- **Positivas:** una sola fuente; el contrato nunca está desactualizado respecto al código; el cliente del frontend sale tipado; los cambios que rompen se detectan en CI.
- **Negativas / costo:** el frontend no puede empezar contra un contrato hasta que `core` tenga al menos los modelos esqueleto; el OpenAPI generado depende de que los modelos pydantic estén bien escritos (nombres, descripciones, ejemplos).
- **Riesgos y cómo se mitigan:**
  - Un modelo sin `extra="forbid"` acepta campos de más sin que el contrato lo diga: se exige `extra="forbid"` en los modelos de entrada (CU-02 rechaza `created_by`).
  - Las respuestas de error de validación de FastAPI por defecto (`422` con `input`) repiten el valor enviado y no siguen el formato común: se reemplaza el manejador para usar `{"error":{"code","message","details"}}` sin el valor (CU-02, pregunta 16), y el modelo de error se declara en el OpenAPI.
  - 🔒 En producción, `/docs` y `/openapi.json` no deben quedar públicos sin necesidad: se decide por pieza al desplegar.
