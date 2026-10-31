#!/bin/bash
# run.sh file.js  -> execute file with the H prelude
D="$(cd "$(dirname "$0")" && pwd)"
cat "$D/prelude.js" "$1" > "$D/.last.js"
"$D/pp.sh" code "$D/.last.js"
