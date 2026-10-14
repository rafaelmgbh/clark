#!/usr/bin/env bash
# Atualiza o CLARK instalado para o último commit do repo de onde ele foi compilado.
#
# O build.sh grava no Info.plist do app o repo (ClarkSourceRepo) e a árvore de mac/ que foi
# compilada (ClarkSourceTree). Quando o HEAD do repo traz outra árvore em mac/, este script extrai
# essa árvore para uma pasta de cache, compila com o build.sh dela e instala com o install.sh dela.
# Vale só o que está commitado: o que está sendo editado no repo fica de fora. Usa só o repo local,
# sem `git fetch`.
#
# Quem chama: o atalho `clark`, antes de abrir o app, e o próprio app, ao fechar.
#
# Uso: update.sh --app <Clark.app> [--after <pid>] [--log <arquivo>]
#   --after  espera o processo sair antes (o app passa o próprio pid ao fechar)
#   --log    manda a saída do build e da instalação para o arquivo
# Sem nada a fazer, não escreve nada. CLARK_NO_UPDATE desliga; CLARK_UPDATE_DIR troca a pasta de cache.
#
# Roda no bash 3.2 do macOS. Tudo fica dentro de main: o bash lê a função inteira antes de rodar,
# e a instalação apaga o app de onde este arquivo pode estar sendo lido.
set -euo pipefail

say() { echo "clark: $*"; }

die() {
  echo "clark: $*" >&2
  exit 1
}

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
}

short() {
  if [ -n "$1" ]; then echo "${1:0:7}"; else echo "?"; fi
}

# O binário do app está rodando. Compara o começo da linha de comando, e não um trecho dela:
# o próprio update.sh recebe o caminho do app como argumento.
app_running() {
  local pattern
  pattern="$(printf '%s' "$1/Contents/MacOS/Clark" | sed 's/[][\\.*^$+?(){}|]/\\&/g')"
  pgrep -qf "^$pattern( |\$)"
}

wait_exit() {
  local tries=0
  while kill -0 "$1" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -le 120 ] || return 1
    sleep 1
  done
}

# Uma atualização por vez. A trava é uma pasta com o pid de quem a criou; a de um processo que
# morreu no meio é desfeita.
take_lock() {
  local lock="$1" holder
  if ! mkdir "$lock" 2>/dev/null; then
    holder="$(cat "$lock/pid" 2>/dev/null || true)"
    case "$holder" in
      "" | *[!0-9]*)
        # Sem pid: ou acabou de ser criada, ou o processo morreu antes de escrever.
        [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] || return 1
        ;;
      *)
        if kill -0 "$holder" 2>/dev/null; then return 1; fi
        ;;
    esac
    rm -rf "$lock"
    mkdir "$lock" 2>/dev/null || return 1
  fi
  echo "$$" > "$lock/pid"
}

run() {
  if [ -n "$log" ]; then "$@" >>"$log" 2>&1; else "$@"; fi
}

main() {
  app="" after="" log=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --app | --after | --log)
        [ $# -ge 2 ] || die "update.sh: falta o valor de $1"
        case "$1" in
          --app) app="$2" ;;
          --after) after="$2" ;;
          --log) log="$2" ;;
        esac
        shift 2
        ;;
      *) die "update.sh: opção desconhecida: $1" ;;
    esac
  done
  [ -n "$app" ] || die "uso: update.sh --app <Clark.app> [--after <pid>] [--log <arquivo>]"
  [ -z "${CLARK_NO_UPDATE:-}" ] || exit 0
  if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then die "update.sh: HOME não aponta para uma pasta"; fi
  # Só o app que o install.sh instala, que é o que ele troca. Um app rodado de dist/ fica como está.
  [ "$app" = "$HOME/Applications/Clark.app" ] || exit 0

  plist="$app/Contents/Info.plist"
  repo="$(plist_value "$plist" ClarkSourceRepo)"
  # Compilado fora de um repo: não há de onde atualizar.
  [ -n "$repo" ] || exit 0

  if [ -n "$after" ]; then
    case "$after" in *[!0-9]*) die "update.sh: --after espera um pid" ;; esac
    wait_exit "$after" || die "o processo $after não saiu; nada foi atualizado"
  fi
  # Aberto: a atualização fica para quando ele fechar.
  if app_running "$app"; then exit 0; fi

  head="$(git -C "$repo" rev-parse --verify --quiet HEAD:mac 2>/dev/null)" \
    || die "o repo $repo não foi lido; o CLARK segue na versão instalada"
  [ "$head" != "$(plist_value "$plist" ClarkSourceTree)" ] || exit 0

  cache="${CLARK_UPDATE_DIR:-$HOME/Library/Caches/io.github.rafaelmgbh.clark/update}"
  mkdir -p "$cache"
  if ! take_lock "$cache/lock"; then
    say "outra atualização do CLARK está rodando"
    exit 0
  fi
  trap 'rm -rf "$cache/lock"' EXIT
  # Quem tinha a trava antes pode ter acabado de instalar esta mesma versão.
  built="$(plist_value "$plist" ClarkSourceTree)"
  [ "$head" != "$built" ] || exit 0

  if [ -n "$log" ]; then
    mkdir -p "$(dirname "$log")"
    : > "$log"
  fi
  say "atualizando o CLARK: $(short "$built") -> $(short "$head") (a primeira vez leva alguns minutos)"

  # A pasta .build da extração anterior volta para a nova: o build seguinte só recompila o que mudou.
  src="$cache/src"
  next="$cache/src.next"
  rm -rf "$next"
  mkdir -p "$next"
  git -C "$repo" archive --format=tar "$head" | tar -x -C "$next"
  if [ -d "$src/.build" ]; then mv "$src/.build" "$next/.build"; fi
  rm -rf "$src"
  mv "$next" "$src"

  run env CLARK_SOURCE_REPO="$repo" CLARK_SOURCE_TREE="$head" "$src/build.sh" \
    || die "o build falhou; o CLARK segue na versão instalada${log:+ (detalhes em $log)}"
  if app_running "$app"; then
    die "o CLARK abriu durante o build; a atualização fica para quando ele fechar"
  fi
  run "$src/install.sh" || die "a instalação falhou${log:+ (detalhes em $log)}"
  say "CLARK atualizado para $(short "$head")"
}

main "$@"
exit 0
