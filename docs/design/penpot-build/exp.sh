#!/bin/bash
# exp.sh "<top-level shape name>" out.png   (current page)
D="$(cd "$(dirname "$0")" && pwd)"
id=$("$D/pp.sh" js "const s = penpot.root.children.find(s => s.name === $(jq -nc --arg n "$1" '$n')); return s ? s.id : null" | jq -r .result)
[ "$id" = "null" ] && { echo "not found: $1"; exit 1; }
TMO=${TMO:-90} "$D/pp.sh" call export_shape "{\"shapeId\":\"$id\",\"filePath\":\"$2\"}"
