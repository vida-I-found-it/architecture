#!/usr/bin/env bash
# PreToolUse: protege la configuración de Claude Code y pide autorización para acciones destructivas.
#  - Subagente (el payload trae agent_id) que escribe en config protegida  -> DENY.
#  - Sesión principal que escribe en config protegida                      -> ASK (el humano confirma).
#  - Cualquiera: borrado / privilegios por Bash (rm, sudo, git clean...)   -> ASK.
#  - Subagente que lanza otra instancia (`claude ...`)                     -> DENY.
#  - Si el hook no puede analizar el payload                               -> ASK (falla seguro, nunca en silencio).
# Solo emite `deny` o `ask`; NUNCA `allow`: los permisos del repo siguen aplicando.
# Límite conocido: el análisis de Bash es por texto y es evadible (variables, base64, scripts). Es una barrera
# contra descuidos e inyección simple, no contra un atacante decidido.
set -u
# Si el hook termina sin haber decidido (error interno, señal), pregunta en vez de dejar pasar en silencio.
decided=0
# shellcheck disable=SC2329  # se invoca vía trap EXIT
finish() {
  [ "$decided" -eq 1 ] && return 0
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"GUARD: el hook terminó sin decidir. Confirma manualmente."}}'
  exit 0   # Claude Code solo procesa el JSON de stdout si el hook sale con 0
}
trap finish EXIT
trap 'exit 0' TERM INT HUP
# shellcheck source=lib.sh
source "${0%/*}/lib.sh"


emit() { # $1 = deny|ask, $2 = motivo
  jq -n --arg d "$1" --arg r "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}' 2>/dev/null \
    || printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"GUARD: no se pudo formar el aviso de esta llamada. Confirma manualmente."}}'
  decided=1
}

if ! command -v jq >/dev/null 2>&1; then
  hook_warn "jq no disponible; guard-writes pide confirmación"
  decided=1
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"GUARD: jq no está disponible y no se puede analizar esta llamada. Confirma manualmente."}}'
  exit 0
fi

# Evalúa una regex; si el motor devuelve error (exit 2) pregunta en vez de dejar pasar en silencio.
m() {
  [[ "$1" =~ $2 ]]; local rc=$?
  if [ "$rc" -eq 2 ]; then
    hook_warn "regex inválida; guard-writes pide confirmación"
    emit ask "GUARD: error interno al analizar el comando. Confirma manualmente."
    exit 0
  fi
  return "$rc"
}

input=$(cat)
if ! printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1; then
  hook_warn "payload inválido; guard-writes pide confirmación"
  emit ask "GUARD: no se pudo analizar el payload de esta llamada. Confirma manualmente."
  exit 0
fi

get() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }
tool=$(get '.tool_name // empty')
case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit|Bash) ;;
  "") emit ask "GUARD: la llamada no indica qué herramienta usa. Confirma manualmente."; exit 0 ;;
  *) decided=1; exit 0 ;;   # el resto no es asunto de este hook
esac

sub=false
[ "$(get 'has("agent_id")')" = "true" ] && sub=true   # solo un subagente trae agent_id
who="la sesión principal"; $sub && who="un subagente"
atype=$(get '.agent_type // empty')   # nombre del subagente; solo se acepta [a-z0-9-], si no se ignora
if [ -n "$atype" ] && ! [[ "$atype" =~ ^[a-z0-9-]{1,40}$ ]]; then atype="__invalid__"; fi
$sub && [ -z "$atype" ] && atype="__invalid__"   # subagente sin agent_type => también el más restringido   # nombre raro => se trata como el más restringido (docs-only)

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }   # macOS tiene FS insensible a mayúsculas

# Normaliza una ruta (sin tocar el disco): resuelve ~, relativas, "." y "..".
norm_path() {
  local p="$1" cwd="$2" seg stack=""
  # shellcheck disable=SC2088  # se compara el "~" literal que escribió el modelo, no se expande
  case "$p" in "~"|"~/"*) p="${HOME:-}${p#\~}" ;; esac
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  set -f
  local IFS=/
  for seg in $p; do
    case "$seg" in
      ""|".") ;;
      "..") stack="${stack%/*}" ;;
      *) stack="$stack/$seg" ;;
    esac
  done
  set +f
  printf '%s' "${stack:-/}"
}

# Resuelve symlinks (el archivo y el ancestro existente más profundo) para que un enlace a .claude no sirva de atajo.
resolve_real() { # $1 = ruta absoluta normalizada
  local p="$1" n=0 t d b parent
  while [ -L "$p" ] && [ "$n" -lt 10 ]; do
    t=$(readlink "$p") || break
    case "$t" in /*) p="$t" ;; *) p="${p%/*}/$t" ;; esac
    p=$(norm_path "$p" "/")
    n=$((n + 1))
  done
  d="$p"; b=""
  while [ -n "$d" ] && [ "$d" != "/" ] && [ ! -e "$d" ]; do b="/${d##*/}$b"; d="${d%/*}"; done
  [ -n "$d" ] || d="/"
  if [ -d "$d" ]; then
    d=$(cd -P "$d" 2>/dev/null && pwd -P) || d="$p"
  else
    parent="${d%/*}"; [ -n "$parent" ] || parent="/"
    parent=$(cd -P "$parent" 2>/dev/null && pwd -P) || parent="${d%/*}"
    d="${parent%/}/${d##*/}"
  fi
  printf '%s' "${d%/}$b"
}

# Rutas que cambian el comportamiento de Claude Code (equivale a ejecutar código en esta máquina)
# o el estado de los guardias (.state: reiniciar el reloj de turno debilitaría el límite de tiempo).
is_protected_path() {
  case "$1" in
    */.claude/agents/*|*/.claude/hooks/*|*/.claude/skills/*|*/.claude/commands/*) return 0 ;;
    */.claude/rules/*|*/.claude/output-styles/*|*/.claude/plugins/*|*/.claude/.state/*) return 0 ;;
    */.claude/settings.json|*/.claude/settings.local.json|*/.claude.json) return 0 ;;
    */claude.md|*/claude.local.md) return 0 ;;
    # Configuración de git y de gestores de paquetes que ejecuta código (filtros, submódulos, pre-commit, .npmrc) y el gitfile `.git` de los worktrees.
    */.gitattributes|*/.gitmodules|*/.pre-commit-config.yaml|*/.npmrc|*/.git) return 0 ;;
    # Se ejecutan solos en la máquina del equipo (MCP, hooks de git, tareas de IDE, entorno del shell).
    */.mcp.json|*/.envrc|*/.git/*|*/.githooks/*|*/.husky/*|*/.vscode/*|*/.gitignore) return 0 ;;
  esac
  return 1
}

# CI: solo `devops` puede proponerlo (con confirmación humana); los demás subagentes, no.
is_soft_path() {
  case "$1" in */.github/workflows/*) return 0 ;; esac
  return 1
}

# Agentes que solo escriben documentación: lista permitida (docs/** y README.md), no lista negra.
is_docs_only_agent() {
  case "$1" in architect|dba|requirements-analyst|technical-writer|__invalid__) return 0 ;; esac
  return 1
}

cwd=$(get '.cwd // empty'); [ -n "$cwd" ] || cwd="$PWD"

if [ "$tool" != "Bash" ]; then
  # Todas las rutas del tool_input (file_path, notebook_path, path, también dentro de listas como edits[]).
  paths=$(get '[.tool_input | .. | objects | (.file_path?, .notebook_path?, .path?) | strings] | .[]')
  if [ -z "$paths" ]; then
    hook_warn "sin ruta en tool_input de $tool; guard-writes pide confirmación"
    emit ask "GUARD: no se pudo determinar qué archivo modifica esta llamada. Confirma manualmente."
    exit 0
  fi
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    # shellcheck disable=SC2088  # idem: "~" literal
    case "$raw" in
      "~"|"~/"*) if [ -z "${HOME:-}" ]; then
        emit ask "GUARD: la ruta usa ~ pero HOME no está definido. Confirma manualmente."; exit 0
      fi ;;
    esac
    p=$(lower "$(norm_path "$raw" "$cwd")")
    r=$(lower "$(resolve_real "$p")")
    # Se muestra la cola de la ruta (lo que identifica el archivo), sin caracteres de control.
    # Solo ASCII imprimible (evita cortar un carácter multibyte y UTF-8 inválido en el JSON de salida).
    shown=$(printf '%s' "$r" | LC_ALL=C tr -cd '[:print:]')
    [ "${#shown}" -gt 120 ] && shown="...${shown: -120}"
    if is_soft_path "$p" || is_soft_path "$r"; then
      if $sub && [ "$atype" != "devops" ]; then
        emit deny "GUARD: $who no puede modificar workflows de CI ($shown). Propón el cambio en tu reporte."
      else
        emit ask "GUARD: se va a modificar un workflow de CI ($shown). Revisa permisos del token y acciones fijadas antes de autorizar."
      fi
      exit 0
    fi
    if $sub && is_docs_only_agent "$atype" && ! is_protected_path "$p" && ! is_protected_path "$r"; then
      if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
        emit ask "GUARD: no se pudo determinar la raíz del proyecto para validar dónde escribe $atype. Confirma manualmente."; exit 0
      fi
      root=$(lower "$(resolve_real "$(norm_path "$CLAUDE_PROJECT_DIR" "/")")")
      case "$r" in
        "$root"/docs/*|"$root"/readme.md) ;;
        *) emit deny "GUARD: $atype solo puede escribir en docs/** y README.md ($shown). Propón el cambio en tu reporte."; exit 0 ;;
      esac
    fi
    if is_protected_path "$p" || is_protected_path "$r"; then
      if $sub; then
        emit deny "GUARD: $who no puede modificar la configuración protegida ($shown). Propón el cambio en tu reporte; solo el usuario lo aplica."
      else
        emit ask "GUARD: se va a modificar configuración protegida ($shown). Confirma que lo pediste tú."
      fi
      exit 0
    fi
  done <<EOF
$paths
EOF
  decided=1; exit 0
fi

# ---- Bash ----
cmd=$(get '.tool_input.command // empty')
[ -n "$cmd" ] || { decided=1; exit 0; }
lc=$(lower "$cmd")
# Redirecciones inocuas que no escriben archivos reales.
lc="${lc//2>&1/ }"; lc="${lc//&>\/dev\/null/ }"; lc="${lc//2>\/dev\/null/ }"
lc="${lc//> \/dev\/null/ }"; lc="${lc//>\/dev\/null/ }"; lc="${lc//>&2/ }"
# Colapsa "/./" y "//" para que .claude/./hooks no esquive la búsqueda.
while [[ "$lc" == *"/./"* ]]; do lc="${lc//\/.\//\/}"; done
while [[ "$lc" == *"//"* ]]; do lc="${lc//\/\//\/}"; done
# Continuaciones de línea (\ + salto) cuentan como espacio; un salto de línea suelto separa comandos.
nl=$'\n'; bsnl=$'\\\n'
lc="${lc//"$bsnl"/ }"; lc="${lc//"$nl"/;}"

# Separadores de comando: incluye / \ comillas { } = para ver /bin/rm, \rm, bash -c "rm ..."
SEP=$'(^|[;&|(`{}[:space:]/\\\\"\'=])'
# 1) Subagente lanzando otra instancia de Claude (se ordenarían entre ellos). Solo en POSICIÓN DE COMANDO
#    (tras ; & | ( o envoltorios como env/nohup/xargs/npx/bash -c), para no bloquear `grep claude docs/`.
CMDSTART=$'(^|[;&|(`{])[[:space:]]*'
WRAP='((env|exec|command|nohup|xargs|time|sudo|npx|eval|nice|stdbuf|caffeinate|then|do|else|!|timeout[[:space:]]+(-[a-z]+[[:space:]]+[0-9a-z.]+[[:space:]]+)?[0-9a-z.]+|(ba|z)?sh[[:space:]]+-[a-z]*c|-[a-z-]+([[:space:]]+[^-[:space:];&|][^[:space:];&|]*)?|[a-z_][a-z0-9_]*=[^[:space:]]*)[[:space:]]+)*'
QPATH=$'["\']?(\\\\)?([^[:space:]"\';&|]*/)?'
CTERM=$'([[:space:]"\';)&|]|-code|$)'
RE_CLAUDE="${CMDSTART}${WRAP}${QPATH}claude${CTERM}|anthropic-ai/claude-code"
if $sub && m "$lc" "$RE_CLAUDE"; then
  emit deny "GUARD: $who no puede lanzar otra instancia de Claude. Los agentes no se ordenan entre sí."
  exit 0
fi

# 2) Escritura por Bash sobre configuración protegida. "Menciona" = el comando nombra .claude / CLAUDE*.md
#    o cualquier otra ruta protegida (.git/, .githooks, .husky, .vscode, .mcp.json, .envrc, .gitignore), o se ejecuta desde dentro de .claude (cwd), aunque no escriba la ruta completa.
mentions=false
for s in ".claude" "claude.md" "claude.local.md" ".gitattributes" ".gitmodules" ".pre-commit-config" ".npmrc" ".git/" ".githooks" ".husky" ".vscode" ".mcp.json" ".envrc" ".gitignore"; do
  [[ "$lc" == *"$s"* ]] && { mentions=true; break; }
done
RE_DOTGIT='(^|[^a-z0-9_])[.]git([/;&|[:space:]]|$)'
m "$lc" "$RE_DOTGIT" && mentions=true
lcwd=$(lower "$cwd")
case "$lcwd" in */.claude|*/.claude/*) mentions=true ;; esac
# Globs que podrían apuntar a .claude sin nombrarlo (.clau*, .cl*, .c?aude, .c[l]aude).
RE_GLOB='[.]c[a-z]*[*?[]'
m "$lc" "$RE_GLOB" && mentions=true
# `python -m json.tool` solo lee y formatea: no cuenta como escritura.
lcw="${lc//python3 -m json.tool/}"; lcw="${lcw//python -m json.tool/}"
RE_WRITE="(>|${SEP}(tee|mv|cp|rm|ln|install|truncate|chmod|chown|dd|patch|perl|python[0-9.]*|node|ruby|touch|rsync|unlink|shred|ed|ex|vim?|nano|curl|wget|tar|unzip|sponge|ditto|cpio|scp|emacs|code|cursor|open|zip|gzip|gunzip|bzip2|xz|mkdir|php|deno|bun|osascript|swift|lua|source|eval|xxd)([[:space:]]|\$)|sed[^;&|]*[[:space:]]-[a-z]*i|sed[^;&|]*--in-place|awk[^;&|]*-i[[:space:]]*inplace|sort[^;&|]*[[:space:]]-o|openssl[^;&|]*-out|git[^;&|]*(--output|archive[^;&|]*[[:space:]]-o|format-patch[^;&|]*[[:space:]]-o)|(ba|z)?sh[[:space:]]+[^-[:space:];&|]|find[^;&|]*-exec)"
RE_SEDW=$'sed[^;&|]*([[:space:]\'"/;]w[^[:alpha:]]|/e([[:space:]\'"]|$))'
# `git` con opciones globales entre medias: -c/-C valor, --git-dir X, --flag[=valor], -p, y comillas alrededor de git.
QV=$'("[^"]*"|\'[^\']*\'|[^[:space:]]+)'
GOPT="(-[cC][[:space:]]+${QV}|--(git-dir|work-tree|namespace|exec-path|config-env|super-prefix)[[:space:]=]+${QV}|--[a-z-]+(=${QV})?|-[a-zA-Z])"
GITP=$'["\']?git["\']?'"([[:space:]]+${GOPT})*[[:space:]]+"
RE_GITTREE="${GITP}(checkout|checkout-index|restore|stash|reset|clean|apply|am|rebase|merge|switch|pull|cherry-pick|revert|read-tree|sparse-checkout|submodule|worktree[[:space:]]+add|branch[[:space:]]+(-f|--force))([[:space:]]|\$)"
RE_GITWRITE="${GITP}(commit|commit-tree|update-ref|fast-import)([[:space:]]|\$)"
RE_GITHIST="${GITP}(merge|rebase|pull|cherry-pick|revert|am)([[:space:]]|\$)|gh[[:space:]]+pr[[:space:]]+(create|merge)([[:space:]]|\$)"
# Variantes de solo lectura que no deben contar como cambio del árbol.
lcg="$lc"
for ro in "apply --check" "apply --stat" "apply --numstat" "apply --summary" "stash list" "stash show"; do
  # `apply --stat --apply` SÍ aplica el parche: con --apply no se exime nada de apply.
  case "$ro" in apply*) [[ "$lc" == *"--apply"* ]] && continue ;; esac
  lcg="${lcg//$ro/;}"   # se sustituye por ";" (no por vacío) para que los restos no se unan en un verbo peligroso
done
if $mentions && { m "$lcw" "$RE_WRITE" || m "$lcw" "$RE_SEDW" || m "$lcg" "$RE_GITTREE" || m "$lc" "$RE_GITWRITE"; }; then
  if $sub; then
    emit deny "GUARD: $who no puede modificar configuración protegida (.claude/, CLAUDE*.md, .git/, .mcp.json...) con Bash. Propón el cambio en tu reporte."
  else
    emit ask "GUARD: este comando parece modificar configuración protegida (.claude/, CLAUDE*.md, .git/, .mcp.json...). Confirma que lo pediste tú."
  fi
  exit 0
fi
# git config que ejecuta código (hooks, fsmonitor, ssh, alias): un subagente no; la sesión principal confirma.
GITKEYS='core\.(hookspath|fsmonitor|sshcommand|editor|pager|gitproxy|askpass|worktree|attributesfile|alternaterefscommand)|credential\.|diff\.[^[:space:]]*(external|textconv|command)|gpg\.program|sequence\.editor|filter\.|merge\.[^[:space:]]*driver|uploadpack\.packobjectshook|pager\.|url\.[^[:space:]]*insteadof|protocol\.ext|alias\.|include\.path'
RE_GITCFG="${GITP}config[[:space:]]+[^;&|]*(${GITKEYS})"
# `-c`/`--config-env` justo tras git y sus opciones globales (no en cualquier posición: `git diff -c filter.py` no cuenta).
RE_GITDASHC="[\"']?git[\"']?([[:space:]]+(-[pP]|--no-pager|--[a-z-]+(=[^[:space:]]+)?|-C[[:space:]]+[^[:space:]]+))*[[:space:]]+(-c|--config-env)[[:space:]=]+[\"']?(${GITKEYS})"
RE_GITENV="git_(ssh|ssh_command|dir|work_tree|exec_path|external_diff|askpass|editor|pager|config_(count|key|value|parameters|global|system))="
if m "$lc" "$RE_GITCFG" || m "$lc" "$RE_GITDASHC" || m "$lc" "$RE_GITENV"; then
  if $sub; then emit deny "GUARD: $who no puede cambiar configuración de git que ejecuta código (hooks, fsmonitor, alias). Propónlo en tu reporte."
  else emit ask "GUARD: este comando cambia configuración de git que ejecuta código (hooks, fsmonitor, alias). Confirma que lo pediste tú."; fi
  exit 0
fi
# Un subagente no cambia el árbol de trabajo con git (checkout/restore/apply... pueden reescribir .claude sin nombrarlo).
if $sub && m "$lcg" "$RE_GITTREE"; then
  emit deny "GUARD: $who no puede cambiar el árbol de trabajo con git (puede reescribir configuración protegida). Pídeselo al usuario."
  exit 0
fi

# 3) Commit/historial y borrado/privilegios: siempre autorización del humano, con UN solo aviso que reúne las razones.
reasons=""
if m "$lc" "$RE_GITWRITE" || m "$lc" "$RE_GITHIST"; then
  reasons="commit o cambio de historial git (autoriza solo si viste el mensaje, el autor, los archivos y la rama destino)"
fi
# Borrado o privilegios.
RE_DESTRUCTIVE="${SEP}(rm|rmdir|unlink|shred|sudo|su|chmod|chown|chgrp|mkfs[a-z0-9.]*|dd|truncate|diskutil|launchctl|systemctl|kill|pkill|killall)([[:space:]]|\$)"
RE_DESTRUCTIVE="$RE_DESTRUCTIVE|${GITP}(clean|push|restore|checkout[[:space:]]+(--|-f|\.)|reset[[:space:]]+[^;&|]*--hard|branch[[:space:]]+(-d|--delete)|tag[[:space:]]+-d|stash[[:space:]]+(drop|clear)|filter-branch|worktree[[:space:]]+remove)"
RE_DESTRUCTIVE="$RE_DESTRUCTIVE|docker(-compose)?([[:space:]]+compose)?[[:space:]]+([^;&|]*[[:space:]])?(down|rm|kill)([[:space:]]|\$)|docker[[:space:]]+(rmi|(system|container|image|volume|network|builder|buildx)[[:space:]]+(prune|rm))"
RE_DESTRUCTIVE="$RE_DESTRUCTIVE|find[^;&|]*-delete|rsync[^;&|]*--delete|redis-cli[^;&|]*flush(all|db)|dropdatabase[[:space:]]*\(|kubectl[[:space:]]+delete|terraform[[:space:]]+destroy|drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+table|delete[[:space:]]+from|rimraf|(^|[[:space:];&|])trash[[:space:]]|${GITP}rm([[:space:]]|\$)|drop[[:space:]]+(index|user|role|view|collection)|alter[[:space:]]+table[^;\&|]*drop|\.drop\(|flushall|shutil\.rmtree|os\.(remove|unlink|rmdir)"
if m "$lc" "$RE_DESTRUCTIVE"; then
  reasons="${reasons:+$reasons; }borrado o acción con privilegios (autoriza solo si borra algo que el agente creó en esta tarea; rechaza si toca código o archivos existentes de otros)"
fi
RE_DOCKERRISK="docker(-compose)?[^;&|]*(--privileged|--(network|net|pid|ipc|userns|uts)[[:space:]=]+[\"']?host|--pid[[:space:]=]|--cap-add|--device|docker\\.sock|--env-file|--security-opt[[:space:]=]+[\"']?(seccomp|apparmor|label|systempaths)|--security-opt[[:space:]=]+[\"']?no-new-privileges[=:]false|(-v|--volume)[[:space:]=]*[\"']?(/:|~|\\\$home|\\\$\\{home|/(users|home)/[^/:[:space:]\"']+/?[:\"'[:space:]])|--mount[^;&|]*(src|source)=[\"']?(/|~|\\\$home)|-p[[:space:]=]*[\"']?0\\.0\\.0\\.0|(-p|--publish)[[:space:]=]*[\"']?[0-9]+([:/-]|[[:space:]\"']|\$)|(-v|--volume)[[:space:]=]*[\"']?(\\.\\.?/?|\\\$pwd|\\\$\\{pwd\\}|\\\$\\(pwd\\))[:\"'[:space:]]|(-v|--volume)[[:space:]=]*[\"']?[^[:space:]:]*\\.(claude|git)([/:\"'[:space:]]|\$)|--mount[^;&|]*(src|source)=[\"']?(\\.\\.?/?|\\\$pwd|\\\$\\{pwd\\}|\\\$\\(pwd\\))([,\"'[:space:]]|\$)|[[:space:]]pull[[:space:]])"
# `-P` (publicar todos los puertos) se distingue de `-p` solo en el texto original (lc lo pasa a minúsculas).
RE_DOCKERP='docker[^;&|]*[[:space:]]-P([[:space:]]|$)'
if m "$lc" "$RE_DOCKERRISK" || m "$cmd" "$RE_DOCKERP"; then
  reasons="${reasons:+$reasons; }docker fuera de la lista cerrada (privileged, red host, socket, env-file, puerto sin 127.0.0.1, montaje de /, HOME o de la raíz del repo, pull de imagen)"
fi
if [ -n "$reasons" ]; then
  emit ask "GUARD: $who ejecuta: $reasons. Revisa el comando completo antes de autorizar."
fi
decided=1
exit 0
