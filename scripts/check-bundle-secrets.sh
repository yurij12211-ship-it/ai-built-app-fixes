#!/usr/bin/env bash
# check-bundle-secrets.sh
# Scans a production build (default: ./dist) for secrets that must never reach the browser.
# Usage:  bash scripts/check-bundle-secrets.sh [build-dir]
# Exit code 0 = clean, 1 = something found, 2 = usage error.
#
# The Supabase anon key and project URL are SUPPOSED to be in the bundle; they are not flagged.
# What is flagged: Stripe secret/restricted keys and webhook secrets, Supabase service-role keys,
# OpenAI/Anthropic/Google/AWS keys, private key blocks, and .env leftovers.

set -u
DIR="${1:-dist}"

if [ ! -d "$DIR" ]; then
  echo "Build directory '$DIR' not found. Run your build first (npm run build) or pass the path." >&2
  exit 2
fi

# pattern|label
PATTERNS=$(cat <<'EOF'
sk_live_[0-9a-zA-Z]{10,}|Stripe live secret key
sk_test_[0-9a-zA-Z]{10,}|Stripe test secret key
rk_live_[0-9a-zA-Z]{10,}|Stripe live restricted key
rk_test_[0-9a-zA-Z]{10,}|Stripe test restricted key
whsec_[0-9a-zA-Z]{10,}|Stripe webhook signing secret
SUPABASE_SERVICE_ROLE|Supabase service-role variable name
"role":"service_role"|Supabase service-role JWT payload (decoded)
InJvbGUiOiJzZXJ2aWNlX3JvbGUi|Supabase service-role JWT payload (base64)
sk-[A-Za-z0-9]{20,}|OpenAI-style secret key
sk-ant-[A-Za-z0-9_-]{20,}|Anthropic API key
AIza[0-9A-Za-z_-]{30,}|Google API key
AKIA[0-9A-Z]{16}|AWS access key id
ghp_[0-9A-Za-z]{30,}|GitHub personal access token
xox[baprs]-[0-9A-Za-z-]{10,}|Slack token
-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|Private key block
EOF
)

FOUND=0
while IFS='|' read -r pattern label; do
  [ -z "$pattern" ] && continue
  matches=$(grep -rEl --include='*.js' --include='*.mjs' --include='*.html' --include='*.css' --include='*.map' --include='*.json' -- "$pattern" "$DIR" 2>/dev/null)
  if [ -n "$matches" ]; then
    FOUND=1
    echo "FOUND: $label"
    echo "$matches" | sed 's/^/    /'
    # show a redacted sample so you can locate it without printing the whole secret
    grep -rEoh -- "$pattern" "$DIR" 2>/dev/null | head -n 3 | sed -E 's/^(.{12}).*$/    sample: \1…/'
  fi
done <<< "$PATTERNS"

# .env files should never be inside the build output
envfiles=$(find "$DIR" -name '.env*' 2>/dev/null)
if [ -n "$envfiles" ]; then
  FOUND=1
  echo "FOUND: .env file inside build output"
  echo "$envfiles" | sed 's/^/    /'
fi

if [ "$FOUND" -eq 0 ]; then
  echo "Clean: no server-side secrets found in '$DIR'."
  exit 0
else
  echo
  echo "Remove these from the front-end. Server secrets belong in edge-function secrets or server env vars."
  echo "If a Stripe or service-role key was ever deployed, ROTATE it in the provider's dashboard; deleting it from the code is not enough."
  exit 1
fi
