# ROADMAP — arcos vivos de nyx-proxy

> **Rol de este archivo**: SOLO los arcos VIVOS, los encargos abiertos y los pendientes fichados
> que todavía no son arco. Un arco que cierra se
> BORRA de acá — su narración va al `CHANGELOG.md` y su ledger queda cosechado en
> `docs/archive/sdd/<arco>/`. Es la «doc raíz» del método: un documento de diseño VIGENTE se
> sostiene porque este archivo lo cita, porque otro documento VIGENTE citado desde acá lo cita,
> o porque tiene un ledger vivo (regla (b) de `scripts/sdd/state-check`).
>
> Sin números de versión: la fuente de verdad es `nyx.toml`. Sin conteo de tests: es
> `scripts/run_unit_tests.sh`. El estado operativo del proyecto vive fuera del repo.
>
> Última actualización: 2026-09-24.

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
| `briefs/_recibidos/2026-09-24-nyx1036-pub.md` — avisos NYX1036 en tests | repo del lenguaje, sesión lang-c1 | **respondido** el 2026-09-24 (v0.4.7): report al pie del encargo |
| `briefs/_recibidos/2026-09-24-nyxerp-forwarded.md` — X-Forwarded-Host/Proto al upstream | repo del lenguaje, sesión lang-c1 | **respondido** el 2026-09-24 (v0.4.8): report al pie del encargo; falta re-vendorizar el gateway (lo hace el lenguaje) |

## Pendientes (sin arco todavía)

- **Opción por upstream para preservar el Host** del cliente en vez de reescribirlo a
  `backend.host:port`. Se decidió no hacerla en v0.4.8: `X-Forwarded-Host` alcanzaba para el
  caso que la motivó (nyxerp). Se retoma si aparece un backend que no lea X-Forwarded-Host.
- **`Transfer-Encoding` del cliente**: `http_parse_request` solo lee cuerpos con
  `Content-Length`, y el router reenvía el `Transfer-Encoding` del cliente tal cual. Un pedido
  chunked llegaría al upstream con la cabecera y sin cuerpo.

## Cómo se trabaja acá

El método completo está en `docs/design/specs/2026-09-20-sdd-proxy-design.md` y los comandos en
`AGENTS.md`. En dos líneas: un arco se siembra con `arc-new`, se aprueba pasando su banner a
VIGENTE con el `GO`, se ejecuta contra un ledger efímero (gitignored, con la ruta derivable del
plan) y se cierra con `arc-close`, que cosecha ese ledger a `docs/archive/sdd/` y lo publica.
