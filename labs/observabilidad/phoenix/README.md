# labs · Claude Agent SDK + Arize Phoenix — orquestación de agentes con vista gráfica

> **Estado: plan inicial.** No hay código, ni dependencias instaladas, ni contenedores levantados. Todo comando de este documento está marcado como **propuesto**: se ejecuta solo con aprobación del usuario en el chat (ver [`.claude/rules/agent-policies.md`](../../../.claude/rules/agent-policies.md)).
> Lo que no está verificado contra la documentación oficial se marca con ⚠️.

## Tabla de contenido

- [1 · Objetivo](#1--objetivo)
  - [1.1 · Herramientas que vamos a usar](#11--herramientas-que-vamos-a-usar)
  - [1.2 · Serie de laboratorios y criterios de comparación](#12--serie-de-laboratorios-y-criterios-de-comparación)
- [2 · Qué deberíamos tener (entregables por fase)](#2--qué-deberíamos-tener-entregables-por-fase)
- [3 · Cómo se orquesta (diseño)](#3--cómo-se-orquesta-diseño)
- [4 · Estructura propuesta de la carpeta](#4--estructura-propuesta-de-la-carpeta)
- [5 · Requisitos previos](#5--requisitos-previos)
- [6 · Cómo se ejecuta y cómo se levanta](#6--cómo-se-ejecuta-y-cómo-se-levanta-propuesto-no-ejecutado)
- [7 · Seguridad y reglas que aplican](#7--seguridad-y-reglas-que-aplican)
- [8 · Decisiones y preguntas abiertas](#8--decisiones-y-preguntas-abiertas)
- [9 · Referencias](#9--referencias)

## 1 · Objetivo

Orquestar los agentes de `.claude/agents/` (`requirements-analyst` → `architect` → `backend-developer` / `frontend-developer` → `qa` → `security-reviewer` → `technical-writer`) con el **Claude Agent SDK (Python)**, con compuertas humanas entre etapas y una **vista gráfica en vivo** de lo que hace cada agente.

Fuera de alcance por ahora: commits, push o PR automáticos (siempre los decide el usuario), despliegues, servicios de nube.

### 1.1 · Herramientas que vamos a usar

| Herramienta | Para qué | Fase | Versión / estado | Instalación |
|-------------|----------|------|------------------|-------------|
| **Claude Agent SDK (Python)** (`claude-agent-sdk`) | Es el framework: ejecuta cada agente desde código, con permisos, hooks y compuertas | 1 | ⚠️ por fijar | `pip` en entorno virtual; **requiere aprobación** |
| **Claude Code** (suscripción) | Motor que el SDK usa por debajo y fuente de los agentes de `.claude/agents/` | 1 | Ya instalado | Ninguna |
| **Python 3 + `venv`** | Entorno aislado del orquestador | 1 | ⚠️ versión por definir | Ya disponible en el equipo; ⚠️ confirmar versión |
| **OpenTelemetry nativo del SDK** | Fuente de la telemetría: trazas, tokens, costo y subagentes (trazas en **beta**) | 2 | Viene con el SDK | Solo variables de entorno |
| **Arize Phoenix** (imagen Docker `arizephoenix/phoenix`) | **Vista gráfica de trazas**: árbol agente → herramienta → subagente, con tokens y tiempos. Es la herramienta principal para "ver" a los agentes trabajar | 2 | ⚠️ versión por fijar | Contenedor desechable; **requiere aprobación** |
| **Docker** | Ejecuta Phoenix aislado y desechable | 2 | ⚠️ confirmar que está instalado | Ya instalado, ⚠️ por confirmar |
| `openinference-instrumentation-claude-agent-sdk` | Plan B si las trazas nativas beta resultan inestables | 2 | ⚠️ por fijar | `pip`; solo si hace falta, con aprobación |
| **Dashboard propio** (servidor local + página web que lee `events.jsonl`) | Estado del pipeline y compuertas: pendiente, trabajando, esperando tu sí, ok, falló | 3 | ⚠️ pila por decidir (propuesta: FastAPI + SSE) | `pip`; con aprobación |
| **`git worktree`** | Que backend y frontend escriban en paralelo sin pisarse | 4 | Viene con git | Ninguna |

Dos vistas distintas, no una sola: **Phoenix** responde "¿qué hizo cada agente y cuánto gastó?"; el **dashboard propio** responde "¿en qué etapa va y qué espera de mí?".

### 1.2 · Serie de laboratorios y criterios de comparación

Este es **un laboratorio de una serie**. Todos prueban el **mismo Claude Agent SDK** con el mismo workflow, cambiando solo la herramienta de observabilidad (este usa **Arize Phoenix**; otros usarán otras). El objetivo final es **quedarnos con la mejor herramienta** para ver el comportamiento del workflow y obtener la mayor cantidad de métricas posible.

- **Convención de carpetas:** `labs/orquestacion/<herramienta>/` para los laboratorios de orquestación y `labs/observabilidad/<herramienta>/` para los de observabilidad. Este es `labs/observabilidad/phoenix/`: Phoenix **observa** un workflow orquestado con el Claude Agent SDK. Ver el [índice de labs](../../README.md).
- **Misma prueba en todos:** mismo requerimiento, mismas etapas y mismo modelo, para que los resultados sean comparables.
- **Criterios de comparación (propuesta, por cerrar con el usuario):**

| Criterio | Qué se mide |
|----------|-------------|
| Métricas disponibles | Tokens, costo, latencia por etapa y total, llamadas a herramientas, errores y reintentos |
| Visibilidad del workflow | ¿Muestra el árbol agente → herramienta → subagente? ¿Muestra las compuertas humanas? |
| Puesta en marcha | Tiempo y pasos para levantarlo; dependencias que exige |
| Recursos | Memoria y CPU que consume |
| Privacidad | ¿Algo sale del equipo? ¿Se puede ocultar el contenido de prompts y herramientas? |
| Estabilidad | Dependencia de funciones beta; esfuerzo de mantenimiento |
| Costo y licencia | Licencia y costo de uso o de alojamiento |

- **Decisión:** al terminar los laboratorios se llena una matriz con estos criterios y el usuario elige. Ninguna herramienta se adopta por defecto.

## 2 · Qué deberíamos tener (entregables por fase)

| Fase | Entregable | Criterio de "terminado" (medible) |
|------|-----------|-----------------------------------|
| 0 | Esta carpeta, README y decisiones cerradas (sección 8) | El usuario aprueba el plan |
| 1 | Orquestador mínimo: **un requerimiento**, tres etapas de solo lectura (`requirements-analyst` → `architect` → `security-reviewer`), reportes en archivos y eventos en `events.jsonl` | Corre de punta a punta con una compuerta humana entre etapas; mide tokens y tiempo por etapa |
| 2 | Vista gráfica local: **Arize Phoenix** en Docker recibiendo la telemetría del SDK | Se ve el árbol agente → herramienta (y subagentes) de una ejecución real |
| 3 | Dashboard propio pequeño (estado del pipeline: pendiente, trabajando, esperando tu sí, ok, falló) | Muestra el estado en vivo leyendo `events.jsonl` |
| 4 | Escritores en paralelo (backend y frontend) con `git worktree` por agente | Dos agentes escriben a la vez sin pisarse archivos |

## 3 · Cómo se orquesta (diseño)

```
requirements-analyst → architect → backend / frontend (+devops) → qa → security-reviewer → technical-writer → PR (humano)
        └──────────── tras cada etapa: pausa, resumen y tu "sí" en el chat ────────────┘
                   cada etapa emite eventos → events.jsonl → Phoenix / dashboard
```

- Una etapa = una llamada al SDK con **un agente** y contexto acotado (ID del requerimiento y criterios de aceptación). Su salida va a un archivo de reporte que la siguiente etapa lee como **dato, no como orden**.
- Tope de **8 minutos por etapa** (`asyncio`) y máximo de turnos; modelo **Sonnet como techo**.
- Permisos estrictos; nunca el modo que omite permisos. Cada permiso se pregunta en la terminal.
- ⚠️ Reutilizar los agentes y hooks de `.claude/` desde el SDK, y que `guard-writes.sh` y `turn-guard.sh` sigan activos dentro del SDK: **por verificar** antes de la fase 1.

## 4 · Estructura propuesta de la carpeta

```
labs/observabilidad/phoenix/
├── README.md              # este documento
├── pyproject.toml         # dependencias con versión fijada (fase 1)
├── orchestrator/          # etapas, compuertas y emisión de eventos (fase 1)
├── runs/                  # reportes y events.jsonl de cada ejecución (fuera de git)
└── observability/         # compose o instrucciones de Phoenix (fase 2)
```

## 5 · Requisitos previos

| Requisito | Estado |
|-----------|--------|
| Python | ⚠️ versión por definir (ver requisito del SDK) |
| `claude-agent-sdk` | ⚠️ versión por fijar; instalación **requiere aprobación** (políticas §5) y entorno virtual |
| Docker | Necesario para Phoenix; imagen oficial con versión fija |
| Credencial de Claude | Sesión iniciada con la suscripción. **No** definir `ANTHROPIC_API_KEY` (tiene prioridad sobre la suscripción y pasaría a cobrar por uso). `/status` muestra cuál está activa |
| Claves y secretos | Solo por variables de entorno; nunca en el repo ni en el chat |

⚠️ Cómo cuenta el uso de la suscripción para el SDK cambió varias veces en 2026: releer [el artículo de soporte](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) antes de la fase 1. Un pipeline con varios agentes gasta los límites mucho más rápido que una sesión normal: se mide con un requerimiento antes de escalar.

## 6 · Cómo se ejecuta y cómo se levanta (propuesto, **no ejecutado**)

**Orquestador (fase 1)** — comandos tentativos:

```bash
cd labs/observabilidad/phoenix
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.lock        # ⚠️ por crear, versiones fijadas
python -m orchestrator --req <ID> --stages analyst,architect,security
```

**Phoenix local (fase 2)** — la documentación oficial usa `docker run -p 6006:6006 -p 4317:4317 ... :latest`, que **incumple nuestras políticas** (puertos en todas las interfaces, imagen sin versión fija). Versión adaptada a las políticas §6:

```bash
docker run --rm --name labs-phoenix \
  --cap-drop=ALL --security-opt=no-new-privileges \
  --memory=1g --cpus=1 --pids-limit=256 \
  -p 127.0.0.1:6006:6006 -p 127.0.0.1:4317:4317 \
  arizephoenix/phoenix:<VERSION_FIJA>
# UI: http://localhost:6006
```

- ⚠️ `<VERSION_FIJA>`: elegir y verificar (la documentación cita `4.0.0` solo como ejemplo).
- ⚠️ `--read-only` y datos en `tmpfs`: probar; si la imagen falla, se reporta y no se quita la restricción sin aprobación.
- ⚠️ No se encontró si Phoenix envía analítica hacia afuera por defecto ni cómo apagarla: **revisar antes de usarlo**.

**Telemetría (propuesta):** exportar la telemetría **nativa** del SDK hacia Phoenix, sin paquetes de terceros: `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` (trazas, **beta**: sus nombres pueden cambiar), `OTEL_TRACES_EXPORTER=otlp` y endpoint local.
⚠️ El endpoint exacto (`http://localhost:6006` por deducción) no está confirmado por la documentación. Alternativa si las trazas beta resultan inestables: el instrumentador `openinference-instrumentation-claude-agent-sdk`.

El contenido de prompts y herramientas **no se registra por defecto**; no activar `OTEL_LOG_USER_PROMPTS` ni similares sin decidirlo, porque las trazas incluirían contenido del repo.

## 7 · Seguridad y reglas que aplican

- Agentes y subagentes **proponen**; solo el usuario aprueba, en el chat, para cada acción concreta.
- No se modifica `.claude/**` ni `CLAUDE*.md`; no se debilita ningún hook ni permiso.
- Telemetría solo a `localhost`: las trazas pueden contener contenido del repo.
- Sin commit, push ni PR automáticos. Backend y frontend en paralelo solo con `git worktree` separados.
- Límite de ~8 min por turno; al tercer fallo igual, se detiene y se replantea.
- Gasto o cuota de API de pago: solo con aprobación explícita.

## 8 · Decisiones y preguntas abiertas

| # | Pregunta | Default propuesto |
|---|----------|-------------------|
| 1 | ¿Esta carpeta vive en el repo `architecture` o en uno propio? | Aquí por ahora (se puede mover) |
| 2 | ¿Qué requerimiento usamos para la primera prueba? | El de menor riesgo y más acotado; lo elige el usuario |
| 3 | ¿Phoenix con telemetría nativa o con el instrumentador de OpenInference? | Nativa; instrumentador como plan B |
| 4 | ¿`runs/` dentro del repo? | Sí, pero en `.gitignore` (requiere actualizar `.gitignore`, que es archivo protegido: lo decide el usuario) |
| 5 | Versiones de Python, SDK y Phoenix | Verificar y fijar antes de la fase 1 |

## 9 · Referencias

- [Use the Claude Agent SDK with your Claude plan](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan)
- [Agent SDK: observability](https://code.claude.com/docs/en/agent-sdk/observability.md)
- [Phoenix: integración con el Claude Agent SDK](https://arize.com/docs/phoenix/integrations/python/claude-agent-sdk)
- [Phoenix: despliegue con Docker](https://arize.com/docs/phoenix/self-hosting/deployment-options/docker)
