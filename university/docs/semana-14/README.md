# Semana 14 · Lógica de negocio y API

---

## Antes de programar

### ¿Sigue igual la matriz de la semana 13?

Sí, sin cambios de alcance:

- **RF-01 (registrar una alerta)** sigue con prioridad 1 y **RF-02 (consultar una alerta)**, con prioridad 2.
- Los RNF son los mismos: RNF-SEC-01, RNF-SEC-02, RNF-PERF-01, RNF-PERF-02 y RNF-MANT-01, con las mismas metas.

### ¿Se repitió la prueba de guardar y leer?

Sí. Se volvieron a correr las pruebas de integración de la semana 13 contra un PostgreSQL 16 nuevo y vacío, y pasaron todas: guardar, leer desde otra conexión, número inexistente e integridad.

### ¿Qué métodos necesita cada RF y qué servicio los usa?

| RF | Servicio (`service.py`) | Método del repositorio | Qué hace el método |
|---|---|---|---|
| RF-01 | `AlertService.create` | `create` | Guarda la alerta con sus páginas y correos, y devuelve su número |
| RF-02 | `AlertService.get_alert` | `get_alert_detail` | Lee la alerta, sus páginas activas y sus correos; si no existe, devuelve «no existe» |

RF-02 quedó documentado como historia de usuario en [US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario).

### ¿Quién implementa, quién prueba y quién revisa?

- **Implementa:** el agente `backend-developer` en `core-service` y el agente `frontend-developer` en `foundit-web-app`.
- **Prueba:** cada agente escribe y corre sus pruebas. Después, Yonko (el asistente principal) las vuelve a correr y prueba el recorrido en el navegador.
- **Revisa:** Yonko revisa cada cambio antes de proponer el commit, y una persona del equipo lo aprueba al mergear el PR.
- **Pendiente:** no se corrió una revisión de seguridad dedicada (agente `security-reviewer`). Los riesgos conocidos están anotados en los PR.

---

## Actividad 1 · Implementar los servicios

**Endpoint** (recibe la petición y delega) → **Servicio** (aplica las reglas) → **Repositorio** (guarda o lee) → **Base de datos**

El servicio no sabe nada de HTTP ni de la pantalla: recibe datos y devuelve un resultado o un error del negocio. Por eso se prueba solo.

### ¿Qué hace el servicio de cada RF?

| | RF-01 · Registrar una alerta | RF-02 · Consultar una alerta |
|---|---|---|
| **Servicio** | `AlertService.create` | `AlertService.get_alert` |
| **Entrada** | Modo (`url`), de 1 a 10 páginas, de 1 a 5 correos y una nota opcional | El número de la alerta |
| **Reglas o condiciones** | <ul><li>De 1 a 10 páginas y de 1 a 5 correos.</li><li>Solo el modo `url` está habilitado.</li><li>Las páginas se limpian y una repetida se guarda una sola vez.</li><li>Se bloquean las direcciones a la red interna, los puertos raros y las que llevan usuario y contraseña.</li><li>Los correos se pasan a minúsculas y uno repetido se guarda una sola vez.</li><li>La nota tiene como máximo 500 caracteres.</li></ul> | <ul><li>El número debe ser un entero entre 1 y 2147483647.</li><li>Solo se muestran las páginas activas.</li><li>Los correos se ocultan antes de devolverlos (`u***@example.com`).</li><li>No modifica nada.</li></ul> |
| **Método de repositorio** | `create` | `get_alert_detail`, con un máximo de 2 consultas a la base |
| **Resultado válido** | La alerta guardada, con su número, estado y páginas | Los datos de la alerta, con los correos ocultos |
| **Rechazo** | Datos inválidos: se explica qué campo y qué fila fallaron, y **no se llama a guardar** | La alerta no existe (`AlertNotFound`), o el número no es válido; en este caso, **ni siquiera se consulta la base** |
| **Estado** | ✅ Hecho | ✅ Hecho |

### ¿Quién confirma la operación y cómo se liberan las conexiones?

- **Quién confirma:** el repositorio guarda la alerta, sus páginas y sus correos en una sola transacción: o se guarda todo, o nada.
- **Cuándo se responde:** el sistema **solo responde «creada» después de que la base confirma** que guardó.
- **Conexiones:** al terminar, la conexión vuelve al grupo de conexiones, haya salido bien o mal.
- **Aviso al servicio de capturas:** después de guardar, el sistema avisa al servicio que programa las capturas de precios. Si ese aviso falla, la alerta **ya está guardada** y se reintenta después; no se deshace.

### ¿Qué pasa con un conflicto de unicidad?

La guía pide que un choque con una regla de «no repetido» de la base se convierta en un rechazo claro.

- **En nuestro caso no puede ocurrir:**
  - el servicio quita las páginas y los correos repetidos **antes** de guardar;
  - las reglas de la base solo prohíben repetir **dentro de la misma alerta**, y cada alerta es nueva, así que dos peticiones al mismo tiempo no pueden chocar.
- **Si aun así la base rechazara algo:** la API responde **500** con un mensaje genérico y lo registra en el servidor. Lo tratamos como un error del programa, no como un error del usuario.

---

## Actividad 2 · Contratos de la API

### ¿Cómo se pide cada RF y qué responde?

| | RF-01 · Registrar una alerta | RF-02 · Consultar una alerta |
|---|---|---|
| **Método y ruta** | `POST /api/alerts` | `GET /api/alerts/{alert_id}` |
| **Entrada** | JSON en el cuerpo:<ul><li>`mode`: texto, `url`; si falta, se asume `url`.</li><li>`urls`: lista de 1 a 10 direcciones `http` o `https`, de hasta 2.048 caracteres.</li><li>`emails`: lista de 1 a 5 correos.</li><li>`notes`: opcional, hasta 500 caracteres.</li></ul> | El número en la ruta, un entero de 1 a 2147483647. Sin cuerpo |
| **Si sale bien** | **201**: el número de la alerta, su estado, sus páginas y la fecha. **Nunca devuelve el correo** | **200**: la alerta, sus páginas activas y sus correos ocultos |
| **Si algo falla** | **422**: datos inválidos, con el campo y la fila exactos · **413**: petición demasiado grande · **500**: error interno, sin detalles técnicos | **404**: la alerta no existe · **422**: el número no es válido · **500**: error interno, sin detalles técnicos |
| **Servicio que invoca** | `AlertService.create` | `AlertService.get_alert` |

**Errores del usuario frente a errores internos:**

- Los errores esperados llevan un código claro, por ejemplo `alert_not_found`, `validation_error` o `url_host_not_allowed`.
- Un error interno siempre responde `internal_error` con un mensaje genérico. En el servidor solo se registra el tipo de error: nunca la consulta SQL ni el correo.

**Ejemplo de RF-01:**

```json
POST /api/alerts
{"mode": "url", "urls": ["https://example.com/producto/1"], "emails": ["usuario@example.com"]}

201 Created
{"id": 1, "status": "active", "urls": ["https://example.com/producto/1"], "created_at": "2026-11-24T14:22:36Z"}
```

**Ejemplo de RF-02** (respuestas reales del 25/11, con 1.000 alertas de prueba):

```json
GET /api/alerts/500

200 OK
{"id": 500, "status": "active",
 "urls": [{"id": 500, "url": "https://example.com/p/500/1", "domain": "example.com"},
          {"id": 1500, "url": "https://example.com/p/500/2", "domain": "example.com"}],
 "subscriptions": [{"email_masked": "u***@example.com", "status": "active"},
                   {"email_masked": "u***@example.com", "status": "active"}],
 "created_at": "2026-11-25T17:04:53.597559Z"}

GET /api/alerts/999999

404 Not Found
{"error": {"code": "alert_not_found", "message": "La alerta no existe.", "details": []}}

GET /api/alerts/abc

422 Unprocessable Entity
{"error": {"code": "validation_error", "message": "Hay datos inválidos en la solicitud.",
  "details": [{"field": "alert_id", "code": "invalid_type", "message": "…"}]}}
```

La tercera página de la alerta 500 estaba inactiva; por eso no aparece.

**Ejemplo de un error de RF-01.** Nuestro formato es un poco más detallado que el de la guía: en vez de `400` con `detail`, usa `422` e indica el campo y la fila exactos. Lo documentamos así a propósito, y la pantalla y las pruebas usan este mismo formato.

```json
{"error": {"code": "validation_error", "message": "Hay datos inválidos en la solicitud.",
  "details": [{"field": "urls", "index": 1, "code": "url_host_not_allowed",
               "message": "Esta dirección apunta a una red no permitida."}]}}
```

**Contrato de RF-02:** lo aprobó el usuario y está implementado y probado. Detalle en [US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario).

---

## Actividad 3 · Probar los dos RF

### ¿Qué se probó y qué pasó?

- **Estado inicial:** una base PostgreSQL 16 vacía, con las tablas creadas.
- **Datos de prueba:** páginas de `example.com` y el correo ficticio `usuario@example.com`.
- **Cómo:** pruebas automáticas que llaman a la API real (`TestClient`) contra la base real, más peticiones HTTP manuales con `curl`.

| RF | Prueba | Pasos | Esperado | Obtenido |
|---|---|---|---|---|
| RF-01 | Alerta válida | Enviar 1 página y 1 correo | 201, y la alerta guardada | ✅ 201 con el número 1. En la base, leída desde otra conexión: 1 alerta, 1 página y 1 correo |
| RF-01 | Página repetida | Enviar la misma página escrita de dos formas | Se guarda una sola vez | ✅ 201 y 1 sola página en la base |
| RF-01 | Dirección peligrosa | Página 2 = `http://localhost/x` | 422 y nada guardado | ✅ 422 con `url_host_not_allowed` en la fila 2. Tablas en 0 antes y después |
| RF-01 | Faltan datos | Enviar sin correos, o con 11 páginas | 422 y nada guardado | ✅ 422 con `emails_required` o `urls_too_many`. Tablas en 0 |
| RF-01 | La base falla a mitad del guardado | Forzar un error en el último paso (el correo) | Nada a medias y sin el correo en el error | ✅ 0 alertas, 0 páginas y 0 correos; el error no muestra el correo |
| RF-02 | Consultar la alerta creada | `GET` con el número obtenido al crear | 200 con los mismos datos, sin cambios en la base | ✅ 200 con los mismos datos. Una segunda consulta da lo mismo, y la base no cambió |
| RF-02 | Número que no existe | `GET /api/alerts/999999` | 404, y la API sigue respondiendo | ✅ 404 «La alerta no existe.». La consulta siguiente respondió 200 |
| RF-02 | Número inválido | `GET /api/alerts/abc`, `0` y `-1` | 422 sin error interno | ✅ 422 `validation_error`, sin consultar la base |

**Estado de `core-service`:** 196 pruebas automáticas pasan sin base de datos, y 227 en total cuando también corren contra PostgreSQL real. Las pruebas de estos casos están en:

- `tests/unit/test_api.py` y `tests/unit/test_get_alert.py`;
- `tests/integration/test_alerts_db.py` y `tests/integration/test_get_alert_db.py`.

**Para repetir una creación exitosa:** basta con volver a correr; la base desechable empieza vacía en cada ejecución.

---

## Actividad 4 · Verificar los RNF

### ¿Qué RNF se cumplieron?

| RNF | Qué se comprobó | Estado |
|---|---|---|
| RNF-SEC-01 · Seguridad / integridad | Las direcciones a la red interna, los puertos raros y las que llevan usuario y contraseña se rechazaron todas (100 %), sin guardar nada | ✅ Cumple |
| RNF-SEC-02 · Seguridad / confidencialidad | Se buscó el correo de prueba completo en los registros del servidor y en todas las respuestas. Apareció **0** veces. Las pruebas `test_us_07_06_ac12_no_email_in_logs` lo comprueban de forma automática | ✅ Cumple en RF-01 y RF-02 |
| RNF-PERF-01 · Eficiencia / tiempo | 20 altas HTTP seguidas, cada una con 10 páginas: entre 5,4 y 11,1 ms | ✅ Cumple (20 de 20 ≤ 1 s) |
| RNF-PERF-02 · Eficiencia / tiempo | 1.000 alertas sembradas y 20 consultas HTTP seguidas: entre 3,7 y 7,3 ms cada una | ✅ Cumple (20 de 20 ≤ 0,5 s) |
| RNF-MANT-01 · Mantenibilidad / capacidad para ser probado | La lógica se probó con un repositorio simulado, sin abrir ninguna conexión a la base | ✅ Cumple en RF-01 y RF-02 |

### ¿En qué entorno se midió la velocidad?

| Elemento | Valor |
|---|---|
| Equipo | Portátil Apple M3 Pro, 18 GB de memoria, macOS |
| Versiones | Python 3.12, PostgreSQL 16 en Docker |
| Ubicación | API y base en el mismo equipo (`127.0.0.1`); un solo cliente |
| Qué se mide | La respuesta HTTP completa, desde que `curl` envía hasta que recibe la respuesta (`time_total`) |
| Caché | Sin caché en la API. La primera petición de cada serie se descarta porque abre la conexión a la base (174 ms en RF-01) |
| Datos | RF-01: base vacía y 10 páginas por alerta · RF-02: 1.000 alertas de 3 páginas y 2 correos |

### ¿Cuánto tardó cada petición?

| # | RF-01 · Crear (código, ms) | RF-02 · Consultar (código, ms) |
|---|---|---|
| 1 | 201 · 11,1 | 200 · 7,3 |
| 2 | 201 · 10,6 | 200 · 6,1 |
| 3 | 201 · 9,9 | 200 · 4,8 |
| 4 | 201 · 8,4 | 200 · 4,1 |
| 5 | 201 · 7,0 | 200 · 5,8 |
| 6 | 201 · 5,9 | 200 · 4,4 |
| 7 | 201 · 5,5 | 200 · 5,6 |
| 8 | 201 · 6,6 | 200 · 5,1 |
| 9 | 201 · 6,1 | 200 · 4,7 |
| 10 | 201 · 6,6 | 200 · 4,4 |
| 11 | 201 · 5,4 | 200 · 5,0 |
| 12 | 201 · 5,9 | 200 · 4,4 |
| 13 | 201 · 6,8 | 200 · 4,2 |
| 14 | 201 · 5,9 | 200 · 4,1 |
| 15 | 201 · 7,2 | 200 · 3,9 |
| 16 | 201 · 6,1 | 200 · 4,0 |
| 17 | 201 · 7,8 | 200 · 3,9 |
| 18 | 201 · 6,2 | 200 · 3,7 |
| 19 | 201 · 6,9 | 200 · 3,9 |
| 20 | 201 · 5,5 | 200 · 4,1 |
| **Cumplen** | **20 de 20** (≤ 1.000 ms) | **20 de 20** (≤ 500 ms) |

**Límite de RNF-PERF-01:** la medición se hizo sin el servicio que programa las capturas.

- Hoy, al crear la alerta, el sistema también avisa a ese servicio.
- Si ese servicio está caído, la respuesta puede tardar unos **19 segundos**, y **no cumpliría** la meta.
- Proponemos que ese aviso se haga en segundo plano.

Esta prueba es de un solo cliente; no demuestra cómo se comporta con muchos usuarios a la vez.

### ¿Cómo se comprobó que la lógica se prueba sin la base real?

El repositorio real se cambia por uno simulado en memoria (`FakeRepository`), que cuenta las veces que lo llaman. Ninguna de estas pruebas abre una conexión:

| Caso | Prueba | Qué verifica |
|---|---|---|
| RF-01 válido | `test_tc_02_01_us_02_01_ac1_creates_201_with_agreed_contract` | 201 y una sola llamada a guardar |
| RF-01 rechazo | `test_us_02_01_ac3_eleven_urls_422_nothing_saved` | 422 y **ninguna** llamada a guardar |
| RF-02 existente | `test_us_07_06_ac14_service_returns_masked_view` | Devuelve la alerta con los correos ocultos y solo lee |
| RF-02 ausente | `test_us_07_06_ac14_missing_alert_raises_not_found` | Comunica «no existe» |
| RF-02 inválido | `test_us_07_06_ac7_invalid_id_is_422_and_never_reads` | 422 y **cero** lecturas |

---

## Matriz RF–RNF

| RF / RNF | Calidad ISO | Prueba y meta | Resultado y evidencia |
|---|---|---|---|
| RF-01 / RNF-SEC-01 | Seguridad / integridad | Direcciones peligrosas: 100 % rechazadas | ✅ Cumple · `tests/unit/test_urls.py` y `tests/unit/test_api.py` |
| RF-01, RF-02 / RNF-SEC-02 | Seguridad / confidencialidad | 0 correos completos | ✅ RF-01 y RF-02 · búsqueda en los registros del 24 y el 25/11 y pruebas `..._no_email_in_logs` |
| RF-01 / RNF-PERF-01 | Eficiencia / tiempo | 20 altas, cada una en ≤ 1 s | ✅ 20 de 20, máximo 11,1 ms · tabla de tiempos de esta semana (medición HTTP del 25/11) |
| RF-02 / RNF-PERF-02 | Eficiencia / tiempo | 20 consultas, cada una en ≤ 0,5 s | ✅ 20 de 20, máximo 7,3 ms · tabla de tiempos y `scripts/measure_get_alert.py` |
| RF-01, RF-02 / RNF-MANT-01 | Mantenibilidad / capacidad para ser probado | Pruebas sin la base real | ✅ RF-01 y RF-02 · las 5 pruebas de la tabla anterior, en `tests/unit` |

---

## ¿Cómo se ejecuta?

**Requisitos:** Python 3.12 con `uv`, y Docker con la imagen `postgres:16`.

1. Instalar dependencias:

   ```bash
   cd core-service && uv sync
   ```

2. Correr las pruebas sin base de datos:

   ```bash
   uv run pytest tests/unit
   ```

3. Levantar la base y cargar el esquema oficial: son los pasos 1 y 2 de [«¿Cómo se repite la demostración?»](../semana-15/README.md#cómo-se-repite-la-demostración) de la semana 15.

4. Levantar la API. Toma su configuración de las variables de entorno:

   ```bash
   uv run uvicorn core_service.main:create_app --factory --host 127.0.0.1 --port 8000
   ```

Variables que necesita (valores de muestra en `.env.example`, nunca reales):

| Variable | Para qué |
|---|---|
| `DATABASE_URL` | Conexión a PostgreSQL con el usuario `core_service` |
| `FIXED_USER_ID` | Usuario fijo de esta versión (no hay inicio de sesión) |
| `ALERT_CREATION_MODES` | Modos habilitados; en el prototipo, `url` |
| `CORS_ORIGINS` | Dirección de la pantalla: `http://127.0.0.1:5173` |
| `SCHEDULE_URL` y `CORE_RUN_COMPLETED_URL` | Opcionales; solo si se usa el servicio que programa las capturas |

- **URL base:** la API queda en `http://127.0.0.1:8000`, con su documentación en `/api/docs`.
- **Reiniciar los datos:** basta con detener el contenedor de la base, porque los datos se borran. Al levantarlo de nuevo, se vuelve a cargar el esquema.

## ¿Qué recibe la interfaz para la semana 15?

- **Contratos:** los de la actividad 2, para los dos RF.
- **Datos disponibles:** la base empieza vacía. La pantalla crea sus propias alertas con RF-01 y las consulta con RF-02. Para medir, se pueden sembrar 1.000 alertas.
- **Origen permitido para el navegador (CORS):** `http://127.0.0.1:5173`.
- **Pendiente para la semana 15:**
  - comprobar RNF-SEC-02 también en la pantalla;
  - comprobar RNF-SEC-01 desde la pantalla;
  - probar qué ve el usuario cuando la API está apagada.

---

## Checklist de entrega

| Criterio | Cumple | Evidencia |
|---|---|---|
| Los RF mantienen la prioridad y el alcance de la semana 13 | ✅ | «Antes de programar» |
| Ambos RF tienen servicio y endpoint | ✅ | Actividad 1 y contratos |
| Contratos con éxito, entrada inválida y errores | ✅ | Actividad 2 |
| Caso válido y rechazo o ausencia por RF | ✅ | Actividad 3 |
| Persistencia real y sin datos guardados de más | ✅ | Actividad 3: tablas en 0 tras cada rechazo |
| SQL en el repositorio y reglas en el servicio | ✅ | `adapters/sql_repository.py` y `service.py` |
| RF vinculados con RNF e ISO | ✅ | Matriz RF–RNF |
| RNF con medidas observadas | ✅ | Actividad 4: tabla de tiempos |
| Incumplimientos y pendientes señalados | ✅ | Límite de RNF-PERF-01 y pendientes de la semana 15 |
| Se puede repetir con este README | ✅ | «¿Cómo se ejecuta?» |

## Antes de cerrar

- **Demostración desde el cliente HTTP:** con `curl` o `/api/docs` se crea una alerta (201), se consulta con su número (200) y se pide un número que no existe (404).
- **Dónde está cada responsabilidad:**
  - el endpoint, en `api/routes.py`;
  - las reglas, en `service.py`;
  - el SQL, en `adapters/sql_repository.py`.
- **Qué RNF se verificaron:** los cinco cumplen sus metas. Crear y consultar tardan menos de 12 ms, muy por debajo de 1 s y 0,5 s.
- **Qué falta al conectar la pantalla:** comprobar que el correo tampoco aparece completo en la pantalla y probar qué pasa cuando la API está apagada.
