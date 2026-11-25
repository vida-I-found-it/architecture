# Semana 13 · Priorización, calidad y persistencia

> Enunciado: [guía de la semana 13](../../sources/semana-13/README.md) · Proyecto: **I Found It** (ejercicio universitario).
> Toda la documentación de base está en [`docs/`](../../../docs/README.md); aquí solo respondemos las preguntas de la guía.

**Integrantes:** _por completar por el equipo._

---

## Actividad 1 · Confirmar y priorizar los dos RF

### ¿Cuáles son los dos RF? (identificador, actor, acción y resultado)

| RF | Actor | Acción | Resultado que se ve |
|---|---|---|---|
| **RF-01 · Registrar una alerta** ([CU-02](../../../docs/requirements/user-stories/CU-02.md)) | Usuario | Escribe de 1 a 10 páginas de un producto y de 1 a 5 correos, y confirma | La alerta queda guardada y el sistema le muestra su número de referencia |
| **RF-02 · Consultar una alerta** ([CU-07](../../../docs/requirements/user-stories/CU-07.md), historia [US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario)) | Usuario | Pide ver una alerta usando su número | Ve las páginas y el estado de la alerta, con los correos ocultos en parte (`a***@dominio.com`); si el número no existe, recibe un aviso claro |

### ¿Qué prioridad tiene cada uno y por qué?

| Prioridad | RF | Por qué |
|---|---|---|
| **1** | RF-01 | **Valor:** sin alertas el sistema no hace nada. **Arquitectura:** es la operación más exigente, porque valida lo que escribe el usuario, bloquea direcciones peligrosas y guarda en tres tablas a la vez. **Dependencia:** RF-02 necesita una alerta ya creada |
| **2** | RF-02 | **Valor:** confirma al usuario que su alerta quedó guardada y es la base del panel de la alerta. **Arquitectura:** es una lectura sencilla que además debe responder bien cuando la alerta no existe. Esfuerzo y riesgo bajos |

### ¿Qué queda fuera?

La captura automática de precios, el análisis y el envío de correos, el histórico de precios y la baja de una suscripción. Siguen en el proyecto, pero no entran en este prototipo de tres semanas.

---

## Actividad 2 · Vincular RNF y calidad verificable

### ¿Qué RNF se asocian a cada RF, y con qué característica de ISO/IEC 25010:2023?

Usamos los escenarios de calidad que ya estaban definidos en la [arquitectura](../../../docs/architecture/architecture.md) (QS-01 a QS-18); no creamos otros.

| RNF | Aplica a | Característica ISO / subcaracterística | En palabras simples |
|---|---|---|---|
| **RNF-SEC-01** (QS-01) | RF-01 | Seguridad / integridad | No se aceptan páginas que apunten a la red interna del equipo |
| **RNF-SEC-02** (QS-02) | RF-01 y RF-02 | Seguridad / confidencialidad | El correo nunca aparece completo |
| **RNF-PERF-01** (QS-13) | RF-01 | Eficiencia de desempeño / comportamiento temporal | Crear una alerta responde rápido |
| **RNF-PERF-02** (adaptado de QS-14) | RF-02 | Eficiencia de desempeño / comportamiento temporal | Consultar una alerta responde rápido |
| **RNF-MANT-01** (RNF-1) | RF-01 y RF-02 | Mantenibilidad / capacidad para ser probado | La lógica se puede probar sin la base de datos real |

### ¿Cuál es la condición de prueba, la medida, el umbral y la evidencia de cada RNF?

| RNF | Cómo se prueba | Meta | Evidencia | Cuándo |
|---|---|---|---|---|
| RNF-SEC-01 | Intentar crear alertas con páginas como `http://localhost`, IP internas, puertos raros o usuario y contraseña en la dirección | **100 %** rechazadas y **ninguna** guardada | Pruebas automáticas de `core-service` | Semanas 13 y 14 |
| RNF-SEC-02 | Hacer todo el recorrido con un correo de prueba y buscarlo después | **0** veces completo en registros (logs), respuestas y pantallas | Búsqueda en los registros y en la pantalla | Semanas 14 y 15 |
| RNF-PERF-01 | En el equipo local, crear 20 alertas de 10 páginas, una tras otra | Cada una en **1 segundo o menos** | Tabla de tiempos | Semana 14 |
| RNF-PERF-02 | Con 1.000 alertas de prueba, consultar 20 seguidas | Cada una en **medio segundo o menos** | Tabla de tiempos | Semana 14 |
| RNF-MANT-01 | Probar la lógica con una base «de mentira» en memoria | Una prueba de éxito y una de rechazo o ausencia por cada RF | Pruebas automáticas | Semanas 13 y 14 |

**Ojo, esto no es un RNF:** «una página no se repite dentro de la alerta» o «máximo 10 páginas» son **reglas de negocio** de RF-01. Las aplica el servicio y la base de datos las refuerza.

---

## Actividad 3 · Preparar y probar la persistencia

### ¿Qué datos mínimos se necesitan?

Tres tablas del [esquema de `core`](../../../docs/data/scripts/core/schema.sql), sin cambios frente al modelo del segundo corte:

| Tabla | Qué guarda | Sirve a | Regla que protege |
|---|---|---|---|
| `ALERT` | La alerta y su estado | RF-01 y RF-02 | Cada alerta tiene un número único |
| `ALERT_URL` | Las páginas de la alerta | RF-01 y RF-02 | Una página no se repite dentro de la misma alerta |
| `SUBSCRIPTION` | Los correos que reciben el aviso | RF-01, y RF-02 para mostrarlos ocultos | Un correo no se repite dentro de la misma alerta |

### ¿Cómo se recrea la base con un estado conocido?

En cada prueba se levanta un **PostgreSQL 16 nuevo y desechable** en Docker, se crean las tablas, se ejecutan los casos y la base se borra al terminar. Por eso siempre se parte de cero. Los pasos exactos están en [«Cómo repetir la prueba»](#cómo-repetir-la-prueba).

### ¿Cómo se separa el acceso a los datos?

Un **repositorio** es el único que habla con la base: ni la pantalla ni los endpoints escriben SQL.

| Operación del repositorio | Para qué | Estado |
|---|---|---|
| Guardar la alerta con sus páginas y correos, y devolver su número | RF-01 | ✅ Hecha |
| Leer una alerta y sus páginas por número (o decir «no existe») | Base de RF-02 | ✅ Hecha |
| Leer los correos de una alerta para mostrarlos ocultos | RF-02 completo | ⏳ Semana 14 → ✅ hecha en la semana 14 |

Código: `core-service/src/core_service/adapters/sql_repository.py`.

### ¿Quién confirma o deshace la operación, y cómo se liberan las conexiones?

El repositorio guarda la alerta, sus páginas y sus correos **en un solo paso**: o se guarda todo, o no se guarda nada. Al terminar devuelve la conexión para que otra petición la use. Si la base falla, el error se reemplaza por uno genérico que **no lleva el correo**.

### ¿Cómo se probó? (guardar, recuperar, número inexistente, regla de integridad)

| Lo que pide la guía | Qué hicimos | Resultado |
|---|---|---|
| Guardar y recuperar desde otra conexión | Crear la alerta y leerla con una conexión distinta | ✅ |
| Número inexistente | Pedir una alerta que no existe | ✅ Responde «no existe» sin romperse |
| Regla de integridad | Forzar un error en el último dato | ✅ No queda **nada** guardado a medias |
| Esquema real | Prueba completa con el script oficial de la base | ✅ |

**Resultado del 24 de noviembre de 2026:** pasaron 129 pruebas automáticas, 15 de ellas contra PostgreSQL 16 real.

### Cómo repetir la prueba

**Requisitos:** Docker con la imagen `postgres:16`, Python 3.12 y `uv`.

1. Instalar dependencias:

   ```bash
   cd core-service && uv sync
   ```

2. Levantar la base desechable. `$PW` es una contraseña de prueba que se inventa en el momento:

   ```bash
   docker run --rm -d --name core-it-pg --user 999:999 --cap-drop=ALL --security-opt=no-new-privileges --memory=512m --cpus=1 --pids-limit=200 --read-only --tmpfs /var/lib/postgresql/data:uid=999,gid=999 --tmpfs /var/run/postgresql:uid=999,gid=999 --tmpfs /tmp -e POSTGRES_PASSWORD="$PW" -p 127.0.0.1:55432:5432 postgres:16
   ```

3. Correr las pruebas contra esa base:

   ```bash
   TEST_DATABASE_URL="postgresql+psycopg://postgres:$PW@127.0.0.1:55432/postgres" uv run pytest tests/integration
   ```

**Resultado esperado:** todas las pruebas en verde. Al detener el contenedor, la base desaparece.

---

## Ficha RF–RNF del equipo

| Elemento | RF-01 · Registrar una alerta | RF-02 · Consultar una alerta |
|---|---|---|
| Actor y resultado | Usuario; recibe el número de la alerta | Usuario; ve la alerta o el aviso de que no existe |
| Prioridad | 1: es la base de todo y la más exigente | 2: depende de RF-01 y es sencilla |
| RNF | RNF-SEC-01, RNF-SEC-02, RNF-PERF-01, RNF-MANT-01 | RNF-SEC-02, RNF-PERF-02, RNF-MANT-01 |
| ISO/IEC 25010 | Seguridad, eficiencia de desempeño, mantenibilidad | Seguridad, eficiencia de desempeño, mantenibilidad |
| Datos | `ALERT`, `ALERT_URL`, `SUBSCRIPTION` | `ALERT`, `ALERT_URL`, `SUBSCRIPTION` (solo lectura) |
| Pruebas de esta semana | ✅ Guardar, leer, inexistente e integridad | ✅ Lectura base (la lectura con correos ocultos se terminó en la semana 14) |
| Pendiente | Medir la velocidad (semana 14) | Endpoint y pantalla: ✅ hechos en las semanas 14 y 15 |

---

## Antes de cerrar: ¿qué construiremos, en qué orden, con qué calidad y cómo lo comprobaremos?

Construiremos **RF-01 (registrar una alerta)** y luego **RF-02 (consultarla)**, porque la consulta necesita una alerta creada. Esperamos que sea **seguro**: no acepta direcciones peligrosas y nunca muestra el correo completo. Esperamos que sea **rápido**: un segundo o menos para crear y medio segundo para consultar. Y que sea **fácil de probar**. Lo comprobaremos con pruebas automáticas, la búsqueda del correo en los registros y una tabla de tiempos.

## Criterios de revisión

| Criterio | Cumple | Dónde |
|---|---|---|
| Dos RF identificados, priorizados y justificados | ✅ | Actividad 1 |
| Cada RF con sus RNF e ISO/IEC 25010 | ✅ | Actividad 2 |
| RNF con condición, medida, umbral y verificación | ✅ | Actividad 2 |
| Datos y operaciones para ambos RF | ⚠️ Casi | En esta semana faltaba leer los correos ocultos de RF-02; se completó en la semana 14 |
| Base y datos recreables | ✅ | Actividad 3 |
| Lectura, escritura y persistencia real | ✅ | Actividad 3 |
| Pasos exactos para repetir | ✅ | «Cómo repetir la prueba» |
| Probado frente a pendiente | ✅ | Ficha RF–RNF |
