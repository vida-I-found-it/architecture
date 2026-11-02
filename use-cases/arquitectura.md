# Arquitectura · Seguimiento diario del precio de un producto por scraping

El sistema vigila el precio de un producto en varias tiendas. El usuario registra las páginas y un correo; el sistema las scrapea de forma programada, guarda y analiza el historial, lo muestra en un dashboard y avisa por correo cuando baja el mejor precio. Se construye como cuatro piezas independientes más un frontend, que se comunican por REST.

## Tabla de contenido

1. [Piezas](#piezas)
2. [Vista de componentes](#vista-de-componentes)
3. [Flujo por casos de uso](#flujo-por-casos-de-uso)
4. [Comunicación entre piezas](#comunicación-entre-piezas)
5. [Decisiones de arquitectura](#decisiones-de-arquitectura)
6. [Atributos de calidad](#atributos-de-calidad)

---

## Piezas

| Pieza | Responsabilidad | Persistencia | API |
|---|---|---|---|
| **Frontend** | Pantallas de alta de alerta, lista, dashboard y baja | Ninguna | Consume la de `core` |
| **`core`** | Alertas, suscripciones, precios, análisis y pedido de aviso | PostgreSQL | Pública y entre piezas |
| **`schedule`** | Motor de jobs genérico: agenda, dispara y entrega el resultado | PostgreSQL y MongoDB | Solo entre piezas |
| **`scraper`** | Descarga las URLs y extrae el precio | Ninguna | No expone: consulta a `schedule` |
| **`notify`** | Arma y envía el email, y reintenta si falla | PostgreSQL | Solo entre piezas |

## Vista de componentes

```mermaid
flowchart LR
    FE[Frontend] -->|REST| CO[core]
    CO -->|crea y consulta jobs| SC[schedule]
    SR[scraper] -->|pide trabajo y entrega el resultado| SC
    SC -->|detalle del job y callback de precios| CO
    CO -->|pide el aviso| NT[notify]
    NT -->|SMTP| MX[Servidor de correo]
    CO --- DC[(PostgreSQL core)]
    SC --- DS[(PostgreSQL schedule)]
    SC --- DM[(MongoDB resultados)]
    NT --- DN[(PostgreSQL notify)]
```

## Flujo por casos de uso

Cada recuadro es un caso de uso.

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant FE as Frontend
    participant CO as core
    participant SC as schedule
    participant SR as scraper
    participant NT as notify
    participant PG as PostgreSQL

    rect rgba(70, 130, 220, 0.14)
        Note over U,PG: CU-02 · Registrar la alerta
        U->>FE: elige el modo URL, pega 1..N URLs y escribe el correo
        FE->>CO: crea la alerta (tras el modal de confirmación)
        CO->>CO: valida y sanea (URLs anti-SSRF, correo)
        CO->>PG: guarda alerta, URLs y suscripción
    end

    rect rgba(60, 170, 120, 0.14)
        Note over CO,SC: CU-03 · Programar la captura
        CO->>SC: crea el job con su callback
        SC->>SC: dispara el job a su hora
    end

    rect rgba(70, 130, 220, 0.14)
        Note over SC,SR: CU-04 · Capturar el precio
        SR->>SC: pull de trabajo
        SC->>CO: pide el detalle del job (las URLs de la alerta)
        SR->>SR: descarga cada URL (anti-SSRF) y prueba estrategias hasta obtener el precio
        SR->>SC: reporta estado y resultado
    end

    rect rgba(60, 170, 120, 0.14)
        Note over SC,PG: CU-05 · Procesar y almacenar
        SC->>CO: callback con los precios (si falla, su outbox reintenta)
        CO->>CO: normaliza y valida
        CO->>PG: guarda el snapshot solo si cambia
    end

    rect rgba(70, 130, 220, 0.14)
        Note over CO,PG: CU-06 · Analizar el mejor precio
        CO->>PG: actualiza el mejor precio y marca anomalías
    end

    rect rgba(150, 90, 200, 0.14)
        Note over CO,U: CU-10 · Notificar al correo registrado
        CO->>NT: llamada REST que crea la notificación (destino = correo de la suscripción)
        NT->>NT: crea la notificación y arma el email con su enlace de baja
        NT-->>U: envía el email (si falla, su outbox reintenta)
    end

    rect rgba(150, 90, 200, 0.14)
        Note over U,PG: CU-11 · Darse de baja de una alerta
        U->>FE: abre el enlace de baja del email y confirma
        FE->>CO: confirma la baja
        CO->>PG: marca la suscripción como unsubscribed
    end

    rect rgba(220, 150, 50, 0.14)
        Note over U,PG: CU-07 y CU-08 · Dashboard
        U->>FE: abre la alerta
        FE->>CO: pide detalle, último precio e histórico
        CO->>PG: lee
        CO-->>FE: datos
        FE-->>U: último precio por sitio, mejor precio, histórico y comparador
    end
```

## Comunicación entre piezas

| De → a | Operación y ruta | Para qué |
|---|---|---|
| Frontend → `core` | `POST /api/alerts` | Crear la alerta con sus URLs y su correo |
| Frontend → `core` | `GET /api/alert-modes` | Saber qué modos de creación están habilitados |
| Frontend → `core` | `GET /api/alerts` | Listar las alertas |
| Frontend → `core` | `GET /api/alerts/{alert_id}` | Ver el detalle y el último precio por sitio |
| Frontend → `core` | `GET /api/alerts/{alert_id}/price-history` | Histórico y comparador |
| Frontend → `core` | `POST /api/subscriptions/{subscription_id}/unsubscribe` | Darse de baja |
| `core` → `schedule` | `POST /schedule/internal/jobs` | Crear el job de la alerta |
| `core` → `schedule` | `GET /schedule/internal/jobs/{job_id}` | Consultar un job |
| `scraper` → `schedule` | `POST /schedule/internal/pull` | Pedir trabajo y entregar el resultado |
| `schedule` → `core` | `GET /api/internal/job-detail` | Obtener las URLs de la alerta |
| `schedule` → `core` | `POST /api/internal/prices` | Entregar los precios capturados |
| `core` → `notify` | `POST /notify/notifications` | Pedir el aviso por correo |

## Decisiones de arquitectura

- **REST con JSON** entre todas las piezas, y un contrato Swagger (OpenAPI) por pieza que expone endpoints.
- **Cada pieza es dueña de sus datos:** su propia base, sin claves foráneas hacia otra pieza; se enlazan solo por identificadores.
- **El scraper nunca llama a `core`:** pregunta a `schedule` si hay trabajo y le entrega el resultado, que `schedule` reenvía a `core`.
- **Cada pieza reintenta lo suyo:** `schedule` reintenta el callback y `notify` el envío del email, cada una con su cola de reintentos. `core` reintenta la llamada a `notify` con el mismo identificador de transacción.
- **Idempotencia por llaves únicas:** repetir una corrida, un callback o un aviso no duplica datos.
- **Estrategias reemplazables:** la forma de crear una alerta, la extracción del precio y el canal de notificación van detrás de interfaces, para cambiarlos sin tocar el resto.
- **Sin autenticación ni autorización:** la versión corre solo en local, sin sesión ni token entre piezas.
- **Scraping sin eludir protecciones:** si una tienda no permite scrapear, ese sitio queda sin precio.

## Atributos de calidad

| Atributo | Cómo se logra |
|---|---|
| Seguridad | Las URLs se validan contra direcciones peligrosas al crear la alerta y en cada descarga; todo texto se sanea; lo scrapeado se trata como dato; el correo se muestra enmascarado |
| Confiabilidad | Reintentos por pieza; una URL que falla no frena a las demás; un fallo al avisar no revierte el análisis |
| Mantenibilidad | Piezas desacopladas, servicios detrás de interfaces, un repositorio por entidad y migraciones por pieza; el mismo identificador de transacción acompaña una corrida en todas las piezas y en los logs, para diagnosticar fallos |
| Rendimiento | Solo se guarda un snapshot cuando el precio o el stock cambian; la captura ocurre en segundo plano, no dentro de una petición; bloqueos de fila acotados y sin consultas repetidas |
