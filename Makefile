# Makefile — nyx-proxy-stack
# El toolchain Nyx vive fuera de este repo; se apunta vía NYX_HOME.

NYX_HOME ?= /home/admin/nyx/lang
export NYX_HOME

.PHONY: build test-proxy sdd-check docs-health clean

# Compila la lib vía examples/standalone.nx (binario de referencia HTTP-only,
# smoke de la API pública). El consumer de producción es ~/nyx-gateway.
build:
	nyx build

# Unit tests .nx sin servidores: cache LRU, histogramas Prometheus, XFF.
test-proxy:
	bash scripts/run_unit_tests.sh

clean:
	rm -f nyx-proxy script.nx script.ll nyx.lock

# Selftest del método SDD — control positivo de scripts/sdd/.
sdd-check:
	bash scripts/sdd/selftest

# Guardas de la documentación de diseño: el INDEX no puede mentir sobre el estado
# de un arco, y state-check es la lista de reglas del método. Son los dos checks
# que arc-close corre antes de commitear un cierre.
docs-health:
	bash scripts/sdd/index-gen --check
	bash scripts/sdd/state-check
