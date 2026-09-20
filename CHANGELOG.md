# Changelog — nyx-proxy

Se lleva el historial de releases separado del lenguaje. Ver
`/docs/PRODUCTS_ROADMAP.md` para el plan global de productos.

## v0.4.4 — 2026-09-20

**Una respuesta `text/event-stream` ahora se transmite en vivo en vez de juntarse
hasta que el upstream cierre.** [arco: sse-tunnel]

- `src/router.nx` — **túnel SSE de un solo sentido**. `std/serve` emite un canal
  SSE sin `Content-Length` y sin `chunked`, con el cuerpo terminado por FIN TCP.
  El router lo trataba como «cuerpo hasta el cierre»: lo juntaba entero, con un
  plazo de INACTIVIDAD de 30 s y un tope de 16 MiB. Pero el heartbeat de
  `std/serve` (`:\n\n` cada 15 s) renueva ese plazo indefinidamente, así que el
  gateway acumulaba en silencio y el navegador no recibía NINGÚN evento hasta que
  el upstream cerrara. Medido antes del fix, con un upstream que cierra a los
  3 s: la respuesta volvía a los 3016 ms, con todo junto; con los valores de
  producción (plazo de 30 s y un canal que no cierra), no volvía nunca — la
  corrida moría por el timeout de 60 s del runner sin imprimir una línea. Ahora
  una respuesta con `Content-Type: text/event-stream` y sin longitud declarada se
  tuneliza: el primer evento llega a los 2 ms y la pausa entre eventos del
  upstream se preserva en el cliente (medido: 500 ms de pausa → 502 ms).
- El túnel es **de un solo sentido y sin threads ni mutex**, a diferencia de
  `ws_tunnel`, que es bidireccional y por eso necesita 2 threads y un lock sobre
  el `SSL*`. En SSE el cliente no manda nada después del GET, así que un segundo
  thread solo existiría para bloquearse; con un único thread tocando el SSL
  tampoco aplica el caveat de NewSessionTicket. La asimetría es deliberada y está
  comentada en el código.
- **El fd de un stream nunca vuelve al pool**, y el cierre del cliente se detecta
  en ~2 s (medido: 402 ms en el test) por dos vías independientes: una sonda en
  el ciclo ocioso —cuando el upstream no tenía nada que relayar, así que no
  retrasa ningún evento— y el resultado de la escritura. Detectarlo solo por la
  escritura habría tardado entre 15 y 30 s por cliente que cierra la pestaña,
  con un worker clavado todo ese rato.
- **Tope de túneles simultáneos** (`sse_set_max_tunnels`, default 1024): cada
  túnel retiene el worker que lo atiende, así que sin tope N clientes SSE dejan
  al gateway sin workers — no degradado, mudo. Al exceder se responde un 503
  explícito y contabilizado. OJO: el techo EFECTIVO es la cantidad de workers, no
  este número; el valor sirve para que el modo de falla sea un 503 y no una
  desaparición, y para darle la perilla a quien opera.
- `proxy_dispatch_c(raw, ssl_handle, client_fd)` es la variante con el socket del
  cliente a la vista, que es lo que permite tunelizar; devuelve `""` cuando ya no
  queda nada que escribir. `proxy_dispatch(raw)` queda como el nombre de siempre,
  sin sink y sin túnel. Igual `forward_pooled` y `read_upstream_response_m`: con
  el túnel apagado ni se mira el `Content-Type`, y el camino del pool queda
  byte-idéntico al de v0.4.3.
- Suite nueva `tests/test_proxy_sse_tunnel.nx` (8 casos): detección sin leer el
  cuerpo, relay en orden y sin buffering (se verifica que la pausa del upstream
  se PRESERVE, porque si se bufferizara los eventos llegarían juntos al final),
  cliente que se va, el pedido siguiente por el mismo pool, no regresión de una
  respuesta sin longitud que no es SSE, matching del `Content-Type`, SSE con
  longitud y el tope.
- **Alcance acotado, a propósito**: se tuneliza por `Content-Type`, no toda
  respuesta sin longitud. Un SSE que venga CON `Content-Length` o `chunked` se
  sirve encuadrado y su fd sigue siendo reusable (`std/serve` nunca manda
  ninguno de los dos). Una respuesta sin longitud que no es SSE se comporta
  igual que en v0.4.3: se junta con plazo y tope, y el fd se descarta.
- **fix (build)**: `nyx build` estaba ROTO desde que el toolchain llegó a 0.32.4,
  que empezó a exigir `pub` para cruzar el límite de módulo. `proxy_dispatch` y
  `ws_proxy` no lo tenían, así que ni el binario de referencia ni el ejemplo
  `gateway-tls` compilaban — y los dos están en CI. No lo cazó nadie porque el
  binario commiteado era anterior al cambio del compilador.
- **fix (estabilidad, encontrado al cubrir el sink TLS)**: un cliente TLS que
  cerraba mataba EL PROCESO ENTERO por SIGPIPE. Este runtime no instala un
  `SIG_IGN` global —el `MSG_NOSIGNAL` de `os_sock_send` es «load-bearing», lo
  dice su propio comentario— y OpenSSL escribe con `write()` crudo, así que un
  `tls_write_conn` contra un peer que ya cerró se lleva puesto el proceso. En el
  camino normal la ventana es de milisegundos y por eso nunca se había visto; en
  un túnel dura lo que dure el stream, o sea que alcanzaba con cerrar la pestaña
  para tirar un gateway con todos sus dominios. Medido: sin el fix,
  `tests/test_proxy_sse_tls.nx` muere con rc=141 (128+SIGPIPE) sin alcanzar a
  imprimir una línea. Es un bug del runtime, no del proxy —afecta igual a
  `ws_tunnel` y al camino normal, con ventana más corta— y está reportado al repo
  del lenguaje; acá se mitiga donde el riesgo es real.
- Suite nueva `tests/test_proxy_sse_tls.nx` (1 caso): el túnel sobre TLS, que es
  el sink que corre en producción, con certificado autofirmado generado al vuelo
  y SKIP limpio si no hay `openssl`. Vive aparte porque `tls_server_init` publica
  un contexto TLS global de proceso. Medido: primer evento a los 0-1 ms y la
  pausa de 500 ms del upstream preservada.
- Fuera de alcance, sin cambio: el `access_log` y las métricas de un túnel se
  emiten al ABRIR, con la latencia hasta la cabecera. Registrarlas al cerrar
  metería la duración entera del stream en el histograma y destruiría el p99 del
  vhost. Un túnel no emite una segunda línea al terminar.

## v0.4.3 — 2026-09-15

**SEGURIDAD: el pool de conexiones al upstream podía entregarle a un pedido los
bytes de la respuesta de OTRO.**

- `src/router.nx` — **fix (seguridad, mezcla de respuestas entre usuarios)**:
  `read_upstream_response` leía el cuerpo SOLO si venía `Content-Length`,
  comparado con mayúsculas exactas, y devolvía el fd al pool igual. Con una
  respuesta `Transfer-Encoding: chunked`, delimitada por cierre, o con
  `content-length` en minúscula, el cuerpo quedaba sin leer en el socket y el
  SIGUIENTE pedido que tomaba ese fd —quizá de otro usuario— lo leía como su
  respuesta. Medido antes del fix: con un upstream chunked sobre keep-alive, la
  respuesta al segundo pedido empezaba con `5` (el tamaño de chunk del primero);
  con `content-length` en minúscula, empezaba con `uno!!HTTP/1.1 200 OK`.
  Hoy no se disparaba en producción porque todos los upstreams mandan
  `Content-Length` capitalizado, pero cualquier upstream con streaming, chunked o
  SSE lo disparaba. Ahora el encuadre sigue RFC 9112 §6.3: cabeceras sin
  mayúsculas; HEAD, 1xx, 204 y 304 sin cuerpo (los 1xx provisionales se saltan);
  chunked se lee hasta el chunk 0 y trailers, y se reemite con `Content-Length`;
  `Transfer-Encoding` y `Content-Length` a la vez → gana chunked y el fd no se
  reusa; EOF entre el chunk 0 y la línea final → se entrega el cuerpo pero el fd
  no se reusa; `Content-Length` truncado → 502; sin longitud → se lee hasta el
  cierre con plazo de inactividad (30 s sin recibir un byte) y tope (16 MiB), y el
  fd se descarta siempre. `Connection: close` en cualquier capitalización, y
  HTTP/1.0 sin keep-alive, descartan el fd.
- Suite nueva `tests/test_proxy_pool_framing.nx` (11 casos, con upstreams locales
  que atienden varios pedidos sobre UNA conexión, así que si el proxy abriera otra
  el test cuelga y falla): chunked, minúsculas, delimitado por cierre, sin cierre
  que vence el plazo, HEAD, 304/204/100, Content-Length truncado, `connection:
  Close`, TE+CL, EOF en los trailers de chunked y el control positivo de que
  Content-Length normal se sigue reusando. RED verificado contra el router previo:
  fallan o cuelgan los 10 casos del bug y pasa solo el control positivo.
- Fuera de alcance, pendiente: una respuesta SSE (`text/event-stream`) detrás del
  proxy ya no corrompe el pool, pero tampoco se transmite en vivo: se junta hasta
  el cierre y vence a los 30 s de silencio. El túnel en un solo sentido es la
  Task 6 del arco serve-sse del lenguaje.
- Fuera de alcance, sin cambio: `ws_proxy` ante un handshake rechazado sigue
  relayando solo los headers (no pasa por el pool); una respuesta con
  `Content-Length` enorme se sigue leyendo sin tope, como antes.

## v0.4.2 — 2026-09-10

**Tres relojes mal escalados: la ventana del rate limiter estaba congelada, el
access log escribía `1789` como marca de tiempo y el uptime de `/metrics`
reportaba 0.**

- `src/ratelimit.nx` — **fix (silently-wrong)**: `proxy_check_rate` calculaba
  `now = time_epoch() / 1000000` con el comentario «// seconds» al lado.
  `time_epoch()` YA devuelve segundos, así que `now` avanzaba una vez cada
  1.000.000 de segundos — **11,6 días**. La ventana de un segundo del token
  bucket quedaba congelada: todas las peticiones de casi dos semanas caían en el
  mismo cubo, y una IP que llegaba al límite seguía recibiendo 429 hasta el
  siguiente múltiplo de 1.000.000. Sin error, sin log, sin crash.
- `src/logger.nx` — **fix**: el mismo `/ 1000000` en `access_log` escribía `1789`
  al frente de cada línea en vez de `1789048733`. Un access log sin marca de
  tiempo utilizable.
- `src/metrics.nx` — **fix**: el mismo error de escala en un tercer sitio.
  `metrics_init` guardaba `time_epoch() / 1000` (kilosegundos) en una variable
  llamada `g_m_start_ms`, y `metrics_render` volvía a dividir entre 1000 para
  sacar los segundos: el gauge `nyx_proxy_uptime_seconds` reportaba **0** hasta
  que el proxy llevaba 11,6 días arriba. Ahora usa `time_ms()`, que es el reloj
  MONÓTONO — el correcto para una duración, inmune a un salto de NTP.
- Suite nueva `tests/test_proxy_time.nx` (5 casos, **RED verificado**: con la
  división reintroducida falla en el caso de la ventana). Ninguna de las cinco
  suites que había tocaba `ratelimit.nx` ni `logger.nx` — por eso el bug
  sobrevivió desde que se escribieron los módulos.
- `CAPABILITIES.md` regenerado por el toolchain (la stdlib del core creció:
  `std/time`, `std/postgres`).

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
