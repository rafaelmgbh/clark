#!/usr/bin/env bash
# Confere o install.sh e o atalho `clark` numa HOME de mentira, sem tocar na de verdade.
#
# Uso: Tests/packaging.sh   (feche o CLARK antes: o install.sh recusa instalar com o app aberto)
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "FALHOU: $1" >&2
  exit 1
}

[ -d dist/Clark.app ] || ./build.sh

fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
app="$fake/Applications/Clark.app"
launcher="$fake/.local/bin/clark"

echo "1. instalação limpa"
HOME="$fake" ./install.sh >/dev/null
[ -x "$app/Contents/MacOS/Clark" ] || fail "o app não foi copiado"
codesign --verify --strict "$app" || fail "a assinatura quebrou na cópia"
[ "$(HOME="$fake" "$launcher" --version)" = "$(dist/Clark.app/Contents/MacOS/Clark --version)" ] \
  || fail "clark --version"
HOME="$fake" "$launcher" --help | grep -q "^uso: clark" || fail "clark --help"

echo "2. reinstalar por cima do próprio atalho"
HOME="$fake" ./install.sh >/dev/null || fail "a reinstalação foi recusada"

echo "3. um clark de outro programa fica como está"
printf '#!/bin/sh\necho outro\n' > "$launcher"
rm -rf "$app"
if HOME="$fake" ./install.sh >/dev/null 2>&1; then fail "sobrescreveu um clark alheio"; fi
[ "$("$launcher")" = "outro" ] || fail "alterou o clark alheio"
[ ! -e "$app" ] || fail "instalou o app mesmo recusando o atalho"

echo "4. link simbólico não é seguido"
rm "$launcher"
echo "clark-mac-launcher" > "$fake/alvo"
ln -s "$fake/alvo" "$launcher"
if HOME="$fake" ./install.sh >/dev/null 2>&1; then fail "instalou por cima de um link"; fi
[ "$(cat "$fake/alvo")" = "clark-mac-launcher" ] || fail "escreveu no alvo do link"

echo "5. atalho sem o app avisa e falha"
rm "$launcher"
HOME="$fake" ./install.sh >/dev/null
rm -rf "$app"
if HOME="$fake" "$launcher" --version >/dev/null 2>&1; then fail "o atalho respondeu sem o app"; fi

echo "6. HOME vazia é recusada"
if HOME="" ./install.sh >/dev/null 2>&1; then fail "aceitou HOME vazia"; fi

echo "ok"
