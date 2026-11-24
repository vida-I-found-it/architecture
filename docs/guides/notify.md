# Guía de arranque · `notify`

> Para quien implementará este repositorio. Lo que la documentación no define figura como «pendiente de decisión» con enlace a la pregunta abierta. No inventes endpoints, campos ni variables.

## Repositorio

- **GitHub:** [vida-I-found-it/notify-service](https://github.com/vida-I-found-it/notify-service)
- **Local:** [`../notify-service/`](../../../notify-service/), en la carpeta que contiene este repositorio de arquitectura (un nivel arriba de su raíz).

> Estado al 2026-11-24: el repositorio solo tiene `LICENSE` y `README.md`; el código está por escribir.

## Qué es el servicio

`notify` recibe peticiones de aviso por REST, las guarda de forma idempotente y las envía por correo en un worker con outbox. Tiene dos clientes: `core` (avisos de bajada de precio, [CU-10](../requirements/user-stories/CU-10.md)) y `schedule` (correo diario de errores al administrador). No conoce suscripciones, análisis ni secretos de baja: solo recibe el `payload` ya armado. La arquitectura: [`architecture.md`](../architecture/architecture.md#comunicación-entre-piezas).

## Historias y criterios, en orden de implementación

Solo las partes que son de `notify`. El orden sigue la tabla de dependencias de [CU-10](../requirements/user-stories/CU-10.md#dependencias-y-orden-de-implementación-sugerido): `notify` se puede probar solo, con `curl` y un SMTP de prueba, antes de que exista `core`.

| Orden | Historia | Criterios | Nota |
|---|---|---|---|
| 1 | US-10-02 · crear la notificación de forma idempotente | AC1 a AC11 | `POST /notify/notifications`: 202 nuevo, 200 repetido, 4xx validación. |
| 2 | US-10-03 · enviar el email con reintentos | AC1 a AC11 | Worker del outbox. Requiere SMTP de prueba (pregunta 17). |
| 3 | US-10-04 · contenido del correo y plantillas | AC1 a AC7 | Plantilla `price-drop-email` sembrada en `seed.sql`; versiones nuevas, nunca `UPDATE`. |
| 4 | US-10-05 · aviso diario de errores y semillas | AC1 a AC4 | Canal `email` y plantilla `admin-alert-email`. El barrido vive en `schedule`. |

US-10-01 (la llamada desde `core`) está en [`core.md`](core.md).

## Endpoints

### Que expone

| Método y ruta | Historia | Estado |
|---|---|---|
| `POST /notify/notifications` | US-10-02 | 202 `{id, status: pending}` al crear; 200 si ya existe la llave; 4xx para canal o plantilla inexistentes o inactivos, campos mal formados o `destination` inválido. Cuerpo y códigos exactos: **pendiente** ([CU-10, pregunta 2](../requirements/user-stories/CU-10.md#preguntas-abiertas)). Tamaño máximo del `payload`: pendiente (pregunta 5). |
| `GET /notify/health` | EJ-4 | Ruta del prefijo que menciona la historia; la arquitectura pide `/health` en cada pieza. |

No expone nada más. Sin rutas de escritura sobre plantillas.

### Que consume

Ninguno. El envío es SMTP, hacia el SMTP de prueba. Según [`architecture.md`](../architecture/architecture.md#comunicación-entre-piezas) el candidato de prueba es Mailpit; **instalarlo o descargar su imagen requiere el sí del usuario** ([CU-10, pregunta 17](../requirements/user-stories/CU-10.md#preguntas-abiertas)).

## Tablas y colecciones que posee

Fuente: [`data/scripts/notify/schema.sql`](../data/scripts/notify/schema.sql).

- `channel`, `template` (la versión vigente se marca con `IS_ACTIVE`; índice `IX_TEMPLATE_ACTIVE`).
- `notification` (índices por `APP_USER_ID`, `SYSTEM` y por fallidas) y `notification_outbox` (índice `IX_NOTIFICATION_OUTBOX_RETRY`).
- Semillas: [`data/scripts/notify/seed.sql`](../data/scripts/notify/seed.sql) (`price-drop-email` y `admin-alert-email`, versión 1). Idempotente con `ON CONFLICT (code, version) DO NOTHING`.
- Rol de base de datos `NOTIFY_SERVICE`, según [CU-10](../requirements/user-stories/CU-10.md) (US-10-04 y guía). Revisar [`provision-roles.sql`](../data/scripts/provision-roles.sql) antes de usarlo.

Mongo: [`data/scripts/notify/mongo-setup.js`](../data/scripts/notify/mongo-setup.js). Las historias no le asignan colecciones; revisar el script antes de dar por hecho que no se usa.

**Pendiente:** `notification` guarda `destination` (correo en claro) y `payload`, que incluye el enlace de baja. Hay que decidir su retención ([CU-10, pregunta 21](../requirements/user-stories/CU-10.md#preguntas-abiertas)) y el manejo del token ([pregunta 1](../requirements/user-stories/CU-10.md#preguntas-abiertas), 🔒).

## Variables de entorno

**Ninguna nombrada en la documentación.** Pendiente de decisión:

- Conexión al SMTP de prueba, remitente (`From`) y nombre visible ([CU-10, pregunta 17](../requirements/user-stories/CU-10.md#preguntas-abiertas)).
- Conexión a PostgreSQL con el rol de `notify` y a MongoDB ([`architecture.md`, Configuración](../architecture/architecture.md#configuración)): sin nombre definido.
- Reintentos del envío de correo (número, esperas, variable de entorno): [CU-10, pregunta 7](../requirements/user-stories/CU-10.md#preguntas-abiertas).

## Contratos con otros servicios

| Contrato | Con quién | Estado |
|---|---|---|
| `POST /notify/notifications` | `core` y `schedule` | Ruta y reglas de idempotencia definidas (llave `UNIQUE (transaction_id, app_user_id, channel_id, destination)`). Cuerpo y códigos **pendientes** (CU-10 p. 2 y p. 4). |
| Llave de idempotencia | ADR-0004 | **Contradicción:** el ADR omite `destination`; DEC-11 y el esquema lo incluyen. Propuesta: corregir el ADR ([CU-10, pregunta 8](../requirements/user-stories/CU-10.md#preguntas-abiertas)). |
| Nombre de la plantilla del admin | EJ-6 | **Contradicción:** EJ-6 dice `admin_alert`; la plantilla real es `admin-alert-email` ([CU-10, pregunta 16](../requirements/user-stories/CU-10.md#preguntas-abiertas)). |
| Plantilla de baja y texto de anomalía | NOT-5 | El texto de `seed.sql` no coincide con NOT-5 ([CU-10, pregunta 15](../requirements/user-stories/CU-10.md#preguntas-abiertas)). Propuesta: versión 2. |

## Preguntas abiertas que bloquean este repositorio

- Campos oficiales del `payload` y si las claves desconocidas se rechazan (CU-10 p. 4).
- Ruta y token de baja: aceptar que el token viaje en `notification.payload` o que `notify` no lo guarde (CU-10 p. 1, 🔒).
- Códigos y cuerpos de respuesta (CU-10 p. 2).
- Quién normaliza el correo antes de llamar (CU-10 p. 3).
- Reintentos de `core` y del worker, y su timeout (CU-10 pp. 6 y 7).
- SMTP de prueba y remitente (CU-10 p. 17).
- Autoescape de Jinja2 y validación de `product_url` y `unsubscribe_url` (CU-10 p. 12, 🔒).
- Formato de precios y moneda en el correo (CU-10 p. 13).

## Seguridad

- Ningún log con `destination`, `payload` ni enlace de baja. Los errores SMTP se enmascaran antes de guardarlos (US-10-03-AC8).
- Envío solo al SMTP de prueba local. Nunca a internet (US-10-03-AC9).
- `notify` no conoce el secreto HMAC de la baja (DEC-13). La arquitectura todavía lo lista para `notify` ([CU-10, pregunta 11](../requirements/user-stories/CU-10.md#preguntas-abiertas)).
- Sin autenticación entre servicios en esta versión.
