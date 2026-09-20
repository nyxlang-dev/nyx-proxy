# AGENTS.md — playbook de nyx-proxy

Para agentes y personas que vienen a trabajar **en este repo**. Si lo que buscás es cómo *usar*
la librería, eso está en `README.md` y `docs/CONFIG.md`; si buscás qué existe en la stdlib de
Nyx, en `CAPABILITIES.md`.

---

## ⚠ Lo primero: encargos abiertos

**`docs/design/ROADMAP.md` §Encargos abiertos.** Leelo antes de empezar nada.

Este repo recibe encargos de otros repos (hoy, del repo del lenguaje). Llegan **por git**, nunca
por chat, y se copian al buzón `docs/design/briefs/_recibidos/` aunque su plan viva en el otro
repo. La regla es una sola:

> **Un encargo que no está en el repo no existe.**

No es teoría: el 2026-09-15 el lenguaje encargó el túnel SSE y el encargo **se perdió tres días**
porque vivía solo allá y nada de este lado lo mencionaba. Cuando termines un encargo, el report
vuelve por git al repo que lo emitió. Un report de «no se hace» también sirve — lo que no puede
pasar es el silencio.

---

## Qué es este repo

Una **librería** reverse proxy escrita en Nyx, no un daemon. Da TLS termination, SNI
multi-dominio, health checks activos, rate limiting per-IP, cache LRU por host con TTL,
`/metrics` Prometheus, WebSocket proxying y access logging.

El binario que produce `make build` (desde `examples/standalone.nx`) es un **smoke HTTP-only**, no
el producto. El consumer de producción vive aparte, en `~/nyx/web/gateway`: es el gateway HTTPS
:443 de nyxlang.com y **vendoriza esta lib commiteada** en su `packages/nyx-proxy/`, con pin
explícito, vía su `scripts/vendor_nyx_proxy.sh`. Cambiar la lib no cambia producción: hay que
re-vendorizar, commitear el pin, recompilar y reiniciar el servicio.

**El repo es público.** Todo commit —el mensaje incluido— se publica al instante.

## Mapa de `src/`

| Módulo | Qué hace |
|---|---|
| `config.nx` | parsea `proxy.toml`: upstreams, vhosts, health, rate, TLS, cache, metrics |
| `router.nx` | **el corazón** (~1000 líneas): pool de conexiones, encuadre de la respuesta, `proxy_dispatch`, `ws_proxy`/`ws_tunnel` |
| `health.nx` | health checks TCP activos con umbral de fallos |
| `logger.nx` | access logs |
| `ratelimit.nx` | ventana deslizante per-IP, 429 con `Retry-After` |
| `cache.nx` | LRU por host con TTL + single-flight |
| `metrics.nx` | Prometheus: requests, cache, histograma de latencia, rate-limit |
| `admin.nx` | listener HTTP aparte para `/metrics` y `/healthz` |

Casi todo el riesgo está en `router.nx` y `cache.nx`. Un cambio ahí no se revisa a la ligera
(lo dice el método, §4 del spec).

## Comandos

```bash
make build        # compila examples/standalone.nx → ./nyx-proxy
make test-proxy   # las suites .nx, sin servidores externos
make sync-public  # publica la lib
make sdd-check    # selftest del método SDD
make docs-health  # guardas de docs: index-gen --check + state-check
```

El toolchain se toma de `NYX_HOME`. El monorepo corre `make test-proxy` como canario.

---

## Rieles y gotchas

Cada uno tiene una cicatriz detrás. No son preferencias de estilo.

**Strings: rebanar SIEMPRE con `byte_length()` / `str_byte_length()`, nunca `length()`.**
`length()` cuenta codepoints UTF-8, pero `substring()` e `indexOf()` operan en bytes. Un body
multi-byte cacheado perdía sus últimos 8 bytes en cada HIT (`6d519cb`).

**`tcp_read_partial` devuelve `""` en EOF, en error Y en timeout — es ambiguo.** Para
distinguirlos usá la variante Result `try_tcp_read_partial`: `Ok("")` es EOF limpio,
`Err{code:11}` es EAGAIN (venció el `SO_RCVTIMEO`). **Discriminá por `e.code`, no por `e.kind`**:
el 11 no está en `errno_to_kind` y cae al catch-all `"io"`, indistinguible de un error real.

**`tcp_set_timeout(fd, 0)` DESACTIVA el plazo**, no lo pone en cero. El mínimo útil es 1.

**`tcp_close(fd)` NO despierta un `recv()` bloqueado en otro thread; `tcp_shutdown(fd, …)` sí.**
Peor: después del close el número de fd puede reciclarse y el lector todavía bloqueado puede
robarle bytes a una conexión nueva. Patrón: el **no-dueño** hace `tcp_shutdown` para despertar al
lector; solo el **dueño** hace `tcp_close`.

**`tcp_write` no tiene timeout por defecto**: loopea `send()` hasta completar, así que un peer con
ventana cero lo bloquea para siempre. Cualquier camino de escritura que no pueda colgarse necesita
`tcp_set_timeout` antes.

**Nunca un read bloqueante bajo el lock del `SSL*`.** Un wakeup de `poll()` puede ser solo un
record de control TLS 1.3 (un `NewSessionTicket` post-handshake): el `SSL_read` siguiente se queda
esperando **con el lock tomado** y deadlockea contra el writer. El patrón correcto es
poll-then-lock: `tls_wait_readable` sin lock, y después `tls_read_nonblock` bajo lock.

**Si `tls_wait_readable` devuelve 1, hay que consumir.** Cortocircuita en `h->buf` y
`SSL_pending()` **antes** de mirar `h->eof`, y solo `tls_read_nonblock` setea ese flag. Sin el
consumo, un peer que mandó `close_notify` devuelve `1` para siempre → busy-spin al 100% de CPU.

**Escritura al cliente: comparar bytes escritos contra el largo esperado.** `tls_write_conn`
devuelve `-1` si no escribió ninguno, pero puede devolver un valor **parcial** si un `SSL_write`
intermedio falla. `wrote > 0` no es «salió bien».

**Un fd solo vuelve al pool con el cuerpo leído entero y su fin conocido** (RFC 9112 §6.3). Antes
de `104d400` el router devolvía al pool conexiones con el cuerpo sin leer y el pedido siguiente
—quizá de otro usuario— leía la respuesta ajena. `pool_put` se llama en **un solo lugar**; si
agregás un camino de salida a `read_upstream_response_*`, decidí explícitamente si descarta.

**No hay HTTP/2 al upstream** (solo HTTP/1.1), el cache **ignora `Vary`** (la clave es
`host:path`) y los health checks son **solo TCP**.

## Tests

Sin framework. Cada caso es una `fn test_xxx()`, `main()` las llama en orden, se assertea con
`assert(cond, "msg")` y cada caso exitoso imprime una línea que **empieza con `PASS` en columna 0**
— el runner las cuenta con `grep -c "^PASS"`.

Los upstreams se simulan con **servidores TCP reales en threads del mismo proceso**: un array
global de fds de listener, una fn-thread por caso que hace `tcp_accept`, drena el pedido y escribe
bytes crudos de respuesta. Puertos fijos fuera del rango efímero (19350+), uno por caso, y un
índice de upstream distinto por caso para no compartir pool.

Dos cosas que hay que saber:

- **La lista de suites está hardcodeada** en `scripts/run_unit_tests.sh`. Una suite nueva que no
  se agregue ahí no corre nunca; una que se borre sin sacarla de la lista falla explícito (por eso
  es una lista y no un glob).
- **Un test que se cuelga muere por `timeout 60`**, y eso es una herramienta, no un accidente: si
  un upstream falso atiende varios pedidos sobre UNA conexión y el proxy abriera otra en vez de
  reusar el pool, el `accept` no llega y el test falla en vez de pasar por casualidad.

---

## El método: SDD

Un **arco** es una unidad de trabajo con diseño aprobado. Se siembra con
`bash scripts/sdd/arc-new <slug> --plan "Título"`, que crea el documento con su banner de estado;
se aprueba pasando ese banner a `VIGENTE` con el `GO`; se ejecuta contra un **ledger efímero**
(`.sdd/<plan-basename>/`, gitignored) donde van las marcas que el cierre exige; y se cierra con
`bash scripts/sdd/arc-close <plan>`, que valida todo **antes de escribir nada**, cosecha el ledger
a `docs/archive/sdd/` y lo commitea.

Los encargos a otra máquina o sesión salen con `bash scripts/sdd/brief <plan> N --remote`, que
escribe un archivo commiteable — nunca por chat.

Como el repo es público, **lo que el cierre cosecha se publica**. Por eso `arc-close` rechaza
cerrar si el ledger cita una ruta de máquina (`/home/…`, un scratchpad de sesión, un montaje de
WSL). Escribí `~/nyx/…` y listo. El método completo, con las diez reglas y sus guardas, está en
`docs/design/specs/2026-09-20-sdd-proxy-design.md`.
