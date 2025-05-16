FROM alpine:3.20
RUN apk add --no-cache openssl curl && \
    curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64 -o /usr/bin/cfssl && \
    curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64 -o /usr/bin/cfssljson && \
    chmod +x /usr/bin/cfssl /usr/bin/cfssljson

COPY generate-root-ca.sh /scripts/
COPY root-config.json /scripts/
RUN chmod +x /scripts/generate-root-ca.sh

ENTRYPOINT ["/scripts/generate-root-ca.sh"]
