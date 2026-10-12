#!/usr/bin/env bash
# Compila o CLARK em release, monta dist/Clark.app e assina ad hoc.
#
# Uso: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

app="dist/Clark.app"

./swiftpm.sh build -c release --product Clark
binary="$(./swiftpm.sh build -c release --show-bin-path)/Clark"
if [ ! -x "$binary" ]; then
  echo "build.sh: o binário não apareceu em $binary" >&2
  exit 1
fi

# A versão tem uma fonte só: Sources/ClarkCore/Version.swift, lida pelo próprio binário.
version="$("$binary" --version | awk '{print $2}')"   # clark 0.1.0-mac.1 -> 0.1.0-mac.1
short="${version%%-*}"                                # 0.1.0
build="${version##*.}"                                # 1
if ! [[ "$short" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]]; then
  echo "build.sh: versão inesperada: '$version'" >&2
  exit 1
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/Clark"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $short" \
  -c "Set :CFBundleVersion $build" \
  "$app/Contents/Info.plist"

# O bundle de recursos do SwiftTerm (só o shader do renderizador Metal) fica de fora:
# o CLARK desenha por CoreGraphics e nunca liga esse renderizador.

# Assinatura ad hoc, sem "hardened runtime": com ele o macOS passa a exigir do CLARK
# um entitlement para cada permissão que um programa dos agentes pedir.
codesign --force --sign - "$app"
codesign --verify --strict "$app"

echo "pronto: $(pwd)/$app (versão $version)"
