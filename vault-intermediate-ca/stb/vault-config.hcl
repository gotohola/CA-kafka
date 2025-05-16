listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1                 # solo laboratorio
}

storage "file" {
  path = "/vault/data"
}

ui = true
