#!/bin/sh
set -e

#-----------------------------
# CONFIG BÁSICA
#-----------------------------
export VAULT_ADDR=${VAULT_ADDR:-http://vault:8200}


DATA_DIR="/vault/data"
echo "[*] Verificando permisos de $DATA_DIR ..."
touch $DATA_DIR/.permcheck 2>/dev/null || {
  echo "[!] Sin permiso de escritura; corrigiendo owner a UID 100..."
  chown -R 100:100 $DATA_DIR
}
rm -f $DATA_DIR/.permcheck || true


echo "[*] Esperando a que Vault responda en $VAULT_ADDR ..."
until curl -s $VAULT_ADDR/v1/sys/health >/dev/null 2>&1; do sleep 1; done

#-----------------------------
# ¿YA INICIALIZADO?
#-----------------------------
if curl -s $VAULT_ADDR/v1/sys/init | jq -e '.initialized' | grep true >/dev/null; then
  echo "[+] Vault ya inicializado. No hay nada que hacer."
  exit 0
fi

#-----------------------------
# INIT + UNSEAL
#-----------------------------
echo "[*] Inicializando Vault ..."
INIT_JSON=$(vault operator init -format=json -key-shares=1 -key-threshold=1)
UNSEAL_KEY=$(echo "$INIT_JSON" | jq -r '.unseal_keys_b64[0]')
ROOT_TOKEN=$(echo  "$INIT_JSON" | jq -r '.root_token')

vault operator unseal "$UNSEAL_KEY"
export VAULT_TOKEN="$ROOT_TOKEN"

#-----------------------------
# PKI INTERMEDIA
#-----------------------------
echo "[*] Habilitando motor PKI en /pki_int ..."
vault secrets enable -path=pki_int pki

echo "[*] Generando CSR ..."
vault write -field=csr pki_int/intermediate/generate/internal \
      common_name="SKCA Intermediate" ttl=43800h > /tmp/int.csr

echo "[*] Firmando CSR con la raíz ..."
openssl x509 -req -in /tmp/int.csr \
  -CA /certs/rootCA.pem -CAkey /certs/rootCA-key.pem \
  -CAcreateserial -out /tmp/int.crt -days 1825 -sha256 \
  -extfile /etc/ssl/openssl.cnf -extensions v3_ca

echo "[*] Entregando certificado a Vault ..."
vault write pki_int/intermediate/set-signed certificate=@/tmp/int.crt

echo "[*] Publicando URLs de emisión y CRL ..."
vault write pki_int/config/urls \
      issuing_certificates="http://vault:8200/v1/pki_int/ca" \
      crl_distribution_points="http://vault:8200/v1/pki_int/crl"

echo "[*] Creando roles ..."
vault write pki_int/roles/kafka-broker \
      allowed_domains="broker.kafka" allow_subdomains=true max_ttl=720h
vault write pki_int/roles/kafka-client \
      allowed_domains="client.kafka" allow_subdomains=true client_flag=true max_ttl=168h

echo "[*] Creando policy y AppRole para brokers ..."
echo 'path "pki_int/issue/kafka-broker" { capabilities = ["update"] }' \
  | vault policy write kafka-broker -

echo "[*] Habilitando método de autenticación AppRole ..."
vault auth enable approle

vault write auth/approle/role/kafka-broker-role \
     policies="kafka-broker" \
     secret_id_ttl=0 token_ttl=0 token_max_ttl=0

echo "[*] Emitiendo Secret-ID ..."
SECRET_ID=$(vault write -force -field=secret_id \
             auth/approle/role/kafka-broker-role/secret-id)
ROLE_ID=$(vault read  -field=role_id  \
             auth/approle/role/kafka-broker-role/role-id)

mkdir -p /vault                       # la MISMA ruta que usa el broker
echo "$ROLE_ID"   > /vault/role_id
echo "$SECRET_ID" > /vault/secret_id
chmod 600 /vault/role_id /vault/secret_id


# --- CLIENT PKI ROLE, POLICY & APPROLE -------------------------------------
echo "[*] Creando policy y AppRole para clientes ..."
cat <<'EOF' | vault policy write kafka-client -
path "pki_int/issue/kafka-client" {
  capabilities = ["update"]
}
EOF

vault write auth/approle/role/kafka-client-role \
     policies="kafka-client" \
     secret_id_ttl=0 token_ttl=0 token_max_ttl=0

CLIENT_ROLE_ID=$(vault read -field=role_id  auth/approle/role/kafka-client-role/role-id)
CLIENT_SECRET_ID=$(vault write -force -field=secret_id \
                    auth/approle/role/kafka-client-role/secret-id)

mkdir -p /vault/client
echo "$CLIENT_ROLE_ID"   > /vault/client/role_id
echo "$CLIENT_SECRET_ID" > /vault/client/secret_id
chmod 600 /vault/client/*
echo "[+] AppRole 'kafka-client-role' creado."

echo "[+] Bootstrap completado. Vault listo para emitir certificados."
