# nyx-proxy — Configuration Reference

Configuration is read from `proxy.toml` in the working directory at startup.

---

## `[server]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `listen` | int | `8080` | Port to listen on. With TLS enabled it defaults to `443` instead — an **explicit** `listen` always wins (v0.4.1+), which lets a TLS gateway run unprivileged (e.g. `8443`). |
| `workers` | int | `64` | Number of worker threads |
| `rate_limit` | int | `0` | Requests/second per client IP; `0` disables. Rejections answer `429` with `Retry-After`. |
| `health_check_interval` | int | `10` | Seconds between TCP health checks per backend |
| `health_check_threshold` | int | `3` | Consecutive failures before a backend is marked unhealthy |
| `access_log` | string | `""` | Path for the access log; empty disables |
| `upstream_idle_timeout` | int | `10` | Seconds an idle keep-alive connection to an upstream may wait in the pool before it is closed instead of reused (v0.4.9+). Keep it **below** the upstreams' own idle timeout (`std/serve` closes at 15 s). An upstream's `Keep-Alive: timeout=N` lowers it to `N-1` for that connection. `0` disables reuse. Reloads with the config. |
| `tls_cert` | string | — | Path to TLS certificate (PEM). Setting it enables TLS mode. |
| `tls_key` | string | — | Path to TLS private key (PEM). Required for TLS mode. |

Setting `tls_cert`/`tls_key` enables TLS mode in the config globals. The
accept loop, SNI certificate registration and any HTTP→HTTPS redirect
listener are the **consumer's** code, not the library's — see
[`examples/gateway-tls/`](../examples/gateway-tls/) and
[TUTORIAL.md](TUTORIAL.md) for a full working gateway that does all three.

---

## `[upstream.N]`

One `[upstream.N]` block per upstream backend. `N` is an integer index (0, 1, 2, ...).

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | string | Yes | Logical name for logging |
| `host` | string | Yes | Backend hostname or IP |
| `port` | int | Yes | Backend port |
| `hostname` | string | No | Route by `Host` header value |
| `path_prefix` | string | No | Route by request path prefix |

**Routing priority** (per request):
1. Upstream with matching `hostname`
2. Upstream with matching `path_prefix`
3. First upstream with neither (default catch-all)

---

## `[cache]` (v0.3+)

Response cache (LRU + TTL). Only `GET 200` responses are cached, keyed by
`host:path`; upstream `Cache-Control` is honored (`no-store` / `no-cache` /
`private` bypass, `max-age=N` overrides the TTL). Cache misses are coalesced
(single-flight), and hits carry an `X-Nyx-Cache: HIT` header. Note: the
config only stores these values — the consumer must call
`cache_init(g_cache_cfg_max_entries, g_cache_cfg_default_ttl_s)` to activate
the cache (both examples do).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | int | `0` | `1` enables the cache (via `cache_init`, see above) |
| `max_entries` | int | `10000` | LRU capacity |
| `default_ttl_seconds` | int | `300` | TTL when the upstream sends no `max-age` |

---

## `[metrics]` (v0.3+)

Separate admin listener serving `GET /metrics` (Prometheus text format) and
`GET /healthz`. It has **no authentication** — keep it on loopback and scrape
locally or through an SSH tunnel. The consumer spawns it with
`thread_spawn(admin_worker)`.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | int | `0` | `1` enables the admin listener |
| `bind` | string | `"127.0.0.1"` | Bind address. Do not use `0.0.0.0` without auth in front. |
| `port` | int | `9090` | Admin port |

---

## Example Configurations

### Single Backend

```toml
[server]
listen = 8080
workers = 32

[upstream.0]
name = "app"
host = "127.0.0.1"
port = 3000
```

### TLS + Multiple Backends by Hostname

```toml
[server]
listen = 443
workers = 64
tls_cert = "/etc/letsencrypt/live/nyxlang.com/fullchain.pem"
tls_key  = "/etc/letsencrypt/live/nyxlang.com/privkey.pem"

[upstream.0]
name = "main"
host = "127.0.0.1"
port = 3000

[upstream.1]
name = "kv-api"
hostname = "kv.nyxlang.com"
host = "127.0.0.1"
port = 6380

[upstream.2]
name = "playground"
hostname = "play.nyxlang.com"
host = "127.0.0.1"
port = 8080
```

### Path-Based Routing

```toml
[server]
listen = 8080
workers = 32

[upstream.0]
name = "api"
path_prefix = "/api"
host = "127.0.0.1"
port = 4000

[upstream.1]
name = "static"
path_prefix = "/static"
host = "127.0.0.1"
port = 3002

[upstream.2]
name = "app"
host = "127.0.0.1"
port = 3000
```

---

## Notes

- `proxy.toml` is read at startup. For hot reload of **routing** (upstreams /
  vhosts / rate limit), spawn the library's `watch_config_loop(interval_sec)`
  (`src/config.nx`) — it re-reads the file on mtime changes. TLS cert paths
  are excluded by design: cert changes need a restart.
- Health checks are **TCP-connect only** — a backend is healthy if its port
  accepts connections. No HTTP endpoint is probed, so backends don't need a
  `/health` route.
