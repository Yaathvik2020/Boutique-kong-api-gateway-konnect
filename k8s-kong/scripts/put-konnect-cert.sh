#!/usr/bin/env bash
# Store the Kong data plane certificate for one environment in AWS Secrets Manager.
# External Secrets then creates the Kubernetes Secret kong/kong-cluster-cert in that cluster.
#
# Get the files in Konnect -> API Gateway -> <control plane for this env>
#   -> Data plane nodes -> New data plane node -> Kubernetes -> Generate certificate.
#
#   k8s-kong/scripts/put-konnect-cert.sh <dev|staging|prod> <cert file> <key file>
set -euo pipefail

ENV="${1:?env: dev | staging | prod}"
CERT="${2:?certificate file from Konnect}"
KEY="${3:?private key file from Konnect}"
REGION="${AWS_REGION:-us-east-1}"
SECRET="boutique/${ENV}/konnect-cluster-cert"   # created (empty) by terraform-infra/envs/$ENV

openssl x509 -in "$CERT" -noout -subject -enddate      # fails if it isn't a certificate

payload="$(python3 -c 'import json,sys; print(json.dumps({"crt": open(sys.argv[1]).read(), "key": open(sys.argv[2]).read()}))' "$CERT" "$KEY")"
aws secretsmanager put-secret-value --region "$REGION" --secret-id "$SECRET" --secret-string "$payload" >/dev/null

echo "Stored in $SECRET. The cluster picks it up within 1 hour, or now with:"
echo "  kubectl -n kong annotate externalsecret kong-cluster-cert force-sync=\$(date +%s) --overwrite"
echo "Put the certificate expiry date (above) in your calendar."
