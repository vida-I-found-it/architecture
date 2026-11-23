# labs · orquestación · LangGraph — plan inicial

> **Estado: plan inicial.** Sin código todavía; el entorno `.venv` con las dependencias fijas se instaló el 19 de noviembre de 2026 (sección 5.2). Todo comando está marcado como **propuesto** y se ejecuta solo con aprobación del usuario en el chat ([políticas](../../../.claude/rules/agent-policies.md)).
> Lo que no encontré en la documentación oficial se marca con ⚠️. Índice general y criterios de comparación: [`labs/README.md`](../../README.md).

## Tabla de contenido

- [1 · Objetivo](#1--objetivo)
- [2 · Fases y criterios de terminado](#2--fases-y-criterios-de-terminado)
- [3 · Diseño del workflow en LangGraph](#3--diseño-del-workflow-en-langgraph)
  - [3.1 · De pipeline a grafo](#31--de-pipeline-a-grafo)
  - [3.2 · Dos variantes de modelo](#32--dos-variantes-de-modelo)
  - [3.3 · Visualización con LangSmith Studio](#33--visualización-con-langsmith-studio)
- [4 · Herramientas](#4--herramientas)
- [5 · Requisitos previos](#5--requisitos-previos)
  - [5.1 · LangSmith Studio: configuración técnica](#51--langsmith-studio-configuración-técnica)
  - [5.2 · Versiones propuestas (pendientes de aprobación)](#52--versiones-propuestas-pendientes-de-aprobación)
- [6 · Cómo se ejecuta](#6--cómo-se-ejecuta)
  - [6.0 · Probar el flujo en local, paso a paso](#60--probar-el-flujo-en-local-paso-a-paso)
  - [6.1 · Plan original (propuesto, no ejecutado)](#61--plan-original-propuesto-no-ejecutado)
- [7 · Métricas que se recolectan](#7--métricas-que-se-recolectan)
- [8 · Riesgos y reglas](#8--riesgos-y-reglas)
- [9 · Decisiones abiertas](#9--decisiones-abiertas)
- [10 · Referencias](#10--referencias)

## 1 · Objetivo

Ejecutar **el mismo pipeline de agentes** que en el laboratorio del Claude Agent SDK (`requirements-analyst` → `architect` → `security-reviewer`, un requerimiento, compuerta humana entre etapas) pero orquestado con **LangGraph**, y medirlo con los mismos criterios para compararlos. LangGraph es el eje de **orquestación**; la observabilidad es otra pieza (ver [Phoenix](../../observabilidad/phoenix/README.md)).

Qué queremos averiguar:
- Si un grafo con estado, checkpoints e interrupciones mejora lo que logramos con el SDK y con los workflows dinámicos de Claude Code.
- Si se pueden reutilizar los agentes de `.claude/agents/` o hay que reescribirlos.
- Cuánto cuesta ejecutarlo, y con qué credencial.

Fuera de alcance: commits, push o PR automáticos (los decide el usuario), despliegue en servidores de LangGraph, escritores en paralelo sobre el repo.

## 2 · Fases y criterios de terminado

| Fase | Entregable | Criterio de "terminado" (medible) |
|------|-----------|-----------------------------------|
| 0 | Este plan y decisiones de la sección 9 | El usuario aprueba el plan |
| 1 | Grafo de **3 nodos de solo lectura** con compuerta humana entre nodos, checkpoints en SQLite y eventos a `events.jsonl` | Corre de punta a punta; se pausa y se reanuda con tu "sí"; mide tokens y tiempo por nodo |
| 1b | **LangSmith Studio** conectado al servidor local (`langgraph dev`), con trazas apagadas | Se ve el grafo y cada paso de la ejecución en la interfaz (sección 3.3) |
| 2 | Observabilidad conectada (la del lab de Phoenix u otra) | Se ve el árbol de la ejecución |
| 3 | Caso de falla: matar el proceso a mitad de ejecución y reanudar desde el checkpoint | Reanuda sin repetir efectos ni perder estado |
| 4 | Paralelismo con `Send` (dos revisores a la vez) | Ambos corren en paralelo y sus resultados se fusionan en el estado |
| 5 | Llenar la matriz de comparación con los otros laboratorios | Tabla completa de criterios |

## 3 · Diseño del workflow en LangGraph

### 3.1 · De pipeline a grafo

```
        ┌──────────────┐    ┌───────────┐    ┌───────────────────┐
START → │ requirements │ →  │ architect │ →  │ security-reviewer │ → END
        │   -analyst   │    │           │    │                   │
        └──────┬───────┘    └─────┬─────┘    └─────────┬─────────┘
               └── interrupt ─────┴──── interrupt ─────┘   (compuerta: tu "sí")
```

| Pieza del pipeline | Pieza de LangGraph | Fuente |
|--------------------|--------------------|--------|
| Etapa (un agente) | **Nodo**: función que recibe el estado y devuelve cambios | 🧠 |
| Reporte de la etapa anterior | **Estado compartido** del grafo | 🧠 |
| Compuerta humana | **`interrupt()`** en el nodo; se reanuda con `Command(resume=...)` | ✅ [interrupciones](https://docs.langchain.com/oss/python/langgraph/interrupts) |
| Pausar y reanudar entre sesiones | **Checkpointer** (`InMemorySaver` para pruebas, `SqliteSaver` para persistir) e `thread_id` | ✅ |
| Decidir el siguiente paso y actualizar estado a la vez | **`Command(update=..., goto=...)`** | ✅ [Graph API](https://docs.langchain.com/oss/python/langgraph/use-graph-api) |
| Revisores en paralelo (fase 4) | **`Send`**: un nodo una vez por elemento | ✅ |

🧠 = de memoria, por verificar al implementar.

### 3.2 · Dos variantes de modelo

La documentación oficial solo describe el modelo de Claude con **API key** (`langchain-anthropic` y `ANTHROPIC_API_KEY`); no encontré autenticación con la suscripción. Eso lleva a dos variantes:

| Variante | Qué hace cada nodo | Credencial y costo | Qué mide bien |
|----------|--------------------|--------------------|---------------|
| **A · Nativa** | Llama al modelo con `ChatAnthropic` | API key, **pago por uso** (requiere tu aprobación y un tope) | LangGraph de punta a punta, incluidos tokens por nodo |
| **B · Híbrida** | Llama al Claude Agent SDK dentro de cada nodo | Tu suscripción (sin API key); consume tus límites | LangGraph como coordinador de estado, compuertas y checkpoints. Los tokens vienen del SDK |

**Decisión del usuario: variante B** (era la recomendación de Yonko). No gasta dinero y mide justo lo que LangGraph aporta (estado, checkpoints, compuertas). La variante A se agrega solo si quieres medir tokens nativos y apruebas un tope de gasto. ⚠️ La variante B no está documentada por nadie en lo que leí: es una idea nuestra y hay que probar que funcione.

### 3.3 · Visualización con LangSmith Studio

**Decisión del usuario:** usar **LangSmith Studio** para ver el workflow de forma visual, siempre que sea gratuito.

| Punto | Hallazgo (documentación oficial y página de precios) |
|-------|------------------------------------------------------|
| ¿Es gratis? | La documentación lo llama "a free visual interface" ✅. El plan Developer cuesta $0 (1 asiento, 5.000 trazas base al mes). ⚠️ No encontré un texto que diga explícitamente que Studio local funciona en ese plan: se confirma al crear la cuenta |
| Qué muestra | Cada paso del agente: prompts al modelo, llamadas a herramientas y resultados, estado intermedio, ejecución en tiempo real y recarga en caliente ✅. ⚠️ Las páginas que leí no dicen "grafo de nodos" con esas palabras: se confirma con la primera prueba que dibuja el grafo |
| Cómo se conecta | `langgraph dev` levanta un servidor local y la interfaz alojada en `smith.langchain.com` se conecta a él |
| Privacidad | Con `LANGSMITH_TRACING=false`, según la documentación, "no data leaves your local server" ✅. Aun así la interfaz es alojada y exige una API key de LangSmith |
| Navegador | Safari bloquea la conexión a `localhost`. La salida documentada es `langgraph dev --tunnel`, que **expone el servidor por un túnel de internet: no se usa sin tu aprobación**. Se prefiere otro navegador (⚠️ no vi qué pasa con los demás) |
| Límite en la variante B | Studio ve los nodos y el estado, pero ⚠️ (inferencia) **no verá los prompts ni las herramientas que ocurren dentro del Agent SDK** de cada nodo. Para ese detalle hace falta la telemetría del SDK (Phoenix u otra) |

**Respaldo sin cuenta:** diagrama Mermaid generado desde el código del grafo (🧠, por verificar), para incluirlo en este README.

## 4 · Herramientas

| Herramienta | Para qué | Estado |
|-------------|----------|--------|
| **LangGraph** (`pip install -U langgraph`) | Orquestación | ✅ 1.2.23, MIT, Python ≥ 3.10 (PyPI). Ver la sección 5.2 |
| **`langchain-anthropic`** | Modelo de Claude (solo variante A) | ⚠️ por fijar; requiere API key |
| **Claude Agent SDK** | Modelo dentro de cada nodo (variante B) | Ver [el lab de Phoenix](../../observabilidad/phoenix/README.md#5--requisitos-previos) |
| **`InMemorySaver`**, **`SqliteSaver`** | Checkpoints en pruebas y persistentes | ✅ nombres en la documentación; ⚠️ paquete de SQLite por confirmar |
| **Modos de streaming** `updates`, `tasks`, `checkpoints`, `debug` | Fuente de las métricas | ✅ |
| **LangSmith Studio** (interfaz alojada) | Ver el workflow y cada paso en tiempo real | ✅ descrita como gratuita; ⚠️ confirmar plan Developer al crear la cuenta |
| **`langgraph-cli[inmem]`** | `langgraph dev`: servidor local sin Docker que usa Studio | ✅ comando en la documentación; ⚠️ versión por fijar; instalación requiere tu aprobación |
| **Observabilidad** | Ver la ejecución | ⚠️ La documentación de LangGraph apunta a LangSmith (servicio alojado). **No encontré** una guía oficial de Phoenix para LangGraph, así que se confirma antes de elegirla. Línea base sin terceros: `events.jsonl` propio |

## 5 · Requisitos previos

| Requisito | Estado |
|-----------|--------|
| Python | ✅ **3.11 o superior** para la CLI de Studio (documentación). LangGraph y el SDK piden 3.10 o superior (PyPI). El equipo tiene 3.14.6 por defecto, que **no figura** entre las versiones soportadas: se usa 3.12 (ver 5.2) |
| Entorno virtual aislado | Sí |
| Cuenta de LangSmith | La crea **el usuario** (plan Developer); Yonko no crea cuentas |
| API key de LangSmith | Solo por variable de entorno; nunca en el chat ni en el repo. ⚠️ El ejemplo de la documentación usa variables de un espacio de trabajo "agent" (`LANGSMITH_AGENT_ID`); comprobar cuáles aplican a tu cuenta |
| Instalación de paquetes | **Requiere tu aprobación**, con versiones fijadas (políticas §5) |
| API key de Anthropic | Solo variante A; nunca en el chat ni en el repo, solo variable de entorno; con tope de gasto aprobado |
| `ANTHROPIC_API_KEY` en el entorno | **No definir** en la variante B: tiene prioridad sobre la suscripción |

### 5.1 · LangSmith Studio: configuración técnica

Todo lo técnico para que Studio funcione con nuestro servidor local. ✅ = leído en la documentación oficial; ⚠️ = no encontrado o por confirmar.

**1 · Cuenta y región**

| Punto | Detalle |
|-------|---------|
| Quién la crea | **El usuario**. Yonko no crea cuentas ni maneja la clave |
| Plan | Developer ($0, 1 asiento, 5.000 trazas base al mes) ✅. ⚠️ Confirmar que Studio local está incluido |
| Región | UI en EE. UU. por defecto. Si la cuenta es de la UE: UI `eu.smith.langchain.com` y API `https://eu.api.smith.langchain.com` ✅ |

**2 · Variables de entorno** — plantilla sin valores: [`.env.example`](.env.example)

| Variable | ¿Obligatoria? | Para qué | Fuente |
|----------|---------------|----------|--------|
| `LANGSMITH_API_KEY` | **Sí** | "Studio requires a LangSmith API key". La crea el usuario | ✅ |
| `LANGSMITH_TRACING=false` | Recomendada | Apaga las trazas; "no data leaves your local server" | ✅ |
| `LANGSMITH_ENDPOINT` | Solo cuenta de la UE | Apunta la API a la región de la UE | ✅ (en la configuración de perfil, no en las páginas de Studio) |
| `LANGSMITH_AGENT_ID`, `LANGSMITH_AGENT_ENVIRONMENT=local` | ⚠️ Por confirmar | Aparecen en el ejemplo de `.env` de la página de Studio; pertenecen a espacios de trabajo "agent" | ⚠️ No dice si aplican a una cuenta personal |
| `ANTHROPIC_API_KEY` | **No definir** | Tiene prioridad sobre la suscripción (variante B) | — |

Uso: `cp .env.example .env` y completar **tú** el valor de la clave. `.env` ya está en el `.gitignore` del repo (verificado con `git check-ignore`), mientras que `.env.example` tiene una excepción (`!.env.example`) y sí se versiona. No hace falta cambiar `.gitignore`.

**3 · Estructura del proyecto**

```
orquestacion/langgraph/
├── langgraph.json     # configuración que lee `langgraph dev`
├── .env               # real, fuera de git
└── src/
    └── agent.py       # define el grafo compilado
```

```json
{
  "dependencies": ["."],
  "graphs": { "agent": "./src/agent.py:agent" },
  "env": ".env"
}
```

- `dependencies` y `graphs` son obligatorias; `env` apunta al archivo `.env` ✅. Ejemplo tomado de la documentación; los nombres reales se definen en la fase 1.
- El grafo se referencia como `ruta:variable` (grafo ya compilado) o `ruta:función` (función que recibe la configuración y devuelve el grafo) ✅.

**4 · CLI y servidor local**

| Punto | Detalle |
|-------|---------|
| Instalación | `pip install -U "langgraph-cli[inmem]"` con Python 3.11 o superior ✅; ⚠️ fijar versión; requiere tu aprobación |
| Arranque | `langgraph dev` ✅ (sin Docker) |
| Host y puerto | `--host` por defecto **127.0.0.1** y `--port` por defecto **2024** ✅. No cambiar a `0.0.0.0` |
| `--tunnel` | Abre un túnel público de Cloudflare ✅. **Prohibido sin aprobación del usuario** |
| `--no-browser` | No abre el navegador solo ✅ |
| `--no-reload` | Desactiva la recarga en caliente, que viene activa por defecto ✅ |
| `--allow-blocking` | Por defecto desactivado ✅. ⚠️ Si un nodo hace llamadas bloqueantes (por ejemplo, el Agent SDK de forma síncrona) puede hacer falta; decidirlo al probar, no activarlo por defecto |
| Estado | Persiste en un directorio local ✅; ⚠️ no encontré su nombre: añadirlo al `.gitignore` cuando se sepa |

**5 · Red y navegador**

| Punto | Detalle |
|-------|---------|
| Dominios que contacta la interfaz y las trazas | `smith.langchain.com`, `api.smith.langchain.com` y `beacon.langchain.com`, con variantes `eu.` y `apac.` ✅. Solo hace falta abrirlos si hay firewall |
| Dirección de Studio | `https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024` ✅ |
| Safari | Bloquea la conexión a `localhost` ✅. Usar otro navegador. ⚠️ No encontré qué pasa con Brave u otros |

**6 · Lo que no está confirmado y se prueba primero**

- ⚠️ Si un grafo necesita **su propio checkpointer** en `langgraph dev` o si Studio inyecta uno.
- ⚠️ Si **`interrupt()` funciona en Studio** (nuestra compuerta humana). No lo encontré en ninguna página.
- ⚠️ La página de resolución de problemas de Studio no la leí.
- ⚠️ La variable `LANGSMITH_PROJECT` no aparece en estas páginas.

### 5.2 · Versiones propuestas (pendientes de aprobación)

Datos de las páginas de PyPI, leídas el 19 de noviembre de 2026. **Instalado con aprobación del usuario el 19 de noviembre de 2026** en `.venv` (Python 3.12.16); ver el resultado al final de esta sección.

| Paquete | Versión | Licencia | Python | Para qué | Nota |
|---------|---------|----------|--------|----------|------|
| `langgraph` | 1.2.23 | MIT | ≥ 3.10 (listados 3.10–3.13) | Grafo, checkpoints, interrupciones | — |
| `langgraph-cli[inmem]` | 0.4.43 | MIT | ≥ 3.10 | `langgraph dev` (servidor local para Studio) | La extra `inmem` está documentada; ⚠️ la página no dice qué instala |
| `claude-agent-sdk` | 0.2.186 | MIT | ≥ 3.10 (listados 3.10–3.13) | Modelo dentro de cada nodo (variante B) | **Trae empaquetado el CLI de Claude Code** en sus ruedas. ⚠️ Si usa tu sesión iniciada o necesita otra: se prueba |
| `langgraph-checkpoint-sqlite` | 3.1.3 | MIT | ≥ 3.10 | Checkpoints persistentes | Usa `aiosqlite` en modo asíncrono. Recomienda `LANGGRAPH_STRICT_MSGPACK=true` (hardening de deserialización) |
| `langgraph-api` y `langgraph-runtime-inmem` | 0.18.3 y 0.38.3 | **Elastic-2.0** (no MIT) | ≥ 3.11 | Servidor en memoria de desarrollo | ⚠️ Probablemente llegan con la extra `inmem` (inferencia mía). Licencia permite uso propio, no ofrecerlo como servicio; igual que Phoenix |

**Python:** el equipo tiene 3.14.6 por defecto, pero ni `langgraph` ni `claude-agent-sdk` lo listan como soportado. Ya existe **Python 3.12.16** instalado con `uv` (en `~/.local/share/uv/python`), así que **no hay que descargar ni instalar Python**: se usa 3.12.

**Instalación realizada** con estos comandos (aprobados por el usuario):

```bash
cd labs/orquestacion/langgraph
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python --only-binary :all: \
  "langgraph==1.2.23" "langgraph-cli[inmem]==0.4.43" \
  "claude-agent-sdk==0.2.186" "langgraph-checkpoint-sqlite==3.1.3"
uv pip freeze --python .venv/bin/python > requirements.lock   # versiones exactas de todo, incluidas las transitivas
```

- `--only-binary :all:` evita ejecutar scripts de construcción de paquetes de código fuente (políticas §5).
- `.venv/` ya está en el `.gitignore` del repo.
**Resultado de la instalación (verificado):**

- Se instalaron **85 paquetes** (90 tras el ajuste de abajo), todos fijados en `requirements.lock`. `uv pip check` dice que son compatibles, y una importación de prueba (`langgraph`, `claude_agent_sdk`, `interrupt`, `Command`, `SqliteSaver`) funciona. `langgraph --version` responde 0.4.43.
- Los cuatro paquetes quedaron en las versiones aprobadas.
- ✅ **Ajuste de versiones (aprobado por el usuario):** la extra `inmem` instaló al principio **pre-lanzamientos** incompatibles entre sí (`langgraph-api 0.19.0.dev8` con `langgraph-runtime-inmem 0.39.0.dev17`) y `langgraph dev` caía con `ImportError: cannot import name 'stop_pool'`. Se fijaron las estables **`langgraph-api 0.18.3` y `langgraph-runtime-inmem 0.38.3`**. Estas dependen de `blockbuster` → `forbiddenfruit` 0.1.4, que **solo existe como código fuente** en PyPI (sin wheel, última versión de 2021); se construyó únicamente ese paquete desde fuente: `uv pip install --only-binary :all: --no-binary forbiddenfruit "forbiddenfruit==0.1.4" "langgraph-api==0.18.3" "langgraph-runtime-inmem==0.38.3"`. Antes se leyó su `setup.py` (sin red ni ejecución de comandos; la extensión en C solo se activa con `FFRUIT_EXTENSION=true`, que no se usó) y no se revisó el resto de su código. `requirements.lock` ya no tiene versiones `dev` ni `rc`.
- ⚠️ **Dependencias sin revisar una a una**, entre ellas `httpx2` 2.16.2 (la piden `langsmith` y `mcp`; no pude verificar su origen), `grpcio`, `cryptography` y `opentelemetry-*`. `langsmith` 0.15.0 quedó instalado: las trazas siguen apagadas mientras `LANGSMITH_TRACING=false`.
- `.venv/` está ignorado por git. `requirements.lock` no lo está: revisarlo antes de commitear.

## 6 · Cómo se ejecuta

### 6.0 · Probar el flujo en local, paso a paso

El grafo mínimo (`src/agent.py`) tiene 3 nodos: `plan` → `approve` (pausa con `interrupt()`) → `execute`. No llama a modelos: no gasta tokens ni API. Verificado ejecutándolo el 2026-11-22.

1. **Entrar a la carpeta** y tener el `.env` creado desde `.env.example` (con tu clave de LangSmith; nunca la pegues en el chat ni la subas al repo):
   ```bash
   cd labs/orquestacion/langgraph
   ```
2. **Prueba rápida sin servidor ni cuenta** (el grafo en memoria, pausa y reanuda):
   ```bash
   .venv/bin/python -I - <<'EOF'
   import sys; sys.path.insert(0, "src")
   from agent import builder
   from langgraph.checkpoint.memory import InMemorySaver
   from langgraph.types import Command
   g = builder.compile(checkpointer=InMemorySaver())
   cfg = {"configurable": {"thread_id": "t1"}}
   print(g.invoke({"task": "demo"}, cfg).get("__interrupt__"))   # se pausa en approve
   print(g.invoke(Command(resume=True), cfg))                    # reanuda y termina
   EOF
   ```
   Esperado: primero la pregunta "¿Apruebas este plan?", luego el estado final con `approved: True` y `result`.
3. **Levantar el servidor local** (solo en tu máquina, `127.0.0.1`) y dejarlo abierto en esa terminal:
   ```bash
   .venv/bin/langgraph dev --no-browser --host 127.0.0.1 --port 2024
   ```
   Comprobar en otra terminal: `curl http://127.0.0.1:2024/ok` debe responder `{"ok":true,...}`.
4. **Ver el grafo en Studio** abriendo en **Chrome o Brave** (no Safari, que bloquea `localhost`; el navegador integrado de Claude tampoco lo permite) con tu sesión de LangSmith iniciada:
   `https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024`
   Deberías ver los nodos `plan`, `approve` y `execute`. Pulsa *Submit* con la entrada `{"task": "demo"}`: el grafo se detiene en `approve` y Studio muestra la pregunta para reanudar.
5. **Alternativa por la API local** (sin Studio):
   ```bash
   B=http://127.0.0.1:2024; H='content-type: application/json'
   T=$(curl -s -X POST $B/threads -H "$H" -d '{}' | python3 -c "import sys,json;print(json.load(sys.stdin)['thread_id'])")
   curl -s -X POST $B/threads/$T/runs/wait -H "$H" -d '{"assistant_id":"agent","input":{"task":"demo"}}'      # termina pausado en approve
   curl -s -X POST $B/threads/$T/runs/wait -H "$H" -d '{"assistant_id":"agent","command":{"resume":true}}'   # reanuda; resume:false termina sin ejecutar
   ```
6. **Detener** el servidor con `Ctrl+C` en la terminal del paso 3.

Con `LANGSMITH_TRACING=false`, según la documentación, no salen trazas del servidor local; el navegador sí carga la interfaz desde `smith.langchain.com`. Qué funciona dentro de Studio (dibujar el grafo, reanudar un `interrupt`) se anota en la sección 9 cuando se confirme.

### 6.1 · Plan original (propuesto, no ejecutado)

```bash
cd labs/orquestacion/langgraph
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.lock        # ⚠️ por crear, versiones fijadas
python -m pipeline --req <ID>           # corre hasta la primera compuerta y se pausa
python -m pipeline --req <ID> --resume  # reanuda tras tu "sí"
```

**Studio (fase 1b)** — comandos de la documentación, no ejecutados:

```bash
pip install -U "langgraph-cli[inmem]"   # ⚠️ fijar versión
export LANGSMITH_TRACING=false          # nada sale del servidor local
langgraph dev                           # API en http://127.0.0.1:2024
# Studio: https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024
```

Patrón de pausa y reanudación según la documentación (no ejecutado; la API puede haber cambiado):

```python
from langgraph.types import interrupt, Command

def gate(state):
    answer = interrupt("¿Apruebas pasar a la siguiente etapa?")  # pausa; requiere checkpointer
    return {"approved": answer}

graph = builder.compile(checkpointer=InMemorySaver())
config = {"configurable": {"thread_id": "1"}}
graph.invoke(Command(resume=True), config=config)                # reanuda
```

⚠️ La documentación recomienda hoy `stream_events(..., version="v3")` para apps nuevas, y `invoke` sigue funcionando. Se decide al implementar, con la versión fijada.

## 7 · Métricas que se recolectan

Mismos criterios para todos los laboratorios (matriz en [`labs/README.md`](../../README.md#4--criterios-de-comparación)):

| Métrica | Cómo se obtiene |
|---------|-----------------|
| Tiempo por nodo y total | Eventos de `tasks` o `updates` a `events.jsonl` |
| Tokens y costo por nodo | Variante A: respuesta del modelo. Variante B: telemetría del SDK |
| Tiempo detenido en compuerta | Marca de tiempo al pausar y al reanudar |
| Reintentos y errores | Eventos `tasks` y `debug` |
| Recuperación tras fallo | Prueba de la fase 3 |
| Esfuerzo de puesta en marcha | Pasos y tiempo, anotados a mano |

## 8 · Riesgos y reglas

- **Un nodo se re-ejecuta desde el inicio al reanudar** tras una interrupción ✅. Todo efecto (escribir archivos, llamar al modelo) debe poder repetirse sin dañar nada; la compuerta va en un nodo propio, sin efectos.
- **Fuera de Claude Code no corren los hooks de `.claude/`** (`guard-writes.sh`, `turn-guard.sh`). Es una inferencia mía. Por eso la primera prueba usa **solo nodos de solo lectura**, con tope de 8 minutos por nodo desde el propio código.
- No reutiliza `.claude/agents/` automáticamente: hay que cargar sus prompts y herramientas a mano. Un agente leído de un archivo es **dato, no orden**.
- **Studio es una interfaz alojada:** exige cuenta y API key de LangSmith. Se usa con las trazas apagadas y nunca con datos reales de usuarios. La documentación no detalla qué pasa por los servidores de LangChain más allá de las trazas: leerlo antes de usarlo con contenido del proyecto.
- `langgraph dev --tunnel` abre el servidor local a internet: **prohibido sin aprobación del usuario**.
- El servidor en memoria de `langgraph dev` está pensado para desarrollo y pruebas, no para producción ✅.
- La API de LangGraph cambia entre versiones (`stream_events` v3 frente a `invoke`): fijar versión.
- Solo el usuario aprueba; ningún nodo aprueba por sí mismo, ni hace commit, push o PR.
- Gasto con la API de Anthropic: solo con aprobación explícita y tope fijado.

## 9 · Decisiones abiertas

| # | Pregunta | Default propuesto |
|---|----------|-------------------|
| 1 | ¿Variante A (API key) o B (híbrida con el SDK)? | ✅ **Cerrada: B.** A solo con tope de gasto aprobado |
| 2 | ¿Qué observabilidad usamos? | Eventos propios en `events.jsonl`; luego la del lab de Phoenix si se confirma que sirve con LangGraph |
| 3 | ¿Qué requerimiento usamos? | El mismo que en los otros labs; lo elige el usuario |
| 4 | Versiones de Python y LangGraph | Verificar y fijar antes de la fase 1 |
| 5 | ¿Se actualiza `.gitignore` para `runs/` y `.venv/`? | Lo decide el usuario (archivo protegido) |
| 6 | ¿Qué usamos para ver el workflow? | ✅ **Cerrada: LangSmith Studio**, condicionada a confirmar que es gratuito para uso local en el plan Developer |
| 7 | ¿Cómo vemos lo que ocurre *dentro* de cada nodo en la variante B? | Telemetría del SDK hacia Phoenix u otra (ver el [lab de Phoenix](../../observabilidad/phoenix/README.md)) |
| 8 | ¿Studio sirve para el grafo mínimo? | ✅ **Confirmado por el usuario (2026-11-22, Chrome):** el grafo se dibuja; con `{"task": "demo"}` se pausa en `approve` y muestra "Plan para: demo" y "¿Apruebas este plan?". **Reanudación confirmada por el usuario** con `true` y con `false` desde Studio (grafo `agent`). Aviso "Not seeing LangSmith runs?": es normal con `LANGSMITH_TRACING=false` (el servidor reporta `"langsmith": false`); la clave sí está definida. Sin verificar: si el plan Developer cobra por Studio local |
| 11 | ¿Cuánto consume el lab del plan? | 📊 **Instantánea (2026-11-23, plan Pro), tras las pruebas con el SDK:** límite de 5 horas **18 %** usado (se reinicia en 4 h 22 min); semanal, todos los modelos, **5 %** (se reinicia en 4 d 20 h); uso extra desactivado (0,00 USD). Ventana de contexto de la sesión de Claude: **17 %** (166.204 de 1.000.000 tokens). Es una foto de **toda la cuenta y la sesión**, no solo de las llamadas del lab: no se puede atribuir al lab sin una medición antes/después |
| 10 | ¿Funciona el grafo de dos etapas con el SDK? | ✅ **Verificado en Python (2026-11-22):** `src/pipeline.py` = `writer` (SDK) → `gate` (`interrupt`) → `reviewer` (SDK), con `metrics` por nodo. Aprobar (`true`) corre las dos llamadas: writer 1,8 s / 187 tokens de salida; reviewer 4,2 s / 678; total ≈ 6,1 s, 865 tokens de salida, est. 0,0025 USD. Rechazar (`false`) termina tras `writer`, sin `reviewer`. La 2.ª llamada leyó 8.832 tokens de caché (el prompt base del CLI se reutiliza). Pendiente: probarlo en Studio (grafo `pipeline`, entrada `{"task": "..."}`) |
| 9 | ¿El Agent SDK dentro de un nodo usa la suscripción? | ✅ **Funciona tras iniciar sesión con el CLI del SDK** (`_bundled/claude auth login`; `auth status`: `claude.ai`, plan `pro`). Una llamada con `claude-haiku-5-5` desde el nodo `ask`: 977 ms, 1 turno, 2 tokens de entrada nuevos + 14.145 de creación de caché (el prompt base del CLI) y 20 de salida; el SDK estima 0,0028 USD (referencia, no cobro). Sin `ANTHROPIC_API_KEY`. Pendiente: probarlo desde el servidor `langgraph dev` en Studio. Historial del primer intento, fallido: **(2026-11-22)** `src/sdk_node.py` (un nodo, `claude-haiku-5-5`, 1 turno, sin herramientas) falla con `Failed to authenticate: OAuth session expired and could not be refreshed`. El CLI incluido en el SDK (`_bundled/claude`, 2.1.329) responde `auth status` → `loggedIn: false`: **no comparte la sesión de la app de escritorio**. No hay `ANTHROPIC_API_KEY` definida. Requiere que el usuario inicie sesión con ese CLI (login de suscripción, a mano) y reintentar |

## 10 · Referencias

- [LangGraph: overview](https://docs.langchain.com/oss/python/langgraph/overview)
- [LangGraph: interrupciones](https://docs.langchain.com/oss/python/langgraph/interrupts)
- [LangGraph: Graph API (`Send` y `Command`)](https://docs.langchain.com/oss/python/langgraph/use-graph-api)
- [LangGraph: streaming](https://docs.langchain.com/oss/python/langgraph/streaming)
- [LangChain: integración con Anthropic](https://docs.langchain.com/oss/python/integrations/chat/anthropic)
- [LangSmith Studio](https://docs.langchain.com/oss/python/langgraph/studio)
- [LangGraph: servidor local](https://docs.langchain.com/oss/python/langgraph/local-server)
- [LangSmith: desarrollo y pruebas locales](https://docs.langchain.com/langsmith/local-dev-testing)
- [LangChain: precios](https://www.langchain.com/pricing)
