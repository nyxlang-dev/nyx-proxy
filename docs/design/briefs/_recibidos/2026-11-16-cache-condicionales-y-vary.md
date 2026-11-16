# Encargo recibido — la caché no contesta 304, ignora `Vary` y lee `Cache-Control` del cuerpo

> **Origen**: sesión del lenguaje, 2026-11-16, pedido por el dueño del repo. Nace de un reporte de
> fricción del equipo de nyxerp del 2026-11-13.
> **Recibido**: 2026-11-16, por mensaje entre sesiones (no llegó por git: se copia acá para que
> exista). Se suma a `2026-11-14-cache-autenticada.md`, que va primero; se solapan en `Vary`.
> **Report**: al pie de este archivo, y como sección «Respuesta» en el encargo original.
>
> Transcripción del encargo, sin las rutas de la máquina que lo escribió. Está en `_recibidos/` y
> exento de la regla (f) de `state-check`.

---

Verificado leyendo el código en `5a37a8a` (v0.4.14), no corriendo el proxy.

| # | Defecto | Dónde | Clase |
|---|---|---|---|
| 1 | Un acierto de caché contesta 200 con el cuerpo entero aunque el pedido traiga un `If-None-Match` que coincide | `src/router.nx`, el acierto y el camino de single-flight: devuelven lo guardado sin mirar las cabeceras del pedido. En `src/` no hay ninguna mención a `If-None-Match` ni a `If-Modified-Since` | ineficiencia: un `.wasm` de 1 MB bajaba entero en cada apertura |
| 2 | Un cliente sin `Accept-Encoding` recibe `content-encoding: gzip` | la clave es `host + ":" + path` (`src/cache.nx`, y las tres de single-flight); `Vary` no se lee nunca | **datos equivocados en silencio** |
| 3 | `Cache-Control` se busca en la respuesta entera, cuerpo incluido | `_extract_cache_control` hace `indexOf` sobre todo el `String`. Si la cabecera no viene, un cuerpo que contenga ese texto decide si se guarda y con qué TTL | hallazgo propio, no está en el reporte |
| 4 | La documentación no dice cómo trata la caché los condicionales ni `Vary` | `docs/CONFIG.md` y `README.md` sí dicen qué se guarda y el TTL por omisión | doc |

Dos detalles vecinos del punto 3: `_cc_contains_directive` compara por subcadena, y la cabecera
solo se reconoce escrita `Cache-Control:` o `cache-control:`.

**Qué se pide.**

1. **`Vary`.** Recomendación: meter el `Accept-Encoding` normalizado del pedido en la clave cuando
   la respuesta trae `Vary: Accept-Encoding`, y no guardar respuestas con cualquier otro `Vary`.
   La clave de single-flight tiene que cambiar igual.
2. **304 en el acierto.** Si el `If-None-Match` del pedido coincide con el `ETag` guardado,
   contestar 304 sin cuerpo (RFC 9111 §4.3.2), con comparación débil y admitiendo lista y `*`.
   `If-Modified-Since` contra `Last-Modified` como respaldo cuando no hay `If-None-Match`. El
   access log y las métricas hoy registran 200 fijo en el acierto.
3. **Leer `Cache-Control` solo de la cabecera** de la respuesta, sin distinguir mayúsculas.
4. **Documentar** en `docs/CONFIG.md` y el `README.md` cómo se tratan los condicionales y `Vary`.
5. **Tests** en `tests/test_proxy_cache.nx`, uno por punto. Antes de darlos por buenos, sabotear
   el código y comprobar que cada uno falla. El reporte dice que el defecto 1 se ve igual por
   HTTP/1.1 y por HTTP/2: conviene un test por cada frente.

**Entrega.** Publicar el gateway y reiniciarlo corta todos los dominios: ese paso lo decide el
dueño. Encender la caché en producción es una decisión aparte y depende además del encargo del
14/11.

---

## Report — 2026-11-16

**Hecho en v0.5.0**, en la misma tanda
que el encargo del 14/11. Los cinco puntos:

1. **`Vary` — hecho como se recomendó.** Sin `Vary`: una entrada por `host:path`. Con
   `Vary: Accept-Encoding`: una por variante del `Accept-Encoding` normalizado del pedido (los
   códigos br/deflate/gzip/zstd/`*` que acepta, sin los `q=0`, en orden fijo: 32 variantes como
   mucho, un cliente no puede fabricar más). Cualquier otro `Vary` no se guarda. Dos añadidos: una
   respuesta con `Content-Encoding` va por variante aunque no traiga `Vary`, y solo se guarda si el
   código es uno de esos cuatro y el pedido lo aceptaba. La clave de single-flight lleva la
   variante.
2. **304 en el acierto — hecho.** `If-None-Match` con comparación débil, lista y `*`;
   `If-Modified-Since` contra `Last-Modified` solo si no hay `If-None-Match`. El 304 va sin cuerpo,
   repite `ETag`, `Cache-Control`, `Date`, `Expires`, `Last-Modified`, `Vary` y lleva
   `X-Nyx-Cache: HIT`. También en el camino de single-flight. El access log registra 304; `/metrics`
   lo cuenta en `3xx` (solo expone la clase del status).
3. **`Cache-Control` solo de la cabecera — hecho**, sin distinguir mayúsculas y por directiva
   entera (los dos detalles vecinos). Añadido: `s-maxage` manda sobre `max-age`.
4. **Documentación — hecha.** `docs/CONFIG.md` §`[cache]` dice qué se guarda, por cuánto
   (`s-maxage` → `max-age` → `default_ttl_seconds`, 300 s), cómo se tratan los condicionales y
   `Vary`, y cómo se apaga; `README.md`, `AGENTS.md` y `CHANGELOG.md` al día.
5. **Tests — hechos y saboteados.** `tests/test_proxy_cache.nx` (23 casos nuevos, uno o más por
   punto; 19 sabotajes de `src/cache.nx`, todos hicieron fallar la suite),
   `tests/test_proxy_cache_router.nx` (nueva, por el router contra upstreams reales) y
   `tests/e2e_h2/run.sh` con curl **por los dos frentes**: el 304 con 0 bytes y `x-nyx-cache: HIT`
   por HTTP/2 y por HTTP/1.1. HTTP/2 llega al router por `proxy_dispatch_o`, el mismo camino: no
   hizo falta código aparte.

Verificación: `make test-proxy` — 13 suites y el e2e (33 chequeos) en verde.

**Para nyxerp:** cuando esto esté en producción *y* la caché se vuelva a encender para su
upstream, pueden retirar el `Cache-Control: no-cache` de los estáticos. Ojo con el punto 1 del
encargo del 14/11: un pedido con `Cookie` no pasa por la caché, así que un navegador con sesión
revalida contra su servidor (que ya contesta bien el 304), no contra el gateway.

Queda fuera de este repo: re-vendorizar el gateway, agregar `cache = true` a los upstreams que se
quieran cachear, que el gateway corra `watch_config_loop` si quiere la recarga en caliente, y la
decisión de volver a encender la caché en producción.
