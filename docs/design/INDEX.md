# docs/design/ — índice

> Generado por `scripts/sdd/index-gen` desde el banner (línea 1) de cada
> archivo de `docs/design/{plans,specs,spikes}/`, más una fila por carpeta de
> `reviews/` y de `briefs/` (y una por `.md` suelto de `reviews/`). La guarda
> `scripts/sdd/index-gen --check`, dentro de `make docs-health`, falla si este
> archivo difiere de lo que genera el script. **No editar la tabla a mano** —
> correr `index-gen` tras cambiar un banner. La sección de más abajo,
> `## Notas de clasificación`, sí es manual.

## Leyenda de estado

- **BORRADOR** — sembrado por `arc-new` sin `--go` y todavía sin aprobar (sufijo
  `GO pendiente`). Vive en `main` a la espera de que Ottavio lo lea: no es un arco
  activo ni trabajo en curso.
- **VIGENTE** — el arco lo usa hoy: diseño de referencia activo, trabajo en curso,
  o documento que sigue guiando decisiones pendientes.
- **COMPLETO** — arco cerrado/mergeado; el documento queda como historia. Es el
  default cuando nada vivo lo cita.
- **SUPERSEDED por `<archivo>`** — reemplazado por una revisión posterior; banner
  de advertencia en la línea 1 del propio archivo.
- **EXPLORADO — sin decisión** — estudio de feasibility sin decisión de Ottavio
  tomada todavía.
- **ABANDONADO** — se decidió no hacerlo (`arc-close --abandon`); el motivo
  queda en el sufijo del banner.

«Referenciado por» = grep del nombre de archivo en `README.md`, `AGENTS.md`,
`CAPABILITIES.md`, `CHANGELOG.md`, `docs/design/ROADMAP.md` y `docs/*.md`.
`—` = sin citas vivas encontradas (no implica que el documento sea irrelevante,
solo que ninguna doc raíz lo apunta hoy).

**Los documentos cerrados no se mueven**: el banner COMPLETO más este índice son
el archivado.

## Tabla completa

<!-- index:begin -->
| Archivo | Fecha | Tipo | Estado | Nota | Referenciado por |
|---|---|---|---|---|---|
| `docs/design/briefs/_recibidos` | — | briefs | — | — | `AGENTS.md`, `docs/design/ROADMAP.md` |
| `docs/design/specs/2026-09-20-sdd-proxy-design.md` | 2026-09-20 | spec | VIGENTE | GO Ottavio 2026-09-20 | `AGENTS.md`, `docs/design/ROADMAP.md` |
<!-- index:end -->

## Notas de clasificación

- `briefs/_recibidos/` es el **buzón**: encargos que llegaron de OTRO repo y cuyo
  plan vive allá. No tienen plan local y por eso están exentos de la regla (f) de
  `state-check`; lo que sí les aplica es la (j), porque se publican igual.
- La cosecha de los arcos cerrados no está acá sino en `docs/archive/sdd/<arco>/`:
  el ledger de ejecución es efímero y `arc-close` lo cosecha al cerrar.
