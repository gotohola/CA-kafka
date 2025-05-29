vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/client/role_id"
      secret_id_file_path = "/vault/client/secret_id"
    }
  }
  sink "file" {
    config = { path = "/vault/token" }
  }
}

template {
  destination = "/output/client.pem"
  command     = "/bin/sh -c 'echo PEM listo $(date)'"
  contents = <<EOF
{{- with secret "pki_int/issue/kafka-client" "common_name=srv1.client.kafka" -}}
{{ .Data.private_key }}
{{ .Data.certificate }}
{{ .Data.issuing_ca }}
{{ end -}}
EOF
}

