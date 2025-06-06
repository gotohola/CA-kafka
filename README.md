# Demostración Kafka mTLS + Vault — README

Laboratorio de extremo a extremo que muestra cómo emitir certificados TLS desde HashiCorp Vault
(CA intermedia), usarlos para asegurar un broker Kafka 3.7.0 y un cliente solo por línea de comandos,
e intercambiar mensajes mediante SSL/TLS dentro de Docker.

---

## 1. Estructura del repositorio

.
├── ca-root-generator/ # Imagen de una sola ejecución que crea rootCA.{key,pem}
├── vault-intermediate-ca/
│ ├── stb/ # Imagen del servidor Vault "estable"
│ └── efi/ # Imagen "efímera" de arranque (init + configuración PKI)
├── kafka-broker-mtls/ # Imagen del broker (base Strimzi + vault-agent)
├── kafka-client-mtls/ # Imagen del cliente (Alpine + CLI de Kafka + vault-agent)
├── stage-compose/ # 4 archivos compose para levantar el laboratorio en etapas
│ ├── 01_root.yml # ① crea la CA raíz
│ ├── 02_intermediate.yml # ② inicia Vault + configura PKI intermedia
│ ├── 03_broker.yml # ③ inicia el broker de Kafka (obtiene broker.pem)
│ └── 04_client.yml # ④ inicia el cliente (obtiene client.pem)
└── README.md # estás aquí


---

## 2. Qué sucede internamente

| Paso | Contenedor | Función |
|------|------------|---------|
| 1 | ca-root-generator | Genera una CA raíz offline (rootCA.pem, rootCA-key.pem). Los archivos se colocan en el volumen `./certs/`. |
| 2-a | vault (`vault-intermediate-ca/stb`) | Servidor Vault simple (TLS deshabilitado para simplicidad). |
| 2-b | vault-bootstrap (`vault-intermediate-ca/efi`) | • Inicializa y desbloquea Vault. <br> • Crea la CA intermedia (`pki_int`) firmada por la raíz. <br> • Define dos roles: <br> - `kafka-broker` → certificados *.broker.kafka (válidos 30 días) <br> - `kafka-client` → certificados *.client.kafka (válidos 7 días) <br> • Crea dos AppRoles y guarda sus `role_id` / `secret_id` en el volumen `broker-auth`. |
| 3 | kafka-broker | • Ejecuta `vault-agent`, que se autentica vía AppRole y escribe `broker.pem` (clave + cert + cadena) en `/etc/kafka/certs`. <br> • Genera `server.properties` (almacenes en formato PEM) e inicia un broker KRaft de un solo nodo anunciando `SSL://srv1.broker.kafka:9093`. |
| 4 | kafka-client | • `vault-agent` escribe `client.pem`. <br> • El entrypoint extrae: `client.crt`, `client.key.pk8`, `ca-chain.pem`. <br> • Crea `client.properties` para la CLI. <br> • Se deja una shell interactiva abierta para pruebas manuales. |

El alias DNS interno `srv1.broker.kafka` se añade vía `extra_hosts` para que el hostname del certificado del broker coincida con lo que el cliente espera.

---

## 3. Requisitos previos

- Docker 20.10+ / Podman 4+
- Docker Compose v2
- ≈ 2 GB de espacio libre en disco (imagen de Kafka + logs)

---

## 4. Inicio rápido — laboratorio completo

```bash
# 0) Clonar el repositorio
git clone https://github.com/<tu_usuario>/kafka-vault-mtls.git
cd kafka-vault-mtls

# 1) Construir/crear la CA raíz (una sola vez, toma pocos segundos)
docker compose -f stage-compose/01_root.yml up --build

# 2) Iniciar Vault + configurar la CA intermedia
docker compose -f stage-compose/02_intermediate.yml up --build -d
# Espera ~10 s hasta que los logs muestren “Bootstrap completado”

# 3) Iniciar el broker Kafka (obtiene su certificado desde Vault)
docker compose -f stage-compose/03_broker.yml up --build -d
# El broker estará listo cuando pase el health-check

# 4) Iniciar el cliente
docker compose -f stage-compose/04_client.yml run --build --rm kafka-client
bash```
Llegarás a /opt/kafka/bin dentro del contenedor del cliente.

```

## 5. Prueba de ida y vuelta

```bash
#Crear offset topic#
kafka-topics.sh --bootstrap-server srv1.broker.kafka:9093 \
  --command-config /client/client.properties \
  --create --topic __consumer_offsets \
  --replication-factor 1 \
  --partitions 1 \
  --config cleanup.policy=compact

#Crear un tópico
./kafka-topics.sh --bootstrap-server srv1.broker.kafka:9093 \
  --command-config /client/client.properties \
  --create --if-not-exists --topic demo --replication-factor 1 --partitions 1

#Producir un mensaje
printf 'hola mtls\n' | ./kafka-console-producer.sh \
  --bootstrap-server srv1.broker.kafka:9093 \
  --producer.config /client/client.properties \
  --topic demo --request-required-acks all

#Consumir el mensaje
kafka-console-consumer.sh \
  --bootstrap-server srv1.broker.kafka:9093 \
  --consumer.config /client/client.properties \
  --topic mi-topic \
  --partition 0 \
  --offset 0 \
  --property print.timestamp=true

Deberías ver hola mtls impreso en consola — lo que confirma que el handshake TLS,
la autenticación mediante certificado y el flujo de mensajes funcionan correctamente.
```

## 6. Limpieza

```bash
docker compose -f stage-compose/04_client.yml down
docker compose -f stage-compose/03_broker.yml down -v
docker compose -f stage-compose/02_intermediate.yml down -v
docker compose -f stage-compose/01_root.yml down -v
```

El flag -v elimina volúmenes nombrados como broker-auth, kafka-data, vault-data.

## 7. Despliegue de un cliente Kafka en una máquina externa

> **Objetivo:** levantar un contenedor `kafka-client` en una VM diferente a la que aloja Vault y el broker, autenticándolo en Vault mediante AppRole para obtener certificados mTLS y comunicarse con el broker.

### 7.1. Requisitos de red y software

- La VM externa (`VM‑B`) debe llegar por red a:
  - Vault → `1.1.1.1:8200`
  - Broker → `1.1.1.1:9094`  (hay que añadir el mapeo de puertos en el yaml del stage 03)
- Docker 20.10+ y Docker Compose v2 instalados en `VM‑B`.

### 7.2. Copiar archivos a la VM externa

Es necesario copiar en la maquina cliente tanto el role_id, como el secret_id generados por la CA intermedia asi como el rootCA.pem
```bash
# Aqui se encuentran role_id y secret_id del cliente en la maquina con la CA intermedia
docker run --rm -v stage-compose_broker-auth:/data alpine ls -l /data/client 
```

Movemos los archivos hacia el cliente
```bash
# Copiar con scp (ajusta usuario y ruta)
scp role_id secret_id user@VM-B:/home/user/CA-kafka/secrets/
scp certs/rootCA.pem  user@VM-B:/home/user/CA-kafka/certs/
```

Y en el directorio del cliente montamos una estructura tal que asi

CA-kafka/
├── secrets/
│   ├── role_id      # Role‑ID
│   └── secret_id    # Secret‑ID (chmod 600)
└── certs/
    └── rootCA.pem   # CA raíz

### 7.4. Resolver el hostname del broker

Añade en `/etc/hosts` de `VM‑B`:

```
1.1.1.1   srv1.broker.kafka
```

### 7.5. Ajustar `vault-agent-client.hcl`

```
vault {
  address = "http://10.10.12.159:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/client/role_id"
      secret_id_file_path = "/vault/client/secret_id"
    }
  }
  sink "file" { config = { path = "/vault/token" } }
}

template {
  destination = "/output/client.pem"
  contents = <<EOF
{{- with secret "pki_int/issue/kafka-client" "common_name=$(hostname).client.kafka" -}}
{{ .Data.private_key }}
{{ .Data.certificate }}
{{ .Data.issuing_ca }}
{{ end -}}
EOF
}
```

### 7.6. Ajustar `stage-compose/04_client.yml`

```yaml
services:
  kafka-client:
    build: ../kafka-client-mtls
    container_name: kafka-client
    volumes:
      - ../secrets:/vault/client   # role_id y secret_id
      - ../certs:/certs            # rootCA.pem
      - ./certs:/output            # client.pem generado
    networks:
      - internal-net
    command: ["bash"]

networks:
  internal-net:
    driver: bridge
```

### 7.7. Arrancar y verificar

```bash
# Construir y lanzar el cliente
docker compose -f stage-compose/04_client.yml up --build
# Espera el log: "✅ client.pem generado"

# Listar tópicos para validar la conexión
docker exec -it kafka-client \
  kafka-topics.sh --bootstrap-server srv1.broker.kafka:9093 \
  --command-config /client/client.properties --list
```

Si la lista aparece sin errores, la autenticación mTLS y la resolución DNS están funcionando.