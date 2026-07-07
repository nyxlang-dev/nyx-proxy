# nyx-proxy — Portable Makefile
# Prerequisites: Nyx toolchain installed
#   curl -sSf https://nyxlang.com/install.sh | sh
BINARY = nyx-proxy
.PHONY: build clean
build:
	nyx build
clean:
	rm -f $(BINARY)
