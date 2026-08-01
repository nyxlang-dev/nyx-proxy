# Changelog — nyx-proxy

Se lleva el historial de releases separado del lenguaje. Ver
`/docs/PRODUCTS_ROADMAP.md` para el plan global de productos.

## v0.4.1 — 2026-08-01

**El camino HTTPS existe fuera de producción: tutorial + ejemplo real
`gateway-tls`, y la doc deja de mentir.**

- `examples/gateway-tls/` — gateway HTTPS multi-dominio COMPLETO como proyecto
  autocontenido que consume nyx-proxy vía PM (`nyx.toml` → `packages/`): TLS +
  SNI (cert default + `tls_server_add_cert` por dominio), workers keep-alive
  con rate-limit antes del dispatch, passthrough WebSocket, redirect
  HTTP→HTTPS, health checker y `/metrics`+`/healthz` por loopback. Certs
  self-signed gitignorados (one-liners en `certs/README.md`). Verificado E2E
  9/9 antes de publicarse (vhosts por SNI, fallback, 301, healthz, metrics,
  cache hit, 429).
- `docs/TUTORIAL.md` + `TUTORIAL.es.md` — walkthrough completo: certs locales,
  build, sondas curl de cada feature, y producción (certbot, unit systemd con
  `CAP_NET_BIND_SERVICE` en vez de root). Cada comando fue ejecutado antes de
  escribirse.
- `src/config.nx` — **fix**: un `server.listen` explícito ya no es pisado por
  el 443 que implica TLS; el 443 queda como default solo cuando `listen` no
  está en el config. Habilita gateways TLS sin root (el ejemplo escucha 8443).
  Suite nueva `test_proxy_config_listen` (3 casos, RED verificado).
- README/CONFIG.md — reparados contra el código real: el `proxy.toml` de
  ejemplo usaba claves inexistentes (`[vhost.N]`, `[health] interval_ms`,
  `[rate]`, `[logging]`) y el snippet llamaba funciones inexistentes
  (`health_start`, `proxy_listen`); Limitations negaba WebSocket y
  single-flight (implementados desde v0.4.0); CONFIG.md afirmaba un redirect
  :80 automático, un fallback `127.0.0.1:3000` y health checks por `GET
  /health` que no existen (son TCP-connect). CONFIG.md gana `[cache]` y
  `[metrics]`. El puntero muerto a `services/gateway/` (muerto desde el split
  del monorepo) apunta ahora a `examples/gateway-tls/`.
- CI — compila también el ejemplo TLS en cada push, con `packages/` sembrado
  del checkout actual (el puntero muerto sobrevivió años porque ningún
  automatismo compilaba el camino TLS).

## v0.4.0 — 2026-07-19

**Arranque del roadmap v0.4.0: single-flight con condvar, retry-on-stale,
lock SSL del túnel WS.** Usa builtins nuevos del toolchain (`condvar_*`,
`tls_wait_readable`, `tls_read_nonblock` — monorepo commits e7ead96 /
26ea0ee / 50d74a3).

- `src/cache.nx`: single-flight (`singleflight_wait`) dejó de hacer
  busy-poll de 10ms y pasó a bloquearse en una condvar (`g_sf_cv`,
  pareada con `g_sf_mtx`). `singleflight_release` hace
  `condvar_broadcast` bajo el mutex al liberar el slot (broadcast, no
  signal — hay waiters de keys distintas compartiendo la misma cv).
  Latencia de wakeup: de hasta 10ms de polling a prácticamente
  instantánea. Semántica de contadores/timeout/snapshot preservada.
- `src/router.nx`: `read_upstream_response` ahora distingue "conexión
  pooled murió" (status-line vacía, was_stale=1) de un 502 real que
  respondió el backend. `forward_pooled` reintenta UNA vez con conexión
  fresca en fallo de conexión inicial (cualquier método) y en
  status-line vacía SOLO para métodos idempotentes (GET/HEAD/OPTIONS —
  un POST pudo haberse ejecutado antes de morir el upstream, reintentarlo
  arriesga doble ejecución). Reduce los 502 breves característicos de un
  restart de upstream.
- `src/router.nx`: `ws_tunnel` resuelve la limitación piloto de
  SSL_read/SSL_write concurrentes sin lock sobre el mismo `SSL*` — patrón
  poll-then-lock (`tls_wait_readable` sin lock + `tls_read_nonblock` bajo
  lock, nunca un read bloqueante bajo el lock). De paso destraba el
  cuelgue "upstream cierra primero" (flag `up_closed` + poll con timeout).
  Verificado con el E2E real del monorepo (`test_ws_proxy.py`, 6/6).
- Tests nuevos: `test_singleflight_condvar_wakeup` (cache),
  `tests/test_proxy_retry.nx` (3 casos, listeners TCP reales).

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
