# Scripts de base de datos — divididos por esquema/dominio

> Referencia ejecutable de lo que describe el [doc 03 · Modelo de datos](../../03-modelo-datos.md). Cada pieza tiene acceso **solo** a su funcionalidad concreta: en PostgreSQL, vía un **esquema propio + un rol propio**; en MongoDB, vía una **base propia** (Mongo no tiene "esquemas" como Postgres — su unidad de aislamiento es la base). **No** son la migración definitiva de cada repo (eso lo lleva Alembic dentro de cada repo, INF-4): son el punto de partida.
>
> **Estilo de los `.sql`:** esquemas, tablas, columnas, roles e índices van en **mayúsculas** (`SCREAMING_SNAKE_CASE`), sin comillas dobles — es solo estilo visual del archivo: PostgreSQL pliega igual a minúsculas cualquier identificador no citado, así que el objeto real en el catálogo (y el resto de la documentación, que sigue en minúscula) no cambia. Los `mongo-setup.js` **no** siguen esta convención: en MongoDB el nombre escrito es el nombre real (no hay plegado), así que se mantienen en minúscula para no romper la consistencia con las colecciones ya documentadas en doc 02/03.

## Tabla de contenido

- [Estructura](#estructura)
- [Regla dura: sin FK entre esquemas](#regla-dura-sin-fk-entre-esquemas)
- [Una sola base PostgreSQL, cuatro esquemas](#una-sola-base-postgresql-cuatro-esquemas)
- [Pendiente](#pendiente)

## Estructura

| Carpeta | Esquema/base | Motor | Contenido |
|---|---|---|---|
| [`auth/`](auth/schema.sql) | esquema `auth` (rol `auth_service`) | PostgreSQL | `person`, `app_user`, `role`/`permission`, `refresh_token`, `password_reset`, `audit_log`, `system` |
| [`core/`](core/schema.sql) | esquema `core` (rol `core_service`) | PostgreSQL | `alert`, `alert_url`, `tag`, `site_adapter`, `site_stats_daily`, `price_snapshot` (particionado), `subscription` |
| [`schedule/`](schedule/schema.sql) | esquema `schedule` (rol `schedule_service`) | PostgreSQL | `execution_type`, `job`, `job_script`, `job_execution`, `job_callback_sent`, `job_callback_outbox` — motor de jobs genérico, sin ningún concepto de `core` (2026-10-01) |
| [`notify/`](notify/schema.sql) | esquema `notify` (rol `notify_service`) | PostgreSQL | `notification` (configurada), `notification_sent` (enviada), `notification_outbox` (cola de reintento) |
| [`core/mongo-setup.js`](core/mongo-setup.js) | base Mongo de `core` | MongoDB | `exchange_rate` |
| [`schedule/mongo-setup.js`](schedule/mongo-setup.js) | base Mongo de `schedule` | MongoDB | `job_execution_result` |
| [`notify/mongo-setup.js`](notify/mongo-setup.js) | base Mongo de `notify` | MongoDB | `notification_log` |

## Regla dura: sin FK entre esquemas

**Cada rol solo tiene permisos sobre su propio esquema** (`provision-roles.sql`). Ningún script referencia con `REFERENCES` una tabla de otro esquema. Un campo que *parece* apuntar a otro dominio es un valor simple, sin FK real — la integridad la garantiza el servicio que escribe, no la base de datos:

| Campo | Vive en | Referencia (sin FK) a |
|---|---|---|
| `core.alert.created_by`, `core.site_adapter.created_by`, `core.subscription.created_by` | `core` | `auth.app_user.id` |
| `core.price_snapshot.run_id` | `core` | `schedule.job_execution.id` |
| `notify.notification.alert_id`, `notify.notification.trigger_alert_url_id` | `notify` | `core.alert.id` / `core.alert_url.id` |
| `notify.notification.run_id` | `notify` | `schedule.job_execution.id` |
| `notify.notification.app_user_id` | `notify` | `auth.app_user.id` (obligatorio: toda funcionalidad exige cuenta, 2026-09-30) |
| `notify.notification.system` | `notify` | `auth.system.code` |

Esto es deliberado: al no haber ninguna FK que cruce un esquema, **los 4 scripts de PostgreSQL se pueden correr en cualquier orden**, sin dependencias circulares entre sí.

> ✅ **`schedule` es su propio repositorio** (decidido 2026-09-29, [ADR-0001](../../adr/0001-estructura-repos-servicios.md) actualizado): el esquema de base de datos de esta carpeta y el repo que lo administra coinciden 1:1. Consecuencia pendiente de resolver: **ALE-8 deja de ser una sola transacción** entre `core` (crea la alerta) y `schedule` (crea su schedule por defecto) — ver [doc 09](../../09-pendientes.md), D7.
>
> ✅ **El scraper ya no llama a `core`** (decidido 2026-09-30, SCR-20): entrega su resultado a `schedule`, que se lo reenvía a `core` llamando a la URL configurada al crear el job (`api_call`, SCH-14).
>
> ✅ **`schedule` se rediseñó como motor de jobs genérico** (decidido 2026-10-01, resuelve D9): `schedule`/`run` (atados a `alert_id`) desaparecen; `job`/`job_execution` ya no conocen ningún concepto de `core` — `system` + `execution_type` + `payload` (opaco) son su única entrada. `execution_type='script'` soporta además código serverless (Python/JavaScript, `job_script`), acotado por `CHECK` a propósito. Consecuencia: `job_state`/`run_summary`/`raw_capture`/`scrape_result` (detalle específico de scraping) **dejaron de existir** en la Mongo de `schedule` — las reemplaza una única `job_execution_result` genérica. El nuevo hogar de ese detalle de scraping queda pendiente — ver [doc 09](../../09-pendientes.md).
>
> ✅ **`notification` se movió de `core` a `notify`** (decidido 2026-09-30): es el dato que `notify` posee de punta a punta. Consecuencia pendiente de resolver: el motor de decisión de `core` ya no puede insertar el outbox en la misma transacción donde actualiza `best_price_*` — falta el mecanismo de entrega confiable entre `core` y `notify` — ver [doc 09](../../09-pendientes.md), D12.
>
> ✅ **El outbox se partió en 3 tablas** (decidido 2026-09-30): `notification` (configurada, sin estado) ya no muta un `status` en el sitio — `notification_sent` se llena solo si `SEND` entrega con éxito, y `notification_outbox` solo si falla (cola de reintento real, con `FOR UPDATE SKIP LOCKED` sobre `next_retry_at`). Antes una sola fila mezclaba "por enviar" con "enviada".
>
> ✅ **Se retiró el rol incógnito** (decidido 2026-09-30): toda funcionalidad exige usuario registrado. `auth.role` queda sembrado con solo `admin`/`user`, y `notify.notification` se amarra a `app_user_id` (obligatorio) + `system` en vez de `subscription_id` — ya no hay destino anónimo que resolver.
>
> ✅ **`core.subscription.created_by` pasó a ser obligatorio** (decidido 2026-09-30, D13): toda suscripción exige cuenta. Cabo suelto: `subscription.email` (SUB-1) sigue permitiendo suscribir un correo distinto al de la cuenta, pero `notify` ya no recibe ningún email — solo `app_user_id` — así que esa función queda sin mecanismo de entrega hasta que se retome aparte.

## Una sola base PostgreSQL, cuatro esquemas

A diferencia de lo discutido antes (una base física por servicio), aquí los 4 esquemas viven en **una misma base PostgreSQL**: es lo realista con un proveedor gratuito que solo da una base por proyecto (Neon, Supabase…), y el aislamiento por **rol + esquema** cumple el mismo objetivo — cada servicio, con sus propias credenciales, solo ve y puede crear objetos en el suyo.

```bash
# 1) una sola vez, como admin de la base: crea los 4 esquemas y sus roles
psql "$ADMIN_DATABASE_URL" \
     -v auth_pw="'$AUTH_SERVICE_PASSWORD'" \
     -v core_pw="'$CORE_SERVICE_PASSWORD'" \
     -v schedule_pw="'$SCHEDULE_SERVICE_PASSWORD'" \
     -v notify_pw="'$NOTIFY_SERVICE_PASSWORD'" \
     -f provision-roles.sql

# 2) cada script, conectado con SU PROPIO rol (nunca con el admin)
psql "postgresql://auth_service:$AUTH_SERVICE_PASSWORD@host/db"     -f auth/schema.sql
psql "postgresql://core_service:$CORE_SERVICE_PASSWORD@host/db"     -f core/schema.sql
psql "postgresql://schedule_service:$SCHEDULE_SERVICE_PASSWORD@host/db" -f schedule/schema.sql
psql "postgresql://notify_service:$NOTIFY_SERVICE_PASSWORD@host/db" -f notify/schema.sql

# MongoDB: cada uno en SU PROPIA base (Mongo no tiene "esquema" — es la base misma)
mongosh "$CORE_MONGO_URL"     core/mongo-setup.js
mongosh "$SCHEDULE_MONGO_URL" schedule/mongo-setup.js
mongosh "$NOTIFY_MONGO_URL"   notify/mongo-setup.js
```

Cada repo (cuando exista) copia el script de su propia carpeta como primera migración de Alembic y sigue desde ahí; no vuelve a leer los de las otras carpetas, y se conecta **solo** con su propio rol.

## Pendiente

- Proveedor gratuito concreto y credenciales reales — [doc 09](../../09-pendientes.md), B1.
- Mecanismo exacto de la llamada `core` → `notify` (qué datos de la decisión viajan, y cómo `notify` confirma que el aviso quedó encolado) — doc 09, D6.
- Entrega confiable `core` → `notify` tras mover el outbox fuera de la transacción de `core` — doc 09, D12.
- Job que crea la partición anual siguiente de `price_snapshot` (`core/schema.sql` solo trae la partición del año en curso).
