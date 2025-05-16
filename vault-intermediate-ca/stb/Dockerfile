# Imagen persistente de Vault + OpenSSL
FROM hashicorp/vault:1.17

RUN apk add --no-cache openssl

COPY vault-config.hcl /etc/vault/
