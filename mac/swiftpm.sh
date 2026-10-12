#!/usr/bin/env bash
# Roda `swift <comando>` com o sistema de build que funciona nesta máquina.
#
# O SwiftTerm traz um shader Metal. O build padrão do SwiftPM compila esse shader e
# exige o Metal Toolchain do Xcode (xcodebuild -downloadComponent MetalToolchain).
# Sem ele, o build nativo só copia o arquivo, e isso basta: o Clark desenha por
# CoreGraphics e nunca liga o renderizador Metal.
#
# Uso: ./swiftpm.sh test | ./swiftpm.sh build -c release
set -euo pipefail
cd "$(dirname "$0")"

cmd="${1:?uso: swiftpm.sh <build|test|run> [argumentos]}"
shift
flags=()
if ! xcrun metal --version >/dev/null 2>&1; then
  flags+=(--build-system native)
fi
exec swift "$cmd" ${flags[@]+"${flags[@]}"} "$@"
