# Encargo recibido — X-Forwarded-Host y X-Forwarded-Proto hacia el upstream

> **Origen**: repo del lenguaje (`~/nyx/lang`), sesión lang-c1.
> **Recibido**: 2026-09-24, por chat (no llegó por git: se copia acá para que exista).
> **Urgencia**: nyxerp abre su punto de venta en producción el sábado 2026-09-26 detrás del
> gateway (sumain2.nyxerp.com y demo.nyxerp.com ya publicados).
> **Report**: al pie de este archivo. El encargo pedía no tocar `~/nyx/lang`, `~/.nyx` ni el
> gateway (`~/nyx/web/gateway`): lo re-vendoriza y despliega la sesión del lenguaje.
>
> Transcripción del encargo. Está en `_recibidos/` y exento de la regla (f) de `state-check`.

---

Hoy el login de nyxerp da 403 por dos fallas de nyx-proxy en el reenvío al upstream
(`src/router.nx`: `forward_pooled_c`, y el camino WS/túnel si arma su propia petición):

1. `Host` se reescribe a `backend.host:port` y NO se agrega `X-Forwarded-Host`: el backend no
   puede saber el dominio público (nyxerp compara el Origin con X-Forwarded-Host/Host; también
   hace falta para redirecciones absolutas). Pedido: agregar
   `X-Forwarded-Host: <Host original del cliente>`. Decidir si además conviene una opción por
   upstream para preservar el Host; lo mínimo es X-Forwarded-Host.
2. `X-Forwarded-Proto: http` está FIJO aunque el cliente haya entrado por TLS (el gateway
   termina HTTPS en :443). Silencioso: cookie Secure y URLs absolutas del backend se equivocan.
   Tiene que reflejar el esquema real (https en el listener TLS, http en el plano).

Además: hoy se omite Host con comparación sensible a mayúsculas (`hk != "Host"`): un `host` en
minúsculas pasaría duplicado. Y cualquier X-Forwarded-Host/Proto que mande el cliente se
DESCARTA y se reemplaza (como ya se hace con X-Real-IP): es falsificable.

Tests de regresión que fallen con el código viejo (upstream falso que devuelva los encabezados
recibidos): Host original → X-Forwarded-Host; listener TLS → Proto https, plano → http; valores
falsos del cliente descartados; `host` en minúsculas sin duplicar. Verificar el sabotaje. Release
de parche, commit y push. Al terminar: tag/sha publicado y, si cambió la firma de
`inject_forwarded_headers`, cómo llamarla ahora.

---

## Report — 2026-09-24

**Hecho en v0.4.8.** La firma de `inject_forwarded_headers` **no cambió**, ni la de ninguna fn
pública: el gateway no necesita tocar su `main.nx`, alcanza con re-vendorizar.

Dónde se resolvió: en el router y no en `inject_forwarded_headers`. El router ya sabe el esquema
por la convención del sink de `proxy_dispatch_c` (`ssl_handle > 0` ⇒ TLS), y el gateway ya le
pasa `ssl_handle` desde el worker TLS y `0` desde el plano. `ws_proxy` solo existe en el camino
TLS, así que manda `https`. Una fn nueva `upstream_header_lines` arma las cabeceras reenviadas
para los dos caminos (HTTP y handshake WS), así que no pueden divergir.

- `X-Forwarded-Host` = Host original del cliente, tal cual (con puerto si lo traía). Si el
  cliente no mandó Host, no se inventa.
- `X-Forwarded-Proto` = `https` / `http` según el listener.
- Los `X-Forwarded-Host`/`X-Forwarded-Proto` del cliente se descartan, sin importar mayúsculas.
- Nombres de cabecera sin mayúsculas: `host` en minúsculas ya no llega duplicado, y además ahora
  enruta a su vhost (antes caía en el upstream por defecto, porque `http_find_header` compara
  exacto).
- De paso, en el mismo lazo: el `Content-Length` del cliente llegaba duplicado con el del router
  en cada POST. Ahora va uno solo.

**Opción para preservar el Host: no se agregó.** Con `X-Forwarded-Host` alcanza para nyxerp y
para las redirecciones absolutas, y una opción nueva de `proxy.toml` a dos días de una apertura
en producción es superficie sin pedido concreto. Queda como pendiente en el ROADMAP.

Evidencia:

- Suite nueva `tests/test_proxy_fwd_headers.nx`, 7 casos contra un upstream eco real que devuelve
  como cuerpo las cabeceras recibidas. `make test-proxy` en verde.
- Sabotaje: con el `src/router.nx` anterior la suite falla. Además, cada falla reintroducida POR
  SEPARADO sobre el código nuevo rompe su propio caso: sin X-Forwarded-Host, Proto fijo en http,
  X-Forwarded-* del cliente pasando, `Host` comparado exacto, vhost buscado exacto (502) y
  Content-Length duplicado — seis de seis.
- No cubierto por test de punta a punta: el handshake WS (`ws_proxy` escribe con
  `tls_write_conn` y necesita un handle TLS real). Usa la misma `upstream_header_lines` que sí
  está cubierta.

Para el gateway, que sigue siendo de la sesión del lenguaje: el rate limit de su `http_worker`
lee el Host con `http_find_header(headers, "Host")`, que compara exacto; un `host` en minúsculas
llega ahí vacío. No es de este encargo, pero vale mirarlo al re-vendorizar.
