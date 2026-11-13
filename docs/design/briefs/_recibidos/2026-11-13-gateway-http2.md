# Encargo recibido — HTTP/2 hacia el navegador (ALPN `h2`), con SSE como flujo

> **Origen**: repo del lenguaje (`~/nyx/lang`), arco `gateway-http2`, Task 4 del plan
> `docs/design/plans/2026-11-13-gateway-http2.md`. GO del dueño del repo el 2026-11-13.
> **Recibido**: 2026-11-13. Lo trabajó la misma sesión del lenguaje que escribió el motor, en este
> repo; se copia acá para que exista.
> **Report**: al pie de este archivo.
>
> Está en `_recibidos/` y exento de la regla (f) de `state-check`.

---

Fricción de nyxerp del 2026-11-13: una aplicación con un canal SSE por pantalla detrás de
`nyx-proxy`. El gateway solo ofrece HTTP/1.1 y el navegador abre como mucho 6 conexiones por
dominio, compartidas entre pestañas y PWA; cada SSE ocupa una. Con 6 pantallas abiertas la petición
siguiente espera de 20 s a más de un minuto, con el servidor respondiendo en milisegundos.

QUÉ SE PIDE:

1. Que el gateway negocie `h2` por ALPN en su puerto TLS y siga hablando HTTP/1.1 con el upstream.
2. Que un canal SSE del upstream viaje como un flujo HTTP/2, sin almacenarse.
3. Apagado por defecto: opción en `proxy.toml`.
4. El camino HTTP/1.1 no cambia de conducta.

El protocolo lo pone el lenguaje (`std/http2`, motor `nyx_h2c_*`; ALPN en `std/tls`).

---

## Report — 2026-11-13, v0.4.13

Hecho. `src/h2front.nx` nuevo; `proxy_dispatch_o` y `sse_slot_release` en `src/router.nx`;
`[server] http2` y tres topes en `src/config.nx`; enganche de ejemplo en
`examples/gateway-tls/main.nx`.

- Un bucle por conexión es el único que escribe al cliente. Las peticiones comunes van por el
  router de siempre, en un hilo auxiliar por petición en curso; los SSE los bombea el bucle y no
  gastan hilo.
- Medido con `curl`/nghttp2 (`tests/e2e_h2/run.sh`, dentro de `make test-proxy`): 8 SSE y un `GET`
  por una sola conexión, el `GET` vuelve en ~12 ms; una petición de 1,5 s no frena a otra de la
  misma conexión; al irse los clientes, el backend queda con 0 canales abiertos.
- Las 12 suites que ya había siguen en verde, sin tocarlas.

**No se hizo**: activarlo en el gateway de producción (`~/nyx/web/gateway`). Hace falta
re-vendorizar, poner `http2 = true`, enganchar `proxy_h2_init` / `proxy_h2_spawn_conn` en su
`main.nx`, recompilar y reiniciar el servicio. Es producción: espera la confirmación del dueño.

**Límite conocido**: el router sigue siendo bloqueante, así que cada petición en curso usa un hilo
mientras el upstream responde (tope `http2_max_inflight`, 64 por conexión).
