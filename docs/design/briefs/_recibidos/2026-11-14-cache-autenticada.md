# Encargo recibido — la caché sirve respuestas autenticadas a pedidos sin sesión

> **Origen**: sesión del servidor, 2026-11-14. Gravedad: seguridad.
> **Recibido**: 2026-11-16, por mensaje entre sesiones (no llegó por git: se copia acá para que
> exista). Se trabajó junto con `2026-11-16-cache-condicionales-y-vary.md`.
> **Report**: al pie de este archivo, y como sección «Respuesta» en el encargo original.
>
> Resumen del encargo, sin los datos de la instalación afectada: este repo es público. Está en
> `_recibidos/` y exento de la regla (f) de `state-check`.

---

**Qué pasó.** Detrás del gateway, una ruta de API que directo al backend da `403` sin cookie de
sesión devolvía `200` con `x-nyx-cache: HIT`. Un usuario con sesión pedía la ruta, el proxy
guardaba la respuesta y durante el TTL se la servía a cualquiera. Segundo efecto: los clientes
veían datos de hasta un TTL y medio atrás.

**Causa.**

- La clave de la caché es `host:path`: no mira `Cookie` ni `Authorization` del pedido, e ignora
  `Vary`.
- Una respuesta `GET 200` sin `Cache-Control` se guarda con el TTL por omisión.
- `[cache]` es global: no se puede limitar por dominio ni por upstream.
- `cache_init` corre una vez al arrancar: apagar la caché exige reiniciar.

**Mitigación en producción.** `[cache].enabled = 0`, publicado el mismo 14/11.

**Qué se pide.**

1. No guardar ni servir desde caché un pedido que trae `Cookie` o `Authorization`, ni una
   respuesta con `Set-Cookie`.
2. Caché por dominio o por upstream (opt-in), para poder encenderla solo en las landings.
3. Respetar `Vary`, o no guardar respuestas que lo traen.
4. Tests de lo anterior en la suite de la caché.
5. Deseable: poder apagarla sin reiniciar (que `enabled` entre en la recarga en caliente).

La caché no se vuelve a encender en producción hasta que estén 1 y 2.

---

## Report — 2026-11-16

**Hecho en v0.5.0**. Los cinco puntos:

1. **Hecho.** Un GET con `Cookie` o `Authorization` (cualquier capitalización, aunque vengan
   vacías) no pasa por la caché: ni se sirve de lo guardado ni se guarda su respuesta, y tampoco
   entra en el single-flight. Una respuesta con `Set-Cookie` no se guarda. Consecuencia a saber:
   un navegador que manda cualquier cookie al dominio (analítica incluida) nunca recibe un acierto.
2. **Hecho, por upstream.** `cache = true` en `[upstream.N]`. Es opt-in estricto y por eso es un
   **cambio incompatible**: `[cache] enabled = 1` solo ya no guarda nada.
3. **Hecho** (ver el encargo del 16/11): `Vary: Accept-Encoding` va por variante; cualquier otro
   `Vary` no se guarda.
4. **Hecho.** `tests/test_proxy_cache.nx` (reglas de la caché) y la suite nueva
   `tests/test_proxy_cache_router.nx`, que reproduce el incidente por el router contra un upstream
   real: pedido con cookie, después sin cookie, y mide que el segundo llega al upstream y no trae
   el cuerpo del primero. Lo mismo con curl por HTTP/2 y HTTP/1.1 en `tests/e2e_h2/run.sh`. Cada
   caso se saboteó (p. ej. `cache_request_bypass` devolviendo 0) y falló.
5. **Hecho en la lib.** `reload_config_if_changed` relee `[cache] enabled` y los `cache = true`:
   apagarla vacía la caché y el router deja de consultarla en el pedido siguiente; encenderla la
   inicializa. `max_entries` y `default_ttl_seconds` solo se leen al inicializar.

De paso: `Cache-Control` se lee solo de la cabecera y por directiva entera, `s-maxage` manda sobre
`max-age`, y un acierto contesta 304 a los condicionales.

Verificación: `make test-proxy` — 13 suites y el e2e (33 chequeos) en verde; `make docs-health` y
`make sdd-check` en verde.

Queda fuera de este repo: re-vendorizar el gateway, agregar `cache = true` a los upstreams que se
quieran cachear, que el gateway corra `watch_config_loop` si quiere la recarga en caliente, y la
decisión de volver a encender la caché en producción.
