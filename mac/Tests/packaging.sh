#!/usr/bin/env bash
# Confere o build.sh, o install.sh, o atalho `clark` e o update.sh numa HOME de mentira, sem tocar
# na de verdade. Pode rodar com o CLARK aberto. O último passo compila o app de novo numa pasta de
# cache: leva alguns minutos.
#
# Uso: Tests/packaging.sh
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "FALHOU: $1" >&2
  exit 1
}

./build.sh >/dev/null

fake="$(mktemp -d)"
sleeper=""
trap '[ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null; rm -rf "$fake"' EXIT
app="$fake/Applications/Clark.app"
launcher="$fake/.local/bin/clark"

echo "1. instalação limpa"
HOME="$fake" ./install.sh >/dev/null
[ -x "$app/Contents/MacOS/Clark" ] || fail "o app não foi copiado"
[ -s "$app/Contents/Resources/AppIcon.icns" ] || fail "o app foi copiado sem o ícone"
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

value() { plutil -extract "$2" raw -o - "$1/Contents/Info.plist"; }

echo "7. o build grava de onde o app veio e leva o update.sh"
[ "$(value dist/Clark.app ClarkSourceRepo)" = "$(git rev-parse --show-toplevel)" ] || fail "ClarkSourceRepo"
[ "$(value dist/Clark.app ClarkSourceTree)" = "$(git rev-parse HEAD:mac)" ] || fail "ClarkSourceTree"
[ -x dist/Clark.app/Contents/Resources/update.sh ] || fail "o app saiu sem o update.sh"

# Um repo de mentira com o mac/ desta pasta, commitado, e o app instalado apontando para ele.
repo="$fake/repo"
mkdir -p "$repo/mac"
git ls-files -z -co --exclude-standard | tar --null -T - -cf - | tar -x -C "$repo/mac"
g() { git -C "$repo" -c user.name=clark -c user.email=clark@example.invalid -c commit.gpgsign=false "$@"; }
g -c init.defaultBranch=main init -q
g add -- mac
g commit -qm um
tree() { git -C "$repo" rev-parse HEAD:mac; }
point() {
  plutil -replace ClarkSourceRepo -string "$repo" "$1/Contents/Info.plist"
  plutil -replace ClarkSourceTree -string "$2" "$1/Contents/Info.plist"
}

home="$fake/home"
mkdir -p "$home"
HOME="$home" ./install.sh >/dev/null
app="$home/Applications/Clark.app"
point "$app" "$(tree)"
cache="$fake/cache"
log="$fake/update.log"
# update [VAR=valor ...] -- [argumentos do update.sh]
update() {
  local vars=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do vars+=("$1"); shift; done
  [ $# -eq 0 ] || shift
  env HOME="$home" CLARK_UPDATE_DIR="$cache" ${vars[@]+"${vars[@]}"} \
    "$app/Contents/Resources/update.sh" --app "$app" --log "$log" "$@"
}

echo "8. em dia, o update.sh não faz nada"
[ -z "$(update)" ] || fail "em dia, o update.sh escreveu algo"
g commit -q --allow-empty -m vazio
echo nota > "$repo/fora.txt"
g add -- fora.txt
g commit -qm fora
[ -z "$(update)" ] || fail "um commit fora de mac/ disparou a atualização"
[ ! -e "$cache/src" ] || fail "em dia, o update.sh extraiu o repo"

echo nota > "$repo/mac/NOTA.txt"
g add -- mac/NOTA.txt
g commit -qm nota
new="$(tree)"

echo "9. desligado, ou com outra atualização rodando, o update.sh não faz nada"
[ -z "$(update CLARK_NO_UPDATE=1)" ] || fail "CLARK_NO_UPDATE escreveu algo"
mkdir -p "$cache/lock"
echo "$$" > "$cache/lock/pid"
update | grep -q "outra atualização" || fail "não avisou da outra atualização"
[ -e "$cache/lock" ] || fail "apagou a trava de outro processo"
[ ! -e "$cache/src" ] || fail "atualizou com a trava de outro processo"
[ "$(value "$app" ClarkSourceTree)" != "$new" ] || fail "atualizou desligado ou travado"

echo "10. app aberto: nem o update.sh nem o install.sh mexem nele"
open_home="$fake/aberto"
open_app="$open_home/Applications/Clark.app"
mkdir -p "$open_home/Applications"
ditto "$app" "$open_app"
# O app "aberto" é um sleep com o nome do binário do app. Copiar o sleep para dentro do pacote não
# serve: o macOS mata binário do sistema fora do lugar e passa a dizer que o pacote está danificado.
( exec -a "$open_app/Contents/MacOS/Clark" sleep 60 ) &
sleeper=$!
out="$(env HOME="$open_home" CLARK_UPDATE_DIR="$fake/cache-aberto" \
  "$open_app/Contents/Resources/update.sh" --app "$open_app")" || fail "o update.sh falhou com o app aberto"
[ -z "$out" ] && [ ! -e "$fake/cache-aberto/src" ] || fail "o update.sh mexeu no app aberto"
if HOME="$open_home" ./install.sh >/dev/null 2>&1; then fail "o install.sh trocou o app aberto"; fi
kill "$sleeper"
wait "$sleeper" 2>/dev/null || true
sleeper=""

echo "11. commit novo em mac/: o update.sh espera o app sair, compila o HEAD e reinstala"
( exit 0 ) &
gone=$!
wait "$gone"
echo "$gone" > "$cache/lock/pid"
update -- --after "$gone" > "$fake/out" || { tail -30 "$log" >&2; fail "a atualização falhou"; }
grep -q "atualizado" "$fake/out" || fail "não disse que atualizou"
[ "$(value "$app" ClarkSourceTree)" = "$new" ] || fail "o app instalado não é o do HEAD"
[ "$(value "$app" ClarkSourceRepo)" = "$repo" ] || fail "o app instalado perdeu o repo"
codesign --verify --strict "$app" || fail "a assinatura do app atualizado"
[ -n "$(HOME="$home" "$home/.local/bin/clark" --version)" ] || fail "o atalho depois da atualização"
[ ! -e "$cache/lock" ] || fail "a trava ficou para trás"
[ -z "$(update)" ] || fail "atualizado, o update.sh ainda escreveu algo"
ls -A "$home/Applications" | grep -q "clark-install" && fail "a pasta da instalação ficou para trás"

echo "ok"
