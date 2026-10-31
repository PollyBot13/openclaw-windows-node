#!/bin/sh
set -eu
root="$1"
mode="$2"
helper_root="$3"
node=/home/openclaw/.openclaw/tools/node/bin/node
entry=/home/openclaw/.openclaw/tools/node-v24.19.0/lib/node_modules/openclaw/dist/entry.js
if [ "$mode" = backend ]; then
  printf '%s\n' "$$" > "$root/backend.pid"
  exec /usr/bin/env -i PATH=/usr/bin:/bin HOME="$root/home" TMPDIR="$root/tmp" LANG=C.UTF-8 "$node" "$helper_root/synthesis-backend.mjs" "$root/backend-private.json"
fi
if [ "$mode" = gateway ]; then
  printf '%s\n' "$$" > "$root/gateway.pid"
  exec /usr/bin/env -i PATH=/usr/bin:/bin HOME="$root/home" TMPDIR="$root/tmp" LANG=C.UTF-8 OPENCLAW_HOME="$root/home" OPENCLAW_STATE_DIR="$root/state" OPENCLAW_CONFIG_PATH="$root/state/openclaw.json" OPENCLAW_CONFIG_READONLY=1 OPENCLAW_PROFILE=pr1915-successor "$node" "$entry" gateway run --bind loopback --port 19515
fi
exit 2
