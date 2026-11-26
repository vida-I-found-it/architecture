# Semana 13 · Priorización, calidad y persistencia

---

## Actividad 1 · Confirmar y priorizar los dos RF

### ¿Cuáles son los dos RF? (identificador, actor, acción y resultado)

| RF | Actor | Acción | Resultado que se ve |
|---|---|---|---|
| **RF-01 · Registrar una alerta** ([CU-02](../../../docs/requirements/user-stories/CU-02.md)) | Usuario | Escribe de 1 a 10 páginas de un producto y de 1 a 5 correos, y confirma | La alerta queda guardada y el sistema le muestra su número de referencia |
| **RF-02 · Consultar una alerta** ([CU-07](../../../docs/requirements/user-stories/CU-07.md), historia [US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario)) | Usuario | Pide ver una alerta usando su número | Ve las páginas y el estado de la alerta, con los correos ocultos en parte (`a***@dominio.com`); si el número no existe, recibe un aviso claro |

**Ajuste frente al segundo corte:** RF-01 se conserva tal cual. RF-02 ya existía dentro de CU-07 (panel de la alerta), pero para el prototipo se recortó a una sola historia, US-07-06: consultar por número, sin histórico de precios ni inicio de sesión. Se recortó para que cupiera en tres semanas; los identificadores no cambian.

### ¿Qué prioridad tiene cada uno y por qué?

| Prioridad | RF | Valor para el usuario | Relevancia para la arquitectura | Esfuerzo y riesgo | Dependencia |
|---|---|---|---|---|---|
| **1** | RF-01 | Alto: sin alertas el sistema no hace nada | Alta: valida lo que escribe el usuario, bloquea direcciones peligrosas y guarda en tres tablas en un solo paso | Esfuerzo medio. Riesgo alto: es la puerta de entrada de datos externos | Ninguna: es la base de todo |
| **2** | RF-02 | Medio: confirma que la alerta quedó guardada y es la base del panel de la alerta | Media: es una lectura, pero debe ocultar los correos y responder bien cuando la alerta no existe | Esfuerzo y riesgo bajos | Necesita una alerta creada con RF-01 |

Los dos tienen valor, pero **la dependencia decide el orden**: no se puede consultar lo que no se ha creado.

### ¿Qué queda fuera?

La captura automática de precios, el análisis y el envío de correos, el histórico de precios y la baja de una suscripción. Siguen en el proyecto, pero no entran en este prototipo de tres semanas.

---

## Actividad 2 · Vincular RNF y calidad verificable

### ¿Qué RNF se asocian a cada RF, y con qué característica de ISO/IEC 25010:2023?

Usamos los escenarios de calidad que ya estaban definidos en la [arquitectura](../../../docs/architecture/architecture.md) (QS-01 a QS-18). No los copiamos aquí: cada RNF referencia su escenario.

| RNF | Aplica a | Característica ISO / subcaracterística | En palabras simples |
|---|---|---|---|
| **RNF-SEC-01** (QS-01) | RF-01 | Seguridad / integridad | No se aceptan páginas que apunten a la red interna del equipo |
| **RNF-SEC-02** (QS-02) | RF-01 y RF-02 | Seguridad / confidencialidad | El correo nunca aparece completo |
| **RNF-PERF-01** (QS-13) | RF-01 | Eficiencia de desempeño / comportamiento temporal | Crear una alerta responde rápido |
| **RNF-PERF-02** (adaptado de QS-14) | RF-02 | Eficiencia de desempeño / comportamiento temporal | Consultar una alerta responde rápido |
| **RNF-MANT-01** (RNF-1) | RF-01 y RF-02 | Mantenibilidad / capacidad para ser probado | La lógica se puede probar sin la base de datos real |

### ¿Cuál es la condición de prueba, la medida, el umbral y la evidencia de cada RNF?

| RNF | Condición de prueba | Medida | Umbral | Evidencia | Semana |
|---|---|---|---|---|---|
| RNF-SEC-01 | Intentar crear alertas con páginas como `http://localhost`, IP internas (`10.x`, `192.168.x`), puertos raros o usuario y contraseña en la dirección | Porcentaje de intentos rechazados y alertas guardadas | **100 %** rechazadas y **0** guardadas | Pruebas automáticas `test_urls.py` y `test_api.py` de `core-service` | 13 y 14 |
| RNF-SEC-02 | Hacer todo el recorrido con un correo de prueba y buscarlo después en registros, respuestas y pantalla | Veces que aparece el correo completo | **0** | Búsqueda del correo en los registros y pruebas `..._no_email_in_logs` | 14 y 15 |
| RNF-PERF-01 | En el equipo local, con un cliente, crear 20 alertas de 10 páginas una tras otra, midiendo la respuesta HTTP completa | Tiempo de cada petición | **≤ 1 s cada una** (no el promedio) | Tabla con los 20 tiempos y su código HTTP | 14 |
| RNF-PERF-02 | En el equipo local, con 1.000 alertas de prueba y un cliente, consultar 20 alertas existentes seguidas | Tiempo de cada petición | **≤ 0,5 s cada una** | Tabla con los 20 tiempos y su código HTTP | 14 |
| RNF-MANT-01 | Reemplazar el repositorio real por uno simulado en memoria | Pruebas de servicio que pasan sin abrir conexión | Al menos **una de éxito y una de rechazo o ausencia por RF** | Pruebas en `tests/unit` | Contrato en la 13; pruebas en la 14 |

**Ojo, esto no es un RNF:** «una página no se repite dentro de la alerta» o «máximo 10 páginas» son **reglas de negocio** de RF-01. Las aplica el servicio y la base de datos las refuerza.

---

## Actividad 3 · Preparar y probar la persistencia

### ¿Qué datos mínimos se necesitan?

Tres tablas del [esquema de `core`](../../../docs/data/scripts/core/schema.sql), **sin cambios** frente al modelo del segundo corte. Solo se usan las columnas que necesitan los dos RF:

| Tabla | Clave | Relación | Campos obligatorios que usan los RF | Regla que protege la base |
|---|---|---|---|---|
| `ALERT` | `ID` (número que asigna la base) | Una alerta tiene muchas páginas y muchos correos | `TITLE`, `PRODUCT_NAME`, `STATUS` (por defecto `active`), `CREATED_BY`, `CREATED_AT`. Opcional: `NOTES` | `STATUS` solo puede ser `active` o `inactive`; la nota tiene máximo 500 caracteres |
| `ALERT_URL` | `ID` | Pertenece a una alerta (`ALERT_ID` → `ALERT.ID`) | `ALERT_ID`, `URL`, `DOMAIN`, `IS_ACTIVE` | **Una página no se repite en la misma alerta** (`UNIQUE (ALERT_ID, URL)`); máximo 2.048 caracteres |
| `SUBSCRIPTION` | `ID` | Pertenece a una alerta (`ALERT_ID` → `ALERT.ID`) | `ALERT_ID`, `EMAIL`, `STATUS`, `CREATED_BY` | El correo se guarda en minúsculas y con máximo 254 caracteres (`CHECK`) |

- **RF-01** escribe en las tres tablas.
- **RF-02** lee `ALERT`, las páginas activas de `ALERT_URL` y los correos de `SUBSCRIPTION`, que muestra ocultos.

### ¿Cómo se recrea la base con un estado conocido?

- **Esquema:** los scripts oficiales `provision-roles.sql` (crea los esquemas y el usuario `CORE_SERVICE`) y `core/schema.sql` (crea las tablas).
- **Base:** en cada prueba se levanta un **PostgreSQL 16 nuevo y desechable** en Docker. Al terminar se borra, así que siempre se parte de una base vacía.
- **Datos de prueba conocidos**, que se mantienen en las tres semanas:
  - páginas de `example.com` (por ejemplo `https://example.com/producto/1`);
  - el correo ficticio `usuario@example.com`;
  - para medir la consulta se siembran **1.000 alertas** de 3 páginas y 2 correos cada una, con la tercera página inactiva (script `core-service/scripts/measure_get_alert.py`).

Los pasos exactos están en [«Cómo repetir la prueba»](#cómo-repetir-la-prueba).

### ¿Cómo se separa el acceso a los datos?

Un **repositorio** (`SqlAlertRepository`) es el único que habla con la base: ni la pantalla ni los endpoints escriben SQL. El servicio lo usa a través de una interfaz (`AlertRepository`, en `ports.py`). Así, en las pruebas se cambia por uno simulado.

| Operación | Entrada | Resultado | Para qué | Estado |
|---|---|---|---|---|
| `create` | La alerta ya validada (páginas limpias, correos y nota) y el usuario que la crea | El número de la alerta, su estado y sus páginas | RF-01 | ✅ Hecha |
| `get_alert_detail` | El número de la alerta | La alerta con sus páginas activas y sus correos, o **«no existe»** (`None`) | RF-02 | ✅ Lectura de alerta y páginas en la semana 13; los correos se agregaron en la semana 14 |

Código: `core-service/src/core_service/adapters/sql_repository.py`.

### ¿Quién confirma o deshace la operación, y cómo se liberan las conexiones?

- **Quién confirma:** el repositorio abre una transacción (`sessionmaker.begin()`) y guarda en ella la alerta, sus páginas y sus correos.
  - Si todo sale bien, **confirma** al cerrar el bloque.
  - Si cualquier paso falla, **deshace todo**: no queda nada guardado a medias.
- **Conexiones:** al cerrar ese bloque, la conexión vuelve al grupo de conexiones (*pool*) para que otra petición la use, haya salido bien o mal.
- **Errores:** si la base falla, el repositorio cambia el error por uno genérico (`PersistenceError`) que solo lleva el código técnico de la base, **nunca el correo**.

### ¿Cómo se probó? (guardar, recuperar, número inexistente, regla de integridad)

Las pruebas llaman al repositorio desde pruebas automáticas contra un PostgreSQL 16 real.

| Lo que pide la guía | Qué hicimos | Resultado obtenido |
|---|---|---|
| Guardar y recuperar desde otra conexión | Crear una alerta y leerla con una conexión nueva (`test_tc_02_01_...`) | ✅ 1 alerta, 1 página y 1 correo, con los mismos datos |
| Guardar el máximo | Crear una alerta con 10 páginas (`test_tc_02_02_...`) | ✅ Las 10 guardadas en el orden del usuario |
| Número inexistente | Pedir una alerta que no existe, incluso el mayor número posible, 2147483647 (`test_ac6_ac8_...`) | ✅ Responde «no existe», sin error |
| Regla de integridad | Saltarse la validación y enviar un correo en MAYÚSCULAS. El `CHECK` de `SUBSCRIPTION` lo rechaza en el último paso (`test_tc_02_07_...`) | ✅ La base lo rechazó, y quedaron **0** alertas, **0** páginas y **0** correos. El error no muestra el correo |
| Página repetida | Enviar la misma página dos veces (`test_us_02_01_ac5_...`) | ✅ Se guarda una sola vez |
| Esquema real | Las pruebas automáticas crean las tablas desde el modelo del código, que repite las mismas reglas del script. Por eso, el 24/11 se hizo además una prueba completa cargando el script oficial `core/schema.sql` con el usuario `CORE_SERVICE` | ✅ |

**Resultado del 24 de noviembre de 2026:** pasaron 129 pruebas automáticas, 15 de ellas contra PostgreSQL 16 real.

### Cómo repetir la prueba

**Requisitos:** Docker con la imagen `postgres:16`, Python 3.12 y `uv`.

**Configuración:** no hay archivos con contraseñas. La contraseña de prueba se inventa en el momento, por ejemplo `PW=$(openssl rand -hex 16)`.

1. Instalar dependencias:

   ```bash
   cd core-service && uv sync
   ```

2. Levantar la base desechable, solo en `127.0.0.1`:

   ```bash
   docker run --rm -d --name core-it-pg --user 999:999 --cap-drop=ALL --security-opt=no-new-privileges --memory=512m --cpus=1 --pids-limit=200 --read-only --tmpfs /var/lib/postgresql/data:uid=999,gid=999 --tmpfs /var/run/postgresql:uid=999,gid=999 --tmpfs /tmp -e POSTGRES_PASSWORD="$PW" -p 127.0.0.1:55432:5432 postgres:16
   ```

3. Correr las pruebas contra esa base. Las pruebas crean las tablas solas y vacían los datos entre casos. Si `TEST_DATABASE_URL` no apunta a `127.0.0.1` o `localhost`, se niegan a correr:

   ```bash
   TEST_DATABASE_URL="postgresql+psycopg://postgres:$PW@127.0.0.1:55432/postgres" uv run pytest tests/integration
   ```

4. Apagar la base; los datos se borran:

   ```bash
   docker stop core-it-pg
   ```

**Resultado esperado:** `pytest` termina con todas las pruebas en `passed` y ninguna en `failed`. Las pruebas de la semana 13 están en `tests/integration/test_alerts_db.py` y `tests/integration/test_get_alert_db.py`.

**Dónde está la evidencia:** la salida de `pytest` y el código de las pruebas citadas en la tabla anterior.

---

## Ficha RF–RNF del equipo

| Elemento | RF-01 · Registrar una alerta | RF-02 · Consultar una alerta |
|---|---|---|
| Identificador y enunciado | RF-01: el usuario registra una alerta con sus páginas y correos | RF-02: el usuario consulta una alerta por su número |
| Actor y resultado | Usuario; recibe el número de la alerta | Usuario; ve la alerta o el aviso de que no existe |
| Prioridad y justificación | 1: alto valor, la más exigente y no depende de nada | 2: valor medio, sencilla y depende de RF-01 |
| RNF | RNF-SEC-01, RNF-SEC-02, RNF-PERF-01, RNF-MANT-01 | RNF-SEC-02, RNF-PERF-02, RNF-MANT-01 |
| ISO/IEC 25010 | Seguridad (integridad y confidencialidad), eficiencia de desempeño (comportamiento temporal), mantenibilidad (capacidad para ser probado) | Seguridad (confidencialidad), eficiencia de desempeño (comportamiento temporal), mantenibilidad (capacidad para ser probado) |
| Condición, medida y umbral | 100 % de direcciones peligrosas rechazadas; 0 correos completos; 20 altas de 10 páginas, cada una en ≤ 1 s; una prueba de éxito y una de rechazo sin base real | 0 correos completos; con 1.000 alertas, 20 consultas, cada una en ≤ 0,5 s; una prueba de éxito y una de ausencia sin base real |
| Prueba, evidencia y semana | Pruebas de `core-service` (semanas 13 y 14); tabla de tiempos (semana 14); búsqueda del correo (semanas 14 y 15) | Pruebas de `core-service` (semana 14); tabla de tiempos (semana 14); búsqueda del correo (semanas 14 y 15) |
| Datos y operaciones | `ALERT`, `ALERT_URL`, `SUBSCRIPTION` · `create` | `ALERT`, `ALERT_URL`, `SUBSCRIPTION` (solo lectura) · `get_alert_detail` |
| Resultado de la semana 13 | ✅ Guardar, leer desde otra conexión, número inexistente e integridad | ✅ Lectura de alerta y páginas, y número inexistente |
| Pendiente | Medir la velocidad y crear el endpoint (semana 14); la pantalla (semana 15) | Leer los correos ocultos, el endpoint y la medición (semana 14); la pantalla (semana 15). Todo se cumplió; ver las semanas [14](../semana-14/README.md) y [15](../semana-15/README.md) |

---

## Antes de cerrar: ¿qué construiremos, en qué orden, con qué calidad y cómo lo comprobaremos?

- **Qué y en qué orden:** primero **RF-01 (registrar una alerta)** y luego **RF-02 (consultarla)**, porque la consulta necesita una alerta creada.
- **Qué calidad esperamos:**
  - **Seguro:** no acepta direcciones peligrosas y nunca muestra el correo completo.
  - **Rápido:** un segundo o menos para crear y medio segundo para consultar, en cada petición.
  - **Fácil de probar:** la lógica se prueba sin la base real.
- **Con qué evidencia:** pruebas automáticas, la búsqueda del correo en los registros y una tabla con los tiempos de cada petición.

## Criterios de revisión

| Criterio | Cumple | Evidencia |
|---|---|---|
| Dos RF identificados, priorizados y justificados | ✅ | Actividad 1 |
| Cada RF con sus RNF e ISO/IEC 25010 | ✅ | Actividad 2 y ficha |
| RNF con condición, medida, umbral y verificación | ✅ | Actividad 2, segunda tabla |
| Datos y operaciones para ambos RF | ⚠️ Casi | Actividad 3. En esta semana faltaba leer los correos ocultos de RF-02; se completó en la semana 14 |
| Base y datos recreables | ✅ | «¿Cómo se recrea la base…?» |
| Lectura, escritura y persistencia real | ✅ | `test_alerts_db.py` y `test_get_alert_db.py` |
| Pasos exactos para repetir | ✅ | «Cómo repetir la prueba» |
| Probado frente a pendiente | ✅ | Ficha RF–RNF, filas «Resultado» y «Pendiente» |
