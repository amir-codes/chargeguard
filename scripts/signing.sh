#!/bin/bash
# Prints the code signing identity or team for the Makefile.
#   scripts/signing.sh identity   -> "Apple Development: Name (ABCDE12345)" or nothing
#   scripts/signing.sh team       -> the certificate's Team ID (subject OU) or nothing
# Nothing printed means ad-hoc signing.
set -uo pipefail

identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ { print $2; exit }')"

case "${1:-identity}" in
    identity)
        [[ -n "$identity" ]] && echo "$identity"
        ;;
    team)
        if [[ -n "$identity" ]]; then
            security find-certificate -c "$identity" -p 2>/dev/null \
                | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
                | awk -F' = ' '/organizationalUnitName/ { print $2; exit }'
        fi
        ;;
esac
exit 0
