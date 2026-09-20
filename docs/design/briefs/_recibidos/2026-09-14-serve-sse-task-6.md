# Encargo recibido — Task 6 del arco `serve-sse`

> **Origen**: repo del lenguaje (`~/nyx/lang`), rama `arc/serve-sse`, archivo
> `docs/design/briefs/2026-09-14-serve-sse/task-6-fix1.md` (commit `14116e52`).
> **Recibido**: 2026-09-20. **GO**: 2026-09-19. **Report**: vuelve por git a esa misma
> rama, como `task-6-report.md`.
>
> Copia literal del encargo. El plan al que pertenece vive en el repo del lenguaje, no
> acá: por eso está en `_recibidos/` y está exento de la regla (f) de `state-check`.

---

# Brief — Task 6 de 2026-09-14-serve-sse

GO: 2026-09-19 · rama: arc/serve-sse · base: a7f738d · ejecuta: sesión de ~/nyx/products/proxy
Reporte: escribir `docs/design/briefs/2026-09-14-serve-sse/task-6-report.md` y commitearlo en la rama.

## Task

### Task 6: Encargo a nyx-proxy: respuestas sin longitud fuera del pool y túnel SSE

Tamaño estimado: **M** (1 día, en el repo de `nyx-proxy`).

**Files:**
- Create: `docs/design/briefs/2026-09-14-serve-sse/` vía `bash scripts/sdd/brief docs/design/plans/2026-09-14-serve-sse.md 6 --remote`.
- Modify (en `~/nyx/products/proxy`, por su sesión): `src/router.nx` (`read_upstream_response` y un túnel de un solo sentido modelado en `ws_tunnel`); en el gateway PRIVADO, solo lo que haga falta para usarlo.
- Test: en el repo del proxy, un upstream de prueba que responde `text/event-stream` y otro que responde sin `Content-Length`; verificar que el cliente recibe el stream y que el pedido siguiente por el mismo pool recibe su propia respuesta.

**Interfaces:**
- Consumes: la spec §3 y D-7.
- Produces: un gateway que tuneliza `text/event-stream` y nunca devuelve al pool un fd con cuerpo sin leer. El aviso de `LLM.md` sobre el gateway se quita cuando esto esté entregado en producción.

- [ ] **Step 1:** Escribir el brief con la evidencia de §Contexto 6 de la spec (líneas de `router.nx`, `main.nx` y `std/proxy.nx`) y el caso que corrompe el pool.
- [ ] **Step 2:** Registrar en el ledger la línea `Ruling:` con el GO citado (regla cross-repo del método).
- [ ] **Step 3:** Al volver el reporte de la sesión del proxy, verificar su evidencia y anotarla en el ledger.


## Ajustes del coordinador

**Reemisión del encargo `task-6.md` (2026-09-19): no es una ronda de corrección.** La Task 6 nunca
se ejecutó. El encargo del 2026-09-15 vivía solo en este repo y nada del lado del proxy apuntaba a
él: `~/nyx/ops/proxy/PROJECT_STATE.md` es del 1 de agosto. Por eso el report no volvió. El alcance
técnico es el mismo de `task-6.md`; esto actualiza lo que cambió desde entonces.

- **La precondición ya se cumplió.** El arreglo del pool está en el `main` del proxy (`104d400`,
  v0.4.3, suite `tests/test_proxy_pool_framing.nx` de 11 casos) y en producción: el gateway lo
  vendorizó (`c4f148d`), el binario se compiló el 2026-09-15 12:40 y el servicio se reinició el
  2026-09-17. El túnel se construye sobre `read_upstream_response_m`, no sobre el router viejo.
- **Qué pasa hoy con un SSE detrás del gateway (medido leyendo el código, no en vivo):** ya NO se
  mezclan respuestas entre usuarios. Una respuesta sin longitud se lee hasta el cierre, con un plazo
  de 30 s de inactividad y un tope de 16 MiB, y el fd se descarta. Pero el heartbeat de `std/serve`
  (`:\n\n` cada 15 s) impide que venza el plazo, así que el gateway acumula en silencio y el
  navegador **no recibe ningún evento** hasta que el upstream cierre o se llegue al tope. Eso es lo
  que el túnel tiene que resolver.
- **Rama y base.** El encargo original nombraba una rama de worktree que ya no existe. El trabajo de
  código va en el repo del proxy, en la rama que su sesión elija, y el merge a su `main` es del
  proxy. El **report** va en ESTE repo (`~/nyx/lang`), en la rama `arc/serve-sse`:
  `git fetch && git checkout arc/serve-sse`, escribir
  `docs/design/briefs/2026-09-14-serve-sse/task-6-report.md`, commitear solo ese archivo y
  `git pull --rebase && git push`. No toques ningún otro archivo de este repo: los archivos raíz
  (`LLM.md`, `CHANGELOG.md`, etc.) los cambia la máquina con el candado cuando llegue el report.
- **El report tiene que traer:** los commits del proxy (y del vendor en el gateway, si se hizo); la
  salida de los tests nuevos, junto al RED verificado contra el router sin túnel; y si quedó
  desplegado en producción o no. De eso depende quitar el aviso del gateway de la documentación del
  lenguaje.
- **Si no se va a hacer**, un report de una línea que lo diga también sirve: el arco `serve-sse` se
  cierra entonces con un `Ruling:` que deja el túnel como deuda del proxy. Lo que no puede pasar es
  que el encargo quede en silencio otra vez.
