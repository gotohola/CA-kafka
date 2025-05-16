# Job efímero que inicializa y configura Vault
FROM alpine:3.20

RUN apk add --no-cache curl jq openssl

# Instala el CLI de Vault de forma ligera
ENV VAULT_VERSION=1.17.6
RUN curl -sL https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip \
    -o vault.zip \
 && unzip vault.zip -d /usr/local/bin \
 && chmod +x /usr/local/bin/vault \
 && rm vault.zip

COPY bootstrap.sh /bootstrap.sh
RUN chmod +x /bootstrap.sh

ENTRYPOINT ["/bootstrap.sh"]
