#!/bin/sh
set -e
mkdir -p /out
cfssl genkey -initca /scripts/root-config.json | cfssljson -bare /out/rootCA
echo "✅ CA raíz generada en /out/rootCA.pem y /out/rootCA-key.pem"
