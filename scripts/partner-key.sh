#!/usr/bin/env bash
# Add (or rotate) a partner's API key in Secrets Manager boutique/<env>/partner-api-keys.
#   scripts/partner-key.sh <env> <partner>            # add a key if the partner has none
#   scripts/partner-key.sh <env> <partner> --rotate   # replace the partner's key
#   scripts/partner-key.sh <env> <partner> --show     # print the key (to send to the partner)
# The secret is one JSON object {"acme": "<key>", "globex": "<key>"}; deck.sh reads it on every sync.
# After adding/rotating: re-run the kong-config workflow (or push) so Kong gets the new key.
set -euo pipefail
ENV="${1:?env (dev|staging|prod)}"
NAME="${2:?partner name, e.g. globex}"
MODE="${3:-}"
REGION="${AWS_REGION:-us-east-1}"
SECRET="boutique/$ENV/partner-api-keys"
[[ "$NAME" =~ ^[a-z0-9-]+$ ]] || { echo "partner name: lowercase letters, digits, '-'" >&2; exit 1; }

if CUR="$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET" \
          --query SecretString --output text 2>/dev/null)"; then EXISTS=1; else CUR='{}'; EXISTS=0; fi

if [[ "$MODE" == "--show" ]]; then
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d[sys.argv[2]])' "$CUR" "$NAME"
  exit 0
fi

NEW="$(python3 - "$CUR" "$NAME" "$MODE" <<'PY'
import json, secrets, sys
d = json.loads(sys.argv[1]); name, mode = sys.argv[2], sys.argv[3]
if name in d and mode != "--rotate":
    sys.exit(f"partner '{name}' already has a key (use --rotate to replace it)")
d[name] = secrets.token_hex(24)
print(json.dumps(d))
PY
)"
if [[ "$EXISTS" == 1 ]]; then
  aws secretsmanager put-secret-value --region "$REGION" --secret-id "$SECRET" --secret-string "$NEW" >/dev/null
else
  aws secretsmanager create-secret --region "$REGION" --name "$SECRET" --secret-string "$NEW" >/dev/null
fi
echo "Key for '$NAME' stored in $SECRET. Next: re-run kong-config (or push) so Kong gets it."
echo "Show it: scripts/partner-key.sh $ENV $NAME --show"
