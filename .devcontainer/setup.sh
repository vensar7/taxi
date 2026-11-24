#!/usr/bin/env bash
set -euo pipefail
if [ ! -d /home/vscode/flutter ]; then
  git clone https://github.com/flutter/flutter.git -b stable /home/vscode/flutter
fi
export PATH="$PATH:/home/vscode/flutter/bin"
flutter config --enable-web
for project in packages/taxi_shared taxi-customers taxi-driver; do
  (cd "$project" && flutter pub get)
done
