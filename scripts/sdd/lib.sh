# scripts/sdd/lib.sh — funciones compartidas del método SDD-nyx.
# Spec: docs/design/specs/2026-09-02-sdd-nyx-design.md (§2 banner, §4 ledger, §8 scripts).
# Se hace `source` desde los demás scripts de scripts/sdd/: no es ejecutable, no imprime
# nada al cargarse y no cambia el cwd. Regla del repo: `set -u` sin `pipefail`, así que
# ninguna función de acá depende del código de salida de un pipe.
# Por qué un único archivo: la ruta del ledger y el formato del banner son el contrato que
# comparten task-brief, review-package, index-gen, state-check y (Task 3) arc-new/brief/
# arc-close. Duplicarlos es cómo se pudren los métodos — una sola definición, un solo lugar
# donde cambiarlos.

# Banner canónico de línea 1 (spec §2). El sufijo tras « — » es libre y opcional.
# BORRADOR es el estado de un arco sembrado y todavía sin GO: legal en main (así es como se
# aprueba, leyéndolo), pero sin los derechos de un VIGENTE — ver state-check (i).
BANNER_RE='^> \*\*ESTADO: (BORRADOR|VIGENTE|COMPLETO|SUPERSEDED por `[^`]+`|EXPLORADO|ABANDONADO)\*\*( — .+)?$'

die() { printf 'sdd: %s\n' "$*" >&2; exit 1; }

# Raíz del repo. DOCS_HEALTH_ROOT (la misma variable que usa run_docs_health.sh) permite
# apuntar los scripts a un árbol alternativo — el fixture del selftest, sin tocar el repo real.
root_dir() {
    if [ -n "${DOCS_HEALTH_ROOT:-}" ]; then printf '%s\n' "$DOCS_HEALTH_ROOT"
    else git rev-parse --show-toplevel; fi
}

# Estado del banner (VIGENTE|COMPLETO|SUPERSEDED|EXPLORADO|ABANDONADO), vacío si no hay banner.
banner_of() {
    [ -f "$1" ] || return 0
    head -1 "$1" | grep -E "$BANNER_RE" | sed -E 's/^> \*\*ESTADO: ([A-Z]+).*/\1/'
}

# Texto libre tras « — » en el banner; vacío si no lo hay.
banner_suffix() {
    [ -f "$1" ] || return 0
    head -1 "$1" | sed -nE 's/^> \*\*ESTADO: [^*]+\*\* — (.*)$/\1/p'
}

# Ruta de un archivo relativa a la raíz del repo. La línea de identidad del ledger
# («# SDD ledger — plan: <ruta>») la escribe ledger-new con este formato, así que arc-close
# tiene que normalizar igual antes de comparar: `./docs/…`, una ruta absoluta y `docs/…` son
# el MISMO plan. Fuera del árbol devuelve la ruta tal cual vino.
rel_path() {
    local abs root
    root=$(cd "$(root_dir)" 2>/dev/null && pwd -P) || { printf '%s\n' "$1"; return 0; }
    abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1")" || { printf '%s\n' "$1"; return 0; }
    case "$abs" in "$root"/*) printf '%s\n' "${abs#"$root"/}" ;; *) printf '%s\n' "$1" ;; esac
}

# Reescribe la línea 1 de un documento de diseño. Sin `sed -i "1s#…#"` a propósito: el sufijo
# es texto libre (el motivo de un --abandon puede traer «#», «/» o «&»). `cp` y no `mv` desde
# el temporal, para no dejarle al documento los permisos 600 de mktemp.
banner_set() {   # banner_set ARCHIVO LÍNEA
    local tmp; tmp=$(mktemp) || die "mktemp falló"
    { printf '%s\n' "$2"; tail -n +2 "$1"; } > "$tmp" && cp "$tmp" "$1" || die "no se pudo escribir $1"
    rm -f "$tmp"
}

base_of() { basename "$1" .md; }
slug_of() { base_of "$1" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//'; }

# La ruta del ledger es DERIVABLE del plan: ningún documento la cita (spec §1).
ledger_dir() { printf '%s/.sdd/%s\n' "$(root_dir)" "$(base_of "$1")"; }
