# Task 2 — el túnel en el router

`is_event_stream` (corta en el primer `;` y compara por igualdad, no por prefijo),
`read_upstream_response_mc` con el fd del stream como tercer elemento en todas sus salidas,
`forward_pooled_c`, `sse_tunnel` y `proxy_dispatch_c`. Los nombres viejos quedan como wrappers
con el túnel apagado, y con el flag apagado ni se evalúa el `Content-Type`.

El túnel es de un solo sentido, inline, sin threads ni mutex: `ws_tunnel` necesita dos threads y
un lock sobre el `SSL*` porque es bidireccional, y en SSE el cliente no manda nada después del
GET. La asimetría está comentada donde invita a unificarlas.

Desvío respecto del plan: la rama del túnel iba «antes del `if reusable == 1`», que es DESPUÉS de
leer el cuerpo — con lo cual `read_until_close` ya había bloqueado y el túnel no servía de nada.
Se movió antes del bloque de lectura. Lo cazó el primer caso del test.
