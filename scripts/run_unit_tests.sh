#!/bin/bash
# run_unit_tests.sh — corre los unit tests .nx del proxy (cache/metrics/xff/retry)
# compilándolos con el bootstrap del toolchain (NYX_HOME). Sin servidores.
# Adaptado de run_product_unit_tests.sh del monorepo al extraerse (split #7,
# 2026-07-06).
#
# OJO: usa $NYX_HOME/script.nx compartido — NO correr en paralelo con suites
# del monorepo (regla preexistente: los runners nunca se solapan).
set -uo pipefail
STACK="$(cd "$(dirname "$0")/.." && pwd)"
NYX_HOME="${NYX_HOME:-/home/admin/nyx/lang}"
cd "$STACK"
TESTS="test_proxy_cache test_proxy_metrics test_proxy_xff test_proxy_retry test_proxy_config_listen"
pass=0; fail=0
for name in $TESTS; do
    src="tests/${name}.nx"
    if [ ! -f "$src" ]; then
        echo "FAIL $name: NO EXISTE (¿suite borrada/renombrada? actualizar TESTS)"
        fail=$((fail+1)); continue
    fi
    cp "$src" "$NYX_HOME/script.nx"
    if out=$(cd "$NYX_HOME" && NYX_PROJECT_DIR="$STACK" ./nyx_bootstrap >/dev/null 2>&1 && \
             clang -O2 script.ll runtime/*.c runtime/os/os_posix.c -lgc -lpthread -ldl -lm -lssl -lcrypto -lz -o script_bin 2>/dev/null && \
             timeout 60 ./script_bin 2>&1); then
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
    rm -f "$NYX_HOME/script.nx" "$NYX_HOME/script.ll" "$NYX_HOME/script_bin"
done
echo "Suites: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
