# ADR 0002 · Despliegue y propiedad de datos: Cloudflare como única puerta, APIs en Cloud Run, scraper en Oracle y bases gestionadas

- **Estado:** Propuesta (borrador). No se acepta hasta cerrar B1, C1, C3 y C4 de [pendientes](../../00-context/pending.md). Cada punto abierto lleva la marca **⏳ por cerrar**
- **Fecha:** 2026-11-25
- **Parte de:** la [vista de despliegue](../general-architecture.md#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle) (dirección ya aprobada) y el [ADR-0001](0001-repo-and-service-structure.md) (seis repos, cada uno dueño de sus datos)
- **Requerimientos / casos de uso afectados:** INF-7, INF-8, INF-12, INF-13, INF-15, SCH-10, SCH-11, SCR-18 · pendientes A2, B1, B4, C1–C7

> **Cifras de proveedores:** los límites de los planes gratis (cuotas, RAM, vencimientos) están marcados con 💡. Salvo los de Oracle (verificados el 2026-10-01 en C7), son de memoria y **se verifican en la página oficial de cada proveedor antes de aceptar este ADR**.

## Contexto

La vista de despliegue ya fija la dirección: Cloudflare delante, `auth`/`core`/`schedule`/`notify` en GCP Cloud Run, el scraper solo en la VM Ampere de Oracle y las bases en un proveedor gestionado gratuito, con presupuesto $0. Faltaba cerrar cuatro cosas que la vista deja abiertas, y al revisar el código apareció una quinta:

1. **Dónde viven las bases (B1).** Ningún proveedor está elegido, y ninguno de los planes gratis trae backups (B4).
2. **Cómo se restringe la red (C4).** `schedule` no debe tener ruta pública (SCH-11) y el scraper solo debe ser alcanzable desde `schedule`, pero el mecanismo no está definido.
3. **La VM de Oracle (C1, C3, C7).** Hay que crearla, medir la RAM del scraper con Chromium y convivir con que Oracle ya recortó el *Always Free* una vez y detiene instancias inactivas.
4. **Imágenes en dos arquitecturas (C2).** Cloud Run corre `amd64` y la Ampere `arm64`.
5. **Nuevo: los workers no corren en Cloud Run.** `schedule` tiene un proceso aparte (`python -m schedule_service.worker`) que llama a `engine.tick()` cada 2 s, y `notify` tendrá un worker del outbox. Cloud Run escala a cero y solo da CPU mientras atiende una petición: un bucle `while True` sin peticiones no se ejecuta.

Además hay una deriva: [pendientes](../../00-context/pending.md#ya-decidido-para-no-reabrir-sin-motivo) fija el frontend en Cloudflare Workers Static Assets, pero `foundit-web-app` ya trae un Blueprint de Render (`deploy/render/render.yaml`).

## Decisión

### 1 · Topología (confirma la dirección aprobada)

| Pieza | Dónde | Arquitectura | Cómo se alcanza |
|---|---|---|---|
| `frontend` | Cloudflare Workers Static Assets | — | Público, por Cloudflare |
| Gateway | Cloudflare Worker | — | Público; enruta `/auth/*` y `/api/*` |
| `auth`, `core` | Cloud Run | `amd64` | Solo desde el Gateway (ver §3) |
| `schedule` | Cloud Run | `amd64` | Solo con JWT de servicio, sin ruta en el Gateway para usuarios (SCH-11) |
| `notify` | Cloud Run | `amd64` | Solo desde cuentas de servicio de GCP (IAM) |
| `scraper` | VM Ampere A1 de Oracle (Always Free) | `arm64` | Solo por Cloudflare Tunnel, con token de servicio |
| PostgreSQL, MongoDB | Proveedor gestionado gratuito (§4) | — | Solo desde `auth`/`core`/`schedule`/`notify`, con TLS; **nunca** desde la VM del scraper |

**Región única** para Cloud Run y las bases, para no pagar latencia en cada consulta. 💡 Propuesta: `us-east1` o `us-central1` (están en el nivel gratis de Cloud Run). ⏳ **Por cerrar:** confirmar que Neon y Atlas ofrecen la misma región o una vecina.

**Render no es producción.** El Blueprint de `foundit-web-app` queda como **preview** del frontend (ramas o demos). Producción va en Cloudflare, como está decidido.

### 2 · Workers: de bucle a petición agendada

- `schedule` expone **`POST /schedule/internal/tick`**. Llama a `engine.tick()` y repite mientras haya trabajo, dentro de un presupuesto de tiempo (💡 50 s), igual que hoy el bucle de `worker.py`.
- **Cloud Scheduler** la invoca **cada minuto** con un token OIDC de una cuenta de servicio propia. Cloud Run solo acepta esa identidad en esa ruta (rol `run.invoker`).
- `notify` hace lo mismo con **`POST /notify/internal/outbox/drain`**.
- **`worker.py` se mantiene** para docker-compose local: los dos caminos llaman a la misma función, así que no hay lógica duplicada.
- Los ticks pueden solaparse sin romper nada: el motor ya toma el trabajo con `FOR UPDATE SKIP LOCKED`.
- 💡 Se usan 2 jobs de Cloud Scheduler (3 si se suma el backup de §4); el plan gratis cubre 3 por cuenta.

### 3 · Red y entrada (cierra C4)

- **Cloudflare es la única puerta pública.** Los servicios que reciben tráfico de fuera de GCP validan, además de su JWT, una **cabecera secreta que pone el Gateway**. Así una llamada directa a la URL `*.run.app` se rechaza aunque sea pública a nivel de Cloud Run. El secreto vive en Secret Manager y en el Worker, y se rota.
- **`notify` es solo IAM** (`--no-allow-unauthenticated`): todos sus llamadores (`auth`, `core`, `schedule`, Cloud Scheduler) están en GCP y usan su cuenta de servicio. No necesita cabecera ni ruta en el Gateway.
- **`schedule`** recibe de `core` y Cloud Scheduler (dentro de GCP) y el callback del scraper (fuera de GCP). Por eso queda público a nivel de Cloud Run, pero **todas** sus rutas exigen JWT de servicio (`aud=system`). El callback del scraper entra por el Gateway, que lo deja pasar solo a `/schedule/internal/results`.
- **La VM de Oracle no abre ningún puerto de entrada.** En la *security list* solo queda la salida, y `cloudflared` crea un túnel saliente que publica el scraper en un hostname interno. Ese hostname exige un **token de servicio de Cloudflare Access** que solo tiene `schedule`. SSH solo por el túnel o por Oracle Cloud Shell, nunca abierto a internet.
- **El scraper sigue sin credenciales de base de datos** y conserva su anti-SSRF (SCR-18) y la lista blanca de callbacks ([ADR-0004](0004-schedule-dispatches-work-to-scraper.md)).
- ⏳ **Por cerrar (bloque D):** cómo obtiene el scraper su JWT de servicio para el callback. Propuesta: credencial de cliente emitida por `auth` y guardada en la VM con permisos `600`.

### 4 · Datos y backups (cierra B1 y B4)

- **PostgreSQL: Neon** (recomendado), una base con los 4 esquemas y dos roles por esquema, como está decidido. Neon se elige por la compatibilidad con PostgreSQL 16, la separación por ramas (útil para preview) y porque el plan gratis no vence. Contrapartida: 💡 0,5 GB y suspensión por inactividad (el primer acceso tras la pausa tarda más). Plan B: Supabase.
- **MongoDB: Atlas M0**, un clúster con **una base y un usuario por servicio** (`core`, `schedule`, `notify`). Cada usuario solo ve su base, lo que mantiene la propiedad de datos del ADR-0001 sin tres clústeres. 💡 512 MB. El TTL de 90 días de `job_execution_result` sigue siendo lo que lo hace caber.
- **Lista de IP permitidas:** Cloud Run no tiene IP de salida fija sin pagar un NAT, así que el control es **TLS obligatorio + usuario por servicio + contraseña fuerte rotada**. Se documenta como riesgo aceptado (abajo).
- **Backups:** un **Cloud Run Job** nocturno (`pg_dump` + `mongodump`) disparado por Cloud Scheduler, que sube un archivo cifrado a Cloud Storage con retención de 💡 7 días. Necesita un ID de requerimiento (candidato `INF-16`, por asignar en `requerimientos.md`). **No corre en la VM de Oracle**, porque esa VM procesa contenido no confiable y no debe tener credenciales de base de datos.
- ⏳ **Por cerrar (B1):** verificar los límites actuales de Neon y Atlas y que el volumen de B3 cabe.

### 5 · Imágenes, registro y CD (avanza INF-12 e INF-13)

- GitHub Actions construye con `docker buildx`: **`amd64`** para los servicios de Cloud Run y **`arm64`** para el scraper. Esa imagen se prueba en un runner `arm64` o con QEMU antes de publicarse (C2).
- **Registro:** Artifact Registry para las imágenes de Cloud Run (💡 0,5 GB gratis) y GHCR para el scraper, que la VM descarga con un token de solo lectura.
- **Tags inmutables** con el SHA del commit; se despliega **por digest**, nunca con `latest`.
- **Sin llaves JSON de GCP en GitHub:** Workload Identity Federation, con una cuenta de servicio de despliegue por repo y el mínimo de roles.
- **En la VM**, el scraper corre con docker compose bajo los mismos límites de la vista local (usuario no root, `cap_drop: ALL`, `no-new-privileges`, 💡 1 GB y 1 CPU hasta medir C3). Se actualiza descargando el digest nuevo, primero a mano y luego con un paso del CD por el túnel.
- **Secretos:** Secret Manager para Cloud Run. 💡 Si se supera el gratis (versiones activas), el costo es de centavos y requiere aprobación.

### 6 · Observabilidad

Sin cambios respecto a INF-8: Sentry gratis y OpenTelemetry. Los logs de Cloud Run van a Cloud Logging (💡 50 GB/mes gratis) y los del scraper salen por Sentry/OTel. **Alerta mínima:** un *uptime check* contra `/scraper/health` por el túnel, porque una VM detenida por Oracle debe avisar el mismo día y no esperar al barrido diario.

## Alternativas descartadas

| Alternativa | Por qué no |
|---|---|
| **Todo en Render** (servicios web + Postgres + workers) | 💡 Los servicios gratis se duermen tras ~15 min y tardan en despertar; los *background workers* y *cron jobs* no tienen plan gratis; 512 MB no alcanzan para Chromium; el Postgres gratis vence. Sirve para preview, no para que el sistema corra solo (SCH-10) |
| **Todo en la VM de Oracle** (la topología antigua de INF-15) | Un solo punto de falla sujeto a C7, y la pieza que procesa contenido no confiable conviviría con las bases y los secretos: se rompe el aislamiento del scraper |
| **Workers con `min-instances=1`** en Cloud Run | Deja de ser gratis por cada servicio con worker. El tick agendado logra lo mismo a costo cero |
| **Load Balancer + Cloud Armor** para restringir la entrada a Cloudflare | 💡 El balanceador tiene costo fijo mensual; la cabecera del Gateway más el JWT y el IAM dan el mismo efecto sin costo |
| **Abrir el puerto del scraper** por firewall a las IP de `schedule` | Cloud Run no tiene IP de salida fija sin NAT de pago; además deja un puerto expuesto. El túnel no expone nada |
| **Postgres de Render o en un contenedor de la VM** | El primero vence; el segundo mete credenciales de base de datos en la VM del scraper |

**Plan B, no descartado: scraper en Cloud Run** (`amd64`, 💡 2 GiB). Con 2 capturas al día y URLs secuenciales, el volumen es bajo y podría caber en el nivel gratis. Se activa si C1 falla (sin capacidad en Oracle) o si C7 empeora. El costo es medir el arranque en frío de Chromium y perder la VM dedicada. Gracias al callback configurable y la lista blanca, el cambio no toca a `schedule`.

## Consecuencias

- **Positivas:**
  - Costo $0 con cada pieza escalando por separado.
  - Ningún origen queda expuesto directo a internet.
  - El scraper queda aislado de datos y secretos.
  - Los workers corren sin servidor siempre encendido.
  - Los despliegues son reproducibles por digest y no hay llaves de larga vida en CI.
- **Negativas / costo:**
  - **Hay que cambiar código:** endpoints de tick en `schedule` y de drain en `notify`, validación de la cabecera del Gateway en `auth`/`core`/`schedule` y la credencial de servicio del scraper.
  - **CI con dos arquitecturas.**
  - **Operar dos nubes más Cloudflare**, con sus cuentas y alertas.
  - **Más espera entre URLs.** El envío secuencial del ADR-0004 queda atado al tick: si el callback de una URL no dispara la siguiente, cada URL espera hasta el próximo tick (≤ 1 min). Con el volumen previsto es aceptable. Si molesta, el callback puede llamar a `engine.tick()` al terminar.
- **Riesgos y cómo se mitigan:**

  | Riesgo | Mitigación |
  |---|---|
  | Oracle detiene la VM por inactividad o recorta más el Always Free (C7). El scraper pasa casi todo el día ocioso, por debajo del umbral de 10 % de CPU | *Uptime check* diario, plan B en Cloud Run listo. Pasar la cuenta a *pay-as-you-go* evita la recuperación por inactividad, pero exige tarjeta: **lo decide el usuario** |
  | Sin capacidad de Ampere en la región (C1) | Probar otra región de origen al crear la cuenta; si no, plan B |
  | Bases sin lista de IP permitidas | TLS obligatorio, usuario por servicio con mínimo privilegio, contraseñas en Secret Manager rotadas, alertas de conexiones del proveedor |
  | Neon o Atlas se suspenden o cambian sus límites | Backups nocturnos fuera del proveedor; el acceso a datos va detrás de interfaces y de `DATABASE_URL`, así que se cambia de proveedor sin tocar código |
  | Arranque en frío de `auth` (C5) | Se mide; `min-instances=1` solo con aprobación |
  | Se filtra el secreto del Gateway | No basta solo: cada servicio sigue exigiendo su JWT. Se rota |

## Qué falta para aceptarlo

| Punto | Qué hay que hacer | Quién |
|---|---|---|
| C1 | Crear la cuenta de Oracle y la VM Ampere | Usuario (crea la cuenta y acepta los términos) |
| C2 | Dockerfile multi-arch del scraper y prueba en `arm64` | Yonko prepara, usuario aprueba |
| C3 | Medir la RAM del scraper con Chromium en la VM | Yonko prepara el script, usuario lo corre en la VM |
| B1 | Verificar los límites de Neon y Atlas y elegir región | Yonko investiga, usuario decide |
| C4 | Aprobar el esquema de §3 (o ajustarlo) | Usuario |
| Requerimientos | IDs para el endpoint de tick y el drain del outbox, y para el backup (`INF-16`) | requirements-analyst, usuario aprueba |
| C6 | Reescribir INF-15 con esta topología | technical-writer, después de aceptar |
