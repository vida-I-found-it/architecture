# Semana 15 · Interfaz e integración

## Los dos RF de esta entrega

| Prioridad | RF | Por qué en ese orden |
|---|---|---|
| 1 | **RF-01 · Registrar una alerta** ([CU-02](../../../docs/requirements/user-stories/CU-02.md)) | Es la base de todo y la operación más exigente |
| 2 | **RF-02 · Consultar una alerta** ([US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario)) | Necesita una alerta creada con RF-01 |

**RNF asociados:** RNF-SEC-01, RNF-SEC-02, RNF-PERF-01, RNF-PERF-02 y RNF-MANT-01 (ver la [matriz de la actividad 4](#actividad-4--cerrar-la-verificación-de-los-rnf)).

---

## Antes de construir la interfaz

### ¿Funcionan los endpoints sin la pantalla?

Sí. Antes de conectar la pantalla se probaron con `curl` y con `/api/docs`:

- `POST /api/alerts` (RF-01) respondió 201 o 422 según el caso; el 413 lo cubren las pruebas automáticas.
- `GET /api/alerts/{alert_id}` (RF-02) respondió 200, 404 y 422.

No hubo fallos del backend que corregir antes de seguir.

### ¿Cuáles son los contratos que usa la pantalla?

Los de la [semana 14](../semana-14/README.md#actividad-2--contratos-de-la-api), sin cambios. La pantalla envía los nombres tal cual (`mode`, `urls`, `emails`, `notes`) y lee los errores con el formato `{"error": {"code", "message", "details"}}`.

### ¿Cómo se arranca todo y qué datos hay al inicio?

| Pieza | Dirección | Orden de arranque |
|---|---|---|
| Base (PostgreSQL 16) | `127.0.0.1:55432` | 1 |
| API (`core`) | `http://127.0.0.1:8000` | 2 |
| Pantalla (`foundit-web-app`) | `http://127.0.0.1:5173` | 3 |

- **CORS:** la API acepta peticiones desde la dirección de la pantalla, configurada en `CORS_ORIGINS`.
- **Datos iniciales:** la base empieza vacía, solo con las tablas. La primera alerta creada desde la pantalla recibe el número 1. Para la consulta con muchos datos se siembran 1.000 alertas.

### ¿Qué venía verificado de la semana 14 y qué faltaba?

| Estado al empezar la semana | RNF |
|---|---|
| ✅ Verificado en la API | RNF-SEC-01, RNF-SEC-02 (en la API y los registros), RNF-PERF-01, RNF-PERF-02 y RNF-MANT-01 |
| ⚠️ Límite conocido | RNF-PERF-01: si el servicio de capturas está caído, crear tarda unos 19 s |
| ⏳ Pendiente de integración | RNF-SEC-02 en la pantalla, RNF-SEC-01 desde la pantalla y el comportamiento con la API apagada |

---

## Actividad 1 · Diseñar la interacción

### ¿Qué hace el usuario en cada RF y qué ve?

| RF | Campos | Acción | Resultado visible | Corrección ante errores |
|---|---|---|---|---|
| RF-01 · Registrar | Modo («URL directa»), de 1 a 10 páginas, de 1 a 5 correos y una nota opcional | Pulsa **Guardar alerta**. Se abre una ventana de confirmación y pulsa **Crear alerta** | «Alerta creada», con su número, las páginas y el correo oculto (`u***@example.com`). También ve un aviso: la primera revisión de precios se hace en segundo plano | El error aparece junto al campo o a la fila exacta, y arriba un resumen: «Revisa los campos marcados antes de continuar.». Lo escrito se conserva |
| RF-02 · Consultar | «Número de alerta» | Pulsa **Consultar**, o **Ver alerta** al terminar de crear | La alerta, con estado, fecha, páginas activas y correos ocultos | «La alerta no existe.» o «El número no es válido…»; el número escrito se conserva para corregirlo |

### ¿Es fácil de usar?

- Todos los campos tienen etiqueta visible.
- Se puede usar solo con el teclado, y el foco va al primer campo con error.
- Los errores se explican con texto, no solo con color.
- Lo escrito no se borra cuando hay un error.

No priorizamos un RNF de accesibilidad: estas son buenas prácticas básicas, no un cumplimiento medido.

---

## Actividad 2 · Conectar cada acción con su contrato

### ¿Por qué estados pasa cada acción?

| Estado | RF-01 · Registrar | RF-02 · Consultar |
|---|---|---|
| Inicial | Formulario vacío, con el botón **Guardar alerta** | Campo «Número de alerta», con el botón **Consultar** |
| En curso | El botón cambia a «Creando…» y queda deshabilitado | «Cargando la alerta…»; el resultado anterior desaparece |
| Resultado | «Alerta creada», con el número y el estado que devolvió la API | Los datos que devolvió la API |
| Error | Mensaje en el campo o en un aviso, con el botón habilitado de nuevo | Mensaje de error; si es de conexión, aparece el botón **Reintentar** |

### ¿Qué muestra la pantalla según la respuesta?

| Respuesta | RF-01 · Registrar | RF-02 · Consultar |
|---|---|---|
| Éxito | 201: el número y el estado reales | 200: los datos recuperados de la base |
| Rechazo | 422: marca el campo o la fila exacta, por ejemplo «Esta dirección apunta a una red no permitida.» | 404: «La alerta no existe.» · 422: «El número no es válido…». No quedan datos de la consulta anterior |
| Error del servidor | 500: «Ocurrió un error al crear la alerta. No se guardó nada; inténtalo de nuevo.» | 500: «No pudimos consultar la alerta por un error del servidor…» |
| Sin conexión | «No pudimos conectar con el servidor…», y se conserva lo escrito | El mismo aviso, con el botón **Reintentar** |

### ¿Cómo se evitan los errores de comunicación?

- **Un solo envío:** mientras se envía, el botón queda deshabilitado. Aunque se haga doble clic, sale **una sola** petición.
- **Sin falso «creada»:** «Alerta creada» se muestra **solo** cuando la API responde 201 con datos válidos.
- **Sin reintento automático:** si se pierde la respuesta, la pantalla **no reintenta sola**, porque podría crear la alerta dos veces.
- **Sin *polling*:** la pantalla no pregunta por el estado una y otra vez. Una prueba automática lo comprueba.
- **Brecha conocida frente a la guía:** si la conexión se cae justo después de enviar, el aviso dice «No pudimos conectar… inténtalo de nuevo». No advierte que la alerta **pudo haberse guardado**, y la pantalla no tiene cómo comprobarlo, porque no conoce el número. Si el usuario repite, puede crear una alerta duplicada. Proponemos cambiar el mensaje para que diga que el resultado no está confirmado.

---

## Actividad 3 · Probar la integración

### ¿Qué se probó desde la pantalla?

**Fechas:** 24 de noviembre de 2026 (RF-01) y 25 de noviembre de 2026 (RF-02), en el navegador.

| RF | Escenario | Estado inicial | Entrada | Esperado | Obtenido | Evidencia |
|---|---|---|---|---|---|---|
| RF-01 | Válido | Base vacía | `https://example.com/producto/1` y `usuario@example.com` | «Alerta creada» y la alerta guardada | ✅ Número 1. En la base, desde otra conexión: 1 alerta, 1 página y 1 correo | Pantalla y consulta a la base |
| RF-01 | Rechazo | La alerta 1 creada | Página 2 = `http://localhost/x` | Error solo en la fila 2 y nada nuevo guardado | ✅ Error en la fila 2; la base siguió con 1 alerta | Pantalla y conteo antes y después |
| RF-01 | Vacío | Igual | Pulsar **Guardar** sin datos | Pide al menos una página y un correo | ✅ «Agrega al menos una página del producto.» y «Agrega al menos un correo.» | Pantalla |
| RF-01 | Repetida | Igual | La misma página escrita de dos formas | Avisa y guarda una sola | ✅ «Esta página repite la página 1; solo se guardará una.» | Pantalla y base |
| RF-01, RF-02 | Privacidad | Alertas creadas | Buscar `usuario@example.com` completo | No aparece en ninguna parte | ✅ 0 apariciones en la pantalla, las respuestas y los registros | Búsqueda en los registros |
| RF-01 | Sin conexión | API apagada | Enviar una alerta válida | Aviso y sin falso «creada» | ✅ En pruebas automáticas · ⏳ no repetido en el navegador | `tests` de `foundit-web-app` |
| RF-02 | Válido | 1.000 alertas más la 1001, creada desde la pantalla | **Ver alerta** y luego **recargar** la página | Los datos vienen de la API, no de la memoria del navegador | ✅ Tras recargar, los mismos datos | Pantalla y petición `GET` en el navegador |
| RF-02 | Ausencia | Igual | `999999`, comprobado antes como inexistente | «La alerta no existe.» y sin datos anteriores | ✅ | Pantalla |
| RF-02 | Entrada inválida | Igual | `abc` | «El número no es válido…» | ✅ | Pantalla |
| RF-02 | Cambio de número | Igual | Pasar a `500` sin recargar | Muestra la alerta 500 con un solo formulario | ✅ Al principio aparecía un formulario repetido; se corrigió y se agregó una prueba automática | Prueba `alert-lookup.test.tsx` |
| RF-02 | Sin conexión | API apagada | Consultar | Aviso y botón **Reintentar** | ✅ En pruebas automáticas · ⏳ no repetido en el navegador | `tests` de `foundit-web-app` |

**Pruebas automáticas de la pantalla:** 66 de 66 pasan.

---

## Actividad 4 · Cerrar la verificación de los RNF

### ¿Cómo quedó la calidad frente a las metas?

No se agregaron RNF nuevos por haber construido la pantalla. Las pruebas sin base real se volvieron a correr después de los últimos cambios, y siguen pasando.

| RF / RNF | Calidad y escenario | Resultado frente a la meta | Evidencia y estado |
|---|---|---|---|
| RF-01 / RNF-SEC-01 | Seguridad / integridad · QS-01: rechazar direcciones peligrosas | 100 % rechazadas, también desde la pantalla | `tests/unit/test_urls.py` y prueba en pantalla del 24/11 · ✅ Cumple |
| RF-01, RF-02 / RNF-SEC-02 | Seguridad / confidencialidad · QS-02: correo nunca completo | 0 apariciones en pantalla, API y registros | Pruebas `..._no_email_in_logs` y búsqueda del 24 y el 25/11 · ✅ Cumple |
| RF-01 / RNF-PERF-01 | Eficiencia / comportamiento temporal · QS-13: crear en ≤ 1 s | 20 de 20 cumplen, de 5,4 a 11,1 ms | [Tabla de tiempos de la semana 14](../semana-14/README.md#cuánto-tardó-cada-petición). Local, M3 Pro, PostgreSQL 16 · ✅ Cumple, con límite: sin el servicio de capturas; si está caído, unos 19 s |
| RF-02 / RNF-PERF-02 | Eficiencia / comportamiento temporal · adaptado de QS-14: consultar en ≤ 0,5 s | 20 de 20 cumplen, de 3,7 a 7,3 ms, con 1.000 alertas | Misma tabla y `scripts/measure_get_alert.py` · ✅ Cumple |
| RF-01, RF-02 / RNF-MANT-01 | Mantenibilidad / capacidad para ser probado · RNF-1 | 5 pruebas de servicio sin base real, todas pasan | `tests/unit` de `core-service`, 196 pruebas en verde · ✅ Cumple |

**Alcance de la medición:** los tiempos son de la respuesta HTTP completa medida con `curl`, no del tiempo hasta que la pantalla muestra los datos. Son 20 peticiones seguidas de un solo cliente, así que **no prueban concurrencia**. No se hicieron pruebas de carga porque ningún RNF priorizado las pide.

---

## Entrega final y demostración

### ¿Qué se necesita?

| Herramienta | Versión |
|---|---|
| Python y `uv` | Python 3.12 |
| Node.js y `pnpm` | Node 24 y pnpm 11 |
| Docker | Con la imagen `postgres:16` |

**Configuración sin credenciales reales:**

- Las variables de la API están en la [semana 14](../semana-14/README.md#cómo-se-ejecuta).
- La pantalla solo necesita `VITE_API_BASE_URL`; ver el `.env.example` de `foundit-web-app`.
- Las contraseñas de prueba se inventan en el momento.

### ¿Cómo se repite la demostración?

Desde la carpeta donde están los repositorios `architecture`, `core-service` y `foundit-web-app`:

1. **Base.** Inventar las contraseñas de prueba y levantar PostgreSQL 16 desechable:

   ```bash
   export PW=$(openssl rand -hex 16) CORE_PW=$(openssl rand -hex 16) OTHER_PW=$(openssl rand -hex 16)
   ```

   ```bash
   docker run --rm -d --name demo-pg --user 999:999 --cap-drop=ALL --security-opt=no-new-privileges --memory=512m --cpus=1 --pids-limit=200 --read-only --tmpfs /var/lib/postgresql/data:uid=999,gid=999 --tmpfs /var/run/postgresql:uid=999,gid=999 --tmpfs /tmp -e POSTGRES_PASSWORD="$PW" -p 127.0.0.1:55432:5432 postgres:16
   ```

2. **Esquema.** Cargar los dos scripts oficiales, en este orden. El segundo se carga con el usuario `core_service`, nunca como administrador:

   ```bash
   docker exec -i demo-pg psql -q -v ON_ERROR_STOP=1 -U postgres -d postgres -v auth_pw="$OTHER_PW" -v core_pw="$CORE_PW" -v schedule_pw="$OTHER_PW" -v notify_pw="$OTHER_PW" < architecture/docs/data/scripts/provision-roles.sql
   ```

   ```bash
   docker exec -i -e PGPASSWORD="$CORE_PW" demo-pg psql -q -v ON_ERROR_STOP=1 -h 127.0.0.1 -U core_service -d postgres < architecture/docs/data/scripts/core/schema.sql
   ```

3. **API.** En otra terminal, con las mismas contraseñas:

   ```bash
   cd core-service && DATABASE_URL="postgresql+psycopg://core_service:$CORE_PW@127.0.0.1:55432/postgres" FIXED_USER_ID=$(uuidgen) ALERT_CREATION_MODES=url CORS_ORIGINS=http://127.0.0.1:5173 uv run uvicorn core_service.main:create_app --factory --host 127.0.0.1 --port 8000
   ```

4. **Pantalla.** En otra terminal, apuntando a la API:

   ```bash
   cd foundit-web-app && VITE_API_BASE_URL=http://127.0.0.1:8000 pnpm exec vite --host 127.0.0.1 --port 5173
   ```

5. **Recorrido.** Abrir `http://127.0.0.1:5173`, pulsar **Ir al board** y seguir las pruebas de la actividad 3.

6. **Comprobar en la base** que la alerta quedó guardada:

   ```bash
   docker exec demo-pg psql -U postgres -d postgres -c "SELECT id, status FROM core.alert ORDER BY id"
   ```

7. **Reiniciar los datos:** `docker stop demo-pg` borra todo. Para repetir, se vuelve al paso 1.

### Guion de demostración

1. **Los RF y su orden:** RF-01 va primero porque RF-02 necesita una alerta creada.
2. **RF-01:** crear una alerta desde la pantalla y comprobar en la base que quedó guardada (paso 6).
3. **Rechazo de RF-01:** una página que apunta a `localhost`; la base no cambia.
4. **RF-02:**
   - pulsar **Ver alerta** y recargar la página, para mostrar que los datos vienen de la API;
   - luego consultar `999999`, que no existe.
5. **Mostrar cada capa en el código:**

   | Capa | RF-01 · Registrar | RF-02 · Consultar |
   |---|---|---|
   | Pantalla (`foundit-web-app/src/features/alerts/`) | `create-alert-page.tsx` | `alert-lookup-page.tsx` |
   | Endpoint (`core-service/.../api/routes.py`) | `POST /api/alerts` | `GET /api/alerts/{alert_id}` |
   | Servicio (`service.py`) | `AlertService.create` | `AlertService.get_alert` |
   | Repositorio (`adapters/sql_repository.py`) | `create` | `get_alert_detail` |

6. **Un resultado de calidad**, por ejemplo RNF-PERF-02:
   - **Meta:** consultar en 0,5 s o menos.
   - **Medida:** 20 consultas con 1.000 alertas.
   - **Resultado:** las 20 tardaron entre 3,7 y 7,3 ms.
   - **Límite real:** crear una alerta puede tardar unos 19 s si el servicio de capturas está caído.

### Evidencias

| Evidencia | Dónde |
|---|---|
| Pruebas de la API y la base | `core-service/tests/unit` y `core-service/tests/integration` |
| Pruebas de la pantalla | `foundit-web-app/tests` (66 pruebas) |
| Tiempos de RNF-PERF-01 y RNF-PERF-02 | [Semana 14, tabla de tiempos](../semana-14/README.md#cuánto-tardó-cada-petición) |
| Contratos | [Semana 14, actividad 2](../semana-14/README.md#actividad-2--contratos-de-la-api) |
| Requerimientos y criterios de aceptación | [CU-02](../../../docs/requirements/user-stories/CU-02.md) y [US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario) |

### Limitaciones

- La velocidad de crear una alerta (RNF-PERF-01) se midió sin el servicio que programa las capturas. Si ese servicio está caído, la respuesta puede tardar unos 19 s.
- Si se pierde la respuesta al crear, el aviso no dice que la alerta pudo haberse guardado (ver la actividad 2).
- La prueba sin conexión está cubierta por pruebas automáticas, pero no se repitió en el navegador.
- No hay pruebas automáticas de punta a punta en el navegador: la herramienta está por definir.
- La pantalla no se probó con un lector de pantalla.

---

## Checklist final

| Criterio | Cumple | Evidencia |
|---|---|---|
| Ambos RF conservan alcance, prioridad e identificadores | ✅ | «Los dos RF de esta entrega» |
| La interfaz ejecuta ambos RF con la API real | ✅ | Actividad 3: recarga y consulta a la base |
| Los contratos coinciden con lo observado | ✅ | Contratos de la semana 14 y actividad 2 |
| Éxito, rechazo o ausencia de ambos RF | ✅ | Actividad 3 |
| Persistencia real, sin resultados simulados | ✅ | Paso 6 de la demostración y recarga en RF-02 |
| Errores de entrada y de conexión comprensibles | ⚠️ Casi | Actividad 2: falta avisar que el resultado no está confirmado cuando se pierde la respuesta |
| Reglas en el servicio y datos en el repositorio | ✅ | Tabla de capas del guion |
| Trazabilidad RF–RNF–prueba–evidencia | ✅ | Matriz de la actividad 4 |
| Calidad comparada con las metas | ✅ | Matriz de la actividad 4 |
| Incumplimientos y limitaciones identificados | ✅ | «Limitaciones» |
| Otra persona puede repetir la demostración | ✅ | «¿Cómo se repite la demostración?» |

## Cierre

- **Los dos RF funcionan de punta a punta:** la pantalla llama a la API, la API al servicio, el servicio al repositorio y el repositorio a la base, con resultados que se pueden comprobar.
- **Los cinco RNF cumplen sus metas**, verificados por separado con mediciones y pruebas.
- **Quedan anotadas dos brechas:**
  - crear una alerta es lento si el servicio de capturas está caído;
  - el aviso no dice que la alerta pudo haberse guardado cuando se pierde la respuesta.
