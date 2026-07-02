# Changelog — nyx-proxy

Se lleva el historial de releases separado del lenguaje. Ver
`/docs/PRODUCTS_ROADMAP.md` para el plan global de productos.

## v0.3.1 — 2026-04-24

**Bug fix: vhost match cortocircuitaba path_prefix bajo el mismo host.**

- `src/router.nx`: dos-pase sobre `g_vhost_names`. Bajo un hostname
  match, el upstream con `path_prefix` matching gana (longest wins);
  fallback al catch-all (vhost sin prefix) cuando ninguno matchea. Antes
  el primer vhost que matcheaba ganaba con un `break`, ignorando
  cualquier `[upstream.N]` posterior con `hostname` repetido +
  `path_prefix` específico.
- Caso reproducible: `nyxkv.com/stripe/webhook` caía en `[upstream.2]`
  (kv-web :3002) en vez de `[upstream.5]` (kv-webhook :3006), aunque el
  comentario en `proxy.toml` afirmaba que "path_prefix takes precedence
  over bare hostname match" — el código no lo implementaba.
- Sin cambios a la API ni al schema TOML. Compatible hacia atrás para
  configs sin vhost-with-prefix.

## v0.3.0 — 2026-04-23

**Response cache LRU por-host con TTL.**

- Nuevo modulo `src/cache.nx`: LRU sobre arrays paralelos (doubly-linked
  list via indices), O(1) en lookup/move-to-front/evict bajo un unico
  mutex global.
- Solo se cachea `GET` con status `200`.
- Honra `Cache-Control` del upstream: `no-store`, `no-cache` y `private`
  bypassean; `max-age=N` setea TTL; sin header se usa
  `default_ttl_seconds` del config.
- Header `X-Nyx-Cache: HIT` agregado en respuestas servidas desde cache
  para observabilidad.
- Config:
  ```toml
  [cache]
  enabled = 1
  max_entries = 10000
  default_ttl_seconds = 300
  ```

**Endpoint `/metrics` Prometheus.**

- Nuevo modulo `src/metrics.nx` + `src/admin.nx`.
- Admin listener separado (default `127.0.0.1:9090`) — no se expone al
  trafico publico.
- Expone:
  - `nyx_proxy_requests_total{host,status}` — counter por host +
    clase de status (2xx/3xx/4xx/5xx/other).
  - `nyx_proxy_cache_{hits,misses,evictions}_total` — counters.
  - `nyx_proxy_cache_size`, `nyx_proxy_cache_capacity` — gauges.
  - `nyx_proxy_upstream_latency_ms_{sum,count}{host}` — counters para
    avg por host (solo cuando NO es cache hit).
  - `nyx_proxy_ratelimit_rejects_total{host}` — counter de 429s.
  - `nyx_proxy_uptime_seconds` — gauge.
- Ademas sirve `GET /healthz` → `"ok"` para liveness probes.
- Config:
  ```toml
  [metrics]
  enabled = 1
  bind = "127.0.0.1"
  port = 9090
  ```

**Cambios de firma internos.**

- `proxy_check_rate(ip: String, host: String)` — antes tomaba solo `ip`.
  El nuevo parametro se usa como label en
  `nyx_proxy_ratelimit_rejects_total`. Los consumers
  (`examples/standalone.nx` y `services/gateway/src/main.nx`) fueron
  actualizados; pasa `""` si el Host header aun no se parseo.

**Deuda conocida.**

- Sin manejo de `Vary` — cache key es solo `host:path`.
- Sin single-flight — dos requests concurrentes en miss van ambas al
  backend (thundering herd).
- Latencias emitidas como sum/count; histogramas (buckets Prometheus)
  quedan para v0.4.

## v0.2.0 — 2026-04

- Refactor a libreria PM (antes era un daemon ejecutable).
- `services/gateway/` es el consumer de produccion.
- Hot-reload de `proxy.toml` via `reload_config_if_changed` + watcher
  thread opcional.

## v0.1.0

- Version inicial: TLS termination, SNI multi-dominio, vhost dispatch,
  health checks TCP, rate limit por IP, access log.
