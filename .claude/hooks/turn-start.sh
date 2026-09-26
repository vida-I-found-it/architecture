#!/usr/bin/env bash
# UserPromptSubmit: marca el inicio del turno (cada prompt del usuario reinicia el reloj de 5 min).
set -u
source "${0%/*}/lib.sh"
hook_require_jq || exit 0
dir=$(hook_state_dir) || exit 0
sid=$(jq -r '.session_id // empty' 2>/dev/null) || sid=""
[ -n "$sid" ] || { hook_warn "session_id ausente o JSON inválido; límite de tiempo inactivo"; exit 0; }

key=$(hook_session_key "$sid") || exit 0
{ mkdir -p "$dir" && chmod 700 "$dir"; } || { hook_warn "no se pudo preparar $dir; límite de tiempo inactivo"; exit 0; }
# Escritura atómica: el guard nunca lee un archivo a medio escribir.
tmp=$(mktemp "$dir/.tmp.XXXXXX") \
  && date +%s > "$tmp" \
  && mv "$tmp" "$dir/turn-start-$key" \
  || { hook_warn "no se pudo registrar el inicio del turno; límite de tiempo inactivo"; [ -n "${tmp:-}" ] && rm -f "$tmp"; exit 0; }
# Limpieza de estados antiguos y temporales huérfanos.
find "$dir" \( -name 'turn-start-*' -o -name '.tmp.*' \) -mtime +1 -delete 2>/dev/null
exit 0
