vault {
  address = "http://vault:8200"
  tls_skip_verify = true
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/role_id"
      secret_id_file_path = "/vault/secret_id"
    }
  }
  sink "file" { config = { path = "/vault/token" } }
}

template {
  destination = "/etc/kafka/certs/broker.pem"
  command     = "pkill -HUP -f kafka.Kafka || true"   # reload on renew
  contents = <<EOF
{{- with secret "pki_int/issue/kafka-broker" "common_name=svr1.broker.kafka" -}}
{{ .Data.private_key }}
{{ .Data.certificate }}
{{ .Data.issuing_ca }}
{{ end -}}
EOF
}
