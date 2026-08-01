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

Wire the library modules (config parsing, health checker, dispatch):

```nyx
import "nyx-proxy/src/config"
import "nyx-proxy/src/router"
import "nyx-proxy/src/health"

fn main() {
    load_config("proxy.toml")
    thread_spawn(health_checker)
    // ... spawn workers that accept connections and call proxy_dispatch()
    // Full working versions: examples/standalone.nx (HTTP) and
    // examples/gateway-tls/ (HTTPS + SNI — see docs/TUTORIAL.md)
}
```

Minimal `proxy.toml` (every key below exists in `src/config.nx` — the
authoritative schema):

```toml
[server]
listen = 8080
workers = 64
# Per-IP requests/second; 0 = disabled
rate_limit = 100
# TCP health checks (seconds / consecutive failures to mark unhealthy)
health_check_interval = 10
health_check_threshold = 3
access_log = "/var/log/nyx-proxy/access.log"
# TLS: set both to enable HTTPS. With TLS on, `listen` defaults to 443
# unless set explicitly (v0.4.1+).
# tls_cert = "/etc/letsencrypt/live/example.com/fullchain.pem"
# tls_key  = "/etc/letsencrypt/live/example.com/privkey.pem"

# Virtual host: routed when the Host header matches `hostname`
[upstream.0]
name     = "app"
host     = "127.0.0.1"
port     = 3000
hostname = "example.com"

# No hostname and no path_prefix -> default catch-all upstream
[upstream.1]
name = "fallback"
host = "127.0.0.1"
port = 3000

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

Test the smoke test (HTTP mode):

```bash
curl http://localhost:8080/
```

## Tutorial

**[docs/TUTORIAL.md](docs/TUTORIAL.md)** ([español](docs/TUTORIAL.es.md)) walks
through building a real multi-domain HTTPS gateway on this library — TLS
termination with SNI, HTTP→HTTPS redirect, WebSocket passthrough, rate
limiting, cache and `/metrics` — with local self-signed certs and curl probes
for every feature. The finished code is
[`examples/gateway-tls/`](examples/gateway-tls/).

## Configuration

Full reference in [`docs/CONFIG.md`](docs/CONFIG.md). Key sections:

| Section | Purpose |
|---------|---------|
| `[server]` | `listen`, `workers`, `rate_limit`, `health_check_interval`, `health_check_threshold`, `access_log`, `tls_cert`, `tls_key` |
| `[upstream.N]` | `name`, `host`, `port`, optional `hostname` (vhost) or `path_prefix` |
| `[cache]` | `enabled`, `max_entries`, `default_ttl_seconds` (v0.3+) |
| `[metrics]` | `enabled`, `bind`, `port` (v0.3+) |

## Documentation

- [`docs/TUTORIAL.md`](docs/TUTORIAL.md) — Build a multi-domain HTTPS gateway ([ES](docs/TUTORIAL.es.md))
- [`docs/CONFIG.md`](docs/CONFIG.md) — Full `proxy.toml` reference

## Limitations

- HTTP/1.1 to backends only — no HTTP/2 upstream
- WebSocket passthrough terminates TLS at the proxy; the upstream leg is plain TCP
- Health checks are TCP-only (no HTTP endpoint probing)
- Response cache ignores `Vary` header (cache key is `host:path` only)
- No hot reload of TLS certificates (config routing does hot-reload via `watch_config_loop`; cert changes need a restart)

## License

Apache 2.0 — see [LICENSE](./LICENSE)
