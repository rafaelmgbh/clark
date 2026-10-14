#!/usr/bin/env bash
# Compila o CLARK em release, monta dist/Clark.app com o ícone e assina ad hoc.
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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Clark"

# O ícone é desenhado pelo próprio binário (Sources/Clark/AppIcon.swift), um PNG por tamanho.
iconset="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "$(dirname "$iconset")"' EXIT
mkdir "$iconset"
for points in 16 32 128 256 512; do
  "$binary" --export-icon "$iconset/icon_${points}x${points}.png" --icon-size "$points"
  "$binary" --export-icon "$iconset/icon_${points}x${points}@2x.png" --icon-size "$((points * 2))"
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $short" \
  -c "Set :CFBundleVersion $build" \
  "$app/Contents/Info.plist"

# De onde o app veio, para o update.sh trazê-lo ao último commit: o repo e a árvore de mac/ no HEAD.
# Um build com mudanças ainda não commitadas grava o HEAD, e o commit delas dispara a atualização.
# O update.sh passa os dois prontos, porque compila uma cópia extraída do repo.
source_repo="${CLARK_SOURCE_REPO:-}"
source_tree="${CLARK_SOURCE_TREE:-}"
if [ -z "$source_repo" ]; then
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  # Só o repo em que este build.sh está: uma pasta solta pode ficar dentro de outro repo.
  if [ -n "$top" ] && [ "$top/mac/build.sh" -ef build.sh ] \
    && source_tree="$(git rev-parse --verify --quiet HEAD:mac)"; then
    source_repo="$top"
  fi
fi
if [ -n "$source_repo" ] && [ -n "$source_tree" ]; then
  plutil -replace ClarkSourceRepo -string "$source_repo" "$app/Contents/Info.plist"
  plutil -replace ClarkSourceTree -string "$source_tree" "$app/Contents/Info.plist"
fi
install -m 755 update.sh "$app/Contents/Resources/update.sh"

# O bundle de recursos do SwiftTerm (só o shader do renderizador Metal) fica de fora:
# o CLARK desenha por CoreGraphics e nunca liga esse renderizador.

# Assinatura ad hoc, sem "hardened runtime": com ele o macOS passa a exigir do CLARK
# um entitlement para cada permissão que um programa dos agentes pedir.
codesign --force --sign - "$app"
codesign --verify --strict "$app"

echo "pronto: $(pwd)/$app (versão $version${source_tree:+, mac/ ${source_tree:0:7}})"
