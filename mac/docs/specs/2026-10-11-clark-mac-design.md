# CLARK para macOS — design

- **Data:** 2026-10-11
- **Status:** aprovado em 2026-10-11; atualizado no mesmo dia com o que a preparação do M1 mostrou
- **Base:** CLARK 0.1.0 de Gabriel Bruno, commit `4f30452` (`clark.py` na raiz deste repo)

## Objetivo

Rodar vários agentes Claude Code numa janela só, no macOS, com três ganhos sobre o original:

1. Agentes de empresas diferentes lado a lado, sem que variáveis de ambiente de uma cheguem aos agentes da outra.
2. A fila das skills `/paralelo` e `/to-dev` visível na janela, sem digitar `status`.
3. As correções de segurança levantadas na auditoria do original.

O visual retrô em pixel art é mantido por inteiro.

**Pronto quando:** abrir o `Clark.app`, criar agentes em pastas de empresas diferentes, ver cada um com a cor da sua empresa e o ambiente filtrado, acompanhar a fila ao lado e reabrir o app com as mesmas conversas.

## Decisões tomadas

| Decisão | Motivo |
|---|---|
| Reescrita nativa em Swift, não porta do GTK | O original é só Linux (GTK 3 + VTE). GTK no macOS tem atalhos em Ctrl e visual não nativo. |
| AppKit + SwiftTerm + CoreGraphics | Mesmo molde dos outros apps do autor do fork; pixel exato com antialias desligado; controle direto do foco entre vários terminais. SwiftUI foi descartado pelo foco de teclado frágil entre terminais. |
| Python original fica intacto na raiz; Swift em `mac/` | Sem conflito se o upstream for puxado; o original serve de referência para a porta. |
| Visual retrô completo | Splash, dragões, GAME OVER, três temas e ícone são a identidade do CLARK. |
| Lista TODO sai, painel da fila entra | As tarefas vêm das skills; uma segunda lista seria duplicação. |
| `auto_trust` não existe | Pulava a confirmação de pasta confiável e reescrevia `~/.claude.json` com permissão mais aberta. |
| Repo público, sem dado de cliente | Nomes de empresa, caminhos e hosts ficam em `~/.config/clark/`, fora do repo. |

## Fora do escopo

Linux, duas contas Claude por agente, lista TODO, status por hooks do Claude Code, ações que alteram a fila (integrar, cancelar), notarização e App Store, argumentos extras do `claude` persistidos em config.

## Estrutura do repositório

```
clark.py, install.sh, uninstall.sh, docs/   original, intocado
mac/
  Package.swift, Package.resolved
  swiftpm.sh            chama o swift com o sistema de build que funciona na máquina
  build.sh              compila, monta dist/Clark.app, assina ad hoc
  install.sh            copia para ~/Applications e cria ~/.local/bin/clark
  README.md
  Resources/Info.plist
  Sources/ClarkCore/    lógica pura, sem AppKit
  Sources/Clark/        interface AppKit
  Tests/ClarkCoreTests/
  Tests/ClarkTests/     interface, com processos de verdade e sem depender da tela
  Tests/packaging.sh    install.sh e atalho numa HOME temporária
  docs/specs/, docs/plans/
```

- SwiftPM, `swift-tools-version: 5.9`, macOS 14 ou mais novo.
- Dependência direta única: SwiftTerm (MIT), fixada pela revisão `464df5207fc2432e16c9a23abe538187196daf5f` (tag `v1.19.0`, 2026-08-18), com `Package.resolved` versionado. Essa versão expõe `dataReceived`, `rangeChanged` e `send` como `open`, que são os ganchos de que o app precisa. O `v1.99.0` saiu três dias antes deste spec, moveu esses ganchos para uma classe privada e fica para depois.
- O manifesto do SwiftTerm declara um plugin de build próprio (`SwiftTermBuildInfoPlugin`, que roda na compilação). Conferido na preparação do M1: o `Package.resolved` fixa o SwiftTerm e o `swift-argument-parser` 1.8.2 (Apple), usado só por um executável do SwiftTerm que o app não liga. `package-benchmark` e `swift-docc-plugin`, também declarados no manifesto, não são resolvidos. Qualquer pacote novo nesse arquivo é revisado antes de seguir.
- O SwiftTerm traz um shader Metal, e o build padrão do SwiftPM exige o Metal Toolchain do Xcode para compilá-lo. Sem o toolchain, o `swiftpm.sh` usa `--build-system native`, que só copia o arquivo. O app desenha por CoreGraphics e não liga o renderizador Metal; o bundle de recursos do SwiftTerm não vai para o `Clark.app`.
- Empacotamento: o `Clark.app` (identificador `io.github.rafaelmgbh.clark`) leva o executável, o `Info.plist` e o ícone, em `Contents/Resources/AppIcon.icns`, que o `build.sh` monta com `Clark --export-icon` e `iconutil`. A assinatura é ad hoc e sem hardened runtime. O macOS cobra do CLARK as permissões que os programas dos agentes pedem (pastas protegidas, rede local, microfone, automação): o `Info.plist` traz os textos desses pedidos, e o hardened runtime exigiria um entitlement para cada um. Sem identidade de assinatura estável, cada compilação pode pedir as permissões de novo.
- Licença MIT mantida. O README de `mac/` credita o original; a fonte pixel e os sprites derivam dele.

## Unidades

### ClarkCore (testável sem interface)

| Unidade | Faz | Depende de |
|---|---|---|
| `Config` | Lê e grava `config.json` com permissão `0600`; valida cada campo e cai no padrão quando inválido; preserva chaves desconhecidas. | Foundation |
| `CompanyResolver` | Caminho → empresa (nome, cor, `env_allow`). | `companies.json` |
| `EnvPolicy` | Ambiente base + empresa → ambiente do agente e lista dos nomes removidos. | `CompanyResolver` |
| `AgentStateMachine` | Estados BOOT, WORKING, IDLE, SHELL, DONE, EXITED a partir de eventos com relógio injetado. | nada |
| `SessionReport`, `SessionActivity` | O que o Claude Code diz da sessão de um processo, lido do arquivo de sessão dele: o que ela está fazendo (`busy`, `idle`, `shell`) e se o controle remoto está ligado. | sistema de arquivos |
| `SessionLocator` | Decide entre `--resume` e `--session-id`; valida UUID. | sistema de arquivos |
| `ClaudeCommand` | Monta o argv do agente; detecta flags de sessão e de permissão perigosa nos argumentos extras. | `SessionLocator` |
| `QueueStatus` | Decodifica o JSON de `fila.py status --json` e de `runstate.py find` e `report`. | Foundation |
| `PixelFont`, `Sprites`, `Themes` | Dados portados do original: glifos, quadros do dragão, três paletas. | nada |
| `GridLayout` | Linhas e colunas da grade para N painéis e o tamanho da janela. | nada |
| `ProjectCatalog`, `ProjectNaming` | Empresas e projetos que existem no disco, para o menu `PROJETO`; nome do projeto de uma pasta, com os apelidos. | `CompanyResolver`, sistema de arquivos |
| `SessionDigest` | Resumo da última conversa do Claude Code numa pasta, tirado do fim do arquivo da conversa. | sistema de arquivos |
| `UsageMeter` | Consumo do plano do Claude lido do arquivo de cache do AiUsageBar: janelas de 5 horas e de 7 dias, nível, idade da leitura e o texto da dica. | sistema de arquivos |
| `GitDiff`, `GitLocator` | Interpreta a saída do git em arquivos com estado e contagem de linhas, soma os totais e classifica as linhas de um diff; acha o `git` no `PATH` capturado. | sistema de arquivos |
| `ChangedFiles` | Linhas da coluna de arquivos alterados: os grupos por estado, na ordem, e o nome de cada arquivo separado da pasta. | nada |

### Clark (AppKit)

| Unidade | Faz |
|---|---|
| `ShellEnvironment` | Captura o ambiente do shell de login uma vez na abertura. |
| `AgentPaneView` | Cabeçalho desenhado + subclasse de `LocalProcessTerminalView`; traduz eventos do terminal para a máquina de estado. |
| `AgentCardView` | Card da lista lateral: nome, estado, projeto, empresa, caminho e as duas últimas linhas úteis do terminal. |
| `SessionDigestView` | Faixa `ULTIMA SESSAO` entre o cabeçalho e o terminal do agente que começa conversa nova num projeto. |
| `TopBarView`, `UsageMeterView` | Barra superior: logo, contagens por estado, medidor do consumo do plano e os botões `PROJETO`, layout e `+ AGENT`. |
| `GitRunner` | Roda o git na pasta de um agente, só para ler, com tempo e tamanho limitados. |
| `DiffMonitor` | Lê o diff da pasta de um agente fora da thread principal e guarda o último resultado. |
| `DiffBadge`, `DiffWindowController` | Resumo do diff no cabeçalho e no card; janela única com a lista de arquivos e o diff do escolhido. |
| `ChangedFilesView` | Coluna dos arquivos alterados ao lado do terminal do agente; o clique num arquivo abre a janela do diff nele. |
| `RemoteBadge` | Etiqueta `REMOTO` no cabeçalho e no card do agente que está com o controle remoto do Claude Code ligado. |
| `QueueWatcher` | Observa os arquivos de estado e chama os helpers das skills quando mudam. |
| `QueuePanelView` | Desenha a fila e o botão de abrir agente na worktree. |
| `SplashView`, `DragonLayer`, `PixelRenderer` | Splash animada, dragões por agente, desenho de texto e sprites em CoreGraphics. |
| `MainWindowController` | Barra superior, lista lateral à direita no modo foco, modos foco e grade, zoom, atalhos, salvar e restaurar. |

## Ciclo de vida do agente

**Abrir.** O argv é `claude`, mais os argumentos extras vindos de `clark -- <args>`, mais `--resume <id>` quando existe `<config do claude>/projects/*/<id>.jsonl` ou `--session-id <id>` quando não existe. Se os extras já trazem `-c`, `--continue`, `-r`, `--resume` ou `--session-id`, nenhuma flag de sessão é acrescentada. `CLAUDE_CONFIG_DIR` é respeitado. O diretório de trabalho inválido cai na home.

O `claude` é procurado no `PATH` capturado e depois em `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin` e `/usr/local/bin`. Sem `claude`, o painel abre o shell do usuário com o aviso em vermelho, como no original.

**Estado.** Porta exata do original, com os mesmos tempos:

| Evento | Efeito |
|---|---|
| Saída do terminal | Marca `last_change`, a não ser dentro de um silêncio (`mute`) ou a menos de 0,3 s de uma tecla do usuário. |
| Tique de 100 ms com `last_change` há menos de 1,0 s | WORKING. |
| Tique em WORKING sem saída recente | Se já houve entrada do usuário, o trabalho durou mais de 2,5 s e o painel não está sendo observado: DONE e notificação. Senão: IDLE. |
| Tique em BOOT após 2,0 s | IDLE. |
| Sino do terminal | DONE e notificação, salvo se observado. |
| Tecla do usuário | Marca entrada; DONE volta a IDLE. |
| Painel ganha foco | Silêncio de 0,3 s; DONE volta a IDLE. |
| Redimensionar / trocar layout | Silêncio de 0,5 s / 0,8 s. |
| Processo termina | EXITED, tela GAME OVER; Enter reabre na mesma conversa. |

"Observado" significa painel com foco e janela ativa.

**Comando em segundo plano.** É o que o CLARK acrescenta ao original. Com o turno encerrado e um comando rodando em segundo plano, a tela do Claude Code fica parada e a tabela acima diria IDLE. Parado (em IDLE, SHELL ou DONE), o agente lê uma vez por segundo `<config do claude>/sessions/<pid>.json`, o arquivo em que o Claude Code grava o `status` da sessão do processo: `busy`, `idle` ou `shell`. Com `shell`, onde a tabela diz IDLE o estado é SHELL: rótulo `SHELL` no ciano do terminal, a cor do `1 shell` do rodapé do Claude Code, contado em WORKING na barra superior. O DONE e a notificação não mudam, porque o turno acabou e o agente espera você; quem olha para ele vê o DONE dar lugar ao SHELL. Quando o comando termina, o `status` deixa de ser `shell` e o estado volta a IDLE, ou o Claude Code retoma o turno e a saída do terminal leva a WORKING.

O arquivo só vale se é um arquivo comum de até 64 KiB, nomeia o mesmo `pid` e foi gravado depois que o processo abriu; mais velho que isso, sobrou de outro processo que teve o mesmo número. Ele é um detalhe interno do Claude Code, não uma interface: sem o arquivo, ou com um `status` que o CLARK não conhece, o estado sai só da saída do terminal, como antes. O CLARK só lê esse arquivo, e não o procura para o agente que abriu o shell por falta do `claude`.

**Controle remoto.** O mesmo arquivo diz se o controle remoto do Claude Code (`/remote-control`) está ligado na sessão. O rodapé do Claude Code avisa com `/rc active`, mas some em terminal estreito, e num painel do CLARK o terminal quase sempre é estreito. Enquanto o controle remoto dura, o arquivo guarda o nome da sessão remota em `bridgeSessionId`; ao desligar, o Claude Code grava `null` no lugar. Texto não vazio nesse campo liga a etiqueta `REMOTO`; campo ausente, `null`, vazio ou de outro tipo desliga, assim como a falta do arquivo. O CLARK não guarda o nome nem monta o endereço da sessão: a etiqueta só avisa, sem clique.

A etiqueta é azul (`term[4]`, cor que nenhum estado usa), com as letras na cor do fundo. Ela não é estado: fica fora da máquina de estado e das contagens da barra superior. O controle remoto é relido uma vez por segundo em qualquer estado menos EXITED, inclusive em WORKING, quando o arquivo não serve para decidir o estado. Em EXITED a etiqueta some na hora e o arquivo não é mais lido, porque o processo morto à força deixa o arquivo para trás. No cabeçalho ela fica encostada na etiqueta de estado e escolhe o espaço antes da empresa, do resumo do diff e do caminho, sem tirar espaço do nome e do projeto: no aperto sai primeiro o resumo do diff, e sem espaço nem para ela o aviso fica só no card. No card ela fica na ponta direita da linha de detalhe, com o resumo do diff à esquerda.

**Notificação.** Só com a janela inativa: notificação do macOS com `CLARK · <agente>`, selo no Dock com a contagem de DONE e pedido de atenção do app.

**Fechar.** SIGHUP no processo. Ao sair do app com agentes vivos, um diálogo confirma; a lista de agentes é gravada e reaberta na próxima vez. `--fresh` ignora a lista. Agente salvo cuja pasta não existe mais abre na home, numa conversa nova, e a barra avisa: a conversa antiga pertence à pasta que sumiu.

## Isolamento por empresa

**Resolução.** Primeiro os `paths` explícitos de `companies.json`, vencendo o prefixo mais longo. Depois a detecção automática: a primeira pasta abaixo de uma das `roots` (padrão `~/Projetos`) vira a empresa, com cor escolhida na paleta do tema por hash estável do nome. Fora disso, `AVULSO`. O arquivo é opcional. Um `path` igual a uma das `roots`, ou acima dela, cobre as pastas de todas as empresas dali: a regra vale como foi escrita, e a barra superior avisa. Um `path` que ainda não existe é resolvido até a pasta mais funda que já existe, com links e caixa do disco; o trecho restante vale como foi escrito, para a regra casar com a pasta quando ela nascer.

```json
{
  "roots": ["~/Projetos"],
  "env_allow": [],
  "companies": [
    { "name": "EmpresaA", "paths": ["~/Projetos/EmpresaA"],
      "color": "#5fb3b3", "env_allow": ["EMPRESAA_API_KEY"] }
  ]
}
```

**Ambiente do agente**, nesta ordem:

1. Base: saída de `$SHELL -l -i -c` imprimindo um marcador e `env -0`, lida uma vez na abertura, com limite de 5 s. O marcador descarta o que o shell interativo imprimir antes. Se falhar, a base é o ambiente do próprio app com um `PATH` padrão, e a barra superior mostra o aviso.
2. Saem as nove variáveis de sessão do Claude pai listadas em `PARENT_SESSION_VARS` no original.
3. Saem os nomes que casam, sem diferenciar maiúsculas, com `*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*PASSWD*`, `*CREDENTIAL*`, `AWS_*`, `PG*`, `*_DSN`, `DATABASE_URL`, `*_PASS`, `*_PWD` e `*_PAT`. Os três últimos, aprovados em 2026-10-12, só valem no fim do nome e com o `_`: `SMTP_PASS`, `MYSQL_PWD` e `GITHUB_PAT` saem; `PWD`, `OLDPWD`, `PATH` e `SSH_ASKPASS` ficam.
4. Voltam os nomes em `env_allow` global e da empresa.
5. Entram `TERM=xterm-256color`, `COLORTERM=truecolor`, `CLARK_AGENT` e `CLARK_COMPANY`.

Quem autentica o `claude` por variável de ambiente precisa listá-la em `env_allow`. O menu do agente mostra os nomes removidos; valores nunca são exibidos nem gravados.

**O que o filtro não alcança.** O filtro vale para o ambiente com que o agente nasce. Um shell aberto pelo agente relê os arquivos de inicialização do shell: no zsh, todo `zsh -c` lê o `~/.zshenv`, e uma variável exportada ali volta para o agente de qualquer empresa. Na abertura, o app roda `$SHELL -c` a partir do ambiente já sem os nomes do passo 3 e avisa na barra os nomes que voltam, menos os do `env_allow` global. Sem `claude`, o painel é o shell de login, que relê tudo: ali o menu do agente diz que o filtro não vale, em vez de listar variáveis removidas.

**Cor.** Cabeçalho, card e dragão usam a cor da empresa. Agentes da mesma empresa escurecem em passos de 15% (0, 15, 30, 45 e recomeça). A paleta tem oito cores: duas empresas detectadas pela pasta podem cair na mesma, e `color` em `companies.json` desfaz o empate.

**Projeto do agente.** Todo agente tem uma pasta, e o `claude` roda dentro dela: é o que faz o `CLAUDE.md`, o `AGENTS.md` e o `.claude/` do projeto valerem. O agente aberto na home é o `GLOBAL`, fora de projeto. Nos outros, o nome do projeto é o apelido, quando existe, ou o nome arrumado (`portal_compras` vira `Portal Compras`) do repositório em que a pasta está, ou da própria pasta quando ela não está em repositório. O cabeçalho mostra `AGENT 2  PORTAL DE COMPRAS  ACME`: o projeto na cor da empresa e a empresa em cinza, omitida no `GLOBAL` e quando é igual ao projeto. Sem largura, o projeto e depois o nome passam para a fonte pequena antes de qualquer corte. O card tem 104 px de altura, com o projeto numa linha própria.

**Início.** O CLARK restaura os agentes salvos. Sem nenhum, e sem pedido na linha de comando, abre um agente no `GLOBAL`. O ⌘N e o `+ AGENT` abrem sempre no `GLOBAL`; o ⌘⇧N (`Novo agente nesta pasta`) repete a pasta do agente em foco. Não existe mais pasta padrão: o `cwd` do `config.json` é preservado no arquivo e ignorado.

**Menu de projetos.** O botão `PROJETO` da barra (⌘D) troca o seletor de pastas do original por um menu: `GLOBAL`, as empresas e `Outra pasta…` (o seletor do macOS). Cada empresa é um submenu com, de cima para baixo: os projetos apelidados; os projetos do primeiro nível e, com eles, um submenu para cada pasta que guarda projetos mais fundos; `Worktrees`, com as worktrees do git; `Outras pastas`, com as pastas do primeiro nível que não são projeto; e `Pasta da empresa`. A empresa de uma pasta só que é repositório, ou que não tem nada dentro, abre direto. Escolher um item abre um agente naquela pasta; com o limite de agentes atingido, nada abre e a barra avisa.

**Grupos.** O submenu de um grupo leva o nome da pasta que guarda os projetos (`Vendas`). Pasta que só organiza (`projects`, `projetos`, `repos`, `apps`, `packages`, `src`) não dá nome: o grupo fica com o nome da pasta acima dela. Quando dois grupos da mesma empresa ficariam com o mesmo nome, o título ganha as pastas de fora, da mais próxima para a mais distante, até eles se distinguirem (`Sistemas › Vendas`); a pasta que só organiza entra nessa hora (`Projects › Erp`). O projeto que guarda outros projetos não fica solto: é a primeira linha do submenu do grupo dele, separada das demais. A dica de cada grupo é o caminho da pasta. Os nomes vêm das pastas e só mudam por apelido: não há arquivo de mapeamento para manter.

**Worktrees.** A pasta cujo `.git` é um arquivo com `gitdir:` apontando para `<repositório>/.git/worktrees/<nome>` é uma worktree: um branch de um projeto que já está na lista. Ela sai do meio dos projetos e vai para o submenu `Worktrees`; com apelido, fica só com os apelidados. O `.git` em arquivo que aponta para outro lugar (um submódulo, por exemplo) segue como projeto. Do arquivo são lidos no máximo 4 KiB, e a busca não entra em worktree.

Projeto é a pasta com `.git` ou com instruções para agente (`CLAUDE.md`, `AGENTS.md`, `.claude`). A busca desce até quatro níveis abaixo da pasta da empresa, em largura, e para depois de ler 4.000 pastas; não entra em repositório, em pasta oculta nem em pasta de dependências ou de build (`node_modules`, `vendor`, `venv`, `dist`, `build`, `target`, `__pycache__`, `Pods`, `DerivedData`). A lista vem do disco a cada abertura do menu: as subpastas visíveis das `roots` e os `paths` declarados que existem, agrupados pelo nome que a resolução acima dá a cada um. Assim, tudo o que aparece numa empresa abre como agente dela; a pasta que resolveria para outra empresa (um `path` declarado dentro de outra, um link simbólico) fica de fora, e a mesma pasta alcançada por dois caminhos entra uma vez. O tipo de cada entrada sai da própria listagem do diretório, e só link simbólico passa por `realpath`: numa árvore de 62 projetos e 6.800 subpastas, o menu monta em 70 a 120 ms na compilação de depuração, conforme a carga da máquina.

**Apelidos.** `Apelidar projeto…`, no menu do cabeçalho e no menu `Agentes`, dá ao projeto um nome de até 40 caracteres. O apelido fica em `project_names` no `config.json`, pelo caminho da pasta que dá o nome ao projeto (o repositório), e vale para todo agente aberto nela ou numa subpasta. Texto vazio, ou igual ao nome arrumado da pasta, tira o apelido. O agente do `GLOBAL` não tem apelido.

**Última sessão.** O agente que começa conversa nova num projeto mostra, entre o cabeçalho e o terminal, a faixa `ULTIMA SESSAO`: a data (`HOJE 09:07`, `ONTEM 23:40`, `03/10 09:07`), o título da conversa, o último pedido, até duas linhas do começo da última resposta e, em amarelo, a linha que fala de pendência, que toma o lugar de uma linha da resposta. O texto sai do fim (256 KiB) do arquivo da conversa mais nova daquela pasta em `projects/` da configuração do Claude Code, tentando até cinco conversas, sem chamar modelo nenhum: custa uma leitura de arquivo, fora da thread principal. A faixa some na primeira tecla ou com um clique, e a resposta que chega depois disso é descartada. Não aparece no `GLOBAL`, em conversa retomada, sem `claude`, nem quando não há conversa anterior; as conversas dos agentes abertos não contam como a última. A pendência é o item de lista desmarcado (`- [ ]`) ou a linha com uma destas palavras inteiras: `pendente`, `pendência`, `falta`, `aguardando`, `próximo passo`, `ainda não`, `TODO` e as equivalentes em inglês. A frase que diz que não há pendência (`sem pendências`, `nada pendente`) não conta.

## Diff do agente

Não existe no original. Cada agente mostra o que mudou no repositório da sua pasta desde o último commit.

**Resumo.** O cabeçalho e o card trazem `+12 -3 4 ARQ`: linhas a mais em verde, linhas a menos em vermelho e a quantidade de arquivos. Repositório sem mudança, pasta fora de repositório e máquina sem `git` não mostram resumo. Quando falta largura, a empresa fica e o resumo sai.

**Janela.** O ⌘⇧D e o `Ver diff` do menu do cabeçalho abrem a janela do diff: à esquerda os arquivos (estado, caminho, contagem), à direita o diff unificado do arquivo escolhido, com uma cor por tipo de linha. A janela é uma só no app, e pedir o diff de outro agente troca o conteúdo dela. Com ela na frente, o ⌘W fecha a janela e não o agente. Fechada, ela larga o agente e não lê mais nada. Fechar o agente mostrado fecha a janela.

**Coluna de arquivos.** Clicar no resumo do cabeçalho, ou o `Arquivos alterados` do menu dele, abre uma coluna de 264 pontos à direita do terminal daquele agente. A faixa `SEM PERMISSOES` e a `ULTIMA SESSAO` ficam acima dela, com a largura toda. No topo vêm `ALTERADOS N`, o `R` que relê e o `X` que fecha; outro clique no resumo também fecha. A lista é plana, em grupos na ordem `MODIFICADOS`, `NOVOS`, `REMOVIDOS`, `NAO RASTREADOS`, cada um com a sua contagem. O arquivo traz a letra do estado, o nome, a pasta embaixo e `+N -N`, ou `-` quando não há contagem; arquivo da raiz do repositório não tem a linha da pasta. Clicar num arquivo abre a janela do diff daquele agente já nesse arquivo. Abrir a coluna relê o repositório, e depois ela acompanha as leituras do agente. Sem arquivo para listar, o corpo diz o motivo: `LENDO...`, `NADA MUDOU`, `FORA DE REPOSITORIO GIT`, `GIT NAO ENCONTRADO` ou `O GIT NAO RESPONDEU`. Lista cortada pelo limite de tamanho ganha `INCOMPLETA` ao lado do título. A coluna só abre se sobram 320 pontos para o terminal: em painel mais estreito o clique abre a janela do diff, e a coluna já aberta some enquanto o painel está estreito e volta quando ele alarga. O redesenho do terminal ao abrir e ao fechar a coluna não conta como trabalho do agente. Clicar na coluna não tira o foco do terminal. Cada agente tem a sua, e ela não é lembrada ao reabrir o app.

**O que entra.** O repositório inteiro, mesmo com o agente numa subpasta, contra o `HEAD`: mudanças preparadas e não preparadas, e os arquivos não rastreados que o `.gitignore` não cobre. Repositório sem commit é comparado com a árvore vazia. Renomeação aparece como um arquivo removido e outro novo. Submódulo fica de fora.

**Quando lê.** Na abertura do agente, quando ele sai de WORKING, quando o app volta para a frente e no ⌘R, que relê todos os agentes. Não há leitura periódica. As leituras da lista passam por uma fila única, uma por vez, fora da thread principal; pedidos feitos durante uma leitura viram uma leitura só.

**Limites.** O git tem 10 s para responder. A lista de arquivos vai até 4 MiB de saída e o diff de um arquivo até 1 MiB; a tela mostra até 20 mil linhas de 2 mil caracteres. O que passa disso é cortado, com aviso. Só os 200 primeiros arquivos não rastreados têm as linhas contadas, e só os de até 1 MiB.

## Consumo do plano

A barra superior mostra, entre as contagens e os botões, o consumo do plano do Claude: `5H` e `7D`, cada um com uma barra de dez blocos e o percentual. Qualquer consumo acende um bloco e a barra só enche em 100%. Os cortes de cor são os do AiUsageBar: verde até 79%, amarelo de 80% a 94%, vermelho de 95% em diante.

**Fonte.** O CLARK não consulta a rede nem lê o Keychain para isso. Ele lê `~/Library/Caches/io.github.rafaelmgbh.ai-usage-bar/claude-usage.json`, o arquivo que o [AiUsageBar](https://github.com/rafaelmgbh/ai-usage-bar) regrava a cada 5 minutos, com uma entrada por conta: `fetchedAt` e, em `fiveHour` e `sevenDay`, `percent` e `resetsAt` (segundos desde 1970). Vale a entrada `Claude Code-credentials`, a conta padrão do Claude Code; sem ela, a de `fetchedAt` mais recente. A leitura acontece no primeiro tique, depois a cada 60 s e a cada volta ao app; do arquivo são lidos no máximo 64 KiB, e o que não tem a forma esperada é ignorado. A alternativa, o próprio CLARK consultar a API de uso com o token do Claude Code, foi descartada: poria uma credencial e um acesso de rede num app que hoje não tem nenhum dos dois, para repetir o que o AiUsageBar já faz.

**Idade.** Leitura com mais de 15 minutos sai toda em cinza. Com mais de 24 horas o medidor some: é sobra de um AiUsageBar que não roda mais. A janela cujo `resetsAt` já passou mostra `0%` se a leitura é recente e `--` se é velha, porque o que foi gasto depois da renovação não foi lido. Sem o arquivo não há medidor.

**Espaço.** As contagens de agentes têm a preferência. O medidor entra inteiro quando cabe entre elas e os botões com 16 px de cada lado; apertado, perde as barras e fica com os números; sem espaço nem para eles, some. A dica do medidor traz, por janela, o percentual e em quanto tempo ela renova, e de quando é a leitura.

## Segurança

| Achado no original | Tratamento |
|---|---|
| `auto_trust` reescreve `~/.claude.json` e aceita o diálogo sozinho | Removido. O app nunca escreve em arquivo do Claude Code nem envia teclas ao terminal por conta própria. |
| Todo agente herda o ambiente inteiro | `EnvPolicy`, por agente. |
| `--dangerously-skip-permissions` vale para todos sem aviso | Aceito, mas cada agente ganha uma faixa vermelha fixa `SEM PERMISSOES`. Vale também para `--permission-mode bypassPermissions`. |
| `config.json` com permissão `0644` | Diretório `0700`, arquivos `0600`, gravação por arquivo temporário criado já com `0600` e troca atômica. |
| `session_id` do config vai para o argv sem validação | Só UUID válido é aceito; valor inválido gera UUID novo e a conversa não é retomada. |
| Links no terminal | Clique só abre `http` e `https`; outros esquemas são ignorados. |
| Atualização por `git pull` em cima do executável | O app instalado é uma cópia compilada; mudança do upstream só entra por diff revisado. |

**Achado da porta.** O SwiftTerm responde ao pedido de leitura da área de transferência (OSC 52) com o texto que o usuário copiou, e a classe-base não deixa desligar isso. O app descarta a resposta antes que ela chegue ao processo: um texto qualquer na saída de um agente não lê a área de transferência. A escrita (o `copiar` dos programas) continua valendo. O relato de título, outro vetor conhecido, o SwiftTerm já não responde.

**Diff.** O app roda o `git` sozinho em pastas de qualquer empresa, então o processo nasce com o ambiente já filtrado do próprio agente, sem as variáveis `GIT_*` herdadas, e só executa comandos de leitura (`rev-parse`, `diff`, `ls-files`, `hash-object`). O que o config do repositório poderia mandar executar fica desligado: monitor de arquivos (`core.fsmonitor`), ganchos (`core.hooksPath`), programa externo de diff (`--no-ext-diff`), conversor de texto (`--no-textconv`) e paginador. O git não pergunta nada (`GIT_TERMINAL_PROMPT=0`), não regrava o índice (`--no-optional-locks`) e não busca na rede (`protocol.allow=never`, `GIT_NO_LAZY_FETCH`). Os caminhos valem ao pé da letra (`--literal-pathspecs`) e vêm sempre depois de `--`. Link simbólico não rastreado não é seguido, nem na contagem nem no diff: o destino pode estar fora do repositório. Fica um limite conhecido: os filtros `clean` e `process` declarados no config do repositório continuam rodando quando o git compara um arquivo que os usa, porque sem eles o diff de arquivo em Git LFS sairia errado.

## Painel da fila

Somente leitura. Ocupa o lugar do painel TODO e alterna com ⌘T.

**Repo de cada agente.** Na abertura do agente, `git rev-parse --show-toplevel` e `--git-common-dir` resolvem a raiz e o diretório git compartilhado, de modo que um agente dentro de uma worktree aponta para o repo principal. Agente fora de repo não entra no painel.

**Fontes.** A cada 2 s o `QueueWatcher` consulta só a data de modificação dos arquivos; os helpers rodam quando ela muda, e a cada 30 s enquanto houver grupo ativo.

| Skill | Arquivo observado | Comando | Campos usados |
|---|---|---|---|
| `/paralelo` | `<git-common-dir>/paralelo/estado.json` | `fila.py --repo <raiz> status --json` | `rodando`, `max_workers`, `trava_teste`, `tarefas[].{id,titulo,grupo,status,espera}`, `grupos.<gN>.{status,worktree,teste.{exit,fresco}}` |
| `/to-dev` | `<raiz>/docs/dev-runs/*/run-state.json` | `runstate.py --repo <raiz> find`, depois `report --run <R>` do run com `aberto: true` de maior nome (o nome começa pela data) | `concluidas`, `interrompidas`, `pendentes`, cada linha com `name`, `status`, `pr` |

Os helpers ficam em `~/.claude/skills/<skill>/bin/`, caminho alterável por `skills_dir` no `config.json`. Rodam com o `python3` do `PATH` capturado e limite de 10 s. Só os subcomandos `status`, `find` e `report` são chamados, fixos no código.

**Exibição.** Uma seção por repo, com a cor da empresa. Em `/paralelo`: workers rodando sobre o máximo, trava de teste livre ou ocupada, e uma linha por correção com grupo, status e teste (`exit` 0 verde, 1 vermelho, 3 sem suíte; `fresco` falso acrescenta "velho"). Grupo com worktree existente ganha o botão `ABRIR`, que cria um agente com o diretório de trabalho na worktree. Em `/to-dev`: concluídas sobre o total e uma linha por tarefa com status e PR.

Rótulos e status usam a fonte pixel; títulos de tarefa usam a fonte monoespaçada do sistema, porque a fonte pixel não tem acentos.

**Falha.** Helper ausente, limite estourado, saída diferente de zero ou JSON inválido mostram `FILA INDISPONIVEL` na seção, com o motivo ao passar o mouse. A próxima mudança do arquivo tenta de novo.

## Visual

Porta fiel das funções do original, desenhadas em CoreGraphics com antialias desligado e escala inteira:

- Fonte pixel (`_FONT_SRC`, `norm`, `text_w`, `fit_text`, `draw_text` com sombra).
- Dragão: `mascot_rows` com passo, piscar, dormir, braços para cima e fogo; `sprite_pal`.
- Cabeçalho do agente com mascote animado, nome, caminho e a etiqueta de estado piscando em DONE.
- `Splash` com a checagem da versão do `claude`.
- `DragonSky`: um dragão por agente andando pela janela, ligável e desligável.
- Tela vazia com o mascote dormindo e `PRESS START`.
- Três temas (`dark`, `white`, `magick`) com as paletas do original, inclusive as 16 cores do terminal, trocados ao vivo.
- Ícone gerado por `make_icon_surface`; o `build.sh` usa `--export-icon` e `iconutil` para o `.icns`. Adiantado para o M1, a pedido: o desenho segue a grade dos ícones do macOS (placa de 824 num quadro de 1024, raio de 22,5%), porque fora dela o sistema encolhe o ícone dentro de uma moldura cinza. Abaixo de 128 px o desenho grande é reduzido.

O tique de animação é de 100 ms, como no original, e só redesenha o que está visível.

## Atalhos

| macOS | Ação | Original |
|---|---|---|
| ⌘N | novo agente no `GLOBAL` | Ctrl+Shift+N |
| ⌘⇧N | novo agente na pasta do agente em foco | não tem |
| ⌘W | fechar agente | Ctrl+Shift+W |
| ⌘↩ | zoom no agente | Ctrl+Shift+Enter |
| ⌘L | alternar foco e grade | Ctrl+Shift+L |
| ⌘⇧[ e ⌘⇧] | agente anterior e próximo | Ctrl+Shift+← e → |
| ⌘1 a ⌘9 | pular para o agente N | Alt+1 a 9 |
| ⌘D | abrir agente num projeto (menu `PROJETO`) | Ctrl+Shift+D |
| ⌘⇧D | ver o diff do agente em foco | não tem |
| ⌘R | reler o diff de todos os agentes | não tem |
| ⌘T | mostrar ou esconder a fila | Ctrl+Shift+T |
| ⌘C e ⌘V | copiar e colar | Ctrl+Shift+C e V |
| ⌘+, ⌘− e ⌘0 | tamanho da fonte | Ctrl+Shift++, − e 0 |
| duplo clique no cabeçalho | renomear (20 caracteres) | igual |
| Enter em GAME OVER | reabrir o agente | igual |

Linha de comando, pelo atalho `clark`: `clark [PASTA] [-n N] [--no-splash] [--fresh] [--version] [-- argumentos do claude]`. `PASTA` abre um agente nela (com `-n`, N agentes) e não vira padrão; se não existe, os agentes pedidos abrem no `GLOBAL`, com um aviso. `-n` sem `PASTA` abre no `GLOBAL`. `--no-splash` é aceito desde o M1 e passa a ter efeito no M3. `--export-icon ARQUIVO` e `--icon-size N` (16 a 1024, padrão 256) gravam o ícone em PNG e saem sem abrir a janela; servem ao `build.sh` e ficam fora do texto de ajuda. Com o CLARK já aberto, o atalho só traz a janela para a frente e as opções são ignoradas.

## Configuração

Tudo em `~/.config/clark/`.

`config.json`: `theme` (`dark`, `white`, `magick`), `layout` (`focus`, `grid`), `font` (padrão `Menlo 12`), `font_scale` (0,6 a 2,5), `dragons`, `queue_visible`, `cwd` (do original; preservado e ignorado), `skills_dir`, `main_agent`, `project_names` (caminho → apelido do projeto) e `agents`, lista de `{name, cwd, session_id, color}`, em que `color` é o tom do agente dentro da empresa (0 a 3).

`companies.json`: descrito em Isolamento por empresa.

## Erros

| Situação | Comportamento |
|---|---|
| `config.json` ou `companies.json` ilegível ou inválido | Padrões no lugar; aviso na barra superior. Antes da primeira gravação, o arquivo ruim é renomeado para `<nome>.invalido-<data>`; `companies.json` nunca é gravado pelo app. |
| Captura do ambiente do shell falha | Ambiente do app com `PATH` padrão; aviso na barra. |
| O rc do shell devolve uma variável filtrada | A barra avisa com os nomes, nunca com valores; os agentes abrem normalmente. |
| `claude` não encontrado | Barra superior e painel avisam (a splash também, a partir do M3); o painel abre o shell. |
| Falha ao iniciar o processo | Mensagem no painel; estado EXITED. |
| Falha ao gravar config | O estado em memória segue valendo; a barra avisa, uma vez, que os agentes não voltam ao reabrir. |
| Pasta de um agente salvo não existe mais | O agente abre na home, numa conversa nova; aviso na barra. |
| Fila indisponível | Ver Painel da fila. |
| `git` não encontrado | Nenhum agente mostra resumo de diff; a janela do diff e a coluna de arquivos dizem que não acharam o git. |
| A pasta do agente não é repositório | Sem resumo; a janela do diff e a coluna de arquivos dizem isso. |
| O git falha ou não responde em 10 s | Sem resumo; a janela do diff e a coluna de arquivos avisam. A próxima leitura tenta de novo. |

## Testes

`swift test` em `ClarkCoreTests`:

- `EnvPolicy`: cada padrão de segredo remove; as formas curtas de senha só contam como sufixo; `env_allow` global e da empresa devolvem; variável liberada para uma empresa não aparece em outra; as variáveis de sessão do pai saem sempre.
- `CompanyResolver`: prefixo mais longo vence; detecção automática sob `roots`; `AVULSO`; cor estável para o mesmo nome; `path` que cobre uma root gera aviso.
- `AgentStateMachine`: cada linha da tabela de estado, com relógio injetado, e o SHELL em cada ponto em que ela diz IDLE.
- `SessionReport`: os três valores de `status`; valor desconhecido não dá atividade; `pid` de outro processo, arquivo mais velho que o processo, pasta ou pipe no lugar do arquivo e arquivo grande demais não dão resposta; o controle remoto liga com o nome da sessão remota, desliga com `null`, texto vazio ou outro tipo, e não depende do `status`.
- `SessionLocator` e `ClaudeCommand`: UUID inválido é trocado; `--resume` contra `--session-id`; flags de sessão nos extras suprimem as do app; detecção das flags de permissão.
- `Config`: campo inválido cai no padrão; chave desconhecida sobrevive; arquivo gravado sai `0600`.
- `QueueStatus`: amostras sintéticas no formato real dos dois helpers, sem dado de cliente; JSON truncado dá erro tratado.
- `GridLayout`: mesmas contas do original para 1 a 16 painéis.
- `GitDiff`: saída do git com caminhos estranhos (espaço, tabulação, `:` e `*`), binário sem contagem, totais e rótulos do resumo, tipo de cada linha do diff.
- `ChangedFiles`: grupos na ordem, grupo vazio de fora, contagem de cada grupo, nome e pasta de cada caminho.

`swift test` em `ClarkTests` cobre a interface sem depender da tela: o terminal com processo de verdade (saída, sino, entrada, leitura do buffer, links, pedido de leitura da área de transferência), a captura do ambiente do shell e a sonda do que o rc devolve, o desenho das views de pixel e o `MainWindowController` (abrir, fechar, restaurar, foco, grade, zoom, renomear, menus e avisos). O diff roda contra o git de verdade em repositórios temporários: a lista e o diff de cada tipo de arquivo, o repositório com config hostil (nada do que ele aponta é executado), as variáveis `GIT_*` herdadas, o git que trava, as releituras do `DiffMonitor` e a janela do diff em cada estado. A coluna de arquivos alterados é conferida pelo desenho (título, grupos, linhas, aviso no lugar da lista, só o trecho pedido) e dentro do painel: abre e fecha pelo resumo, pelo `X` e pelo menu, relê ao abrir, toma a largura do terminal sem passar por cima das faixas, some em painel estreito e leva o clique num arquivo até a janela do diff.

`Tests/packaging.sh` cobre o `install.sh` e o atalho `clark` numa HOME temporária.

O que depende da tela, do teclado e do `claude` de verdade fica no roteiro manual de cada marco.

## Marcos

Cada marco termina num app usável e tem seu próprio plano de implementação.

**M1 — Núcleo.** Começa por uma verificação curta do SwiftTerm na revisão fixada: saída recebida (`dataReceived`), sino (`bell`), entrada do usuário (`send`), leitura das últimas linhas do buffer, teclas mortas do teclado ABNT, o `claude` desenhando certo em cores e redimensionamento, e o conteúdo do `Package.resolved`. Se a leitura do buffer não existir, os cards ficam sem as duas linhas de prévia e isso é registrado aqui.

Resultado em 2026-10-11: `dataReceived`, `bell`, `send` e a leitura do buffer existem na revisão fixada e ficam cobertos por testes com processo de verdade; os cards têm as duas linhas de prévia. O `Package.resolved` está descrito em Estrutura do repositório. As teclas mortas do ABNT e o `claude` de verdade desenhando ficam no roteiro manual do M1, porque dependem de teclado e de conta.

Pronto quando:
- `mac/build.sh` gera o `Clark.app`, que abre pelo Finder e pelo `clark`.
- Dois agentes em empresas diferentes: `env` em cada um mostra o `PATH` do shell, nenhuma variável dos padrões de segredo e a variável liberada só na empresa certa.
- Os estados mudam como na tabela, a notificação chega com a janela inativa e Enter em GAME OVER retoma a conversa.
- Fechar e abrir o app devolve os mesmos agentes e conversas.
- Foco, grade, zoom, renomear e todos os atalhos funcionam.
- Tema `dark`, fonte pixel no cabeçalho, nos cards e na barra, sem animação de mascote.
- `swift test` e `Tests/packaging.sh` verdes.

**M2 — Fila.** Pronto quando o painel mostra as duas fontes num repo com fila aberta, `ABRIR` cria o agente na worktree, a fila indisponível aparece tratada e os testes de `QueueStatus` passam.

**M3 — Retrô completo.** Pronto quando a splash, o mascote animado nos cabeçalhos e cards, os dragões, a tela vazia, o GAME OVER e os três temas com troca ao vivo estão no app (o ícone gerado já entrou no M1), comparados lado a lado com as capturas em `docs/` do original.
