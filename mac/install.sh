#!/usr/bin/env bash
# Instala o CLARK em ~/Applications e cria o atalho ~/.local/bin/clark.
#
# Uso: ./install.sh
# Para remover: apague ~/Applications/Clark.app e ~/.local/bin/clark.
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
  echo "install.sh: HOME não aponta para uma pasta" >&2
  exit 1
fi

source_app="dist/Clark.app"
target_app="$HOME/Applications/Clark.app"
launcher="$HOME/.local/bin/clark"
# Linha que identifica o atalho criado por este script.
marker="clark-mac-launcher"

# Antes de copiar qualquer coisa: um `clark` que não é nosso fica como está.
if [ -L "$launcher" ] || { [ -e "$launcher" ] && ! grep -q "$marker" "$launcher" 2>/dev/null; }; then
  echo "install.sh: $launcher já existe e não é o atalho do CLARK para macOS." >&2
  echo "Nada foi instalado. Remova ou renomeie esse arquivo e rode de novo." >&2
  exit 1
fi

# Trocar o app embaixo de um CLARK aberto invalida a assinatura do processo em execução.
if pgrep -qf "Clark\.app/Contents/MacOS/Clark"; then
  echo "install.sh: o CLARK está aberto. Feche o app e rode de novo." >&2
  exit 1
fi

if [ ! -d "$source_app" ]; then
  ./build.sh
fi
codesign --verify --strict "$source_app"

mkdir -p "$HOME/Applications" "$(dirname "$launcher")"
rm -rf "$target_app"
ditto "$source_app" "$target_app"

rm -f "$launcher"
cat > "$launcher" <<'LAUNCHER'
#!/usr/bin/env bash
# clark-mac-launcher: atalho criado pelo install.sh do CLARK para macOS.
app="$HOME/Applications/Clark.app"
if [ ! -x "$app/Contents/MacOS/Clark" ]; then
  echo "clark: $app não encontrado; rode o install.sh de novo" >&2
  exit 1
fi
# --version e --help respondem no terminal. Depois do `--` a opção é do claude.
for argument in "$@"; do
  case "$argument" in
    --) break ;;
    -h|--help|--version) exec "$app/Contents/MacOS/Clark" "$@" ;;
  esac
done
# O `open` não preserva a pasta do terminal: ela vai em --launch-dir.
exec /usr/bin/open -a "$app" --args --launch-dir "$PWD" "$@"
LAUNCHER
chmod 755 "$launcher"

echo "instalado: $target_app"
echo "atalho:    $launcher"
case ":${PATH:-}:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "aviso: $HOME/.local/bin não está no PATH; sem isso o comando \`clark\` não é achado." ;;
esac
