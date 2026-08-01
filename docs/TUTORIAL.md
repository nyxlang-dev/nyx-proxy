# Tutorial: a multi-domain HTTPS gateway in Nyx

> Léelo en español: [TUTORIAL.es.md](TUTORIAL.es.md)

This walkthrough builds a real gateway on top of the `nyx-proxy` library: TLS
termination with **SNI** (one process, N domains), an HTTP→HTTPS redirect,
WebSocket passthrough, per-IP rate limiting, a response cache and Prometheus
`/metrics`. It is the same architecture that serves nyxlang.com and friends in
production. Every command below was run, verbatim, against the example before
being written here.

The finished code lives in [`examples/gateway-tls/`](../examples/gateway-tls/)
— about 250 lines of Nyx. You can follow along from scratch or start from it.

## 0. Prerequisites

```bash
curl -fsSL https://raw.githubusercontent.com/nyxlang-dev/nyx/main/scripts/install.sh | bash
git clone https://github.com/nyxlang-dev/nyx-proxy
cd nyx-proxy/examples/gateway-tls
```

## 1. Generate local test certificates

The gateway serves two domains: `example.com` (default cert) and
`api.example.com` (registered via SNI). For local testing, self-signed
certs are fine (they are gitignored — never commit private keys):

```bash
cd certs
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
  -keyout example.com.key -out example.com.pem \
  -subj "/CN=example.com" -addext "subjectAltName=DNS:example.com"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
  -keyout api.example.com.key -out api.example.com.pem \
  -subj "/CN=api.example.com" -addext "subjectAltName=DNS:api.example.com"
cd ..
```

## 2. The config: `proxy.toml`

Routing is config; certificates-per-domain are code (they are
deployment-specific — see step 3). The example ships this `proxy.toml`
(every key exists in `src/config.nx`; full schema in [CONFIG.md](CONFIG.md)):

- `listen = 8443` — with TLS on, `listen` defaults to 443; the explicit
  value lets the example run unprivileged (v0.4.1+).
- Two vhosts routed by Host/SNI (`example.com` → :9101, `api.example.com`
  → :9102) plus a catch-all fallback.
- `[cache]` and `[metrics]` enabled; metrics bound to loopback **on
  purpose** — `/metrics` and `/healthz` have no auth, scrape locally or
  over an SSH tunnel.

## 3. The code: `main.nx`

Read [`examples/gateway-tls/main.nx`](../examples/gateway-tls/main.nx) top to
bottom — it is the whole gateway. The shape:

1. `load_config("proxy.toml")` — populates routing, TLS paths, cache/metrics
   config (library: `src/config.nx`).
2. `tls_server_init(g_tls_cert, g_tls_key)` — default certificate, then one
   `tls_server_add_cert(hostname, cert, key)` per additional domain. This is
   the SNI part, and it is code on purpose: a gateway instance serves a
   concrete set of domains.
3. `g_workers` × `thread_spawn(tls_worker)` — each worker does
   `tls_accept` → keep-alive loop → rate limit → `proxy_dispatch` (routing,
   pooling, cache, single-flight, metrics — all library) → `tls_write_conn`.
   WebSocket upgrades hand off to the library's `ws_proxy` tunnel.
4. `thread_spawn(health_checker)` + `thread_spawn(admin_worker)` — TCP health
   checks marking backends unhealthy, and the loopback `/metrics`/`/healthz`
   listener.
5. A second listener (port 8080 here, 80 in production) answers every plain
   HTTP request with a `301` to `https://`.

## 4. Build and run

```bash
nyx build        # resolves nyx-proxy into packages/, produces ./gateway-tls
```

Start two dummy upstreams and the gateway (three terminals, or `&`):

```bash
mkdir -p /tmp/web /tmp/api
echo "HELLO-FROM-WEB" > /tmp/web/index.html
echo "HELLO-FROM-API" > /tmp/api/index.html
(cd /tmp/web && python3 -m http.server 9101 --bind 127.0.0.1) &
(cd /tmp/api && python3 -m http.server 9102 --bind 127.0.0.1) &
./gateway-tls
```

## 5. Probe it

`--resolve` maps the test domains to localhost without touching `/etc/hosts`;
`-k` accepts the self-signed certs.

```bash
# SNI/Host routing: each domain hits its own upstream
curl -sk --resolve example.com:8443:127.0.0.1     https://example.com:8443/      # HELLO-FROM-WEB
curl -sk --resolve api.example.com:8443:127.0.0.1 https://api.example.com:8443/  # HELLO-FROM-API

# Unknown host falls back to the default upstream
curl -sk --resolve otro.example.com:8443:127.0.0.1 https://otro.example.com:8443/

# HTTP -> HTTPS redirect
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' \
  -H "Host: example.com" http://127.0.0.1:8080/x        # 301 https://example.com/x

# Health + Prometheus metrics (loopback only)
curl -s http://127.0.0.1:9090/healthz                   # ok
curl -s http://127.0.0.1:9090/metrics | head

# Cache: request the same path twice, then check the hit counter
curl -sk --resolve example.com:8443:127.0.0.1 https://example.com:8443/index.html > /dev/null
curl -sk --resolve example.com:8443:127.0.0.1 https://example.com:8443/index.html > /dev/null
curl -s http://127.0.0.1:9090/metrics | grep cache_hits

# Rate limit: set `rate_limit = 3` in proxy.toml, restart, then burst —
# you'll see 429s with a Retry-After header
for i in $(seq 1 12); do
  curl -sk -o /dev/null -w '%{http_code}\n' \
    --resolve example.com:8443:127.0.0.1 https://example.com:8443/
done
```

## 6. Taking it to production

- **Real certificates**: point `proxy.toml` and the `tls_server_add_cert`
  calls at `/etc/letsencrypt/live/<domain>/fullchain.pem` / `privkey.pem`
  (certbot). Cert changes need a restart — there is no hot cert reload.
- **Ports**: remove `listen` from `[server]` (TLS then defaults to 443) and
  change `g_redirect_port` to 80 in `main.nx`.
- **Privileges**: don't run as root. Grant the binary the low-port capability
  instead:

  ```ini
  # /etc/systemd/system/my-gateway.service
  [Unit]
  Description=HTTPS gateway (nyx-proxy)
  After=network.target

  [Service]
  User=gateway
  AmbientCapabilities=CAP_NET_BIND_SERVICE
  WorkingDirectory=/opt/my-gateway
  ExecStart=/opt/my-gateway/gateway-tls
  Restart=always

  [Install]
  WantedBy=multi-user.target
  ```

  The `gateway` user needs read access to the cert paths (a `ssl-cert`-style
  group works; avoid world-readable private keys).
- **Config hot-reload**: the library ships `watch_config_loop(interval_sec)`
  (`src/config.nx`) — spawn it if you want routing changes picked up from
  `proxy.toml` without restarts (TLS paths excluded by design).
- **Keep `/metrics` on loopback**. It has no auth; that is a deliberate
  design choice documented in the config.

## Where to go next

- [`CONFIG.md`](CONFIG.md) — full `proxy.toml` schema.
- [`examples/standalone.nx`](../examples/standalone.nx) — the plain-HTTP
  variant of the same wiring, good as a minimal starting point.
- The library modules under `src/` are small and readable — `router.nx`
  (dispatch, pooling, WebSocket tunnel), `cache.nx` (LRU + single-flight),
  `metrics.nx`, `ratelimit.nx`, `health.nx`.
