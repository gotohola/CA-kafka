auto_auth {
  method "approle" {
    config = {
      role_id_file_path = "/vault/role_id"
      secret_id_file_path = "/vault/secret_id"
    }
  }
  sink "file" { config = { path = "/vault/token" } }
}
template {
  destination = "/etc/kafka/certs/broker.pem"
  contents = <<EOF
{{ with secret "pki_int/issue/kafka-broker" "common_name=broker1.kafka" }}
{{ .Data.certificate }}{{ end }}
EOF
}
