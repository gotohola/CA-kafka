                       ┌──────────────────────────────┐
                       │  Root CA  (offline, cfssl)   │
                       │  self-signed rootCA.pem      │
                       │  rootCA-key.pem (guardado)   │
                       └────────────┬─────────────────┘
                                    ▼   ① firma CSR
                       ┌──────────────────────────────┐
                       │  Vault PKI - Intermediate    │
                       │  • Vault genera par de claves │
                       │    (pki_int/intermediate/*)  │
                       │  • int.crt ← firmado por root│
                       │  • int.key queda cifrado en  │
                       │    el storage /vault/data    │
                       │  • expone /v1/pki_int/ca, CRL│
                       └────────────┬─────────────────┘
                                    ▼   ② emite leaf
        ┌────── auto-auth AppRole ──┼───────────────────────────┐
        │                           ▼                           │
┌─────────────────┐    vault.write pki_int/issue/kafka-broker   │
│  Broker (TLS)   │ ───────────────────────────────────────────►│
│  srv1.broker…   │  leaf cert + PK + chain → broker.pem       │
│  vault-agent    │                                            │
│  /vault/token   │◄────────────────────────────────────────────┘
└─────────────────┘

*Los clientes repetirán el mismo flujo contra el rol `kafka-client`.*

---

## Paso a paso con los contenedores

| Stage | Contenedor                    | Qué certificados toca                                        | Resultado persistente                                        |
| ----- | ----------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **1** | `ca-root-generator` (efímero) | • **Genera** pareja root (self-signed)<br>• No firma a nadie | `certs/rootCA.pem`<br>`certs/rootCA-key.pem`                 |
| **2** | `vault-bootstrap` (efímero)   | 1. **Vault init** & unseal (no certs)<br>2. **Gen CSR** intermedia ↠ `int.csr`<br>3. **Firma** con raíz → `int.crt`<br>4. **Carga** `int.crt` a Vault | • Private key de la intermedia alojada/crypted en `/vault/data` (volume)<br>• Rol `kafka-broker` + `kafka-client`<br>• `broker-auth` volume con `role_id` + `secret_id` |
| **2** | `vault` (persistente)         | • **Almacena** CA intermedia, publica `/v1/pki_int/ca` y CRL | Volume `vault-data`                                          |
| **3** | `kafka` (persistente)         | 1. **Vault Agent** usa AppRole → token<br>2. `vault.write pki_int/issue/kafka-broker common_name=srv1.broker.kafka`<br>3. **Recibe**: `private_key`, `certificate`, `issuing_ca` | `/etc/kafka/certs/broker.pem` (leaf + chain)<br>`/etc/kafka/certs/rootCA.pem` (anchor)<br>`/vault/token` (renovable) |

---

## Flujo de validación TLS

1. **Broker ⇄ Cliente** intercambian certificados durante el handshake.
2. Cada parte:
   * Extrae la **cadena** recibida ⇒ Intermedia + Root (incluida).
   * Comprueba que Root = `rootCA.pem` (archivo de confianza).
   * Ejecuta validaciones de CN/SAN → las ACL de Kafka se basarán en el CN.

Si cualquiera de los certificados (leaf o intermedia) se revoca o expira,
Vault generará un nuevo leaf y el **Vault Agent** volverá a renderizar
`broker.pem`; el hook recarga Kafka sin reinicio completo (puedes quitar
la línea de `pkill` o instalar `procps-ng`).

---

## Dónde queda cada clave y cómo se protege

| Elemento                       | Dónde vive                                           | Protegido por                                                |
| ------------------------------ | ---------------------------------------------------- | ------------------------------------------------------------ |
| **Root key**                   | `certs/rootCA-key.pem` (bind mount fuera de Vault)   | Sólo accesible en el host/air-gapped; el runtime no lo monta nunca. |
| **Intermediate key**           | K/V cifrado de Vault (`storage "file"` + master-key) | Se descifra sólo cuando Vault está unsealed.                 |
| **Broker/Cliente private key** | Dentro del *pod* que lo solicitó (`broker.pem`)      | El archivo no sale del contenedor; se regenera al renovar.   |
| **Role ID / Secret ID**        | Volume `broker-auth`                                 | Sólo lectura para el broker; revocable desde Vault.          |
| **Token**                      | `/vault/token` (tmpFS del contenedor)                | Renovable, TTL corto; desaparece al destruir el contenedor.  |

---

### Resumen rápido

1. **Raíz** (cfssl) = *trust anchor*, firma **una** CA intermedia.
2. **VAULT** guarda la clave de la intermedia, publica endpoints y gestiona CRL.
3. **Vault roles** definen qué CN/SAN puede pedir cada tipo de entidad.
4. **AppRole** proporciona credenciales mínimas (`role_id`, `secret_id`).
5. **Vault Agent** en cada broker/cliente intercambia secret-id ↠ token ↠ leaf cert.
6. mTLS completa: cualquier parte verifica hasta la raíz sin dependencia externa.

Ya tienes la cadena completa operativa; sólo faltaría Stage 4 (cliente mTLS) si quieres probar la producción/consumo.