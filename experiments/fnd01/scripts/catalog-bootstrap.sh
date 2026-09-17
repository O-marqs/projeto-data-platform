#!/bin/sh
set -eu

apk add --no-cache jq >/dev/null

base_url="${POLARIS_INTERNAL_ENDPOINT}"
management_base="${base_url%/catalog}/management"
token_response=$(curl --fail-with-body -sS -X POST "${base_url}/v1/oauth/tokens" \
  --user "${CLIENT_ID}:${CLIENT_SECRET}" \
  -H "Polaris-Realm: ${POLARIS_REALM}" \
  -d grant_type=client_credentials \
  -d scope=PRINCIPAL_ROLE:ALL)
token=$(printf '%s' "$token_response" | jq -er '.access_token')

catalog_url="${management_base}/v1/catalogs/${POLARIS_CATALOG}"
if curl --fail -sS -o /dev/null \
  -H "Authorization: Bearer ${token}" \
  -H "Polaris-Realm: ${POLARIS_REALM}" \
  "$catalog_url"; then
  echo "Polaris catalog already exists"
  exit 0
fi

payload=$(jq -n \
  --arg catalog "$POLARIS_CATALOG" \
  --arg location "s3://${RUSTFS_BUCKET}" \
  --arg endpoint "$RUSTFS_CLIENT_ENDPOINT" \
  --arg endpoint_internal "$RUSTFS_INTERNAL_ENDPOINT" \
  --arg region "$RUSTFS_REGION" \
  '{catalog: {name: $catalog, type: "INTERNAL", readOnly: false,
    properties: {"default-base-location": $location},
    storageConfigInfo: {storageType: "S3", allowedLocations: [$location],
      endpoint: $endpoint, endpointInternal: $endpoint_internal,
      pathStyleAccess: true, stsUnavailable: true, region: $region}}}')

curl --fail-with-body -sS -X POST "${management_base}/v1/catalogs" \
  -H "Authorization: Bearer ${token}" \
  -H "Polaris-Realm: ${POLARIS_REALM}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "$payload" >/dev/null

echo "Polaris catalog created"
