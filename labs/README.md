# labs · Laboratorios de workflows multiagente con Claude Code

> **Estado: investigación inicial.** No hay nada instalado ni ejecutado. La información sale de la documentación oficial de Claude Code (leída) y de búsquedas web en blogs comparativos (no verificada contra los repositorios). Lo no verificado se marca con ⚠️.

## Tabla de contenido

- [1 · Propósito de esta carpeta](#1--propósito-de-esta-carpeta)
- [2 · Laboratorios (índice)](#2--laboratorios-índice)
- [3 · Herramientas para workflows multiagente](#3--herramientas-para-workflows-multiagente)
  - [3.1 · Nativas de Claude Code](#31--nativas-de-claude-code)
  - [3.2 · SDK oficial](#32--sdk-oficial)
  - [3.3 · Orquestadores externos para Claude Code](#33--orquestadores-externos-para-claude-code)
  - [3.4 · Frameworks generales de agentes](#34--frameworks-generales-de-agentes)
- [4 · Criterios de comparación](#4--criterios-de-comparación)
- [5 · Recomendación de orden](#5--recomendación-de-orden)
- [6 · Reglas y riesgos](#6--reglas-y-riesgos)
- [7 · Qué no está verificado](#7--qué-no-está-verificado)
- [8 · Referencias](#8--referencias)

## 1 · Propósito de esta carpeta

Probar **la misma tarea de workflow multiagente** con distintas herramientas, medir su comportamiento y obtener la mayor cantidad de métricas posible, para **quedarnos con la mejor**. Partimos de Claude Code (nuestros agentes viven en `.claude/agents/`) y solo después miramos frameworks externos.

Hay **dos ejes independientes**, y cada laboratorio fija uno y varía el otro:

| Eje | Pregunta | Ejemplos |
|-----|----------|----------|
| **Orquestación** | ¿Quién coordina a los agentes? | Subagentes, workflows dinámicos, agent teams, Agent SDK, orquestadores externos (sección 3) |
| **Observabilidad** | ¿Con qué vemos qué hicieron y cuánto costó? | Phoenix, MLflow, Langfuse, SigNoz… (ver [el laboratorio de Phoenix](observabilidad/phoenix/README.md#12--serie-de-laboratorios-y-criterios-de-comparación)) |

**Estructura por secciones:** cada herramienta que probemos va en la carpeta de su eje.

```
labs/
├── README.md                    # este índice
├── orquestacion/                # herramientas que ejecutan el workflow
│   └── langgraph/
└── observabilidad/              # herramientas que observan y miden el workflow
    └── phoenix/
```

- `orquestacion/<herramienta>/`: se prueba la herramienta como orquestador y se mide con una observabilidad fija.
- `observabilidad/<herramienta>/`: se prueba la herramienta como observador sobre un workflow fijo (por defecto, el Claude Agent SDK).
- Cada carpeta lleva su propio README con plan, comandos propuestos y resultados.

## 2 · Laboratorios (índice)

**Observabilidad** (`observabilidad/`)

| Laboratorio | Qué prueba | Workflow que observa | Estado |
|-------------|------------|----------------------|--------|
| [`phoenix`](observabilidad/phoenix/README.md) | Arize Phoenix | Claude Agent SDK (Python) | 📝 Plan inicial |
| *(candidatos)* | MLflow, Langfuse, SigNoz | Claude Agent SDK | ⬜ Sin crear |

**Orquestación** (`orquestacion/`)

| Laboratorio | Qué prueba | Observabilidad usada | Estado |
|-------------|------------|----------------------|--------|
| [`langgraph`](orquestacion/langgraph/README.md) | LangGraph | Por definir | 📝 Plan inicial |
| *(propuesto)* | Workflows dinámicos de Claude Code | Por definir | ⬜ Sin crear |
| *(propuesto)* | Agent teams | Por definir | ⬜ Sin crear |

## 3 · Herramientas para workflows multiagente

"Costo" distingue dos cosas: lo que cuesta la **herramienta** y lo que consumen los **tokens** (en los nativos, tu suscripción; con frameworks externos suele ser API de pago, ver 3.4).

### 3.1 · Nativas de Claude Code

Fuente: documentación oficial de Claude Code (páginas de [agentes en paralelo](https://code.claude.com/docs/en/agents), [workflows](https://code.claude.com/docs/en/workflows) y [agent teams](https://code.claude.com/docs/en/agent-teams)).

| Herramienta | Qué es | Cómo se usa | Costo | Madurez y límites |
|-------------|--------|-------------|-------|-------------------|
| **Subagentes** (`.claude/agents/`) | Agentes con rol y herramientas propias, en su propio contexto; devuelven un resumen a la sesión principal | Ya los usamos | Suscripción; sin software extra | Estable. No hablan entre sí |
| **Workflows dinámicos** | Un script JavaScript que Claude escribe y un runtime ejecuta en segundo plano para orquestar muchos subagentes; los resultados intermedios no entran al contexto | Palabra clave `ultracode` o "use a workflow"; `/deep-research`; guardar en `.claude/workflows/` y ejecutar como `/<nombre>`; vigilar con `/workflows` | Suscripción; cuenta contra tus límites. Aviso por encima de 25 agentes o 1,5 M de tokens proyectados | Disponible en planes de pago (en Pro se activa en `/config`). Hasta 16 agentes en paralelo por defecto, 1.000 por ejecución. El script no accede directo al sistema de archivos ni a la shell |
| **Agent teams** | Varias sesiones de Claude Code coordinadas por un líder, con lista de tareas compartida y mensajes entre pares | Variable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; paneles con tmux o iTerm2 (`teammateMode`) | Suscripción; "significativamente más tokens" que una sesión; se recomienda empezar con 3 a 5 | **Experimental y desactivado por defecto.** Sin worktrees por compañero (hay que repartir archivos), un equipo por sesión, sin equipos anidados. Con `-p` y el Agent SDK no lanza compañeros |
| **Agent view** (`claude agents`) | Vista para gestionar varias sesiones | `claude agents`, `/agents`, `/tasks` | Suscripción | **Research preview** |
| **`/batch`** | Skill que divide un cambio en 5 a 30 subagentes, cada uno en su worktree | Comando `/batch` | Suscripción; multiplica los tokens | ⚠️ No leí su página específica |
| **Worktrees + `claude -p`** | Un checkout de git por sesión y ejecuciones sin interfaz; orquestación a mano con scripts | `git worktree` + scripts | Suscripción | Manual: control total, cero herramientas nuevas |

### 3.2 · SDK oficial

| Herramienta | Qué es | Integración con Claude Code | Costo | Notas |
|-------------|--------|-----------------------------|-------|-------|
| **Claude Agent SDK** (Python y TypeScript) | Ejecuta agentes desde código, con permisos, hooks y compuertas; patrón líder + subagentes | Es el motor de Claude Code expuesto como librería; puede reutilizar la configuración del proyecto ⚠️ por verificar | Con sesión de la suscripción usa tus límites; con API key, pago por uso (ver [el laboratorio](observabilidad/phoenix/README.md#5--requisitos-previos)) | Es el eje del primer laboratorio. Los equipos de agentes no se lanzan dentro del SDK |

### 3.3 · Orquestadores externos para Claude Code

Fuente: blogs comparativos ([Tembo](https://www.tembo.io/blog/claude-code-multi-agent-orchestration), [claudefa.st](https://claudefa.st/blog/tools/orchestrators/multi-agent-orchestrators), [Addy Osmani](https://addyosmani.com/blog/claude-code-agent-teams/)). ⚠️ No verifiqué licencias, versiones ni funciones en los repositorios.

| Herramienta | Qué es (según las fuentes) | Costo y licencia |
|-------------|----------------------------|------------------|
| **Ruflo** (antes `claude-flow`) | Orquestador de enjambres de agentes sobre Claude Code; renombrado en enero de 2026. El paquete npm y la CLI conservan el nombre `claude-flow` | ⚠️ Sin verificar |
| **Claude Squad** | Gestiona varias sesiones de agentes en paralelo con worktrees | ⚠️ Sin verificar |
| **ccpm** | Gestión de proyectos y tareas para trabajo paralelo con Claude Code | ⚠️ Sin verificar |
| **Conductor** | Ejecuta varios agentes de código en paralelo | ⚠️ Sin verificar (puede ser de pago) |
| **Crystal** | Igual categoría (agentes en paralelo con worktrees) | ⚠️ Sin verificar |
| **Vibe Kanban** | Tablero Kanban para repartir tareas a agentes | ⚠️ Sin verificar |
| **Swarm SDK** / **Mission Control** | Mencionados en las fuentes sin detalle | ⚠️ Sin verificar |

Estas herramientas ejecutan código con tus permisos y no son de Anthropic: **se revisa su código antes de usarlas** (políticas §5).

### 3.4 · Frameworks generales de agentes

Fuente: comparativas ([LangChain](https://langchain.com/resources/ai-agent-frameworks), [gurusup](https://gurusup.com/blog/best-multi-agent-frameworks-2026), [Rework](https://resources.rework.com/tools/ai-agents/best-multi-agent-frameworks-2026)). No son "de Claude Code": son independientes del modelo. ⚠️ No encontré un puente oficial entre el Claude Agent SDK y ellos; el punto de unión descrito son los protocolos MCP y A2A.

| Framework | Patrón principal | Estado según las fuentes |
|-----------|------------------|--------------------------|
| **LangGraph** | Grafo de ejecución con checkpoints; librerías separadas de supervisor y enjambre | Muy citado en producción |
| **CrewAI** | Roles; procesos secuencial y jerárquico; soporta A2A | Muy citado |
| **Google ADK** | Árbol de agentes con delegación y ejecución en paralelo; A2A | Activo |
| **Microsoft Agent Framework** | Grafo con checkpoints; concurrencia y patrón "Magentic" | Sucesor recomendado de AutoGen, que pasó a mantenimiento en el primer trimestre de 2026 |
| **OpenAI Agents SDK** | Agentes con traspasos | Citado |
| **Semantic Kernel** | Orquestación de Microsoft | Citado |

⚠️ **Costo con Claude:** estos frameworks llaman al modelo por API, no por tu suscripción de Claude Code. Para usar Claude con ellos haría falta API key y pago por uso. Es una inferencia mía a partir de la política de autenticación del SDK; confírmalo antes de planear un laboratorio con ellos.

## 4 · Criterios de comparación

Mismos criterios para todos los laboratorios (los de observabilidad están en [el README de Phoenix](observabilidad/phoenix/README.md#12--serie-de-laboratorios-y-criterios-de-comparación)). Para el eje de orquestación se proponen además estos, **por cerrar contigo**:

| Criterio | Qué se mide |
|----------|-------------|
| Reutiliza `.claude/agents/` | ¿Usa nuestros agentes sin reescribirlos? |
| Compuertas humanas | ¿Se puede pausar entre etapas y exigir tu "sí" en el chat? |
| Hooks y permisos | ¿Siguen activos `guard-writes.sh` y `turn-guard.sh`? ¿Respeta el modo de permisos? |
| Aislamiento de escritura | ¿Worktrees por agente o riesgo de pisarse archivos? |
| Paralelismo | Máximo de agentes concurrentes y control de ese tope |
| Costo en tokens | Tokens totales y por etapa para la misma tarea |
| Madurez | Estable, preview o experimental; frecuencia de cambios |
| Esfuerzo de puesta en marcha | Pasos, dependencias y tiempo |

## 5 · Recomendación de orden

1. **Terminar el laboratorio del SDK con Phoenix** (ya planificado), porque fija la línea base de métricas.
2. **Siguiente: workflows dinámicos de Claude Code.** No instalan nada, usan nuestra suscripción y su script no accede directo al sistema de archivos ni a la shell, lo que es un punto a favor en seguridad. Se compara contra la línea base con la misma tarea.
3. **Después: agent teams**, con cuidado por ser experimentales, por el mayor consumo de tokens y por no aislar worktrees.
4. **Al final: orquestadores externos y frameworks generales**, solo si lo nativo no alcanza. Piden revisión de código y, con frameworks, probablemente API de pago.

## 6 · Reglas y riesgos

- Instalar herramientas, paquetes o imágenes exige tu aprobación, con versión fijada ([políticas](../.claude/rules/agent-policies.md) §5 y §6).
- Todo orquestador debe respetar las compuertas humanas: ningún agente aprueba por sí mismo ni hace commit, push o PR.
- Agent teams no aísla worktrees: los escritores en paralelo necesitan archivos repartidos o worktrees propios.
- Más agentes en paralelo multiplican los tokens; se fija un tope por ejecución y se mide antes de escalar.
- Ninguna herramienta se adopta por defecto: se decide al final con la matriz de criterios.

## 7 · Qué no está verificado

- Licencias, versiones y funciones de los orquestadores externos y frameworks generales (salen de blogs).
- Que los hooks de `.claude/` sigan activos dentro de workflows, agent teams y el Agent SDK.
- Si `/batch` y los workflows dinámicos respetan `.claude/agents/`.
- Cuánto consume cada opción en tu plan: solo se sabe medir ejecutándolas.

## 8 · Referencias

- [Claude Code: ejecutar agentes en paralelo](https://code.claude.com/docs/en/agents)
- [Claude Code: workflows dinámicos](https://code.claude.com/docs/en/workflows)
- [Claude Code: agent teams](https://code.claude.com/docs/en/agent-teams)
- [Claude Code: subagentes](https://code.claude.com/docs/en/sub-agents)
- [Tembo: orquestación multiagente con Claude Code](https://www.tembo.io/blog/claude-code-multi-agent-orchestration)
- [claudefa.st: 6 frameworks multiagente para Claude Code](https://claudefa.st/blog/tools/orchestrators/multi-agent-orchestrators)
- [Addy Osmani: Claude Code Swarms](https://addyosmani.com/blog/claude-code-agent-teams/)
- [LangChain: mejores frameworks de agentes 2026](https://langchain.com/resources/ai-agent-frameworks)
- [gurusup: mejores frameworks multiagente 2026](https://gurusup.com/blog/best-multi-agent-frameworks-2026)
