# Task 3 — la suite

8 casos en el camino plano: detección sin leer el cuerpo, relay en orden y sin buffering, cliente
que se va, el pedido siguiente por el mismo pool, no regresión de una respuesta sin longitud que
no es SSE, matching del `Content-Type`, SSE con longitud, y el tope.

«Sin buffering» se mide verificando que la PAUSA del upstream se reproduzca en el cliente: si se
acumulara, los eventos saldrían juntos al final. Medido: primer evento a los 0 ms, separación de
500 ms contra una pausa de 500 ms del upstream.

Dos errores propios corregidos acá, los dos del tipo que el playbook del repo ya documenta: el
thread lector podía arrancar después del túnel y medía su propio retraso de arranque (en una
máquina cargada daba «los dos a los 500 ms», que parecía buffering y no lo era), y el centinela de
«todavía no llegó» era 0, indistinguible de «llegó a los 0 ms».
