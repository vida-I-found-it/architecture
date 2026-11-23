"""Prueba de la variante B: un nodo de LangGraph que llama al Claude Agent SDK.

Una sola llamada corta, sin herramientas ni configuración del usuario.
No define ANTHROPIC_API_KEY: debe usarse la sesión de Claude Code (suscripción).
"""
from typing import TypedDict

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    TextBlock,
    query,
)
from langgraph.graph import END, START, StateGraph

MODEL = "claude-haiku-5-5"  # el más barato; la política fija Sonnet como tope


class State(TypedDict, total=False):
    prompt: str
    answer: str
    metrics: dict


async def ask(state: State) -> State:
    options = ClaudeAgentOptions(
        model=MODEL,
        max_turns=1,
        allowed_tools=[],
        setting_sources=[],  # no cargar hooks ni CLAUDE.md del usuario
        system_prompt="Responde en una sola frase corta, en español.",
    )
    text, metrics = [], {}
    async for msg in query(prompt=state["prompt"], options=options):
        if isinstance(msg, AssistantMessage):
            text += [b.text for b in msg.content if isinstance(b, TextBlock)]
        elif isinstance(msg, ResultMessage):
            metrics = {
                "duration_ms": msg.duration_ms,
                "num_turns": msg.num_turns,
                "total_cost_usd": msg.total_cost_usd,  # estimado por el SDK; con suscripción no se cobra por uso
                "usage": msg.usage,
                "is_error": msg.is_error,
            }
    return {"answer": "".join(text), "metrics": metrics}


builder = StateGraph(State)
builder.add_node("ask", ask)
builder.add_edge(START, "ask")
builder.add_edge("ask", END)
graph = builder.compile()
