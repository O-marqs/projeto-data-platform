#!/bin/sh
set -eu

base_url="${POLARIS_INTERNAL_ENDPOINT}"
management_base="${base_url%/catalog}/management"
token=""
for attempt in $(seq 1 30); do
  token_response=$(curl --fail -sS -X POST "${base_url}/v1/oauth/tokens" \
    --user "${CLIENT_ID}:${CLIENT_SECRET}" \
    -H "Polaris-Realm: ${POLARIS_REALM}" \
    -d grant_type=client_credentials \
    -d scope=PRINCIPAL_ROLE:ALL 2>/dev/null || true)
  token=$(printf '%s' "$token_response" | tr -d '\r\n' | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -n "$token" ]; then
    break
  fi
  sleep 2
done
if [ -z "$token" ]; then
  echo "Polaris token response did not contain access_token" >&2
  exit 1
fi

catalog_url="${management_base}/v1/catalogs/${POLARIS_CATALOG}"
payload=$(printf '{"catalog":{"name":"%s","type":"INTERNAL","readOnly":false,"properties":{"default-base-location":"s3://%s"},"storageConfigInfo":{"storageType":"S3","allowedLocations":["s3://%s"],"endpoint":"%s","endpointInternal":"%s","pathStyleAccess":true,"stsUnavailable":true,"region":"%s"}}}' \
  "$POLARIS_CATALOG" "$RUSTFS_BUCKET" "$RUSTFS_BUCKET" "$RUSTFS_CLIENT_ENDPOINT" "$RUSTFS_INTERNAL_ENDPOINT" "$RUSTFS_REGION")

for attempt in $(seq 1 30); do
  if curl --fail -sS -o /dev/null \
    -H "Authorization: Bearer ${token}" \
    -H "Polaris-Realm: ${POLARIS_REALM}" \
    "$catalog_url" 2>/dev/null; then
    echo "Polaris catalog already exists"
    exit 0
  fi

  if curl --fail -sS -X POST "${management_base}/v1/catalogs" \
    -H "Authorization: Bearer ${token}" \
    -H "Polaris-Realm: ${POLARIS_REALM}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null 2>/dev/null; then
    echo "Polaris catalog created"
    exit 0
  fi
  sleep 2
done

echo "Polaris catalog was not ready after retries" >&2
exit 1
