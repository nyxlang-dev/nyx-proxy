> **ESTADO: VIGENTE** — GO Ottavio 2026-09-20

# El método SDD en nyx-proxy

## Contexto

El 2026-09-15 el repo del lenguaje encargó a este repo la Task 6 del arco `serve-sse` (un túnel
SSE en el gateway). El encargo **se perdió**: vivía solo en el repo del lenguaje y nada de este
lado lo mencionaba. Se reemitió el 2026-09-19 con el diagnóstico escrito en el propio brief —
*«nada del lado del proxy apuntaba a él»* — y con una instrucción explícita: lo único inaceptable
es que el encargo quede en silencio otra vez.

Este repo no tenía dónde poner un encargo. Tampoco tenía `AGENTS.md`, aunque `CAPABILITIES.md`
lo referencia desde que se generó. Y `.superpowers/sdd/` ya guardaba un review-package suelto:
alguien había intentado usar el método acá, sin los scripts.

El método existe y está probado en el repo del lenguaje (`scripts/sdd/`, 13 scripts). Lo que
sigue es cómo queda al portarse, y **en qué se aparta del original y por qué**.

## Decisión

Se porta el método completo, con scripts. La regla de oro se conserva intacta:

> **Si una regla no tiene una guarda o un script que la haga cumplir, no es regla.** Es una
> costumbre, y las costumbres no se documentan.

### §1 — Las piezas de un arco

| Pieza | Obligatoria | Ubicación única |
|---|---|---|
| Spec (diseño aprobado) | si el arco es M o L | `docs/design/specs/YYYY-MM-DD-<slug>-design.md` |
| Plan de ejecución | siempre | `docs/design/plans/YYYY-MM-DD-<slug>.md` |
| Ledger de ejecución | siempre | derivable del plan, **efímero**, gitignored |
| Cosecha del ledger | siempre, al cerrar | `docs/archive/sdd/<plan-basename>/` — inmutable |
| Encargos emitidos | si los hay | `docs/design/briefs/<plan-basename>/` |
| Encargos **recibidos** | si los hay | `docs/design/briefs/_recibidos/` — **propio de este repo** |
| Evidencia con valor propio | si la hay | `docs/design/spikes/` |
| Corpus de repros | si lo hay | `docs/design/reviews/` |

El `<slug>` es `^[a-z0-9-]+$`. **La ruta del ledger es derivable del plan; ningún documento la
cita.** Un spec puede cubrir varios planes; un plan tiene exactamente un ledger.

### §2 — El banner

Línea 1 de todo `.md` en `docs/design/{specs,plans,spikes}/`, literal:
`> **ESTADO: <ESTADO>** — <sufijo libre de una línea>`. Estados: `BORRADOR`, `VIGENTE`,
`COMPLETO`, `SUPERSEDED por `<archivo>``, `EXPLORADO`, `ABANDONADO`.

Un VIGENTE está citado por `docs/design/ROADMAP.md`, `README.md`, `AGENTS.md`, `CAPABILITIES.md`
o `CHANGELOG.md`; **o** por un plan/spec VIGENTE que esa raíz sí cite (transitiva de UN nivel, no
más); **o** tiene ledger vivo. Un VIGENTE con fecha posterior al 2026-09-19 lleva `GO Ottavio` en
el sufijo.

**BORRADOR es legal en `main`** y no exige nada de lo anterior: un arco sembrado y no aprobado
tiene que poder vivir en `main` sin poner el gate en rojo, porque así es exactamente como se
aprueba, leyéndolo. Lo que no puede es comportarse como aprobado: no reparte encargos (`brief`
exige VIGENTE), no se cierra (`arc-close` exige VIGENTE) y no exhibe steps ya completos.

`docs/design/INDEX.md` es **generado**. Los documentos cerrados **no se mueven**.

### §4 — El ledger

`ledger-new PLAN` lo crea, con la primera línea `# SDD ledger — plan: <ruta del plan>`. **Un
ledger cuya primera línea nombre otro plan es de otro plan: no se toca.** Es el mapa de
recuperación: tras una sesión cortada, se confía en el ledger y en `git log` antes que en la
memoria.

Vocabulario greppable, **anclado a principio de línea** (los ejemplos sembrados van indentados a
propósito, para que no matcheen):

    Task N: review <Approved|Approved-con-fix|light <archivos>/<líneas>> (<modelo|coordinador>)
    Task N: complete (<sha7>..<sha7>)
    Task N: skipped — Ruling: <qué> — porqué: <por qué> — costo si está mal: <costo>
    Ruling: <decisión> — GO Ottavio <fecha>
    Merge: autorizado por Ottavio <fecha>

El orden importa: `review` tiene que aparecer **antes** que `complete`. Cada `complete` exige su
`task-N-report.md`. Una task que no se hace se cierra con `skipped` y su ruling, no se deja sin
marca.

**Review light** permitido solo si la task toca ≤3 archivos y ≤80 líneas netas (los cuenta
`review-package`) **y** no toca `src/router.nx` ni `src/cache.nx` — el pool y el encuadre viven
en el primero, el slicing por bytes en el segundo, y son donde este repo se hizo sus tres
cicatrices. Fuera de esos umbrales, reviewer aparte, obligatorio.

### §5 — Encargos

**Los encargos viajan por git, nunca por chat.** El coordinador lo commitea en la rama del arco;
la máquina remota lee el archivo del repo, ejecuta, escribe `task-N-report.md` al lado y pushea.
Un `briefs/<plan-basename>/` sin plan VIGENTE es FAIL; un archivo en `plans/` con `-brief` o
`-fixround` en el nombre es FAIL.

**Agregado de este repo**: `briefs/_recibidos/` es el buzón de entrada. Un encargo que llega de
otro repo **se copia acá** aunque su plan viva allá, y se anota en `ROADMAP.md §Encargos
abiertos`. Está exento de la regla (f) —no tiene plan local— pero no de la (j). Esta carpeta
existe porque su ausencia costó tres días y una reemisión.

### §8 — Scripts y guardas

`scripts/sdd/`, bash, **`set -u` sin `pipefail`**, todos con control positivo en
`scripts/sdd/selftest` (`make sdd-check`). El método no depende de ningún plugin.

| Script | Rol |
|---|---|
| `lib.sh` | banner, rutas, derivación del ledger — el contrato compartido |
| `arc-new` | siembra spec o plan con banner y plantilla |
| `ledger-new` | siembra el ledger con las marcas pendientes |
| `task-brief` | extrae una task del plan (respetando fences) |
| `brief --remote` | el encargo commiteable, con cabecera fija |
| `review-package` | log + diff + `stats: files=N net=M` |
| `index-gen [--check]` | regenera / verifica el INDEX |
| `state-check` | la guarda: 10 reglas etiquetadas `(a)`…`(j)` |
| `arc-close` | el cierre en un comando: valida todo **antes** de escribir |
| `selftest`, `selftest-arc` | control positivo de todo lo anterior |

Guardas: `make docs-health` (= `index-gen --check` + `state-check`) y `make sdd-check`.

### §10 — Repo público (regla propia, no existe en el lenguaje)

**Este repo es público: todo commit se publica al instante.** `arc-close` cosecha el ledger
entero —`progress.md` y todos los `task-N-report.md`— y lo commitea. Un ledger real está lleno
de rutas de `home`, puertos de backends y nombres de unidad de producción.

Por eso la regla (j) de `state-check`, que en el lenguaje miraba solo los encargos, acá cubre
**`docs/design/**` y `docs/archive/sdd/**`**, y `arc-close` la corre **como validación, antes de
la primera escritura**: un cierre que fuera a publicar una ruta de máquina falla con el ledger
intacto, en vez de dejar el dato en la historia de git para siempre. Se permite `~/nyx/…` (el
layout canónico) y `/tmp/<archivo>` suelto.

## Fuera de alcance

- **`PLAN.md`, `PROJECT_STATE.md`, `TASKS.md`, `docs/SESSION_LOG.md`**: no se crean. La narrativa
  de este repo vive en el `CHANGELOG.md`, que ya explica el porqué de cada cambio, y el estado
  operativo vive fuera del repo. En consecuencia `arc-close` **no** valida bitácora ni estado, y
  `state-check (i)` pierde su mitad de «BORRADOR citado como campaña activa»: sin archivo de
  campañas no hay regla que romper, y se documenta en vez de dejar una guarda que no guarda nada.
- **El check de frescura del estado** (check 10 del lenguaje): el archivo vive fuera del árbol y
  grepear fuera de la raíz rompería la hermeticidad del fixture del selftest.
- **`run_docs_health.sh`**: no se porta un runner entero para envolver dos llamadas; `arc-close`
  y el Makefile invocan `index-gen --check` y `state-check` directo.
- **La regla «≤150 líneas por script»**: se descarta explícitamente. En el repo del lenguaje ya
  estaba rota en 4 de 13 archivos y ninguna guarda la verificaba; por la propia regla de oro, era
  una costumbre. Acá se prefiere un `arc-close` de 190 líneas legible a dos de 95 encadenados.
- **El E2E del túnel en el repo del lenguaje**: se pide por report, no se escribe desde acá.

## Riesgos

- **La cosecha publica.** Mitigado por §10, pero la guarda es sintáctica: caza rutas, no secretos
  semánticos. Un ledger que narre una decisión comercial la publica igual. Quien escribe el
  ledger tiene que saber que escribe en público.
- **Un solo arco vivo a la vez.** Nada lo impide técnicamente, pero `brief` exige rama ≠ `main` y
  este repo venía commiteando lineal a `main`; con dos arcos en paralelo y un solo `main`, el
  cierre del segundo arrastra el árbol del primero. Se adopta la convención `arc/<slug>`.
- **Divergencia con el original.** `state-check:root_cites` y `arc-close:cita_raiz` son la misma
  regla escrita dos veces y **divergen a propósito** (la segunda omite `ROADMAP.md`, igual que la
  original omitía `PLAN.md`). Está comentado en ambos lados; si alguien las unifica sin leer el
  comentario, el cierre va a dejar specs en rojo después de escribir.
