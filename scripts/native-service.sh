#!/usr/bin/env bash
set -euo pipefail
set -a
source /var/www/everframe/shared/.env
set +a
cd /var/www/everframe/current/website
exec /usr/bin/node server.mjs
