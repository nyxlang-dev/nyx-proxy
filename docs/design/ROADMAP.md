# ROADMAP — arcos vivos de nyx-proxy

> **Rol de este archivo**: SOLO los arcos VIVOS y los encargos abiertos. Un arco que cierra se
> BORRA de acá — su narración va al `CHANGELOG.md` y su ledger queda cosechado en
> `docs/archive/sdd/<arco>/`. Es la «doc raíz» del método: un documento de diseño VIGENTE se
> sostiene porque este archivo lo cita, porque otro documento VIGENTE citado desde acá lo cita,
> o porque tiene un ledger vivo (regla (b) de `scripts/sdd/state-check`).
>
> Sin números de versión: la fuente de verdad es `nyx.toml`. Sin conteo de tests: es
> `scripts/run_unit_tests.sh`. El estado operativo del proyecto vive fuera del repo.
>
> Última actualización: 2026-09-20.

---

## Arcos vivos

_(ninguno)_

## Encargos abiertos

Los encargos que llegan de otro repo viven en `docs/design/briefs/_recibidos/`. **Un encargo que
no está en el repo no existe**: esa es la lección que costó la reemisión de la Task 6 de
`serve-sse`, que se perdió tres días porque vivía solo en el repo del lenguaje y nada de este
lado la mencionaba.

| Encargo | De | Estado |
|---|---|---|
| `briefs/_recibidos/2026-09-14-serve-sse-task-6.md` — túnel SSE | repo del lenguaje, rama `arc/serve-sse` | **respondido** el 2026-09-20 (v0.4.4, desplegado) |

## Deuda con orden de ejecución: retirar la mitigación de SIGPIPE

`signal_ignore(13)` está en dos lugares y es **temporal**. Lo puso v0.4.4 cuando se descubrió que
un `tls_write_conn` contra un peer cerrado mataba el proceso (el runtime no instalaba `SIG_IGN`
global y OpenSSL escribe con `write()` crudo). El core ya tiene el arreglo de verdad: un
`BIO_METHOD` propio cuyo `bwrite` va por `os_sock_send` con `MSG_NOSIGNAL`.

**El orden importa: retirarlo antes de tiempo reabre el agujero en producción.**

1. El repo del lenguaje mergea el BIO y publica el toolchain (`make install-local`). *(fuera de
   este repo; a la espera)*
2. Recompilar **esta lib y el gateway contra ese toolchain**. Mientras el binario desplegado siga
   enlazado con el runtime viejo, `signal_ignore(13)` es lo único que lo protege.
3. Correr `tests/test_proxy_sse_tls.nx` **sin** el `signal_ignore` del caso. Si pasa, el BIO cubre
   el agujero y recién ahí se retira la mitigación.

Qué se retira y qué no:

- **`sse_init()` en `src/router.nx` — SÍ, se retira.** Una biblioteca no puede cambiarle la política
  de señales al proceso que la importa; es el mismo argumento por el que el core NO hizo un
  `SIG_IGN` global.
- **El arranque del gateway privado — opcional.** Ahí somos la *aplicación*, que es la única que
  legítimamente decide ignorar una señal en su propio proceso. Como cinturón de seguridad no hace
  daño, solo deja de ser necesario.

## Cómo se trabaja acá

El método completo está en `docs/design/specs/2026-09-20-sdd-proxy-design.md` y los comandos en
`AGENTS.md`. En dos líneas: un arco se siembra con `arc-new`, se aprueba pasando su banner a
VIGENTE con el `GO`, se ejecuta contra un ledger efímero (gitignored, con la ruta derivable del
plan) y se cierra con `arc-close`, que cosecha ese ledger a `docs/archive/sdd/` y lo publica.
