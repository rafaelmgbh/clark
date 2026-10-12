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
| `AgentStateMachine` | Estados BOOT, WORKING, IDLE, DONE, EXITED a partir de eventos com relógio injetado. | nada |
| `SessionLocator` | Decide entre `--resume` e `--session-id`; valida UUID. | sistema de arquivos |
| `ClaudeCommand` | Monta o argv do agente; detecta flags de sessão e de permissão perigosa nos argumentos extras. | `SessionLocator` |
| `QueueStatus` | Decodifica o JSON de `fila.py status --json` e de `runstate.py find` e `report`. | Foundation |
| `PixelFont`, `Sprites`, `Themes` | Dados portados do original: glifos, quadros do dragão, três paletas. | nada |
| `GridLayout` | Linhas e colunas da grade para N painéis e o tamanho da janela. | nada |

### Clark (AppKit)

| Unidade | Faz |
|---|---|
| `ShellEnvironment` | Captura o ambiente do shell de login uma vez na abertura. |
| `AgentPaneView` | Cabeçalho desenhado + subclasse de `LocalProcessTerminalView`; traduz eventos do terminal para a máquina de estado. |
| `AgentCardView` | Card da lista lateral: nome, estado, empresa, caminho e as duas últimas linhas úteis do terminal. |
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
3. Saem os nomes que casam, sem diferenciar maiúsculas, com `*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*PASSWD*`, `*CREDENTIAL*`, `AWS_*`, `PG*`, `*_DSN` e `DATABASE_URL`.
4. Voltam os nomes em `env_allow` global e da empresa.
5. Entram `TERM=xterm-256color`, `COLORTERM=truecolor`, `CLARK_AGENT` e `CLARK_COMPANY`.

Quem autentica o `claude` por variável de ambiente precisa listá-la em `env_allow`. O menu do agente mostra os nomes removidos; valores nunca são exibidos nem gravados.

**O que o filtro não alcança.** O filtro vale para o ambiente com que o agente nasce. Um shell aberto pelo agente relê os arquivos de inicialização do shell: no zsh, todo `zsh -c` lê o `~/.zshenv`, e uma variável exportada ali volta para o agente de qualquer empresa. Na abertura, o app roda `$SHELL -c` a partir do ambiente já sem os nomes do passo 3 e avisa na barra os nomes que voltam, menos os do `env_allow` global. Sem `claude`, o painel é o shell de login, que relê tudo: ali o menu do agente diz que o filtro não vale, em vez de listar variáveis removidas.

**Cor.** Cabeçalho, card e dragão usam a cor da empresa. Agentes da mesma empresa escurecem em passos de 15% (0, 15, 30, 45 e recomeça). A paleta tem oito cores: duas empresas detectadas pela pasta podem cair na mesma, e `color` em `companies.json` desfaz o empate.

**Menu de projetos.** O botão `PROJETO` da barra (⌘D) troca o seletor de pastas do original por um menu: `GLOBAL` (a home, empresa `AVULSO`), as empresas com seus projetos e `Outra pasta…` (o seletor do macOS). Escolher um item abre um agente naquela pasta e ela passa a ser a do ⌘N; com o limite de agentes atingido, só a pasta muda. A lista vem do disco a cada abertura do menu: as subpastas visíveis das `roots` e os `paths` declarados que existem, agrupados pelo nome que a resolução acima dá a cada um. Assim, tudo o que aparece numa empresa abre como agente dela; a pasta que resolveria para outra empresa (um `path` declarado dentro de outra, um link simbólico) fica de fora. Há um nível de aninhamento: a pasta sem `.git` que guarda pelo menos um repositório vira submenu.

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
| ⌘N | novo agente | Ctrl+Shift+N |
| ⌘W | fechar agente | Ctrl+Shift+W |
| ⌘↩ | zoom no agente | Ctrl+Shift+Enter |
| ⌘L | alternar foco e grade | Ctrl+Shift+L |
| ⌘⇧[ e ⌘⇧] | agente anterior e próximo | Ctrl+Shift+← e → |
| ⌘1 a ⌘9 | pular para o agente N | Alt+1 a 9 |
| ⌘D | abrir agente num projeto (menu `PROJETO`) | Ctrl+Shift+D |
| ⌘T | mostrar ou esconder a fila | Ctrl+Shift+T |
| ⌘C e ⌘V | copiar e colar | Ctrl+Shift+C e V |
| ⌘+, ⌘− e ⌘0 | tamanho da fonte | Ctrl+Shift++, − e 0 |
| duplo clique no cabeçalho | renomear (20 caracteres) | igual |
| Enter em GAME OVER | reabrir o agente | igual |

Linha de comando, pelo atalho `clark`: `clark [PASTA] [-n N] [--no-splash] [--fresh] [--version] [-- argumentos do claude]`. `--no-splash` é aceito desde o M1 e passa a ter efeito no M3. `--export-icon ARQUIVO` e `--icon-size N` (16 a 1024, padrão 256) gravam o ícone em PNG e saem sem abrir a janela; servem ao `build.sh` e ficam fora do texto de ajuda. Com o CLARK já aberto, o atalho só traz a janela para a frente e as opções são ignoradas.

## Configuração

Tudo em `~/.config/clark/`.

`config.json`: `theme` (`dark`, `white`, `magick`), `layout` (`focus`, `grid`), `font` (padrão `Menlo 12`), `font_scale` (0,6 a 2,5), `dragons`, `queue_visible`, `cwd`, `skills_dir`, `main_agent` e `agents`, lista de `{name, cwd, session_id, color}`, em que `color` é o tom do agente dentro da empresa (0 a 3).

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

## Testes

`swift test` em `ClarkCoreTests`:

- `EnvPolicy`: cada padrão de segredo remove; `env_allow` global e da empresa devolvem; variável liberada para uma empresa não aparece em outra; as variáveis de sessão do pai saem sempre.
- `CompanyResolver`: prefixo mais longo vence; detecção automática sob `roots`; `AVULSO`; cor estável para o mesmo nome; `path` que cobre uma root gera aviso.
- `AgentStateMachine`: cada linha da tabela de estado, com relógio injetado.
- `SessionLocator` e `ClaudeCommand`: UUID inválido é trocado; `--resume` contra `--session-id`; flags de sessão nos extras suprimem as do app; detecção das flags de permissão.
- `Config`: campo inválido cai no padrão; chave desconhecida sobrevive; arquivo gravado sai `0600`.
- `QueueStatus`: amostras sintéticas no formato real dos dois helpers, sem dado de cliente; JSON truncado dá erro tratado.
- `GridLayout`: mesmas contas do original para 1 a 16 painéis.

`swift test` em `ClarkTests` cobre a interface sem depender da tela: o terminal com processo de verdade (saída, sino, entrada, leitura do buffer, links, pedido de leitura da área de transferência), a captura do ambiente do shell e a sonda do que o rc devolve, o desenho das views de pixel e o `MainWindowController` (abrir, fechar, restaurar, foco, grade, zoom, renomear, menus e avisos).

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
