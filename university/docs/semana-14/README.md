# Semana 14 · Lógica de negocio y API

> Enunciado: [guía de la semana 14](../../sources/semana-14/README.md) · Continúa la [semana 13](../semana-13/README.md): mismos RF, mismas prioridades y mismos RNF.

**Integrantes:** _por completar por el equipo._

---

## Antes de programar

### ¿Sigue igual la matriz de la semana 13?

Sí. **RF-01 (registrar una alerta)** sigue con prioridad 1 y **RF-02 (consultar una alerta)** con prioridad 2. Los RNF son los mismos: RNF-SEC-01, RNF-SEC-02, RNF-PERF-01, RNF-PERF-02 y RNF-MANT-01.

### ¿Se repitió la prueba de guardar y leer?

Sí. Las pruebas automáticas contra un PostgreSQL 16 desechable pasan.

### ¿Qué necesita cada RF del repositorio?

- **RF-01:** guardar la alerta con sus páginas y correos.
- **RF-02:** leer la alerta con sus páginas y sus correos (documentado en [US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario)).

### ¿Quién implementa, quién prueba y quién revisa?

- **Implementa:** el agente `backend-developer`.
- **Prueba:** el agente `qa`.
- **Revisa la seguridad:** el agente `security-reviewer`.
- **Aprueba:** una persona del equipo.

Todos los integrantes deben poder explicar los dos RF.

---

## Actividad 1 · Implementar los servicios

El recorrido siempre es el mismo:

**Endpoint** (recibe la petición) → **Servicio** (aplica las reglas) → **Repositorio** (guarda o lee) → **Base de datos**

### ¿Qué hace el servicio de cada RF?

| | RF-01 · Registrar una alerta | RF-02 · Consultar una alerta |
|---|---|---|
| **Entrada** | Modo, páginas, correos y una nota opcional | El número de la alerta |
| **Reglas** | <ul><li>De 1 a 10 páginas y de 1 a 5 correos.</li><li>Las páginas se ordenan y limpian, y una repetida se guarda una sola vez.</li><li>Se bloquean las direcciones a la red interna.</li><li>La nota tiene como máximo 500 caracteres.</li></ul> | El número debe ser un entero positivo |
| **Repositorio** | Guardar | Leer |
| **Resultado válido** | La alerta guardada, con su número | Los datos de la alerta, con los correos ocultos |
| **Rechazo** | Datos inválidos: se explica qué campo falló y **no se guarda nada** | La alerta no existe, o el número no es válido |
| **Estado** | ✅ Hecho | ✅ Hecho (`AlertService.get_alert`) |

### ¿Quién confirma la operación?

El repositorio guarda todo en un solo paso. El sistema **solo responde «creada» después de que la base confirma** que guardó.

---

## Actividad 2 · Contratos de la API

### ¿Cómo se pide cada RF y qué responde?

| RF | Petición | Si sale bien | Si algo falla |
|---|---|---|---|
| RF-01 | `POST /api/alerts` con las páginas, los correos y la nota | **201**: el número de la alerta, su estado y sus páginas. Nunca devuelve el correo | **422**: datos inválidos, con el campo y la fila exactos · **413**: petición demasiado grande · **500**: error interno, sin detalles técnicos |
| RF-02 | `GET /api/alerts/{alert_id}` | **200**: la alerta, sus páginas activas y sus correos ocultos | **404**: la alerta no existe · **422**: el número no es válido |

**Ejemplo de RF-01:**

```json
POST /api/alerts
{"mode": "url", "urls": ["https://example.com/producto/1"], "emails": ["usuario@example.com"]}

201 Created
{"id": 1, "status": "active", "urls": ["https://example.com/producto/1"], "created_at": "2026-11-24T14:22:36Z"}
```

**Ejemplo de un error.** Nuestro formato es un poco más detallado que el de la guía: en vez de `400` con `detail`, usa `422` e indica el campo exacto.

```json
{"error": {"code": "validation_error", "message": "Hay datos inválidos en la solicitud.",
  "details": [{"field": "urls", "index": 1, "code": "url_host_not_allowed",
               "message": "Esta dirección apunta a una red no permitida."}]}}
```

**Estado de los contratos:**
- **RF-01:** el contrato es el **real**, implementado y probado.
- **RF-02:** el contrato lo aprobó el usuario y está implementado y probado. Detalle en [US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario).

---

## Actividad 3 · Probar los dos RF

### ¿Qué se probó y qué pasó?

**Estado inicial:** una base vacía. **Datos de prueba:** páginas de `example.com` y el correo ficticio `usuario@example.com`.

| RF | Prueba | Esperado | Resultado |
|---|---|---|---|
| RF-01 | Crear una alerta válida | 201 y la alerta guardada | ✅ |
| RF-01 | La misma página escrita de dos formas | Se guarda una sola vez | ✅ |
| RF-01 | Una página que apunta a `localhost` | 422 y nada guardado | ✅ |
| RF-01 | Faltan los correos | 422 y nada guardado | ✅ |
| RF-01 | La base falla a mitad del guardado | No queda nada a medias y el error no lleva el correo | ✅ |
| RF-02 | Consultar la alerta creada | 200 con los mismos datos | ✅ Sin cambios en la base |
| RF-02 | Consultar un número que no existe | 404 | ✅ «La alerta no existe.» |
| RF-02 | Consultar con un número inválido, como `abc` | 422 | ✅ Sin consultar la base |

**Estado de `core-service`:** 175 pruebas automáticas pasan sin base, y 25 más pasan contra PostgreSQL real.

---

## Actividad 4 · Verificar los RNF

### ¿Qué RNF se cumplieron?

| RNF | Qué se comprobó | Estado |
|---|---|---|
| RNF-SEC-01 · Seguridad / integridad | Las direcciones a la red interna se rechazaron todas, sin guardar nada | ✅ Cumple |
| RNF-SEC-02 · Seguridad / confidencialidad | El correo no apareció ni una vez completo en los registros ni en las respuestas | ✅ Cumple en RF-01 y RF-02 |
| RNF-PERF-01 · Eficiencia / tiempo | Crear una alerta en 1 s o menos | ⏳ Sin medir |
| RNF-PERF-02 · Eficiencia / tiempo | 1.000 alertas sembradas y 20 consultas HTTP seguidas: entre 3,7 y 7,3 ms cada una | ✅ Cumple (20 de 20 ≤ 0,5 s) |
| RNF-MANT-01 · Mantenibilidad / capacidad para ser probado | La lógica se probó con una base «de mentira», sin la real | ✅ Cumple en RF-01 y RF-02 |

**Riesgo para RNF-PERF-01.** Hoy, al crear la alerta, el sistema también avisa al servicio que programa las capturas. Si ese servicio está caído, la respuesta puede tardar unos **19 segundos**, y **no cumpliría** la meta. Proponemos que ese aviso se haga en segundo plano.

---

## Matriz RF–RNF

| RF / RNF | Calidad ISO | Prueba y meta | Resultado y evidencia |
|---|---|---|---|
| RF-01 / RNF-SEC-01 | Seguridad / integridad | Direcciones peligrosas: 100 % rechazadas | ✅ Cumple · pruebas `test_urls.py` y `test_api.py` |
| RF-01, RF-02 / RNF-SEC-02 | Seguridad / confidencialidad | 0 correos completos | ✅ RF-01 y RF-02 · búsqueda en los registros del 24 y el 25/11 |
| RF-01 / RNF-PERF-01 | Eficiencia / tiempo | 20 altas, cada una en ≤ 1 s | ⏳ No verificado |
| RF-02 / RNF-PERF-02 | Eficiencia / tiempo | 20 consultas, cada una en ≤ 0,5 s | ✅ 20 de 20, máximo 7,3 ms · `scripts/measure_get_alert.py` y medición HTTP del 25/11 |
| RF-01, RF-02 / RNF-MANT-01 | Mantenibilidad / capacidad para ser probado | Pruebas sin la base real | ✅ RF-01 y RF-02 · `tests/unit` |

---

## ¿Cómo se ejecuta?

1. Instalar dependencias:

   ```bash
   cd core-service && uv sync
   ```

2. Correr las pruebas sin base de datos:

   ```bash
   uv run pytest tests/unit
   ```

3. Levantar la API. Toma su configuración de las variables de entorno; `.env.example` trae valores de muestra:

   ```bash
   uv run uvicorn core_service.main:create_app --factory --host 127.0.0.1 --port 8000
   ```

La API queda en `http://127.0.0.1:8000`, con su documentación en `/api/docs`. Para empezar de cero basta con detener el contenedor de la base: los datos se borran.

## ¿Qué recibe la interfaz para la semana 15?

- **Contratos:** los de la actividad 2.
- **Origen permitido para el navegador (CORS):** `http://127.0.0.1:5173`.
- **Pendientes:**
  - ~~RF-02 completo~~: ✅ hecho.
  - Las dos mediciones de velocidad.

---

## Checklist de entrega

| Criterio | Cumple |
|---|---|
| Los RF mantienen la prioridad y el alcance de la semana 13 | ✅ |
| Ambos RF tienen servicio y endpoint | ✅ |
| Contratos con éxito, entrada inválida y errores | ✅ |
| Caso válido y rechazo o ausencia por RF | ✅ |
| Persistencia real y sin datos guardados de más | ✅ |
| SQL en el repositorio y reglas en el servicio | ✅ |
| RF vinculados con RNF e ISO | ✅ |
| RNF con medidas observadas | ⚠️ Todos menos RNF-PERF-01 (crear una alerta), que sigue sin medir |
| Incumplimientos y pendientes señalados | ✅ |
| Se puede repetir con este README | ✅ |

## Antes de cerrar

Los dos RF funcionan por la API y están probados, con sus rechazos y ausencias. Verificamos su seguridad, que la consulta es rápida y que la lógica se puede probar sin la base real. Falta medir la velocidad de crear una alerta (RNF-PERF-01).
