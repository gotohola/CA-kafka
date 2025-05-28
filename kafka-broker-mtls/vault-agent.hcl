vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/role_id"
      secret_id_file_path = "/vault/secret_id"
    }
  }
  sink "file" {           # Guarda el token por si quieres examinarlo
    config = { path = "/vault/token" }
  }
}

template {
  destination = "/output/broker.pem"
  # nada que recargar; con éxito basta generar el archivo
  command     = "/bin/sh -c 'echo PEM listo $(date)'"
  contents = <<EOF
{{- with secret "pki_int/issue/kafka-broker" "common_name=srv1.broker.kafka" -}}
{{ .Data.private_key }}
{{ .Data.certificate }}
{{ .Data.issuing_ca }}
{{ end -}}
EOF
}
