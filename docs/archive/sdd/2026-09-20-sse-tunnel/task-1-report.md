# Task 1 — RED

Suite `tests/test_proxy_sse_tunnel.nx` y su entrada en la lista explícita del runner.

Evidencia capturada contra el router SIN túnel, de dos formas:
- en miniatura (plazo de inactividad en 1 s, upstream que late cada 200 ms y cierra a los ~3 s):
  `ASSERTION FAILED: la respuesta SSE vuelve mientras el stream sigue abierto`, con
  `tiempo hasta la respuesta: 3016 ms` — o sea, volvía justo al cerrar el upstream.
- con los valores de producción (plazo de 30 s, upstream que no cierra nunca): `forward_pooled`
  no retorna jamás; la corrida muere por el `timeout 60` del runner sin imprimir una línea
  (rc=124). Es lo que veía el navegador. No se deja en la suite: quemaría 60 s por corrida.

Línea base antes de tocar nada: 7 suites, 41 casos.
