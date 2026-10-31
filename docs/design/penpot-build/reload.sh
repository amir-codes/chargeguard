#!/bin/bash
D="$(cd "$(dirname "$0")" && pwd)"
node -e 'const fs=require("fs");const src=fs.readFileSync(process.argv[1],"utf8").trim(); new Function("penpot","penpotUtils","storage","return "+src); fs.writeFileSync(process.argv[2], "const src = "+JSON.stringify(src)+";\npenpot.currentFile.setSharedPluginData(\"cg\",\"core\",src);\nstorage.H = new Function(\"penpot\",\"penpotUtils\",\"storage\",\"return \"+src)(penpot,penpotUtils,storage);\nreturn Object.keys(storage.H).length;\n")' "$D/core.js" "$D/load_core.js" && "$D/pp.sh" code "$D/load_core.js"
