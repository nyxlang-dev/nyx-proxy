#!/usr/bin/env bash
# Prueba de punta a punta del frente HTTP/2 (src/h2front.nx) con un cliente
# real: curl con nghttp2. Levanta un backend std/serve con un canal SSE y el
# gateway de prueba delante, con TLS y `http2 = true`.
#
# El caso que motiva todo (fricción de nyxerp, 2026-11-13): con HTTP/1.1 un
# navegador da 6 conexiones por dominio y cada SSE ocupa una; la petición
# siguiente espera. Acá van 8 SSE y un GET por UNA conexión.
#
# SKIP limpio si curl no trae HTTP/2 u openssl no está.
set -u
STACK="$(cd "$(dirname "$0")/../.." && pwd)"
NYX_HOME="${NYX_HOME:-/home/admin/nyxlang}"
export NYX_HOME
if ! curl --version 2>/dev/null | grep -q "HTTP2"; then echo "SKIP e2e_h2: curl sin HTTP/2"; exit 0; fi
if ! command -v openssl >/dev/null 2>&1; then echo "SKIP e2e_h2: sin openssl"; exit 0; fi
BP="${E2E_H2_BACKEND_PORT:-19481}"
GP="${E2E_H2_GATEWAY_PORT:-19482}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nyx-proxy-e2e-h2.XXXXXX")"
PIDS=""
trap 'for p in $PIDS; do kill -9 $p 2>/dev/null; done; rm -rf "$WORK"' EXIT

build() {   # build <nombre> <fuente>
    mkdir "$WORK/$1" && cp "$2" "$WORK/$1/script.nx" || return 1
    (cd "$WORK/$1" && NYX_PROJECT_DIR="$STACK" "$NYX_HOME/nyx_bootstrap" >build.log 2>&1) || { echo "FAIL e2e_h2: compilación de $1"; tail -5 "$WORK/$1/build.log"; return 1; }
    (cd "$WORK/$1" && clang -O2 script.ll "$NYX_HOME"/runtime/*.c "$NYX_HOME/runtime/os/os_posix.c" \
        -lgc -lpthread -ldl -lm -lssl -lcrypto -lz -o bin >link.log 2>&1) || { echo "FAIL e2e_h2: clang de $1"; tail -5 "$WORK/$1/link.log"; return 1; }
}
build backend "$STACK/tests/e2e_h2/backend.nx" || exit 1
build gateway "$STACK/tests/e2e_h2/gateway.nx" || exit 1

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/k.pem" -out "$WORK/c.pem" -days 2 -subj "/CN=localhost" 2>/dev/null
cat > "$WORK/proxy.toml" <<TOML
[server]
listen = $GP
workers = 4
tls_cert = "$WORK/c.pem"
tls_key = "$WORK/k.pem"
http2 = true

[upstream.0]
name = "app"
host = "127.0.0.1"
port = $BP
TOML

"$WORK/backend/bin" "$BP" >"$WORK/backend.log" 2>&1 & PIDS="$PIDS $!"; disown
(cd "$WORK" && exec "$WORK/gateway/bin" "$WORK/proxy.toml") >"$WORK/gateway.log" 2>&1 & PIDS="$PIDS $!"; disown
U="https://127.0.0.1:$GP"
for _ in $(seq 1 60); do curl -sk --max-time 1 --http2 -o /dev/null "$U/hola" 2>/dev/null && break; sleep 0.1; done

FAIL=0
check() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1: esperaba «$3», dio «${2:0:300}»"; FAIL=1; fi; }

check "el gateway negocia HTTP/2" "$(curl -sk --max-time 5 --http2 -w ' %{http_version} %{http_code}' "$U/hola")" "hola 2 200"
check "un cliente HTTP/1.1 sigue funcionando" "$(curl -sk --max-time 5 --http1.1 -w ' %{http_version} %{http_code}' "$U/hola")" "hola 1.1 200"
check "POST con cuerpo" "$(curl -sk --max-time 5 --http2 -d 'hola cuerpo' "$U/eco")" "hola cuerpo"
check "cuerpo de 300 KB íntegro" "$(curl -sk --max-time 10 --http2 "$U/grande" | sha256sum | cut -c1-16)" "$(python3 -c "import hashlib;print(hashlib.sha256(('0123456789abcdef'*64*293).encode()).hexdigest()[:16])")"
check "X-Forwarded-Proto, cookies unidas y X-Forwarded-For" "$(curl -sk --max-time 5 --http2 -H 'Cookie: a=1' -H 'Cookie: b=2' "$U/cabeceras")" "proto=https cookie=a=1; b=2 xff=127.0.0.1"
# El upstream es un servidor HTTP/1.1 que busca "Cookie" y "Content-Type" con
# esas mayúsculas exactas (std/serve). En HTTP/2 los nombres viajan en
# minúsculas: el gateway los devuelve a su forma canónica al reescribir.
ESPERADO="form.a=1 cookie.s=abc ctype=application/x-www-form-urlencoded"
check "formulario y cookie de sesión por HTTP/2" "$(curl -sk --max-time 5 --http2 -H 'Cookie: s=abc' -d 'a=1' "$U/entendido")" "$ESPERADO"
check "lo mismo por HTTP/1.1 (referencia)" "$(curl -sk --max-time 5 --http1.1 -H 'Cookie: s=abc' -d 'a=1' "$U/entendido")" "$ESPERADO"
check "404 del upstream" "$(curl -sk --max-time 5 --http2 -o /dev/null -w '%{http_code}' "$U/nada")" "404"

# Un SSE solo: llegan eventos mientras el canal sigue abierto.
SSE=$(curl -sk --max-time 2 --http2 -N "$U/avisos" 2>/dev/null | grep -c '^event: tick')
if [ "$SSE" -ge 3 ]; then echo "  ✓ SSE como flujo HTTP/2: $SSE eventos en 2 s"; else echo "  ✗ SSE: $SSE eventos en 2 s"; FAIL=1; fi

# El caso del reporte: 8 SSE abiertos y un GET, todo por una conexión. El GET
# tiene que volver enseguida aunque los 8 canales sigan abiertos.
ARGS=()
for i in 1 2 3 4 5 6 7 8; do ARGS+=(-o "$WORK/sse$i.txt" "$U/avisos"); done
ARGS+=(-o "$WORK/hola.txt" "$U/hola")
curl -sk --max-time 4 --http2 --parallel --parallel-max 20 -N \
    -w '%{url} %{http_code} %{time_total} %{num_connects}\n' "${ARGS[@]}" >"$WORK/par.txt" 2>/dev/null
check "GET con 8 SSE abiertos en la misma conexión" "$(cat "$WORK/hola.txt" 2>/dev/null)" "hola"
T_HOLA=$(grep '/hola ' "$WORK/par.txt" | awk '{print $3}')
if python3 -c "import sys; sys.exit(0 if float('${T_HOLA:-9}') < 1.0 else 1)"; then echo "  ✓ ese GET tardó ${T_HOLA}s (menos de 1 s)"; else echo "  ✗ ese GET tardó ${T_HOLA:-?}s"; FAIL=1; fi
CONNS=$(awk '{s+=$4} END{print s+0}' "$WORK/par.txt")
check "las 9 peticiones usaron una sola conexión" "$CONNS" "1"
VIVOS=0; for i in 1 2 3 4 5 6 7 8; do [ "$(grep -c '^event: tick' "$WORK/sse$i.txt" 2>/dev/null)" -ge 3 ] && VIVOS=$((VIVOS+1)); done
check "los 8 canales SSE recibieron eventos" "$VIVOS" "8"

# Una petición lenta no frena a las demás del mismo navegador.
ARGS=(-o "$WORK/lento.txt" "$U/lento" -o "$WORK/rapido.txt" "$U/hola")
curl -sk --max-time 6 --http2 --parallel -w '%{url} %{time_total}\n' "${ARGS[@]}" >"$WORK/par2.txt" 2>/dev/null
T_RAP=$(grep '/hola ' "$WORK/par2.txt" | awk '{print $2}')
if python3 -c "import sys; sys.exit(0 if float('${T_RAP:-9}') < 1.0 else 1)"; then echo "  ✓ una petición de 1,5 s no frena a otra de la misma conexión (${T_RAP}s)"; else echo "  ✗ la rápida tardó ${T_RAP:-?}s detrás de la lenta"; FAIL=1; fi
check "la lenta también responde" "$(cat "$WORK/lento.txt" 2>/dev/null)" "lento"

# Tras irse los clientes, el gateway cerró sus conexiones SSE al backend: el
# backend ya no cuenta ningún canal abierto (no quedan túneles colgados).
CUENTA=9
for _ in $(seq 1 30); do CUENTA=$(curl -sk --max-time 2 --http2 "$U/cuenta"); [ "$CUENTA" = "0" ] && break; sleep 0.2; done
check "sin canales SSE colgados después de irse los clientes" "$CUENTA" "0"
check "el gateway sigue respondiendo después de todo" "$(curl -sk --max-time 5 --http2 "$U/hola")" "hola"

if [ "$FAIL" -ne 0 ]; then echo "--- gateway.log"; tail -15 "$WORK/gateway.log"; echo "FAIL e2e_h2"; exit 1; fi
echo "PASS e2e_h2"
