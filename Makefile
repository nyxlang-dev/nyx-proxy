# Makefile — nyx-proxy-stack
# El toolchain Nyx vive fuera de este repo; se apunta vía NYX_HOME.

NYX_HOME ?= /home/admin/nyx/lang
export NYX_HOME

.PHONY: build test-proxy clean

# Compila la lib vía examples/standalone.nx (binario de referencia HTTP-only,
# smoke de la API pública). El consumer de producción es ~/nyx-gateway.
build:
	nyx build

# Unit tests .nx sin servidores: cache LRU, histogramas Prometheus, XFF.
test-proxy:
	bash scripts/run_unit_tests.sh

clean:
	rm -f nyx-proxy script.nx script.ll nyx.lock
