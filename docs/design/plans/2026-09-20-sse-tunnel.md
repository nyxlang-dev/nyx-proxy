> **ESTADO: COMPLETO** — cerrado 2026-09-20, cosecha en docs/archive/sdd/2026-09-20-sse-tunnel/

# Túnel SSE: text/event-stream en vivo a través del proxy — Implementation Plan

> **Para agentes:** los steps se siguen con checkbox (`- [ ]`), pero lo que el cierre lee no
> es el checkbox sino las marcas ancladas del ledger, que siembra `scripts/sdd/ledger-new`.
> El método no depende de ningún plugin: los scripts de `scripts/sdd/` se bastan solos.

**Goal:** que una respuesta `Content-Type: text/event-stream` llegue al cliente evento por
evento en vez de acumularse hasta que el upstream cierre.

**Architecture:** un túnel de UN SOLO SENTIDO (upstream → cliente) modelado en `ws_tunnel` pero
sin su segundo thread ni su mutex, porque SSE no es bidireccional. La detección va en la
RESPUESTA (el `Content-Type` del upstream), no en el request como el upgrade WebSocket.

**Tech Stack:** Nyx; `src/router.nx`; builtins `try_tcp_read_partial`, `tls_wait_readable`,
`tls_read_nonblock`, `tls_write_conn`, `tcp_shutdown`, `tcp_set_timeout`.

**Encargo:** este arco responde el encargo recibido en
`docs/design/briefs/_recibidos/2026-09-14-serve-sse-task-6.md` (Task 6 del arco `serve-sse` del
repo del lenguaje, GO 2026-09-19). El report vuelve por git a ese repo.

**Spec:** el diseño vive en el brief recibido y en la spec §3 / D-7 del repo del lenguaje; acá
no se duplica.

## Global Constraints

- La versión vive en `nyx.toml` y no se toca por mergear. Mergear ≠ releasear.
- Gates por task: `make test-proxy` 100% + `make build` + `make sdd-check`.
- Los subagentes NUNCA pushean ni mergean; sin sub-subagentes.
- Gate humano de merge: no
- **No se toca el arreglo del pool de `104d400`**: el túnel se construye sobre
  `read_upstream_response_m`, y con el flag apagado el camino caliente queda byte-idéntico.
- **La detección es por `Content-Type`, no por «respuesta sin longitud»**: desviación explícita
  de la spec §3, declarada en el report para su `Ruling:`.

---

### Task 1: RED — probar que hoy el SSE se acumula

**Files:**
- Create: `tests/test_proxy_sse_tunnel.nx` (solo el caso rojo)
- Modify: `scripts/run_unit_tests.sh` (la lista `TESTS` es explícita, no un glob)
- Test: el caso rojo ES el test

**Interfaces:**
- Consumes: `forward_pooled`, `upstream_set_close_timeout`, `monotonic_ms`
- Produces: el transcript del RED, que el report exige

- [ ] **Step 1:** upstream falso que manda la cabecera SSE, un evento y heartbeat cada 200 ms
      durante ~3 s; con el plazo de inactividad en 1 s el heartbeat impide que venza.
- [ ] **Step 2:** assert de que la respuesta vuelve en menos de 1 s → falla hoy (vuelve a los
      ~3 s, con todo junto). Capturar la salida.
- [ ] **Step 3:** correr a mano, UNA vez, la variante con plazo de 30 s y heartbeat sin cierre:
      no retorna nunca y el runner la mata a los 60 s. Es el síntoma de producción. No se deja
      en la suite.

### Task 2: el túnel en el router

**Files:**
- Modify: `src/router.nx`
- Test: la suite de la Task 1 pasa a verde

**Interfaces:**
- Consumes: `read_upstream_response_m`, `forward_pooled`, `proxy_dispatch`
- Produces: `sse_tunnel`, `proxy_dispatch_c`, y los wrappers que dejan intacta la API vieja

- [ ] **Step 1:** capturar `content-type` en el loop de cabeceras y `is_event_stream()`, que
      corta en el primer `;` y compara por igualdad (no por prefijo: `text/event-streamx`).
- [ ] **Step 2:** `read_upstream_response_mc(..., tunnel_ok)` con un tercer elemento `sse_fd`
      (`-1` salvo SSE) en TODAS sus salidas; wrapper viejo de 2 elementos.
- [ ] **Step 3:** la rama SSE antes del `if reusable == 1`: devuelve el fd sin `pool_put` ni
      `pool_discard`, y arma la cabecera sin `Content-Length` y con `Connection: close`.
- [ ] **Step 4:** `forward_pooled_c` propagando en sus tres llamadas; wrapper viejo.
- [ ] **Step 5:** `sse_tunnel` inline (0 threads, 0 mutex) con la sonda de vida del cliente en
      el ciclo ocioso, y el tope `g_sse_max_tunnels`.
- [ ] **Step 6:** `proxy_dispatch_c`: single-flight liberado ANTES de bloquear, sin
      `cache_try_store`, log y métrica al ABRIR, y `""` como retorno.

### Task 3: la suite completa

**Files:**
- Modify: `tests/test_proxy_sse_tunnel.nx`
- Test: 9 casos

**Interfaces:**
- Consumes: el patrón de `tests/test_proxy_pool_framing.nx`
- Produces: cobertura de todo lo que el encargo pide verificar

- [ ] **Step 1:** relay en orden y sin buffering — se mide que la pausa del upstream se
      PRESERVE entre los dos eventos; si bufferizara llegarían juntos al final.
- [ ] **Step 2:** cliente que se va → el upstream ve el cierre, el fd no vuelve al pool.
- [ ] **Step 3:** el pedido siguiente por el mismo pool recibe SU respuesta.
- [ ] **Step 4:** no regresión — una respuesta sin longitud que NO es SSE se comporta igual.
- [ ] **Step 5:** matching del `Content-Type`, SSE con longitud, y el tope.
- [ ] **Step 6:** un caso sobre TLS real, último y con SKIP limpio.

### Task 4: consumidores y release

**Files:**
- Modify: `examples/standalone.nx`, `examples/gateway-tls/main.nx`, `CHANGELOG.md`, `nyx.toml`
- Test: `make build` y la compilación del ejemplo TLS, que es lo que corre CI

**Interfaces:**
- Consumes: `proxy_dispatch_c`
- Produces: v0.4.4

- [ ] **Step 1:** los dos ejemplos pasan a `proxy_dispatch_c` y tratan `""` como «ya está».
- [ ] **Step 2:** `CHANGELOG.md` con la etiqueta del arco, la asimetría con `ws_tunnel`, el
      alcance acotado y el techo efectivo de túneles.

### Task 5: producción

**Files:**
- Modify: `~/nyx/web/gateway` (repo aparte): `src/main.nx` y el pin vendorizado
- Test: `smoke.sh`, y un upstream SSE de prueba con `curl -N` contra :443

**Interfaces:**
- Consumes: la lib vendorizada
- Produces: el gateway sirviendo SSE en vivo

- [ ] **Step 1:** los dos workers a `proxy_dispatch_c`, y `sse_set_max_tunnels(128)` (la mitad
      de los 256 workers, para que un flood de SSE no deje el gateway mudo).
- [ ] **Step 2:** vendorizar, compilar, smoke, reiniciar el servicio.
- [ ] **Step 3:** verificar con un upstream SSE de prueba: hoy NO hay ninguno en producción,
      así que sin este paso no se puede escribir «desplegado y verificado».

### Task 6: el report al repo del lenguaje

**Files:**
- Create: `task-6-report.md` en el repo del lenguaje, rama `arc/serve-sse`, y solo ese archivo
- Test: el arco `serve-sse` deja de estar bloqueado

**Interfaces:**
- Consumes: todo lo anterior
- Produces: el report que el encargo espera desde el 2026-09-15

- [ ] **Step 1:** escribirlo desde un `git worktree`, NO con checkout: esa rama está detrás de
      `main` y cambiar de rama en `~/nyx/lang` movería el toolchain y arrastraría trabajo ajeno
      sin commitear.
- [ ] **Step 2:** incluir el RED verificado, el GREEN, los commits, el estado de despliegue, la
      desviación para `Ruling:` y los hallazgos laterales.

## Fuera de alcance

- Tunelizar TODA respuesta sin longitud (la otra mitad de la spec §3): ya no corrompe el pool
  desde `104d400`, y hacerlo cambiaría el comportamiento de cualquier upstream HTTP/1.0.
- El bug de unidades de `proxy_dispatch` (mide en segundos y lo pasa a parámetros `latency_us`):
  se documenta, no se arregla acá, y la rama SSE usa las mismas expresiones para que un solo fix
  futuro cubra los dos caminos.
- El E2E en `tests/integration/` del repo del lenguaje: se pide por report, no se escribe desde
  este lado (el encargo dice explícitamente que no se toque ningún otro archivo de aquel repo).
- Un builtin `tcp_wait_readable`: se pide por report.

## Verificación E2E

`make test-proxy` con las 11 suites de `test_proxy_pool_framing` intactas; `make build`; el
ejemplo TLS compilando; el gateway desplegado sirviendo eventos uno por uno bajo `curl -N`.

## Self-review

- ¿El camino sin túnel quedó byte-idéntico? (el flag apagado ni evalúa el `Content-Type`)
- ¿Algún camino nuevo puede devolver al pool un fd de un stream?
- ¿El single-flight queda liberado en TODAS las salidas de la rama SSE?
