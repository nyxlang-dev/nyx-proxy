# Tutorial: un gateway HTTPS multi-dominio en Nyx

> Read it in English: [TUTORIAL.md](TUTORIAL.md)

Esta guía construye un gateway real sobre la librería `nyx-proxy`: terminación
TLS con **SNI** (un proceso, N dominios), redirect HTTP→HTTPS, passthrough de
WebSocket, rate limiting por IP, cache de respuestas y `/metrics` Prometheus.
Es la misma arquitectura que sirve nyxlang.com y compañía en producción. Cada
comando de abajo se ejecutó, literal, contra el ejemplo antes de escribirse acá.

El código terminado vive en [`examples/gateway-tls/`](../examples/gateway-tls/)
— unas 250 líneas de Nyx. Podés seguir la guía desde cero o partir de él.

## 0. Prerrequisitos

```bash
curl -fsSL https://raw.githubusercontent.com/nyxlang-dev/nyx/main/scripts/install.sh | bash
git clone https://github.com/nyxlang-dev/nyx-proxy
cd nyx-proxy/examples/gateway-tls
```

## 1. Generar certificados de prueba

El gateway sirve dos dominios: `example.com` (cert default) y
`api.example.com` (registrado vía SNI). Para probar en local alcanzan
certificados self-signed (están gitignorados — nunca commitees claves
privadas):

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

## 2. La config: `proxy.toml`

El routing es config; los certificados por dominio son código (son específicos
del deployment — ver paso 3). El ejemplo trae este `proxy.toml` (todas las
claves existen en `src/config.nx`; esquema completo en [CONFIG.md](CONFIG.md)):

- `listen = 8443` — con TLS activo, `listen` defaultea a 443; el valor
  explícito permite correr el ejemplo sin root (v0.4.1+).
- Dos vhosts ruteados por Host/SNI (`example.com` → :9101,
  `api.example.com` → :9102) más un fallback catch-all.
- `[cache]` y `[metrics]` activados; metrics bindeado a loopback **a
  propósito** — `/metrics` y `/healthz` no tienen auth: scrapeá local o por
  túnel SSH.

## 3. El código: `main.nx`

Leé [`examples/gateway-tls/main.nx`](../examples/gateway-tls/main.nx) de punta
a punta — es el gateway entero. La forma:

1. `load_config("proxy.toml")` — llena routing, paths TLS, config de
   cache/metrics (librería: `src/config.nx`).
2. `tls_server_init(g_tls_cert, g_tls_key)` — certificado default, y después
   un `tls_server_add_cert(hostname, cert, key)` por dominio adicional. Esa
   es la parte SNI, y es código a propósito: una instancia de gateway sirve
   un conjunto concreto de dominios.
3. `g_workers` × `thread_spawn(tls_worker)` — cada worker hace `tls_accept`
   → loop keep-alive → rate limit → `proxy_dispatch` (routing, pooling,
   cache, single-flight, métricas — todo librería) → `tls_write_conn`. Un
   upgrade WebSocket pasa al túnel `ws_proxy` de la librería.
4. `thread_spawn(health_checker)` + `thread_spawn(admin_worker)` — health
   checks TCP que marcan backends caídos, y el listener loopback de
   `/metrics`/`/healthz`.
5. Un segundo listener (acá 8080; en producción 80) responde todo request
   HTTP plano con `301` a `https://`.

## 4. Compilar y correr

```bash
nyx build        # resuelve nyx-proxy en packages/, produce ./gateway-tls
```

Levantá dos upstreams dummy y el gateway (tres terminales, o `&`):

```bash
mkdir -p /tmp/web /tmp/api
echo "HELLO-FROM-WEB" > /tmp/web/index.html
echo "HELLO-FROM-API" > /tmp/api/index.html
(cd /tmp/web && python3 -m http.server 9101 --bind 127.0.0.1) &
(cd /tmp/api && python3 -m http.server 9102 --bind 127.0.0.1) &
./gateway-tls
```

## 5. Probarlo

`--resolve` mapea los dominios de prueba a localhost sin tocar `/etc/hosts`;
`-k` acepta los certs self-signed.

```bash
# Routing por SNI/Host: cada dominio pega en su upstream
curl -sk --resolve example.com:8443:127.0.0.1     https://example.com:8443/      # HELLO-FROM-WEB
curl -sk --resolve api.example.com:8443:127.0.0.1 https://api.example.com:8443/  # HELLO-FROM-API

# Host desconocido cae al upstream default
curl -sk --resolve otro.example.com:8443:127.0.0.1 https://otro.example.com:8443/

# Redirect HTTP -> HTTPS
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' \
  -H "Host: example.com" http://127.0.0.1:8080/x        # 301 https://example.com/x

# Health + métricas Prometheus (solo loopback)
curl -s http://127.0.0.1:9090/healthz                   # ok
curl -s http://127.0.0.1:9090/metrics | head

# Cache: dos GET al mismo path, y mirar el contador de hits
curl -sk --resolve example.com:8443:127.0.0.1 https://example.com:8443/index.html > /dev/null
curl -sk --resolve example.com:8443:127.0.0.1 https://example.com:8443/index.html > /dev/null
curl -s http://127.0.0.1:9090/metrics | grep cache_hits

# Rate limit: poné `rate_limit = 3` en proxy.toml, reiniciá, y tirá una
# ráfaga — vas a ver 429 con header Retry-After
for i in $(seq 1 12); do
  curl -sk -o /dev/null -w '%{http_code}\n' \
    --resolve example.com:8443:127.0.0.1 https://example.com:8443/
done
```

## 6. Llevarlo a producción

- **Certificados reales**: apuntá `proxy.toml` y las llamadas
  `tls_server_add_cert` a `/etc/letsencrypt/live/<dominio>/fullchain.pem` /
  `privkey.pem` (certbot). Cambiar certs requiere reiniciar — no hay hot
  reload de certificados.
- **Puertos**: sacá `listen` de `[server]` (con TLS defaultea a 443) y
  cambiá `g_redirect_port` a 80 en `main.nx`.
- **Privilegios**: no corras como root. Dale al binario la capability de
  puertos bajos:

  ```ini
  # /etc/systemd/system/mi-gateway.service
  [Unit]
  Description=Gateway HTTPS (nyx-proxy)
  After=network.target

  [Service]
  User=gateway
  AmbientCapabilities=CAP_NET_BIND_SERVICE
  WorkingDirectory=/opt/mi-gateway
  ExecStart=/opt/mi-gateway/gateway-tls
  Restart=always

  [Install]
  WantedBy=multi-user.target
  ```

  El usuario `gateway` necesita lectura sobre los paths de certs (un grupo
  estilo `ssl-cert`; evitá claves privadas world-readable).
- **Hot-reload de config**: la librería trae `watch_config_loop(interval_sec)`
  (`src/config.nx`) — spawnealo si querés que los cambios de routing de
  `proxy.toml` se tomen sin reiniciar (los paths TLS quedan afuera por
  diseño).
- **Dejá `/metrics` en loopback**. No tiene auth; es una decisión de diseño
  documentada en la config.

## Para seguir

- [`CONFIG.md`](CONFIG.md) — esquema completo de `proxy.toml`.
- [`examples/standalone.nx`](../examples/standalone.nx) — la variante HTTP
  plano del mismo cableado, buen punto de partida mínimo.
- Los módulos de `src/` son chicos y legibles — `router.nx` (dispatch,
  pooling, túnel WebSocket), `cache.nx` (LRU + single-flight), `metrics.nx`,
  `ratelimit.nx`, `health.nx`.
