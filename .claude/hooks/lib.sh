# shellcheck shell=bash
# Utilidades comunes de los hooks (se hace `source` desde cada script).
# Política: el límite de tiempo es fail-open (nunca bloquea el trabajo por un fallo del propio hook),
# pero jamás falla en silencio: todo se avisa por stderr.

hook_warn() { echo "[hooks] $*" >&2; }

hook_require_jq() {
  command -v jq >/dev/null 2>&1 || { hook_warn "jq no disponible; límite de tiempo inactivo"; return 1; }
}

# Directorio de estado: CLAUDE_PROJECT_DIR, o la raíz del repo git como respaldo.
hook_state_dir() {
  local base="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$base" ] || base=$(git rev-parse --show-toplevel 2>/dev/null) || base=""
  [ -n "$base" ] || { hook_warn "CLAUDE_PROJECT_DIR no definido y fuera de un repo git; límite de tiempo inactivo"; return 1; }
  printf '%s/.claude/.state' "$base"
}

# session_id viene de stdin (no confiable): se convierte en hash para usarlo como nombre de archivo.
# Falla (return 1) si no hay herramienta de hash, para que ninguna sesión comparta archivo de estado.
hook_session_key() {
  local key=""
  if command -v shasum >/dev/null 2>&1; then key=$(printf '%s' "$1" | shasum | cut -c1-40)
  elif command -v sha1sum >/dev/null 2>&1; then key=$(printf '%s' "$1" | sha1sum | cut -c1-40)
  fi
  [ -n "$key" ] || { hook_warn "sin shasum/sha1sum; límite de tiempo inactivo"; return 1; }
  printf '%s' "$key"
}

# Entero sin signo (hasta 12 dígitos) o el valor por defecto. Evita evaluación aritmética de texto arbitrario.
hook_uint_or() { if [[ "$1" =~ ^[0-9]{1,12}$ ]]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
