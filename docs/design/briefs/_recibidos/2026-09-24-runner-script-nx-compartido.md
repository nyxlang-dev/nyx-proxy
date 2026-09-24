# Encargo recibido — el runner de tests pisa un scratch compartido

> **Origen**: repo del lenguaje, sesión lang-c1. **Recibido**: 2026-09-24, por mensaje directo
> (se copia acá para que exista). **Estado**: abierto, sin arco.
>
> Está en `_recibidos/` y exento de la regla (f) de `state-check`.

---

`scripts/run_unit_tests.sh` escribe en `$NYX_HOME/script.nx`. Es un scratch compartido, y con
dos corridas a la vez se pisan: es la misma carrera que el lenguaje arregló en `nyx test` el
2026-09-20. Conviene migrarlo a `nyx test` o a un `mktemp` propio.

Contexto de este lado: AGENTS.md §Tests ya documenta el síntoma (una corrida del RED del túnel
SSE ejecutó el binario de otro test) y el rodeo manual de un `NYX_HOME` aislado. Este encargo es
sacar el rodeo manual: que el runner no dependa de él.
