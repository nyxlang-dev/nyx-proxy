# Task 5 — producción

Gateway privado: vendor 0.4.3 → 0.4.4, los dos workers a `proxy_dispatch_c`, y un tope de 128
túneles (la mitad de sus 256 workers, para que el tráfico normal tenga workers garantizados).
Desplegado con su script de deploy, que verifica los 8 dominios por SNI tras el restart.

Verificación E2E contra el binario, en puertos de prueba:
- HTTP plano: tres eventos separados por 1 s llegan a 0.00s, 1.00s y 2.00s, y el cierre a 3.00s.
- TLS: un cliente que corta en seco a mitad del stream deja el proceso vivo y atendiendo.

HALLAZGO GRAVE (del runtime, no del proxy): sin `SIG_IGN` global para SIGPIPE y con OpenSSL
escribiendo por `write()` crudo, un `tls_write_conn` contra un peer cerrado mata el proceso
entero. En el camino normal la ventana es de milisegundos; en un túnel dura lo que dure el
stream. Mitigado de este lado e informado al core en el report del encargo.

No hay ningún upstream SSE en producción todavía, así que la verificación en vivo se hizo con
upstreams de prueba contra el binario real, no con tráfico real.
