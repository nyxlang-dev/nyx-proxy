# nyx-proxy

Reverse proxy **library** for [Nyx](https://nyxlang.com). TLS, SNI,
virtual hosts, path-prefix routing, connection pooling, rate limiting,
health checks and access logs. Consumed as a package by concrete
gateway projects.

## Features

- **TLS + SNI**: Register any number of certificates at startup, one
  binary can terminate several domains with distinct certs
- **Routing**: Host-based virtual hosts and longest-prefix path matching
- **Connection pooling**: Keep-alive reuse against backends, honors
  upstream `Connection: close`
- **Rate limiting**: Sliding window, per-IP, configurable via TOML
- **Health checks**: Active TCP probes with failure threshold
- **Access logs**: Append-only, method/path/status/latency per request
- **~170KB** self-contained binary once linked by a consumer

## How to use

`nyx-proxy` is not meant to be run as-is. It is a library: you build
**your own gateway project** that imports the modules you need and
decides where to listen, which certs to load, and how to wire TLS.

Minimal consumer (`nyx.toml`):

```toml
[package]
name = "my-gateway"
main = "src/main.nx"

[dependencies]
nyx-proxy = "*"
```

Minimal consumer (`src/main.nx`):

```nyx
import "nyx-proxy/src/config"
import "nyx-proxy/src/router"
import "nyx-proxy/src/health"

fn main() {
    load_config("proxy.toml")
    // tls_server_init / tls_server_add_cert / tcp_listen / tls_worker
    // ...
}
```

For a full example see **`examples/standalone.nx`** (HTTP-only smoke
test) or **`services/gateway/`** in the main NyxLang repository
(production HTTPS gateway for `nyxlang.com`, with TLS, SNI for four
domains, and an HTTP→HTTPS redirect on port 80).

## Build the standalone smoke test

```bash
make build           # compiles examples/standalone.nx
./nyx-proxy          # reads ./proxy.toml, HTTP mode only
```

This binary is a development aid — it lets you exercise the router,
pool and rate limiter against real traffic without needing TLS certs.
For anything public-facing, use the gateway pattern above.

## Library modules

| Module | Purpose |
|---|---|
| `src/config.nx` | TOML parser, populates routing state, honors optional TLS |
| `src/router.nx` | Virtual host + path-prefix dispatch, connection pool, upstream forwarding |
| `src/health.nx` | Active TCP health checker, failure threshold, auto-recovery |
| `src/logger.nx` | Append-only access log (method path status latency_ms) |
| `src/ratelimit.nx` | Sliding-window rate limit per client IP |

## Benchmark

~4,300 req/s HTTPS on AWS `t4g.micro` ARM64.

## License

Apache 2.0 — see [LICENSE](../../LICENSE)

---
*Library used by [nyxlang.com](https://nyxlang.com), [nyxkv.com](https://nyxkv.com), `serve.nyxlang.com` and `proxy.nyxlang.com` through a single gateway binary in `services/gateway/`.*
