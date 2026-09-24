#!/bin/bash
# run_unit_tests.sh — corre los unit tests .nx del proxy (cache/metrics/xff/retry)
# compilándolos con el bootstrap del toolchain (NYX_HOME). Sin servidores.
# Adaptado de run_product_unit_tests.sh del monorepo al extraerse (split #7,
# 2026-07-06).
#
# Cada corrida compila en un directorio PROPIO de mktemp, nunca en $NYX_HOME.
# Hasta 2026-09-24 copiaba cada suite a $NYX_HOME/script.nx, un archivo único del
# toolchain: dos corridas a la vez (de este repo o de cualquiera con el mismo
# NYX_HOME) se pisaban, y una podía ejecutar el binario de la otra sin ningún
# error que lo delatara. Es la misma carrera que el lenguaje arregló en `nyx test`
# el 2026-09-20. De NYX_HOME solo se LEE: el bootstrap, std/ y runtime/.
#
# El bootstrap busca std/ primero en el cwd y después en $NYX_HOME/std, así que
# el directorio de trabajo NO debe tener un std/ propio.
#
# Lo que esto NO aísla: los puertos fijos (19350+) y los archivos de /tmp que
# usan las suites. Dos corridas simultáneas chocan ahí, pero fallan a la vista
# (bind rechazado), no en silencio.
set -uo pipefail
STACK="$(cd "$(dirname "$0")/.." && pwd)"
NYX_HOME="${NYX_HOME:-/home/admin/nyx/lang}"
export NYX_HOME
cd "$STACK"
TESTS="test_proxy_cache test_proxy_metrics test_proxy_xff test_proxy_retry test_proxy_config_listen test_proxy_time test_proxy_pool_framing test_proxy_sse_tunnel test_proxy_sse_tls test_proxy_fwd_headers"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nyx-proxy-tests.XXXXXX")" || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
for name in $TESTS; do
    src="tests/${name}.nx"
    if [ ! -f "$src" ]; then
        echo "FAIL $name: NO EXISTE (¿suite borrada/renombrada? actualizar TESTS)"
        fail=$((fail+1)); continue
    fi
    dir="$WORK/$name"
    mkdir "$dir"
    cp "$src" "$dir/script.nx"
    if ! (cd "$dir" && NYX_PROJECT_DIR="$STACK" "$NYX_HOME/nyx_bootstrap" >build.log 2>&1); then
        echo "FAIL $name (compilación)"
        tail -5 "$dir/build.log"
        fail=$((fail+1)); continue
    fi
    if ! (cd "$dir" && clang -O2 script.ll "$NYX_HOME"/runtime/*.c "$NYX_HOME/runtime/os/os_posix.c" \
              -lgc -lpthread -ldl -lm -lssl -lcrypto -lz -o script_bin >link.log 2>&1); then
        echo "FAIL $name (clang)"
        tail -5 "$dir/link.log"
        fail=$((fail+1)); continue
    fi
    if out=$(cd "$dir" && timeout 60 ./script_bin 2>&1); then
        if echo "$out" | grep -q "ASSERTION FAILED"; then
            echo "FAIL $name (assertion)"
            echo "$out" | tail -5
            fail=$((fail+1))
        else
            cases=$(echo "$out" | grep -c "^PASS")
            echo "ok $name ($cases casos)"
            pass=$((pass+1))
        fi
    else
        echo "FAIL $name"
        echo "$out" | tail -5
        fail=$((fail+1))
    fi
done
echo "Suites: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
