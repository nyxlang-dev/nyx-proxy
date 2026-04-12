# nyx-proxy Makefile
#
# nyx-proxy is a library (products/proxy/src/*.nx) consumed by gateway
# projects (see services/gateway/). `make build` compiles the standalone
# example from examples/standalone.nx — a smoke test that produces an
# HTTP-only reference binary. For the production HTTPS gateway, build
# from services/gateway/ instead.

BINARY = nyx-proxy
MAIN = examples/standalone.nx
NYX_ROOT ?= $(abspath ../..)

.PHONY: build clean

build:
	cd $(NYX_ROOT) && cp products/proxy/$(MAIN) script.nx && \
	NYX_PROJECT_DIR=products/proxy ./nyx_bootstrap && \
	clang -O2 script.ll runtime/*.c -lgc -lpthread -ldl -lm -lssl -lcrypto -lz -o products/proxy/$(BINARY) && \
	rm -f script.nx script.ll
	@echo "Built $(BINARY) ($$(ls -lh $(BINARY) | awk '{print $$5}'))"

clean:
	rm -f $(BINARY) script.nx script.ll
