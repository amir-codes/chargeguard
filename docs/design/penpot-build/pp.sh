#!/bin/bash
# Minimal Penpot MCP JSON-RPC client.
# pp.sh init                  -> new session id into sid.txt
# pp.sh call <tool> <json>    -> tools/call with raw JSON arguments
# pp.sh code <file.js>        -> execute_code with the file's contents
# pp.sh js '<code>'           -> execute_code with inline code
D="$(cd "$(dirname "$0")" && pwd)"
URL=http://localhost:4401/mcp
H1='Content-Type: application/json'
H2='Accept: application/json, text/event-stream'

init() {
  curl -s -m 15 -D "$D/hdr.txt" -o /dev/null -X POST $URL -H "$H1" -H "$H2" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cc","version":"1"}}}'
  sid=$(grep -i mcp-session-id "$D/hdr.txt" | awk '{print $2}' | tr -d '\r')
  echo "$sid" > "$D/sid.txt"
  curl -s -m 15 -o /dev/null -X POST $URL -H "$H1" -H "$H2" -H "Mcp-Session-Id: $sid" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  echo "$sid"
}

call() {
  [ -s "$D/sid.txt" ] || init >/dev/null
  sid=$(cat "$D/sid.txt")
  body=$(jq -nc --arg t "$1" --argjson a "$2" '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:$t,arguments:$a}}')
  out=$(curl -s -m ${TMO:-60} -X POST $URL -H "$H1" -H "$H2" -H "Mcp-Session-Id: $sid" -d "$body")
  if echo "$out" | grep -q 'Session not found\|Bad Request: No valid session'; then
    init >/dev/null; sid=$(cat "$D/sid.txt")
    out=$(curl -s -m ${TMO:-60} -X POST $URL -H "$H1" -H "$H2" -H "Mcp-Session-Id: $sid" -d "$body")
  fi
  echo "$out" | sed -n 's/^data: //p' | jq -r '.result.content[]?.text // .error // .' 2>/dev/null || echo "$out"
}

case "$1" in
  init) init ;;
  call) call "$2" "${3:-{\}}" ;;
  code) call execute_code "$(jq -Rs '{code:.}' < "$2")" ;;
  js) call execute_code "$(jq -nc --arg c "$2" '{code:$c}')" ;;
esac
