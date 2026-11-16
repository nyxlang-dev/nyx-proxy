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
| `http2` | bool | `false` | Offer HTTP/2 to clients on the TLS port (ALPN `h2`), v0.4.13+. Upstreams are still reached over HTTP/1.1. A browser then uses ONE connection with up to 100 streams instead of 6 connections per domain — which matters as soon as pages keep SSE channels open. The gateway's `main` must call `proxy_h2_init()` after loading its certificates and hand `h2` connections to `proxy_h2_spawn_conn` (see `examples/gateway-tls/main.nx`). Clients without HTTP/2 keep working over HTTP/1.1. WebSocket still uses a separate HTTP/1.1 connection. Not hot-reloaded: restart to change it. |
| `http2_max_body` | int | `16777216` | Largest request body accepted over HTTP/2, in bytes; beyond it the client gets `413`. |
| `http2_idle_timeout` | int | `120` | Seconds an HTTP/2 connection with no open streams is kept before it is closed. A connection with an SSE channel open is never idle. |
| `http2_max_conns` | int | `1024` | HTTP/2 connections open at once (v0.4.14+). Each one is a thread for its whole life (one per browser, not per tab); beyond the cap a new connection is closed right after the handshake. |
| `http2_max_inflight` | int | `64` | Requests of ONE connection being forwarded at the same time (each uses a thread while the upstream answers). Beyond it the request gets `503` with `Retry-After: 1`. SSE channels do not count. |

Setting `tls_cert`/`tls_key` enables TLS mode in the config globals. The
accept loop, SNI certificate registration and any HTTP→HTTPS redirect
listener are the **consumer's** code, not the library's — see
[`examples/gateway-tls/`](../examples/gateway-tls/) and
[TUTORIAL.md](TUTORIAL.md) for a full working gateway that does all three.

---

## `[upstream.N]`

One `[upstream.N]` block per upstream backend. `N` is an integer index (0, 1, 2, ...), contiguous from 0 and at most 128 blocks (v0.4.11+; 16 before). Loading stops at the first missing index.

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | string | Yes | Logical name for logging |
| `host` | string | Yes | Backend hostname or IP |
| `port` | int | Yes | Backend port |
| `hostname` | string | No | Route by `Host` header value. `*.example.com` (v0.4.10+) matches exactly one non-empty label (`a.example.com`, not `example.com` nor `a.b.example.com`) — the same rule as a wildcard certificate. A `*` anywhere else is ignored with a warning at load. |
| `path_prefix` | string | No | Route by request path prefix |
| `cache` | bool | No | `true` (or `1`) sends this upstream's `GET` traffic through the response cache (v0.5.0+; default off). Needs `[cache] enabled = 1`, see [`[cache]`](#cache-v03). |

**Routing priority** (per request):
1. Upstream with matching `hostname` — exact hostnames first, then wildcards, regardless of their order in the file
2. Upstream with matching `path_prefix`
3. First upstream with neither (default catch-all)

---

## `[cache]` (v0.3+)

Response cache (LRU + TTL, shared between clients). **Since v0.5.0 it is opt-in
per upstream**: `[cache] enabled = 1` alone stores nothing. Each upstream that
wants caching must also say `cache = true` in its own `[upstream.N]` section;
the proxy prints a warning at load if the cache is enabled but no upstream asks
for it. Cache misses are coalesced (single-flight) and hits carry an
`X-Nyx-Cache: HIT` header.

Note: the config only stores these values — the consumer must call
`cache_init(g_cache_cfg_max_entries, g_cache_cfg_default_ttl_s)` at startup
(both examples do).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | int | `0` | `1` enables the cache (together with `cache = true` on the upstream) |
| `max_entries` | int | `10000` | LRU capacity |
| `default_ttl_seconds` | int | `300` | TTL of a cacheable response that carries no `s-maxage` / `max-age` |

```toml
[cache]
enabled = 1

[upstream.0]
name = "web"
host = "127.0.0.1"
port = 3000
cache = true     # this upstream goes through the cache
```

**Migrating from v0.4.x:** add `cache = true` to every upstream you want
cached. Until you do, a config with only `[cache] enabled = 1` caches nothing.

### What goes through the cache

A request is served from the cache, and its response is stored, only if **all**
of these hold:

| Condition | Detail |
|-----------|--------|
| Method is `GET` | Other methods always go to the upstream. |
| The upstream has `cache = true` | And `[cache] enabled = 1` is in force. |
| The request has no `Cookie` and no `Authorization` header | Such a request neither reads from the cache nor writes to it (even if the header is empty). The response to a signed-in user must never be served to someone else. |

### What gets stored

Everything is read from the response **headers** only (never from the body),
case-insensitively, by whole directive.

| Response | Stored? |
|----------|---------|
| Status other than `200` | No |
| Has `Set-Cookie` | No |
| `Cache-Control` contains `no-store`, `no-cache` or `private` | No |
| `s-maxage=0`, `max-age=0`, or a value that is not a number | No |
| No `Vary` | Yes, one entry per `host:path` |
| `Vary: Accept-Encoding` | Yes, one entry per variant (see below) |
| Any other `Vary` (or `Vary: *`) | No |
| Has `Content-Encoding` (even without `Vary`) | Treated as `Vary: Accept-Encoding`; stored only if the coding is `br`, `deflate`, `gzip` or `zstd` and the request accepted it |

**Variants.** The variant key is the request's `Accept-Encoding` normalized to
the known codings it accepts (`br`, `deflate`, `gzip`, `zstd`, `*`), without the
ones marked `q=0`, in a fixed order. A client that did not ask for `gzip`
therefore never receives a `content-encoding: gzip` response.

### How long it lives

The TTL of a stored response is, in order:

1. `s-maxage=N` from the upstream's `Cache-Control`;
2. otherwise `max-age=N`;
3. otherwise `default_ttl_seconds` (**300 seconds** if you do not set it).

So a cacheable response with no `Cache-Control` at all lives 300 s. Entries are
also evicted least-recently-used when `max_entries` is reached.

### Conditional requests

On a hit, the cache answers `304 Not Modified` with no body when:

- the request's `If-None-Match` matches the stored `ETag` (weak comparison; a
  list and `*` are accepted), or
- the request has no `If-None-Match` and its `If-Modified-Since` is not earlier
  than the stored `Last-Modified`.

The 304 repeats `Cache-Control`, `Content-Location`, `Date`, `ETag`, `Expires`,
`Last-Modified` and `Vary`, and carries `X-Nyx-Cache: HIT`. The access log and
`/metrics` record it as a 304. It works the same over HTTP/1.1 and HTTP/2.
Otherwise the full cached response is returned.

### Turning it off

- **Per upstream:** remove `cache = true` (or set it to `false`).
- **Globally:** set `enabled = 0`.
- **Hot reload:** `enabled` and the per-upstream `cache` flags are re-read on
  hot reload (`reload_config_if_changed` / `watch_config_loop`; the consumer
  must be running `watch_config_loop`). Turning the cache off empties it with
  no restart; turning it on initializes it. `max_entries` and
  `default_ttl_seconds` are only read the first time the cache is initialized.

### Keeping a response out of the cache (from the backend)

Send `Cache-Control: no-store` (or `private`, or `no-cache`) on the response.
Responses that set a cookie, or vary on anything but `Accept-Encoding`, are
never stored either.

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
