# Task 4 — consumidores y release

Los dos ejemplos pasan a `proxy_dispatch_c` y tratan `""` como «ya no queda nada que escribir».
CHANGELOG de v0.4.4 y versión en `nyx.toml`.

Hallazgo: `nyx build` estaba ROTO en `main` desde que el toolchain llegó a 0.32.4, que empezó a
exigir `pub` para cruzar el límite de módulo; ni el binario de referencia ni el ejemplo TLS
compilaban, y los dos están en CI. Verificado compilando el HEAD anterior en un worktree limpio,
para no atribuirse un problema ajeno. Arreglado de paso.
