# ADR 0002 · Despliegue y propiedad de datos: principios fijos y combinaciones de proveedores a costo $0

- **Estado:** Propuesta (borrador). Cada punto abierto lleva la marca **⏳ por cerrar**
- **Fecha:** 2026-11-25 · reescrito el 2026-11-26
- **Parte de:** el [ADR-0001](0001-repo-and-service-structure.md) (seis repos, cada uno dueño de sus datos), el [ADR-0004](0004-schedule-dispatches-work-to-scraper.md) y la [vista de despliegue](../general-architecture.md#vista-de-despliegue-servicios-desacoplados--cloudflare--gcp--oracle), que este ADR deja pendiente de actualizar
- **Requerimientos / casos de uso afectados:** INF-7, INF-8, INF-12, INF-13, INF-15, SCH-10, SCH-11, SCR-18 · pendientes A2, B1, B4, C1–C7
- **Alcance:** es diseño. INF-7 a INF-13 e INF-15 están [fuera de la versión actual](../../requirements/requirements.md), que corre solo en local

## Contexto

La primera redacción fijaba una sola topología. Se cambia por estas decisiones del usuario (2026-11-26):

1. **No nos casamos con un proveedor.** El ADR se divide en secciones para probar combinaciones, y **el costo $0 es el pilar principal**.
2. **Cloud Run sigue como candidato.**
3. **Cloud Scheduler queda fuera**, por la forma en que está programado `schedule`.
4. La cuenta de Oracle con la VM Ampere ya está creada.

**Cómo está programado `schedule`** (revisado en la copia local, rama `feat/INF-2-schedule-stubs`, sin comparar con `main`):

- `python -m schedule_service.worker` es un bucle continuo que llama a `engine.tick()` y, sin trabajo, espera 2 s.
- La agenda vive en la base de datos: ventanas de captura (por defecto 04:00–06:00 y 18:00–20:00) escalonadas por alerta, con plazos de callback, reservas y reintentos.
- Por eso **necesita un proceso siempre encendido**. Un servicio de Cloud Run que escala a cero no lo ejecuta. Una instancia encendida 24/7 con 1 vCPU son unos 2,6 millones de vCPU-segundos al mes, muy por encima de lo gratis.

⏳ **Por cerrar:** no se ha revisado cómo correrá el outbox de `notify`. Se asume que también necesita un proceso continuo.

## Cómo se lee este ADR

| Sección | Qué contiene | Cuándo cambia |
|---|---|---|
| 1 · Principios | Lo que toda combinación debe cumplir | Solo con una decisión nueva |
| 2 · Piezas intercambiables | Qué le exige el sistema a cada pieza | Cuando cambia el diseño |
| 3 · Catálogo | Límites gratis de cada proveedor | Cada vez que se vuelven a verificar |
| 4 · Combinaciones | Una ficha por combinación, con sus resultados | Con cada prueba |
| 5 · Evaluación | Cómo se aprueba o se descarta una combinación | Poco |

## 1 · Principios fijos

| # | Principio |
|---|---|
| P1 | **Costo $0.** Una combinación que genere un cobro queda descartada. Se declara por proveedor si pide tarjeta y si puede cobrar solo |
| P2 | **Portabilidad.** Imágenes OCI, configuración por variables de entorno y datos detrás de `DATABASE_URL` e interfaces. Cambiar de proveedor no cambia la lógica de negocio |
| P3 | **Ninguna petición sin autenticar.** El navegador entra solo por el Gateway. Cada servicio valida su JWT, aunque el proveedor ya filtre |
| P4 | **`schedule` sin ruta para usuarios** (SCH-11): solo acepta JWT de servicio |
| P5 | **Scraper aislado.** No tiene credenciales de base de datos ni comparte máquina con APIs, workers, bases o sus secretos. Conserva el anti-SSRF (SCR-18) y la lista blanca de callbacks |
| P6 | **La agenda es de `schedule`.** No depende de un programador externo como Cloud Scheduler |
| P7 | **Backups fuera del proveedor de la base**, cifrados, y nunca desde la máquina del scraper |
| P8 | **Despliegue reproducible y sin llaves de larga vida:** tags inmutables, despliegue por digest, secretos fuera del repo y federación de identidad en CI donde el proveedor la ofrezca |

### Regla de red · ⏳ por cerrar (C4)

Los documentos se contradicen: la vista detallada pasa las llamadas entre servicios por el Gateway, la vista mínima las dibuja directas y la redacción anterior de este ADR mezclaba ambas.

**Propuesta:**

- Todo lo que llega a un servicio **desde fuera de su proveedor** entra por el Gateway, que agrega una cabecera secreta. El servicio la exige además del JWT.
- Entre servicios **del mismo proveedor**, la llamada es directa y autenticada con JWT de servicio o con la identidad del proveedor (por ejemplo, IAM).
- El scraper no abre puertos de entrada: se publica por un túnel saliente con una credencial que solo tiene `schedule`.

## 2 · Piezas intercambiables

| Pieza | Lo que exige |
|---|---|
| `frontend` y Gateway | Archivos estáticos, enrutamiento por ruta y límite de tasa |
| APIs (`auth`, `core`, API de `schedule`, `notify`) | Contenedor sin estado. Puede escalar a cero |
| Workers (`schedule` y, por confirmar, outbox de `notify`) | **Proceso siempre encendido**, con acceso a las bases y salida hacia `core` y el scraper |
| Scraper | Contenedor con Chromium en una máquina o servicio propio, sin credenciales de base de datos (P5) |
| PostgreSQL | Compatible con PostgreSQL 16. **Una instancia, 4 esquemas y dos roles por esquema.** Debe aguantar el sondeo del worker |
| MongoDB | Una base y un usuario por servicio (`core`, `schedule`, `notify`). TTL de 90 días en `job_execution_result` |
| Backups | Disparador diario y almacenamiento cifrado con retención de 💡 7 días |
| Secretos | Almacén del proveedor o archivo con permisos `600` en la VM; nunca en el repo |
| Imágenes y CI | `amd64`, `arm64` o ambas según el host; registro con tags inmutables |
| Observabilidad | Sentry gratis y OpenTelemetry (INF-8), más una alerta si el scraper o un worker dejan de responder |

## 3 · Catálogo de proveedores

Verificado el **2026-11-26**. Los límites gratis cambian: se vuelven a revisar antes de aceptar una combinación.

**Evidencia:** 🟢 página oficial leída · 🟡 resultados de búsqueda, sin abrir la página · 💡 de memoria o estimado, sin verificar.

**Riesgo de cobro:** *bajo* = sin tarjeta, limita o suspende (💡 en todos los proveedores marcados así); *medio* = pide tarjeta y no cobra mientras la cuenta siga en *Always Free* (💡); *alto* = puede cobrar.

### Cómputo y borde

| Proveedor | Lo gratis | Avisos | Cobro | Ev. |
|---|---|---|---|---|
| Cloud Run (por petición) | 180.000 vCPU-s, 360.000 GiB-s y 2 millones de peticiones al mes | La facturación por instancia y los *worker pools* no quedaron verificados | Alto | 🟢 |
| GCP `e2-micro` | 1 VM en `us-west1`, `us-central1` o `us-east1`; 30 GB de disco | **1 GB de salida al mes** desde Norteamérica. IP externa sin costo: 🟡 | Alto | 🟢 |
| Oracle Ampere A1 | 1.500 OCPU-h y 9.000 GB-h al mes (2 OCPU y 12 GB), 200 GB de bloque, 10 TB de salida | `arm64`. Sujeta a la regla de inactividad (abajo) | Medio | 🟢 |
| Oracle `E2.1.Micro` | Hasta 2 VM: 1/8 de OCPU, 1 GB, 50 Mbps a internet | `amd64`, CPU muy limitada. Misma regla de inactividad | Medio | 🟢 |
| Azure Container Apps | 180.000 vCPU-s, 360.000 GiB-s y 2 millones de peticiones al mes | Alternativa a Cloud Run | Alto | 🟡 |
| Render | 750 horas de instancia al mes | Se duerme a los 15 min; su Postgres vence a los 30 días y no tiene backups | Bajo | 🟡 |
| Cloudflare Workers y estáticos | 100.000 peticiones diarias, 10 ms de CPU por petición; estáticos sin límite | Tunnel, Access y Cron Triggers sin verificar | Bajo | 🟡 |

> ⚠️ **Inactividad en Oracle:** una instancia se considera inactiva si en 7 días la CPU (percentil 95) y la red quedan por debajo del **20 %**, y en las A1 también la memoria. [Pendientes](../../00-context/pending.md) (C7) dice 10 %: está desactualizado.

### Datos

| Proveedor | Lo gratis | Avisos | Cobro | Ev. |
|---|---|---|---|---|
| Neon (PostgreSQL) | 100 CU-horas y 1 GB por proyecto | Se suspende a los 5 min sin actividad | Bajo | 🟡 |
| Supabase (PostgreSQL) | 500 MB, 5 GB de salida, 2 proyectos activos | Se pausa tras 1 semana sin actividad. *Pooler* IPv4 sin verificar | Bajo | 🟡 |
| Aiven (PostgreSQL) | 1 GB de disco, 1 GB de RAM, 1 CPU | Las fuentes se contradicen sobre el apagado por inactividad; límite de conexiones sin dato | Bajo | 🟡 |
| MongoDB Atlas (clúster gratis) | Unos 512 MB; un clúster por proyecto | Se pausa tras 30 días sin conexiones; **sin backups** | Bajo | 🟡 |

> ⚠️ **El sondeo del worker condiciona la base.** Con un worker que consulta cada 2 s, Neon no llega a suspenderse. Con un cómputo mínimo de 0,25 CU (💡), 100 CU-horas son unas 400 horas activas y el mes tiene 730. **Neon queda en pausa como candidato mientras el worker sondee así.**
> En Supabase, 💡 los cerca de 1,3 millones de ciclos al mes moverían de 1 a 4 GB de los 5 GB de salida. No se ha medido.

### Imágenes, secretos y backups

| Proveedor | Lo gratis | Avisos | Ev. |
|---|---|---|---|
| GitHub Actions y GHCR | Runners estándar gratis en repos públicos; GHCR «gratis por ahora» | La cuota para repos privados no quedó clara | 🟡 |
| Artifact Registry | 0,5 GB al mes | — | 🟢 |
| GCP Secret Manager | 6 versiones activas y 10.000 accesos al mes | 💡 No alcanzan para todos los secretos | 🟢 |
| Cloud Storage | 5 GB, solo en regiones de EE. UU. | — | 🟢 |
| Oracle Object Storage | 20 GB | — | 🟢 |

**Fuera del catálogo para producción:** Fly.io y Railway (💡 sin plan gratis permanente), las máquinas de AWS (💡 el gratis de cuentas nuevas vence) y Koyeb mientras no se verifique.

**Fuentes:** [Oracle Always Free](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm) · [Google Cloud Free Tier](https://docs.cloud.google.com/free/docs/free-cloud-features) · [Compute free tier](https://cloud.google.com/free/docs/compute-getting-started) · [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/billing) · [Render](https://render.com/docs/free) · [Neon](https://neon.com/docs/introduction/limits) · [Supabase](https://supabase.com/pricing.md) · [Aiven](https://aiven.io/docs/products/postgresql/concepts/pg-free-tier) · [Atlas, límites](https://www.mongodb.com/docs/atlas/reference/free-shared-limitations/) · [Atlas, pausa](https://www.mongodb.com/docs/atlas/pause-terminate-cluster/) · [Cloudflare Workers](https://developers.cloudflare.com/workers/platform/limits) · [GitHub Actions](https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions) · [GitHub Packages](https://docs.github.com/en/billing/concepts/product-billing/github-packages)

## 4 · Combinaciones a probar

Son **propuestas** (⏳). Ninguna está validada ni desplegada. Se numeran y no se reutilizan: una descartada conserva su ficha y el motivo.

| Pieza | A · principal | B · workers en Oracle | C · preview |
|---|---|---|---|
| `frontend` y Gateway | Cloudflare | Cloudflare | Cloudflare |
| APIs | Cloud Run | Cloud Run | Render |
| Workers | GCP `e2-micro` | Oracle `E2.1.Micro` | Sin resolver |
| Scraper | Oracle Ampere | Oracle Ampere | Oracle Ampere |
| PostgreSQL | Supabase | Supabase | Neon |
| MongoDB | Atlas gratis | Atlas gratis | Atlas gratis |
| Arquitecturas | `amd64` y `arm64` | `amd64` y `arm64` | `amd64` y `arm64` |

**Región:** Cloud Run, la VM de workers y las bases van en la misma región de EE. UU. o en la más cercana. ⏳ Por cerrar, junto con la región de la Ampere.

### Combinación A · principal

- **A favor:** el scraper queda en otra nube que las bases y los workers; no depende de la CPU de la Micro de Oracle.
- **En contra:** GCP exige facturación y puede cobrar. Una alerta de presupuesto avisa, pero no frena el gasto.
- **Por validar antes de crear nada:** que el tráfico del worker quepa en 1 GB de salida (`e2-micro`) y en 5 GB (Supabase).
- **Si no cabe:** se reduce el sondeo o el worker duerme hasta la siguiente ejecución (requiere código y decidir cómo despierta si llega un job antes), o se cambia de base o de host.

### Combinación B · workers en Oracle

- **A favor:** 10 TB de salida en la cuenta de Oracle y menor riesgo de cobro en el host del worker.
- **En contra:** 1/8 de OCPU; el worker y el scraper comparten cuenta, y por tanto riesgo de suspensión o recorte; el worker casi ocioso puede caer en la regla de inactividad. La salida de Supabase sigue aplicando.
- **Por validar:** que el worker corra holgado en 1/8 de OCPU y 1 GB, y que ambas máquinas estén en redes separadas (P5).

### Combinación C · preview

- Solo para demos y ramas. **No es producción:** sin workers, el sistema no corre solo (SCH-10).
- El Blueprint de Render de `foundit-web-app` cabe aquí.

### Variante · scraper en Cloud Run

Se activa si la Ampere falla o si Oracle recorta más lo gratis. Hay que medir antes la memoria y el arranque en frío de Chromium. Gracias al callback configurable y la lista blanca, el cambio no toca a `schedule`.

### Descartadas

| Combinación | Por qué no |
|---|---|
| Todo en la VM Ampere | Rompe P5: el componente que procesa contenido no confiable conviviría con las bases y los secretos. Es además un solo punto de falla |
| Workers en Cloud Run siempre encendidos | Rompe P1: supera lo gratis |
| Cloud Scheduler llamando a un endpoint de tick | Rompe P6 (decisión del usuario) |
| Postgres de Render | 🟡 Vence a los 30 días |
| Postgres en la VM del scraper | Rompe P5 |
| Abrir el puerto del scraper por firewall | Deja un puerto expuesto, y Cloud Run 💡 no tiene IP de salida fija sin pagar |
| Load Balancer con Cloud Armor | 💡 Costo fijo mensual (P1) |

## 5 · Cómo se evalúa una combinación

**La descartan:** cualquier cobro, o incumplir un principio.

| Criterio | Cómo se mide | Umbral (💡 propuesto) |
|---|---|---|
| Costo | Factura real tras 30 días | $0,00 |
| Cuotas | Consumo de cada límite en esos 30 días | Menos del 70 % |
| Memoria | Pico por contenedor, con Chromium activo | Menos del 80 % de la asignada |
| Arranque en frío | Primera petición a `auth` y `core` | Por fijar |
| Agenda | Capturas ejecutadas dentro de su ventana | Todas |
| Seguridad | P3–P5, P7 y P8 comprobados uno por uno | Todos |
| Operación | Pasos manuales para desplegar y recuperar | Por fijar |

**Resultados:**

| Combinación | Estado | Costo | Cuota más alta | Notas |
|---|---|---|---|---|
| A | Sin probar | — | — | — |
| B | Sin probar | — | — | — |
| C | Sin probar | — | — | — |

## Reglas comunes de datos, imágenes y operación

- **Datos:** TLS obligatorio, un usuario por servicio con mínimo privilegio y contraseñas rotadas. Donde el host tenga IP fija, se agrega la lista de IP permitidas; donde no, queda como riesgo aceptado.
- **Backups:** `pg_dump` y `mongodump` diarios y cifrados. ⏳ El disparador (cron en el host del worker o workflow programado de GitHub Actions) y el destino se deciden por combinación; ambos disparadores requieren revisar qué credenciales de base de datos quedan expuestas. Necesita un ID de requerimiento (candidato `INF-16`, por asignar).
- **Imágenes:** `docker buildx` para la arquitectura de cada host. La imagen `arm64` del scraper se prueba en `arm64` antes de publicarse (C2). Se despliega por digest, nunca con `latest`.
- **VMs:** sin puertos de entrada abiertos a internet; contenedores sin root, con `cap_drop: ALL`, `no-new-privileges` y límites de recursos. El contenedor del scraper no puede alcanzar el endpoint de metadata de la VM.
- **Credencial del scraper:** ⏳ falta definir cómo obtiene su JWT de servicio para el callback. Propuesta: credencial de cliente emitida por `auth`, guardada en la VM con permisos `600`.

## Consecuencias

- **Positivas:** cambiar de proveedor es cambiar una ficha, no reabrir el ADR; cada límite queda con fecha y nivel de evidencia; las pruebas son comparables.
- **Negativas / costo:** hay que mantener el catálogo al día; probar varias combinaciones toma más tiempo; A y B obligan a operar al menos cuatro proveedores y dos arquitecturas; la regla de red propuesta requiere código para validar la cabecera del Gateway.
- **Riesgos:**

  | Riesgo | Mitigación |
  |---|---|
  | Un proveedor recorta o elimina lo gratis (Oracle ya recortó la A1) | P2, backups fuera del proveedor y combinaciones alternativas documentadas |
  | Oracle recupera máquinas inactivas | Alerta de disponibilidad y la variante del scraper en Cloud Run. Pasar a *pay-as-you-go* 💡 evitaría la recuperación, pero abre la puerta a cobros: **lo decide el usuario** |
  | Cobro inesperado en un proveedor de riesgo alto | Alertas de presupuesto, límites de instancias y revisión de la factura |
  | Se filtra el secreto del Gateway | No basta solo: cada servicio sigue exigiendo su JWT (P3). Se rota |

## Qué falta

**Propuesta de aceptación (⏳):** aceptar el ADR cuando se aprueben los principios, la regla de red y los criterios. Cada combinación se valida después en su ficha, sin reabrir el ADR. Reemplaza la condición anterior de cerrar antes B1, C1, C3 y C4.

| Punto | Qué hay que hacer | Quién |
|---|---|---|
| Aceptación | Aprobar los principios, la regla de red (C4) y los criterios | Usuario |
| Medición previa | Medir en local los bytes que mueve el worker en reposo | Yonko prepara, usuario aprueba |
| B1 | Completar la verificación (🟡 y 💡), y elegir base y región | Yonko investiga, usuario decide |
| C1 | Cuenta creada. Confirmar que la instancia Ampere está aprovisionada, su región y el tipo de cuenta | Usuario |
| C2 | Imagen `arm64` del scraper y su prueba | Yonko prepara, usuario aprueba |
| C3 | Medir la RAM del scraper con Chromium en la VM | Yonko prepara el script, usuario lo corre |
| `notify` | Revisar cómo correrá su outbox | Yonko |
| Documentos | Actualizar `general-architecture.md`, pendientes (A2, C7 y «Ya decidido», que aún fija Cloud Run) y los demás que describen la topología anterior | technical-writer, con aprobación |
| Requerimientos | ID para el backup | requirements-analyst, usuario aprueba |
| C6 | Reescribir INF-15 | technical-writer, después de aceptar |
