#!/usr/bin/env bash
# PreToolUse: límite máximo por turno (default 480 s = 8 min; override con CLAUDE_TURN_LIMIT_SECONDS).
#  - Si el turno ya superó el límite: deniega la herramienta y ordena a Yonko parar y reportar.
#  - Si es un comando Bash en primer plano: acota su timeout al tiempo restante del turno
#    (solo modifica el input; NO aprueba el comando, así que no se saltan los permisos).
set -u
source "${0%/*}/lib.sh"
hook_require_jq || exit 0
dir=$(hook_state_dir) || exit 0
limit=$(hook_uint_or "${CLAUDE_TURN_LIMIT_SECONDS:-480}" 480)
[ "$limit" -gt 0 ] || limit=480   # 0 denegaría todas las herramientas (autobloqueo)
input=$(cat)

sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || sid=""
[ -n "$sid" ] || { hook_warn "session_id ausente o JSON inválido; límite de tiempo inactivo"; exit 0; }
key=$(hook_session_key "$sid") || exit 0
file="$dir/turn-start-$key"
[ -f "$file" ] || exit 0
read -r raw < "$file" || raw=""
start=$(hook_uint_or "$raw" "")
[ -n "$start" ] || { hook_warn "estado corrupto en $file; se ignora"; exit 0; }

now=$(date +%s)
elapsed=$((now - start))
# Estado de hace más de un día (p. ej. sesión reanudada): no es un turno en curso.
[ "$elapsed" -ge 0 ] && [ "$elapsed" -le 86400 ] || exit 0
remaining=$((limit - elapsed))

if [ "$remaining" -le 0 ]; then
  jq -n --argjson e "$elapsed" --argjson l "$limit" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("LÍMITE DE TIEMPO: el turno lleva \($e)s (máx \($l)s). Yonko debe PARAR ahora, sin más herramientas: reportar qué avanzó, qué falta, qué lo demora y proponer cómo seguir. Solo continúa si el usuario lo aprueba con un nuevo mensaje.")
    }}'
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
bg=$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false')
if [ "$tool" = "Bash" ] && [ "$bg" != "true" ]; then
  printf '%s' "$input" | jq --argjson r "$remaining" '
    (.tool_input.timeout | if type == "number" then . else 120000 end) as $t
    | ([$t, ($r * 1000)] | min) as $m0
    | ([$m0, 1000] | max) as $m
    | {hookSpecificOutput: {
        hookEventName: "PreToolUse",
        updatedInput: (.tool_input + {timeout: $m})
      }}' || hook_warn "no se pudo acotar el timeout de Bash"
fi
exit 0
