# nyx-proxy — Configuration Reference

Configuration is read from `proxy.toml` in the working directory at startup.

---

## `[server]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `listen` | int | `8080` | Port to listen on |
| `workers` | int | `64` | Number of worker goroutines |
| `tls_cert` | string | — | Path to TLS certificate (PEM). Required for TLS mode. |
| `tls_key` | string | — | Path to TLS private key (PEM). Required for TLS mode. |

When `tls_cert` and `tls_key` are set, TLS mode is enabled and nyx-proxy also starts an HTTP→HTTPS redirect listener on port 80.

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

- `proxy.toml` is read once at startup. To reload config: `sudo systemctl restart nyx-proxy` (after `BGSAVE` on nyx-kv if needed).
- If `proxy.toml` is not found, nyx-proxy starts with a single upstream at `127.0.0.1:3000` (hardcoded fallback).
- Health check endpoint on upstreams: `GET /health` → 200. Upstreams without a `/health` route will be considered unhealthy. Add a simple health endpoint to your backends.
