#!/bin/sh
set -eu

TEMPLATE="/usr/share/nginx/html/runtime-config.template.json"
OUTPUT="/usr/share/nginx/html/runtime-config.json"

: "${NEXTCLOUD_BASE_URL:=nc-api}"
: "${NEXTCLOUD_SHARE_TOKEN:=jbXHPXxAxzj8ATB}"
: "${NEXTCLOUD_METADATA_PATH:=MetaData}"

if [ -f "$TEMPLATE" ]; then
  export NEXTCLOUD_BASE_URL NEXTCLOUD_SHARE_TOKEN NEXTCLOUD_METADATA_PATH
  envsubst '${NEXTCLOUD_BASE_URL} ${NEXTCLOUD_SHARE_TOKEN} ${NEXTCLOUD_METADATA_PATH}' < "$TEMPLATE" > "$OUTPUT"
fi
