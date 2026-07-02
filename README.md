# nyx-proxy

HTTPS reverse proxy **library** for [Nyx](https://nyxlang.com). Provides TLS
termination, SNI multi-domain routing, virtual host dispatch, connection pooling,
active health checks, per-IP rate limiting, **response caching (LRU + TTL)**,
**Prometheus `/metrics`**, and access logging. Consume it as a package in
`nyx.toml` to build your own gateway — it is not a standalone daemon.

Librería de reverse proxy HTTPS para [Nyx](https://nyxlang.com). Ofrece TLS
termination, routing SNI multi-dominio, virtual hosts, connection pooling, health
checks activos, rate limiting por IP, **cache de respuestas (LRU + TTL)**,
**endpoint `/metrics` Prometheus** y access logs. Se consume como paquete en
`nyx.toml` para construir tu propio gateway — no es un daemon independiente.

---

## Install

Install the Nyx toolchain:

```bash
curl -sSf https://nyxlang.com/install.sh | sh
```

## Quick start

```bash
git clone https://github.com/nyxlang-dev/nyx-proxy
cd nyx-proxy
nyx build
./nyx-proxy   # HTTP smoke test — reads ./proxy.toml
```

## Usage

Declare the dependency in your gateway project:

```toml
# nyx.toml
[package]
name = "my-gateway"
main = "src/main.nx"

[dependencies]
nyx-proxy = "*"
```

Wire config, router, and health checker:

```nyx
import "nyx-proxy/src/config"
import "nyx-proxy/src/router"
import "nyx-proxy/src/health"

fn main() {
    load_config("proxy.toml")
    health_start()
    proxy_listen()
}
```

Minimal `proxy.toml`:

```toml
[server]
listen = 443

[upstream.0]
name    = "app"
host    = "127.0.0.1"
port    = 3000

[vhost.0]
domain  = "example.com"
backend = "app"

[health]
interval_ms = 5000
threshold   = 3

[rate]
requests_per_second = 100

[logging]
path = "/var/log/nyx-proxy/access.log"

# Response cache LRU (v0.3+). Solo cachea GET 200 y honra Cache-Control
# del upstream (no-store / no-cache / private bypassean, max-age=N override).
[cache]
enabled = 1
max_entries = 10000
default_ttl_seconds = 300

# /metrics Prometheus en puerto admin separado (v0.3+). Default 127.0.0.1
# para no exponer metricas a internet.
[metrics]
enabled = 1
bind = "127.0.0.1"
port = 9090
```

### Cache y `/metrics` (v0.3+)

Con `[cache].enabled = 1`, responses `GET 200` se cachean bajo
`HOST:PATH`. Los hits emiten `X-Nyx-Cache: HIT`:

```bash
$ curl -sD - http://proxy/ -o /dev/null | grep X-Nyx-Cache
X-Nyx-Cache: HIT
```

Con `[metrics].enabled = 1` un listener admin separado sirve
`/metrics` y `/healthz`:

```bash
$ curl http://127.0.0.1:9090/metrics | head -20
# HELP nyx_proxy_requests_total Total HTTP requests processed by the proxy.
# TYPE nyx_proxy_requests_total counter
nyx_proxy_requests_total{host="example.com",status="2xx"} 142
# HELP nyx_proxy_cache_hits_total Cache lookups that served a hit.
# TYPE nyx_proxy_cache_hits_total counter
nyx_proxy_cache_hits_total 87
```

Metricas expuestas: `nyx_proxy_requests_total{host,status}`,
`nyx_proxy_cache_{hits,misses,evictions}_total`, `nyx_proxy_cache_size`,
`nyx_proxy_cache_capacity`,
`nyx_proxy_upstream_latency_ms_{sum,count}{host}`,
`nyx_proxy_ratelimit_rejects_total{host}`,
`nyx_proxy_uptime_seconds`.

Expected output on startup:

```
[nyx-proxy] TLS ready — listening on :443
[nyx-proxy] health checker started (5000ms interval)
```

Test the smoke test (HTTP mode):

```bash
curl http://localhost:8080/
```

## Configuration

Full reference in [`docs/CONFIG.md`](docs/CONFIG.md). Key sections:

| Section | Purpose |
|---------|---------|
| `[server]` | `listen`, `workers` |
| `[upstream.N]` | `name`, `host`, `port` |
| `[vhost.N]` | `domain`, `backend`, optional `path_prefix` |
| `[health]` | `interval_ms`, `threshold` |
| `[rate]` | `requests_per_second` per IP |
| `[logging]` | `path` for access log |
| `[cache]` | `enabled`, `max_entries`, `default_ttl_seconds` (v0.3+) |
| `[metrics]` | `enabled`, `bind`, `port` (v0.3+) |

## Documentation

- [`docs/CONFIG.md`](docs/CONFIG.md) — Full `proxy.toml` reference

## Limitations

- HTTP/1.1 to backends only — no HTTP/2 upstream
- No WebSocket proxy support
- Health checks are TCP-only (no HTTP endpoint probing)
- TLS mode defaults to port 443 (configurable in `src/config.nx`)
- Response cache ignores `Vary` header (v0.3 key is `host:path` only)
- No single-flight / request coalescing on cache miss (thundering herd possible)

## License

Apache 2.0 — see [LICENSE](./LICENSE)
