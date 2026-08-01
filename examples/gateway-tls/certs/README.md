# Local test certificates

The example expects one default cert (`example.com`) plus one SNI cert
(`api.example.com`). For local testing, generate self-signed ones (the
`.pem`/`.key` files are gitignored — never commit private keys):

```bash
cd examples/gateway-tls/certs
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
  -keyout example.com.key -out example.com.pem \
  -subj "/CN=example.com" -addext "subjectAltName=DNS:example.com"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
  -keyout api.example.com.key -out api.example.com.pem \
  -subj "/CN=api.example.com" -addext "subjectAltName=DNS:api.example.com"
```

In production, point `proxy.toml` and the `tls_server_add_cert(...)` calls at
your real certificates instead (e.g. `/etc/letsencrypt/live/<domain>/fullchain.pem`
and `privkey.pem`). Full walkthrough: `docs/TUTORIAL.md`.
