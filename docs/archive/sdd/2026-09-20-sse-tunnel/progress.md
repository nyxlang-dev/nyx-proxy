# SDD ledger — plan: docs/design/plans/2026-09-20-sse-tunnel.md

## Pre-flight

| Par | Hallazgo |
|---|---|

## Marcas por task — las exige `arc-close`, sin ellas el arco no cierra

- [ ] Task 1 — RED — probar que hoy el SSE se acumula
- [ ] Task 2 — el túnel en el router
- [ ] Task 3 — la suite completa
- [ ] Task 4 — consumidores y release
- [ ] Task 5 — producción
- [ ] Task 6 — el report al repo del lenguaje

Al terminar cada task van estas dos líneas, ANCLADAS a principio de línea (vocabulario de la
spec §4). El checklist de arriba es el recordatorio; lo que el cierre lee son estas:

    Task N: review <Approved|Approved-con-fix|light <archivos>/<líneas>> (<modelo|coordinador>)
    Task N: complete (<sha7>..<sha7>)

Y un `task-N-report.md` en este directorio por cada task completa. Una task que no se hace se
cierra con `skipped` y su ruling, no se deja sin marca.

## Rulings

Ruling: ejecutar el encargo recibido (Task 6 del arco `serve-sse` del repo del lenguaje) — GO
Ottavio 2026-09-19, reemitido en `task-6-fix1.md` tras perderse el del 2026-09-15. Porqué: el
arco `serve-sse` del lenguaje está bloqueado esperando este report y un SSE detrás del gateway
hoy no entrega ningún evento. Costo si está mal: el gateway queda como está, que es el estado
de hoy.

Ruling: la detección es por `Content-Type: text/event-stream`, NO por «toda respuesta sin
longitud» como pide la spec §3 del lenguaje — GO de esta sesión, a confirmar por el coordinador
en el report. Porqué: la mitad que importaba de esa regla («no vuelve al pool») ya está cumplida
desde `104d400`, y tunelizar toda respuesta sin longitud le sacaría a cualquier upstream
HTTP/1.0 el recálculo de `Content-Length` y el tope de 16 MiB. Costo si está mal: una task
adicional en el proxy para la otra mitad.

## Marcas

Task 1: review light tests/test_proxy_sse_tunnel.nx+scripts/run_unit_tests.sh/~115 líneas (coordinador)
Task 1: complete (f18306b..f18306b)

## Avance

Task 1 (RED), 2026-09-20. Evidencia capturada para el report:
- caso de la suite: `ASSERTION FAILED: la respuesta SSE vuelve mientras el stream sigue abierto`, con `tiempo hasta la respuesta: 3016 ms` (el upstream cierra a los ~3000).
- variante con los valores de producción (plazo 30 s, upstream que no cierra): rc=124, matada por el timeout de 60 s del runner sin imprimir nada. No se deja en la suite: quemaría 60 s por corrida.
- línea base antes de tocar nada: 7 suites ok, 41 casos.

Nota de entorno: `~/nyx/lang` tiene otra sesión compilando (el arco fn-sin-firma) y
`run_unit_tests.sh` usa un script.nx COMPARTIDO allá. La primera corrida del RED devolvió
la salida de OTRO test. Se montó un NYX_HOME privado (bootstrap + runtime + std copiados)
para aislar las corridas de esta sesión.
Task 2: review (coordinador — el RED pasó a verde y las 11 de pool_framing quedaron intactas; la rama del túnel se movió ANTES de la lectura del cuerpo tras fallar el primer intento)
Task 2: complete (85e8913..85e8913)
Task 3: review (coordinador — 8 casos; el de "sin buffering" mide que la pausa del upstream se preserve, no solo que los eventos lleguen)
Task 3: complete (85e8913..85e8913)
Task 4: review light examples/standalone.nx+examples/gateway-tls/main.nx+CHANGELOG.md+nyx.toml/~70 líneas (coordinador)
Task 4: complete (85e8913..85e8913)

Task 2-4 (2026-09-20). Medición GREEN: primer evento a los 2 ms; segundo a los 502 ms
contra una pausa de 500 ms del upstream (la pausa se preserva ⇒ no hay buffering); el cierre
del cliente se detecta en 402 ms. Gates: 8 suites / 49 casos, sdd-check 76 casos.

Hallazgo lateral: `nyx build` estaba roto en main ANTES de este arco. El toolchain 0.32.4
exige `pub` para cruzar el límite de módulo y ni `proxy_dispatch` ni `ws_proxy` lo tenían;
verificado compilando HEAD en un worktree limpio. CI compila las dos cosas, así que estaba
rojo desde el 15/9. Arreglado acá.

Desvío de diseño respecto del plan: la rama del túnel iba "antes del if reusable == 1", que
es DESPUÉS de leer el cuerpo — con lo cual read_until_close ya había bloqueado y el túnel no
servía de nada. Se movió antes del bloque de lectura. Lo cazó el primer caso del test.
Task 5: review (coordinador — desplegado y verificado E2E sobre TLS contra el binario; el deploy verificó los 8 dominios)
Task 5: complete (45932f8..b8a7cb5)

Task 5 (producción, 2026-09-20). Gateway: vendor 0.4.3→0.4.4 (cf51a5b) y el fix de SIGPIPE
(commit siguiente), los dos desplegados con `make deploy`, que verifica los 8 dominios por SNI.
Verificación E2E contra el binario, en puertos de prueba:
- HTTP plano: tres eventos separados por 1 s llegan al cliente a 0.00s, 1.00s y 2.00s, y el
  cierre a 3.00s — las pausas del upstream se reproducen intactas.
- TLS: un cliente SSE que corta en seco a mitad del stream deja el proceso VIVO y atendiendo
  pedidos nuevos. Antes del fix, el caso equivalente moría con rc=141.

HALLAZGO GRAVE (bug del runtime, no del proxy): el runtime no instala SIG_IGN para SIGPIPE y
OpenSSL escribe con write() crudo, así que tls_write_conn contra un peer cerrado mata el
proceso. Afecta también a ws_tunnel y al camino normal, con ventana más corta. Va al report.

Dos errores propios corregidos en el camino, los dos del tipo que AGENTS.md ya documenta:
- el thread lector del test podía arrancar después del túnel y medía su propio retraso (en una
  máquina cargada daba "500/500", que parecía buffering y no lo era). Antes de encontrarlo
  llegué a atribuirlo a una captura de closures del compilador; era mío.
- el centinela "todavía no llegó" era 0, indistinguible de "llegó a los 0 ms".
Task 6: review (coordinador — report commiteado y pusheado a la rama del arco en el repo del lenguaje)
Task 6: complete (8753da52 en el repo del lenguaje, no en este)

Task 6 (2026-09-20). Report en `docs/design/briefs/2026-09-14-serve-sse/task-6-report.md` de la
rama `arc/serve-sse` del repo del lenguaje, commit 8753da52, pusheado. Se escribió desde un git
worktree y NO con checkout: esa rama está detrás de main y cambiar de rama allá habría movido el
toolchain bajo los pies de esta sesión y arrastrado trabajo ajeno sin commitear. Solo se tocó ese
archivo, como pedía el encargo.
Arco: COMPLETO (97d5bb6, 2026-09-20)
