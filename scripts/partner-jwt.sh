#!/usr/bin/env bash
# Partner-signed JWT for the Kong "jwt" plugin (route /partner/v3/products).
#
#   scripts/partner-jwt.sh keys  <env>   # once: make partner ACME's RSA key pair,
#                                        # store the PUBLIC key in Secrets Manager
#   scripts/partner-jwt.sh token <env> [seconds]   # sign a test token (default 15 min)
#
# In real life the PARTNER makes the key pair and sends you only the public key; the private key
# never leaves the partner. Here the private key stays in ~/partner-acme-jwt/<env>/ on this
# laptop, for testing only. Kong gets the public key through deck.sh (secret
# boutique/<env>/partner-acme-jwt-public-key).
set -euo pipefail
ACTION="${1:?keys|token}"; ENV="${2:?env, e.g. dev}"
DIR="$HOME/partner-acme-jwt/$ENV"
SECRET="boutique/$ENV/partner-acme-jwt-public-key"
ISS="partner-acme-jwt"          # must equal jwt_secrets.key in kong-config/boutique.yaml

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

case "$ACTION" in
  keys)
    mkdir -p "$DIR" && chmod 700 "$DIR"
    if [[ ! -f "$DIR/private.pem" ]]; then
      openssl genrsa -out "$DIR/private.pem" 2048 2>/dev/null
      chmod 600 "$DIR/private.pem"
    fi
    openssl rsa -in "$DIR/private.pem" -pubout -out "$DIR/public.pem" 2>/dev/null
    if aws secretsmanager describe-secret --secret-id "$SECRET" >/dev/null 2>&1; then
      aws secretsmanager put-secret-value --secret-id "$SECRET" --secret-string "$(cat "$DIR/public.pem")" >/dev/null
    else
      aws secretsmanager create-secret --name "$SECRET" \
        --description "Partner ACME JWT public key (RS256) for Kong jwt plugin" \
        --secret-string "$(cat "$DIR/public.pem")" >/dev/null
    fi
    echo "Private key (keep secret): $DIR/private.pem"
    echo "Public key stored in Secrets Manager: $SECRET"
    echo "Next: kong-config/deck.sh $ENV sync  (or push a kong-config change) so Kong gets the key"
    ;;
  token)
    TTL="${3:-900}"
    [[ -f "$DIR/private.pem" ]] || { echo "No key: run '$0 keys $ENV' first" >&2; exit 1; }
    NOW=$(date +%s)
    H=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
    P=$(printf '{"iss":"%s","sub":"acme-insurance-broker","iat":%s,"exp":%s}' "$ISS" "$NOW" "$((NOW + TTL))" | b64url)
    S=$(printf '%s.%s' "$H" "$P" | openssl dgst -sha256 -sign "$DIR/private.pem" | b64url)
    printf '%s.%s.%s\n' "$H" "$P" "$S"
    ;;
  *) echo "usage: $0 keys|token <env> [seconds]" >&2; exit 1 ;;
esac
