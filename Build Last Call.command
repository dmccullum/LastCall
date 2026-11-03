#!/bin/zsh
# Double-click in Finder to build Last Call.app into dist/ and open it.
set -euo pipefail

cd "${0:A:h}"

if ! command -v swift >/dev/null 2>&1; then
    echo "Swift isn’t installed. Install Xcode 26 or its Command Line Tools, then try again."
    read -k 1 "?Press any key to close."
    exit 1
fi

APP="$PWD/dist/LastCall.app"

if ! Scripts/build-app.sh; then
    echo
    echo "The build failed. The errors are above."
    read -k 1 "?Press any key to close."
    exit 1
fi

echo
echo "Built $APP"
open "$APP"
