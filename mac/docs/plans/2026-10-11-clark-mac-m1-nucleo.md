# CLARK para macOS — M1 (Núcleo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar o `Clark.app` nativo do M1: vários agentes do Claude Code numa janela, cada um com a cor da sua empresa e o ambiente filtrado, com estados, notificação, foco, grade, zoom e as conversas de volta ao reabrir.

**Architecture:** Dois alvos SwiftPM em `mac/`. `ClarkCore` guarda a lógica pura (config, empresas, ambiente, máquina de estados, sessão, grade, fonte de pixels) e é testado sem interface. `Clark` é a interface AppKit: um terminal do SwiftTerm por agente, vistas desenhadas em CoreGraphics com pixel inteiro e um `MainWindowController` que junta tudo. O Python original fica intacto na raiz do repo.

**Tech Stack:** Swift 5.9 ou mais novo, SwiftPM, AppKit, CoreGraphics, UserNotifications, SwiftTerm `v1.19.0` (fixado por revisão), XCTest, bash.

**Spec:** [`mac/docs/specs/2026-10-11-clark-mac-design.md`](../specs/2026-10-11-clark-mac-design.md)

## Global Constraints

Valores copiados do spec. Toda tarefa obedece a esta lista.

- SwiftPM, `swift-tools-version: 5.9`, macOS 14 ou mais novo.
- Dependência direta única: SwiftTerm (MIT), fixada pela revisão `464df5207fc2432e16c9a23abe538187196daf5f` (tag `v1.19.0`), com `Package.resolved` versionado.
- O `Package.resolved` fixa o SwiftTerm e o `swift-argument-parser` 1.8.2. Qualquer pacote novo nesse arquivo é revisado antes de seguir.
- Todo build e todo teste passam pelo `mac/swiftpm.sh`, que usa `--build-system native` quando o Metal Toolchain do Xcode não está instalado.
- O `Clark.app` leva só o executável e o `Info.plist`, com o identificador `io.github.rafaelmgbh.clark`, assinatura ad hoc e sem hardened runtime.
- O Python original fica intacto na raiz; o Swift fica em `mac/`. Nenhuma tarefa cria ou altera arquivo fora de `mac/`.
- Repo público, sem dado de cliente: nomes de empresa, caminhos e hosts ficam em `~/.config/clark/`, fora do repo. Exemplos e testes usam nomes inventados.
- `auto_trust` não existe. O app nunca escreve em arquivo do Claude Code nem envia teclas ao terminal por conta própria.
- `~/.config/clark/`: diretório `0700`, arquivos `0600`, gravação por arquivo temporário criado já com `0600` e troca atômica. O `companies.json` nunca é gravado pelo app.
- Padrões de segredo, sem diferenciar maiúsculas: `*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*PASSWD*`, `*CREDENTIAL*`, `AWS_*`, `PG*`, `*_DSN` e `DATABASE_URL`. A lista só muda com aprovação.
- Das variáveis removidas, o app mostra os nomes. Valores nunca são exibidos nem gravados.
- Clique em link só abre `http` e `https`.
- Tempos da máquina de estados, iguais aos do original: 0,3 s de silêncio depois de uma tecla, janela de trabalho de 1,0 s, trabalho mínimo de 2,5 s para virar DONE, 2,0 s de BOOT, silêncios de 0,3 s (foco), 0,5 s (redimensionar) e 0,8 s (trocar layout), tique de 100 ms.
- No M1 só existe o tema `dark`, sem animação de mascote. A fila (M2) e a splash, os dragões, os outros temas e o ícone (M3) ficam fora.
- Os avisos da interface saem em ASCII, porque a fonte de pixels não tem acentos.
- Licença MIT mantida. O README de `mac/` credita o original.
- Nenhum `git add`, `git commit` ou `git push` sem o ok explícito do dono do repo. O plano inteiro é implementado sem commit; a Task 16 pede um ok único. Os commits saem sem `Co-Authored-By` e sem assinatura de assistente, com os arquivos adicionados por caminho.
- Durante a execução do plano, nada é instalado na HOME de verdade: o `install.sh` só roda com HOME temporária (é o que o `Tests/packaging.sh` faz). Os testes não escrevem na área de transferência.

## Review Focus

O que o spec implica e nenhum teste cobriria se o plano seguisse só a lista de testes dele. Do mais provável para o menos provável. Cada linha tem o teste que a fixa, na tarefa dona do código.

1. **Agente salvo cuja pasta foi apagada** (uma worktree removida entre uma sessão e outra). Esperado: o agente abre na home, numa conversa nova, e a barra avisa; a conversa antiga, que pertence a outra pasta, não é retomada de lá. Task 12, `testAgentWhoseFolderVanishedStartsANewConversationAtHome`.
2. **`companies.json` com um `path` igual a uma root, ou acima dela** (por exemplo `~`). Esperado: a regra vale como foi escrita, e a barra avisa que aquela empresa cobre a root inteira. Task 5, `testCompanyPathThatCoversARootWarns`.
3. **Link simbólico dentro da pasta de uma empresa apontando para a pasta de outra.** Esperado: o agente conta como da empresa de destino, que é onde o processo roda de fato. Task 12, `testLinkIntoAnotherCompanyCountsAsTheDestination`.
4. **Saída de um agente pedindo a leitura da área de transferência** (OSC 52 com `?`). Esperado: nada do que foi copiado chega ao processo, e o resto da entrada segue normal. Task 9, `testClipboardReplyNeverReachesTheProcess` e `testOnlyTheClipboardReplyIsDropped`.
5. **`config.json` que não pode ser gravado** (pasta sem permissão de escrita, disco cheio). Esperado: os agentes continuam abertos e a barra avisa, uma vez, que eles não voltam ao reabrir. Task 12, `testConfigThatCannotBeSavedWarnsAndKeepsTheAgents` e `testSaveFailureWarningDoesNotComeBackAfterBeingDismissed`.

---

## Como ler este plano

São 14 tarefas de código, um roteiro manual (Task 15) e o pedido de ok dos commits (Task 16). Cada tarefa de código segue o mesmo ciclo: escrever os testes, ver o build falhar pelo motivo certo, escrever o código, ver os testes passarem.

O plano traz o conteúdo completo de cada arquivo. Antes de cada bloco de código há uma linha `**Arquivo:**` com o caminho; o arquivo é exatamente o que está no bloco, mais uma quebra de linha no fim. Os comandos rodam de dentro de `mac/`.

## Como este plano foi validado

Todo o código abaixo foi escrito e testado antes, fora do repo. Depois o plano foi simulado: um pacote vazio recebeu os arquivos tarefa a tarefa, na ordem e com o conteúdo deste documento, e em cada tarefa rodaram o passo que tem de falhar e os passos que têm de passar. Os resultados em "Expected" são os dessa simulação (Swift 6.4, macOS 26.6.2). No fim, a árvore simulada ficou idêntica à do rascunho: 220 testes sem falha e os seis cenários do `Tests/packaging.sh`.

Depois da execução, a revisão final do código achou três defeitos: o aviso de `config.json` não gravado voltava a cada gravação, o rc do shell desfazia o filtro de ambiente em silêncio, e uma regra de empresa sobre uma pasta que ainda não existia nunca casava. As correções e os testes delas já estão nos arquivos deste plano, e a simulação foi refeita com eles.

A simulação não cobre o que depende de tela, teclado e conta: o `claude` de verdade desenhando, as teclas mortas do teclado ABNT, a notificação do macOS e a abertura pelo Finder. Isso está no roteiro manual da Task 15.

## Decisões deste plano

O spec deixa estes pontos em aberto ou a preparação os mostrou. Vale rever antes de executar.

| Decisão | Motivo | O que fica sabido |
|---|---|---|
| A resposta ao pedido de leitura da área de transferência (OSC 52) é descartada; a escrita continua valendo | O SwiftTerm responde ao pedido com o texto copiado e a classe-base não deixa desligar. A escrita não tem gancho para sobrescrever, e é o comportamento comum dos terminais | A saída de um agente ainda consegue trocar o que está copiado |
| Agente salvo cuja pasta sumiu abre na home, em conversa nova | Retomar na home uma conversa de outra pasta falha em laço | Um aviso na barra por abertura |
| `path` do `companies.json` que cobre uma root vale como foi escrito, com aviso | É a regra do spec: o explícito vence a detecção automática | Alternativa não adotada: o caminho mais específico vencer também entre explícito e detectado, o que mudaria o spec |
| Falha ao gravar o `config.json` vira aviso | Em silêncio, o usuário só descobriria ao reabrir sem os agentes | Um aviso por sessão: dispensado, ele não volta, mesmo que a gravação siga falhando |
| Na abertura, o app sonda o que o rc do shell devolve e avisa os nomes | Todo `$SHELL -c` relê o rc (no zsh, o `~/.zshenv`), e uma variável exportada ali desfaz o filtro em silêncio | O app não bloqueia nem altera o rc. Sem `claude`, o painel é o shell de login, e o menu do agente diz que o filtro não vale |
| `path` do `companies.json` que ainda não existe é resolvido até a pasta mais funda que existe | Uma pasta criada depois de o CLARK abrir tem de cair na empresa certa | O trecho que ainda não existe é comparado como foi escrito, inclusive a caixa; reabrir o CLARK depois de criar a pasta corrige |
| A lista lateral fica à direita e só existe no modo foco | Como no original | Na grade, cada painel já mostra o seu cabeçalho |
| Um quadrado com a cor da empresa ocupa o lugar do mascote | O mascote animado é do M3 | |
| O nome da empresa aparece no cabeçalho e no card | É o ganho principal do fork | |
| A tecla Option fica como Meta, o padrão do SwiftTerm | Os atalhos de palavra do shell e do `claude` dependem disso | Acentos por tecla morta são conferidos no roteiro manual |
| `clark` com o app aberto só traz a janela para a frente | Dois apps gravariam o mesmo `config.json` | As opções dessa segunda chamada são descartadas |
| Renomear não muda o `CLARK_AGENT` do processo que já roda | O ambiente de um processo vivo não se altera de fora | Vale na próxima abertura do agente |
| `--no-splash` é aceito e ignorado | Mantém a linha de comando do original; a splash é do M3 | |
| Fechar a janela é sair do app | Um CLARK sem janela com agentes rodando seria invisível | Com agente vivo, um diálogo confirma |
| Sem botão de ajuda, sem engrenagem e sem lista TODO | Fora do M1; a lista TODO saiu do projeto | |
| Assinatura ad hoc, sem hardened runtime | Com ele o macOS exigiria um entitlement para cada permissão pedida por um programa dos agentes | Cada compilação pode pedir as permissões de novo |
| Saída do build em `mac/dist/`, sem ícone | O ícone é do M3 | |
| A cor por hash do nome pode coincidir entre duas empresas | A paleta tem oito cores | `color` no `companies.json` desfaz o empate |
| A lista de padrões de segredo é a do spec | É uma lista aprovada | Proposta em aberto: incluir `*_PASS`, `*_PWD` e `*_PAT`, e talvez `*_URI` e `REDIS_URL` |
| Dois commits no fim, e não um por tarefa | O `Package.swift` e o `main.swift` têm uma versão intermediária que não existe mais quando o ok chega | Ver a Task 16 |

Limitação herdada do original: o `/clear` dentro do `claude` troca a conversa, e ao reabrir o CLARK retoma a antiga.

## Mapa de arquivos

Caminhos relativos a `mac/`.

| Arquivo | Para que serve | Task | Linhas |
|---|---|---|---|
| `.gitignore` | Tira do git o que o build gera: `.build/`, `.swiftpm/`, `dist/`. | 1 | 6 |
| `Package.swift` | Os alvos `ClarkCore` e `Clark`, os dois de teste e o SwiftTerm fixado por revisão. | 1, final na 9 | 22 |
| `swiftpm.sh` | Chama o `swift` com o sistema de build que funciona na máquina. | 1 | 19 |
| `Package.resolved` | Versões travadas das dependências. | 9 | 22 |
| `README.md` | Como compilar, instalar e usar; empresas, ambiente dos agentes e limitações do M1. | 14 | 167 |
| `build.sh` | Compila em release, monta `dist/Clark.app` e assina ad hoc. | 14 | 43 |
| `install.sh` | Copia o app para `~/Applications` e cria o atalho `~/.local/bin/clark`. | 14 | 68 |
| `Resources/Info.plist` | Identidade do app e os textos dos pedidos de permissão. | 14 | 49 |
| `Sources/ClarkCore/PathTools.swift` | Caminhos: `~`, absoluto, canônico, prefixo por componente, forma curta. | 1 | 68 |
| `Sources/ClarkCore/Version.swift` | A versão, numa fonte só. | 1 | 4 |
| `Sources/ClarkCore/PixelFont.swift` | Fonte 5x7: normalização, largura, corte e pixels de um texto. | 2 | 88 |
| `Sources/ClarkCore/RGB.swift` | Cor de 0 a 1: hex, mistura e escurecimento. | 2 | 54 |
| `Sources/ClarkCore/Theme.swift` | A paleta `dark` do original. | 2 | 47 |
| `Sources/ClarkCore/GridLayout.swift` | Colunas, células e retângulos da grade. | 3 | 46 |
| `Sources/ClarkCore/AgentStateMachine.swift` | Estados do agente a partir de eventos, com relógio injetado. | 4 | 118 |
| `Sources/ClarkCore/CompanyResolver.swift` | Caminho para empresa (nome, cor, `env_allow`); lê o `companies.json` e junta os avisos. | 5 | 199 |
| `Sources/ClarkCore/EnvPolicy.swift` | Ambiente final de um agente e os nomes que ficaram de fora. | 5 | 85 |
| `Sources/ClarkCore/ShellEnvParser.swift` | Lê a saída do shell de login e monta o ambiente de reserva. | 5 | 35 |
| `Sources/ClarkCore/Session.swift` | `SessionLocator`, `ClaudeCommand` e `ClaudeLocator`. | 6 | 97 |
| `Sources/ClarkCore/Config.swift` | `SavedAgent`, `ClarkConfig` e `ConfigStore`. | 7 | 230 |
| `Sources/ClarkCore/AgentNaming.swift` | Nomes e tons dos agentes; linhas de prévia do card. | 8 | 55 |
| `Sources/ClarkCore/CLIOptions.swift` | A linha de comando do `clark`. | 8 | 64 |
| `Sources/Clark/AgentTerminalView.swift` | O terminal de um agente e o encerramento do processo (`ProcessReaper`). | 9 | 148 |
| `Sources/Clark/RGB+AppKit.swift` | `RGB` como `NSColor` e `CGColor`. | 9 | 8 |
| `Sources/Clark/main.swift` | Chama `ClarkMain.run()`. | 9, final na 13 | 1 |
| `Sources/Clark/ShellEnvironment.swift` | Roda o shell de login e captura o ambiente, com limite de tempo; sonda o que o rc do shell devolve. | 10 | 105 |
| `Sources/Clark/AgentCardView.swift` | O card do agente na lista lateral. | 11 | 121 |
| `Sources/Clark/AgentHeaderView.swift` | `AgentSnapshot` e o cabeçalho do agente. | 11 | 90 |
| `Sources/Clark/Pixel.swift` | Desenho em pixels inteiros, a vista-base `PixelView` e os rótulos de estado. | 11 | 109 |
| `Sources/Clark/PixelButton.swift` | Os botões quadrados do original. | 11 | 109 |
| `Sources/Clark/SidebarView.swift` | A lista lateral do modo foco. | 11 | 82 |
| `Sources/Clark/TopBarView.swift` | Barra superior, barra de avisos e tela vazia. | 11 | 177 |
| `Sources/Clark/AgentPaneView.swift` | `AgentLaunch` e o painel de um agente: processo, estado, cabeçalho, menu. | 12 | 339 |
| `Sources/Clark/MainMenu.swift` | A barra de menus e os atalhos. | 12 | 75 |
| `Sources/Clark/MainWindowController.swift` | A janela: foco, grade, zoom, atalhos, salvar e restaurar. | 12 | 595 |
| `Sources/Clark/Notifier.swift` | Notificação e selo do Dock, atrás do protocolo `Notifying`. | 12 | 51 |
| `Sources/Clark/AppDelegate.swift` | Ciclo de vida do app e `ClarkMain`. | 13 | 116 |
| `Tests/ClarkCoreTests/PathToolsTests.swift` | 9 testes: `PathToolsTests`. | 1 | 86 |
| `Tests/ClarkCoreTests/TemporaryDirectory.swift` | Apoio: pasta temporária de um teste. | 1 | 48 |
| `Tests/ClarkCoreTests/PixelFontTests.swift` | 10 testes: `PixelFontTests`. | 2 | 74 |
| `Tests/ClarkCoreTests/RGBThemeTests.swift` | 5 testes: `RGBThemeTests`. | 2 | 44 |
| `Tests/ClarkCoreTests/GridLayoutTests.swift` | 6 testes: `GridLayoutTests`. | 3 | 67 |
| `Tests/ClarkCoreTests/AgentStateMachineTests.swift` | 15 testes: `AgentStateMachineTests`. | 4 | 182 |
| `Tests/ClarkCoreTests/CompanyResolverTests.swift` | 14 testes: `CompanyResolverTests`. | 5 | 164 |
| `Tests/ClarkCoreTests/EnvPolicyTests.swift` | 16 testes: `EnvPolicyTests`, `ShellEnvParserTests`. | 5 | 145 |
| `Tests/ClarkCoreTests/SessionTests.swift` | 15 testes: `SessionLocatorTests`, `ClaudeCommandTests`, `ClaudeLocatorTests`. | 6 | 120 |
| `Tests/ClarkCoreTests/ConfigTests.swift` | 19 testes: `ClarkConfigTests`, `ConfigStoreTests`. | 7 | 258 |
| `Tests/ClarkCoreTests/CLIOptionsTests.swift` | 14 testes: `CLIOptionsTests`, `AgentNamingTests`, `PreviewLinesTests`. | 8 | 112 |
| `Tests/ClarkTests/AgentTerminalViewTests.swift` | 11 testes: `AgentTerminalViewTests`. | 9 | 164 |
| `Tests/ClarkTests/TestSupport.swift` | Apoio: pasta temporária e espera por uma condição. | 9 | 54 |
| `Tests/ClarkTests/ShellEnvironmentTests.swift` | 12 testes: `ShellEnvironmentTests`. | 10 | 112 |
| `Tests/ClarkTests/PixelViewsTests.swift` | 24 testes: `PixelViewsTests`. | 11 | 366 |
| `Tests/ClarkTests/RenderedImage.swift` | Apoio: desenha uma vista num bitmap e lê os pixels. | 11 | 64 |
| `Tests/ClarkTests/ClarkFixture.swift` | Apoio: um CLARK de teste, com home temporária e relógio controlado. | 12 | 65 |
| `Tests/ClarkTests/MainWindowControllerTests.swift` | 48 testes: `MainWindowControllerTests`. | 12 | 824 |
| `Tests/ClarkTests/ClarkMainTests.swift` | 2 testes: `ClarkMainTests`. | 13 | 22 |
| `Tests/packaging.sh` | Confere o `install.sh` e o atalho numa HOME de mentira. | 14 | 54 |
| **57 arquivos** | | | **6737** |

## Tarefas

| Task | O que entrega | Testes novos |
|---|---|---|
| 1 | Pacote Swift, versão e caminhos | 9 testes |
| 2 | Cores, tema e fonte de pixels | 15 testes |
| 3 | Grade dos painéis | 6 testes |
| 4 | Máquina de estados do agente | 15 testes |
| 5 | Empresas e política de ambiente | 30 testes |
| 6 | Conversa do claude: retomar ou começar | 15 testes |
| 7 | config.json | 19 testes |
| 8 | Linha de comando, nomes e prévia | 14 testes |
| 9 | Alvo Clark, SwiftTerm e o terminal do agente | 11 testes |
| 10 | Ambiente do shell de login | 12 testes |
| 11 | Vistas de pixel: botões, cabeçalho, card, barra e lista | 24 testes |
| 12 | Painel do agente, janela e menu | 48 testes |
| 13 | Ponto de entrada do app | 2 testes |
| 14 | Clark.app, instalação e README | 6 cenários |
| 15 | Roteiro manual do M1 | 17 passos à mão |
| 16 | Pedir o ok dos commits | |

---

### Task 1: Pacote Swift, versão e caminhos

Cria o pacote SwiftPM, por enquanto só com o alvo `ClarkCore`, o `swiftpm.sh` e as duas primeiras unidades: a versão e as funções de caminho que quase todo o resto usa (expandir `~`, caminho absoluto e canônico, prefixo por componente e a forma curta para a interface).

**Atenção:** A pasta `mac/` já existe, só com `docs/`. Os arquivos `swiftpm.sh` e, mais adiante, `build.sh`, `install.sh` e `Tests/packaging.sh` precisam de permissão de execução (`chmod +x`).

**Files:**
- Create: `mac/.gitignore`
- Create: `mac/swiftpm.sh`
- Create: `mac/Package.swift`
- Create: `mac/Sources/ClarkCore/Version.swift`
- Create: `mac/Sources/ClarkCore/PathTools.swift`
- Test: `mac/Tests/ClarkCoreTests/TemporaryDirectory.swift`
- Test: `mac/Tests/ClarkCoreTests/PathToolsTests.swift`

**Interfaces:**
- Consumes: nada de tarefas anteriores.
- Produces:

```swift
// mac/Sources/ClarkCore/Version.swift
public enum ClarkVersion
    public static let current = "0.1.0-mac.1"

// mac/Sources/ClarkCore/PathTools.swift
public enum PathTools
    public static func expandTilde(_ path: String, home: String) -> String
    public static func absolute(_ path: String, base: String, home: String) -> String
    public static func canonical(_ path: String, base: String, home: String) -> String
    public static func components(_ path: String) -> [String]
    public static func hasPrefix(_ path: [String], _ prefix: [String]) -> Bool
    public static func short(_ path: String, home: String) -> String
    public static func isDirectory(_ path: String) -> Bool
    public static func isExecutableFile(_ path: String) -> Bool

// mac/Tests/ClarkCoreTests/TemporaryDirectory.swift
final class TemporaryDirectory
    let path: String
    init(file: StaticString = #filePath, line: UInt = #line)
    func makeDirectory(_ relative: String) -> String
    func write(_ relative: String, _ content: String, permissions: Int = 0o644) -> String
    func permissions(_ relative: String) -> Int?
```

- [ ] **Step 1: Preparar o pacote**

Os três arquivos que fazem `mac/` virar um pacote Swift.

**Arquivo:** `mac/.gitignore`

```text
.build/
.swiftpm/
dist/
*.app
.DS_Store
*.xcuserstate
```

**Arquivo:** `mac/swiftpm.sh` (executável: `chmod +x`)

```bash
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
```

**Arquivo:** `mac/Package.swift`

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clark",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClarkCore", path: "Sources/ClarkCore"),
        .testTarget(name: "ClarkCoreTests", dependencies: ["ClarkCore"], path: "Tests/ClarkCoreTests")
    ]
)
```

- [ ] **Step 2: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkCoreTests/TemporaryDirectory.swift`

```swift
import Foundation
import XCTest

/// Pasta temporária de um teste, apagada no fim.
final class TemporaryDirectory {
    let path: String

    init(file: StaticString = #filePath, line: UInt = #line) {
        let base = NSTemporaryDirectory() + "clark-tests-" + UUID().uuidString
        do {
            try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        } catch {
            XCTFail("não criou a pasta temporária: \(error)", file: file, line: line)
        }
        // /var é um link para /private/var: os testes comparam com o caminho real
        if let real = realpath(base, nil) {
            path = String(cString: real)
            free(real)
        } else {
            path = base
        }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    @discardableResult
    func makeDirectory(_ relative: String) -> String {
        let full = path + "/" + relative
        try? FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }

    @discardableResult
    func write(_ relative: String, _ content: String, permissions: Int = 0o644) -> String {
        let full = path + "/" + relative
        makeDirectory((relative as NSString).deletingLastPathComponent)
        FileManager.default.createFile(atPath: full, contents: Data(content.utf8),
                                       attributes: [.posixPermissions: permissions])
        return full
    }

    func permissions(_ relative: String) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path + "/" + relative)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}
```

**Arquivo:** `mac/Tests/ClarkCoreTests/PathToolsTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class PathToolsTests: XCTestCase {
    private let home = "/Users/eu"

    func testExpandTilde() {
        XCTAssertEqual(PathTools.expandTilde("~", home: home), "/Users/eu")
        XCTAssertEqual(PathTools.expandTilde("~/x/y", home: home), "/Users/eu/x/y")
        XCTAssertEqual(PathTools.expandTilde("~outro/x", home: home), "~outro/x")
        XCTAssertEqual(PathTools.expandTilde("/a/~", home: home), "/a/~")
    }

    func testAbsoluteCollapsesDotsAndResolvesRelative() {
        XCTAssertEqual(PathTools.absolute("a/../b/./c", base: "/base", home: home), "/base/b/c")
        XCTAssertEqual(PathTools.absolute("/a//b/", base: "/base", home: home), "/a/b")
        XCTAssertEqual(PathTools.absolute("/../..", base: "/base", home: home), "/")
        XCTAssertEqual(PathTools.absolute("~/p", base: "/base", home: home), "/Users/eu/p")
        XCTAssertEqual(PathTools.absolute(".", base: "/base/x", home: home), "/base/x")
        XCTAssertEqual(PathTools.absolute("", base: "/base/x", home: home), "/base/x")
    }

    func testCanonicalResolvesLinksAndKeepsMissingPaths() {
        let temp = TemporaryDirectory()
        let real = temp.makeDirectory("real/projeto")
        let link = temp.path + "/atalho"
        XCTAssertNoThrow(try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: temp.path + "/real"))
        XCTAssertEqual(PathTools.canonical(link + "/projeto", base: "/", home: home), real)
        XCTAssertEqual(PathTools.canonical("projeto", base: temp.path + "/real", home: home), real)
        XCTAssertEqual(PathTools.canonical("/nao/existe/../aqui", base: "/", home: home), "/nao/aqui")
    }

    func testCanonicalUsesTheCaseStoredOnDisk() throws {
        let temp = TemporaryDirectory()
        let real = temp.makeDirectory("Projetos/EmpresaA")
        let lower = temp.path + "/projetos/empresaa"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: lower), "volume diferencia maiúsculas")
        XCTAssertEqual(PathTools.canonical(lower, base: "/", home: home), real)
    }

    func testCanonicalResolvesTheExistingPartOfAMissingPath() {
        // A pasta ainda não existe: o que existe acima dela é resolvido, e o resto fica como foi escrito.
        let temp = TemporaryDirectory()
        let real = temp.makeDirectory("real/projeto")
        XCTAssertNoThrow(try FileManager.default.createSymbolicLink(atPath: temp.path + "/atalho",
                                                                    withDestinationPath: temp.path + "/real"))
        XCTAssertEqual(PathTools.canonical(temp.path + "/atalho/projeto/novo/src", base: "/", home: home),
                       real + "/novo/src")
        XCTAssertEqual(PathTools.canonical(temp.path + "/atalho/outro", base: "/", home: home),
                       temp.path + "/real/outro")
    }

    func testCanonicalUsesTheCaseStoredOnDiskForTheExistingPartOfAMissingPath() throws {
        let temp = TemporaryDirectory()
        let real = temp.makeDirectory("Projetos/EmpresaA")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: temp.path + "/projetos/empresaa"),
                          "volume diferencia maiúsculas")
        XCTAssertEqual(PathTools.canonical(temp.path + "/projetos/empresaa/Novo", base: "/", home: home),
                       real + "/Novo")
    }

    func testPrefixIsComparedByComponent() {
        XCTAssertEqual(PathTools.components("/a//b/c/"), ["a", "b", "c"])
        XCTAssertTrue(PathTools.components("/").isEmpty)
        XCTAssertTrue(PathTools.hasPrefix(["a", "b", "c"], ["a", "b"]))
        XCTAssertTrue(PathTools.hasPrefix(["a", "b"], ["a", "b"]))
        XCTAssertFalse(PathTools.hasPrefix(["a", "bc"], ["a", "b"]))
        XCTAssertFalse(PathTools.hasPrefix(["a"], ["a", "b"]))
    }

    func testShort() {
        XCTAssertEqual(PathTools.short("/Users/eu", home: home), "~")
        XCTAssertEqual(PathTools.short("/Users/eu/x/y", home: home), "~/x/y")
        XCTAssertEqual(PathTools.short("/Users/eu2/x", home: home), "/Users/eu2/x")
        XCTAssertEqual(PathTools.short("/opt/x", home: home), "/opt/x")
    }

    func testDirectoryAndExecutableChecks() {
        XCTAssertTrue(PathTools.isDirectory("/bin"))
        XCTAssertFalse(PathTools.isDirectory("/bin/sh"))
        XCTAssertFalse(PathTools.isDirectory("/nao/existe"))
        XCTAssertTrue(PathTools.isExecutableFile("/bin/sh"))
        XCTAssertFalse(PathTools.isExecutableFile("/bin"), "pasta não é executável")
        XCTAssertFalse(PathTools.isExecutableFile("/etc/hosts"))
    }
}
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `error: 'mac': invalid custom path 'Sources/ClarkCore' for target 'ClarkCore'`. O alvo `ClarkCore` ainda não tem nenhum arquivo.

- [ ] **Step 4: Escrever o código**

**Arquivo:** `mac/Sources/ClarkCore/Version.swift`

```swift
public enum ClarkVersion {
    /// Versão do CLARK para macOS. O original (`clark.py`) está em 0.1.0.
    public static let current = "0.1.0-mac.1"
}
```

**Arquivo:** `mac/Sources/ClarkCore/PathTools.swift`

```swift
import Foundation

public enum PathTools {
    public static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// Caminho absoluto sem `.` nem `..`. Relativo é resolvido a partir de `base`.
    public static func absolute(_ path: String, base: String, home: String) -> String {
        let expanded = expandTilde(path, home: home)
        let joined = expanded.hasPrefix("/") ? expanded : base + "/" + expanded
        var parts: [Substring] = []
        for part in joined.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Como `absolute`, com a parte que existe trocada pelo caminho real: links resolvidos e
    /// a caixa gravada no disco. Assim `~/projetos/x` e `~/Projetos/X` dão a mesma resposta
    /// num disco que não diferencia maiúsculas, e um link para outra pasta conta como a pasta de destino.
    /// O trecho que ainda não existe fica como foi escrito: uma regra sobre uma pasta que só nasce
    /// depois continua casando com ela.
    public static func canonical(_ path: String, base: String, home: String) -> String {
        var existing = components(absolute(path, base: base, home: home))
        var missing: [String] = []
        while true {
            if let real = realpath("/" + existing.joined(separator: "/"), nil) {
                defer { free(real) }
                return "/" + (components(String(cString: real)) + missing.reversed()).joined(separator: "/")
            }
            // `realpath("/")` sempre responde: o laço acaba antes de `existing` esvaziar.
            guard let last = existing.popLast() else { return "/" + missing.reversed().joined(separator: "/") }
            missing.append(last)
        }
    }

    public static func components(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    public static func hasPrefix(_ path: [String], _ prefix: [String]) -> Bool {
        path.count >= prefix.count && Array(path.prefix(prefix.count)) == prefix
    }

    /// `~/x` no lugar de `/Users/eu/x` (`short_path` do original).
    public static func short(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    public static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public static func isExecutableFile(_ path: String) -> Bool {
        !isDirectory(path) && FileManager.default.isExecutableFile(atPath: path)
    }
}
```

- [ ] **Step 5: Rodar os testes**

Run: `./swiftpm.sh test --filter 'PathToolsTests'`
Expected: PASS, `Executed 9 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 9 tests, with 0 failures`.

- [ ] **Step 6: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/.gitignore`
- `mac/swiftpm.sh`
- `mac/Package.swift`
- `mac/Tests/ClarkCoreTests/TemporaryDirectory.swift`
- `mac/Tests/ClarkCoreTests/PathToolsTests.swift`
- `mac/Sources/ClarkCore/Version.swift`
- `mac/Sources/ClarkCore/PathTools.swift`

---

### Task 2: Cores, tema e fonte de pixels

Porta os dados visuais do original que não dependem de AppKit: a cor (`RGB`), a paleta `dark` e a fonte de pixels 5x7, com as mesmas contas de largura e de corte.

**Files:**
- Create: `mac/Sources/ClarkCore/RGB.swift`
- Create: `mac/Sources/ClarkCore/Theme.swift`
- Create: `mac/Sources/ClarkCore/PixelFont.swift`
- Test: `mac/Tests/ClarkCoreTests/RGBThemeTests.swift`
- Test: `mac/Tests/ClarkCoreTests/PixelFontTests.swift`

**Interfaces:**
- Consumes: nada de tarefas anteriores.
- Produces:

```swift
// mac/Sources/ClarkCore/RGB.swift
public struct RGB: Equatable, Hashable, Sendable
    public let r: Double
    public let g: Double
    public let b: Double
    public static let black = RGB(r: 0, g: 0, b: 0)
    public static let white = RGB(r: 1, g: 1, b: 1)
    public init(r: Double, g: Double, b: Double)
    public init?(hex: String)
    public func mix(_ other: RGB, _ t: Double) -> RGB
    public func darkened(_ t: Double) -> RGB
    public var hex: String

// mac/Sources/ClarkCore/Theme.swift
public struct Theme: Sendable
    public static let names = ["dark", "white", "magick"]
    public let name: String
    public let bg: RGB
    public let bg2: RGB
    public let bg3: RGB
    public let bg4: RGB
    public let bg5: RGB
    public let shadow: RGB
    public let ink: RGB
    public let dim: RGB
    public let accent: RGB
    public let accentHi: RGB
    public let accentLo: RGB
    public let onAccent: RGB
    public let yellow: RGB
    public let green: RGB
    public let red: RGB
    public let agents: [RGB]
    public let term: [RGB]
    public static let dark
    public static func named(_ name: String) -> Theme

// mac/Sources/ClarkCore/PixelFont.swift
public enum PixelFont
    public static let columns = 5
    public static let rows = 7
    public static let advance = 6
    public static func normalize(_ text: String) -> String
    public static func textWidth(_ text: String, scale: Int) -> Int
    public static func fit(_ text: String, scale: Int, width: Int) -> String
    public static func pixels(_ text: String) -> [(x: Int, y: Int)]
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkCoreTests/RGBThemeTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class RGBThemeTests: XCTestCase {
    func testHexParsesWithAndWithoutHash() {
        XCTAssertEqual(RGB(hex: "#ff8000")?.hex, "#ff8000")
        XCTAssertEqual(RGB(hex: "FF8000")?.hex, "#ff8000")
    }

    func testInvalidHexIsRejected() {
        for bad in ["", "#", "#fff", "#gggggg", "#ff80000", "ff 800", "#ff80é0", "##ff800"] {
            XCTAssertNil(RGB(hex: bad), bad)
        }
    }

    func testMixAndDarkened() {
        let orange = RGB(hex: "#d97757")!
        XCTAssertEqual(orange.mix(.black, 0), orange)
        XCTAssertEqual(orange.mix(.black, 1), .black)
        XCTAssertEqual(RGB.white.darkened(0.5).hex, "#808080")
    }

    func testDarkThemeMatchesTheOriginalPalette() {
        let theme = Theme.dark
        XCTAssertEqual(theme.bg.hex, "#14100e")
        XCTAssertEqual(theme.bg2.hex, "#1f1915")
        XCTAssertEqual(theme.ink.hex, "#f0e6d6")
        XCTAssertEqual(theme.dim.hex, "#8a7d6e")
        XCTAssertEqual(theme.accent.hex, "#d97757")
        XCTAssertEqual(theme.yellow.hex, "#f2c14e")
        XCTAssertEqual(theme.green.hex, "#7fc86a")
        XCTAssertEqual(theme.red.hex, "#e05a4f")
        XCTAssertEqual(theme.agents.map(\.hex).first, "#d97757")
        XCTAssertEqual(theme.agents.count, 8)
        XCTAssertEqual(theme.term.count, 16)
        XCTAssertEqual(theme.term[15].hex, "#fff6e8")
    }

    func testEveryThemeNameResolves() {
        for name in Theme.names + ["neon", ""] {
            XCTAssertEqual(Theme.named(name).name, "dark", name)
        }
    }
}
```

**Arquivo:** `mac/Tests/ClarkCoreTests/PixelFontTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class PixelFontTests: XCTestCase {
    private let supported = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .:-!?/+><_%'()[]#*=,"

    private func points(_ text: String) -> [[Int]] {
        PixelFont.pixels(text).map { [$0.x, $0.y] }
    }

    func testNormalizeStripsAccentsAndUppercases() {
        XCTAssertEqual(PixelFont.normalize("Ação é"), "ACAO E")
        XCTAssertEqual(PixelFont.normalize("agent 1"), "AGENT 1")
        XCTAssertEqual(PixelFont.normalize("日本"), "")
    }

    func testTextWidthFollowsTheOriginalFormula() {
        XCTAssertEqual(PixelFont.textWidth("", scale: 2), 0)
        XCTAssertEqual(PixelFont.textWidth("A", scale: 1), 5)
        XCTAssertEqual(PixelFont.textWidth("AB", scale: 2), 22)
        XCTAssertEqual(PixelFont.textWidth("é", scale: 1), 5)
    }

    func testFitKeepsTextThatFits() {
        XCTAssertEqual(PixelFont.fit("agent 1", scale: 2, width: 200), "AGENT 1")
    }

    func testFitCutsWithEllipsis() {
        let cut = PixelFont.fit("ABCDEFGHIJKL", scale: 1, width: 40)
        XCTAssertEqual(cut, "ABC...")
        XCTAssertLessThanOrEqual(PixelFont.textWidth(cut, scale: 1), 40)
    }

    func testFitDropsTrailingSpaceBeforeEllipsis() {
        XCTAssertEqual(PixelFont.fit("AB  CDEFGHIJ", scale: 1, width: 40), "AB...")
    }

    func testFitWithNoRoomIsOnlyEllipsis() {
        XCTAssertEqual(PixelFont.fit("ABCDEF", scale: 1, width: 5), "...")
        XCTAssertEqual(PixelFont.fit("ABCDEF", scale: 2, width: 0), "...")
    }

    func testGlyphPixels() {
        let glyph = points("I")
        XCTAssertEqual(glyph.count, 11)
        XCTAssertEqual(glyph.filter { $0[1] == 0 }.map { $0[0] }, [1, 2, 3])
        XCTAssertTrue(points(" ").isEmpty)
        XCTAssertEqual(points("a"), points("A"))
    }

    func testSecondCharacterIsShiftedByTheAdvance() {
        let single = points("L")
        let double = points("LL")
        XCTAssertEqual(double.count, single.count * 2)
        XCTAssertEqual(Array(double.suffix(single.count)), single.map { [$0[0] + PixelFont.advance, $0[1]] })
    }

    func testUnknownCharacterUsesQuestionMark() {
        XCTAssertEqual(points("~"), points("?"))
        XCTAssertEqual(points("@"), points("?"))
    }

    func testEverySupportedGlyphFitsTheGrid() {
        for (index, character) in supported.enumerated() {
            for point in points(String(character)) {
                XCTAssertTrue((0..<PixelFont.columns).contains(point[0]), "\(character) em \(index)")
                XCTAssertTrue((0..<PixelFont.rows).contains(point[1]), "\(character) em \(index)")
            }
            if character != " " && character != "?" {
                XCTAssertNotEqual(points(String(character)), points("?"), "sem glifo: \(character)")
            }
        }
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkCoreTests/PixelFontTests.swift:8:9: error: cannot find 'PixelFont' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/ClarkCore/RGB.swift`

```swift
import Foundation

/// Cor em componentes de 0 a 1, sem depender de AppKit.
public struct RGB: Equatable, Hashable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double

    public static let black = RGB(r: 0, g: 0, b: 0)
    public static let white = RGB(r: 1, g: 1, b: 1)

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Aceita `#rrggbb` ou `rrggbb`. Qualquer outra forma devolve nil.
    public init?(hex: String) {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        let bytes = Array(digits.utf8)
        guard bytes.count == 6 else { return nil }
        var values: [Double] = []
        for i in stride(from: 0, to: 6, by: 2) {
            guard let high = RGB.nibble(bytes[i]), let low = RGB.nibble(bytes[i + 1]) else { return nil }
            values.append(Double(high * 16 + low) / 255)
        }
        self.init(r: values[0], g: values[1], b: values[2])
    }

    private static func nibble(_ byte: UInt8) -> Int? {
        switch byte {
        case 48...57: return Int(byte) - 48
        case 65...70: return Int(byte) - 55
        case 97...102: return Int(byte) - 87
        default: return nil
        }
    }

    /// Interpolação linear: `t = 0` devolve esta cor, `t = 1` devolve `other`.
    public func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    public func darkened(_ t: Double) -> RGB {
        mix(.black, t)
    }

    public var hex: String {
        func byte(_ value: Double) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }
}
```

**Arquivo:** `mac/Sources/ClarkCore/Theme.swift`

```swift
/// Paleta de um tema, portada de `THEMES` do original.
/// No M1 só existe `dark`; `white` e `magick` entram no M3.
public struct Theme: Sendable {
    /// Nomes aceitos no `config.json`.
    public static let names = ["dark", "white", "magick"]

    public let name: String
    public let bg: RGB
    public let bg2: RGB
    public let bg3: RGB
    public let bg4: RGB
    public let bg5: RGB
    public let shadow: RGB
    public let ink: RGB
    public let dim: RGB
    public let accent: RGB
    public let accentHi: RGB
    public let accentLo: RGB
    public let onAccent: RGB
    public let yellow: RGB
    public let green: RGB
    public let red: RGB
    /// Cores de empresa para a detecção automática.
    public let agents: [RGB]
    /// As 16 cores ANSI do terminal.
    public let term: [RGB]

    public static let dark = Theme(
        name: "dark",
        bg: hex("#14100e"), bg2: hex("#1f1915"), bg3: hex("#2a221d"), bg4: hex("#3a2f28"), bg5: hex("#4a3c33"),
        shadow: hex("#0a0807"), ink: hex("#f0e6d6"), dim: hex("#8a7d6e"),
        accent: hex("#d97757"), accentHi: hex("#e88a6a"), accentLo: hex("#b85c3e"), onAccent: hex("#14100e"),
        yellow: hex("#f2c14e"), green: hex("#7fc86a"), red: hex("#e05a4f"),
        agents: ["#d97757", "#5fb3b3", "#9b7bd8", "#7fc86a", "#f2c14e", "#e07aa8", "#5e9be0", "#e05a4f"].map(hex),
        term: ["#1a1410", "#e05a4f", "#7fc86a", "#f2c14e", "#5e9be0", "#b48ead", "#5fb3b3", "#d9cbb8",
               "#6b5f53", "#ff7a6b", "#a4e08f", "#ffd97a", "#8bb8f0", "#d7a8e0", "#8fd6d6", "#fff6e8"].map(hex)
    )

    /// Tema pelo nome do config. Enquanto só `dark` existe, todo nome devolve `dark`.
    public static func named(_ name: String) -> Theme {
        .dark
    }

    private static func hex(_ value: String) -> RGB {
        RGB(hex: value)!
    }
}
```

**Arquivo:** `mac/Sources/ClarkCore/PixelFont.swift`

```swift
import Foundation

/// Fonte bitmap 5x7 do original (`_FONT_SRC`), com as mesmas contas de largura e corte.
public enum PixelFont {
    public static let columns = 5
    public static let rows = 7
    /// Passo entre um caractere e o próximo, em pontos da fonte.
    public static let advance = 6

    private static let source: [Character: String] = [
        "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
        "C": "01110 10001 10000 10000 10000 10001 01110", "D": "11110 10001 10001 10001 10001 10001 11110",
        "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
        "G": "01110 10001 10000 10111 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
        "I": "01110 00100 00100 00100 00100 00100 01110", "J": "00111 00010 00010 00010 00010 10010 01100",
        "K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
        "M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 10001 11001 10101 10011 10001 10001",
        "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
        "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
        "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
        "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
        "W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
        "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
        "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
        "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11111 00010 00100 00010 00001 10001 01110",
        "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
        "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
        "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
        " ": "00000 00000 00000 00000 00000 00000 00000", ".": "00000 00000 00000 00000 00000 01100 01100",
        ":": "00000 01100 01100 00000 01100 01100 00000", "-": "00000 00000 00000 11111 00000 00000 00000",
        "!": "00100 00100 00100 00100 00100 00000 00100", "?": "01110 10001 00001 00010 00100 00000 00100",
        "/": "00001 00001 00010 00100 01000 10000 10000", "+": "00000 00100 00100 11111 00100 00100 00000",
        ">": "01000 00100 00010 00001 00010 00100 01000", "<": "00010 00100 01000 10000 01000 00100 00010",
        "_": "00000 00000 00000 00000 00000 00000 11111", "%": "11001 11001 00010 00100 01000 10011 10011",
        "'": "00100 00100 01000 00000 00000 00000 00000", "(": "00010 00100 01000 01000 01000 00100 00010",
        ")": "01000 00100 00010 00010 00010 00100 01000", "[": "01110 01000 01000 01000 01000 01000 01110",
        "]": "01110 00010 00010 00010 00010 00010 01110", "#": "01010 01010 11111 01010 11111 01010 01010",
        "*": "00000 00100 10101 01110 10101 00100 00000", "=": "00000 00000 11111 00000 11111 00000 00000",
        ",": "00000 00000 00000 00000 01100 00100 01000",
    ]

    /// Para cada caractere, as 7 linhas com os 5 pontos acesos ou apagados.
    private static let glyphs: [Unicode.Scalar: [[Bool]]] = {
        var table: [Unicode.Scalar: [[Bool]]] = [:]
        for (character, rows) in source {
            guard let scalar = character.unicodeScalars.first else { continue }
            table[scalar] = rows.split(separator: " ").map { row in row.map { $0 == "1" } }
        }
        return table
    }()

    /// Tira acentos, descarta o que não é ASCII e passa para maiúsculas (`norm` do original).
    public static func normalize(_ text: String) -> String {
        let ascii = text.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { $0.isASCII }
        return String(String.UnicodeScalarView(ascii)).uppercased()
    }

    /// Largura em pixels do texto na escala dada (`text_w` do original).
    public static func textWidth(_ text: String, scale: Int) -> Int {
        max(0, normalize(text).unicodeScalars.count * advance * scale - scale)
    }

    /// Corta o texto com `...` para caber em `width` pixels (`fit_text` do original).
    public static func fit(_ text: String, scale: Int, width: Int) -> String {
        let normalized = normalize(text)
        if textWidth(normalized, scale: scale) <= width { return normalized }
        let keep = max(0, (width + scale) / (advance * scale) - 3)
        var scalars = Array(normalized.unicodeScalars.prefix(keep))
        while let last = scalars.last, last.properties.isWhitespace { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars)) + "..."
    }

    /// Pontos acesos do texto em coordenadas da fonte (sem escala), origem no canto superior esquerdo.
    /// Caractere sem glifo usa o `?`.
    public static func pixels(_ text: String) -> [(x: Int, y: Int)] {
        var points: [(x: Int, y: Int)] = []
        let fallback = glyphs["?"]!
        for (index, scalar) in normalize(text).unicodeScalars.enumerated() {
            let glyph = glyphs[scalar] ?? fallback
            for (row, bits) in glyph.enumerated() {
                for (column, lit) in bits.enumerated() where lit {
                    points.append((x: index * advance + column, y: row))
                }
            }
        }
        return points
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'RGBThemeTests|PixelFontTests'`
Expected: PASS, `Executed 15 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 24 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkCoreTests/RGBThemeTests.swift`
- `mac/Tests/ClarkCoreTests/PixelFontTests.swift`
- `mac/Sources/ClarkCore/RGB.swift`
- `mac/Sources/ClarkCore/Theme.swift`
- `mac/Sources/ClarkCore/PixelFont.swift`

---

### Task 3: Grade dos painéis

As contas da grade de painéis, iguais às do original: quantas colunas para N agentes e o retângulo de cada painel.

**Files:**
- Create: `mac/Sources/ClarkCore/GridLayout.swift`
- Test: `mac/Tests/ClarkCoreTests/GridLayoutTests.swift`

**Interfaces:**
- Consumes: nada de tarefas anteriores.
- Produces:

```swift
// mac/Sources/ClarkCore/GridLayout.swift
public enum GridLayout
    public struct Cell: Equatable, Sendable
        public let row: Int
        public let column: Int
        public let span: Int
    public struct Frame: Equatable, Sendable
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    public static func columns(count: Int, width: Double, height: Double) -> Int
    public static func cells(count: Int, columns: Int) -> [Cell]
    public static func frames(count: Int, columns: Int, width: Double, height: Double, spacing: Double) -> [Frame]
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkCoreTests/GridLayoutTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class GridLayoutTests: XCTestCase {
    func testColumnsMatchTheOriginal() {
        XCTAssertEqual(GridLayout.columns(count: 0, width: 1360, height: 700), 0)
        // até 3 painéis numa janela larga ficam lado a lado
        XCTAssertEqual(GridLayout.columns(count: 1, width: 1360, height: 700), 1)
        XCTAssertEqual(GridLayout.columns(count: 2, width: 1360, height: 700), 2)
        XCTAssertEqual(GridLayout.columns(count: 3, width: 1360, height: 700), 3)
        // janela estreita ou mais de 3: teto da raiz quadrada
        XCTAssertEqual(GridLayout.columns(count: 2, width: 800, height: 800), 2)
        XCTAssertEqual(GridLayout.columns(count: 3, width: 800, height: 800), 2)
        let expected = [4: 2, 5: 3, 6: 3, 7: 3, 8: 3, 9: 3, 10: 4, 11: 4, 12: 4, 13: 4, 14: 4, 15: 4, 16: 4]
        for (count, columns) in expected {
            XCTAssertEqual(GridLayout.columns(count: count, width: 1360, height: 700), columns, "\(count)")
        }
    }

    func testZeroHeightDoesNotDivideByZero() {
        XCTAssertEqual(GridLayout.columns(count: 2, width: 1360, height: 0), 2)
    }

    func testLastCellTakesTheRestOfTheRow() {
        XCTAssertEqual(GridLayout.cells(count: 5, columns: 3), [
            .init(row: 0, column: 0, span: 1), .init(row: 0, column: 1, span: 1), .init(row: 0, column: 2, span: 1),
            .init(row: 1, column: 0, span: 1), .init(row: 1, column: 1, span: 2),
        ])
        XCTAssertEqual(GridLayout.cells(count: 3, columns: 2).last, .init(row: 1, column: 0, span: 2))
        XCTAssertEqual(GridLayout.cells(count: 4, columns: 2).last, .init(row: 1, column: 1, span: 1))
        XCTAssertTrue(GridLayout.cells(count: 0, columns: 3).isEmpty)
        XCTAssertTrue(GridLayout.cells(count: 3, columns: 0).isEmpty)
    }

    func testFrames() {
        XCTAssertEqual(GridLayout.frames(count: 2, columns: 2, width: 206, height: 100, spacing: 6), [
            .init(x: 0, y: 0, width: 100, height: 100), .init(x: 106, y: 0, width: 100, height: 100),
        ])
        XCTAssertEqual(GridLayout.frames(count: 3, columns: 2, width: 206, height: 206, spacing: 6).last,
                       .init(x: 0, y: 106, width: 206, height: 100))
        XCTAssertTrue(GridLayout.frames(count: 0, columns: 0, width: 100, height: 100, spacing: 6).isEmpty)
    }

    func testEveryPanelFitsFromOneToSixteen() {
        for count in 1...16 {
            let columns = GridLayout.columns(count: count, width: 1360, height: 700)
            let cells = GridLayout.cells(count: count, columns: columns)
            let frames = GridLayout.frames(count: count, columns: columns, width: 1360, height: 700, spacing: 6)
            XCTAssertEqual(cells.count, count)
            XCTAssertEqual(cells.last.map { $0.column + $0.span }, columns, "\(count)")
            XCTAssertEqual(frames.count, count)
            for frame in frames {
                XCTAssertGreaterThanOrEqual(frame.width, 1)
                XCTAssertGreaterThanOrEqual(frame.height, 1)
                XCTAssertLessThanOrEqual(frame.x + frame.width, 1360, "\(count)")
                XCTAssertLessThanOrEqual(frame.y + frame.height, 700, "\(count)")
            }
        }
    }

    func testTinyAreaNeverProducesEmptyFrames() {
        for frame in GridLayout.frames(count: 16, columns: 4, width: 10, height: 10, spacing: 6) {
            XCTAssertGreaterThanOrEqual(frame.width, 1)
            XCTAssertGreaterThanOrEqual(frame.height, 1)
        }
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkCoreTests/GridLayoutTests.swift:6:24: error: cannot find 'GridLayout' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/ClarkCore/GridLayout.swift`

```swift
/// Contas da grade de painéis, iguais às de `_layout_grid` do original.
public enum GridLayout {
    public struct Cell: Equatable, Sendable {
        public let row: Int
        public let column: Int
        /// Quantas colunas o painel ocupa. O último painel ocupa o resto da linha.
        public let span: Int
    }

    public struct Frame: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }

    /// Colunas para `count` painéis numa janela de `width` por `height`.
    public static func columns(count: Int, width: Double, height: Double) -> Int {
        guard count > 0 else { return 0 }
        if count <= 3 && width / max(1, height) > 1.5 { return count }
        return Int(Double(count).squareRoot().rounded(.up))
    }

    public static func cells(count: Int, columns: Int) -> [Cell] {
        guard count > 0, columns > 0 else { return [] }
        return (0..<count).map { index in
            let column = index % columns
            return Cell(row: index / columns, column: column, span: index == count - 1 ? columns - column : 1)
        }
    }

    /// Retângulos dos painéis numa área de `width` por `height`, origem no canto superior esquerdo.
    public static func frames(count: Int, columns: Int, width: Double, height: Double, spacing: Double) -> [Frame] {
        let cells = cells(count: count, columns: columns)
        guard let last = cells.last else { return [] }
        let rows = last.row + 1
        let cellWidth = max(1, ((width - spacing * Double(columns - 1)) / Double(columns)).rounded(.down))
        let cellHeight = max(1, ((height - spacing * Double(rows - 1)) / Double(rows)).rounded(.down))
        return cells.map { cell in
            Frame(x: Double(cell.column) * (cellWidth + spacing),
                  y: Double(cell.row) * (cellHeight + spacing),
                  width: cellWidth * Double(cell.span) + spacing * Double(cell.span - 1),
                  height: cellHeight)
        }
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'GridLayoutTests'`
Expected: PASS, `Executed 6 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 30 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkCoreTests/GridLayoutTests.swift`
- `mac/Sources/ClarkCore/GridLayout.swift`

---

### Task 4: Máquina de estados do agente

A máquina de estados do agente (BOOT, WORKING, IDLE, DONE, EXITED), com os tempos do original e o relógio injetado. Assim cada linha da tabela de estados do spec vira um teste que não espera tempo de verdade.

**Files:**
- Create: `mac/Sources/ClarkCore/AgentStateMachine.swift`
- Test: `mac/Tests/ClarkCoreTests/AgentStateMachineTests.swift`

**Interfaces:**
- Consumes: nada de tarefas anteriores.
- Produces:

```swift
// mac/Sources/ClarkCore/AgentStateMachine.swift
public enum AgentState: String, Sendable, CaseIterable
    case boot = "BOOT"
    case working = "WORKING"
    case idle = "IDLE"
    case done = "DONE"
    case exited = "EXITED"
public struct AgentStateMachine: Sendable
    public static let inputQuiet = 0.3
    public static let workingWindow = 1.0
    public static let minWork = 2.5
    public static let bootTime = 2.0
    public static let focusMute = 0.3
    public static let resizeMute = 0.5
    public static let layoutMute = 0.8
    public private(set) var state: AgentState
    public private(set) var hasInput = false
    public private(set) var lastChange = -Double.infinity
    public init(now: Double)
    public mutating func spawned(now: Double)
    public mutating func mute(_ seconds: Double, now: Double)
    public mutating func userInput(now: Double)
    public mutating func output(now: Double)
    public mutating func focused(now: Double)
    public mutating func resized(now: Double)
    public mutating func layoutChanged(now: Double)
    public mutating func bell(watched: Bool) -> Bool
    public mutating func tick(now: Double, watched: Bool) -> Bool
    public mutating func exited()
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkCoreTests/AgentStateMachineTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class AgentStateMachineTests: XCTestCase {
    /// Agente que saiu do BOOT e está parado em IDLE no instante 5.
    private func idleMachine() -> AgentStateMachine {
        var machine = AgentStateMachine(now: 0)
        machine.tick(now: 5, watched: false)
        XCTAssertEqual(machine.state, .idle)
        return machine
    }

    /// Faz o agente trabalhar de `start` até `end` com saída a cada 0,5 s e tique a cada 0,1 s.
    private func work(_ machine: inout AgentStateMachine, from start: Double, to end: Double, watched: Bool = false) {
        var now = start
        while now <= end + 0.0001 {
            machine.output(now: now)
            for step in 1...5 { machine.tick(now: now + Double(step) * 0.1, watched: watched) }
            now += 0.5
        }
    }

    func testBootBecomesIdleAfterTwoSeconds() {
        var machine = AgentStateMachine(now: 0)
        XCTAssertEqual(machine.state, .boot)
        XCTAssertFalse(machine.tick(now: 1.9, watched: false))
        XCTAssertEqual(machine.state, .boot)
        XCTAssertFalse(machine.tick(now: 2.1, watched: false))
        XCTAssertEqual(machine.state, .idle)
    }

    func testOutputMakesItWorking() {
        var machine = idleMachine()
        machine.output(now: 6)
        machine.tick(now: 6.1, watched: false)
        XCTAssertEqual(machine.state, .working)
        XCTAssertEqual(machine.lastChange, 6)
    }

    func testOutputRightAfterAKeyIsEcho() {
        var machine = idleMachine()
        machine.userInput(now: 6)
        machine.output(now: 6.2)
        machine.tick(now: 6.25, watched: false)
        XCTAssertEqual(machine.state, .idle)
        machine.output(now: 6.4)
        machine.tick(now: 6.45, watched: false)
        XCTAssertEqual(machine.state, .working)
    }

    func testLongWorkAfterInputEndsInDoneAndNotifies() {
        var machine = idleMachine()
        machine.userInput(now: 10)
        work(&machine, from: 10.5, to: 13.5)
        XCTAssertEqual(machine.state, .working)
        XCTAssertFalse(machine.tick(now: 14.4, watched: false))
        XCTAssertTrue(machine.tick(now: 14.6, watched: false))
        XCTAssertEqual(machine.state, .done)
        XCTAssertFalse(machine.tick(now: 14.7, watched: false), "notifica uma vez só")
        XCTAssertEqual(machine.state, .done)
    }

    func testLongWorkWhileWatchedEndsInIdle() {
        var machine = idleMachine()
        machine.userInput(now: 10)
        work(&machine, from: 10.5, to: 13.5, watched: true)
        XCTAssertFalse(machine.tick(now: 14.6, watched: true))
        XCTAssertEqual(machine.state, .idle)
    }

    func testLongWorkWithoutInputEndsInIdle() {
        var machine = idleMachine()
        work(&machine, from: 10.5, to: 13.5)
        XCTAssertFalse(machine.tick(now: 14.6, watched: false))
        XCTAssertEqual(machine.state, .idle)
    }

    func testShortWorkEndsInIdle() {
        var machine = idleMachine()
        machine.userInput(now: 10)
        work(&machine, from: 10.5, to: 11.5)
        XCTAssertFalse(machine.tick(now: 12.6, watched: false))
        XCTAssertEqual(machine.state, .idle)
    }

    func testBellNotifiesUnlessWatched() {
        var machine = idleMachine()
        XCTAssertTrue(machine.bell(watched: false))
        XCTAssertEqual(machine.state, .done)

        var watched = idleMachine()
        watched.output(now: 6)
        watched.tick(now: 6.1, watched: true)
        XCTAssertEqual(watched.state, .working)
        XCTAssertFalse(watched.bell(watched: true))
        XCTAssertEqual(watched.state, .idle)
    }

    func testKeyAndFocusClearDone() {
        var byKey = idleMachine()
        byKey.bell(watched: false)
        byKey.userInput(now: 6)
        XCTAssertEqual(byKey.state, .idle)
        XCTAssertTrue(byKey.hasInput)

        var byFocus = idleMachine()
        byFocus.bell(watched: false)
        byFocus.focused(now: 6)
        XCTAssertEqual(byFocus.state, .idle)
    }

    func testFocusSilencesOutputForThreeTenths() {
        var machine = idleMachine()
        machine.focused(now: 6)
        machine.output(now: 6.2)
        machine.tick(now: 6.25, watched: true)
        XCTAssertEqual(machine.state, .idle)
        machine.output(now: 6.35)
        machine.tick(now: 6.4, watched: true)
        XCTAssertEqual(machine.state, .working)
    }

    func testResizeSilencesForHalfASecond() {
        var machine = idleMachine()
        machine.resized(now: 6)
        machine.output(now: 6.4)
        machine.tick(now: 6.45, watched: false)
        XCTAssertEqual(machine.state, .idle)
        machine.output(now: 6.6)
        machine.tick(now: 6.65, watched: false)
        XCTAssertEqual(machine.state, .working)
    }

    func testLayoutChangeSilencesForEightTenths() {
        var machine = idleMachine()
        machine.layoutChanged(now: 6)
        machine.output(now: 6.7)
        machine.tick(now: 6.75, watched: false)
        XCTAssertEqual(machine.state, .idle)
        machine.output(now: 6.9)
        machine.tick(now: 6.95, watched: false)
        XCTAssertEqual(machine.state, .working)
    }

    func testShorterSilenceDoesNotCutALongerOne() {
        var machine = idleMachine()
        machine.layoutChanged(now: 6)
        machine.focused(now: 6.1)
        machine.output(now: 6.7)
        machine.tick(now: 6.75, watched: false)
        XCTAssertEqual(machine.state, .idle)
    }

    func testExitedIsFinalUntilRespawn() {
        var machine = idleMachine()
        machine.exited()
        XCTAssertEqual(machine.state, .exited)
        machine.output(now: 6)
        XCTAssertFalse(machine.tick(now: 6.1, watched: false))
        XCTAssertEqual(machine.state, .exited)
        XCTAssertFalse(machine.bell(watched: false))
        XCTAssertEqual(machine.state, .exited)

        machine.userInput(now: 7)
        machine.spawned(now: 8)
        XCTAssertEqual(machine.state, .boot)
        XCTAssertFalse(machine.hasInput)
        machine.tick(now: 9, watched: false)
        XCTAssertEqual(machine.state, .boot, "o BOOT conta a partir do respawn")
        machine.tick(now: 10.1, watched: false)
        XCTAssertEqual(machine.state, .idle)
    }

    func testExitWhileWorkingDoesNotNotify() {
        var machine = idleMachine()
        machine.userInput(now: 10)
        work(&machine, from: 10.5, to: 13.5)
        machine.exited()
        XCTAssertFalse(machine.tick(now: 14.6, watched: false))
        XCTAssertEqual(machine.state, .exited)
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkCoreTests/AgentStateMachineTests.swift:6:35: error: cannot find type 'AgentStateMachine' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/ClarkCore/AgentStateMachine.swift`

```swift
public enum AgentState: String, Sendable, CaseIterable {
    case boot = "BOOT"
    case working = "WORKING"
    case idle = "IDLE"
    case done = "DONE"
    case exited = "EXITED"
}

/// Estado de um agente a partir dos eventos do terminal. Porta de `AgentPane.update`,
/// `_attention`, `_on_commit`, `_on_contents` e `_on_focus` do original, com o relógio injetado.
public struct AgentStateMachine: Sendable {
    /// Saída a menos disso de uma tecla é eco da digitação, não trabalho.
    public static let inputQuiet = 0.3
    /// Houve saída há menos disso: o agente está trabalhando.
    public static let workingWindow = 1.0
    /// Trabalho mais curto que isso termina em IDLE, sem aviso.
    public static let minWork = 2.5
    public static let bootTime = 2.0
    public static let focusMute = 0.3
    public static let resizeMute = 0.5
    public static let layoutMute = 0.8

    public private(set) var state: AgentState = .boot
    public private(set) var hasInput = false
    /// Momento da última saída que contou como atividade.
    public private(set) var lastChange = -Double.infinity
    private var spawnTime: Double
    private var lastInput = -Double.infinity
    private var muteUntil = -Double.infinity
    private var workStart: Double?

    public init(now: Double) {
        spawnTime = now
    }

    /// O processo foi (re)aberto.
    public mutating func spawned(now: Double) {
        state = .boot
        spawnTime = now
        hasInput = false
        workStart = nil
    }

    /// Ignora a saída do terminal pelos próximos `seconds`.
    public mutating func mute(_ seconds: Double, now: Double) {
        muteUntil = max(muteUntil, now + seconds)
    }

    public mutating func userInput(now: Double) {
        lastInput = now
        hasInput = true
        if state == .done { state = .idle }
    }

    public mutating func output(now: Double) {
        if now < muteUntil || now - lastInput < Self.inputQuiet { return }
        lastChange = now
    }

    public mutating func focused(now: Double) {
        mute(Self.focusMute, now: now)
        if state == .done { state = .idle }
    }

    public mutating func resized(now: Double) {
        mute(Self.resizeMute, now: now)
    }

    public mutating func layoutChanged(now: Double) {
        mute(Self.layoutMute, now: now)
    }

    /// Sino do terminal. Devolve true quando o agente deve notificar.
    @discardableResult
    public mutating func bell(watched: Bool) -> Bool {
        attention(watched: watched)
    }

    /// Tique de 100 ms. Devolve true quando o agente deve notificar.
    @discardableResult
    public mutating func tick(now: Double, watched: Bool) -> Bool {
        if state == .exited { return false }
        if now - lastChange < Self.workingWindow {
            if state != .working {
                state = .working
                workStart = now
            }
            return false
        }
        if state == .working {
            let worked = now - (workStart ?? now)
            workStart = nil
            if hasInput && worked > Self.minWork && !watched {
                return attention(watched: watched)
            }
            state = .idle
            return false
        }
        if state == .boot && now - spawnTime > Self.bootTime {
            state = .idle
        }
        return false
    }

    public mutating func exited() {
        state = .exited
        workStart = nil
    }

    private mutating func attention(watched: Bool) -> Bool {
        if watched || state == .exited {
            if state == .working { state = .idle }
            return false
        }
        state = .done
        return true
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'AgentStateMachineTests'`
Expected: PASS, `Executed 15 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 45 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkCoreTests/AgentStateMachineTests.swift`
- `mac/Sources/ClarkCore/AgentStateMachine.swift`

---

### Task 5: Empresas e política de ambiente

O isolamento por empresa: de que empresa é uma pasta (`CompanyResolver`), que variáveis um agente dessa empresa recebe (`EnvPolicy`) e como ler a saída do shell de login (`ShellEnvParser`).

**Files:**
- Create: `mac/Sources/ClarkCore/EnvPolicy.swift`
- Create: `mac/Sources/ClarkCore/CompanyResolver.swift`
- Create: `mac/Sources/ClarkCore/ShellEnvParser.swift`
- Test: `mac/Tests/ClarkCoreTests/EnvPolicyTests.swift`
- Test: `mac/Tests/ClarkCoreTests/CompanyResolverTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 1: `PathTools`
  - Task 2: `RGB`, `Theme`
- Produces:

```swift
// mac/Sources/ClarkCore/EnvPolicy.swift
public struct AgentEnvironment: Equatable, Sendable
    public let variables: [String: String]
    public let removed: [String]
    public var asArray: [String]
public enum EnvPolicy
    public static let parentSessionVars
    public static let secretPatterns = [ "*KEY*", "*TOKEN*", "*SECRET*", "*PASSWORD*", "*PASSWD*", "*CREDENTIAL*", "AWS_*", "PG*", "*_DSN", "DATABASE_URL", ]
    public static func isValidName(_ name: String) -> Bool
    public static func matches(_ name: String, pattern: String) -> Bool
    public static func isSecret(_ name: String) -> Bool
    public static func apply(base: [String: String], globalAllow: [String], company: Company, agentName: String) -> AgentEnvironment

// mac/Sources/ClarkCore/CompanyResolver.swift
public struct Company: Equatable, Sendable
    public let name: String
    public let color: RGB
    public let envAllow: [String]
    public init(name: String, color: RGB, envAllow: [String])
public struct CompanyResolver: Sendable
    public static let fallbackName = "AVULSO"
    public static let defaultRoots = ["~/Projetos"]
    public static let toneStep = 0.15
    public static let toneCount = 4
    public let globalEnvAllow: [String]
    public let warnings: [String]
    public init(json: Data?, palette: [RGB], fallbackColor: RGB, canonicalize: (String) -> String)
    public func resolve(canonicalPath: String) -> Company
    public static func stableIndex(_ name: String, count: Int) -> Int
    public static func tone(_ base: RGB, index: Int) -> RGB

// mac/Sources/ClarkCore/ShellEnvParser.swift
public enum ShellEnvParser
    public static let marker = "__CLARK_ENV_BEGIN__"
    public static let command = "printf '%s\\0' \(marker); /usr/bin/env -0"
    public static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    static let transient: Set<String>
    public static func parse(_ data: Data) -> [String: String]?
    public static func fallback(processEnvironment: [String: String]) -> [String: String]
```

**Review Focus:**
- Item 2 (`path` que cobre uma root): `testCompanyPathThatCoversARootWarns`, em `CompanyResolverTests.swift`.

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkCoreTests/EnvPolicyTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class EnvPolicyTests: XCTestCase {
    private func company(_ name: String = "A", allow: [String] = []) -> Company {
        Company(name: name, color: .white, envAllow: allow)
    }

    private func apply(_ base: [String: String], globalAllow: [String] = [], company: Company? = nil) -> AgentEnvironment {
        EnvPolicy.apply(base: base, globalAllow: globalAllow, company: company ?? self.company(), agentName: "AGENT 1")
    }

    func testValidNames() {
        for name in ["A", "_x1", "a_B", "PATH"] { XCTAssertTrue(EnvPolicy.isValidName(name), name) }
        for name in ["", "1A", "A-B", "A B", "Á", "A=B", "A\n"] { XCTAssertFalse(EnvPolicy.isValidName(name), name) }
    }

    func testPatternMatching() {
        XCTAssertTrue(EnvPolicy.matches("MY_API_KEY", pattern: "*KEY*"))
        XCTAssertTrue(EnvPolicy.matches("aws_region", pattern: "AWS_*"))
        XCTAssertTrue(EnvPolicy.matches("PGHOST", pattern: "PG*"))
        XCTAssertTrue(EnvPolicy.matches("SENTRY_DSN", pattern: "*_DSN"))
        XCTAssertTrue(EnvPolicy.matches("DATABASE_URL", pattern: "DATABASE_URL"))
        XCTAssertTrue(EnvPolicy.matches("abc", pattern: "a*c"))
        XCTAssertTrue(EnvPolicy.matches("", pattern: "*"))
        XCTAssertFalse(EnvPolicy.matches("DSN", pattern: "*_DSN"))
        XCTAssertFalse(EnvPolicy.matches("DATABASE_URL_X", pattern: "DATABASE_URL"))
        XCTAssertFalse(EnvPolicy.matches("GPG_TTY", pattern: "PG*"))
        XCTAssertFalse(EnvPolicy.matches("abd", pattern: "a*c"))
        XCTAssertFalse(EnvPolicy.matches("PATH", pattern: "*KEY*"))
    }

    func testEverySecretPatternRemoves() {
        let secrets = ["OPENAI_API_KEY", "GITHUB_TOKEN", "APP_SECRET", "DB_PASSWORD", "MYSQL_PASSWD",
                       "GOOGLE_APPLICATION_CREDENTIALS", "AWS_PROFILE", "PGPASSFILE", "SENTRY_DSN", "DATABASE_URL",
                       "npm_config_authtoken"]
        XCTAssertEqual(secrets.count, EnvPolicy.secretPatterns.count + 1)
        var base = ["PATH": "/usr/bin", "HOME": "/Users/eu", "LANG": "pt_BR.UTF-8", "EDITOR": "vim"]
        for name in secrets { base[name] = "valor-\(name)" }
        let result = apply(base)
        for name in secrets { XCTAssertNil(result.variables[name], name) }
        XCTAssertEqual(result.removed, secrets.sorted())
        for name in ["PATH", "HOME", "LANG", "EDITOR"] { XCTAssertEqual(result.variables[name], base[name]) }
    }

    func testEachPatternIsExercised() {
        for pattern in EnvPolicy.secretPatterns {
            let sample = pattern.replacingOccurrences(of: "*", with: "X")
            XCTAssertTrue(EnvPolicy.isSecret(sample), pattern)
            XCTAssertTrue(EnvPolicy.isSecret(sample.lowercased()), pattern)
        }
    }

    func testGlobalAndCompanyAllowBringNamesBack() {
        let base = ["PATH": "/usr/bin", "GLOBAL_TOKEN": "g", "A_API_KEY": "a", "OTHER_KEY": "o"]
        let result = apply(base, globalAllow: ["GLOBAL_TOKEN"], company: company(allow: ["A_API_KEY"]))
        XCTAssertEqual(result.variables["GLOBAL_TOKEN"], "g")
        XCTAssertEqual(result.variables["A_API_KEY"], "a")
        XCTAssertNil(result.variables["OTHER_KEY"])
        XCTAssertEqual(result.removed, ["OTHER_KEY"])
    }

    func testVariableAllowedForOneCompanyDoesNotReachAnother() {
        let base = ["PATH": "/usr/bin", "A_API_KEY": "segredo-da-a"]
        let a = apply(base, company: company("A", allow: ["A_API_KEY"]))
        let b = apply(base, company: company("B", allow: ["B_API_KEY"]))
        XCTAssertEqual(a.variables["A_API_KEY"], "segredo-da-a")
        XCTAssertNil(b.variables["A_API_KEY"])
        XCTAssertFalse(b.asArray.joined().contains("segredo-da-a"))
        XCTAssertEqual(b.removed, ["A_API_KEY"])
    }

    func testAllowIsCaseSensitive() {
        let result = apply(["PATH": "/usr/bin", "A_API_KEY": "a"], globalAllow: ["a_api_key"])
        XCTAssertNil(result.variables["A_API_KEY"])
    }

    func testParentSessionVariablesNeverComeBack() {
        XCTAssertEqual(EnvPolicy.parentSessionVars.count, 9)
        var base = ["PATH": "/usr/bin"]
        for name in EnvPolicy.parentSessionVars { base[name] = "1" }
        let result = apply(base, globalAllow: EnvPolicy.parentSessionVars,
                           company: company(allow: EnvPolicy.parentSessionVars))
        for name in EnvPolicy.parentSessionVars { XCTAssertNil(result.variables[name], name) }
        XCTAssertEqual(result.removed, [], "a lista de removidos é só dos padrões de segredo")
    }

    func testClarkVariablesAreSet() {
        let result = apply(["PATH": "/usr/bin", "TERM": "dumb", "CLARK_COMPANY": "falsa"],
                           company: company("EmpresaA"))
        XCTAssertEqual(result.variables["TERM"], "xterm-256color")
        XCTAssertEqual(result.variables["COLORTERM"], "truecolor")
        XCTAssertEqual(result.variables["CLARK_AGENT"], "AGENT 1")
        XCTAssertEqual(result.variables["CLARK_COMPANY"], "EmpresaA")
    }

    func testAsArrayIsSortedNameEqualsValue() {
        let result = apply(["PATH": "/usr/bin", "B": "x=y"])
        XCTAssertEqual(result.asArray, ["B=x=y", "CLARK_AGENT=AGENT 1", "CLARK_COMPANY=A", "COLORTERM=truecolor",
                                        "PATH=/usr/bin", "TERM=xterm-256color"])
    }
}

final class ShellEnvParserTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }
    private var marker: String { ShellEnvParser.marker }

    func testParsesWhatComesAfterTheMarker() {
        let output = "aviso do zshrc\nMOTD=nao e variavel\n\(marker)\0PATH=/opt/homebrew/bin:/usr/bin\0HOME=/Users/eu\0"
            + "MULTI=linha 1\nlinha 2\0VAZIA=\0COM_IGUAL=a=b=c\0"
        XCTAssertEqual(ShellEnvParser.parse(data(output)), [
            "PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/eu",
            "MULTI": "linha 1\nlinha 2", "VAZIA": "", "COM_IGUAL": "a=b=c",
        ])
    }

    func testDropsVariablesOfTheCaptureShell() {
        let output = "\(marker)\0PATH=/usr/bin\0PWD=/x\0OLDPWD=/y\0SHLVL=2\0_=/usr/bin/env\0"
        XCTAssertEqual(ShellEnvParser.parse(data(output)), ["PATH": "/usr/bin"])
    }

    func testSkipsBrokenEntries() {
        var output = data("\(marker)\0PATH=/usr/bin\0SEM_IGUAL\0=sem_nome\0")
        output.append(contentsOf: [0x42, 0x3d, 0xff, 0xfe, 0x00])
        output.append(data("OK=1\0"))
        XCTAssertEqual(ShellEnvParser.parse(output), ["PATH": "/usr/bin", "OK": "1"])
    }

    func testCaptureWithoutMarkerOrPathIsInvalid() {
        XCTAssertNil(ShellEnvParser.parse(data("PATH=/usr/bin\0HOME=/Users/eu\0")))
        XCTAssertNil(ShellEnvParser.parse(data("\(marker)\0HOME=/Users/eu\0")))
        XCTAssertNil(ShellEnvParser.parse(data("\(marker)\0PATH=\0")))
        XCTAssertNil(ShellEnvParser.parse(data("\(marker)")))
        XCTAssertNil(ShellEnvParser.parse(Data()))
    }

    func testFallbackUsesTheDefaultPath() {
        let fallback = ShellEnvParser.fallback(processEnvironment: ["HOME": "/Users/eu", "PATH": "/x", "PWD": "/y", "SHLVL": "1"])
        XCTAssertEqual(fallback, ["HOME": "/Users/eu", "PATH": ShellEnvParser.defaultPath])
    }

    func testCommandPrintsTheMarkerThenTheEnvironment() {
        XCTAssertEqual(ShellEnvParser.command, "printf '%s\\0' __CLARK_ENV_BEGIN__; /usr/bin/env -0")
    }
}
```

**Arquivo:** `mac/Tests/ClarkCoreTests/CompanyResolverTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class CompanyResolverTests: XCTestCase {
    private let home = "/Users/eu"
    private let palette = Theme.dark.agents
    private let fallback = Theme.dark.dim

    private func resolver(_ json: String?) -> CompanyResolver {
        CompanyResolver(json: json.map { Data($0.utf8) }, palette: palette, fallbackColor: fallback) {
            PathTools.absolute($0, base: "/", home: self.home)
        }
    }

    func testWithoutFileTheFirstFolderUnderProjetosIsTheCompany() {
        let resolver = resolver(nil)
        let company = resolver.resolve(canonicalPath: "/Users/eu/Projetos/EmpresaA/api/src")
        XCTAssertEqual(company.name, "EmpresaA")
        XCTAssertEqual(company.color, palette[CompanyResolver.stableIndex("EmpresaA", count: palette.count)])
        XCTAssertEqual(company.envAllow, [])
        XCTAssertTrue(resolver.warnings.isEmpty)
        XCTAssertTrue(resolver.globalEnvAllow.isEmpty)
    }

    func testOutsideTheRootsIsAvulso() {
        let resolver = resolver(nil)
        for path in ["/Users/eu/Projetos", "/Users/eu/Documents/x", "/", "/Users/eu/ProjetosX/y"] {
            let company = resolver.resolve(canonicalPath: path)
            XCTAssertEqual(company.name, CompanyResolver.fallbackName, path)
            XCTAssertEqual(company.color, fallback, path)
        }
    }

    func testLongestExplicitPrefixWins() {
        let resolver = resolver("""
        {"companies": [
          {"name": "A", "paths": ["~/Projetos/A"], "color": "#5fb3b3", "env_allow": ["A_API_KEY"]},
          {"name": "B", "paths": ["~/Projetos/A/sub", "/opt/b"]}
        ]}
        """)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/sub/x").name, "B")
        XCTAssertEqual(resolver.resolve(canonicalPath: "/opt/b").name, "B")
        let a = resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/outro")
        XCTAssertEqual(a.name, "A")
        XCTAssertEqual(a.color.hex, "#5fb3b3")
        XCTAssertEqual(a.envAllow, ["A_API_KEY"])
        XCTAssertTrue(resolver.warnings.isEmpty)
    }

    func testExplicitPrefixStopsAtTheFolderBoundary() {
        let resolver = resolver(#"{"companies": [{"name": "A", "paths": ["~/Projetos/A"], "env_allow": ["A_KEY"]}]}"#)
        let other = resolver.resolve(canonicalPath: "/Users/eu/Projetos/AB/api")
        XCTAssertEqual(other.name, "AB")
        XCTAssertEqual(other.envAllow, [])
    }

    func testDetectedCompanyNeverInheritsEnvAllowByName() {
        let resolver = resolver(#"{"companies": [{"name": "X", "paths": ["~/work/x"], "env_allow": ["X_KEY"]}]}"#)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/work/x/api").envAllow, ["X_KEY"])
        let detected = resolver.resolve(canonicalPath: "/Users/eu/Projetos/X/api")
        XCTAssertEqual(detected.name, "X")
        XCTAssertEqual(detected.envAllow, [])
    }

    func testCustomRootsAndTheDeepestRootWins() {
        let resolver = resolver(#"{"roots": ["~/work", "~/work/clientes"]}"#)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/work/clientes/acme/api").name, "acme")
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/work/interno/api").name, "interno")
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A").name, CompanyResolver.fallbackName)
    }

    func testCompanyPathThatCoversARootWarns() {
        // `~` ou a própria root como path: a empresa engole as pastas de todas as outras,
        // e o `env_allow` dela chega aos agentes de qualquer uma.
        let resolver = resolver("""
        {"roots": ["~/Projetos", "~/work"], "companies": [
          {"name": "Tudo", "paths": ["~", "~/Projetos"], "env_allow": ["TUDO_KEY"]},
          {"name": "A", "paths": ["~/Projetos/A"]},
          {"name": "W", "paths": ["~/work"]}
        ]}
        """)
        XCTAssertEqual(resolver.warnings, [
            "companies.json: path da empresa 1 cobre uma root inteira",
            "companies.json: path da empresa 3 cobre uma root inteira",
        ])
        // O aviso não muda a regra: o path explícito continua valendo.
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/B/api").envAllow, ["TUDO_KEY"])
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/api").name, "A")
    }

    func testBrokenEntriesAreIgnoredWithWarnings() {
        let resolver = resolver("""
        {"roots": "~/Projetos", "env_allow": "X", "companies": [
          {"paths": ["~/a"]},
          {"name": "  ", "paths": ["~/b"]},
          {"name": "SemPasta"},
          {"name": "Raiz", "paths": ["/"]},
          {"name": "Cor", "paths": ["~/cor"], "color": "vermelho"},
          "texto"
        ]}
        """)
        XCTAssertEqual(resolver.warnings.count, 8)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/a").name, CompanyResolver.fallbackName)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/etc").name, CompanyResolver.fallbackName)
        let colored = resolver.resolve(canonicalPath: "/Users/eu/cor")
        XCTAssertEqual(colored.name, "Cor")
        XCTAssertEqual(colored.color, palette[CompanyResolver.stableIndex("Cor", count: palette.count)])
        // roots inválido mantém o padrão
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/Z/x").name, "Z")
    }

    func testRootOfTheDiskIsNeverARoot() {
        let resolver = resolver(#"{"roots": ["/"]}"#)
        XCTAssertEqual(resolver.warnings.count, 1)
        XCTAssertEqual(resolver.resolve(canonicalPath: "/etc/x").name, CompanyResolver.fallbackName)
    }

    func testInvalidJSONKeepsAutomaticDetection() {
        for bad in ["{", "[]", "", "42"] {
            let resolver = resolver(bad)
            XCTAssertEqual(resolver.warnings.count, 1, bad)
            XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/x").name, "A", bad)
        }
    }

    func testEnvAllowKeepsOnlyValidNamesAndWarningsNeverEchoValues() {
        let resolver = resolver("""
        {"env_allow": ["OK_NAME", "sk-segredo colado", 3, "CLAUDECODE"],
         "companies": [{"name": "A", "paths": ["~/a"], "env_allow": ["A_KEY", "tambem-segredo", "CLAUDE_CODE_SESSION_ID"]}]}
        """)
        XCTAssertEqual(resolver.globalEnvAllow, ["OK_NAME"])
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/a").envAllow, ["A_KEY"])
        XCTAssertEqual(resolver.warnings.count, 5)
        let text = resolver.warnings.joined(separator: "\n")
        XCTAssertFalse(text.contains("segredo"))
    }

    func testStableIndexDoesNotChangeBetweenRuns() {
        XCTAssertEqual(CompanyResolver.stableIndex("a", count: 8), 4)
        XCTAssertEqual(CompanyResolver.stableIndex("", count: 8), 5)
        XCTAssertEqual(CompanyResolver.stableIndex("qualquer", count: 0), 0)
        let precomposed = "Ação".precomposedStringWithCanonicalMapping
        let decomposed = "Ação".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(precomposed.utf8), Array(decomposed.utf8))
        XCTAssertEqual(CompanyResolver.stableIndex(precomposed, count: 8),
                       CompanyResolver.stableIndex(decomposed, count: 8))
    }

    func testEmptyPaletteUsesTheFallbackColor() {
        let resolver = CompanyResolver(json: nil, palette: [], fallbackColor: fallback) {
            PathTools.absolute($0, base: "/", home: self.home)
        }
        XCTAssertEqual(resolver.resolve(canonicalPath: "/Users/eu/Projetos/A/x").color, fallback)
    }

    func testToneDarkensInFourSteps() {
        let base = RGB(hex: "#5fb3b3")!
        XCTAssertEqual(CompanyResolver.tone(base, index: 0), base)
        XCTAssertEqual(CompanyResolver.tone(base, index: 1), base.darkened(0.15))
        XCTAssertEqual(CompanyResolver.tone(base, index: 3), base.darkened(0.15 * 3))
        XCTAssertEqual(CompanyResolver.tone(base, index: 4), base)
        XCTAssertEqual(CompanyResolver.tone(base, index: -1), base.darkened(0.15 * 3))
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkCoreTests/CompanyResolverTests.swift:9:47: error: cannot find type 'CompanyResolver' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/ClarkCore/EnvPolicy.swift`

```swift
import Foundation

/// Ambiente final de um agente e os nomes que ficaram de fora por parecerem segredo.
public struct AgentEnvironment: Equatable, Sendable {
    public let variables: [String: String]
    /// Só nomes, em ordem alfabética. Valores nunca saem daqui.
    public let removed: [String]

    /// Formato `NOME=valor` que o `LocalProcess` do SwiftTerm espera.
    public var asArray: [String] {
        variables.map { "\($0.key)=\($0.value)" }.sorted()
    }
}

public enum EnvPolicy {
    /// Variáveis de sessão do Claude Code que abriu o CLARK (`PARENT_SESSION_VARS` do original).
    /// Se chegassem ao agente, ele se acharia uma subsessão. Nunca voltam, nem por `env_allow`.
    public static let parentSessionVars = [
        "CLAUDECODE", "CLAUDE_PID", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID",
        "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_EXECPATH",
        "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
    ]

    /// Nomes com cara de segredo, comparados sem diferenciar maiúsculas. `*` casa com qualquer trecho.
    public static let secretPatterns = [
        "*KEY*", "*TOKEN*", "*SECRET*", "*PASSWORD*", "*PASSWD*", "*CREDENTIAL*",
        "AWS_*", "PG*", "*_DSN", "DATABASE_URL",
    ]

    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.utf8.first else { return false }
        func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 }
        func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
        return isLetter(first) && name.utf8.allSatisfy { isLetter($0) || isDigit($0) }
    }

    public static func matches(_ name: String, pattern: String) -> Bool {
        let text = Array(name.lowercased().utf8)
        let glob = Array(pattern.lowercased().utf8)
        let star = UInt8(ascii: "*")
        var textIndex = 0, globIndex = 0, lastStar = -1, resume = 0
        while textIndex < text.count {
            if globIndex < glob.count, glob[globIndex] == star {
                lastStar = globIndex
                resume = textIndex
                globIndex += 1
            } else if globIndex < glob.count, glob[globIndex] == text[textIndex] {
                textIndex += 1
                globIndex += 1
            } else if lastStar >= 0 {
                globIndex = lastStar + 1
                resume += 1
                textIndex = resume
            } else {
                return false
            }
        }
        while globIndex < glob.count, glob[globIndex] == star { globIndex += 1 }
        return globIndex == glob.count
    }

    public static func isSecret(_ name: String) -> Bool {
        secretPatterns.contains { matches(name, pattern: $0) }
    }

    /// Ambiente base + empresa -> ambiente do agente.
    /// Ordem: saem as variáveis de sessão do pai; saem os nomes com cara de segredo, menos os
    /// liberados em `env_allow` (global e da empresa); entram as variáveis do próprio CLARK.
    public static func apply(base: [String: String], globalAllow: [String], company: Company,
                             agentName: String) -> AgentEnvironment {
        var variables = base
        for name in parentSessionVars { variables[name] = nil }
        let allowed = Set(globalAllow).union(company.envAllow).subtracting(parentSessionVars)
        var removed: [String] = []
        for name in base.keys where variables[name] != nil && isSecret(name) && !allowed.contains(name) {
            variables[name] = nil
            removed.append(name)
        }
        variables["TERM"] = "xterm-256color"
        variables["COLORTERM"] = "truecolor"
        variables["CLARK_AGENT"] = agentName
        variables["CLARK_COMPANY"] = company.name
        return AgentEnvironment(variables: variables, removed: removed.sorted())
    }
}
```

**Arquivo:** `mac/Sources/ClarkCore/CompanyResolver.swift`

```swift
import Foundation

public struct Company: Equatable, Sendable {
    public let name: String
    public let color: RGB
    /// Variáveis com cara de segredo que esta empresa pode receber.
    public let envAllow: [String]

    public init(name: String, color: RGB, envAllow: [String]) {
        self.name = name
        self.color = color
        self.envAllow = envAllow
    }
}

/// Caminho -> empresa, a partir do `companies.json` (opcional).
/// 1. `paths` explícitos, vencendo o prefixo mais longo;
/// 2. primeira pasta abaixo de uma das `roots`;
/// 3. `AVULSO`.
/// Só o passo 1 dá `env_allow`: uma empresa detectada pela pasta nunca libera variável.
public struct CompanyResolver: Sendable {
    public static let fallbackName = "AVULSO"
    public static let defaultRoots = ["~/Projetos"]
    /// Agentes da mesma empresa escurecem nestes passos: 0, 15, 30 e 45%.
    public static let toneStep = 0.15
    public static let toneCount = 4

    public let globalEnvAllow: [String]
    /// Problemas encontrados no arquivo. Nunca trazem o valor inválido, que pode ser um segredo colado por engano.
    public let warnings: [String]

    private struct Rule: Sendable {
        let prefix: [String]
        let company: Company
        /// Posição da empresa na lista do arquivo, a partir de 1. Só para os avisos.
        let position: Int
    }

    private let rules: [Rule]
    private let roots: [[String]]
    private let palette: [RGB]
    private let fallbackColor: RGB

    /// - Parameters:
    ///   - json: conteúdo do `companies.json`, ou nil quando o arquivo não existe.
    ///   - canonicalize: transforma um caminho do arquivo no mesmo formato dos caminhos passados a `resolve`.
    public init(json: Data?, palette: [RGB], fallbackColor: RGB, canonicalize: (String) -> String) {
        self.palette = palette
        self.fallbackColor = fallbackColor
        var warnings: [String] = []
        var rootPaths = Self.defaultRoots
        var globalAllow: [String] = []
        var rules: [Rule] = []

        if let json {
            if let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] {
                if let raw = object["roots"] {
                    if let list = raw as? [Any] {
                        rootPaths = list.compactMap { $0 as? String }.filter { !$0.isEmpty }
                    } else {
                        warnings.append("companies.json: roots precisa ser uma lista")
                    }
                }
                globalAllow = Self.parseNames(object["env_allow"], label: "env_allow", warnings: &warnings)
                if let raw = object["companies"] {
                    if let list = raw as? [Any] {
                        for (index, item) in list.enumerated() {
                            rules += Self.parseCompany(item, position: index + 1, palette: palette,
                                                fallbackColor: fallbackColor, canonicalize: canonicalize,
                                                warnings: &warnings)
                        }
                    } else {
                        warnings.append("companies.json: companies precisa ser uma lista")
                    }
                }
            } else {
                warnings.append("companies.json invalido: valendo a deteccao automatica")
            }
        }

        var roots: [[String]] = []
        for path in rootPaths {
            let components = PathTools.components(canonicalize(path))
            if components.isEmpty {
                warnings.append("companies.json: a raiz do disco nao pode ser uma root")
            } else {
                roots.append(components)
            }
        }
        // Um path igual a uma root, ou acima dela, engole as pastas das outras empresas:
        // o `env_allow` dessa empresa chegaria aos agentes de todas. A regra segue valendo; fica o aviso.
        for rule in rules where roots.contains(where: { PathTools.hasPrefix($0, rule.prefix) }) {
            let warning = "companies.json: path da empresa \(rule.position) cobre uma root inteira"
            if !warnings.contains(warning) { warnings.append(warning) }
        }
        self.rules = rules
        self.roots = roots
        self.globalEnvAllow = globalAllow
        self.warnings = warnings
    }

    /// `canonicalPath` precisa ter passado pela mesma `canonicalize` do init.
    public func resolve(canonicalPath: String) -> Company {
        let components = PathTools.components(canonicalPath)
        var best: Rule?
        for rule in rules where PathTools.hasPrefix(components, rule.prefix) {
            if rule.prefix.count > (best?.prefix.count ?? -1) { best = rule }
        }
        if let best { return best.company }

        var bestRoot: [String]?
        for root in roots where components.count > root.count && PathTools.hasPrefix(components, root) {
            if root.count > (bestRoot?.count ?? -1) { bestRoot = root }
        }
        if let bestRoot {
            let name = components[bestRoot.count]
            return Company(name: name, color: Self.color(for: name, palette: palette, fallback: fallbackColor),
                           envAllow: [])
        }
        return Company(name: Self.fallbackName, color: fallbackColor, envAllow: [])
    }

    /// Índice estável (FNV-1a de 32 bits) para escolher a cor de um nome. Não muda entre execuções.
    public static func stableIndex(_ name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt32 = 2_166_136_261
        for byte in name.precomposedStringWithCanonicalMapping.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(count))
    }

    /// Cor do N-ésimo agente da mesma empresa.
    public static func tone(_ base: RGB, index: Int) -> RGB {
        let step = ((index % toneCount) + toneCount) % toneCount
        return base.darkened(Double(step) * toneStep)
    }

    private static func color(for name: String, palette: [RGB], fallback: RGB) -> RGB {
        palette.isEmpty ? fallback : palette[stableIndex(name, count: palette.count)]
    }

    private static func parseCompany(_ item: Any, position: Int, palette: [RGB], fallbackColor: RGB,
                              canonicalize: (String) -> String, warnings: inout [String]) -> [Rule] {
        guard let entry = item as? [String: Any],
              let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            warnings.append("companies.json: empresa \(position) sem nome, ignorada")
            return []
        }
        let paths = (entry["paths"] as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
        if paths.isEmpty {
            warnings.append("companies.json: empresa \(position) sem paths, ignorada")
            return []
        }
        var color = Self.color(for: name, palette: palette, fallback: fallbackColor)
        if let raw = entry["color"] {
            if let text = raw as? String, let parsed = RGB(hex: text) {
                color = parsed
            } else {
                warnings.append("companies.json: cor invalida na empresa \(position)")
            }
        }
        let allow = parseNames(entry["env_allow"], label: "env_allow da empresa \(position)", warnings: &warnings)
        let company = Company(name: name, color: color, envAllow: allow)
        var rules: [Rule] = []
        for path in paths {
            let components = PathTools.components(canonicalize(path))
            if components.isEmpty {
                warnings.append("companies.json: a raiz do disco nao pode ser path da empresa \(position)")
            } else {
                rules.append(Rule(prefix: components, company: company, position: position))
            }
        }
        return rules
    }

    private static func parseNames(_ raw: Any?, label: String, warnings: inout [String]) -> [String] {
        guard let raw else { return [] }
        guard let list = raw as? [Any] else {
            warnings.append("companies.json: \(label) precisa ser uma lista")
            return []
        }
        var names: [String] = []
        for item in list {
            guard let name = item as? String, EnvPolicy.isValidName(name) else {
                warnings.append("companies.json: nome de variavel invalido em \(label)")
                continue
            }
            if EnvPolicy.parentSessionVars.contains(name) {
                warnings.append("companies.json: \(name) nunca e liberada")
                continue
            }
            names.append(name)
        }
        return names
    }
}
```

**Arquivo:** `mac/Sources/ClarkCore/ShellEnvParser.swift`

```swift
import Foundation

/// Leitura da saída do shell de login: `<lixo do rc>MARCADOR\0NOME=valor\0NOME=valor\0`.
public enum ShellEnvParser {
    public static let marker = "__CLARK_ENV_BEGIN__"
    /// Comando passado a `$SHELL -l -i -c`. O marcador separa o que o rc imprimir do ambiente.
    public static let command = "printf '%s\\0' \(marker); /usr/bin/env -0"
    /// `PATH` usado quando a captura falha.
    public static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    /// Variáveis que só descrevem o shell da captura e não valem para o agente.
    static let transient: Set<String> = ["PWD", "OLDPWD", "SHLVL", "_"]

    /// Devolve nil quando o marcador não aparece ou não há `PATH`: captura inválida.
    public static func parse(_ data: Data) -> [String: String]? {
        guard let start = data.range(of: Data((marker + "\0").utf8)) else { return nil }
        var variables: [String: String] = [:]
        for entry in data[start.upperBound...].split(separator: 0) {
            guard let equals = entry.firstIndex(of: UInt8(ascii: "=")), equals > entry.startIndex,
                  let name = String(data: entry[entry.startIndex..<equals], encoding: .utf8),
                  let value = String(data: entry[entry.index(after: equals)...], encoding: .utf8) else { continue }
            if transient.contains(name) { continue }
            variables[name] = value
        }
        guard let path = variables["PATH"], !path.isEmpty else { return nil }
        return variables
    }

    /// Ambiente do próprio app com um `PATH` padrão, para quando a captura falha.
    public static func fallback(processEnvironment: [String: String]) -> [String: String] {
        var variables = processEnvironment
        for name in transient { variables[name] = nil }
        variables["PATH"] = defaultPath
        return variables
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'EnvPolicyTests|ShellEnvParserTests|CompanyResolverTests'`
Expected: PASS, `Executed 30 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 75 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkCoreTests/EnvPolicyTests.swift`
- `mac/Tests/ClarkCoreTests/CompanyResolverTests.swift`
- `mac/Sources/ClarkCore/EnvPolicy.swift`
- `mac/Sources/ClarkCore/CompanyResolver.swift`
- `mac/Sources/ClarkCore/ShellEnvParser.swift`

---

### Task 6: Conversa do claude: retomar ou começar

Decide entre retomar e começar uma conversa, monta os argumentos do `claude`, detecta nos argumentos extras as flags de sessão e de permissão perigosa, e procura o executável do `claude`.

**Files:**
- Create: `mac/Sources/ClarkCore/Session.swift`
- Test: `mac/Tests/ClarkCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 1: `PathTools`, `TemporaryDirectory`
- Produces:

```swift
// mac/Sources/ClarkCore/Session.swift
public enum SessionLocator
    public static func isValidUUID(_ text: String) -> Bool
    public static func normalized(_ text: String?) -> String?
    public static func newID() -> String
    public static func configDir(environment: [String: String], home: String) -> String
    public static func sessionExists(_ id: String, configDir: String) -> Bool
public struct ClaudeCommand: Equatable, Sendable
    public static let sessionFlags: Set<String>
    public let arguments: [String]
    public let bypassesPermissions: Bool
    public static func build(extraArgs: [String], sessionID: String, sessionExists: Bool) -> ClaudeCommand
    public static func hasSessionFlag(_ args: [String]) -> Bool
    public static func bypassesPermissions(_ args: [String]) -> Bool
public enum ClaudeLocator
    public static func find(path: String?, home: String, isExecutable: (String) -> Bool = PathTools.isExecutableFile) -> String?
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkCoreTests/SessionTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class SessionLocatorTests: XCTestCase {
    private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    func testValidUUID() {
        XCTAssertTrue(SessionLocator.isValidUUID(id))
        XCTAssertTrue(SessionLocator.isValidUUID(id.uppercased()))
        XCTAssertTrue(SessionLocator.isValidUUID(SessionLocator.newID()))
    }

    func testInvalidUUID() {
        let bad = ["", "abc", id + "0", String(id.dropLast()), "{" + id.dropFirst().dropLast() + "}",
                   id.replacingOccurrences(of: "-", with: "_"), "0f8fad5bd-9cb-469f-a165-70867728950e",
                   "0f8fad5b-d9cb-469f-a165-7086772895zz", id + "\n", "--dangerously-skip-permissions",
                   "../../../etc/passwd-aaaaaaaaaaaaaaaaaaaa"]
        for text in bad { XCTAssertFalse(SessionLocator.isValidUUID(text), text) }
    }

    func testNormalizedLowercasesAndRejects() {
        XCTAssertEqual(SessionLocator.normalized(id.uppercased()), id)
        XCTAssertNil(SessionLocator.normalized("nao-e-uuid"))
        XCTAssertNil(SessionLocator.normalized(nil))
    }

    func testNewIDIsLowercaseAndUnique() {
        let first = SessionLocator.newID()
        XCTAssertEqual(first, first.lowercased())
        XCTAssertNotEqual(first, SessionLocator.newID())
    }

    func testConfigDirRespectsClaudeConfigDir() {
        XCTAssertEqual(SessionLocator.configDir(environment: [:], home: "/Users/eu"), "/Users/eu/.claude")
        XCTAssertEqual(SessionLocator.configDir(environment: ["CLAUDE_CONFIG_DIR": ""], home: "/Users/eu"), "/Users/eu/.claude")
        XCTAssertEqual(SessionLocator.configDir(environment: ["CLAUDE_CONFIG_DIR": "/x/y"], home: "/Users/eu"), "/x/y")
        XCTAssertEqual(SessionLocator.configDir(environment: ["CLAUDE_CONFIG_DIR": "~/alt"], home: "/Users/eu"), "/Users/eu/alt")
    }

    func testSessionExistsOnlyWithTheTranscriptOnDisk() {
        let temp = TemporaryDirectory()
        XCTAssertFalse(SessionLocator.sessionExists(id, configDir: temp.path), "sem a pasta projects")
        temp.write("projects/-Users-eu-Projetos-A/\(id).jsonl", "{}\n")
        temp.makeDirectory("projects/-Users-eu-Projetos-B")
        XCTAssertTrue(SessionLocator.sessionExists(id, configDir: temp.path))
        XCTAssertTrue(SessionLocator.sessionExists(id.uppercased(), configDir: temp.path))
        XCTAssertFalse(SessionLocator.sessionExists(SessionLocator.newID(), configDir: temp.path))
    }

    func testInvalidIDNeverTouchesTheDisk() {
        let temp = TemporaryDirectory()
        temp.write("projects/p/segredo.jsonl", "{}")
        XCTAssertFalse(SessionLocator.sessionExists("segredo", configDir: temp.path))
        XCTAssertFalse(SessionLocator.sessionExists("../p/segredo", configDir: temp.path + "/projects"))
    }
}

final class ClaudeCommandTests: XCTestCase {
    private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    func testNewConversationUsesSessionID() {
        let command = ClaudeCommand.build(extraArgs: [], sessionID: id, sessionExists: false)
        XCTAssertEqual(command.arguments, ["--session-id", id])
        XCTAssertFalse(command.bypassesPermissions)
    }

    func testExistingConversationUsesResume() {
        let command = ClaudeCommand.build(extraArgs: ["--model", "opus"], sessionID: id, sessionExists: true)
        XCTAssertEqual(command.arguments, ["--model", "opus", "--resume", id])
    }

    func testSessionFlagsInTheExtrasSuppressOurs() {
        for extras in [["-c"], ["--continue"], ["-r", "abc"], ["--resume"], ["--resume=abc"],
                       ["--session-id", "abc"], ["--session-id=abc"], ["--model", "opus", "-c"]] {
            let command = ClaudeCommand.build(extraArgs: extras, sessionID: id, sessionExists: true)
            XCTAssertEqual(command.arguments, extras, "\(extras)")
        }
    }

    func testLookAlikeFlagsDoNotCount() {
        for extras in [["--resumed"], ["--continue-on-error"], ["-cx"], ["--model", "c"]] {
            XCTAssertFalse(ClaudeCommand.hasSessionFlag(extras), "\(extras)")
        }
    }

    func testDetectsPermissionBypass() {
        XCTAssertTrue(ClaudeCommand.bypassesPermissions(["--dangerously-skip-permissions"]))
        XCTAssertTrue(ClaudeCommand.bypassesPermissions(["--model", "opus", "--permission-mode", "bypassPermissions"]))
        XCTAssertTrue(ClaudeCommand.bypassesPermissions(["--permission-mode=bypassPermissions"]))
        XCTAssertFalse(ClaudeCommand.bypassesPermissions([]))
        XCTAssertFalse(ClaudeCommand.bypassesPermissions(["--permission-mode", "plan"]))
        XCTAssertFalse(ClaudeCommand.bypassesPermissions(["--permission-mode"]))
        XCTAssertFalse(ClaudeCommand.bypassesPermissions(["--permission-mode=acceptEdits"]))
        let command = ClaudeCommand.build(extraArgs: ["--dangerously-skip-permissions"], sessionID: id, sessionExists: false)
        XCTAssertTrue(command.bypassesPermissions)
        XCTAssertEqual(command.arguments, ["--dangerously-skip-permissions", "--session-id", id])
    }
}

final class ClaudeLocatorTests: XCTestCase {
    func testFindsInThePathFirst() {
        let found = ClaudeLocator.find(path: "/a:/b:/c", home: "/Users/eu") { $0 == "/b/claude" || $0 == "/Users/eu/.local/bin/claude" }
        XCTAssertEqual(found, "/b/claude")
    }

    func testRelativePathEntriesAreIgnored() {
        let found = ClaudeLocator.find(path: "rel:.::bin", home: "/Users/eu") { !$0.hasPrefix("/") }
        XCTAssertNil(found)
    }

    func testFallsBackToKnownLocationsInOrder() {
        let candidates = ["/Users/eu/.local/bin/claude", "/Users/eu/.claude/local/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for (index, expected) in candidates.enumerated() {
            let available = Set(candidates[index...])
            XCTAssertEqual(ClaudeLocator.find(path: nil, home: "/Users/eu") { available.contains($0) }, expected)
        }
        XCTAssertNil(ClaudeLocator.find(path: "/a", home: "/Users/eu") { _ in false })
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkCoreTests/SessionTests.swift:8:23: error: cannot find 'SessionLocator' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/ClarkCore/Session.swift`

```swift
import Foundation

/// Identificador de conversa do Claude Code e a decisão entre retomar e começar.
public enum SessionLocator {
    /// UUID no formato 8-4-4-4-12 em hexadecimal.
    public static func isValidUUID(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                if byte != UInt8(ascii: "-") { return false }
            } else if !((48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)) {
                return false
            }
        }
        return true
    }

    /// UUID em minúsculas, ou nil quando o texto não é um UUID. É a única forma de um
    /// `session_id` do config chegar ao argv.
    public static func normalized(_ text: String?) -> String? {
        guard let text, isValidUUID(text) else { return nil }
        return text.lowercased()
    }

    public static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Pasta de configuração do Claude Code, respeitando `CLAUDE_CONFIG_DIR` do ambiente do agente.
    public static func configDir(environment: [String: String], home: String) -> String {
        if let directory = environment["CLAUDE_CONFIG_DIR"], !directory.isEmpty {
            return PathTools.expandTilde(directory, home: home)
        }
        return home + "/.claude"
    }

    /// A conversa só pode ser retomada depois que o claude grava `<projects>/*/<id>.jsonl`.
    public static func sessionExists(_ id: String, configDir: String) -> Bool {
        guard let id = normalized(id) else { return false }
        let projects = configDir + "/projects"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: projects) else { return false }
        return entries.contains { FileManager.default.fileExists(atPath: "\(projects)/\($0)/\(id).jsonl") }
    }
}

/// Argumentos do `claude` de um agente.
public struct ClaudeCommand: Equatable, Sendable {
    /// Flags que já escolhem a conversa; com elas o CLARK não acrescenta a sua.
    public static let sessionFlags: Set<String> = ["-c", "--continue", "-r", "--resume", "--session-id"]

    /// Argumentos sem o executável.
    public let arguments: [String]
    /// O agente roda sem pedir permissão: o painel mostra a faixa `SEM PERMISSOES`.
    public let bypassesPermissions: Bool

    public static func build(extraArgs: [String], sessionID: String, sessionExists: Bool) -> ClaudeCommand {
        var arguments = extraArgs
        if !hasSessionFlag(extraArgs) {
            arguments += [sessionExists ? "--resume" : "--session-id", sessionID]
        }
        return ClaudeCommand(arguments: arguments, bypassesPermissions: bypassesPermissions(extraArgs))
    }

    public static func hasSessionFlag(_ args: [String]) -> Bool {
        args.contains { argument in
            let flag = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            return sessionFlags.contains(String(flag))
        }
    }

    public static func bypassesPermissions(_ args: [String]) -> Bool {
        for (index, argument) in args.enumerated() {
            if argument == "--dangerously-skip-permissions" { return true }
            if argument == "--permission-mode=bypassPermissions" { return true }
            if argument == "--permission-mode", index + 1 < args.count, args[index + 1] == "bypassPermissions" {
                return true
            }
        }
        return false
    }
}

public enum ClaudeLocator {
    /// Procura o `claude` no `PATH` capturado e depois nos lugares de instalação conhecidos.
    /// Entradas relativas do `PATH` são ignoradas.
    public static func find(path: String?, home: String,
                            isExecutable: (String) -> Bool = PathTools.isExecutableFile) -> String? {
        var candidates: [String] = []
        for directory in (path ?? "").split(separator: ":") where directory.hasPrefix("/") {
            candidates.append("\(directory)/claude")
        }
        candidates += ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                       "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first(where: isExecutable)
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'SessionLocatorTests|ClaudeCommandTests|ClaudeLocatorTests'`
Expected: PASS, `Executed 15 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 90 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkCoreTests/SessionTests.swift`
- `mac/Sources/ClarkCore/Session.swift`

---

### Task 7: config.json

Leitura e gravação do `config.json`: cada campo validado, chaves desconhecidas preservadas, permissão `0600`, troca atômica, e o arquivo inválido renomeado antes da primeira gravação.

**Files:**
- Create: `mac/Sources/ClarkCore/Config.swift`
- Test: `mac/Tests/ClarkCoreTests/ConfigTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 1: `TemporaryDirectory`
  - Task 2: `Theme`
  - Task 5: `CompanyResolver`
  - Task 6: `SessionLocator`
- Produces:

```swift
// mac/Sources/ClarkCore/Config.swift
public struct SavedAgent: Equatable, Sendable
    public var name: String?
    public var cwd: String?
    public var sessionID: String?
    public var tone: Int?
    public init(name: String?, cwd: String?, sessionID: String?, tone: Int?)
public struct ClarkConfig
    public static let fontScaleRange = 0.6...2.5
    public static let fontSizeRange = 6.0...48.0
    public static let maxAgents = 16
    public static let layouts = ["focus", "grid"]
    public var theme = "dark"
    public var layout = "focus"
    public var fontName = "Menlo"
    public var fontSize = 12.0
    public var fontScale = 1.0
    public var dragons = true
    public var queueVisible = true
    public var cwd: String?
    public var skillsDir: String?
    public var mainAgent = 0
    public var agents: [SavedAgent]
    public var unknown: [String: Any]
    public init()
    public init(json object: [String: Any])
    public func jsonObject() -> [String: Any]
    static func parseFont(_ text: String) -> (name: String, size: Double)?
public final class ConfigStore
    public let directory: String
    public var configPath: String
    public var companiesPath: String
    public init(directory: String, now: @escaping () -> Date = Date.init)
    public static func defaultDirectory(home: String) -> String
    public func load() -> (config: ClarkConfig, warning: String?)
    public func companiesData() -> Data?
    public func save(_ config: ClarkConfig) throws
    static func writeAtomically(_ data: Data, to path: String) throws
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkCoreTests/ConfigTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class ClarkConfigTests: XCTestCase {
    private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    private func parse(_ json: String) -> ClarkConfig {
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertNotNil(object, json)
        return ClarkConfig(json: object ?? [:])
    }

    func testDefaults() {
        let config = parse("{}")
        XCTAssertEqual(config.theme, "dark")
        XCTAssertEqual(config.layout, "focus")
        XCTAssertEqual(config.fontName, "Menlo")
        XCTAssertEqual(config.fontSize, 12)
        XCTAssertEqual(config.fontScale, 1)
        XCTAssertTrue(config.dragons)
        XCTAssertTrue(config.queueVisible)
        XCTAssertNil(config.cwd)
        XCTAssertNil(config.skillsDir)
        XCTAssertEqual(config.mainAgent, 0)
        XCTAssertTrue(config.agents.isEmpty)
    }

    func testValidValues() {
        let config = parse("""
        {"theme": "magick", "layout": "grid", "font": "JetBrains Mono 14", "font_scale": 1.5,
         "dragons": false, "queue_visible": false, "cwd": "~/Projetos", "skills_dir": "~/skills", "main_agent": 1,
         "agents": [{"name": "API", "cwd": "/a", "session_id": "\(id.uppercased())", "color": 2},
                    {"name": "AGENT 2", "cwd": "/b", "session_id": "\(id)", "color": 0}]}
        """)
        XCTAssertEqual(config.theme, "magick")
        XCTAssertEqual(config.layout, "grid")
        XCTAssertEqual(config.fontName, "JetBrains Mono")
        XCTAssertEqual(config.fontSize, 14)
        XCTAssertEqual(config.fontScale, 1.5)
        XCTAssertFalse(config.dragons)
        XCTAssertFalse(config.queueVisible)
        XCTAssertEqual(config.cwd, "~/Projetos")
        XCTAssertEqual(config.skillsDir, "~/skills")
        XCTAssertEqual(config.mainAgent, 1)
        XCTAssertEqual(config.agents, [SavedAgent(name: "API", cwd: "/a", sessionID: id, tone: 2),
                                       SavedAgent(name: "AGENT 2", cwd: "/b", sessionID: id, tone: 0)])
    }

    func testInvalidFieldsFallBackOneByOne() {
        let config = parse("""
        {"theme": "neon", "layout": 3, "font": "Menlo", "font_scale": "grande", "dragons": 0,
         "queue_visible": "nao", "cwd": 7, "skills_dir": "", "main_agent": -1, "agents": "nenhum"}
        """)
        XCTAssertEqual(config.theme, "dark")
        XCTAssertEqual(config.layout, "focus")
        XCTAssertEqual(config.fontName, "Menlo")
        XCTAssertEqual(config.fontSize, 12)
        XCTAssertEqual(config.fontScale, 1)
        XCTAssertTrue(config.dragons, "0 não é booleano")
        XCTAssertTrue(config.queueVisible)
        XCTAssertNil(config.cwd)
        XCTAssertNil(config.skillsDir)
        XCTAssertEqual(config.mainAgent, 0)
        XCTAssertTrue(config.agents.isEmpty)
    }

    func testNumbersAndBooleansAreNotInterchangeable() {
        XCTAssertEqual(parse(#"{"font_scale": true}"#).fontScale, 1)
        XCTAssertEqual(parse(#"{"main_agent": true}"#).mainAgent, 0)
        XCTAssertEqual(parse(#"{"main_agent": 1.5}"#).mainAgent, 0)
        XCTAssertEqual(parse(#"{"main_agent": 1e30}"#).mainAgent, 0)
        XCTAssertTrue(parse(#"{"dragons": 1}"#).dragons)
        XCTAssertTrue(parse(#"{"dragons": "false"}"#).dragons)
    }

    func testFontScaleIsClamped() {
        XCTAssertEqual(parse(#"{"font_scale": 99}"#).fontScale, 2.5)
        XCTAssertEqual(parse(#"{"font_scale": 0.1}"#).fontScale, 0.6)
        XCTAssertEqual(parse(#"{"font_scale": -3}"#).fontScale, 0.6)
    }

    func testFontNeedsANameAndASaneSize() {
        for bad in ["Menlo", "12", "Menlo 900", "Menlo 2", "Menlo doze", "", "Menlo -12"] {
            let config = parse(#"{"font": "\#(bad)"}"#)
            XCTAssertEqual(config.fontName, "Menlo", bad)
            XCTAssertEqual(config.fontSize, 12, bad)
        }
        let config = parse(#"{"font": "SF Mono 13.5"}"#)
        XCTAssertEqual(config.fontName, "SF Mono")
        XCTAssertEqual(config.fontSize, 13.5)
    }

    func testAgentsAreValidatedFieldByField() {
        let config = parse("""
        {"agents": [{"name": 5, "cwd": "", "session_id": "--dangerously-skip-permissions", "color": "azul"},
                    "texto", 3, {"color": 6}, {"color": -1}, {"session_id": 12}]}
        """)
        XCTAssertEqual(config.agents, [SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: nil),
                                       SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: 2),
                                       SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: 1),
                                       SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: nil)])
    }

    func testAtMostSixteenAgents() {
        let entries = Array(repeating: #"{"name": "A"}"#, count: 20).joined(separator: ",")
        XCTAssertEqual(parse(#"{"agents": [\#(entries)]}"#).agents.count, 16)
    }

    func testUnknownKeysSurviveTheRoundTrip() throws {
        var config = parse(#"{"theme": "white", "auto_trust": true, "todos": [{"text": "x"}], "novo": {"a": 1}}"#)
        config.layout = "grid"
        let object = config.jsonObject()
        XCTAssertEqual(object["theme"] as? String, "white")
        XCTAssertEqual(object["layout"] as? String, "grid")
        XCTAssertEqual(object["auto_trust"] as? Bool, true)
        XCTAssertEqual((object["todos"] as? [[String: String]])?.first?["text"], "x")
        XCTAssertEqual((object["novo"] as? [String: Int])?["a"], 1)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(object))
    }

    func testJSONObjectShape() {
        var config = ClarkConfig()
        config.fontScale = 1.2345
        config.fontSize = 12.5
        config.agents = [SavedAgent(name: "API", cwd: "/a", sessionID: id, tone: 1),
                         SavedAgent(name: nil, cwd: nil, sessionID: nil, tone: nil)]
        let object = config.jsonObject()
        XCTAssertEqual(object["font"] as? String, "Menlo 12.5")
        XCTAssertEqual(object["font_scale"] as? Double, 1.23)
        XCTAssertNil(object["cwd"], "campo vazio não vai para o arquivo")
        XCTAssertNil(object["skills_dir"])
        let agents = object["agents"] as? [[String: Any]]
        XCTAssertEqual(agents?.count, 2)
        XCTAssertEqual(agents?[0]["name"] as? String, "API")
        XCTAssertEqual(agents?[0]["session_id"] as? String, id)
        XCTAssertEqual(agents?[0]["color"] as? Int, 1)
        XCTAssertEqual(agents?[1].isEmpty, true)
        XCTAssertEqual(ClarkConfig(json: object).agents, config.agents)
        XCTAssertEqual((ClarkConfig().jsonObject()["font"] as? String), "Menlo 12")
    }
}

final class ConfigStoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_791_720_000)

    private func store(_ temp: TemporaryDirectory, _ folder: String = "clark") -> ConfigStore {
        ConfigStore(directory: temp.path + "/" + folder, now: { self.fixedDate })
    }

    private func read(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func testDefaultDirectory() {
        XCTAssertEqual(ConfigStore.defaultDirectory(home: "/Users/eu"), "/Users/eu/.config/clark")
    }

    func testLoadWithoutFileGivesDefaults() {
        let temp = TemporaryDirectory()
        let loaded = store(temp).load()
        XCTAssertEqual(loaded.config.theme, "dark")
        XCTAssertNil(loaded.warning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path + "/clark"), "ler não cria nada")
    }

    func testSaveCreatesPrivateDirectoryAndFile() throws {
        let temp = TemporaryDirectory()
        let store = store(temp)
        var config = ClarkConfig()
        config.layout = "grid"
        try store.save(config)
        XCTAssertEqual(temp.permissions("clark"), 0o700)
        XCTAssertEqual(temp.permissions("clark/config.json"), 0o600)
        XCTAssertEqual(read(store.configPath)?["layout"] as? String, "grid")
        XCTAssertEqual(store.load().config.layout, "grid")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.directory)
        XCTAssertEqual(leftovers, ["config.json"], "sem temporário esquecido")
    }

    func testSaveTightensAnOpenFileAndDirectory() throws {
        let temp = TemporaryDirectory()
        temp.write("clark/config.json", #"{"theme": "white"}"#, permissions: 0o644)
        chmod(temp.path + "/clark", 0o755)
        let store = store(temp)
        let config = store.load().config
        XCTAssertEqual(config.theme, "white")
        try store.save(config)
        XCTAssertEqual(temp.permissions("clark"), 0o700)
        XCTAssertEqual(temp.permissions("clark/config.json"), 0o600)
    }

    func testInvalidFileIsSetAsideBeforeTheFirstSave() throws {
        let temp = TemporaryDirectory()
        temp.write("clark/config.json", "{ isto nao e json")
        let store = store(temp)
        let loaded = store.load()
        XCTAssertNotNil(loaded.warning)
        XCTAssertEqual(loaded.config.theme, "dark")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory), ["config.json"],
                       "só a gravação põe o arquivo de lado")

        try store.save(loaded.config)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory).sorted()
        XCTAssertEqual(names.count, 2)
        let quarantined = try XCTUnwrap(names.first { $0.hasPrefix("config.json.invalido-") })
        XCTAssertEqual(try String(contentsOfFile: store.directory + "/" + quarantined, encoding: .utf8), "{ isto nao e json")
        XCTAssertNotNil(read(store.configPath))

        try store.save(loaded.config)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory).count, 2,
                       "a quarentena acontece uma vez")
    }

    func testQuarantineNeverOverwritesAnOlderOne() throws {
        let temp = TemporaryDirectory()
        for _ in 0..<2 {
            temp.write("clark/config.json", "[1, 2, 3]")
            let store = store(temp)
            XCTAssertNotNil(store.load().warning, "lista no topo não é config")
            try store.save(ClarkConfig())
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: temp.path + "/clark")
        XCTAssertEqual(names.filter { $0.contains(".invalido-") }.count, 2)
        XCTAssertEqual(names.filter { $0.hasSuffix("-2") }.count, 1)
    }

    func testSaveThroughASymlinkKeepsTheLink() throws {
        let temp = TemporaryDirectory()
        let real = temp.write("dotfiles/clark.json", #"{"theme": "white"}"#)
        temp.makeDirectory("clark")
        let store = store(temp)
        try FileManager.default.createSymbolicLink(atPath: store.configPath, withDestinationPath: real)
        var config = store.load().config
        XCTAssertEqual(config.theme, "white")
        config.layout = "grid"
        try store.save(config)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: store.configPath), real)
        XCTAssertEqual(read(real)?["layout"] as? String, "grid")
        XCTAssertEqual(temp.permissions("dotfiles/clark.json"), 0o600)
    }

    func testCompaniesFileIsReadAndNeverWritten() throws {
        let temp = TemporaryDirectory()
        let store = store(temp)
        XCTAssertNil(store.companiesData())
        try store.save(ClarkConfig())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.companiesPath))
        temp.write("clark/companies.json", #"{"roots": ["~/work"]}"#)
        XCTAssertEqual(store.companiesData(), Data(#"{"roots": ["~/work"]}"#.utf8))
    }

    func testSaveFailureThrows() {
        let temp = TemporaryDirectory()
        temp.write("clark", "sou um arquivo, não uma pasta")
        XCTAssertThrowsError(try store(temp).save(ClarkConfig()))
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkCoreTests/ConfigTests.swift:7:43: error: cannot find type 'ClarkConfig' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/ClarkCore/Config.swift`

```swift
import Foundation

/// Um agente gravado no `config.json`. Campo inválido vira nil e quem restaura decide o padrão.
public struct SavedAgent: Equatable, Sendable {
    public var name: String?
    public var cwd: String?
    public var sessionID: String?
    /// Passo de escurecimento da cor da empresa (campo `color` do arquivo).
    public var tone: Int?

    public init(name: String?, cwd: String?, sessionID: String?, tone: Int?) {
        self.name = name
        self.cwd = cwd
        self.sessionID = sessionID
        self.tone = tone
    }
}

/// Conteúdo do `config.json`. Cada campo inválido cai no padrão; chave desconhecida é preservada.
public struct ClarkConfig {
    public static let fontScaleRange = 0.6...2.5
    public static let fontSizeRange = 6.0...48.0
    public static let maxAgents = 16
    public static let layouts = ["focus", "grid"]

    public var theme = "dark"
    public var layout = "focus"
    public var fontName = "Menlo"
    public var fontSize = 12.0
    public var fontScale = 1.0
    public var dragons = true
    public var queueVisible = true
    public var cwd: String?
    public var skillsDir: String?
    public var mainAgent = 0
    public var agents: [SavedAgent] = []
    /// Chaves que esta versão não conhece: voltam para o arquivo como vieram.
    public var unknown: [String: Any] = [:]

    private static let knownKeys: Set<String> = [
        "theme", "layout", "font", "font_scale", "dragons", "queue_visible",
        "cwd", "skills_dir", "main_agent", "agents",
    ]

    public init() {}

    public init(json object: [String: Any]) {
        if let value = object["theme"] as? String, Theme.names.contains(value) { theme = value }
        if let value = object["layout"] as? String, Self.layouts.contains(value) { layout = value }
        if let value = object["font"] as? String, let font = Self.parseFont(value) {
            fontName = font.name
            fontSize = font.size
        }
        if let value = Self.number(object["font_scale"]) {
            fontScale = min(Self.fontScaleRange.upperBound, max(Self.fontScaleRange.lowerBound, value))
        }
        if let value = Self.bool(object["dragons"]) { dragons = value }
        if let value = Self.bool(object["queue_visible"]) { queueVisible = value }
        cwd = Self.text(object["cwd"])
        skillsDir = Self.text(object["skills_dir"])
        if let value = Self.integer(object["main_agent"]), value >= 0 { mainAgent = value }
        if let list = object["agents"] as? [Any] {
            agents = list.compactMap { $0 as? [String: Any] }.prefix(Self.maxAgents).map { entry in
                SavedAgent(name: Self.text(entry["name"]), cwd: Self.text(entry["cwd"]),
                           sessionID: SessionLocator.normalized(entry["session_id"] as? String),
                           tone: Self.integer(entry["color"]).map { abs($0) % CompanyResolver.toneCount })
            }
        }
        unknown = object.filter { !Self.knownKeys.contains($0.key) }
    }

    public func jsonObject() -> [String: Any] {
        var object = unknown
        object["theme"] = theme
        object["layout"] = layout
        object["font"] = "\(fontName) \(Self.format(fontSize))"
        object["font_scale"] = (fontScale * 100).rounded() / 100
        object["dragons"] = dragons
        object["queue_visible"] = queueVisible
        object["cwd"] = cwd
        object["skills_dir"] = skillsDir
        object["main_agent"] = mainAgent
        object["agents"] = agents.map { agent -> [String: Any] in
            var entry: [String: Any] = [:]
            entry["name"] = agent.name
            entry["cwd"] = agent.cwd
            entry["session_id"] = agent.sessionID
            entry["color"] = agent.tone
            return entry
        }
        return object
    }

    /// `"Menlo 12"` -> nome e tamanho. O tamanho é o último pedaço.
    static func parseFont(_ text: String) -> (name: String, size: Double)? {
        let parts = text.split(separator: " ")
        guard parts.count >= 2, let size = Double(parts[parts.count - 1]), fontSizeRange.contains(size) else {
            return nil
        }
        return (parts.dropLast().joined(separator: " "), size)
    }

    private static func format(_ size: Double) -> String {
        size == size.rounded() ? String(Int(size)) : String(size)
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// O JSON `true` não vale como número, nem `1` como booleano.
    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number == number.rounded(), abs(number) < 1_000_000 else { return nil }
        return Int(number)
    }
}

/// Lê e grava `~/.config/clark/config.json` e lê `companies.json` (que o app nunca grava).
public final class ConfigStore {
    public let directory: String
    public var configPath: String { directory + "/config.json" }
    public var companiesPath: String { directory + "/companies.json" }

    private let now: () -> Date
    /// O arquivo lido era inválido e ainda não foi posto de lado.
    private var quarantinePending = false

    public init(directory: String, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    public static func defaultDirectory(home: String) -> String {
        home + "/.config/clark"
    }

    public func load() -> (config: ClarkConfig, warning: String?) {
        guard FileManager.default.fileExists(atPath: configPath) else { return (ClarkConfig(), nil) }
        guard let data = FileManager.default.contents(atPath: configPath),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            quarantinePending = true
            return (ClarkConfig(), "config.json invalido: valendo os padroes")
        }
        return (ClarkConfig(json: object), nil)
    }

    /// Conteúdo do `companies.json`, ou nil quando o arquivo não existe.
    public func companiesData() -> Data? {
        FileManager.default.contents(atPath: companiesPath)
    }

    /// Pasta `0700`, arquivo `0600`, troca atômica. O arquivo inválido encontrado no `load`
    /// é renomeado para `config.json.invalido-<data>` antes da primeira gravação.
    public func save(_ config: ClarkConfig) throws {
        let manager = FileManager.default
        try manager.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        chmod(directory, 0o700)
        if quarantinePending {
            try manager.moveItem(atPath: configPath, toPath: quarantinePath())
            quarantinePending = false
        }
        let data = try JSONSerialization.data(withJSONObject: config.jsonObject(),
                                              options: [.prettyPrinted, .sortedKeys])
        try Self.writeAtomically(data, to: configPath)
    }

    private func quarantinePath() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(configPath).invalido-\(formatter.string(from: now()))"
        var candidate = base
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// Grava num temporário criado já com `0600` e troca pelo destino com `rename`.
    /// Se o destino é um link (dotfiles), grava ao lado do arquivo real para o link continuar valendo.
    static func writeAtomically(_ data: Data, to path: String) throws {
        var target = path
        if let real = realpath(path, nil) {
            target = String(cString: real)
            free(real)
        }
        let folder = (target as NSString).deletingLastPathComponent
        let temporary = "\(folder)/.clark-tmp-\(getpid())-\(UUID().uuidString)"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = 0
        if fchmod(descriptor, 0o600) != 0 { failure = errno }
        data.withUnsafeBytes { buffer in
            var offset = 0
            while failure == 0 && offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno != EINTR { failure = errno }
                } else {
                    offset += written
                }
            }
        }
        if failure == 0 && fsync(descriptor) != 0 { failure = errno }
        close(descriptor)
        if failure == 0 && rename(temporary, target) != 0 { failure = errno }
        if failure != 0 {
            unlink(temporary)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'ClarkConfigTests|ConfigStoreTests'`
Expected: PASS, `Executed 19 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 109 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkCoreTests/ConfigTests.swift`
- `mac/Sources/ClarkCore/Config.swift`

---

### Task 8: Linha de comando, nomes e prévia

A linha de comando do `clark`, os nomes dos agentes (o automático e o digitado) e a escolha das duas linhas de prévia do card.

**Files:**
- Create: `mac/Sources/ClarkCore/CLIOptions.swift`
- Create: `mac/Sources/ClarkCore/AgentNaming.swift`
- Test: `mac/Tests/ClarkCoreTests/CLIOptionsTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 1: `PathTools`
  - Task 2: `PixelFont`
  - Task 5: `CompanyResolver`
- Produces:

```swift
// mac/Sources/ClarkCore/CLIOptions.swift
public struct CLIOptions: Equatable, Sendable
    public static let usage
    public static let maxAgents = 16
    public var directory: String?
    public var count = 0
    public var noSplash = false
    public var fresh = false
    public var showVersion = false
    public var showHelp = false
    public var claudeArgs: [String]
    public init()
    public static func parse(_ argv: [String], launchDirectory: String, home: String) -> CLIOptions

// mac/Sources/ClarkCore/AgentNaming.swift
public enum AgentNaming
    public static let maxLength = 20
    public static func automaticNumber(_ name: String) -> Int?
    public static func automaticName(existing: [String]) -> String
    public static func sanitized(_ raw: String) -> String?
    public static func freeTone(used: [Int]) -> Int
public enum PreviewLines
    public static func useful(_ lines: [String], limit: Int = 2) -> [String]
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkCoreTests/CLIOptionsTests.swift`

```swift
import XCTest
@testable import ClarkCore

final class CLIOptionsTests: XCTestCase {
    private func parse(_ argv: String...) -> CLIOptions {
        CLIOptions.parse(argv, launchDirectory: "/work", home: "/Users/eu")
    }

    func testNoArguments() {
        XCTAssertEqual(parse(), CLIOptions())
        XCTAssertNil(parse().directory)
        XCTAssertEqual(parse().count, 0)
    }

    func testDirectoryIsResolvedAgainstTheLaunchDirectory() {
        XCTAssertEqual(parse("proj").directory, "/work/proj")
        XCTAssertEqual(parse(".").directory, "/work")
        XCTAssertEqual(parse("../x").directory, "/x")
        XCTAssertEqual(parse("/abs/x").directory, "/abs/x")
        XCTAssertEqual(parse("~/Projetos/A").directory, "/Users/eu/Projetos/A")
    }

    func testLaunchDirFlagComesFromTheShortcut() {
        XCTAssertEqual(parse("--launch-dir", "/term", "proj").directory, "/term/proj")
        XCTAssertEqual(parse("proj", "--launch-dir", "/term").directory, "/term/proj")
        XCTAssertNil(parse("--launch-dir", "/term").directory, "sem PASTA, a pasta do terminal não vira o padrão")
        XCTAssertNil(parse("--launch-dir").directory)
    }

    func testCountIsClamped() {
        XCTAssertEqual(parse("-n", "3").count, 3)
        XCTAssertEqual(parse("-n", "99").count, 16)
        XCTAssertEqual(parse("-n", "-2").count, 0)
        XCTAssertEqual(parse("-n").count, 1)
        let mixed = parse("-n", "proj")
        XCTAssertEqual(mixed.count, 1)
        XCTAssertEqual(mixed.directory, "/work/proj")
    }

    func testFlags() {
        let options = parse("--fresh", "--no-splash", "--version", "-h")
        XCTAssertTrue(options.fresh)
        XCTAssertTrue(options.noSplash)
        XCTAssertTrue(options.showVersion)
        XCTAssertTrue(options.showHelp)
        XCTAssertTrue(parse("--help").showHelp)
    }

    func testEverythingAfterDoubleDashGoesToClaude() {
        let options = parse("-n", "2", "proj", "--", "--model", "opus", "--fresh", "--", "x")
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options.directory, "/work/proj")
        XCTAssertFalse(options.fresh)
        XCTAssertEqual(options.claudeArgs, ["--model", "opus", "--fresh", "--", "x"])
        XCTAssertEqual(parse("--").claudeArgs, [])
    }

    func testUnknownFlagsAreIgnored() {
        let options = parse("--bogus", "-x", "-psn_0_12345")
        XCTAssertEqual(options, CLIOptions())
    }
}

final class AgentNamingTests: XCTestCase {
    func testAutomaticNumber() {
        XCTAssertEqual(AgentNaming.automaticNumber("AGENT 3"), 3)
        XCTAssertEqual(AgentNaming.automaticNumber("AGENT 12"), 12)
        for name in ["AGENT", "AGENT ", "AGENT x", "AGENT 3 ", "agent 3", "AGENT 1234567", "AGENT -1", "MEU AGENT 1"] {
            XCTAssertNil(AgentNaming.automaticNumber(name), name)
        }
    }

    func testAutomaticNameTakesTheLowestFreeNumber() {
        XCTAssertEqual(AgentNaming.automaticName(existing: []), "AGENT 1")
        XCTAssertEqual(AgentNaming.automaticName(existing: ["AGENT 1", "AGENT 3"]), "AGENT 2")
        XCTAssertEqual(AgentNaming.automaticName(existing: ["API", "AGENT 1"]), "AGENT 2")
        XCTAssertEqual(AgentNaming.automaticName(existing: ["AGENT 2"]), "AGENT 1")
    }

    func testSanitized() {
        XCTAssertEqual(AgentNaming.sanitized("  api façade  "), "API FACADE")
        XCTAssertEqual(AgentNaming.sanitized("a\u{1b}[31mb\n"), "A[31MB")
        XCTAssertEqual(AgentNaming.sanitized("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), "ABCDEFGHIJKLMNOPQRST")
        XCTAssertEqual(AgentNaming.sanitized("ABCDEFGHIJKLMNOPQRS TUV"), "ABCDEFGHIJKLMNOPQRS")
        for empty in ["", "   ", "日本", "\n\t"] { XCTAssertNil(AgentNaming.sanitized(empty), empty) }
    }

    func testFreeTone() {
        XCTAssertEqual(AgentNaming.freeTone(used: []), 0)
        XCTAssertEqual(AgentNaming.freeTone(used: [0]), 1)
        XCTAssertEqual(AgentNaming.freeTone(used: [1, 0, 3]), 2)
        XCTAssertEqual(AgentNaming.freeTone(used: [0, 1, 2, 3]), 0)
        XCTAssertEqual(AgentNaming.freeTone(used: [0, 1, 2, 3, 0]), 1)
    }
}

final class PreviewLinesTests: XCTestCase {
    func testKeepsTheLastTwoUsefulLines() {
        let lines = ["primeira", "", "  segunda  ", "╭──────────╮", "│ terceira │", "╰──────────╯", "   ", "> "]
        XCTAssertEqual(PreviewLines.useful(lines), ["segunda", "terceira"])
    }

    func testFrameOnlyAndEmptyLinesAreDropped() {
        XCTAssertEqual(PreviewLines.useful(["───", "│ │", "❯", "· • *", ""]), [])
        XCTAssertEqual(PreviewLines.useful([]), [])
    }

    func testLimit() {
        XCTAssertEqual(PreviewLines.useful(["a", "b", "c"], limit: 1), ["c"])
        XCTAssertEqual(PreviewLines.useful(["a"], limit: 2), ["a"])
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkCoreTests/CLIOptionsTests.swift:5:46: error: cannot find type 'CLIOptions' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/ClarkCore/CLIOptions.swift`

```swift
/// Linha de comando do `clark` (`parse_args` do original).
public struct CLIOptions: Equatable, Sendable {
    public static let usage =
        "uso: clark [PASTA] [-n N] [--no-splash] [--fresh] [--version] [-- argumentos extras do claude]"
    public static let maxAgents = 16

    public var directory: String?
    /// Agentes novos a abrir, de 0 a 16.
    public var count = 0
    /// Aceito para manter a linha de comando do original. A splash só existe a partir do M3.
    public var noSplash = false
    public var fresh = false
    public var showVersion = false
    public var showHelp = false
    public var claudeArgs: [String] = []

    public init() {}

    /// - Parameter launchDirectory: pasta contra a qual uma PASTA relativa é resolvida.
    ///   O atalho `clark` passa a pasta do terminal em `--launch-dir`, porque o `open` não a preserva.
    public static func parse(_ argv: [String], launchDirectory: String, home: String) -> CLIOptions {
        var options = CLIOptions()
        var own = argv
        if let separator = argv.firstIndex(of: "--") {
            own = Array(argv[..<separator])
            options.claudeArgs = Array(argv[(separator + 1)...])
        }
        var base = launchDirectory
        var positional: String?
        var index = 0
        while index < own.count {
            let argument = own[index]
            switch argument {
            case "-h", "--help":
                options.showHelp = true
            case "--version":
                options.showVersion = true
            case "--fresh":
                options.fresh = true
            case "--no-splash":
                options.noSplash = true
            case "-n":
                if index + 1 < own.count, let count = Int(own[index + 1]) {
                    options.count = max(0, min(maxAgents, count))
                    index += 1
                } else {
                    options.count = 1
                }
            case "--launch-dir":
                if index + 1 < own.count {
                    base = own[index + 1]
                    index += 1
                }
            default:
                if !argument.hasPrefix("-") { positional = argument }
            }
            index += 1
        }
        if let positional {
            options.directory = PathTools.absolute(positional, base: base, home: home)
        }
        return options
    }
}
```

**Arquivo:** `mac/Sources/ClarkCore/AgentNaming.swift`

```swift
import Foundation

public enum AgentNaming {
    public static let maxLength = 20

    /// `"AGENT 3"` -> 3. Qualquer outro nome devolve nil.
    public static func automaticNumber(_ name: String) -> Int? {
        let prefix = "AGENT "
        guard name.hasPrefix(prefix) else { return nil }
        let digits = name.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.utf8.count <= 6,
              digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(digits)
    }

    /// Menor número livre: fechou o AGENT 2, o próximo volta a ser AGENT 2.
    public static func automaticName(existing: [String]) -> String {
        let used = Set(existing.compactMap(automaticNumber))
        var number = 1
        while used.contains(number) { number += 1 }
        return "AGENT \(number)"
    }

    /// Nome digitado: vira ASCII maiúsculo (a fonte pixel não tem acentos), sem espaços nas
    /// pontas, com até 20 caracteres. Vazio devolve nil.
    public static func sanitized(_ raw: String) -> String? {
        let printable = PixelFont.normalize(raw).unicodeScalars.filter { $0.value >= 32 && $0.value < 127 }
        let trimmed = String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces)
        let cut = String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? nil : cut
    }

    /// Menor passo de cor ainda não usado pelos agentes da mesma empresa.
    public static func freeTone(used: [Int]) -> Int {
        (0..<CompanyResolver.toneCount).first { !used.contains($0) } ?? used.count % CompanyResolver.toneCount
    }
}

public enum PreviewLines {
    private static let edges = CharacterSet(charactersIn: "│┃|")
    private static let frame = Set("─━═╭╮╰╯┌┐└┘│┃>❯·•* ".unicodeScalars)

    /// Últimas linhas úteis do terminal para o card: sem moldura, sem linha vazia (`refresh_preview` do original).
    public static func useful(_ lines: [String], limit: Int = 2) -> [String] {
        var useful: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: edges)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.unicodeScalars.allSatisfy({ frame.contains($0) }) { continue }
            useful.append(line)
        }
        return Array(useful.suffix(limit))
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'CLIOptionsTests|AgentNamingTests|PreviewLinesTests'`
Expected: PASS, `Executed 14 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 123 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkCoreTests/CLIOptionsTests.swift`
- `mac/Sources/ClarkCore/CLIOptions.swift`
- `mac/Sources/ClarkCore/AgentNaming.swift`

---

### Task 9: Alvo Clark, SwiftTerm e o terminal do agente

Entram o alvo executável `Clark` e a única dependência, o SwiftTerm, fixado por revisão. O `AgentTerminalView` é o terminal de um agente: avisa saída, entrada, sino, fim do processo e redimensionamento, lê as linhas acima do cursor, só abre links `http` e `https` e descarta a resposta ao pedido de leitura da área de transferência. O `main.swift` desta tarefa é provisório e só existe para o alvo compilar; a Task 13 o substitui.

**Atenção:** O primeiro build desta tarefa baixa o SwiftTerm e o `swift-argument-parser`, então precisa de rede, e compila o SwiftTerm inteiro: pode levar alguns minutos numa máquina que nunca o compilou. O `Package.resolved` vai pronto no plano; se o SwiftPM o alterar, pare e compare antes de seguir.

**Files:**
- Create: `mac/Package.resolved`
- Create: `mac/Sources/Clark/main.swift`
- Create: `mac/Sources/Clark/RGB+AppKit.swift`
- Create: `mac/Sources/Clark/AgentTerminalView.swift`
- Modify: `mac/Package.swift` (o arquivo inteiro é trocado)
- Test: `mac/Tests/ClarkTests/TestSupport.swift`
- Test: `mac/Tests/ClarkTests/AgentTerminalViewTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 1: `ClarkVersion`
  - Task 2: `RGB`, `Theme`
  - SwiftTerm `v1.19.0`: `LocalProcessTerminalView` e os ganchos `dataReceived(slice:)`, `send(source:data:)`, `bell(source:)`, `processTerminated(_:exitCode:)` e `requestOpenLink(source:link:params:)`.
- Produces:

```swift
// mac/Sources/Clark/RGB+AppKit.swift
extension RGB
    var nsColor: NSColor
    var cgColor: CGColor

// mac/Sources/Clark/AgentTerminalView.swift
struct TerminalAppearance
    var theme: Theme
    var fontName: String
    var fontSize: Double
    var font: NSFont
final class AgentTerminalView: LocalProcessTerminalView
    static let scrollbackLines = 20_000
    var onOutput: (() -> Void)?
    var onUserInput: (() -> Void)?
    var onBell: (() -> Void)?
    var onExit: ((Int32?) -> Void)?
    var onResize: (() -> Void)?
    var onRestartRequested: (() -> Void)?
    var openURL: (URL) -> Void
    private(set) var hasExited = false
    static func exitCode(fromWaitStatus status: Int32?) -> Int32?
    func apply(_ appearance: TerminalAppearance)
    func markExited()
    static func isClipboardReply(_ data: ArraySlice<UInt8>) -> Bool
    func linesAboveCursor() -> [String]
enum ProcessReaper
    static func hangUp(_ pid: pid_t, grace: TimeInterval = 2)

// mac/Tests/ClarkTests/TestSupport.swift
final class TemporaryDirectory
    let path: String
    init(file: StaticString = #filePath, line: UInt = #line)
    func makeDirectory(_ relative: String) -> String
    func write(_ relative: String, _ content: String, permissions: Int = 0o644) -> String
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool
```

**Review Focus:**
- Item 4 (pedido de leitura da área de transferência): `testClipboardReplyNeverReachesTheProcess` e `testOnlyTheClipboardReplyIsDropped`, em `AgentTerminalViewTests.swift`.

- [ ] **Step 1: Preparar o pacote**

O `Package.swift` passa a ter o alvo `Clark` e a dependência. O `main.swift` é o provisório.

**Arquivo:** `mac/Package.swift`

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clark",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Fixado por revisão (tag v1.19.0). O Package.resolved é versionado.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm",
                 revision: "464df5207fc2432e16c9a23abe538187196daf5f")
    ],
    targets: [
        .target(name: "ClarkCore", path: "Sources/ClarkCore"),
        .executableTarget(
            name: "Clark",
            dependencies: ["ClarkCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/Clark"
        ),
        .testTarget(name: "ClarkCoreTests", dependencies: ["ClarkCore"], path: "Tests/ClarkCoreTests"),
        .testTarget(name: "ClarkTests", dependencies: ["Clark", "ClarkCore"], path: "Tests/ClarkTests")
    ]
)
```

**Arquivo:** `mac/Package.resolved`

```json
{
  "pins" : [
    {
      "identity" : "swift-argument-parser",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/apple/swift-argument-parser",
      "state" : {
        "revision" : "6a52f3251125d74daf04fcbd5e6f08a75d074382",
        "version" : "1.8.2"
      }
    },
    {
      "identity" : "swiftterm",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/migueldeicaza/SwiftTerm",
      "state" : {
        "revision" : "464df5207fc2432e16c9a23abe538187196daf5f"
      }
    }
  ],
  "version" : 2
}
```

**Arquivo:** `mac/Sources/Clark/main.swift`

```swift
import ClarkCore

// Provisório: a janela entra na tarefa 13.
print("clark \(ClarkVersion.current)")
```

- [ ] **Step 2: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkTests/TestSupport.swift`

```swift
import Foundation
import XCTest

/// Pasta temporária de um teste, apagada no fim.
final class TemporaryDirectory {
    let path: String

    init(file: StaticString = #filePath, line: UInt = #line) {
        let base = NSTemporaryDirectory() + "clark-tests-" + UUID().uuidString
        do {
            try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        } catch {
            XCTFail("não criou a pasta temporária: \(error)", file: file, line: line)
        }
        // /var é um link para /private/var: os testes comparam com o caminho real
        if let real = realpath(base, nil) {
            path = String(cString: real)
            free(real)
        } else {
            path = base
        }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    @discardableResult
    func makeDirectory(_ relative: String) -> String {
        let full = path + "/" + relative
        try? FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }

    @discardableResult
    func write(_ relative: String, _ content: String, permissions: Int = 0o644) -> String {
        let full = path + "/" + relative
        makeDirectory((relative as NSString).deletingLastPathComponent)
        FileManager.default.createFile(atPath: full, contents: Data(content.utf8),
                                       attributes: [.posixPermissions: permissions])
        return full
    }
}

/// Gira o run loop principal até a condição valer. A saída dos processos chega pela fila principal.
@discardableResult
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return true
}
```

**Arquivo:** `mac/Tests/ClarkTests/AgentTerminalViewTests.swift`

```swift
import ClarkCore
import SwiftTerm
import XCTest
@testable import Clark

final class AgentTerminalViewTests: XCTestCase {
    private let environment = ["TERM=xterm-256color", "PATH=/usr/bin:/bin"]

    private func makeView() -> AgentTerminalView {
        AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    }

    /// Roda o script até o fim e devolve o terminal.
    private func run(_ script: String, configure: (AgentTerminalView) -> Void = { _ in }) -> AgentTerminalView {
        let view = makeView()
        let exited = expectation(description: "processo terminou")
        configure(view)
        let previous = view.onExit
        view.onExit = { code in
            previous?(code)
            exited.fulfill()
        }
        view.startProcess(executable: "/bin/sh", args: ["-c", script], environment: environment,
                          currentDirectory: "/")
        wait(for: [exited], timeout: 10)
        return view
    }

    func testOutputBellAndExitReachTheHooks() {
        var outputs = 0, bells = 0, inputs = 0
        var code: Int32?
        let view = run("printf 'ola\\nmundo\\n\\a'; exit 3") { view in
            view.onOutput = { outputs += 1 }
            view.onBell = { bells += 1 }
            view.onUserInput = { inputs += 1 }
            view.onExit = { code = $0 }
        }
        XCTAssertGreaterThan(outputs, 0)
        XCTAssertEqual(bells, 1)
        XCTAssertEqual(inputs, 0)
        XCTAssertEqual(code, 3)
        XCTAssertTrue(view.hasExited)
        XCTAssertEqual(view.linesAboveCursor(), ["ola", "mundo"])
    }

    func testTerminalRepliesAreNotUserInput() {
        var inputs = 0
        // ESC[6n pede a posição do cursor: o emulador responde sozinho, sem tecla do usuário.
        _ = run("printf '\\033[6n'; sleep 0.3") { view in view.onUserInput = { inputs += 1 } }
        XCTAssertEqual(inputs, 0)
    }

    func testTypingCountsAsInputAndEnterAfterExitAsksRestart() {
        var inputs = 0, restarts = 0
        let view = makeView()
        let exited = expectation(description: "processo terminou")
        view.onUserInput = { inputs += 1 }
        view.onRestartRequested = { restarts += 1 }
        view.onExit = { _ in exited.fulfill() }
        view.startProcess(executable: "/bin/sh", args: ["-c", "read x; exit 0"], environment: environment,
                          currentDirectory: "/")
        view.send(txt: "a\r")
        wait(for: [exited], timeout: 10)
        XCTAssertEqual(inputs, 1)

        view.send(txt: "x")
        XCTAssertEqual(restarts, 0, "só o Enter reabre")
        view.send(txt: "\r")
        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(inputs, 1, "tecla em GAME OVER não é entrada do agente")
    }

    func testMarkExitedMakesEnterAskRestartWithoutAProcess() {
        var restarts = 0
        let view = makeView()
        view.onRestartRequested = { restarts += 1 }
        view.markExited()
        view.send(txt: "\r")
        XCTAssertEqual(restarts, 1)
    }

    func testExitCodeComesFromTheWaitStatus() {
        XCTAssertNil(AgentTerminalView.exitCode(fromWaitStatus: nil))
        XCTAssertEqual(AgentTerminalView.exitCode(fromWaitStatus: 0), 0)
        XCTAssertEqual(AgentTerminalView.exitCode(fromWaitStatus: 3 << 8), 3)
        XCTAssertEqual(AgentTerminalView.exitCode(fromWaitStatus: 255 << 8), 255)
    }

    func testOnlyWebLinksOpen() {
        var opened: [String] = []
        let view = makeView()
        view.openURL = { opened.append($0.absoluteString) }
        for link in ["file:///etc/passwd", "javascript:alert(1)", "x-apple.systempreferences:", "ssh://host",
                     "", "sem esquema", "/bin/sh"] {
            view.requestOpenLink(source: view, link: link, params: [:])
        }
        XCTAssertEqual(opened, [])

        view.requestOpenLink(source: view, link: "https://example.com/a?b=1", params: [:])
        view.requestOpenLink(source: view, link: "HTTP://example.com", params: [:])
        XCTAssertEqual(opened, ["https://example.com/a?b=1", "HTTP://example.com"])
    }

    func testClipboardReplyNeverReachesTheProcess() {
        let view = makeView()
        view.startProcess(executable: "/bin/sh", args: ["-c", "printf pronto; read x"], environment: environment,
                          currentDirectory: "/")
        let terminal = view.getTerminal()
        func firstLine() -> String { terminal.getLine(row: 0)?.translateToString(trimRight: true) ?? "" }
        XCTAssertTrue(waitUntil { firstLine() == "pronto" })

        // O que o SwiftTerm manda ao processo quando a saída pede `ESC ] 52 ; c ; ?`:
        // o clipboard do usuário em base64. O tty ecoa o que chega, então dá para ver se passou.
        view.send(source: terminal, data: Array("\u{1b}]52;c;c2VncmVkbw==\u{1b}\\".utf8)[...])
        view.send(source: terminal, data: Array("eco".utf8)[...])
        XCTAssertTrue(waitUntil { firstLine().hasSuffix("eco") })
        XCTAssertEqual(firstLine(), "prontoeco")
        ProcessReaper.hangUp(view.process.shellPid, grace: 0.3)
    }

    func testOnlyTheClipboardReplyIsDropped() {
        func isClipboardReply(_ bytes: [UInt8]) -> Bool { AgentTerminalView.isClipboardReply(bytes[...]) }
        XCTAssertTrue(isClipboardReply(Array("\u{1b}]52;c;c2VncmVkbw==\u{1b}\\".utf8)))
        XCTAssertTrue(isClipboardReply(Array("\u{1b}]52;;\u{1b}\\".utf8)), "clipboard vazio")
        XCTAssertTrue(isClipboardReply([0x9d] + Array("52;c;c2VncmVkbw==".utf8) + [0x9c]), "controles de 8 bits")

        XCTAssertFalse(isClipboardReply(Array("\u{1b}[5;1R".utf8)), "posição do cursor")
        XCTAssertFalse(isClipboardReply(Array("\u{1b}]11;rgb:0d0d/1111/1717\u{1b}\\".utf8)), "cor de fundo")
        XCTAssertFalse(isClipboardReply(Array("\u{1b}]520;x\u{1b}\\".utf8)))
        XCTAssertFalse(isClipboardReply(Array("52;c;c2VncmVkbw==".utf8)))
        XCTAssertFalse(isClipboardReply([]))
        XCTAssertFalse(isClipboardReply([0x1b]))
    }

    func testApplySetsFontAndColors() {
        let view = makeView()
        view.apply(TerminalAppearance(theme: .dark, fontName: "Menlo", fontSize: 15))
        XCTAssertEqual(view.font.pointSize, 15)
        XCTAssertEqual(view.font.familyName, "Menlo")
        XCTAssertEqual(view.nativeBackgroundColor, Theme.dark.bg.nsColor)

        view.apply(TerminalAppearance(theme: .dark, fontName: "Fonte Que Nao Existe", fontSize: 11))
        XCTAssertEqual(view.font.pointSize, 11, "fonte desconhecida cai na monoespaçada do sistema")
    }

    func testHangUpKillsAProcessThatIgnoresSIGHUP() {
        let view = makeView()
        view.startProcess(executable: "/bin/sh", args: ["-c", "trap '' HUP; printf pronto; read x"],
                          environment: environment, currentDirectory: "/")
        XCTAssertTrue(waitUntil { view.linesAboveCursor().isEmpty && view.getTerminal().getCursorLocation().x == 6 })
        let pid = view.process.shellPid
        XCTAssertEqual(kill(pid, 0), 0)

        ProcessReaper.hangUp(pid, grace: 0.3)
        // Um zumbi ainda responde ao sinal 0: sumir da tabela prova que o filho foi recolhido.
        XCTAssertTrue(waitUntil(timeout: 5) { kill(pid, 0) != 0 })
    }

    func testHangUpIgnoresInvalidPids() {
        ProcessReaper.hangUp(0)
        ProcessReaper.hangUp(1)
        ProcessReaper.hangUp(-1)
    }
}
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkTests/AgentTerminalViewTests.swift:9:32: error: cannot find type 'AgentTerminalView' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 4: Escrever o código**

**Arquivo:** `mac/Sources/Clark/RGB+AppKit.swift`

```swift
import AppKit
import ClarkCore

/// Cores do tema nos tipos do AppKit e do CoreGraphics.
extension RGB {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}
```

**Arquivo:** `mac/Sources/Clark/AgentTerminalView.swift`

```swift
import AppKit
import ClarkCore
import SwiftTerm

/// Aparência dos terminais, igual para todos os agentes.
struct TerminalAppearance {
    var theme: Theme
    var fontName: String
    var fontSize: Double

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

/// Terminal de um agente: traduz os ganchos do SwiftTerm em eventos simples.
final class AgentTerminalView: LocalProcessTerminalView {
    static let scrollbackLines = 20_000

    var onOutput: (() -> Void)?
    var onUserInput: (() -> Void)?
    var onBell: (() -> Void)?
    var onExit: ((Int32?) -> Void)?
    var onResize: (() -> Void)?
    var onRestartRequested: (() -> Void)?
    /// Abre um link no navegador. Trocado nos testes.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private(set) var hasExited = false
    private var replying = false

    /// Código de saída a partir do status bruto que o SwiftTerm repassa do `waitpid`.
    static func exitCode(fromWaitStatus status: Int32?) -> Int32? {
        guard let status else { return nil }
        return (status >> 8) & 0xff
    }

    func apply(_ appearance: TerminalAppearance) {
        let theme = appearance.theme
        nativeBackgroundColor = theme.bg.nsColor
        nativeForegroundColor = theme.ink.nsColor
        caretColor = theme.accent.nsColor
        caretTextColor = theme.bg.nsColor
        selectedTextBackgroundColor = theme.accent.mix(theme.bg, 0.55).nsColor
        installColors(theme.term.map { color in
            SwiftTerm.Color(red8: Self.byte(color.r), green8: Self.byte(color.g), blue8: Self.byte(color.b))
        })
        font = appearance.font
    }

    private static func byte(_ value: Double) -> UInt16 {
        UInt16((max(0, min(1, value)) * 255).rounded())
    }

    /// Sem processo vivo, o Enter pede a reabertura. Usado quando o processo nem chegou a abrir.
    func markExited() {
        hasExited = true
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
    }

    /// Resposta do emulador a um pedido de leitura do clipboard (OSC 52): `ESC ] 52 ; …`.
    static func isClipboardReply(_ data: ArraySlice<UInt8>) -> Bool {
        let bytes = Array(data)
        let body: ArraySlice<UInt8>
        if bytes.starts(with: [0x1b, 0x5d]) {
            body = bytes.dropFirst(2)
        } else if bytes.first == 0x9d {
            body = bytes.dropFirst()
        } else {
            return false
        }
        return body.starts(with: Array("52;".utf8))
    }

    // Respostas do próprio emulador (posição do cursor, foco) passam por aqui e não contam como tecla.
    override func send(source: Terminal, data: ArraySlice<UInt8>) {
        // O SwiftTerm responde ao OSC 52 de leitura com o clipboard do usuário, e a classe-base não
        // deixa trocar isso. Um texto qualquer na saída do agente leria o que você copiou: a resposta
        // morre aqui. Escrever no clipboard (o `copiar` dos programas) continua valendo.
        if Self.isClipboardReply(data) { return }
        replying = true
        defer { replying = false }
        super.send(source: source, data: data)
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if hasExited {
            if data.contains(13) { onRestartRequested?() }
            return
        }
        if !replying { onUserInput?() }
        super.send(source: source, data: data)
    }

    override func bell(source: Terminal) {
        onBell?()
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        hasExited = true
        super.processTerminated(source, exitCode: exitCode)
        onExit?(Self.exitCode(fromWaitStatus: exitCode))
    }

    // Só http e https: um link `file:` ou de outro esquema vindo da saída do agente não abre nada.
    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        openURL(url)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { onResize?() }
    }

    /// Linhas visíveis acima do cursor, de cima para baixo.
    func linesAboveCursor() -> [String] {
        let terminal = getTerminal()
        let cursorRow = terminal.getCursorLocation().y
        guard cursorRow > 0 else { return [] }
        return (0..<cursorRow).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
    }
}

/// Encerra o processo de um agente fechado e recolhe o filho, para não deixar zumbi.
enum ProcessReaper {
    /// SIGHUP; se o processo ignorar por `grace` segundos, SIGKILL.
    static func hangUp(_ pid: pid_t, grace: TimeInterval = 2) {
        guard pid > 1 else { return }
        kill(pid, SIGHUP)
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            let attempts = max(1, Int(grace / 0.1))
            for _ in 0..<attempts {
                // Diferente de zero: o filho já foi recolhido aqui (pid) ou pelo SwiftTerm (-1).
                if waitpid(pid, &status, WNOHANG) != 0 { return }
                usleep(100_000)
            }
            kill(pid, SIGKILL)
            waitpid(pid, &status, 0)
        }
    }
}
```

- [ ] **Step 5: Rodar os testes**

Run: `./swiftpm.sh test --filter 'AgentTerminalViewTests'`
Expected: PASS, `Executed 11 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 134 tests, with 0 failures`.

Run: `grep -c '"identity"' Package.resolved && grep -c 464df5207fc2432e16c9a23abe538187196daf5f Package.resolved`
Expected: `2` e `1`. O `Package.resolved` continua com os dois pacotes do plano e o SwiftTerm na revisão fixada.

- [ ] **Step 6: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Package.swift`
- `mac/Package.resolved`
- `mac/Sources/Clark/main.swift`
- `mac/Tests/ClarkTests/TestSupport.swift`
- `mac/Tests/ClarkTests/AgentTerminalViewTests.swift`
- `mac/Sources/Clark/RGB+AppKit.swift`
- `mac/Sources/Clark/AgentTerminalView.swift`

---

### Task 10: Ambiente do shell de login

Captura o ambiente do shell de login uma vez, com limite de tempo. Quando a captura falha, vale o ambiente do próprio app com um `PATH` padrão. Também sonda o que o rc do shell devolve a um agente que nasceu sem a variável e monta o aviso da barra.

**Files:**
- Create: `mac/Sources/Clark/ShellEnvironment.swift`
- Test: `mac/Tests/ClarkTests/ShellEnvironmentTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 1: `PathTools`
  - Task 5: `EnvPolicy`, `ShellEnvParser`
  - Task 9: `TemporaryDirectory`
- Produces:

```swift
// mac/Sources/Clark/ShellEnvironment.swift
enum ShellEnvironment
    struct Capture
        let variables: [String: String]
        let captured: Bool
    static let defaultShell = "/bin/zsh"
    static func shellPath(processEnvironment: [String: String]) -> String
    static func capture(shell: String, processEnvironment: [String: String], timeout: TimeInterval = 5) -> Capture
    static func secretsRestoredByShell(shell: String, environment: [String: String], timeout: TimeInterval = 3) -> [String]
    static func restoredSecretsWarning(_ names: [String], globalAllow: [String]) -> String?
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkTests/ShellEnvironmentTests.swift`

```swift
import ClarkCore
import XCTest
@testable import Clark

final class ShellEnvironmentTests: XCTestCase {
    private let temp = TemporaryDirectory()
    private let base = ["PATH": "/usr/bin:/bin", "CLARK_TESTE": "valor com espaço"]

    /// Um "shell" que é um script: recebe `-l -i -c <comando>` como o shell de verdade.
    private func fakeShell(_ body: String) -> String {
        temp.write("shell-\(UUID().uuidString)", "#!/bin/sh\n" + body + "\n", permissions: 0o755)
    }

    func testCapturesTheEnvironmentOfTheShell() {
        let capture = ShellEnvironment.capture(shell: "/bin/sh", processEnvironment: base)
        XCTAssertTrue(capture.captured)
        XCTAssertEqual(capture.variables["CLARK_TESTE"], "valor com espaço")
        XCTAssertNotNil(capture.variables["PATH"])
        XCTAssertNil(capture.variables["SHLVL"], "variável que só descreve o shell da captura não passa")
    }

    func testVariablesSetByTheProfileAreCaptured() {
        let shell = fakeShell("export SO_DO_PERFIL=sim\neval \"$4\"")
        let capture = ShellEnvironment.capture(shell: shell, processEnvironment: base)
        XCTAssertTrue(capture.captured)
        XCTAssertEqual(capture.variables["SO_DO_PERFIL"], "sim")
    }

    func testNoiseBeforeTheMarkerIsIgnored() {
        let shell = fakeShell("echo 'bem-vindo ao shell'\necho 'FALSA=1'\neval \"$4\"")
        let capture = ShellEnvironment.capture(shell: shell, processEnvironment: base)
        XCTAssertTrue(capture.captured)
        XCTAssertNil(capture.variables["FALSA"])
        XCTAssertEqual(capture.variables["CLARK_TESTE"], "valor com espaço")
    }

    func testMissingShellFallsBack() {
        let capture = ShellEnvironment.capture(shell: temp.path + "/nao-existe", processEnvironment: base)
        XCTAssertFalse(capture.captured)
        XCTAssertEqual(capture.variables["PATH"], ShellEnvParser.defaultPath)
        XCTAssertEqual(capture.variables["CLARK_TESTE"], "valor com espaço")
    }

    func testOutputWithoutTheMarkerFallsBack() {
        let capture = ShellEnvironment.capture(shell: fakeShell("echo oi"), processEnvironment: base)
        XCTAssertFalse(capture.captured)
        XCTAssertEqual(capture.variables["PATH"], ShellEnvParser.defaultPath)
    }

    func testShellThatNeverExitsTimesOut() {
        let started = Date()
        let capture = ShellEnvironment.capture(shell: fakeShell("exec sleep 30"), processEnvironment: base,
                                               timeout: 0.5)
        XCTAssertFalse(capture.captured)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func testBackgroundChildHoldingThePipeDoesNotBlock() {
        // O `sleep` herda a saída do shell e segura o pipe aberto depois que o shell sai.
        let started = Date()
        let capture = ShellEnvironment.capture(shell: fakeShell("sleep 4 &\neval \"$4\""), processEnvironment: base)
        XCTAssertTrue(capture.captured)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    // MARK: o que o rc devolve

    func testSecretExportedByTheShellRcIsReported() {
        // O agente nasce sem a variável, mas o rc lido por todo `$SHELL -c` a exporta de novo.
        let shell = fakeShell("export ACME_API_KEY=segredo-acme\nexport SO_DO_RC=sim\neval \"$2\"")
        // O que o agente não recebe não conta como devolvido: o `GITHUB_TOKEN` sai antes da sonda.
        let environment = base.merging(["GITHUB_TOKEN": "segredo"]) { $1 }
        XCTAssertEqual(ShellEnvironment.secretsRestoredByShell(shell: shell, environment: environment),
                       ["ACME_API_KEY"])
    }

    func testZshenvIsReadByEveryZshCommandAndZshrcIsNot() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/bin/zsh"), "sem zsh")
        temp.write("home/.zshenv", "export ACME_API_KEY=segredo-acme\n")
        temp.write("home/.zshrc", "export BETA_API_KEY=segredo-beta\n")
        let environment = ["PATH": "/usr/bin:/bin", "HOME": temp.path + "/home"]
        XCTAssertEqual(ShellEnvironment.secretsRestoredByShell(shell: "/bin/zsh", environment: environment),
                       ["ACME_API_KEY"])
    }

    func testShellThatRestoresNothingOrFailsReportsNothing() {
        let environment = base.merging(["GITHUB_TOKEN": "segredo"]) { $1 }
        XCTAssertEqual(ShellEnvironment.secretsRestoredByShell(shell: "/bin/sh", environment: environment), [])
        XCTAssertEqual(ShellEnvironment.secretsRestoredByShell(shell: temp.path + "/nao-existe",
                                                               environment: environment), [])
    }

    func testRestoredSecretsWarningListsNamesAndSkipsTheGlobalAllow() {
        XCTAssertNil(ShellEnvironment.restoredSecretsWarning([], globalAllow: []))
        XCTAssertNil(ShellEnvironment.restoredSecretsWarning(["GH_TOKEN"], globalAllow: ["GH_TOKEN"]),
                     "o `env_allow` do topo já libera a variável para todos os agentes")
        XCTAssertEqual(ShellEnvironment.restoredSecretsWarning(["ACME_API_KEY", "GH_TOKEN"], globalAllow: ["GH_TOKEN"]),
                       "rc do shell devolve variaveis filtradas: ACME_API_KEY")
        XCTAssertEqual(
            ShellEnvironment.restoredSecretsWarning(["A_KEY", "B_KEY", "C_KEY", "D_KEY", "E_KEY"], globalAllow: []),
            "rc do shell devolve variaveis filtradas: A_KEY, B_KEY, C_KEY (+2)")
    }

    func testShellPathAcceptsOnlyAbsoluteExecutables() {
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: ["SHELL": "/bin/sh"]), "/bin/sh")
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: [:]), "/bin/zsh")
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: ["SHELL": "zsh"]), "/bin/zsh")
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: ["SHELL": "/nao/existe/zsh"]), "/bin/zsh")
        XCTAssertEqual(ShellEnvironment.shellPath(processEnvironment: ["SHELL": "/etc/hosts"]), "/bin/zsh",
                       "arquivo sem permissão de execução não é shell")
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkTests/ShellEnvironmentTests.swift:15:23: error: cannot find 'ShellEnvironment' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/Clark/ShellEnvironment.swift`

```swift
import ClarkCore
import Foundation

/// Ambiente do shell de login, lido uma vez na abertura do app.
enum ShellEnvironment {
    struct Capture {
        let variables: [String: String]
        /// false: a captura falhou e `variables` é o ambiente do app com o `PATH` padrão.
        let captured: Bool
    }

    static let defaultShell = "/bin/zsh"
    private static let maxOutputBytes = 4 * 1024 * 1024

    /// `SHELL` do ambiente quando é um executável de caminho absoluto; senão `/bin/zsh`.
    static func shellPath(processEnvironment: [String: String]) -> String {
        guard let shell = processEnvironment["SHELL"], shell.hasPrefix("/"),
              PathTools.isExecutableFile(shell) else { return defaultShell }
        return shell
    }

    /// Roda `shell -l -i -c` imprimindo o marcador e `env -0`. Bloqueia até `timeout` segundos:
    /// chamar fora da thread principal.
    static func capture(shell: String, processEnvironment: [String: String],
                        timeout: TimeInterval = 5) -> Capture {
        guard let variables = environment(of: shell, arguments: ["-l", "-i"], startingFrom: processEnvironment,
                                          timeout: timeout) else {
            return Capture(variables: ShellEnvParser.fallback(processEnvironment: processEnvironment),
                           captured: false)
        }
        return Capture(variables: variables, captured: true)
    }

    /// Nomes com cara de segredo que um shell aberto por um agente devolve ao ambiente.
    /// O agente nasce sem eles, mas todo `$SHELL -c` relê o rc do shell (no zsh, o `~/.zshenv`),
    /// e o que o rc exporta volta. A lista sai vazia também quando a sonda falha.
    /// Bloqueia até `timeout` segundos: chamar fora da thread principal.
    static func secretsRestoredByShell(shell: String, environment: [String: String],
                                       timeout: TimeInterval = 3) -> [String] {
        let filtered = environment.filter { !EnvPolicy.isSecret($0.key) }
        guard let seen = self.environment(of: shell, arguments: [], startingFrom: filtered,
                                          timeout: timeout) else { return [] }
        return seen.keys.filter(EnvPolicy.isSecret).sorted()
    }

    /// Aviso da barra para os nomes que o rc devolve. Os do `env_allow` do topo ficam de fora,
    /// porque já valem para todos os agentes. Só nomes, nunca valores.
    static func restoredSecretsWarning(_ names: [String], globalAllow: [String]) -> String? {
        let restored = names.filter { !globalAllow.contains($0) }
        guard !restored.isEmpty else { return nil }
        let more = restored.count > 3 ? " (+\(restored.count - 3))" : ""
        return "rc do shell devolve variaveis filtradas: " + restored.prefix(3).joined(separator: ", ") + more
    }

    /// Roda `shell <arguments> -c` imprimindo o marcador e `env -0` e devolve o ambiente lido.
    /// nil: o shell não abriu, não saiu a tempo ou a saída não tem o marcador.
    private static func environment(of shell: String, arguments: [String],
                                    startingFrom environment: [String: String],
                                    timeout: TimeInterval) -> [String: String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments + ["-c", ShellEnvParser.command]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let lock = NSLock()
        var output = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock()
            if output.count < maxOutputBytes { output.append(chunk) }
            lock.unlock()
        }
        defer { pipe.fileHandleForReading.readabilityHandler = nil }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Espera o shell sair, não o fim do pipe: um processo deixado em segundo plano pelo rc
        // segura o pipe aberto e a leitura até o fim nunca voltaria.
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            return nil
        }
        // O que o shell escreveu logo antes de sair ainda pode estar a caminho.
        for _ in 0..<10 {
            lock.lock()
            let snapshot = output
            lock.unlock()
            if let parsed = ShellEnvParser.parse(snapshot) { return parsed }
            usleep(20_000)
        }
        return nil
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'ShellEnvironmentTests'`
Expected: PASS, `Executed 12 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 146 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkTests/ShellEnvironmentTests.swift`
- `mac/Sources/Clark/ShellEnvironment.swift`

---

### Task 11: Vistas de pixel: botões, cabeçalho, card, barra e lista

As vistas desenhadas à mão, todas em pixel inteiro e sem antialias: o desenho básico (`Pixel`, `PixelView`), os botões, o cabeçalho do agente, o card da lista lateral, a barra superior com a barra de avisos e a tela vazia, e a lista lateral. Os testes desenham cada vista num bitmap e conferem os pixels, sem depender da tela.

**Files:**
- Create: `mac/Sources/Clark/Pixel.swift`
- Create: `mac/Sources/Clark/PixelButton.swift`
- Create: `mac/Sources/Clark/AgentHeaderView.swift`
- Create: `mac/Sources/Clark/AgentCardView.swift`
- Create: `mac/Sources/Clark/TopBarView.swift`
- Create: `mac/Sources/Clark/SidebarView.swift`
- Test: `mac/Tests/ClarkTests/RenderedImage.swift`
- Test: `mac/Tests/ClarkTests/PixelViewsTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 2: `PixelFont`, `RGB`, `Theme`
  - Task 4: `AgentState`
- Produces:

```swift
// mac/Sources/Clark/Pixel.swift
enum Pixel
    static func fill(_ context: CGContext, _ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: RGB, alpha: Double = 1)
    static func frame(_ context: CGContext, _ x: Int, _ y: Int, _ width: Int, _ height: Int, thickness: Int, _ color: RGB)
    static func text(_ context: CGContext, _ text: String, _ x: Int, _ y: Int, scale: Int, _ color: RGB, shadow: RGB? = nil)
    static func monoFont(size: CGFloat, bold: Bool = false) -> NSFont
    static func monoWidth(_ text: String, size: CGFloat, bold: Bool = false) -> Int
    static func mono(_ context: CGContext, _ text: String, _ x: Int, _ y: Int, width: Int, size: CGFloat, _ color: RGB, truncate: NSLineBreakMode = .byTruncatingTail, bold: Bool = false)
class PixelView: NSView
    var theme = Theme.dark
    func render(_ context: CGContext, width: Int, height: Int)
enum StateLabel
    static func text(_ state: AgentState, time: Double) -> String
    static func color(_ state: AgentState, theme: Theme) -> RGB
    static func isAnimated(_ state: AgentState) -> Bool

// mac/Sources/Clark/PixelButton.swift
final class PixelButton: PixelView
    enum Style
        case normal
        case primary
        case mini
        case miniClose
    static let barHeight = 27
    var title: String
    var onClick: (() -> Void)?
    let style: Style
    private(set) var isHovering = false
    private(set) var isPressed = false
    init(title: String, style: Style = .normal, toolTip: String? = nil, onClick: (() -> Void)? = nil)
    var fittingWidth: Int

// mac/Sources/Clark/AgentHeaderView.swift
struct AgentSnapshot: Equatable
    var name: String
    var company: String
    var color: RGB
    var path: String
    var state: AgentState
    var preview: [String]
final class AgentHeaderView: PixelView
    static let height = 30
    var snapshot: AgentSnapshot
    var time: Double
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    init(snapshot: AgentSnapshot)

// mac/Sources/Clark/AgentCardView.swift
final class AgentCardView: PixelView
    static let height = 86
    var snapshot: AgentSnapshot
    var index = 1
    var isActive = false
    var time: Double
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var isHovering = false
    init(snapshot: AgentSnapshot)
    static func closeRect(width: Int) -> CGRect
    func setHovering(_ hovering: Bool)

// mac/Sources/Clark/TopBarView.swift
struct AgentStats: Equatable
    var agents = 0
    var working = 0
    var done = 0
    var idle = 0
    var exited = 0
    init()
    init(states: [AgentState])
final class TopBarView: PixelView
    static let height = 49
    var stats = AgentStats()
    let folderButton = PixelButton(title: "DIR ~", toolTip: "Pasta onde os novos agentes abrem (⌘D)")
    let layoutButton = PixelButton(title: "FOCO", toolTip: "Alternar layout foco / grade (⌘L)")
    let addButton = PixelButton(title: "+ AGENT", style: .primary, toolTip: "Novo agente (⌘N)")
    static func folderTitle(shortPath: String) -> String
final class WarningBarView: PixelView
    static let height = 22
    private(set) var messages: [String]
    var onChange: (() -> Void)?
    func add(_ message: String)
final class EmptyStateView: PixelView
    var isLoading = true
    var time: Double
    var onAdd: ((Int) -> Void)?

// mac/Sources/Clark/SidebarView.swift
final class SidebarView: PixelView
    static let width = 310
    let closeAllButton = PixelButton(title: "FECHAR TODOS", style: .miniClose, toolTip: "Fechar os outros agentes (ou todos)")
    private(set) var cards: [AgentCardView]
    func setCards(_ newCards: [AgentCardView])
final class FlippedView: NSView
    var onLayout: (() -> Void)?

// mac/Tests/ClarkTests/RenderedImage.swift
struct RenderedImage
    let width: Int
    let height: Int
    init(_ view: PixelView, width: Int, height: Int, file: StaticString = #filePath, line: UInt = #line)
    func isColor(_ color: RGB, atX x: Int, y: Int) -> Bool
    func count(_ color: RGB, x: Int = 0, y: Int = 0, width: Int? = nil, height: Int? = nil) -> Int
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkTests/RenderedImage.swift`

```swift
import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// Desenho de uma `PixelView` num bitmap próprio, com a origem em cima à esquerda.
struct RenderedImage {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private let bytesPerRow: Int

    init(_ view: PixelView, width: Int, height: Int, file: StaticString = #filePath, line: UInt = #line) {
        self.width = width
        self.height = height
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            XCTFail("não criou o bitmap", file: file, line: line)
            bytes = []
            bytesPerRow = 0
            return
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(false)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        view.render(context, width: width, height: height)
        NSGraphicsContext.current = previous
        bytesPerRow = context.bytesPerRow
        if let data = context.data {
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                              count: bytesPerRow * height))
        } else {
            bytes = []
        }
    }

    private static func bytes(of color: RGB) -> [Int] {
        [color.r, color.g, color.b].map { Int(($0 * 255).rounded()) }
    }

    /// O pixel tem esta cor, com folga de 1 em cada componente.
    func isColor(_ color: RGB, atX x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height, !bytes.isEmpty else { return false }
        let offset = y * bytesPerRow + x * 4
        return zip(Self.bytes(of: color), 0..<3).allSatisfy { abs(Int(bytes[offset + $0.1]) - $0.0) <= 1 }
    }

    /// Quantos pixels do retângulo têm esta cor.
    func count(_ color: RGB, x: Int = 0, y: Int = 0, width: Int? = nil, height: Int? = nil) -> Int {
        let maxX = min(self.width, x + (width ?? self.width)), maxY = min(self.height, y + (height ?? self.height))
        var total = 0
        for row in max(0, y)..<max(max(0, y), maxY) {
            for column in max(0, x)..<max(max(0, x), maxX) where isColor(color, atX: column, y: row) {
                total += 1
            }
        }
        return total
    }
}
```

**Arquivo:** `mac/Tests/ClarkTests/PixelViewsTests.swift`

```swift
import AppKit
import ClarkCore
import XCTest
@testable import Clark

/// As views desenhadas à mão, conferidas pixel a pixel num bitmap.
final class PixelViewsTests: XCTestCase {
    private let theme = Theme.dark
    /// Cor que não existe no tema: o que aparecer nela veio do agente.
    private let magenta = RGB(r: 1, g: 0, b: 1)

    private func snapshot(_ state: AgentState = .idle, name: String = "AGENT 1", company: String = "ACME",
                          preview: [String] = []) -> AgentSnapshot {
        AgentSnapshot(name: name, company: company, color: magenta, path: "~/Projetos/acme", state: state,
                      preview: preview)
    }

    /// Clique no ponto (x, y) da view, contado de cima para baixo. O evento leva a coordenada
    /// de janela, que cresce para cima.
    private func click(_ view: NSView, x: CGFloat, y: CGFloat, count: Int = 1, up: Bool = false) -> NSEvent {
        let location = NSPoint(x: x, y: view.bounds.height - y)
        let event = NSEvent.mouseEvent(with: up ? .leftMouseUp : .leftMouseDown, location: location,
                                       modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                       eventNumber: 0, clickCount: count, pressure: 1)
        return event!
    }

    // MARK: rótulos

    func testStateLabelAnimatesOnlyBootAndWorking() {
        XCTAssertEqual(StateLabel.text(.working, time: 0), "WORKING")
        XCTAssertEqual(StateLabel.text(.working, time: 0.25), "WORKING.")
        XCTAssertEqual(StateLabel.text(.working, time: 0.75), "WORKING...")
        XCTAssertEqual(StateLabel.text(.working, time: 1), "WORKING")
        XCTAssertEqual(StateLabel.text(.boot, time: 0.5), "BOOT..")
        XCTAssertEqual(StateLabel.text(.idle, time: 0.75), "IDLE")
        XCTAssertEqual(StateLabel.text(.done, time: 0.75), "DONE!")
        XCTAssertEqual(StateLabel.text(.exited, time: 0.75), "GAME OVER")
    }

    func testStateColors() {
        XCTAssertEqual(StateLabel.color(.working, theme: theme), theme.green)
        XCTAssertEqual(StateLabel.color(.done, theme: theme), theme.yellow)
        XCTAssertEqual(StateLabel.color(.boot, theme: theme), theme.yellow)
        XCTAssertEqual(StateLabel.color(.idle, theme: theme), theme.dim)
        XCTAssertEqual(StateLabel.color(.exited, theme: theme), theme.red)
        XCTAssertFalse(StateLabel.isAnimated(.idle))
        XCTAssertFalse(StateLabel.isAnimated(.exited))
        XCTAssertTrue(StateLabel.isAnimated(.done))
    }

    func testEveryLabelFitsThePixelFont() {
        // A fonte pixel só tem ASCII maiúsculo: um texto fora dela sairia como "?".
        let labels = AgentState.allCases.map { StateLabel.text($0, time: 0.75) }
            + ["CLARK", "AGENTS 16", "WORKING 16", "DONE 16", "IDLE 16", "GAME OVER 16", "EM FOCO", "AGENTES 16",
               "SEM PERMISSOES", "NENHUM AGENTE ONLINE", "LENDO O AMBIENTE DO SHELL", "PRESS START  -  CMD+N"]
        for label in labels {
            XCTAssertEqual(PixelFont.normalize(label), label, label)
            XCTAssertFalse(PixelFont.fit(label, scale: 1, width: 10_000).contains("?"), label)
        }
    }

    // MARK: botão

    func testButtonWidthFollowsTheTitle() {
        XCTAssertLessThan(PixelButton(title: "A").fittingWidth, PixelButton(title: "ABCDEF").fittingWidth)
        XCTAssertLessThan(PixelButton(title: "ABC", style: .mini).fittingWidth, PixelButton(title: "ABC").fittingWidth)
    }

    func testButtonFacesAndHardShadow() {
        let normal = RenderedImage(PixelButton(title: "OK"), width: 80, height: 27)
        XCTAssertTrue(normal.isColor(theme.shadow, atX: 0, y: 0), "moldura")
        XCTAssertTrue(normal.isColor(theme.bg3, atX: 3, y: 3), "face")
        XCTAssertTrue(normal.isColor(theme.shadow, atX: 79, y: 26), "sombra dura embaixo à direita")

        let primary = RenderedImage(PixelButton(title: "OK", style: .primary), width: 80, height: 27)
        XCTAssertTrue(primary.isColor(theme.accent, atX: 3, y: 3))

        let mini = RenderedImage(PixelButton(title: "X", style: .miniClose), width: 30, height: 30)
        XCTAssertTrue(mini.isColor(theme.bg2, atX: 1, y: 1))
    }

    func testButtonClicksOnlyWhenReleasedInside() {
        var clicks = 0
        let button = PixelButton(title: "OK") { clicks += 1 }
        button.frame = NSRect(x: 0, y: 0, width: 80, height: 27)
        button.mouseDown(with: click(button, x: 5, y: 5))
        XCTAssertTrue(button.isPressed)
        button.mouseUp(with: click(button, x: 5, y: 5, up: true))
        XCTAssertEqual(clicks, 1)

        button.mouseDown(with: click(button, x: 5, y: 5))
        button.mouseUp(with: click(button, x: 500, y: 500, up: true))
        XCTAssertEqual(clicks, 1, "soltar fora do botão cancela")
        XCTAssertFalse(button.isPressed)
        XCTAssertFalse(button.acceptsFirstResponder, "o botão não tira o teclado do terminal")
    }

    // MARK: cabeçalho

    private func pillOrigin(width: Int) -> (x: Int, y: Int) {
        (width - (PixelFont.textWidth("WORKING...", scale: 2) + 16) - 6, 5)
    }

    func testHeaderShowsTheAgentColorAndTheStatePill() {
        let header = AgentHeaderView(snapshot: snapshot(.working))
        let image = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        let pill = pillOrigin(width: 600)
        XCTAssertTrue(image.isColor(theme.bg2, atX: 1, y: 1))
        XCTAssertTrue(image.isColor(magenta, atX: 15, y: 15), "quadrado na cor do agente")
        XCTAssertTrue(image.isColor(theme.green, atX: pill.x, y: pill.y), "moldura da pílula em WORKING")
        XCTAssertGreaterThan(image.count(theme.ink, x: 30, y: 8, width: 200, height: 14), 0, "nome")

        header.snapshot = snapshot(.exited)
        let exited = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        XCTAssertTrue(exited.isColor(theme.red, atX: pill.x, y: pill.y))
    }

    func testHeaderDonePillBlinks() {
        let header = AgentHeaderView(snapshot: snapshot(.done))
        let pill = pillOrigin(width: 600)
        header.time = 0
        let filled = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        XCTAssertTrue(filled.isColor(theme.yellow, atX: pill.x + 3, y: pill.y + 3), "pílula cheia")

        header.time = 0.34
        let hollow = RenderedImage(header, width: 600, height: AgentHeaderView.height)
        XCTAssertTrue(hollow.isColor(theme.yellow, atX: pill.x, y: pill.y), "só a moldura")
        XCTAssertFalse(hollow.isColor(theme.yellow, atX: pill.x + 3, y: pill.y + 3))
    }

    func testHeaderShowsTheCompanyWhenThereIsRoom() {
        let with = RenderedImage(AgentHeaderView(snapshot: snapshot(company: "ACME")), width: 600,
                                 height: AgentHeaderView.height)
        let without = RenderedImage(AgentHeaderView(snapshot: snapshot(company: "")), width: 600,
                                    height: AgentHeaderView.height)
        // Depois do quadrado (x < 30) a cor do agente só aparece no nome da empresa.
        XCTAssertGreaterThan(with.count(magenta, x: 30), 0)
        XCTAssertEqual(without.count(magenta, x: 30), 0)

        let narrow = RenderedImage(AgentHeaderView(snapshot: snapshot(name: "NOME BEM COMPRIDO 123", company: "ACME")),
                                   width: 200, height: AgentHeaderView.height)
        XCTAssertEqual(narrow.count(magenta, x: 30), 0, "sem espaço, a empresa some e o estado fica")
        XCTAssertGreaterThan(narrow.count(theme.dim, x: 100), 0, "pílula do estado")
    }

    func testHeaderClicks() {
        var clicks = 0, doubles = 0
        let header = AgentHeaderView(snapshot: snapshot())
        header.onClick = { clicks += 1 }
        header.onDoubleClick = { doubles += 1 }
        header.mouseDown(with: click(header, x: 5, y: 5))
        header.mouseDown(with: click(header, x: 5, y: 5, count: 2))
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(doubles, 1)
    }

    // MARK: card

    private let cardWidth = 304

    private func render(_ card: AgentCardView) -> RenderedImage {
        RenderedImage(card, width: cardWidth, height: AgentCardView.height)
    }

    func testCardStripeAndActiveEdge() {
        let card = AgentCardView(snapshot: snapshot())
        let idle = render(card)
        XCTAssertTrue(idle.isColor(magenta, atX: 1, y: 40), "faixa na cor do agente")
        XCTAssertFalse(idle.isColor(magenta, atX: 5, y: 40))
        XCTAssertTrue(idle.isColor(theme.bg2, atX: 100, y: 0), "sem moldura fora do foco")

        card.isActive = true
        let active = render(card)
        XCTAssertTrue(active.isColor(magenta, atX: 5, y: 40), "faixa mais larga no agente em foco")
        XCTAssertTrue(active.isColor(theme.accent, atX: 100, y: 2), "moldura de 3 px")
        XCTAssertTrue(active.isColor(theme.accent, atX: 100, y: AgentCardView.height - 1))
        XCTAssertTrue(active.isColor(theme.accent, atX: cardWidth - 1, y: 40))
        let tagWidth = PixelFont.textWidth("EM FOCO", scale: 1)
        XCTAssertTrue(active.isColor(theme.accent, atX: cardWidth - tagWidth - 13, y: 7), "etiqueta EM FOCO")
        XCTAssertFalse(idle.isColor(theme.accent, atX: cardWidth - tagWidth - 13, y: 7))
    }

    func testCardEdgeFollowsTheState() {
        let card = AgentCardView(snapshot: snapshot(.exited))
        let exited = render(card)
        XCTAssertTrue(exited.isColor(theme.red, atX: 100, y: 1))
        XCTAssertFalse(exited.isColor(theme.red, atX: 100, y: 2), "moldura de 2 px")

        card.snapshot = snapshot(.done)
        card.time = 0
        XCTAssertTrue(render(card).isColor(theme.yellow, atX: 100, y: 0))
        card.time = 0.34
        XCTAssertFalse(render(card).isColor(theme.yellow, atX: 100, y: 0), "DONE pisca")
    }

    func testCardShortcutNumberOnlyUpToNine() {
        let card = AgentCardView(snapshot: snapshot())
        card.index = 3
        XCTAssertGreaterThan(render(card).count(theme.dim, x: cardWidth - 16, y: 10, width: 6, height: 7), 0)
        card.index = 12
        XCTAssertEqual(render(card).count(theme.dim, x: cardWidth - 16, y: 10, width: 6, height: 7), 0)
    }

    func testCardCloseButtonAppearsOnHover() {
        var selected = 0, closed = 0
        let card = AgentCardView(snapshot: snapshot())
        card.frame = NSRect(x: 0, y: 0, width: cardWidth, height: AgentCardView.height)
        card.onSelect = { selected += 1 }
        card.onClose = { closed += 1 }
        let close = AgentCardView.closeRect(width: cardWidth)
        XCTAssertFalse(render(card).isColor(theme.red, atX: Int(close.minX) + 1, y: Int(close.minY) + 1))

        // Sem o mouse em cima não há botão: o clique no canto seleciona.
        card.mouseDown(with: click(card, x: close.midX, y: close.midY))
        XCTAssertEqual([selected, closed], [1, 0])

        card.setHovering(true)
        XCTAssertTrue(render(card).isColor(theme.red, atX: Int(close.minX) + 1, y: Int(close.minY) + 1))
        card.mouseDown(with: click(card, x: close.midX, y: close.midY))
        XCTAssertEqual([selected, closed], [1, 1])
        card.mouseDown(with: click(card, x: 20, y: 40))
        XCTAssertEqual([selected, closed], [2, 1])
    }

    func testCardPreviewChangesTheDrawing() {
        let empty = render(AgentCardView(snapshot: snapshot()))
        let filled = render(AgentCardView(snapshot: snapshot(preview: ["compilando o projeto", "42 testes verdes"])))
        let background = theme.bg2
        XCTAssertLessThan(filled.count(background, y: 44, height: 36), empty.count(background, y: 44, height: 36))
    }

    // MARK: barra superior

    private let statsY = (46 - 14) / 2
    private var firstStatX: Int { 10 + PixelFont.textWidth("CLARK", scale: 3) + 4 + 10 + 16 }

    func testTopBarLogoAndBottomEdge() {
        let image = RenderedImage(TopBarView(), width: 1200, height: TopBarView.height)
        XCTAssertTrue(image.isColor(theme.bg2, atX: 2, y: 2))
        XCTAssertTrue(image.isColor(theme.bg2, atX: 5, y: 45))
        for y in 46..<49 { XCTAssertTrue(image.isColor(theme.shadow, atX: 5, y: y), "borda inferior, linha \(y)") }
        XCTAssertGreaterThan(image.count(theme.accent, x: 10, y: 12, width: PixelFont.textWidth("CLARK", scale: 3),
                                         height: 21), 0)
    }

    func testTopBarStatsColors() {
        let bar = TopBarView()
        let zero = RenderedImage(bar, width: 1200, height: TopBarView.height)
        XCTAssertTrue(zero.isColor(theme.dim, atX: firstStatX + 1, y: statsY + 5), "contagem zero fica apagada")
        XCTAssertEqual(zero.count(theme.red), 0, "GAME OVER só aparece quando há algum")

        bar.stats = AgentStats(states: [.working, .working, .done, .exited])
        let image = RenderedImage(bar, width: 1200, height: TopBarView.height)
        let working = firstStatX + PixelFont.textWidth("AGENTS 4", scale: 2) + 34
        let done = working + PixelFont.textWidth("WORKING 2", scale: 2) + 34
        XCTAssertTrue(image.isColor(theme.ink, atX: firstStatX + 1, y: statsY + 5))
        XCTAssertTrue(image.isColor(theme.green, atX: working + 1, y: statsY + 5))
        XCTAssertTrue(image.isColor(theme.yellow, atX: done + 1, y: statsY + 5))
        XCTAssertGreaterThan(image.count(theme.red), 0)
    }

    func testTopBarDropsStatsThatWouldRunUnderTheButtons() {
        let bar = TopBarView()
        bar.stats = AgentStats(states: [.working, .working, .done, .exited])
        let image = RenderedImage(bar, width: 620, height: TopBarView.height)
        let buttons = Int(bar.folderButton.frame.minX)
        XCTAssertGreaterThan(buttons, 0)
        for color in [theme.ink, theme.green, theme.yellow, theme.red] {
            XCTAssertEqual(image.count(color, x: buttons - 10), 0)
        }
    }

    func testAgentStatsCountBootAsIdle() {
        let stats = AgentStats(states: [.boot, .idle, .working, .done, .done, .exited])
        XCTAssertEqual(stats.agents, 6)
        XCTAssertEqual(stats.idle, 2)
        XCTAssertEqual(stats.working, 1)
        XCTAssertEqual(stats.done, 2)
        XCTAssertEqual(stats.exited, 1)
        XCTAssertEqual(AgentStats(states: []), AgentStats())
    }

    func testFolderTitleKeepsTheEndOfALongPath() {
        XCTAssertEqual(TopBarView.folderTitle(shortPath: "~/x"), "DIR ~/x")
        let exact = "~/" + String(repeating: "a", count: 26)
        XCTAssertEqual(TopBarView.folderTitle(shortPath: exact), "DIR " + exact)
        let long = "~/Projetos/" + String(repeating: "b", count: 30) + "/fim"
        let title = TopBarView.folderTitle(shortPath: long)
        XCTAssertEqual(title, "DIR …" + long.suffix(27))
        XCTAssertTrue(title.hasSuffix("/fim"))
    }

    // MARK: avisos

    func testWarningBarQueuesWithoutRepeating() {
        var changes = 0
        let bar = WarningBarView()
        bar.onChange = { changes += 1 }
        XCTAssertEqual(RenderedImage(bar, width: 600, height: WarningBarView.height).count(theme.yellow), 0)

        bar.add("config invalido")
        bar.add("config invalido")
        bar.add("claude nao encontrado")
        XCTAssertEqual(bar.messages, ["config invalido", "claude nao encontrado"])
        XCTAssertEqual(changes, 2)
        XCTAssertGreaterThan(RenderedImage(bar, width: 600, height: WarningBarView.height).count(theme.yellow), 0)

        bar.mouseDown(with: click(bar, x: 5, y: 5))
        XCTAssertEqual(bar.messages, ["claude nao encontrado"])
        bar.mouseDown(with: click(bar, x: 5, y: 5))
        bar.mouseDown(with: click(bar, x: 5, y: 5))
        XCTAssertEqual(bar.messages, [])
        XCTAssertEqual(changes, 4)
    }

    // MARK: tela vazia

    func testEmptyStateHidesTheButtonsWhileLoading() {
        var asked: [Int] = []
        let view = EmptyStateView()
        view.onAdd = { asked.append($0) }
        let buttons = view.subviews.compactMap { $0 as? PixelButton }
        XCTAssertEqual(buttons.map(\.title), ["1 AGENTE", "2 AGENTES", "4 AGENTES", "6 AGENTES"])
        XCTAssertTrue(buttons.allSatisfy(\.isHidden))
        let loading = RenderedImage(view, width: 900, height: 600)
        XCTAssertGreaterThan(loading.count(theme.ink), 0)
        XCTAssertEqual(loading.count(theme.accent), 0)

        view.isLoading = false
        XCTAssertFalse(buttons.contains(where: \.isHidden))
        buttons.forEach { $0.onClick?() }
        XCTAssertEqual(asked, [1, 2, 4, 6])
    }

    func testEmptyStateHintBlinks() {
        let view = EmptyStateView()
        view.isLoading = false
        view.time = 0
        XCTAssertGreaterThan(RenderedImage(view, width: 900, height: 600).count(theme.accent), 0)
        view.time = 0.5
        XCTAssertEqual(RenderedImage(view, width: 900, height: 600).count(theme.accent), 0)
    }

    // MARK: lista lateral

    func testSidebarStacksTheCards() {
        let sidebar = SidebarView()
        let cards = (1...3).map { AgentCardView(snapshot: snapshot(name: "AGENT \($0)")) }
        sidebar.setCards(cards)
        let image = RenderedImage(sidebar, width: SidebarView.width, height: 600)
        XCTAssertEqual(sidebar.cards.count, 3)
        XCTAssertEqual(cards[0].frame, NSRect(x: 3, y: 3, width: 304, height: 86))
        XCTAssertEqual(cards[1].frame.minY, 92)
        XCTAssertEqual(cards[2].frame.minY, 181)
        XCTAssertEqual(Int(sidebar.closeAllButton.frame.maxX), SidebarView.width)
        XCTAssertTrue(image.isColor(theme.shadow, atX: 1, y: 300), "borda esquerda")
        XCTAssertTrue(image.isColor(theme.bg2, atX: 200, y: 3), "cabeçalho")
        XCTAssertGreaterThan(image.count(theme.dim, y: 0, height: 30), 0, "AGENTES 3")

        sidebar.setCards([cards[2]])
        sidebar.layoutSubtreeIfNeeded()
        XCTAssertNil(cards[0].superview)
        XCTAssertEqual(cards[2].frame.minY, 3)
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkTests/PixelViewsTests.swift:13:54: error: cannot find type 'AgentSnapshot' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/Clark/Pixel.swift`

```swift
import AppKit
import ClarkCore

/// Desenho em pixels inteiros, com a origem no canto superior esquerdo.
enum Pixel {
    static func fill(_ context: CGContext, _ x: Int, _ y: Int, _ width: Int, _ height: Int,
                     _ color: RGB, alpha: Double = 1) {
        guard width > 0, height > 0 else { return }
        context.setFillColor(CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: alpha))
        context.fill(CGRect(x: x, y: y, width: width, height: height))
    }

    /// Moldura por dentro do retângulo.
    static func frame(_ context: CGContext, _ x: Int, _ y: Int, _ width: Int, _ height: Int,
                      thickness: Int, _ color: RGB) {
        fill(context, x, y, width, thickness, color)
        fill(context, x, y + height - thickness, width, thickness, color)
        fill(context, x, y, thickness, height, color)
        fill(context, x + width - thickness, y, thickness, height, color)
    }

    /// Texto na fonte pixel (`draw_text` do original). A sombra sai deslocada de `scale`.
    static func text(_ context: CGContext, _ text: String, _ x: Int, _ y: Int, scale: Int,
                     _ color: RGB, shadow: RGB? = nil) {
        let pixels = PixelFont.pixels(text)
        if let shadow {
            context.setFillColor(shadow.cgColor)
            for pixel in pixels {
                context.fill(CGRect(x: x + (pixel.x + 1) * scale, y: y + (pixel.y + 1) * scale,
                                    width: scale, height: scale))
            }
        }
        context.setFillColor(color.cgColor)
        for pixel in pixels {
            context.fill(CGRect(x: x + pixel.x * scale, y: y + pixel.y * scale, width: scale, height: scale))
        }
    }

    static func monoFont(size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .heavy : .regular)
    }

    static func monoWidth(_ text: String, size: CGFloat, bold: Bool = false) -> Int {
        Int((text as NSString).size(withAttributes: [.font: monoFont(size: size, bold: bold)]).width.rounded(.up))
    }

    /// Texto na fonte monoespaçada do sistema, para o que tem acento ou minúscula: caminhos e
    /// linhas do terminal. Uma linha só, cortada com reticências.
    static func mono(_ context: CGContext, _ text: String, _ x: Int, _ y: Int, width: Int, size: CGFloat,
                     _ color: RGB, truncate: NSLineBreakMode = .byTruncatingTail, bold: Bool = false) {
        guard width > 0, !text.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = truncate
        let font = monoFont(size: size, bold: bold)
        let height = (font.ascender - font.descender + font.leading).rounded(.up)
        context.saveGState()
        context.setShouldAntialias(true)
        (text as NSString).draw(in: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: height),
                                withAttributes: [.font: font, .foregroundColor: color.nsColor,
                                                 .paragraphStyle: style])
        context.restoreGState()
    }
}

/// View desenhada à mão: coordenadas inteiras, origem em cima à esquerda, sem suavização.
class PixelView: NSView {
    var theme = Theme.dark { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(false)
        render(context, width: Int(bounds.width), height: Int(bounds.height))
        context.restoreGState()
    }

    /// Desenho da view. Chamado pelo `draw` e pelos testes, que desenham num bitmap.
    func render(_ context: CGContext, width: Int, height: Int) {}
}

/// Rótulo e cor de cada estado, iguais no cabeçalho e no card.
enum StateLabel {
    static func text(_ state: AgentState, time: Double) -> String {
        let dots = String(repeating: ".", count: Int(time * 4) % 4)
        switch state {
        case .boot: return "BOOT" + dots
        case .working: return "WORKING" + dots
        case .idle: return "IDLE"
        case .done: return "DONE!"
        case .exited: return "GAME OVER"
        }
    }

    static func color(_ state: AgentState, theme: Theme) -> RGB {
        switch state {
        case .boot, .done: return theme.yellow
        case .working: return theme.green
        case .idle: return theme.dim
        case .exited: return theme.red
        }
    }

    /// Estados cujo desenho muda com o tempo e pedem redesenho a cada tique.
    static func isAnimated(_ state: AgentState) -> Bool {
        state == .boot || state == .working || state == .done
    }
}
```

**Arquivo:** `mac/Sources/Clark/PixelButton.swift`

```swift
import AppKit
import ClarkCore

/// Botão quadrado do original (`button.px` e `button.mini` do CSS).
final class PixelButton: PixelView {
    enum Style {
        /// Botão da barra: moldura e sombra dura.
        case normal
        /// Igual ao `normal`, na cor de destaque.
        case primary
        /// Botão chapado do cabeçalho do painel.
        case mini
        /// `mini` que fica vermelho sob o mouse.
        case miniClose
    }

    static let barHeight = 27

    var title: String { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    let style: Style
    private(set) var isHovering = false
    private(set) var isPressed = false

    init(title: String, style: Style = .normal, toolTip: String? = nil, onClick: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.onClick = onClick
        super.init(frame: .zero)
        self.toolTip = toolTip
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    private var isMini: Bool { style == .mini || style == .miniClose }
    private var fontSize: CGFloat { isMini ? 10 : 11 }

    /// Largura que o título pede.
    var fittingWidth: Int {
        let text = Pixel.monoWidth(title, size: fontSize, bold: true)
        return isMini ? text + 18 : text + 24 + 4 + 3
    }

    // Clicar num botão não tira o foco do terminal.
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setState(hovering: true, pressed: isPressed) }
    override func mouseExited(with event: NSEvent) { setState(hovering: false, pressed: false) }
    override func mouseDown(with event: NSEvent) { setState(hovering: true, pressed: true) }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressed = isPressed
        setState(hovering: inside, pressed: false)
        if inside && wasPressed { onClick?() }
    }

    private func setState(hovering: Bool, pressed: Bool) {
        guard hovering != isHovering || pressed != isPressed else { return }
        isHovering = hovering
        isPressed = pressed
        needsDisplay = true
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        if isMini {
            renderMini(context, width: width, height: height)
            return
        }
        let faceWidth = width - 3, faceHeight = height - 3
        if !isPressed { Pixel.fill(context, 3, 3, faceWidth, faceHeight, theme.shadow) }
        let face: RGB
        if style == .primary {
            face = isPressed ? theme.accentLo : (isHovering ? theme.accentHi : theme.accent)
        } else {
            face = isPressed ? theme.bg5 : (isHovering ? theme.bg4 : theme.bg3)
        }
        Pixel.fill(context, 0, 0, faceWidth, faceHeight, face)
        Pixel.frame(context, 0, 0, faceWidth, faceHeight, thickness: 2, theme.shadow)
        let ink = style == .primary ? theme.onAccent : theme.ink
        drawTitle(context, x: 14, width: faceWidth - 28, height: faceHeight, ink)
    }

    private func renderMini(_ context: CGContext, width: Int, height: Int) {
        var face = theme.bg2, ink = theme.dim
        if isHovering {
            face = style == .miniClose ? theme.red : theme.bg3
            ink = style == .miniClose ? theme.onAccent : theme.ink
        }
        Pixel.fill(context, 0, 0, width, height, face)
        drawTitle(context, x: 9, width: width - 18, height: height, ink)
    }

    private func drawTitle(_ context: CGContext, x: Int, width: Int, height: Int, _ color: RGB) {
        let font = Pixel.monoFont(size: fontSize, bold: true)
        let lineHeight = Int((font.ascender - font.descender + font.leading).rounded(.up))
        Pixel.mono(context, title, x, (height - lineHeight) / 2, width: width + 1, size: fontSize, color,
                   truncate: .byTruncatingHead, bold: true)
    }
}
```

**Arquivo:** `mac/Sources/Clark/AgentHeaderView.swift`

```swift
import AppKit
import ClarkCore

/// O que o cabeçalho e o card mostram de um agente.
struct AgentSnapshot: Equatable {
    var name: String
    var company: String
    /// Cor da empresa já no tom deste agente.
    var color: RGB
    /// Pasta de trabalho na forma curta (`~/x`).
    var path: String
    var state: AgentState
    var preview: [String] = []
}

/// Cabeçalho do painel (`_draw_head` do original). O quadrado na cor da empresa ocupa o
/// lugar do mascote, que chega no M3.
final class AgentHeaderView: PixelView {
    static let height = 30

    var snapshot: AgentSnapshot { didSet { if snapshot != oldValue { needsDisplay = true } } }
    /// Relógio das animações, em segundos.
    var time: Double = 0 { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    init(snapshot: AgentSnapshot) {
        self.snapshot = snapshot
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg2)
        let square = 14
        Pixel.fill(context, 8, (height - square) / 2, square, square, snapshot.color)
        Pixel.frame(context, 8, (height - square) / 2, square, square, thickness: 2, snapshot.color.darkened(0.35))

        var x = 8 + square + 8
        let name = PixelFont.fit(snapshot.name, scale: 2, width: max(60, width - x - 200))
        Pixel.text(context, name, x, (height - 14) / 2, scale: 2, theme.ink, shadow: theme.shadow)
        x += PixelFont.textWidth(name, scale: 2) + 14

        let scale = width < 300 ? 1 : 2
        let pillWidth = PixelFont.textWidth("WORKING...", scale: scale) + 16
        let pillHeight = 20
        let pillX = width - pillWidth - 6
        let pillY = (height - pillHeight) / 2

        let companyWidth = PixelFont.textWidth(snapshot.company, scale: 1)
        if pillX - x - 10 >= companyWidth {
            Pixel.text(context, snapshot.company, x, (height - 7) / 2, scale: 1, snapshot.color)
            x += companyWidth + 10
        }
        let room = pillX - x - 10
        if room > 60 {
            Pixel.mono(context, snapshot.path, x, (height - 12) / 2, width: room, size: 9, theme.dim,
                       truncate: .byTruncatingHead)
        }

        let label = StateLabel.text(snapshot.state, time: time)
        let color = StateLabel.color(snapshot.state, theme: theme)
        let textY = pillY + (pillHeight - 7 * scale) / 2
        if snapshot.state == .done && Int(time * 3) % 2 == 0 {
            Pixel.fill(context, pillX, pillY, pillWidth, pillHeight, color)
            Pixel.text(context, label, pillX + 8, textY, scale: scale, theme.bg)
        } else {
            Pixel.fill(context, pillX, pillY, pillWidth, pillHeight, color, alpha: 0.15)
            Pixel.frame(context, pillX, pillY, pillWidth, pillHeight, thickness: 2, color)
            Pixel.text(context, label, pillX + 8, textY, scale: scale, color)
        }
    }
}
```

**Arquivo:** `mac/Sources/Clark/AgentCardView.swift`

```swift
import AppKit
import ClarkCore

/// Card do agente na lista lateral (`AgentCard` do original).
final class AgentCardView: PixelView {
    static let height = 86

    var snapshot: AgentSnapshot { didSet { if snapshot != oldValue { needsDisplay = true } } }
    /// Posição do agente, a partir de 1. Até 9 aparece no canto: é o número do atalho ⌘N.
    var index = 1 { didSet { if index != oldValue { needsDisplay = true } } }
    /// É o agente do painel principal.
    var isActive = false { didSet { if isActive != oldValue { needsDisplay = true } } }
    var time: Double = 0 { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var isHovering = false

    init(snapshot: AgentSnapshot) {
        self.snapshot = snapshot
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Retângulo do botão de fechar, que só existe com o mouse em cima do card.
    static func closeRect(width: Int) -> CGRect {
        CGRect(x: width - 26, y: 4, width: 22, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isHovering && Self.closeRect(width: Int(bounds.width)).contains(point) {
            onClose?()
        } else {
            onSelect?()
        }
    }

    // Botão do meio fecha, como no original.
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        let base = isHovering ? theme.bg3 : theme.bg2
        let background = isActive ? base.mix(theme.accent, 0.18) : base
        Pixel.fill(context, 0, 0, width, height, background)

        var edge: (color: RGB, thickness: Int)?
        if snapshot.state == .done {
            if Int(time * 3) % 2 == 0 { edge = (theme.yellow, 2) }
        } else if snapshot.state == .exited {
            edge = (theme.red, 2)
        } else if isActive {
            edge = (theme.accent, 3)
        }
        if let edge {
            Pixel.fill(context, 0, 0, width, edge.thickness, edge.color)
            Pixel.fill(context, 0, height - edge.thickness, width, edge.thickness, edge.color)
            Pixel.fill(context, width - edge.thickness, 0, edge.thickness, height, edge.color)
        }
        Pixel.fill(context, 0, 0, isActive ? 6 : 4, height, snapshot.color)

        let x = 14
        let tagWidth = PixelFont.textWidth("EM FOCO", scale: 1)
        var reserved = 24
        if isHovering {
            let close = Self.closeRect(width: width)
            Pixel.fill(context, Int(close.minX), Int(close.minY), Int(close.width), Int(close.height), theme.red)
            Pixel.text(context, "X", Int(close.minX) + 6, Int(close.minY) + 3, scale: 2, theme.bg)
            reserved = 34
        } else if isActive {
            Pixel.fill(context, width - tagWidth - 14, 6, tagWidth + 8, 13, theme.accent)
            Pixel.text(context, "EM FOCO", width - tagWidth - 10, 9, scale: 1, theme.onAccent)
            reserved = tagWidth + 20
        } else if index <= 9 {
            Pixel.text(context, String(index), width - 16, 10, scale: 1, theme.dim)
        }

        let name = PixelFont.fit(snapshot.name, scale: 2, width: width - x - reserved)
        Pixel.text(context, name, x, 10, scale: 2, isActive ? theme.accent : theme.ink, shadow: theme.shadow)

        let stateColor = StateLabel.color(snapshot.state, theme: theme)
        Pixel.fill(context, x, 31, 5, 5, stateColor)
        Pixel.text(context, StateLabel.text(snapshot.state, time: time), x + 9, 30, scale: 1, stateColor)
        var pathX = x + 9 + PixelFont.textWidth("WORKING...", scale: 1) + 10
        let companyWidth = PixelFont.textWidth(snapshot.company, scale: 1)
        if pathX + companyWidth < width - 8 {
            Pixel.text(context, snapshot.company, pathX, 30, scale: 1, snapshot.color)
            pathX += companyWidth + 8
        }
        Pixel.mono(context, snapshot.path, pathX, 27, width: width - pathX - 8, size: 9,
                   theme.dim.mix(background, 0.3), truncate: .byTruncatingHead)

        let lines = snapshot.preview.isEmpty ? ["…"] : snapshot.preview
        for (row, line) in lines.prefix(2).enumerated() {
            Pixel.mono(context, line, x, 46 + row * 16, width: width - x - 10, size: 10,
                       isActive ? theme.ink : theme.dim)
        }
    }
}
```

**Arquivo:** `mac/Sources/Clark/TopBarView.swift`

```swift
import AppKit
import ClarkCore

/// Contagem de agentes por estado, mostrada na barra superior.
struct AgentStats: Equatable {
    var agents = 0
    var working = 0
    var done = 0
    var idle = 0
    var exited = 0

    init() {}

    init(states: [AgentState]) {
        agents = states.count
        working = states.filter { $0 == .working }.count
        done = states.filter { $0 == .done }.count
        idle = states.filter { $0 == .idle || $0 == .boot }.count
        exited = states.filter { $0 == .exited }.count
    }
}

/// Barra superior: logo, contagens e os botões de pasta, layout e novo agente.
final class TopBarView: PixelView {
    static let height = 49
    private static let contentHeight = 46

    var stats = AgentStats() { didSet { if stats != oldValue { needsDisplay = true } } }
    let folderButton = PixelButton(title: "DIR ~", toolTip: "Pasta onde os novos agentes abrem (⌘D)")
    let layoutButton = PixelButton(title: "FOCO", toolTip: "Alternar layout foco / grade (⌘L)")
    let addButton = PixelButton(title: "+ AGENT", style: .primary, toolTip: "Novo agente (⌘N)")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        [folderButton, layoutButton, addButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var theme: Theme {
        didSet { [folderButton, layoutButton, addButton].forEach { $0.theme = theme } }
    }

    /// `DIR ~/pasta`, com reticências no começo quando passa de 28 caracteres.
    static func folderTitle(shortPath: String) -> String {
        shortPath.count > 28 ? "DIR …" + shortPath.suffix(27) : "DIR " + shortPath
    }

    private var buttonsLeft: Int {
        Int(bounds.width) - 10 - [folderButton, layoutButton, addButton].map(\.fittingWidth).reduce(0, +) - 20
    }

    override func layout() {
        super.layout()
        var x = buttonsLeft
        let y = (Self.contentHeight - PixelButton.barHeight) / 2
        for button in [folderButton, layoutButton, addButton] {
            button.frame = NSRect(x: x, y: y, width: button.fittingWidth, height: PixelButton.barHeight)
            x += button.fittingWidth + 10
        }
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        let content = Self.contentHeight
        Pixel.fill(context, 0, 0, width, content, theme.bg2)
        Pixel.fill(context, 0, content, width, height - content, theme.shadow)

        let logoY = (content - 21) / 2
        Pixel.text(context, "CLARK", 12, logoY + 2, scale: 3, theme.accent.mix(.black, 0.5))
        Pixel.text(context, "CLARK", 10, logoY, scale: 3, theme.accent)

        var x = 10 + PixelFont.textWidth("CLARK", scale: 3) + 4 + 10 + 16
        let y = (content - 14) / 2
        let limit = buttonsLeft - 10
        var items: [(label: String, count: Int, color: RGB)] = [
            ("AGENTS", stats.agents, theme.ink), ("WORKING", stats.working, theme.green),
            ("DONE", stats.done, theme.yellow), ("IDLE", stats.idle, theme.dim),
        ]
        if stats.exited > 0 { items.append(("GAME OVER", stats.exited, theme.red)) }
        for item in items {
            let label = "\(item.label) \(item.count)"
            let labelWidth = PixelFont.textWidth(label, scale: 2)
            if x + 12 + labelWidth > limit { break }
            let color = item.count == 0 ? theme.dim : item.color
            Pixel.fill(context, x, y + 4, 6, 6, color)
            Pixel.text(context, label, x + 12, y, scale: 2, color)
            x += labelWidth + 34
        }
    }
}

/// Faixa de avisos abaixo da barra superior. Um clique dispensa o aviso mostrado.
final class WarningBarView: PixelView {
    static let height = 22

    private(set) var messages: [String] = []
    var onChange: (() -> Void)?

    func add(_ message: String) {
        guard !messages.contains(message) else { return }
        messages.append(message)
        needsDisplay = true
        onChange?()
    }

    override func mouseDown(with event: NSEvent) {
        guard !messages.isEmpty else { return }
        messages.removeFirst()
        needsDisplay = true
        onChange?()
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg2.mix(theme.yellow, 0.12))
        Pixel.fill(context, 0, height - 2, width, 2, theme.shadow)
        guard let first = messages.first else { return }
        let more = messages.count > 1 ? "  (+\(messages.count - 1))" : ""
        let close = "X"
        let room = width - 20 - PixelFont.textWidth(close, scale: 1) - 12
        Pixel.text(context, PixelFont.fit("! " + first + more, scale: 1, width: room), 10, (height - 2 - 7) / 2,
                   scale: 1, theme.yellow)
        Pixel.text(context, close, width - 10 - PixelFont.textWidth(close, scale: 1), (height - 2 - 7) / 2,
                   scale: 1, theme.dim)
    }
}

/// Tela sem agentes (`_draw_empty` do original, sem o mascote, que chega no M3).
final class EmptyStateView: PixelView {
    /// true enquanto o ambiente do shell ainda está sendo lido: sem botões.
    var isLoading = true { didSet { buttons.forEach { $0.isHidden = isLoading }; needsDisplay = true } }
    var time: Double = 0 { didSet { needsDisplay = true } }
    var onAdd: ((Int) -> Void)?
    private var buttons: [PixelButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for count in [1, 2, 4, 6] {
            let button = PixelButton(title: "\(count) AGENTE" + (count > 1 ? "S" : ""),
                                     style: count == 1 ? .primary : .normal)
            button.onClick = { [weak self] in self?.onAdd?(count) }
            button.isHidden = true
            buttons.append(button)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var theme: Theme { didSet { buttons.forEach { $0.theme = theme } } }

    override func layout() {
        super.layout()
        let total = buttons.map(\.fittingWidth).reduce(0, +) + 14 * (buttons.count - 1)
        var x = (Int(bounds.width) - total) / 2
        let y = Int(bounds.height) - 90 - PixelButton.barHeight
        for button in buttons {
            button.frame = NSRect(x: x, y: y, width: button.fittingWidth, height: PixelButton.barHeight)
            x += button.fittingWidth + 14
        }
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg)
        let unit = max(4, min(width, height) / 70)
        let scale = max(2, unit / 2)
        let y = Int(Double(height) * 0.42)
        let message = isLoading ? "LENDO O AMBIENTE DO SHELL" : "NENHUM AGENTE ONLINE"
        Pixel.text(context, message, (width - PixelFont.textWidth(message, scale: scale)) / 2, y, scale: scale,
                   theme.ink, shadow: theme.shadow)
        guard !isLoading, Int(time * 2) % 2 == 0 else { return }
        let hint = "PRESS START  -  CMD+N"
        Pixel.text(context, hint, (width - PixelFont.textWidth(hint, scale: 2)) / 2, y + 7 * scale + 3 * unit,
                   scale: 2, theme.accent)
    }
}
```

**Arquivo:** `mac/Sources/Clark/SidebarView.swift`

```swift
import AppKit
import ClarkCore

/// Lista lateral do modo foco: um card por agente, na ordem dos agentes.
final class SidebarView: PixelView {
    static let width = 310
    private static let headHeight = 30
    private static let spacing = 3

    let closeAllButton = PixelButton(title: "FECHAR TODOS", style: .miniClose,
                                     toolTip: "Fechar os outros agentes (ou todos)")
    private(set) var cards: [AgentCardView] = []
    private let scroll = NSScrollView()
    private let list = FlippedView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        addSubview(scroll)
        addSubview(closeAllButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var theme: Theme {
        didSet {
            closeAllButton.theme = theme
            cards.forEach { $0.theme = theme }
        }
    }

    /// Troca os cards pelos da lista, na ordem dada.
    func setCards(_ newCards: [AgentCardView]) {
        cards.forEach { $0.removeFromSuperview() }
        cards = newCards
        for card in cards {
            card.theme = theme
            list.addSubview(card)
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let width = Int(bounds.width), height = Int(bounds.height)
        let buttonWidth = closeAllButton.fittingWidth
        closeAllButton.frame = NSRect(x: width - buttonWidth, y: 0, width: buttonWidth, height: Self.headHeight)
        scroll.frame = NSRect(x: 3, y: Self.headHeight, width: width - 3, height: max(0, height - Self.headHeight))
        let cardWidth = width - 3 - 3
        var y = Self.spacing
        for card in cards {
            card.frame = NSRect(x: 3, y: y, width: cardWidth, height: AgentCardView.height)
            y += AgentCardView.height + Self.spacing
        }
        list.frame = NSRect(x: 0, y: 0, width: width - 3, height: max(y, Int(scroll.frame.height)))
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg)
        Pixel.fill(context, 0, 0, 3, height, theme.shadow)
        Pixel.fill(context, 3, 0, width - 3, Self.headHeight, theme.bg2)
        Pixel.text(context, "AGENTES \(cards.count)", 12, (Self.headHeight - 7) / 2, scale: 1, theme.dim)
    }
}

/// Container com a origem em cima à esquerda, como as views desenhadas.
final class FlippedView: NSView {
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        onLayout?()
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'PixelViewsTests'`
Expected: PASS, `Executed 24 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 170 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkTests/RenderedImage.swift`
- `mac/Tests/ClarkTests/PixelViewsTests.swift`
- `mac/Sources/Clark/Pixel.swift`
- `mac/Sources/Clark/PixelButton.swift`
- `mac/Sources/Clark/AgentHeaderView.swift`
- `mac/Sources/Clark/AgentCardView.swift`
- `mac/Sources/Clark/TopBarView.swift`
- `mac/Sources/Clark/SidebarView.swift`

---

### Task 12: Painel do agente, janela e menu

Junta tudo. O painel do agente cuida do processo, da máquina de estados, do cabeçalho, do GAME OVER e do menu com as variáveis removidas. O aviso de agente pronto fica atrás de um protocolo, para os testes não tocarem no sistema. A janela cuida de foco, grade, zoom, atalhos, renomear, salvar e restaurar. Os testes usam uma home temporária e processos de verdade: sem `claude`, os agentes abrem `/bin/sh`, e um `claude` de mentira é um script que o próprio teste escreve.

**Atenção:** Os testes desta tarefa criam a janela sem mostrá-la e abrem processos de verdade. Foram validados com a sessão gráfica aberta.

**Files:**
- Create: `mac/Sources/Clark/Notifier.swift`
- Create: `mac/Sources/Clark/AgentPaneView.swift`
- Create: `mac/Sources/Clark/MainWindowController.swift`
- Create: `mac/Sources/Clark/MainMenu.swift`
- Test: `mac/Tests/ClarkTests/ClarkFixture.swift`
- Test: `mac/Tests/ClarkTests/MainWindowControllerTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 1: `PathTools`
  - Task 2: `PixelFont`, `RGB`, `Theme`
  - Task 3: `GridLayout`
  - Task 4: `AgentState`, `AgentStateMachine`
  - Task 5: `Company`, `CompanyResolver`, `EnvPolicy`
  - Task 6: `ClaudeCommand`, `SessionLocator`
  - Task 7: `ClarkConfig`, `ConfigStore`, `SavedAgent`
  - Task 8: `AgentNaming`, `CLIOptions`, `PreviewLines`
  - Task 9: `AgentTerminalView`, `ProcessReaper`, `TemporaryDirectory`, `TerminalAppearance`, `waitUntil`
  - Task 11: `AgentCardView`, `AgentHeaderView`, `AgentSnapshot`, `AgentStats`, `EmptyStateView`, `FlippedView`, `Pixel`, `PixelButton`, `PixelView`, `RenderedImage`, `SidebarView`, `StateLabel`, `TopBarView`, `WarningBarView`
  - `UserNotifications` (`UNUserNotificationCenter`), só dentro de `Notifier`.
- Produces:

```swift
// mac/Sources/Clark/Notifier.swift
protocol Notifying: AnyObject
    var onOpen: ((String) -> Void)?
    func agentDone(name: String, sessionID: String)
    func setBadge(_ count: Int)
final class Notifier: NSObject, Notifying, UNUserNotificationCenterDelegate
    var onOpen: ((String) -> Void)?
    func start()
    func agentDone(name: String, sessionID: String)
    func setBadge(_ count: Int)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void)

// mac/Sources/Clark/AgentPaneView.swift
struct AgentLaunch
    var baseEnvironment: [String: String]
    var claudePath: String?
    var shell: String
    var home: String
    var claudeArgs: [String]
    var resolver: CompanyResolver
    func usableDirectory(_ directory: String) -> String
    func company(forDirectory directory: String) -> Company
protocol AgentPaneDelegate: AnyObject
    func paneIsWatched(_ pane: AgentPaneView) -> Bool
    func paneNeedsAttention(_ pane: AgentPaneView)
    func paneDidChange(_ pane: AgentPaneView)
    func paneRequestsSelect(_ pane: AgentPaneView)
    func paneRequestsZoom(_ pane: AgentPaneView)
    func paneRequestsClose(_ pane: AgentPaneView)
    func paneRequestsRename(_ pane: AgentPaneView)
final class AgentPaneView: PixelView
    static let border = 3
    static let stripHeight = 16
    static let gameOver = "\r\n\r\n\u{1b}[1;41;97m  GAME OVER  \u{1b}[0m  "
    static let missingClaude = "\r\n\u{1b}[1;31m  claude nao encontrado no PATH.\u{1b}[0m "
    static let launchFailed = "\r\n\u{1b}[1;31m  falha ao iniciar o processo.\u{1b}[0m\r\n"
    static let unfilteredShell = "Sem claude: o shell relê o rc e o filtro de variáveis não vale"
    private(set) var name: String
    private(set) var directory: String
    let sessionID: String
    let tone: Int
    let company: Company
    private(set) var machine: AgentStateMachine
    private(set) var terminal: AgentTerminalView
    private(set) var preview: [String]
    private(set) var removedVariables: [String]
    private(set) var bypassesPermissions = false
    weak var delegate: AgentPaneDelegate?
    var isFocused = false
    let header: AgentHeaderView
    var color: RGB
    var state: AgentState
    var snapshot: AgentSnapshot
    init(name: String, directory: String, sessionID: String, tone: Int, launch: AgentLaunch, appearance: TerminalAppearance, clock: @escaping () -> Double)
    func spawn()
    func respawn()
    func shutdown()
    func tick(now: Double)
    func focused()
    func layoutChanged()
    func refreshPreview(now: Double, force: Bool = false) -> Bool
    func rename(_ newName: String)
    func apply(_ appearance: TerminalAppearance)
    func contextMenu() -> NSMenu

// mac/Sources/Clark/MainWindowController.swift
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, AgentPaneDelegate
    static let margin: CGFloat
    static let fontStep = 0.1
    private(set) var panes: [AgentPaneView]
    private(set) var mainPane: AgentPaneView?
    private(set) var focusedPane: AgentPaneView?
    private(set) var zoomedPane: AgentPaneView?
    private(set) var layoutMode: String
    private(set) var defaultDirectory: String
    private(set) var fontScale: Double
    private(set) var launch: AgentLaunch?
    let warnings = WarningBarView()
    let sidebar = SidebarView()
    let topBar = TopBarView()
    var isAppActive: () -> Bool
    lazy var isWindowKey: () -> Bool
    init(config: ClarkConfig, store: ConfigStore, home: String, notifier: Notifying, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime })
    func start(launch: AgentLaunch, options: CLIOptions, startupWarnings: [String] = [])
    var liveAgentCount: Int
    func shutdown()
    func persist()
    func addAgents(_ count: Int)
    func close(_ pane: AgentPaneView)
    func select(_ pane: AgentPaneView)
    func toggleZoom(of pane: AgentPaneView)
    func applyRename(_ pane: AgentPaneView, text: String)
    func setDefaultDirectory(_ directory: String)
    func setFontScale(_ scale: Double)
    var currentPane: AgentPaneView?
    func relayout()
    var visiblePanes: [AgentPaneView]
    func tick()
    func paneIsWatched(_ pane: AgentPaneView) -> Bool
    func paneNeedsAttention(_ pane: AgentPaneView)
    func paneDidChange(_ pane: AgentPaneView)
    func paneRequestsSelect(_ pane: AgentPaneView)
    func paneRequestsZoom(_ pane: AgentPaneView)
    func paneRequestsClose(_ pane: AgentPaneView)
    func paneRequestsRename(_ pane: AgentPaneView)
    func windowShouldClose(_ sender: NSWindow) -> Bool
    func windowDidBecomeKey(_ notification: Notification)
    @objc func newAgent(_ sender: Any?)
    @objc func closeAgent(_ sender: Any?)
    func closeAllChoices() -> [(title: String, panes: [AgentPaneView])]
    @objc func closeAllAgents(_ sender: Any?)
    @objc func chooseFolder(_ sender: Any?)
    @objc func toggleLayout(_ sender: Any?)
    @objc func toggleZoom(_ sender: Any?)
    @objc func nextAgent(_ sender: Any?)
    @objc func previousAgent(_ sender: Any?)
    @objc func selectAgentByNumber(_ sender: NSMenuItem)
    @objc func renameAgent(_ sender: Any?)
    @objc func increaseFont(_ sender: Any?)
    @objc func decreaseFont(_ sender: Any?)
    @objc func resetFont(_ sender: Any?)
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool

// mac/Sources/Clark/MainMenu.swift
enum MainMenu
    static func build() -> NSMenu

// mac/Tests/ClarkTests/ClarkFixture.swift
final class SpyNotifier: Notifying
    var onOpen: ((String) -> Void)?
    private(set) var done: [String]
    private(set) var badges: [Int]
    func agentDone(name: String, sessionID: String)
    func setBadge(_ count: Int)
final class ClarkFixture
    let temp = TemporaryDirectory()
    let notifier = SpyNotifier()
    var now = 100.0
    private(set) var controllers: [MainWindowController]
    var home: String
    lazy var store = ConfigStore(directory: temp.path + "/.config/clark")
    var environment: [String: String]
    func launch(claude: String? = nil, claudeArgs: [String] = [], environment: [String: String]? = nil) -> AgentLaunch
    func controller(config: ClarkConfig? = nil) -> MainWindowController
    func started(agents count: Int = 0, config: ClarkConfig? = nil, claude: String? = nil, claudeArgs: [String] = [], environment: [String: String]? = nil) -> MainWindowController
    func fakeClaude(_ script: String) -> String
    func shutdown()
```

**Review Focus:**
- Item 1 (pasta de agente que sumiu): `testAgentWhoseFolderVanishedStartsANewConversationAtHome`.
- Item 3 (link entre empresas): `testLinkIntoAnotherCompanyCountsAsTheDestination`.
- Item 5 (config que não grava): `testConfigThatCannotBeSavedWarnsAndKeepsTheAgents` e `testSaveFailureWarningDoesNotComeBackAfterBeingDismissed`.
- Todos em `MainWindowControllerTests.swift`.

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkTests/ClarkFixture.swift`

```swift
import ClarkCore
import Foundation
@testable import Clark

final class SpyNotifier: Notifying {
    var onOpen: ((String) -> Void)?
    private(set) var done: [String] = []
    private(set) var badges: [Int] = []

    func agentDone(name: String, sessionID: String) { done.append(name) }
    func setBadge(_ count: Int) { badges.append(count) }
}

/// Um CLARK de teste: home temporária, `ConfigStore` próprio e relógio controlado.
final class ClarkFixture {
    let temp = TemporaryDirectory()
    let notifier = SpyNotifier()
    var now = 100.0
    private(set) var controllers: [MainWindowController] = []

    var home: String { temp.path }
    lazy var store = ConfigStore(directory: temp.path + "/.config/clark")

    /// Ambiente base dos agentes, como se tivesse vindo do shell de login.
    var environment: [String: String] { ["PATH": "/usr/bin:/bin", "HOME": home] }

    func launch(claude: String? = nil, claudeArgs: [String] = [], environment: [String: String]? = nil) -> AgentLaunch {
        let home = home
        let resolver = CompanyResolver(json: store.companiesData(), palette: Theme.dark.agents,
                                       fallbackColor: Theme.dark.dim) {
            PathTools.canonical($0, base: home, home: home)
        }
        return AgentLaunch(baseEnvironment: environment ?? self.environment, claudePath: claude, shell: "/bin/sh",
                           home: home, claudeArgs: claudeArgs, resolver: resolver)
    }

    func controller(config: ClarkConfig? = nil) -> MainWindowController {
        let controller = MainWindowController(config: config ?? store.load().config, store: store, home: home,
                                              notifier: notifier) { [unowned self] in self.now }
        controllers.append(controller)
        return controller
    }

    /// Controller já iniciado, sem `claude`: os agentes abrem `/bin/sh`.
    func started(agents count: Int = 0, config: ClarkConfig? = nil, claude: String? = nil,
                 claudeArgs: [String] = [], environment: [String: String]? = nil) -> MainWindowController {
        let controller = controller(config: config)
        var options = CLIOptions()
        options.count = count
        controller.start(launch: launch(claude: claude, claudeArgs: claudeArgs, environment: environment),
                         options: options)
        return controller
    }

    /// `claude` de mentira: um script que o teste escreve.
    func fakeClaude(_ script: String) -> String {
        temp.write("bin/claude", "#!/bin/sh\n" + script + "\n", permissions: 0o755)
    }

    /// Encerra os processos dos agentes. Chamar no `tearDown`.
    func shutdown() {
        controllers.forEach { $0.shutdown() }
        controllers = []
    }
}
```

**Arquivo:** `mac/Tests/ClarkTests/MainWindowControllerTests.swift`

```swift
import AppKit
import ClarkCore
import XCTest
@testable import Clark

final class MainWindowControllerTests: XCTestCase {
    private var fixture: ClarkFixture!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        fixture = ClarkFixture()
    }

    override func tearDown() {
        fixture.shutdown()
        fixture = nil
        super.tearDown()
    }

    private func lines(_ pane: AgentPaneView) -> [String] {
        pane.terminal.linesAboveCursor()
    }

    private func savedConfig() -> ClarkConfig {
        fixture.store.load().config
    }

    private func click() -> NSEvent? {
        NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }

    // MARK: início

    func testStartsEmptyAndThenOpensAgents() {
        let controller = fixture.started()
        XCTAssertTrue(controller.panes.isEmpty)
        XCTAssertNil(controller.currentPane)
        XCTAssertTrue(controller.visiblePanes.isEmpty)
        XCTAssertEqual(controller.window?.title, "CLARK — 0 agentes")

        controller.addAgents(2)
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1", "AGENT 2"])
        XCTAssertTrue(controller.mainPane === controller.panes[1], "o agente novo vira o principal")
        XCTAssertTrue(controller.focusedPane === controller.panes[1])
        XCTAssertTrue(controller.window?.firstResponder === controller.panes[1].terminal)
        XCTAssertEqual(controller.liveAgentCount, 2)
        XCTAssertEqual(controller.window?.title, "CLARK — 2 agentes")
    }

    func testCountOptionOpensAgentsInTheDefaultDirectory() {
        let controller = fixture.started(agents: 3)
        XCTAssertEqual(controller.panes.count, 3)
        XCTAssertEqual(Set(controller.panes.map(\.directory)), [fixture.home])
        XCTAssertEqual(Set(controller.panes.map(\.sessionID)).count, 3)
        XCTAssertTrue(controller.panes.allSatisfy { SessionLocator.isValidUUID($0.sessionID) })
    }

    func testDirectoryOptionBecomesTheDefaultDirectory() {
        let project = fixture.temp.makeDirectory("Projetos/acme/app")
        let controller = fixture.controller()
        var options = CLIOptions()
        options.directory = project
        options.count = 1
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertEqual(controller.defaultDirectory, project)
        XCTAssertEqual(controller.panes[0].directory, project)
        XCTAssertEqual(controller.topBar.folderButton.title, "DIR ~/Projetos/acme/app")
        XCTAssertEqual(savedConfig().cwd, project)
    }

    func testMissingDirectoryOptionWarnsAndKeepsThePreviousOne() {
        let controller = fixture.controller()
        var options = CLIOptions()
        options.directory = fixture.home + "/nao-existe"
        controller.start(launch: fixture.launch(), options: options, startupWarnings: ["config.json invalido"])
        XCTAssertEqual(controller.defaultDirectory, fixture.home)
        XCTAssertEqual(controller.warnings.messages, [
            "config.json invalido",
            "claude nao encontrado: os agentes abrem o shell",
            "pasta nao encontrada: valendo a anterior",
        ])
    }

    func testSavedDirectoryThatVanishedFallsBackToHome() {
        var config = ClarkConfig()
        config.cwd = fixture.home + "/apagada"
        config.agents = [SavedAgent(name: "API", cwd: fixture.home + "/apagada", sessionID: nil, tone: nil)]
        let controller = fixture.started(config: config)
        XCTAssertEqual(controller.defaultDirectory, fixture.home)
        XCTAssertEqual(controller.panes[0].directory, fixture.home)
    }

    func testAgentWhoseFolderVanishedStartsANewConversationAtHome() throws {
        // Worktree apagada entre uma abertura e outra: a conversa antiga é de outra pasta,
        // e o `claude --resume` não a acha da home. Sem conversa nova, o agente nasce em GAME OVER.
        let gone = fixture.temp.makeDirectory("Projetos/acme/worktree")
        let id = SessionLocator.newID()
        fixture.temp.write(".claude/projects/-um-projeto/\(id).jsonl", "{}\n")
        var config = ClarkConfig()
        config.agents = [
            SavedAgent(name: "API", cwd: gone, sessionID: id, tone: nil),
            SavedAgent(name: "WEB", cwd: gone, sessionID: SessionLocator.newID(), tone: nil),
        ]
        try FileManager.default.removeItem(atPath: gone)

        let controller = fixture.started(config: config, claude: fixture.fakeClaude(printEnvironment))
        let pane = controller.panes[0]
        XCTAssertEqual(pane.directory, fixture.home)
        XCTAssertNotEqual(pane.sessionID, id)
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertTrue(lines(pane).contains("ARGS=--session-id \(pane.sessionID)"))
        XCTAssertEqual(controller.warnings.messages, ["pasta de agente sumiu: abriu na home, conversa nova"],
                       "um aviso só, mesmo com dois agentes na mesma situação")
        XCTAssertEqual(savedConfig().agents.map(\.sessionID), controller.panes.map(\.sessionID))
    }

    func testAgentLimit() {
        let controller = fixture.started()
        controller.addAgents(ClarkConfig.maxAgents + 4)
        XCTAssertEqual(controller.panes.count, ClarkConfig.maxAgents)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.count, ClarkConfig.maxAgents)
        let item = NSMenuItem(title: "", action: #selector(MainWindowController.newAgent(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
    }

    // MARK: layout

    func testFocusModeShowsOnePaneAndTheSidebar() {
        let controller = fixture.started(agents: 1)
        XCTAssertEqual(controller.layoutMode, "focus")
        XCTAssertTrue(controller.sidebar.isHidden, "um agente só não precisa de lista")

        controller.addAgents(2)
        XCTAssertFalse(controller.sidebar.isHidden)
        XCTAssertEqual(controller.sidebar.cards.count, 3)
        XCTAssertEqual(controller.visiblePanes.count, 1)
        XCTAssertTrue(controller.visiblePanes[0] === controller.panes[2])
        XCTAssertEqual(controller.panes.map(\.isHidden), [true, true, false])
        // Os ocultos ficam do tamanho do principal: trocar de agente não muda as colunas do terminal.
        XCTAssertEqual(Set(controller.panes.map { NSStringFromRect($0.frame) }).count, 1)
        XCTAssertLessThanOrEqual(controller.panes[2].frame.maxX, controller.sidebar.frame.minX)
        XCTAssertEqual(controller.sidebar.frame.width, CGFloat(SidebarView.width))
    }

    func testGridShowsEveryPaneWithoutOverlap() throws {
        let controller = fixture.started(agents: 4)
        controller.toggleLayout(nil)
        XCTAssertEqual(controller.layoutMode, "grid")
        XCTAssertTrue(controller.sidebar.isHidden)
        XCTAssertEqual(controller.visiblePanes.count, 4)
        XCTAssertFalse(controller.panes.contains(where: \.isHidden))
        XCTAssertEqual(controller.topBar.layoutButton.title, "GRADE")
        let content = try XCTUnwrap(controller.window?.contentView).bounds
        for (index, pane) in controller.panes.enumerated() {
            XCTAssertGreaterThan(pane.frame.width, 100)
            XCTAssertGreaterThan(pane.frame.height, 100)
            XCTAssertLessThanOrEqual(pane.frame.maxX, content.width)
            for other in controller.panes[(index + 1)...] {
                XCTAssertFalse(pane.frame.intersects(other.frame), "\(pane.name) sobre \(other.name)")
            }
        }
        XCTAssertEqual(savedConfig().layout, "grid")

        controller.toggleLayout(nil)
        XCTAssertEqual(controller.layoutMode, "focus")
        XCTAssertEqual(controller.visiblePanes.count, 1)
        XCTAssertEqual(controller.topBar.layoutButton.title, "FOCO")
    }

    func testZoomShowsOnlyOnePaneAndFollowsTheSelection() {
        let controller = fixture.started(agents: 3)
        controller.toggleLayout(nil)
        controller.toggleZoom(of: controller.panes[0])
        XCTAssertTrue(controller.zoomedPane === controller.panes[0])
        XCTAssertEqual(controller.panes.map(\.isHidden), [false, true, true])
        XCTAssertTrue(controller.currentPane === controller.panes[0])

        controller.select(controller.panes[2])
        XCTAssertTrue(controller.zoomedPane === controller.panes[2], "com zoom, selecionar troca o agente ampliado")
        XCTAssertEqual(controller.panes.map(\.isHidden), [true, true, false])

        controller.addAgents(1)
        XCTAssertTrue(controller.zoomedPane === controller.panes[3])

        controller.toggleZoom(nil)
        XCTAssertNil(controller.zoomedPane)
        XCTAssertEqual(controller.visiblePanes.count, 4)

        controller.toggleZoom(of: controller.panes[1])
        controller.toggleLayout(nil)
        XCTAssertNil(controller.zoomedPane, "trocar de layout desfaz o zoom")
    }

    func testSelectBringsTheAgentToTheMainPane() {
        let controller = fixture.started(agents: 3)
        let first = controller.panes[0]
        controller.select(first)
        XCTAssertTrue(controller.mainPane === first)
        XCTAssertTrue(controller.focusedPane === first)
        XCTAssertTrue(first.isFocused)
        XCTAssertFalse(controller.panes[2].isFocused)
        XCTAssertEqual(controller.panes.map(\.isHidden), [false, true, true])
        XCTAssertTrue(controller.window?.firstResponder === first.terminal)
        XCTAssertEqual(savedConfig().mainAgent, 0)
    }

    func testNextPreviousAndNumberShortcuts() {
        let controller = fixture.started(agents: 3)
        controller.nextAgent(nil)
        XCTAssertTrue(controller.mainPane === controller.panes[0], "depois do último vem o primeiro")
        controller.previousAgent(nil)
        XCTAssertTrue(controller.mainPane === controller.panes[2])

        let item = NSMenuItem(title: "", action: #selector(MainWindowController.selectAgentByNumber(_:)),
                              keyEquivalent: "2")
        item.tag = 2
        XCTAssertTrue(controller.validateMenuItem(item))
        controller.selectAgentByNumber(item)
        XCTAssertTrue(controller.mainPane === controller.panes[1])

        item.tag = 7
        XCTAssertFalse(controller.validateMenuItem(item))
        controller.selectAgentByNumber(item)
        XCTAssertTrue(controller.mainPane === controller.panes[1], "número sem agente não faz nada")
    }

    func testFocusInGridMakesThePaneTheMainOne() {
        let controller = fixture.started(agents: 3)
        controller.toggleLayout(nil)
        controller.window?.makeFirstResponder(controller.panes[0].terminal)
        XCTAssertTrue(controller.focusedPane === controller.panes[0])
        XCTAssertTrue(controller.mainPane === controller.panes[0])
        XCTAssertTrue(controller.currentPane === controller.panes[0])
        XCTAssertEqual(controller.sidebar.cards.map(\.isActive), [true, false, false])
    }

    // MARK: cards

    func testCardsMirrorTheAgents() {
        let controller = fixture.started(agents: 3)
        let cards = controller.sidebar.cards
        XCTAssertEqual(cards.map(\.snapshot.name), ["AGENT 1", "AGENT 2", "AGENT 3"])
        XCTAssertEqual(cards.map(\.index), [1, 2, 3])
        XCTAssertEqual(cards.map(\.isActive), [false, false, true])

        cards[0].onSelect?()
        XCTAssertTrue(controller.mainPane === controller.panes[0])
        XCTAssertEqual(controller.sidebar.cards.map(\.isActive), [true, false, false])

        cards[1].onClose?()
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1", "AGENT 3"])
        XCTAssertEqual(controller.sidebar.cards.map(\.index), [1, 2])
    }

    // MARK: fechar

    func testCloseMovesTheMainPaneToTheNeighbour() {
        let controller = fixture.started(agents: 3)
        let (first, second, third) = (controller.panes[0], controller.panes[1], controller.panes[2])
        controller.closeAgent(nil)
        XCTAssertEqual(controller.panes.count, 2)
        XCTAssertNil(third.superview)
        XCTAssertTrue(controller.mainPane === second)
        XCTAssertTrue(controller.window?.firstResponder === second.terminal)
        XCTAssertEqual(savedConfig().agents.map(\.name), ["AGENT 1", "AGENT 2"])

        controller.close(first)
        XCTAssertTrue(controller.mainPane === second)
        controller.close(second)
        XCTAssertTrue(controller.panes.isEmpty)
        XCTAssertNil(controller.mainPane)
        XCTAssertNil(controller.focusedPane)
        XCTAssertEqual(savedConfig().agents.count, 0)
        XCTAssertEqual(controller.liveAgentCount, 0)
    }

    func testClosedNumberIsReused() {
        let controller = fixture.started(agents: 3)
        controller.close(controller.panes[1])
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1", "AGENT 3", "AGENT 2"])
    }

    func testCloseAllChoices() {
        let controller = fixture.started(agents: 3)
        controller.select(controller.panes[0])
        let choices = controller.closeAllChoices()
        XCTAssertEqual(choices.map(\.title), ["Cancelar", "Só os outros (2)", "Todos (3)"])
        XCTAssertTrue(choices[0].panes.isEmpty)
        XCTAssertEqual(choices[1].panes.map(\.name), ["AGENT 2", "AGENT 3"])
        XCTAssertEqual(choices[2].panes.count, 3)

        choices[1].panes.forEach(controller.close)
        XCTAssertEqual(controller.closeAllChoices().map(\.title), ["Cancelar", "Todos (1)"])
    }

    // MARK: nome, pasta e fonte

    func testRenameSanitizesAndPersists() {
        let controller = fixture.started(agents: 1)
        let pane = controller.panes[0]
        controller.applyRename(pane, text: "  api de pagamentos do cliente  ")
        XCTAssertEqual(pane.name, "API DE PAGAMENTOS DO")
        XCTAssertEqual(pane.header.snapshot.name, "API DE PAGAMENTOS DO")
        XCTAssertEqual(savedConfig().agents.first?.name, "API DE PAGAMENTOS DO")

        controller.applyRename(pane, text: "   ")
        XCTAssertEqual(pane.name, "API DE PAGAMENTOS DO", "nome vazio não troca nada")
    }

    func testChangingTheFolderAffectsOnlyNewAgents() {
        let project = fixture.temp.makeDirectory("Projetos/beta")
        let controller = fixture.started(agents: 1)
        controller.setDefaultDirectory(fixture.home + "/nao-existe")
        XCTAssertEqual(controller.defaultDirectory, fixture.home)

        controller.setDefaultDirectory(project)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.map(\.directory), [fixture.home, project])
        XCTAssertEqual(controller.topBar.folderButton.title, "DIR ~/Projetos/beta")
    }

    func testFontScaleIsClampedAndReachesEveryTerminal() {
        let controller = fixture.started(agents: 2)
        controller.increaseFont(nil)
        XCTAssertEqual(controller.fontScale, 1.1, accuracy: 0.0001)
        XCTAssertEqual(controller.panes[0].terminal.font.pointSize, 13.2, accuracy: 0.01)
        XCTAssertEqual(controller.panes[1].terminal.font.pointSize, 13.2, accuracy: 0.01)
        XCTAssertEqual(savedConfig().fontScale, 1.1, accuracy: 0.0001)

        controller.setFontScale(99)
        XCTAssertEqual(controller.fontScale, 2.5)
        controller.setFontScale(-3)
        XCTAssertEqual(controller.fontScale, 0.6)
        controller.resetFont(nil)
        XCTAssertEqual(controller.fontScale, 1)
        controller.decreaseFont(nil)
        XCTAssertEqual(controller.fontScale, 0.9, accuracy: 0.0001)

        controller.addAgents(1)
        XCTAssertEqual(controller.panes[2].terminal.font.pointSize, 10.8, accuracy: 0.01, "agente novo já nasce na escala")
    }

    // MARK: salvar e restaurar

    func testAgentsComeBackAfterReopening() {
        let project = fixture.temp.makeDirectory("Projetos/acme")
        let first = fixture.started(agents: 2)
        first.setDefaultDirectory(project)
        first.addAgents(1)
        first.applyRename(first.panes[1], text: "revisor")
        first.toggleLayout(nil)
        first.select(first.panes[1])
        let saved = first.panes.map { [$0.name, $0.directory, $0.sessionID, String($0.tone)] }
        first.shutdown()

        let second = fixture.started()
        XCTAssertEqual(second.panes.map { [$0.name, $0.directory, $0.sessionID, String($0.tone)] }, saved)
        XCTAssertEqual(second.panes.map(\.name), ["AGENT 1", "REVISOR", "AGENT 3"])
        XCTAssertEqual(second.layoutMode, "grid")
        XCTAssertTrue(second.mainPane === second.panes[1])
        XCTAssertEqual(second.defaultDirectory, project)
    }

    func testCountOptionAddsToTheRestoredAgents() {
        fixture.started(agents: 2).shutdown()
        let controller = fixture.started(agents: 1)
        XCTAssertEqual(controller.panes.map(\.name), ["AGENT 1", "AGENT 2", "AGENT 3"])
        XCTAssertTrue(controller.mainPane === controller.panes[2])
    }

    func testFreshIgnoresTheSavedAgents() {
        fixture.started(agents: 2).shutdown()
        let controller = fixture.controller()
        var options = CLIOptions()
        options.fresh = true
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertTrue(controller.panes.isEmpty)
    }

    func testQuittingBeforeTheStartKeepsTheSavedAgents() {
        fixture.started(agents: 2).shutdown()
        // Fechou o app enquanto o ambiente do shell ainda era lido: a lista em memória está vazia.
        fixture.controller().shutdown()
        XCTAssertEqual(savedConfig().agents.count, 2)
    }

    func testRepeatedSessionIDGetsANewOne() {
        let id = SessionLocator.newID()
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "A", cwd: fixture.home, sessionID: id, tone: 0),
                         SavedAgent(name: "B", cwd: fixture.home, sessionID: id, tone: 1)]
        let controller = fixture.started(config: config)
        XCTAssertEqual(controller.panes[0].sessionID, id)
        XCTAssertNotEqual(controller.panes[1].sessionID, id, "duas abas na mesma conversa corromperiam o histórico")
    }

    func testUnknownConfigKeysSurviveASave() throws {
        fixture.temp.write(".config/clark/config.json", #"{"chave_do_futuro": {"x": 1}, "theme": "dark"}"#)
        let controller = fixture.started(agents: 1)
        controller.toggleLayout(nil)
        let data = try XCTUnwrap(FileManager.default.contents(atPath: fixture.store.configPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["chave_do_futuro"] as? [String: Int], ["x": 1])
        XCTAssertEqual(object["layout"] as? String, "grid")
    }

    func testConfigThatCannotBeSavedWarnsAndKeepsTheAgents() {
        // `~/.config/clark` é um arquivo: nada grava. O app segue aberto e avisa uma vez.
        fixture.temp.write(".config/clark", "nao sou uma pasta")
        let controller = fixture.started(agents: 2)
        controller.toggleLayout(nil)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.count, 3)
        XCTAssertEqual(controller.layoutMode, "grid")
        XCTAssertTrue(controller.panes.allSatisfy { $0.terminal.process.running })
        XCTAssertEqual(controller.warnings.messages, [
            "claude nao encontrado: os agentes abrem o shell",
            "config.json nao gravado: os agentes nao voltam ao reabrir",
        ])
    }

    func testSaveFailureWarningDoesNotComeBackAfterBeingDismissed() throws {
        fixture.temp.write(".config/clark", "nao sou uma pasta")
        let controller = fixture.started(agents: 2)
        let warning = "config.json nao gravado: os agentes nao voltam ao reabrir"
        XCTAssertTrue(controller.warnings.messages.contains(warning))
        // Um clique dispensa o aviso mostrado.
        let click = try XCTUnwrap(click())
        while !controller.warnings.messages.isEmpty { controller.warnings.mouseDown(with: click) }
        // Cada troca de agente grava de novo, e a gravação segue falhando.
        controller.select(controller.panes[0])
        controller.select(controller.panes[1])
        XCTAssertEqual(controller.warnings.messages, [])
    }

    // MARK: empresa e ambiente

    private let printEnvironment = """
    printf 'AGENTE=%s\\n' "$CLARK_AGENT"
    printf 'EMPRESA=%s\\n' "$CLARK_COMPANY"
    printf 'A=%s\\n' "${ACME_API_KEY:-vazio}"
    printf 'B=%s\\n' "${BETA_API_KEY:-vazio}"
    printf 'GH=%s\\n' "${GITHUB_TOKEN:-vazio}"
    printf 'PAI=%s\\n' "${CLAUDECODE:-vazio}"
    printf 'EDITOR=%s\\n' "$EDITOR"
    printf 'PASTA=%s\\n' "${PWD##*/}"
    printf 'ARGS=%s\\n' "$*"
    printf 'FIM\\n'
    read x
    """

    func testEachAgentGetsOnlyItsCompanyEnvironment() {
        let acme = fixture.temp.makeDirectory("Projetos/acme/api")
        let beta = fixture.temp.makeDirectory("clientes/beta")
        fixture.temp.write(".config/clark/companies.json", """
        {"companies": [
          {"name": "ACME", "paths": ["~/Projetos/acme"], "env_allow": ["ACME_API_KEY"], "color": "#ff00ff"},
          {"name": "BETA", "paths": ["~/clientes/beta"], "env_allow": ["BETA_API_KEY"], "color": "#00ffff"}
        ]}
        """)
        var environment = fixture.environment
        environment["ACME_API_KEY"] = "segredo-acme"
        environment["BETA_API_KEY"] = "segredo-beta"
        environment["GITHUB_TOKEN"] = "segredo-global"
        environment["CLAUDECODE"] = "1"
        environment["EDITOR"] = "vim"
        let controller = fixture.started(claude: fixture.fakeClaude(printEnvironment), environment: environment)
        XCTAssertEqual(controller.warnings.messages, [])

        controller.setDefaultDirectory(acme)
        controller.addAgents(1)
        controller.setDefaultDirectory(beta)
        controller.addAgents(1)
        let (first, second) = (controller.panes[0], controller.panes[1])
        XCTAssertTrue(waitUntil { self.lines(first).contains("FIM") && self.lines(second).contains("FIM") })

        XCTAssertEqual(first.company.name, "ACME")
        XCTAssertEqual(Array(lines(first).prefix(9)), [
            "AGENTE=AGENT 1", "EMPRESA=ACME", "A=segredo-acme", "B=vazio", "GH=vazio", "PAI=vazio", "EDITOR=vim",
            "PASTA=api", "ARGS=--session-id \(first.sessionID)",
        ])
        XCTAssertEqual(first.removedVariables, ["BETA_API_KEY", "GITHUB_TOKEN"])
        XCTAssertEqual(first.color, RGB(r: 1, g: 0, b: 1))

        XCTAssertEqual(second.company.name, "BETA")
        XCTAssertEqual(Array(lines(second).prefix(9)), [
            "AGENTE=AGENT 2", "EMPRESA=BETA", "A=vazio", "B=segredo-beta", "GH=vazio", "PAI=vazio", "EDITOR=vim",
            "PASTA=beta", "ARGS=--session-id \(second.sessionID)",
        ])
        XCTAssertEqual(second.removedVariables, ["ACME_API_KEY", "GITHUB_TOKEN"])
        XCTAssertEqual(second.header.snapshot.company, "BETA")

        let menu = first.contextMenu()
        XCTAssertEqual(menu.items.last?.title, "Variáveis removidas (2)")
        XCTAssertEqual(menu.items.last?.submenu?.items.map(\.title), ["BETA_API_KEY", "GITHUB_TOKEN"])
    }

    func testLinkIntoAnotherCompanyCountsAsTheDestination() throws {
        // Um link dentro da pasta da ACME que aponta para a BETA: o agente mexe nos arquivos da BETA,
        // então é da BETA e não recebe a chave da ACME.
        let acme = fixture.temp.makeDirectory("Projetos/acme")
        let beta = fixture.temp.makeDirectory("Projetos/beta/api")
        try FileManager.default.createSymbolicLink(atPath: acme + "/atalho", withDestinationPath: beta)
        fixture.temp.write(".config/clark/companies.json", """
        {"companies": [{"name": "ACME", "paths": ["~/Projetos/acme"], "env_allow": ["ACME_API_KEY"]}]}
        """)
        var environment = fixture.environment
        environment["ACME_API_KEY"] = "segredo-acme"
        let controller = fixture.started(claude: fixture.fakeClaude(printEnvironment), environment: environment)
        controller.setDefaultDirectory(acme + "/atalho")
        controller.addAgents(1)
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertEqual(pane.company.name, "beta")
        XCTAssertTrue(lines(pane).contains("A=vazio"))
        XCTAssertEqual(pane.removedVariables, ["ACME_API_KEY"])
    }

    func testCompanyRuleOnAFolderCreatedLaterStillMatches() throws {
        // A regra da BETA é escrita por um link e aponta para uma pasta que só nasce depois de o
        // CLARK abrir. Sem resolver a parte que já existe, o agente cairia na ACME, a empresa de fora.
        let temp = fixture.temp
        temp.makeDirectory("Projetos/acme")
        try FileManager.default.createSymbolicLink(atPath: temp.path + "/trab",
                                                   withDestinationPath: temp.path + "/Projetos")
        temp.write(".config/clark/companies.json", """
        {"companies": [
          {"name": "ACME", "paths": ["~/Projetos/acme"], "env_allow": ["ACME_API_KEY"]},
          {"name": "BETA", "paths": ["~/trab/acme/terceiro"], "env_allow": ["BETA_API_KEY"]}
        ]}
        """)
        let launch = fixture.launch()
        let company = launch.company(forDirectory: temp.makeDirectory("Projetos/acme/terceiro"))
        XCTAssertEqual(company.name, "BETA")
        XCTAssertEqual(company.envAllow, ["BETA_API_KEY"])
    }

    func testFolderOutsideAnyCompanyGetsNoSecret() {
        fixture.temp.write(".config/clark/companies.json", """
        {"env_allow": ["GITHUB_TOKEN"],
         "companies": [{"name": "ACME", "paths": ["~/Projetos/acme"], "env_allow": ["ACME_API_KEY"]}]}
        """)
        var environment = fixture.environment
        environment["ACME_API_KEY"] = "segredo-acme"
        environment["GITHUB_TOKEN"] = "liberado-para-todos"
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude(printEnvironment),
                                         environment: environment)
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { self.lines(pane).contains("FIM") })
        XCTAssertEqual(pane.company.name, CompanyResolver.fallbackName)
        XCTAssertEqual(Array(lines(pane)[1...4]), ["EMPRESA=AVULSO", "A=vazio", "B=vazio", "GH=liberado-para-todos"])
        XCTAssertEqual(pane.removedVariables, ["ACME_API_KEY"])
    }

    func testAgentsOfTheSameCompanyGetDifferentTones() {
        let project = fixture.temp.makeDirectory("Projetos/acme")
        let other = fixture.temp.makeDirectory("Projetos/beta")
        let controller = fixture.started()
        controller.setDefaultDirectory(project)
        controller.addAgents(2)
        controller.setDefaultDirectory(other)
        controller.addAgents(1)
        XCTAssertEqual(controller.panes.map(\.company.name), ["acme", "acme", "beta"])
        XCTAssertEqual(controller.panes.map(\.tone), [0, 1, 0])
        XCTAssertNotEqual(controller.panes[0].color, controller.panes[1].color)
    }

    func testSavedConversationIsResumed() {
        let id = SessionLocator.newID()
        fixture.temp.write(".claude/projects/-um-projeto/\(id).jsonl", "{}\n")
        var config = ClarkConfig()
        config.agents = [SavedAgent(name: "ANTIGO", cwd: fixture.home, sessionID: id, tone: 0)]
        let controller = fixture.started(agents: 1, config: config, claude: fixture.fakeClaude(printEnvironment),
                                         claudeArgs: ["--model", "opus"])
        let (old, new) = (controller.panes[0], controller.panes[1])
        XCTAssertTrue(waitUntil { self.lines(old).contains("FIM") && self.lines(new).contains("FIM") })
        XCTAssertTrue(lines(old).contains("ARGS=--model opus --resume \(id)"))
        XCTAssertTrue(lines(new).contains("ARGS=--model opus --session-id \(new.sessionID)"))
    }

    func testSkippingPermissionsShowsTheRedStrip() {
        let plain = fixture.started(agents: 1, claude: fixture.fakeClaude("read x")).panes[0]
        XCTAssertFalse(plain.bypassesPermissions)
        let plainImage = RenderedImage(plain, width: 660, height: 450)
        XCTAssertFalse(plainImage.isColor(Theme.dark.red, atX: 10, y: 37))
        let plainTop = plain.terminal.frame.minY

        let bypass = fixture.started(agents: 1, config: ClarkConfig(), claude: fixture.fakeClaude("read x"),
                                     claudeArgs: ["--dangerously-skip-permissions"]).panes[0]
        XCTAssertTrue(bypass.bypassesPermissions)
        let image = RenderedImage(bypass, width: 660, height: 450)
        XCTAssertTrue(image.isColor(Theme.dark.red, atX: 10, y: 37), "faixa SEM PERMISSOES")
        XCTAssertEqual(bypass.terminal.frame.minY - plainTop, CGFloat(AgentPaneView.stripHeight))
    }

    func testWithoutClaudeTheAgentOpensTheShellWithAWarning() {
        let controller = fixture.started(agents: 1)
        let pane = controller.panes[0]
        XCTAssertTrue(waitUntil { self.lines(pane).contains { $0.contains("claude nao encontrado no PATH") } })
        XCTAssertNotEqual(pane.state, .exited)
        XCTAssertEqual(controller.liveAgentCount, 1)
    }

    func testWithoutClaudeTheMenuDoesNotClaimRemovedVariables() {
        // Sem `claude` o painel abre o shell de login, que relê o rc: o que saiu do ambiente pode voltar.
        var environment = fixture.environment
        environment["GITHUB_TOKEN"] = "segredo"
        let controller = fixture.started(agents: 1, environment: environment)
        let item = controller.panes[0].contextMenu().items.last
        XCTAssertEqual(item?.title, "Sem claude: o shell relê o rc e o filtro de variáveis não vale")
        XCTAssertEqual(item?.isEnabled, false)
        XCTAssertNil(item?.submenu)
    }

    // MARK: estados e avisos

    /// Leva o agente a WORKING por `seconds` e deixa a saída parar.
    private func work(_ pane: AgentPaneView, in controller: MainWindowController, seconds: Double) {
        pane.terminal.onUserInput?()
        fixture.now += 1
        pane.terminal.onOutput?()
        controller.tick()
        XCTAssertEqual(pane.state, .working)
        fixture.now += seconds
        pane.terminal.onOutput?()
        controller.tick()
        fixture.now += 1.5
        controller.tick()
    }

    func testFinishedAgentNotifiesWhenNobodyIsLooking() {
        let controller = fixture.started(agents: 1)
        controller.isAppActive = { false }
        controller.isWindowKey = { false }
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        XCTAssertEqual(pane.state, .idle)

        work(pane, in: controller, seconds: 4)
        XCTAssertEqual(pane.state, .done)
        XCTAssertEqual(fixture.notifier.done, ["AGENT 1"])
        XCTAssertEqual(fixture.notifier.badges.last, 1)
        XCTAssertEqual(controller.window?.title, "(1) CLARK — 1 agentes")
        XCTAssertEqual(controller.topBar.stats.done, 1)
        XCTAssertEqual(controller.sidebar.cards.count, 1)

        // Voltar à janela com o agente em foco apaga o DONE.
        controller.isAppActive = { true }
        controller.isWindowKey = { true }
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        controller.tick()
        XCTAssertEqual(pane.state, .idle)
        XCTAssertEqual(fixture.notifier.badges.last, 0)
        XCTAssertEqual(controller.window?.title, "CLARK — 1 agentes")
    }

    func testWatchedAgentFinishesQuietly() {
        let controller = fixture.started(agents: 1)
        controller.isAppActive = { true }
        controller.isWindowKey = { true }
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        work(pane, in: controller, seconds: 4)
        XCTAssertEqual(pane.state, .idle)
        XCTAssertEqual(fixture.notifier.done, [])
    }

    func testShortBurstOfOutputIsNotAFinishedTask() {
        let controller = fixture.started(agents: 1)
        controller.isAppActive = { false }
        let pane = controller.panes[0]
        fixture.now += 5
        controller.tick()
        work(pane, in: controller, seconds: 0.5)
        XCTAssertEqual(pane.state, .idle)
        XCTAssertEqual(fixture.notifier.done, [])
    }

    func testHiddenAgentFinishingWithTheAppInFrontMarksDoneWithoutNotification() {
        let controller = fixture.started(agents: 2)
        controller.isAppActive = { true }
        controller.isWindowKey = { true }
        let hidden = controller.panes[0]
        fixture.now += 5
        controller.tick()
        work(hidden, in: controller, seconds: 4)
        XCTAssertEqual(hidden.state, .done)
        XCTAssertEqual(fixture.notifier.done, [], "com o app na frente, o card piscando já avisa")
        XCTAssertEqual(controller.sidebar.cards[0].snapshot.state, .done)

        controller.select(hidden)
        XCTAssertEqual(hidden.state, .idle)
    }

    func testBellMarksDone() {
        let controller = fixture.started(agents: 2)
        controller.isAppActive = { false }
        controller.panes[0].terminal.onBell?()
        XCTAssertEqual(controller.panes[0].state, .done)
        XCTAssertEqual(fixture.notifier.done, ["AGENT 1"])
    }

    func testClickingTheNotificationSelectsTheAgent() {
        let controller = fixture.started(agents: 3)
        fixture.notifier.onOpen?(controller.panes[0].sessionID)
        XCTAssertTrue(controller.mainPane === controller.panes[0])
        fixture.notifier.onOpen?("sessao-que-nao-existe")
        XCTAssertTrue(controller.mainPane === controller.panes[0])
    }

    func testGameOverAndEnterReopensTheSameConversation() {
        let script = """
        if [ -f "$HOME/viva" ]; then printf 'de volta\\n'; read x; fi
        exit 0
        """
        let controller = fixture.started(agents: 1, claude: fixture.fakeClaude(script))
        let pane = controller.panes[0]
        let sessionID = pane.sessionID
        XCTAssertTrue(waitUntil { pane.state == .exited })
        XCTAssertTrue(lines(pane).contains { $0.contains("GAME OVER") })
        XCTAssertEqual(controller.liveAgentCount, 0)
        controller.tick()
        XCTAssertEqual(controller.topBar.stats.exited, 1)
        XCTAssertTrue(RenderedImage(pane, width: 660, height: 450).isColor(Theme.dark.red, atX: 0, y: 0))
        XCTAssertEqual(savedConfig().agents.count, 1, "agente em GAME OVER continua salvo")

        fixture.temp.write("viva", "")
        let old = pane.terminal
        controller.window?.makeFirstResponder(old)
        old.send(txt: "x")
        XCTAssertTrue(pane.terminal === old, "só o Enter reabre")
        old.send(txt: "\r")
        XCTAssertFalse(pane.terminal === old, "terminal novo, sem o lixo do anterior")
        XCTAssertNil(old.superview)
        XCTAssertEqual(pane.state, .boot)
        XCTAssertEqual(pane.sessionID, sessionID)
        XCTAssertTrue(controller.window?.firstResponder === pane.terminal)
        XCTAssertTrue(waitUntil { self.lines(pane).contains("de volta") })
        XCTAssertEqual(controller.liveAgentCount, 1)
    }

    func testClaudeThatCannotRunEndsInGameOver() {
        let controller = fixture.started(agents: 1, claude: fixture.home + "/bin/nao-existe")
        XCTAssertTrue(waitUntil { controller.panes[0].state == .exited })
    }

    func testPaneBorderFollowsFocusAndState() {
        let controller = fixture.started(agents: 2)
        controller.toggleLayout(nil)
        let (first, second) = (controller.panes[0], controller.panes[1])
        XCTAssertTrue(RenderedImage(second, width: 660, height: 450).isColor(Theme.dark.accent, atX: 1, y: 1))
        XCTAssertTrue(RenderedImage(first, width: 660, height: 450).isColor(Theme.dark.bg3, atX: 1, y: 1))
        controller.isAppActive = { false }
        first.terminal.onBell?()
        XCTAssertTrue(RenderedImage(first, width: 660, height: 450).isColor(Theme.dark.yellow, atX: 1, y: 1))
    }

    // MARK: menu

    func testMenuItemsFollowTheAgents() {
        let controller = fixture.controller()
        func enabled(_ action: Selector) -> Bool {
            controller.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        XCTAssertFalse(enabled(#selector(MainWindowController.newAgent(_:))), "antes do ambiente do shell")
        XCTAssertFalse(enabled(#selector(MainWindowController.chooseFolder(_:))))

        var options = CLIOptions()
        controller.start(launch: fixture.launch(), options: options)
        XCTAssertTrue(enabled(#selector(MainWindowController.newAgent(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.closeAllAgents(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.toggleZoom(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.nextAgent(_:))))
        XCTAssertTrue(enabled(#selector(MainWindowController.toggleLayout(_:))))

        controller.addAgents(1)
        XCTAssertTrue(enabled(#selector(MainWindowController.renameAgent(_:))))
        XCTAssertFalse(enabled(#selector(MainWindowController.previousAgent(_:))))
        controller.addAgents(1)
        XCTAssertTrue(enabled(#selector(MainWindowController.previousAgent(_:))))
        options.count = 0
    }

    func testMenuShortcutsAreUniqueAndReachTheController() {
        let controller = fixture.controller()
        var leaves: [NSMenuItem] = []
        func collect(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { collect(submenu) } else if !item.isSeparatorItem { leaves.append(item) }
            }
        }
        collect(MainMenu.build())

        let shortcuts = leaves.filter { !$0.keyEquivalent.isEmpty }.map {
            "\($0.keyEquivalentModifierMask.contains(.option) ? "opt+" : "")\($0.keyEquivalent)"
        }
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count, "atalho repetido: \(shortcuts)")
        for key in ["n", "w", "d", "l", "\r", "{", "}", "+", "=", "-", "0", "c", "v", "q"] + (1...9).map(String.init) {
            XCTAssertTrue(shortcuts.contains(key), "falta ⌘\(key)")
        }
        XCTAssertFalse(shortcuts.contains("t"), "⌘T é da fila de tarefas, que chega no M2")

        // Toda ação do CLARK no menu precisa existir no controller: seletor errado vira item morto, sem erro.
        let expected = ["newAgent:", "chooseFolder:", "closeAgent:", "closeAllAgents:", "toggleLayout:", "toggleZoom:",
                        "increaseFont:", "decreaseFont:", "resetFont:", "previousAgent:", "nextAgent:",
                        "renameAgent:", "selectAgentByNumber:"]
        let actions = Set(leaves.compactMap(\.action).map(NSStringFromSelector))
        for name in expected {
            XCTAssertTrue(actions.contains(name), "falta no menu: \(name)")
            XCTAssertTrue(controller.responds(to: NSSelectorFromString(name)), "controller sem \(name)")
        }
        let system = ["orderFrontStandardAboutPanel:", "hide:", "hideOtherApplications:", "terminate:", "copy:",
                      "paste:", "selectAll:", "performMiniaturize:", "performZoom:"]
        XCTAssertEqual(actions, Set(expected + system), "item novo no menu sem teste")
        XCTAssertEqual(leaves.filter { $0.action == #selector(MainWindowController.selectAgentByNumber(_:)) }
            .map(\.tag), Array(1...9))
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkTests/ClarkFixture.swift:5:26: error: cannot find type 'Notifying' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/Clark/Notifier.swift`

```swift
import AppKit
import UserNotifications

/// Avisos de agente pronto. Separado num protocolo para os testes não tocarem no sistema.
protocol Notifying: AnyObject {
    /// Chamado com o `session_id` do agente quando o usuário clica na notificação.
    var onOpen: ((String) -> Void)? { get set }
    /// Notificação do macOS e pedido de atenção no Dock.
    func agentDone(name: String, sessionID: String)
    /// Selo do Dock com a contagem de agentes em DONE.
    func setBadge(_ count: Int)
}

final class Notifier: NSObject, Notifying, UNUserNotificationCenterDelegate {
    var onOpen: ((String) -> Void)?
    // Sem bundle (binário solto do `swift build`) o centro de notificações aborta o processo.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()

    func start() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func agentDone(name: String, sessionID: String) {
        NSApp.requestUserAttention(.informationalRequest)
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "CLARK · \(name)"
        content.body = "Terminou e está te esperando."
        content.sound = .default
        content.userInfo = ["session_id": sessionID]
        // O mesmo identificador por agente: um aviso novo substitui o anterior.
        center.add(UNNotificationRequest(identifier: sessionID, content: content, trigger: nil))
    }

    func setBadge(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let sessionID = response.notification.request.content.userInfo["session_id"] as? String
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            if let sessionID { self?.onOpen?(sessionID) }
            completionHandler()
        }
    }
}
```

**Arquivo:** `mac/Sources/Clark/AgentPaneView.swift`

```swift
import AppKit
import ClarkCore

/// O que todo agente precisa para abrir o processo. Montado uma vez, depois da captura do ambiente.
struct AgentLaunch {
    var baseEnvironment: [String: String]
    /// nil: o `claude` não foi encontrado e o painel abre o shell com o aviso.
    var claudePath: String?
    var shell: String
    var home: String
    /// Argumentos extras vindos de `clark -- <args>`.
    var claudeArgs: [String]
    var resolver: CompanyResolver

    /// A pasta pedida quando existe; senão a home.
    func usableDirectory(_ directory: String) -> String {
        PathTools.isDirectory(directory) ? directory : home
    }

    func company(forDirectory directory: String) -> Company {
        resolver.resolve(canonicalPath: PathTools.canonical(usableDirectory(directory), base: home, home: home))
    }
}

protocol AgentPaneDelegate: AnyObject {
    /// O painel está com o foco e a janela está ativa.
    func paneIsWatched(_ pane: AgentPaneView) -> Bool
    /// O agente terminou e ninguém está olhando.
    func paneNeedsAttention(_ pane: AgentPaneView)
    /// Estado, nome ou prévia mudaram.
    func paneDidChange(_ pane: AgentPaneView)
    func paneRequestsSelect(_ pane: AgentPaneView)
    func paneRequestsZoom(_ pane: AgentPaneView)
    func paneRequestsClose(_ pane: AgentPaneView)
    func paneRequestsRename(_ pane: AgentPaneView)
}

/// Painel de um agente: moldura, cabeçalho, faixa de aviso e o terminal.
final class AgentPaneView: PixelView {
    static let border = 3
    static let stripHeight = 16
    static let gameOver = "\r\n\r\n\u{1b}[1;41;97m  GAME OVER  \u{1b}[0m  "
        + "\u{1b}[2mENTER = continue?  CMD+W = sair\u{1b}[0m\r\n"
    static let missingClaude = "\r\n\u{1b}[1;31m  claude nao encontrado no PATH.\u{1b}[0m "
        + "Instale o Claude Code e reabra o CLARK.\r\n\r\n"
    static let launchFailed = "\r\n\u{1b}[1;31m  falha ao iniciar o processo.\u{1b}[0m\r\n"
    static let unfilteredShell = "Sem claude: o shell relê o rc e o filtro de variáveis não vale"

    private(set) var name: String
    private(set) var directory: String
    let sessionID: String
    /// Passo de escurecimento da cor da empresa.
    let tone: Int
    let company: Company
    private(set) var machine: AgentStateMachine
    private(set) var terminal: AgentTerminalView
    private(set) var preview: [String] = []
    /// Nomes das variáveis que a política de ambiente tirou deste agente. Nunca os valores.
    private(set) var removedVariables: [String] = []
    private(set) var bypassesPermissions = false
    weak var delegate: AgentPaneDelegate?
    var isFocused = false { didSet { if isFocused != oldValue { needsDisplay = true } } }

    let header: AgentHeaderView
    private let zoomButton = PixelButton(title: "[ ]", style: .mini, toolTip: "Zoom (⌘↩)")
    private let closeButton = PixelButton(title: "X", style: .miniClose, toolTip: "Fechar (⌘W)")
    private let launch: AgentLaunch
    private var terminalAppearance: TerminalAppearance
    private let clock: () -> Double
    private var previewAt = -Double.infinity

    var color: RGB { CompanyResolver.tone(company.color, index: tone) }
    var state: AgentState { machine.state }

    var snapshot: AgentSnapshot {
        AgentSnapshot(name: name, company: company.name, color: color,
                      path: PathTools.short(directory, home: launch.home), state: machine.state, preview: preview)
    }

    init(name: String, directory: String, sessionID: String, tone: Int, launch: AgentLaunch,
         appearance: TerminalAppearance, clock: @escaping () -> Double) {
        self.name = name
        self.directory = launch.usableDirectory(directory)
        self.sessionID = sessionID
        self.tone = tone
        self.launch = launch
        terminalAppearance = appearance
        self.clock = clock
        company = launch.company(forDirectory: directory)
        machine = AgentStateMachine(now: clock())
        terminal = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        header = AgentHeaderView(snapshot: AgentSnapshot(name: name, company: "", color: .black, path: "",
                                                         state: .boot))
        super.init(frame: NSRect(x: 0, y: 0, width: 660, height: 450))
        theme = appearance.theme
        header.theme = appearance.theme
        header.snapshot = snapshot
        header.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsSelect($0) } }
        header.onDoubleClick = { [weak self] in self.map { $0.delegate?.paneRequestsRename($0) } }
        header.menuProvider = { [weak self] in self?.contextMenu() }
        zoomButton.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsZoom($0) } }
        closeButton.onClick = { [weak self] in self.map { $0.delegate?.paneRequestsClose($0) } }
        addSubview(header)
        addSubview(zoomButton)
        addSubview(closeButton)
        install(terminal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    // MARK: processo

    /// Abre o `claude` (ou o shell, sem `claude`) no terminal atual.
    func spawn() {
        let now = clock()
        let environment = EnvPolicy.apply(base: launch.baseEnvironment, globalAllow: launch.resolver.globalEnvAllow,
                                          company: company, agentName: name)
        removedVariables = environment.removed
        machine.spawned(now: now)
        if let claude = launch.claudePath {
            let configDir = SessionLocator.configDir(environment: environment.variables, home: launch.home)
            let command = ClaudeCommand.build(
                extraArgs: launch.claudeArgs, sessionID: sessionID,
                sessionExists: SessionLocator.sessionExists(sessionID, configDir: configDir))
            bypassesPermissions = command.bypassesPermissions
            terminal.startProcess(executable: claude, args: command.arguments, environment: environment.asArray,
                                  currentDirectory: directory)
        } else {
            bypassesPermissions = false
            terminal.feed(text: Self.missingClaude)
            terminal.startProcess(executable: launch.shell, args: ["-l"], environment: environment.asArray,
                                  currentDirectory: directory)
        }
        if !terminal.process.running && !terminal.hasExited {
            terminal.feed(text: Self.launchFailed)
            terminal.markExited()
            machine.exited()
        }
        needsLayout = true
        changed()
    }

    /// Enter em GAME OVER: terminal novo, mesma conversa.
    func respawn() {
        guard machine.state == .exited else { return }
        let hadFocus = window?.firstResponder === terminal
        detach(terminal)
        terminal = AgentTerminalView(frame: terminal.frame)
        install(terminal)
        spawn()
        if hadFocus { window?.makeFirstResponder(terminal) }
    }

    /// SIGHUP no processo. Chamado ao fechar o agente e ao sair do app.
    func shutdown() {
        let process = terminal.process
        detach(terminal)
        if let process, process.running { ProcessReaper.hangUp(process.shellPid) }
    }

    private func install(_ terminal: AgentTerminalView) {
        terminal.apply(terminalAppearance)
        terminal.changeScrollback(AgentTerminalView.scrollbackLines)
        terminal.onOutput = { [weak self] in self.map { $0.machine.output(now: $0.clock()) } }
        terminal.onUserInput = { [weak self] in
            guard let self else { return }
            let before = self.machine.state
            self.machine.userInput(now: self.clock())
            if self.machine.state != before { self.changed() }
        }
        terminal.onResize = { [weak self] in self.map { $0.machine.resized(now: $0.clock()) } }
        terminal.onBell = { [weak self] in
            guard let self else { return }
            let notify = self.machine.bell(watched: self.delegate?.paneIsWatched(self) ?? false)
            self.changed()
            if notify { self.delegate?.paneNeedsAttention(self) }
        }
        terminal.onExit = { [weak self] _ in
            guard let self else { return }
            self.machine.exited()
            self.terminal.feed(text: Self.gameOver)
            self.changed()
        }
        terminal.onRestartRequested = { [weak self] in self?.respawn() }
        addSubview(terminal)
        needsLayout = true
    }

    private func detach(_ terminal: AgentTerminalView) {
        terminal.onOutput = nil
        terminal.onUserInput = nil
        terminal.onResize = nil
        terminal.onBell = nil
        terminal.onExit = nil
        terminal.onRestartRequested = nil
        terminal.removeFromSuperview()
    }

    // MARK: estado

    /// Tique de 100 ms.
    func tick(now: Double) {
        let before = machine.state
        let notify = machine.tick(now: now, watched: delegate?.paneIsWatched(self) ?? false)
        if machine.state != before { changed() }
        if notify { delegate?.paneNeedsAttention(self) }
        if StateLabel.isAnimated(machine.state) { header.time = now }
    }

    /// O painel ganhou o foco do teclado.
    func focused() {
        let before = machine.state
        machine.focused(now: clock())
        if machine.state != before { changed() }
    }

    /// O painel mudou de lugar ou de tamanho por troca de layout.
    func layoutChanged() {
        machine.layoutChanged(now: clock())
    }

    /// Relê as últimas linhas úteis do terminal. Devolve true quando a prévia mudou.
    @discardableResult
    func refreshPreview(now: Double, force: Bool = false) -> Bool {
        let interval = machine.lastChange > previewAt ? 0.5 : 2.0
        guard force || now - previewAt > interval else { return false }
        previewAt = now
        let lines = PreviewLines.useful(terminal.linesAboveCursor())
        guard lines != preview else { return false }
        preview = lines
        return true
    }

    func rename(_ newName: String) {
        guard newName != name else { return }
        name = newName
        changed()
    }

    func apply(_ appearance: TerminalAppearance) {
        terminalAppearance = appearance
        theme = appearance.theme
        header.theme = appearance.theme
        zoomButton.theme = appearance.theme
        closeButton.theme = appearance.theme
        terminal.apply(appearance)
    }

    private func changed() {
        header.snapshot = snapshot
        needsDisplay = true
        delegate?.paneDidChange(self)
    }

    /// Menu do cabeçalho. Mostra só os nomes das variáveis removidas.
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(actionItem("Renomear…") { [weak self] in self.map { $0.delegate?.paneRequestsRename($0) } })
        menu.addItem(actionItem("Zoom") { [weak self] in self.map { $0.delegate?.paneRequestsZoom($0) } })
        menu.addItem(actionItem("Fechar") { [weak self] in self.map { $0.delegate?.paneRequestsClose($0) } })
        menu.addItem(.separator())
        // Sem `claude` o painel é o shell de login, que relê o rc e devolve o que saiu do ambiente:
        // o menu não afirma uma remoção que não vale ali.
        guard launch.claudePath != nil else {
            let unfiltered = NSMenuItem(title: Self.unfilteredShell, action: nil, keyEquivalent: "")
            unfiltered.isEnabled = false
            menu.addItem(unfiltered)
            return menu
        }
        let title = removedVariables.isEmpty
            ? "Nenhuma variável removida"
            : "Variáveis removidas (\(removedVariables.count))"
        let removed = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        removed.isEnabled = !removedVariables.isEmpty
        if !removedVariables.isEmpty {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for variable in removedVariables {
                let item = NSMenuItem(title: variable, action: nil, keyEquivalent: "")
                item.isEnabled = false
                submenu.addItem(item)
            }
            removed.submenu = submenu
        }
        menu.addItem(removed)
        return menu
    }

    private func actionItem(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuHandler(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = handler
        return item
    }

    @objc private func runMenuHandler(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }

    // MARK: desenho

    private var headerBottom: Int { Self.border + AgentHeaderView.height + 2 }

    override func layout() {
        super.layout()
        let width = Int(bounds.width), height = Int(bounds.height)
        let border = Self.border
        let zoomWidth = zoomButton.fittingWidth, closeWidth = closeButton.fittingWidth
        header.frame = NSRect(x: border, y: border, width: max(0, width - 2 * border - zoomWidth - closeWidth),
                              height: AgentHeaderView.height)
        zoomButton.frame = NSRect(x: width - border - closeWidth - zoomWidth, y: border, width: zoomWidth,
                                  height: AgentHeaderView.height)
        closeButton.frame = NSRect(x: width - border - closeWidth, y: border, width: closeWidth,
                                   height: AgentHeaderView.height)
        let top = headerBottom + (bypassesPermissions ? Self.stripHeight : 0) + 4
        terminal.frame = NSRect(x: border + 6, y: top, width: max(1, width - 2 * border - 12),
                                height: max(1, height - top - border - 4))
    }

    override func render(_ context: CGContext, width: Int, height: Int) {
        Pixel.fill(context, 0, 0, width, height, theme.bg)
        let edge: RGB
        switch machine.state {
        case .exited: edge = theme.red
        case .done: edge = theme.yellow
        default: edge = isFocused ? theme.accent : theme.bg3
        }
        Pixel.frame(context, 0, 0, width, height, thickness: Self.border, edge)
        Pixel.fill(context, Self.border, headerBottom - 2, width - 2 * Self.border, 2, theme.shadow)
        if bypassesPermissions {
            let label = "SEM PERMISSOES"
            Pixel.fill(context, Self.border, headerBottom, width - 2 * Self.border, Self.stripHeight, theme.red)
            Pixel.text(context, label, (width - PixelFont.textWidth(label, scale: 1)) / 2,
                       headerBottom + (Self.stripHeight - 7) / 2, scale: 1, theme.bg)
        }
    }
}
```

**Arquivo:** `mac/Sources/Clark/MainWindowController.swift`

```swift
import AppKit
import ClarkCore

/// Janela do CLARK: barra superior, modos foco e grade, zoom, atalhos, salvar e restaurar.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, AgentPaneDelegate {
    static let margin: CGFloat = 6
    static let fontStep = 0.1

    private(set) var panes: [AgentPaneView] = []
    /// Agente do painel principal no modo foco.
    private(set) var mainPane: AgentPaneView?
    /// Agente cujo terminal está com o teclado.
    private(set) var focusedPane: AgentPaneView?
    private(set) var zoomedPane: AgentPaneView?
    private(set) var layoutMode: String
    /// Pasta em que os novos agentes abrem.
    private(set) var defaultDirectory: String
    private(set) var fontScale: Double
    private(set) var launch: AgentLaunch?
    let warnings = WarningBarView()
    let sidebar = SidebarView()
    let topBar = TopBarView()
    /// O app está na frente. Trocado nos testes, que rodam sem app ativo.
    var isAppActive: () -> Bool = { NSApplication.shared.isActive }
    /// A janela está com o teclado. Trocado nos testes, que rodam sem janela na tela.
    lazy var isWindowKey: () -> Bool = { [weak self] in self?.window?.isKeyWindow ?? false }

    private var config: ClarkConfig
    private let store: ConfigStore
    private let home: String
    private let notifier: Notifying
    private let clock: () -> Double
    private let theme: Theme
    private let root = FlippedView()
    private let stage = FlippedView()
    private let emptyView = EmptyStateView()
    private var cards: [ObjectIdentifier: AgentCardView] = [:]
    private var timer: Timer?
    private var responderObservation: NSKeyValueObservation?
    private var renamePopover: NSPopover?
    private weak var renameTarget: AgentPaneView?
    private var saveFailureWarned = false
    private var lastTitle = ""
    private var lastBadge = -1
    private var lastBlink = -1

    init(config: ClarkConfig, store: ConfigStore, home: String, notifier: Notifying,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.config = config
        self.store = store
        self.home = home
        self.notifier = notifier
        self.clock = clock
        layoutMode = config.layout
        fontScale = config.fontScale
        defaultDirectory = config.cwd.flatMap { PathTools.isDirectory($0) ? $0 : nil } ?? home
        theme = Theme.named(config.theme)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 840),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.title = "CLARK"
        window.backgroundColor = theme.bg.nsColor
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildViews(in: window)
        responderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            self?.firstResponderChanged()
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        notifier.onOpen = { [weak self] sessionID in
            guard let self, let pane = self.panes.first(where: { $0.sessionID == sessionID }) else { return }
            self.select(pane)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    private var terminalAppearance: TerminalAppearance {
        TerminalAppearance(theme: theme, fontName: config.fontName, fontSize: config.fontSize * fontScale)
    }

    private func buildViews(in window: NSWindow) {
        root.frame = window.contentLayoutRect
        root.onLayout = { [weak self] in self?.layoutContent() }
        window.contentView = root
        for view in [topBar, warnings, sidebar, emptyView] as [PixelView] { view.theme = theme }
        [stage, emptyView, sidebar, warnings, topBar].forEach(root.addSubview)
        topBar.folderButton.onClick = { [weak self] in self?.chooseFolder(nil) }
        topBar.layoutButton.onClick = { [weak self] in self?.toggleLayout(nil) }
        topBar.addButton.onClick = { [weak self] in self?.addAgents(1) }
        sidebar.closeAllButton.onClick = { [weak self] in self?.closeAllAgents(nil) }
        emptyView.onAdd = { [weak self] count in self?.addAgents(count) }
        warnings.onChange = { [weak self] in self?.layoutContent() }
        updateButtonTitles()
        layoutContent()
    }

    // MARK: início e fim

    /// Chamado uma vez, quando o ambiente do shell já foi lido.
    func start(launch: AgentLaunch, options: CLIOptions, startupWarnings: [String] = []) {
        self.launch = launch
        startupWarnings.forEach(warnings.add)
        launch.resolver.warnings.forEach(warnings.add)
        if launch.claudePath == nil { warnings.add("claude nao encontrado: os agentes abrem o shell") }
        if let directory = options.directory {
            if PathTools.isDirectory(directory) {
                defaultDirectory = directory
            } else {
                warnings.add("pasta nao encontrada: valendo a anterior")
            }
        }
        emptyView.isLoading = false
        updateButtonTitles()

        var created: [AgentPaneView] = []
        if !options.fresh {
            for saved in config.agents {
                let directory = saved.cwd ?? defaultDirectory
                // A pasta sumiu (uma worktree apagada): o agente abre na home, e a conversa antiga,
                // que é da outra pasta, não é retomada de lá.
                let vanished = !PathTools.isDirectory(directory)
                if vanished { warnings.add("pasta de agente sumiu: abriu na home, conversa nova") }
                let reused = saved.sessionID.map { id in panes.contains { $0.sessionID == id } } ?? false
                let name = saved.name.flatMap(AgentNaming.sanitized)
                    ?? AgentNaming.automaticName(existing: panes.map(\.name))
                if let pane = makePane(name: name, directory: directory,
                                       sessionID: reused || vanished ? nil : saved.sessionID, tone: saved.tone) {
                    created.append(pane)
                }
            }
            if panes.indices.contains(config.mainAgent) { mainPane = panes[config.mainAgent] }
        }
        for _ in 0..<options.count {
            guard let pane = makePane(name: AgentNaming.automaticName(existing: panes.map(\.name)),
                                      directory: defaultDirectory, sessionID: nil, tone: nil) else { break }
            created.append(pane)
            mainPane = pane
        }
        relayout()
        settleLayout()
        created.forEach { $0.spawn() }
        if let mainPane { focusTerminal(of: mainPane) }
        persist()
    }

    /// Quantos agentes ainda têm processo vivo.
    var liveAgentCount: Int { panes.filter { $0.state != .exited }.count }

    /// Grava a lista de agentes e encerra os processos. Chamado ao sair do app.
    func shutdown() {
        persist()
        timer?.invalidate()
        timer = nil
        responderObservation = nil
        panes.forEach { $0.shutdown() }
    }

    func persist() {
        // Antes do `start` a lista em memória está vazia: gravar apagaria os agentes salvos.
        guard launch != nil else { return }
        config.layout = layoutMode
        config.fontScale = fontScale
        config.cwd = defaultDirectory
        config.agents = panes.map {
            SavedAgent(name: $0.name, cwd: $0.directory, sessionID: $0.sessionID, tone: $0.tone)
        }
        config.mainAgent = mainPane.flatMap { main in panes.firstIndex { $0 === main } } ?? 0
        // Falha de gravação não interrompe nada: o estado em memória segue valendo, e fica o aviso.
        // Um aviso por sessão: dispensado, ele não volta a cada gravação que falha.
        do {
            try store.save(config)
        } catch {
            guard !saveFailureWarned else { return }
            saveFailureWarned = true
            warnings.add("config.json nao gravado: os agentes nao voltam ao reabrir")
        }
    }

    // MARK: agentes

    /// Cria o painel sem abrir o processo: o `spawn` vem depois do layout, com o terminal já no tamanho certo.
    private func makePane(name: String, directory: String, sessionID: String?, tone: Int?) -> AgentPaneView? {
        guard let launch, panes.count < ClarkConfig.maxAgents else { return nil }
        let company = launch.company(forDirectory: directory)
        let usedTones = panes.filter { $0.company.name == company.name }.map(\.tone)
        let pane = AgentPaneView(name: name, directory: directory, sessionID: sessionID ?? SessionLocator.newID(),
                                 tone: tone ?? AgentNaming.freeTone(used: usedTones), launch: launch,
                                 appearance: terminalAppearance, clock: clock)
        pane.delegate = self
        panes.append(pane)
        stage.addSubview(pane)
        let card = AgentCardView(snapshot: pane.snapshot)
        card.onSelect = { [weak self, weak pane] in
            if let self, let pane { self.select(pane) }
        }
        card.onClose = { [weak self, weak pane] in
            if let self, let pane { self.close(pane) }
        }
        cards[ObjectIdentifier(pane)] = card
        return pane
    }

    func addAgents(_ count: Int) {
        var created: [AgentPaneView] = []
        for _ in 0..<max(0, count) {
            guard let pane = makePane(name: AgentNaming.automaticName(existing: panes.map(\.name)),
                                      directory: defaultDirectory, sessionID: nil, tone: nil) else { break }
            created.append(pane)
        }
        guard let last = created.last else { return }
        mainPane = last
        if zoomedPane != nil { zoomedPane = last }
        relayout()
        settleLayout()
        created.forEach { $0.spawn() }
        focusTerminal(of: last)
        persist()
    }

    func close(_ pane: AgentPaneView) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        pane.delegate = nil
        pane.shutdown()
        pane.removeFromSuperview()
        panes.remove(at: index)
        cards[ObjectIdentifier(pane)] = nil
        if zoomedPane === pane { zoomedPane = nil }
        if focusedPane === pane { focusedPane = nil }
        if mainPane === pane { mainPane = panes.isEmpty ? nil : panes[min(index, panes.count - 1)] }
        relayout()
        if let mainPane { focusTerminal(of: mainPane) }
        persist()
    }

    /// Traz o agente para o painel principal e põe o teclado no terminal dele (`select` do original).
    func select(_ pane: AgentPaneView) {
        guard panes.contains(where: { $0 === pane }) else { return }
        mainPane = pane
        if zoomedPane != nil { zoomedPane = pane }
        if zoomedPane != nil || layoutMode == "focus" { relayout() }
        focusTerminal(of: pane)
        persist()
    }

    func toggleZoom(of pane: AgentPaneView) {
        zoomedPane = zoomedPane === pane ? nil : pane
        if zoomedPane != nil { mainPane = pane }
        relayout()
        focusTerminal(of: pane)
    }

    func applyRename(_ pane: AgentPaneView, text: String) {
        guard let name = AgentNaming.sanitized(text) else { return }
        pane.rename(name)
        persist()
    }

    func setDefaultDirectory(_ directory: String) {
        guard PathTools.isDirectory(directory) else { return }
        defaultDirectory = directory
        updateButtonTitles()
        persist()
    }

    func setFontScale(_ scale: Double) {
        let range = ClarkConfig.fontScaleRange
        let clamped = (min(range.upperBound, max(range.lowerBound, scale)) * 100).rounded() / 100
        guard clamped != fontScale else { return }
        fontScale = clamped
        for pane in panes {
            pane.apply(terminalAppearance)
            pane.layoutChanged()
        }
        persist()
    }

    /// Agente sobre o qual os atalhos agem.
    var currentPane: AgentPaneView? {
        if let zoomedPane { return zoomedPane }
        return layoutMode == "focus" ? mainPane : (focusedPane ?? mainPane)
    }

    private func focusTerminal(of pane: AgentPaneView) {
        window?.makeFirstResponder(pane.terminal)
    }

    private func firstResponderChanged() {
        var view = window?.firstResponder as? NSView
        while let current = view, !(current is AgentPaneView) { view = current.superview }
        guard let pane = view as? AgentPaneView, pane !== focusedPane else { return }
        focusedPane = pane
        for other in panes { other.isFocused = other === pane }
        pane.focused()
        if layoutMode == "grid", zoomedPane == nil, mainPane !== pane {
            mainPane = pane
            refreshCards()
        }
    }

    // MARK: layout

    /// Refaz o layout depois de uma mudança na lista de agentes, no modo ou no zoom.
    func relayout() {
        if let main = mainPane, !panes.contains(where: { $0 === main }) { mainPane = nil }
        if mainPane == nil { mainPane = focusedPane ?? panes.first }
        sidebar.setCards(panes.compactMap { cards[ObjectIdentifier($0)] })
        layoutContent()
        let now = clock()
        for pane in panes {
            if !pane.isHidden { pane.layoutChanged() }
            pane.refreshPreview(now: now, force: true)
        }
        refreshCards()
        refreshChrome()
    }

    /// Fecha o layout pendente antes de abrir processos: o terminal já nasce com as colunas
    /// e linhas finais, e o agente não recebe um redimensionamento logo na largada.
    private func settleLayout() {
        for pane in panes { pane.needsLayout = true }
        root.layoutSubtreeIfNeeded()
    }

    /// Painéis que aparecem no layout atual.
    var visiblePanes: [AgentPaneView] {
        if let zoomedPane { return [zoomedPane] }
        if layoutMode == "focus" { return mainPane.map { [$0] } ?? [] }
        return panes
    }

    private func layoutContent() {
        let width = root.bounds.width, height = root.bounds.height
        topBar.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat(TopBarView.height))
        var top = CGFloat(TopBarView.height)
        warnings.isHidden = warnings.messages.isEmpty
        if !warnings.isHidden {
            warnings.frame = NSRect(x: 0, y: top, width: width, height: CGFloat(WarningBarView.height))
            top += CGFloat(WarningBarView.height)
        }
        let body = NSRect(x: 0, y: top, width: width, height: max(0, height - top))
        emptyView.frame = body
        emptyView.isHidden = !panes.isEmpty
        let showSidebar = layoutMode == "focus" && zoomedPane == nil && panes.count > 1
        let sidebarWidth = showSidebar ? CGFloat(SidebarView.width) : 0
        sidebar.isHidden = !showSidebar
        sidebar.frame = NSRect(x: body.maxX - sidebarWidth, y: body.minY, width: sidebarWidth, height: body.height)
        stage.isHidden = panes.isEmpty
        stage.frame = NSRect(x: 0, y: body.minY, width: max(0, body.width - sidebarWidth), height: body.height)

        let margin = Self.margin
        let area = NSRect(x: margin, y: margin, width: max(1, stage.bounds.width - 2 * margin),
                          height: max(1, stage.bounds.height - 2 * margin))
        let visible = visiblePanes
        if layoutMode == "grid" && zoomedPane == nil {
            // As colunas saem da proporção da janela inteira, como no original.
            let columns = GridLayout.columns(count: visible.count, width: Double(width), height: Double(height))
            let frames = GridLayout.frames(count: visible.count, columns: columns, width: Double(area.width),
                                           height: Double(area.height), spacing: Double(margin))
            for (pane, frame) in zip(visible, frames) {
                setFrame(pane, NSRect(x: area.minX + CGFloat(frame.x), y: area.minY + CGFloat(frame.y),
                                      width: CGFloat(frame.width), height: CGFloat(frame.height)))
            }
        } else {
            // Os painéis ocultos ficam do tamanho do principal: trocar de agente não muda as colunas do terminal.
            for pane in panes { setFrame(pane, area) }
        }
        for pane in panes {
            let hidden = !visible.contains { $0 === pane }
            if pane.isHidden != hidden { pane.isHidden = hidden }
        }
    }

    private func setFrame(_ view: NSView, _ frame: NSRect) {
        if view.frame != frame { view.frame = frame }
    }

    private func refreshCards() {
        let active = zoomedPane ?? mainPane
        for (index, pane) in panes.enumerated() {
            guard let card = cards[ObjectIdentifier(pane)] else { continue }
            card.index = index + 1
            card.isActive = pane === active
            card.snapshot = pane.snapshot
        }
    }

    private func refreshChrome() {
        let states = panes.map(\.state)
        topBar.stats = AgentStats(states: states)
        let done = states.filter { $0 == .done }.count
        let title = (done > 0 ? "(\(done)) " : "") + "CLARK — \(panes.count) agentes"
        if title != lastTitle {
            lastTitle = title
            window?.title = title
        }
        if done != lastBadge {
            lastBadge = done
            notifier.setBadge(done)
        }
    }

    private func updateButtonTitles() {
        topBar.folderButton.title = TopBarView.folderTitle(shortPath: PathTools.short(defaultDirectory, home: home))
        topBar.layoutButton.title = layoutMode == "focus" ? "FOCO" : "GRADE"
        topBar.needsLayout = true
        topBar.needsDisplay = true
    }

    /// Tique de 100 ms: estados, prévias dos cards e animações do que está visível.
    func tick() {
        let now = clock()
        for pane in panes { pane.tick(now: now) }
        if !sidebar.isHidden {
            for pane in panes {
                guard let card = cards[ObjectIdentifier(pane)] else { continue }
                if pane.refreshPreview(now: now) { card.snapshot = pane.snapshot }
                if StateLabel.isAnimated(pane.state) { card.time = now }
            }
        }
        let blink = Int(now * 2)
        if panes.isEmpty && blink != lastBlink { emptyView.time = now }
        lastBlink = blink
        refreshChrome()
    }

    // MARK: AgentPaneDelegate

    func paneIsWatched(_ pane: AgentPaneView) -> Bool {
        pane === focusedPane && !pane.isHidden && isWindowKey() && isAppActive()
    }

    func paneNeedsAttention(_ pane: AgentPaneView) {
        if !isAppActive() { notifier.agentDone(name: pane.name, sessionID: pane.sessionID) }
    }

    func paneDidChange(_ pane: AgentPaneView) {
        cards[ObjectIdentifier(pane)]?.snapshot = pane.snapshot
        refreshChrome()
    }

    func paneRequestsSelect(_ pane: AgentPaneView) { select(pane) }
    func paneRequestsZoom(_ pane: AgentPaneView) { toggleZoom(of: pane) }
    func paneRequestsClose(_ pane: AgentPaneView) { close(pane) }

    func paneRequestsRename(_ pane: AgentPaneView) {
        let field = NSTextField(string: pane.name)
        field.frame = NSRect(x: 10, y: 10, width: 240, height: 24)
        field.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        field.target = self
        field.action = #selector(commitRename(_:))
        // Clicar fora fecha sem renomear: só o Enter confirma.
        field.cell?.sendsActionOnEndEditing = false
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        content.view.addSubview(field)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = content
        renamePopover = popover
        renameTarget = pane
        popover.show(relativeTo: pane.header.bounds, of: pane.header, preferredEdge: .maxY)
        field.selectText(nil)
    }

    @objc private func commitRename(_ sender: NSTextField) {
        renamePopover?.close()
        renamePopover = nil
        guard let pane = renameTarget else { return }
        applyRename(pane, text: sender.stringValue)
        focusTerminal(of: pane)
    }

    // MARK: janela

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Fechar a janela é sair do app, e a saída pede confirmação com agentes vivos.
        NSApplication.shared.terminate(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusedPane?.focused()
    }

    // MARK: menu

    @objc func newAgent(_ sender: Any?) { addAgents(1) }

    @objc func closeAgent(_ sender: Any?) {
        if let pane = currentPane {
            close(pane)
        } else {
            window?.performClose(sender)
        }
    }

    /// Botões do diálogo "Fechar agentes?", na ordem, com os agentes que cada um fecha.
    func closeAllChoices() -> [(title: String, panes: [AgentPaneView])] {
        var choices: [(title: String, panes: [AgentPaneView])] = [("Cancelar", [])]
        let current = currentPane
        let others = panes.filter { $0 !== current }
        if !others.isEmpty && others.count < panes.count {
            choices.append(("Só os outros (\(others.count))", others))
        }
        choices.append(("Todos (\(panes.count))", panes))
        return choices
    }

    @objc func closeAllAgents(_ sender: Any?) {
        guard !panes.isEmpty else { return }
        let choices = closeAllChoices()
        let alert = NSAlert()
        alert.messageText = "Fechar agentes?"
        alert.informativeText = "As conversas continuam salvas no Claude (claude --resume), "
            + "mas os agentes fechados não voltam ao reabrir o CLARK."
        choices.forEach { alert.addButton(withTitle: $0.title) }
        let choice = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard choices.indices.contains(choice) else { return }
        choices[choice].panes.forEach(close)
    }

    @objc func chooseFolder(_ sender: Any?) {
        guard let window, launch != nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: defaultDirectory)
        panel.prompt = "Escolher"
        panel.message = "Pasta onde os novos agentes abrem"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let path = panel.url?.path { self?.setDefaultDirectory(path) }
        }
    }

    @objc func toggleLayout(_ sender: Any?) {
        layoutMode = layoutMode == "focus" ? "grid" : "focus"
        zoomedPane = nil
        updateButtonTitles()
        relayout()
        if let mainPane { focusTerminal(of: mainPane) }
        persist()
    }

    @objc func toggleZoom(_ sender: Any?) {
        if let pane = currentPane { toggleZoom(of: pane) }
    }

    @objc func nextAgent(_ sender: Any?) { step(by: 1) }
    @objc func previousAgent(_ sender: Any?) { step(by: -1) }

    private func step(by delta: Int) {
        guard panes.count > 1, let current = currentPane,
              let index = panes.firstIndex(where: { $0 === current }) else { return }
        select(panes[(index + delta + panes.count) % panes.count])
    }

    /// ⌘1 a ⌘9: o número vem na `tag` do item.
    @objc func selectAgentByNumber(_ sender: NSMenuItem) {
        guard (1...panes.count).contains(sender.tag) else { return }
        select(panes[sender.tag - 1])
    }

    @objc func renameAgent(_ sender: Any?) {
        if let pane = currentPane { paneRequestsRename(pane) }
    }

    @objc func increaseFont(_ sender: Any?) { setFontScale(fontScale + Self.fontStep) }
    @objc func decreaseFont(_ sender: Any?) { setFontScale(fontScale - Self.fontStep) }
    @objc func resetFont(_ sender: Any?) { setFontScale(1) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newAgent(_:)):
            return launch != nil && panes.count < ClarkConfig.maxAgents
        case #selector(chooseFolder(_:)):
            return launch != nil
        case #selector(closeAllAgents(_:)), #selector(toggleZoom(_:)), #selector(renameAgent(_:)):
            return !panes.isEmpty
        case #selector(nextAgent(_:)), #selector(previousAgent(_:)):
            return panes.count > 1
        case #selector(selectAgentByNumber(_:)):
            return menuItem.tag <= panes.count
        default:
            return true
        }
    }
}
```

**Arquivo:** `mac/Sources/Clark/MainMenu.swift`

```swift
import AppKit

/// Barra de menus. Os itens sem alvo sobem pela cadeia de resposta até o `MainWindowController`.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("CLARK", [
            item("Sobre o CLARK", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Ocultar o CLARK", #selector(NSApplication.hide(_:)), "h"),
            item("Ocultar os outros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item("Sair do CLARK", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Arquivo", [
            item("Novo agente", #selector(MainWindowController.newAgent(_:)), "n"),
            item("Trocar pasta…", #selector(MainWindowController.chooseFolder(_:)), "d"),
            .separator(),
            item("Fechar agente", #selector(MainWindowController.closeAgent(_:)), "w"),
            item("Fechar todos…", #selector(MainWindowController.closeAllAgents(_:)), ""),
        ]))
        main.addItem(submenu("Editar", [
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Colar", #selector(NSText.paste(_:)), "v"),
            item("Selecionar tudo", #selector(NSText.selectAll(_:)), "a"),
        ]))
        // O `=` invisível faz o ⌘+ funcionar sem o Shift nos teclados em que o + fica na tecla do =.
        let plainPlus = item("Aumentar a fonte", #selector(MainWindowController.increaseFont(_:)), "=")
        plainPlus.isHidden = true
        plainPlus.allowsKeyEquivalentWhenHidden = true
        main.addItem(submenu("Visualizar", [
            item("Alternar foco e grade", #selector(MainWindowController.toggleLayout(_:)), "l"),
            item("Zoom no agente", #selector(MainWindowController.toggleZoom(_:)), "\r"),
            .separator(),
            item("Aumentar a fonte", #selector(MainWindowController.increaseFont(_:)), "+"),
            plainPlus,
            item("Diminuir a fonte", #selector(MainWindowController.decreaseFont(_:)), "-"),
            item("Tamanho original", #selector(MainWindowController.resetFont(_:)), "0"),
        ]))
        var agents: [NSMenuItem] = [
            item("Agente anterior", #selector(MainWindowController.previousAgent(_:)), "{"),
            item("Próximo agente", #selector(MainWindowController.nextAgent(_:)), "}"),
            item("Renomear…", #selector(MainWindowController.renameAgent(_:)), ""),
            .separator(),
        ]
        for number in 1...9 {
            let entry = item("Agente \(number)", #selector(MainWindowController.selectAgentByNumber(_:)), "\(number)")
            entry.tag = number
            agents.append(entry)
        }
        main.addItem(submenu("Agentes", agents))
        let window = submenu("Janela", [
            item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom da janela", #selector(NSWindow.performZoom(_:)), ""),
        ])
        NSApplication.shared.windowsMenu = window.submenu
        main.addItem(window)
        return main
    }

    private static func item(_ title: String, _ action: Selector, _ key: String,
                             _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }
}
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'MainWindowControllerTests'`
Expected: PASS, `Executed 48 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 218 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkTests/ClarkFixture.swift`
- `mac/Tests/ClarkTests/MainWindowControllerTests.swift`
- `mac/Sources/Clark/Notifier.swift`
- `mac/Sources/Clark/AgentPaneView.swift`
- `mac/Sources/Clark/MainWindowController.swift`
- `mac/Sources/Clark/MainMenu.swift`

---

### Task 13: Ponto de entrada do app

O ponto de entrada. `--version` e `--help` respondem sem abrir janela. O `AppDelegate` carrega o config, captura o ambiente e sonda o rc do shell fora da thread principal, monta o `AgentLaunch`, pede confirmação para sair com agentes vivos e não deixa abrir um segundo CLARK.

**Files:**
- Create: `mac/Sources/Clark/AppDelegate.swift`
- Modify: `mac/Sources/Clark/main.swift` (o arquivo inteiro é trocado)
- Test: `mac/Tests/ClarkTests/ClarkMainTests.swift`

**Interfaces:**
- Consumes (assinaturas no bloco "Produces" da tarefa de origem):
  - Task 1: `ClarkVersion`, `PathTools`
  - Task 2: `Theme`
  - Task 5: `CompanyResolver`
  - Task 6: `ClaudeLocator`
  - Task 7: `ConfigStore`
  - Task 8: `CLIOptions`
  - Task 10: `ShellEnvironment`
  - Task 12: `AgentLaunch`, `MainMenu`, `MainWindowController`, `Notifier`
- Produces:

```swift
// mac/Sources/Clark/AppDelegate.swift
final class AppDelegate: NSObject, NSApplicationDelegate
    init(options: CLIOptions, home: String)
    func applicationDidFinishLaunching(_ notification: Notification)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    func applicationWillTerminate(_ notification: Notification)
enum ClarkMain
    static func immediateOutput(for options: CLIOptions) -> String?
    static func run()
```

- [ ] **Step 1: Escrever os testes que falham**

**Arquivo:** `mac/Tests/ClarkTests/ClarkMainTests.swift`

```swift
import ClarkCore
import XCTest
@testable import Clark

final class ClarkMainTests: XCTestCase {
    private func options(_ arguments: [String]) -> CLIOptions {
        CLIOptions.parse(arguments, launchDirectory: "/tmp", home: "/tmp")
    }

    func testVersionAndHelpAnswerWithoutOpeningTheWindow() {
        XCTAssertEqual(ClarkMain.immediateOutput(for: options(["--version"])), "clark \(ClarkVersion.current)")
        XCTAssertEqual(ClarkMain.immediateOutput(for: options(["--help"])), CLIOptions.usage)
        XCTAssertEqual(ClarkMain.immediateOutput(for: options(["-h"])), CLIOptions.usage)
    }

    func testEverythingElseOpensTheWindow() {
        XCTAssertNil(ClarkMain.immediateOutput(for: options([])))
        XCTAssertNil(ClarkMain.immediateOutput(for: options(["-n", "2", "--fresh"])))
        // Depois do `--` a opção é do claude, não do CLARK.
        XCTAssertNil(ClarkMain.immediateOutput(for: options(["--", "--version"])))
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./swiftpm.sh build --build-tests`
Expected: FAIL. O primeiro erro é `Tests/ClarkTests/ClarkMainTests.swift:11:24: error: cannot find 'ClarkMain' in scope`. Os testes citam tipos que ainda não existem.

- [ ] **Step 3: Escrever o código**

**Arquivo:** `mac/Sources/Clark/AppDelegate.swift`

```swift
import AppKit
import ClarkCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: CLIOptions
    private let home: String
    private let notifier = Notifier()
    private var controller: MainWindowController?

    init(options: CLIOptions, home: String) {
        self.options = options
        self.home = home
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateRunningInstance() {
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = MainMenu.build()
        notifier.start()

        let store = ConfigStore(directory: ConfigStore.defaultDirectory(home: home))
        let loaded = store.load()
        let controller = MainWindowController(config: loaded.config, store: store, home: home, notifier: notifier)
        self.controller = controller
        controller.window?.setFrameAutosaveName("ClarkMainWindow")
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        let processEnvironment = ProcessInfo.processInfo.environment
        let shell = ShellEnvironment.shellPath(processEnvironment: processEnvironment)
        let options = options, home = home
        let companies = store.companiesData()
        DispatchQueue.global(qos: .userInitiated).async {
            let capture = ShellEnvironment.capture(shell: shell, processEnvironment: processEnvironment)
            // O que o rc do shell devolve a um agente que nasceu sem a variável.
            let restored = ShellEnvironment.secretsRestoredByShell(shell: shell, environment: capture.variables)
            DispatchQueue.main.async {
                var warnings: [String] = []
                if let warning = loaded.warning { warnings.append(warning) }
                if !capture.captured { warnings.append("ambiente do shell nao lido: valendo o PATH padrao") }
                let palette = Theme.named(loaded.config.theme)
                let resolver = CompanyResolver(json: companies, palette: palette.agents, fallbackColor: palette.dim) {
                    PathTools.canonical($0, base: home, home: home)
                }
                if let warning = ShellEnvironment.restoredSecretsWarning(restored,
                                                                         globalAllow: resolver.globalEnvAllow) {
                    warnings.append(warning)
                }
                let launch = AgentLaunch(
                    baseEnvironment: capture.variables,
                    claudePath: ClaudeLocator.find(path: capture.variables["PATH"], home: home),
                    shell: shell, home: home, claudeArgs: options.claudeArgs, resolver: resolver)
                controller.start(launch: launch, options: options, startupWarnings: warnings)
            }
        }
    }

    /// Já existe um CLARK aberto: traz a janela dele para a frente em vez de abrir outro,
    /// porque dois apps gravariam o mesmo `config.json`.
    private func activateRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        guard let other = others.first else { return false }
        other.activate(options: [.activateAllWindows])
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, controller.liveAgentCount > 0 else { return .terminateNow }
        let count = controller.liveAgentCount
        let alert = NSAlert()
        alert.messageText = "Sair do CLARK?"
        alert.informativeText = (count == 1 ? "1 agente ainda está rodando." : "\(count) agentes ainda estão rodando.")
            + " As conversas ficam salvas e voltam ao reabrir."
        alert.addButton(withTitle: "Sair")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}

enum ClarkMain {
    /// Resposta das opções que imprimem e saem, sem abrir a janela.
    static func immediateOutput(for options: CLIOptions) -> String? {
        if options.showVersion { return "clark \(ClarkVersion.current)" }
        if options.showHelp { return CLIOptions.usage }
        return nil
    }

    static func run() {
        let home = NSHomeDirectory()
        var launchDirectory = FileManager.default.currentDirectoryPath
        // Aberto pelo Finder, o app nasce na raiz do disco.
        if launchDirectory == "/" { launchDirectory = home }
        let options = CLIOptions.parse(Array(CommandLine.arguments.dropFirst()),
                                       launchDirectory: launchDirectory, home: home)
        if let text = immediateOutput(for: options) {
            print(text)
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate(options: options, home: home)
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        // O `delegate` de NSApplication é fraco: o `withExtendedLifetime` segura o objeto até o fim.
        withExtendedLifetime(delegate) { application.run() }
    }
}
```

**Arquivo:** `mac/Sources/Clark/main.swift`

```swift
ClarkMain.run()
```

- [ ] **Step 4: Rodar os testes**

Run: `./swiftpm.sh test --filter 'ClarkMainTests'`
Expected: PASS, `Executed 2 tests, with 0 failures`.

Run: `./swiftpm.sh test`
Expected: PASS, `Executed 220 tests, with 0 failures`.

- [ ] **Step 5: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/ClarkTests/ClarkMainTests.swift`
- `mac/Sources/Clark/AppDelegate.swift`
- `mac/Sources/Clark/main.swift`

---

### Task 14: Clark.app, instalação e README

Monta o `Clark.app` (só o executável e o `Info.plist`, com assinatura ad hoc), instala em `~/Applications` com o atalho `clark` e documenta o uso. O `Tests/packaging.sh` confere a instalação numa HOME de mentira, sem tocar na de verdade.

**Atenção:** O `install.sh` recusa instalar com o CLARK aberto. Feche o app antes de rodar o `Tests/packaging.sh`.

**Files:**
- Create: `mac/Resources/Info.plist`
- Create: `mac/build.sh`
- Create: `mac/install.sh`
- Create: `mac/README.md`
- Test: `mac/Tests/packaging.sh`

**Interfaces:**
- Consumes: O pacote inteiro das Tasks 1 a 13; `Clark --version` e `Clark --help` da Task 13; `ClarkVersion.current` da Task 1, de onde o `build.sh` tira a versão do app.
- Produces: `mac/dist/Clark.app` (pelo `build.sh`), e a instalação em `$HOME/Applications/Clark.app` com o atalho `$HOME/.local/bin/clark` (pelo `install.sh`).

- [ ] **Step 1: Escrever o teste de empacotamento**

**Arquivo:** `mac/Tests/packaging.sh` (executável: `chmod +x`)

```bash
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
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `Tests/packaging.sh`
Expected: FAIL, com `Tests/packaging.sh: line 13: ./build.sh: No such file or directory`. O script chama o `build.sh`, que ainda não existe.

- [ ] **Step 3: Escrever o empacotamento e o README**

**Arquivo:** `mac/Resources/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt-BR</string>
    <key>CFBundleDisplayName</key>
    <string>CLARK</string>
    <key>CFBundleExecutable</key>
    <string>Clark</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.rafaelmgbh.clark</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CLARK</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <!-- As duas versões são preenchidas pelo build.sh a partir de `Clark --version`. -->
    <key>CFBundleShortVersionString</key>
    <string>0.0.0</string>
    <key>CFBundleVersion</key>
    <string>0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <!--
      O macOS cobra do CLARK as permissões que os programas dos agentes pedem.
      Sem o texto abaixo, o pedido do programa é negado sem nenhuma pergunta.
    -->
    <key>NSAppleEventsUsageDescription</key>
    <string>Um programa rodando num agente do CLARK quer controlar outro app.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Um programa rodando num agente do CLARK quer acessar a Mesa.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Um programa rodando num agente do CLARK quer acessar os Documentos.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Um programa rodando num agente do CLARK quer acessar os Downloads.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Um programa rodando num agente do CLARK quer acessar a rede local.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Um programa rodando num agente do CLARK quer usar o microfone.</string>
</dict>
</plist>
```

**Arquivo:** `mac/build.sh` (executável: `chmod +x`)

```bash
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
```

**Arquivo:** `mac/install.sh` (executável: `chmod +x`)

```bash
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
```

**Arquivo:** `mac/README.md`

````markdown
# CLARK para macOS

Porta nativa (Swift, AppKit e [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) do
[CLARK](https://github.com/GabrielBruno7/clark), de Gabriel Bruno: vários agentes do Claude Code
numa janela só, com cara de fliperama.

Esta versão acrescenta o que falta para quem atende mais de uma empresa na mesma máquina:
cada agente mostra a empresa da pasta em que está e só recebe as variáveis de ambiente que
essa empresa pode ver.

**Estado:** M1 (núcleo). A fila de trabalho e os dragões vêm depois; veja [Limitações](#limitações-do-m1).

## Requisitos

- macOS 14 ou mais novo.
- Swift 5.9 ou mais novo (Xcode ou Command Line Tools).
- `claude` instalado. Sem ele os agentes abrem o shell.

## Compilar e instalar

```bash
cd mac
./build.sh      # gera dist/Clark.app
./install.sh    # copia para ~/Applications e cria o atalho ~/.local/bin/clark
```

O `install.sh` não sobrescreve um `clark` que não seja o dele e não instala com o CLARK aberto.

Para remover, apague `~/Applications/Clark.app` e `~/.local/bin/clark`. As preferências ficam em
`~/.config/clark/`.

O app é assinado só localmente (assinatura ad hoc). Para o macOS, cada compilação é um app novo:
depois de recompilar, ele pode pedir de novo as permissões de notificação e de acesso a pastas.

## Uso

```
clark [PASTA] [-n N] [--fresh] [--version] [-- argumentos extras do claude]
```

| Opção | O que faz |
|-------|-----------|
| `PASTA` | Pasta dos agentes novos. Sem ela, vale a última usada. |
| `-n N` | Abre N agentes novos, de 0 a 16. |
| `--fresh` | Não restaura os agentes da última vez. |
| `--` | O que vier depois vai para o `claude` de todos os agentes. |

Ao reabrir, o CLARK restaura os agentes com as mesmas conversas (`claude --resume`). Se a pasta de
um agente não existe mais, ele abre na home, numa conversa nova.

Com o CLARK já aberto, `clark` só traz a janela para a frente: as opções são ignoradas.

### Atalhos

| Atalho | Ação |
|--------|------|
| ⌘N | Novo agente |
| ⌘D | Trocar a pasta dos agentes novos |
| ⌘W | Fechar o agente em foco |
| ⌘L | Alternar entre foco e grade |
| ⌘↩ | Zoom no agente |
| ⌘1 a ⌘9 | Ir para o agente pelo número |
| ⌘{ e ⌘} | Agente anterior e próximo |
| ⌘+, ⌘- e ⌘0 | Tamanho da fonte |

Dois cliques no cabeçalho do agente renomeiam. O botão `[ ]` do cabeçalho dá zoom e o `x` fecha.

### Estados

| Estado | Significado |
|--------|-------------|
| `WORKING` | O agente está escrevendo. |
| `DONE!` | Terminou um trabalho e espera você. O Dock mostra a contagem; com o CLARK em segundo plano, vem também uma notificação. |
| `IDLE` | Parado. |
| `GAME OVER` | O processo saiu. Enter abre de novo na mesma conversa. |

A faixa vermelha `SEM PERMISSOES` aparece no agente aberto com
`--dangerously-skip-permissions` ou `--permission-mode bypassPermissions`.

## Empresas

Sem configuração, a primeira pasta abaixo de `~/Projetos` é a empresa do agente:
um agente em `~/Projetos/acme/api` é da empresa `acme`. Fora dali, a empresa é `AVULSO`.

Para mudar isso, crie `~/.config/clark/companies.json`. O CLARK lê o arquivo ao abrir e nunca
escreve nele.

```json
{
  "roots": ["~/Projetos", "~/trabalho"],
  "env_allow": ["HOMEBREW_GITHUB_API_TOKEN"],
  "companies": [
    {
      "name": "Acme",
      "paths": ["~/Projetos/acme", "~/trabalho/acme-legado"],
      "color": "#5fb3b3",
      "env_allow": ["ACME_API_KEY"]
    }
  ]
}
```

- `roots`: pastas cujas subpastas viram empresas automaticamente.
- `companies`: empresas declaradas. Entre dois `paths` que servem, vale o mais comprido. Um `path`
  declarado vale mais que a detecção automática: se ele for uma das `roots` ou uma pasta acima
  dela, essa empresa engole todas as outras dali, e o CLARK avisa na barra.
- `color`: cor da empresa. Sem ela, a cor sai do nome, e duas empresas podem cair na mesma;
  nesse caso declare as duas com `color`.
- `env_allow`: veja a seção seguinte.

Agentes da mesma empresa ganham tons mais escuros da mesma cor.

## Ambiente dos agentes

Cada agente nasce com o ambiente do seu shell de login, menos:

1. as variáveis de sessão do Claude Code que abriu o CLARK, para o agente não se achar uma
   subsessão;
2. as variáveis com nome de segredo: `*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*PASSWD*`,
   `*CREDENTIAL*`, `AWS_*`, `PG*`, `*_DSN` e `DATABASE_URL`.

Uma variável da lista 2 só chega ao agente se estiver em `env_allow`: o do topo do arquivo vale
para todos os agentes, o da empresa só para os agentes dela. Uma empresa detectada pela pasta,
sem `paths` declarados, nunca libera variável.

O agente também recebe `CLARK_AGENT` e `CLARK_COMPANY`.

Isto é um filtro de ambiente, não um isolamento. O agente continua lendo qualquer arquivo que o
seu usuário lê, inclusive `.env` e `~/.aws`. O filtro evita o vazamento mais comum: a chave de
uma empresa exportada no shell e herdada pelo agente de outra.

O filtro vale para o ambiente com que o agente nasce. Cada comando que o agente roda abre um
shell novo, e esse shell relê os arquivos de inicialização dele: no zsh, todo `zsh -c` lê o
`~/.zshenv`. Uma variável da lista 2 exportada ali volta para os agentes de todas as empresas.
Na abertura, o CLARK testa isso com o seu shell e, quando alguma volta, avisa na barra com os
nomes: `rc do shell devolve variaveis filtradas: ...`. Para o filtro valer, exporte os segredos
no `~/.zshrc` ou no `~/.zprofile`, e não no `~/.zshenv`.

Sem o `claude` instalado, o painel abre o seu shell de login, que relê tudo. Ali o filtro não
vale, e o menu do agente diz isso em vez de listar as variáveis removidas.

A saída de um agente não consegue ler a sua área de transferência: o CLARK descarta a resposta
ao pedido de leitura (OSC 52). Copiar a partir do agente continua funcionando.

## Desenvolvimento

```bash
./swiftpm.sh test       # testes do Swift
Tests/packaging.sh      # install.sh e atalho, numa HOME temporária
```

O `swiftpm.sh` chama o `swift` com `--build-system native` quando o Metal Toolchain do Xcode
não está instalado. O aviso de que esse sistema de build está obsoleto é esperado.

O desenho do projeto está em [`docs/specs/2026-10-11-clark-mac-design.md`](docs/specs/2026-10-11-clark-mac-design.md).

## Limitações do M1

- Só o tema `dark`. Os temas `white` e `magick`, a tela de abertura, os dragões e o ícone do app
  ficam para o M3.
- A fila de trabalho (`/paralelo` e `/to-dev`) fica para o M2.
- Renomear um agente não muda o `CLARK_AGENT` do processo que já está rodando.
- Os avisos da interface saem sem acento, porque a fonte de pixels só tem ASCII.

## Licença

MIT, a mesma do projeto original. Veja [`LICENSE`](../LICENSE).
````

- [ ] **Step 4: Montar o app**

Run: `./build.sh`
Expected: termina com `pronto: <caminho do repo>/mac/dist/Clark.app (versão 0.1.0-mac.1)`. A linha `replacing existing signature` do `codesign` é esperada.

Run: `ls dist/Clark.app/Contents dist/Clark.app/Contents/MacOS && codesign -dv dist/Clark.app 2>&1 | grep -E 'Identifier|Signature'`
Expected: `_CodeSignature`, `Info.plist` e `MacOS`; dentro de `MacOS`, só `Clark`; `Identifier=io.github.rafaelmgbh.clark` e `Signature=adhoc`.

- [ ] **Step 5: Rodar o teste de empacotamento**

Run: `Tests/packaging.sh`
Expected: PASS, com esta saída:

```text
1. instalação limpa
2. reinstalar por cima do próprio atalho
3. um clark de outro programa fica como está
4. link simbólico não é seguido
5. atalho sem o app avisa e falha
6. HOME vazia é recusada
ok
```

- [ ] **Step 6: Rodar a suíte inteira**

Run: `./swiftpm.sh test`
Expected: `Executed 220 tests, with 0 failures`.

- [ ] **Step 7: Commit adiado**

Nenhum `git add` e nenhum `git commit` aqui: o repo só recebe commit depois do ok único da Task 16. Arquivos desta tarefa, para o stage por caminho:

- `mac/Tests/packaging.sh`
- `mac/Resources/Info.plist`
- `mac/build.sh`
- `mac/install.sh`
- `mac/README.md`

---

### Task 15: Roteiro manual do M1

Quem roda é o dono da máquina: o roteiro usa a tela, o teclado, a conta do `claude` e instala o app na HOME de verdade. Nada aqui é automatizado.

**Files:** nenhum.

**Interfaces:**
- Consumes: o `mac/dist/Clark.app` da Task 14.
- Produces: o registro, na Task 16, do que passou e do que não passou.

Preparação, de dentro de `mac/`:

```bash
./build.sh
./install.sh
```

Para os passos 5 e 6, crie um `~/.config/clark/companies.json` com duas empresas suas, cada uma com um `path`, e libere uma variável de teste só na primeira:

```json
{
  "companies": [
    { "name": "EmpresaA", "paths": ["~/Projetos/EmpresaA"], "env_allow": ["EMPRESAA_API_KEY"] },
    { "name": "EmpresaB", "paths": ["~/Projetos/EmpresaB"] }
  ]
}
```

- [ ] **Passo 1: abrir pelo Finder.** Dois cliques em `~/Applications/Clark.app`. Esperado: a janela abre com a barra superior e, sem agentes salvos, a tela `NENHUM AGENTE ONLINE` com `PRESS START - CMD+N` piscando. Nenhum aviso em vermelho além dos que fizerem sentido (por exemplo, `claude nao encontrado`).

- [ ] **Passo 2: abrir pelo atalho, com espaço no caminho.** Feche o app. Rode `mkdir -p "/tmp/clark teste" && clark "/tmp/clark teste" -n 2`. Esperado: dois agentes, `AGENT 1` e `AGENT 2`, na pasta com espaço, empresa `AVULSO`.

- [ ] **Passo 3: o `claude` de verdade.** Num agente, peça uma tarefa curta. Esperado: cores certas, nenhuma sobra de desenho. Redimensione a janela e alterne foco e grade com ⌘L: o `claude` se redesenha inteiro e o estado não vira `DONE!` só por causa do redimensionamento.

- [ ] **Passo 4: teclado ABNT.** Digite `ação, é, à, õ, ü, ç, 'aspas', "aspas"` no prompt do `claude`. Esperado: tudo sai como digitado, inclusive os acentos de tecla morta. Confira também Option+← e Option+→ pulando palavra.

- [ ] **Passo 5: duas empresas, dois ambientes.** Feche o app e abra pelo executável, com a variável de teste no ambiente:

```bash
EMPRESAA_API_KEY=teste-clark ~/Applications/Clark.app/Contents/MacOS/Clark --fresh
```

Com ⌘D escolha uma pasta da primeira empresa e crie um agente com ⌘N; faça o mesmo com uma pasta da segunda. Em cada um rode `! env | sort | grep -E '^(CLARK_|EMPRESAA_|PATH=)'`. Esperado: `CLARK_COMPANY` com o nome certo em cada um; `EMPRESAA_API_KEY` só no agente da primeira; o `PATH` do seu shell de login nos dois. Rode também `! env | cut -d= -f1 | grep -icE 'key|token|secret|password|passwd|credential|^aws_|^pg|_dsn$|^database_url$'`: dá `1` no agente da primeira empresa (a variável liberada) e `0` no da segunda, salvo o que você liberou no `env_allow` do topo do arquivo. Os dois cabeçalhos têm cores diferentes e mostram o nome da empresa.

Se a barra mostrar `rc do shell devolve variaveis filtradas: <nomes>`, essas variáveis aparecem nos dois agentes e entram na contagem: o seu `~/.zshenv` (ou o arquivo equivalente do seu shell) as exporta em todo comando. É o limite descrito no README; tire-as dali e abra de novo. Sem variável com nome de segredo no `~/.zshenv`, o aviso não aparece.

- [ ] **Passo 6: variáveis removidas.** Clique com o botão direito no cabeçalho de um agente. Esperado: o item `Variáveis removidas (N)` lista só nomes, nunca valores. Sem o `claude` instalado, o item é `Sem claude: o shell relê o rc e o filtro de variáveis não vale`.

- [ ] **Passo 7: estados e notificação.** Peça a um agente uma tarefa de uns dez segundos e passe para outro app. Esperado: o agente fica `WORKING` e depois `DONE!`; chega a notificação `CLARK · <agente>`; o Dock mostra a contagem. Clicar na notificação traz o CLARK com aquele agente em foco, e o `DONE!` volta a `IDLE`. Repita olhando para o agente: ele vai de `WORKING` a `IDLE`, sem notificação.

- [ ] **Passo 8: GAME OVER.** Digite `/exit` num agente. Esperado: a tela `GAME OVER`. Enter reabre o agente na mesma conversa, com o histórico.

- [ ] **Passo 9: restaurar.** ⌘Q com agentes vivos. Esperado: o diálogo `Sair do CLARK?`. Saia e abra de novo: os mesmos agentes, nomes, pastas e conversas. Depois `clark --fresh`: nenhum agente restaurado.

- [ ] **Passo 10: pasta que sumiu.** Crie um agente em `/tmp/clark teste`, saia, rode `rm -rf "/tmp/clark teste"` e abra de novo. Esperado: o agente abre na home, numa conversa nova, e a barra mostra `pasta de agente sumiu: abriu na home, conversa nova`.

- [ ] **Passo 11: atalhos.** ⌘N, ⌘W, ⌘↩, ⌘L, ⌘⇧[ e ⌘⇧], ⌘1 a ⌘9, ⌘D, ⌘+, ⌘− e ⌘0, ⌘C e ⌘V. Esperado: cada um faz o que a tabela do README diz, com o foco do teclado sempre no terminal do agente em foco.

- [ ] **Passo 12: renomear.** Dois cliques no cabeçalho. Esperado: o nome novo aparece no cabeçalho e no card, cortado em 20 caracteres, e sobrevive a fechar e abrir.

- [ ] **Passo 13: faixa de aviso.** `clark --fresh -n 1 -- --dangerously-skip-permissions`. Esperado: a faixa vermelha `SEM PERMISSOES` no agente.

- [ ] **Passo 14: links e área de transferência.** Peça ao `claude` para escrever o endereço `https://example.com` e clique nele (com ⌘, se o clique simples não abrir). Esperado: o navegador abre. Copie um texto qualquer em outro app e rode `! printf '\033]52;c;?\a' > /dev/tty`. Esperado: nada do que você copiou aparece digitado no prompt. Este passo só repete à mão o que `testOnlyWebLinksOpen` e `testClipboardReplyNeverReachesTheProcess` já fixam; se o `claude` não deixar o comando escrever no terminal, o passo não prova nada e pode ser pulado.

- [ ] **Passo 15: permissões dos arquivos.** `stat -f '%Lp %N' ~/.config/clark ~/.config/clark/config.json`. Esperado: `700` e `600`.

- [ ] **Passo 16: segunda chamada.** Com o app aberto, rode `clark /tmp`. Esperado: a janela vem para a frente; nenhum agente novo, a pasta padrão não muda.

- [ ] **Passo 17: anotar o resultado.** Liste os passos que falharam, com o que apareceu na tela. Passo que falha vira correção antes da Task 16.

---

### Task 16: Pedir o ok dos commits

**Files:** nenhum arquivo novo.

**Interfaces:**
- Consumes: a árvore `mac/` pronta, a suíte verde e o resultado do roteiro manual.
- Produces: dois commits locais, só depois do ok. O push é outro ok.

- [ ] **Passo 1: conferir a árvore.**

Run: `git status --short --untracked-files=all` (na raiz do repo)
Expected: só caminhos em `mac/`. Nenhum arquivo do original aparece modificado. `mac/.build/` e `mac/dist/` não aparecem, porque o `mac/.gitignore` os ignora.

- [ ] **Passo 2: rodar tudo uma última vez.**

Run: `cd mac && ./swiftpm.sh test && ./build.sh && Tests/packaging.sh`
Expected: `Executed 220 tests, with 0 failures`, a linha `pronto:` do build e `ok` no fim do `packaging.sh`.

- [ ] **Passo 3: procurar dado de cliente no que vai ser publicado.**

Run: `grep -rnIE "/Users/$(whoami)|[.]pem|amazonaw[s]|@gmai[l]" mac --exclude-dir=.build --exclude-dir=dist`
Expected: nenhuma linha. Os testes usam a home inventada `/Users/eu`, que não entra nessa busca. Confira também, de olho, que os nomes de empresa nos testes e exemplos são inventados (`A`, `B`, `acme`, `beta`, `EmpresaA`).

- [ ] **Passo 4: mostrar o resumo e pedir o ok.** Apresentar ao dono do repo o resultado dos passos 1 a 3, o resultado do roteiro manual e a lista abaixo, e esperar a resposta. Sem a resposta, nada é adicionado nem commitado.

Commit 1, a documentação:

```bash
git add mac/docs/specs/2026-10-11-clark-mac-design.md mac/docs/plans/2026-10-11-clark-mac-m1-nucleo.md
git commit -m "mac: spec e plano do M1 do CLARK nativo para macOS"
```

Commit 2, o código:

```bash
git add \
  mac/.gitignore \
  mac/swiftpm.sh \
  mac/Package.swift \
  mac/Tests/ClarkCoreTests/TemporaryDirectory.swift \
  mac/Tests/ClarkCoreTests/PathToolsTests.swift \
  mac/Sources/ClarkCore/Version.swift \
  mac/Sources/ClarkCore/PathTools.swift \
  mac/Tests/ClarkCoreTests/RGBThemeTests.swift \
  mac/Tests/ClarkCoreTests/PixelFontTests.swift \
  mac/Sources/ClarkCore/RGB.swift \
  mac/Sources/ClarkCore/Theme.swift \
  mac/Sources/ClarkCore/PixelFont.swift \
  mac/Tests/ClarkCoreTests/GridLayoutTests.swift \
  mac/Sources/ClarkCore/GridLayout.swift \
  mac/Tests/ClarkCoreTests/AgentStateMachineTests.swift \
  mac/Sources/ClarkCore/AgentStateMachine.swift \
  mac/Tests/ClarkCoreTests/EnvPolicyTests.swift \
  mac/Tests/ClarkCoreTests/CompanyResolverTests.swift \
  mac/Sources/ClarkCore/EnvPolicy.swift \
  mac/Sources/ClarkCore/CompanyResolver.swift \
  mac/Sources/ClarkCore/ShellEnvParser.swift \
  mac/Tests/ClarkCoreTests/SessionTests.swift \
  mac/Sources/ClarkCore/Session.swift \
  mac/Tests/ClarkCoreTests/ConfigTests.swift \
  mac/Sources/ClarkCore/Config.swift \
  mac/Tests/ClarkCoreTests/CLIOptionsTests.swift \
  mac/Sources/ClarkCore/CLIOptions.swift \
  mac/Sources/ClarkCore/AgentNaming.swift \
  mac/Package.resolved \
  mac/Sources/Clark/main.swift \
  mac/Tests/ClarkTests/TestSupport.swift \
  mac/Tests/ClarkTests/AgentTerminalViewTests.swift \
  mac/Sources/Clark/RGB+AppKit.swift \
  mac/Sources/Clark/AgentTerminalView.swift \
  mac/Tests/ClarkTests/ShellEnvironmentTests.swift \
  mac/Sources/Clark/ShellEnvironment.swift \
  mac/Tests/ClarkTests/RenderedImage.swift \
  mac/Tests/ClarkTests/PixelViewsTests.swift \
  mac/Sources/Clark/Pixel.swift \
  mac/Sources/Clark/PixelButton.swift \
  mac/Sources/Clark/AgentHeaderView.swift \
  mac/Sources/Clark/AgentCardView.swift \
  mac/Sources/Clark/TopBarView.swift \
  mac/Sources/Clark/SidebarView.swift \
  mac/Tests/ClarkTests/ClarkFixture.swift \
  mac/Tests/ClarkTests/MainWindowControllerTests.swift \
  mac/Sources/Clark/Notifier.swift \
  mac/Sources/Clark/AgentPaneView.swift \
  mac/Sources/Clark/MainWindowController.swift \
  mac/Sources/Clark/MainMenu.swift \
  mac/Tests/ClarkTests/ClarkMainTests.swift \
  mac/Sources/Clark/AppDelegate.swift \
  mac/Tests/packaging.sh \
  mac/Resources/Info.plist \
  mac/build.sh \
  mac/install.sh \
  mac/README.md
git commit -m "mac: núcleo do CLARK nativo para macOS (M1)" \
  -m "Agentes do Claude Code numa janela AppKit com SwiftTerm, empresa e ambiente filtrado por pasta, estados, notificação, foco, grade, zoom e restauração das conversas."
```

As duas mensagens saem como estão, sem `Co-Authored-By` e sem assinatura.

- [ ] **Passo 5: push, só com outro ok.** O repo é público: `git push origin HEAD` publica o código. Pedir a confirmação à parte, depois dos commits.

---

## Cobertura do spec

Onde cada parte do spec que pertence ao M1 é implementada e testada.

| Spec | Tarefa |
|---|---|
| Estrutura do repositório, SwiftPM, SwiftTerm fixado, `swiftpm.sh` | 1 e 9 |
| `Config`: validação, chaves desconhecidas, `0600`, troca atômica, arquivo inválido renomeado | 7 |
| `CompanyResolver`: `paths`, `roots`, `AVULSO`, cor estável, tons, aviso de `path` que cobre uma root | 5 |
| `EnvPolicy`: variáveis de sessão do pai, padrões de segredo, `env_allow`, `TERM`, `COLORTERM`, `CLARK_AGENT`, `CLARK_COMPANY` | 5 |
| Captura do ambiente do shell de login com marcador e limite de 5 s | 5 (leitura) e 10 (captura) |
| Sonda do que o rc do shell devolve e aviso na barra | 10 (sonda e aviso) e 13 (ligação na abertura) |
| `path` de empresa que ainda não existe | 1 (`PathTools.canonical`) e 12 |
| `AgentStateMachine`: a tabela de estados e os tempos | 4 |
| `SessionLocator` e `ClaudeCommand`: UUID, `--resume` e `--session-id`, flags de sessão e de permissão nos extras, `CLAUDE_CONFIG_DIR` | 6 |
| Procura do `claude` no `PATH` capturado e nas pastas de instalação | 6 |
| `GridLayout` | 3 |
| Fonte pixel e paleta `dark` | 2 |
| Terminal: saída, sino, entrada, leitura do buffer, links só `http` e `https`, OSC 52 | 9 |
| Cabeçalho, card com as duas linhas de prévia, barra superior, avisos, tela vazia, lista lateral | 8 (prévia) e 11 |
| Abrir, estado, notificação, fechar, GAME OVER, faixa `SEM PERMISSOES`, menu com as variáveis removidas | 12 |
| Foco, grade, zoom, renomear, tamanho da fonte, atalhos, salvar e restaurar, `--fresh`, pasta que sumiu | 12 |
| Linha de comando do `clark` | 8, 13 e 14 |
| Sair com agentes vivos, instância única | 13 |
| `build.sh`, `install.sh`, `Info.plist`, README, `Tests/packaging.sh` | 14 |
| Tabela de erros | 7 (config inválido), 10 (ambiente), 12 (demais) |
| O que depende de tela, teclado e conta | 15 |

Fica para os próximos marcos, cada um com o seu plano: `QueueStatus`, `QueueWatcher`, `QueuePanelView` e ⌘T (M2); `Sprites`, `SplashView`, `DragonLayer`, os temas `white` e `magick`, a troca de tema ao vivo e o ícone (M3). As chaves `dragons`, `queue_visible`, `skills_dir` e `theme` já são lidas e preservadas pelo `Config` desde a Task 7, sem efeito no M1 além do tema `dark`.
