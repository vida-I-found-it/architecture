"""Grafo mínimo del laboratorio LangGraph: plan -> aprobación humana -> ejecución.

Sin llamadas a modelos: sirve para validar Studio y `interrupt()`.
"""
from typing import TypedDict

from langgraph.graph import END, START, StateGraph
from langgraph.types import interrupt


class State(TypedDict, total=False):
    task: str
    plan: str
    approved: bool
    result: str


def plan(state: State) -> State:
    task = state.get("task", "")
    return {"plan": f"Plan para: {task}"}


def approve(state: State) -> State:
    # Pausa el grafo; se reanuda con Command(resume=True/False).
    # Al reanudar, el nodo se ejecuta de nuevo desde el inicio.
    decision = interrupt({"question": "¿Apruebas este plan?", "plan": state["plan"]})
    return {"approved": bool(decision)}


def route(state: State) -> str:
    return "execute" if state.get("approved") else END


def execute(state: State) -> State:
    return {"result": f"Ejecutado: {state['plan']}"}


builder = StateGraph(State)
builder.add_node("plan", plan)
builder.add_node("approve", approve)
builder.add_node("execute", execute)
builder.add_edge(START, "plan")
builder.add_edge("plan", "approve")
builder.add_conditional_edges("approve", route, ["execute", END])
builder.add_edge("execute", END)

# `langgraph dev` aporta su propio checkpointer; no se define uno aquí.
graph = builder.compile()
