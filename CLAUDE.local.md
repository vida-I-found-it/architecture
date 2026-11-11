# CLAUDE.local.md · Configuración de Claude Code — I Found It

> Extensión de [`CLAUDE.md`](CLAUDE.md). El detalle (estructura de `.claude/`, hooks activos, roster de agentes, adopción por repo, cómo replicar y reglas para crear o cambiar hooks y agentes) vive en [`.claude/rules/claude-config-guide.md`](.claude/rules/claude-config-guide.md) y y se carga solo (regla con `paths`) al leer o editar hooks, agentes, `settings.json` o este archivo; no entra en el contexto al arrancar.

Lo mínimo que hay que saber sin abrirlo: hay hooks activos que limitan cada turno a 8 min (`turn-guard.sh`) y protegen la configuración (`guard-writes.sh`: deniega a subagentes y pregunta a la sesión principal; nunca aprueba por su cuenta). Los agentes están en `.claude/agents/` y sus políticas comunes en `.claude/rules/agent-policies.md`. Cambiar `.claude/**` o `CLAUDE*.md` solo con orden explícita del usuario.
