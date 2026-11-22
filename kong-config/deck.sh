#!/usr/bin/env bash
# Apply kong-config/boutique.yaml to a Konnect control plane with decK.
#   kong-config/deck.sh <control-plane-name> <ping|validate|diff|sync|dump|restore>
#   kong-config/deck.sh dev diff
#
# Control plane names = environment names (dev, staging, prod); values come from envs/<env>.env
#
# Needs the Konnect system-account token (Organization -> System accounts -> deck-ci -> Manage Tokens):
#   kept in AWS Secrets Manager, secret "boutique/konnect-deck-token" (override: KONNECT_TOKEN_SECRET),
#   read with your AWS login. Store/rotate it with:
#     aws secretsmanager create-secret --name boutique/konnect-deck-token --secret-string 'spat_...'   # first time
#     aws secretsmanager put-secret-value --secret-id boutique/konnect-deck-token --secret-string 'spat_...'  # rotate
#   If DECK_KONNECT_TOKEN is already set (e.g. CI secret), that value is used instead.
#   KONNECT_ADDR        optional, default https://in.api.konghq.com (India region).
#                       Use the region your Konnect org is in, e.g. https://us.api.konghq.com
set -euo pipefail

CP="${1:?control plane name in Konnect, e.g. dev}"
ACTION="${2:-diff}"
DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${DECK_KONNECT_TOKEN:-}" ]]; then
  TOKEN_SECRET="${KONNECT_TOKEN_SECRET:-boutique/konnect-deck-token}"
  DECK_KONNECT_TOKEN="$(aws secretsmanager get-secret-value --region "${AWS_REGION:-us-east-1}" \
      --secret-id "$TOKEN_SECRET" --query SecretString --output text 2>/dev/null)" || {
    echo "Konnect token not found in Secrets Manager ($TOKEN_SECRET). Store it with:" >&2
    echo "  aws secretsmanager create-secret --name $TOKEN_SECRET --secret-string 'spat_...'" >&2
    exit 1
  }
  export DECK_KONNECT_TOKEN
fi

# Per-environment values (Redis host ...) for ${{ env "DECK_..." }} in boutique.yaml
ENV_FILE="$DIR/envs/$CP.env"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a
# Partner API keys (key-auth) from Secrets Manager: boutique/<env>/partner-api-keys =
# {"acme": "<key>", "globex": "<key>"} -> DECK_PARTNER_ACME_KEY, DECK_PARTNER_GLOBEX_KEY, ...
# Add a key: scripts/partner-key.sh <env> <name>
if [[ "$ACTION" != "ping" ]]; then
  KEYS_SECRET="boutique/$CP/partner-api-keys"
  if ! KEYS_JSON="$(aws secretsmanager get-secret-value --region "${AWS_REGION:-us-east-1}" \
        --secret-id "$KEYS_SECRET" --query SecretString --output text 2>/dev/null)"; then
    echo "Partner API keys not found in Secrets Manager ($KEYS_SECRET). Create them with:" >&2
    echo "  scripts/partner-key.sh $CP acme && scripts/partner-key.sh $CP globex" >&2
    exit 1
  fi
  while IFS='=' read -r name value; do
    var="DECK_PARTNER_${name}_KEY"
    [[ -n "${!var:-}" ]] || export "$var=$value"     # a value already set (e.g. CI) wins
  done < <(python3 -c 'import json,sys,re
for k,v in json.load(sys.stdin).items(): print(re.sub(r"[^A-Z0-9]","_",k.upper())+"="+v)' <<<"$KEYS_JSON")
  # every DECK_PARTNER_<NAME>_KEY used in boutique.yaml must have a key in the secret
  while read -r var; do
    if [[ -z "${!var:-}" ]]; then
      name="${var#DECK_PARTNER_}"; name="${name%_KEY}"
      echo "No key for partner '${name,,}' in $KEYS_SECRET. Add it with: scripts/partner-key.sh $CP ${name,,}" >&2
      exit 1
    fi
  done < <(grep -oE 'DECK_PARTNER_[A-Z0-9]+_KEY\b' "$DIR/boutique.yaml" | sort -u)
fi

# Partner ACME's JWT public key (PEM) from Secrets Manager: boutique/<env>/partner-acme-jwt-public-key.
# Newlines become "\n" so the key fits in a quoted YAML string in boutique.yaml.
if [[ "$ACTION" != "ping" && -z "${DECK_PARTNER_ACME_JWT_PUBLIC_KEY:-}" ]]; then
  PUB_SECRET="boutique/$CP/partner-acme-jwt-public-key"
  if ! PUB_PEM="$(aws secretsmanager get-secret-value --region "${AWS_REGION:-us-east-1}" \
        --secret-id "$PUB_SECRET" --query SecretString --output text 2>/dev/null)"; then
    echo "Partner JWT public key not found in Secrets Manager ($PUB_SECRET). See the runbook (partner JWT key pair)." >&2
    exit 1
  fi
  DECK_PARTNER_ACME_JWT_PUBLIC_KEY="$(printf '%s\n' "$PUB_PEM" | awk 'NF {printf "%s\\n", $0}')"
  export DECK_PARTNER_ACME_JWT_PUBLIC_KEY
fi

if [[ "$ACTION" != "ping" ]]; then
  for v in DECK_REDIS_HOST DECK_OIDC_ISSUER DECK_PARTNER_ACME_CLIENT_ID; do
    if [[ -z "${!v:-}" || "${!v}" == *"<"* ]]; then
      echo "Set $v in $ENV_FILE (values from: terraform -chdir=terraform-infra/envs/$CP output)" >&2
      exit 1
    fi
  done
fi

CONN=(--konnect-addr "${KONNECT_ADDR:-https://in.api.konghq.com}"
      --konnect-control-plane-name "$CP")

case "$ACTION" in
  ping)     deck gateway ping     "${CONN[@]}" ;;
  validate) deck gateway validate "${CONN[@]}" "$DIR/boutique.yaml" ;;
  diff)     deck gateway diff     "${CONN[@]}" "$DIR/boutique.yaml" ;;
  sync)     deck gateway sync     "${CONN[@]}" "$DIR/boutique.yaml" ;;
  restore)   # put a dump (from "dump") back, e.g. after a failed smoke test
    file="${3:?usage: deck.sh <cp> restore <backup.yaml>}"
    deck gateway sync "${CONN[@]}" "$file" ;;
  dump)
    out="${3:-backup-$CP-$(date +%Y%m%d-%H%M%S).yaml}"
    deck gateway dump "${CONN[@]}" -o "$out" --yes
    echo "Backup written: $out" ;;
  *) echo "Unknown action: $ACTION (ping|validate|diff|sync|dump|restore)" >&2; exit 1 ;;
esac
