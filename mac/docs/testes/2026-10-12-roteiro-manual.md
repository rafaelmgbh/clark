# Roteiro manual: diff, projetos, última sessão e o que ficou do M1

Escrito em 2026-10-12 para a próxima sessão de teste. Quem roda é o dono da máquina: o roteiro
usa a tela, o teclado e a conta do `claude`. Nada aqui é automatizado.

## O que já está conferido e o que não está

| Parte | Automático | Na tela |
|-------|------------|---------|
| Diff do agente (`dcea13e`) | 324 testes verdes, 8 mutações mortas, imagens renderizadas nos testes | nunca |
| Menu de projetos (`443277d`) | coberto pelos testes | nunca; nem o clique no botão `PROJETO` |
| Início no `GLOBAL`, menu por empresa, projeto no cabeçalho, apelidos e última sessão (commit seguinte ao `ab24420`) | 391 testes verdes, 7 mutações mortas, imagens renderizadas nos testes | nunca |
| Menu com grupos por pasta e worktrees à parte, medidor de consumo na barra e estado `SHELL` (commit seguinte ao `721b889`) | 451 testes verdes, 30 mutações mortas (13 do menu e do medidor, 17 do `SHELL`), menu conferido contra as pastas reais, arquivo de sessão conferido num agente real | nunca |
| Ícone do dragão (`7fa1ec6`) | coberto pelos testes | nunca |
| Núcleo do M1 (`80cb7e8`) | coberto pelos testes | em uso, mas o roteiro da Task 15 do plano nunca foi rodado inteiro |
| `Tests/packaging.sh` depois do diff | não rodou: exige o CLARK fechado | não se aplica |

Os commits estão na `origin/main` (`dcea13e`). O app instalado em `~/Applications/Clark.app` já é
a compilação com o diff: em 2026-10-11 o executável instalado era idêntico ao do `dist/`.

## Preparação

1. Confirme a versão instalada: o menu `Agentes` tem os itens `Ver diff`, `Atualizar diff` e
   `Apelidar projeto…`. Se faltar algum, saia do CLARK (⌘Q) e rode, de dentro de `mac/`:

   ```bash
   ./build.sh && ./install.sh
   ```

2. Crie o repositório de teste. Os números do roteiro dependem dele:

   ```bash
   rm -rf /tmp/clark-diff /tmp/clark-limpo /tmp/clark-vazio
   mkdir -p /tmp/clark-diff/sub /tmp/clark-limpo /tmp/clark-vazio
   cd /tmp/clark-diff && git init -q
   printf 'um\ndois\ntres\n' > a.txt
   printf 'fica\n' > b.txt
   printf 'some\n' > c.txt
   git add -A && git commit -qm base
   printf 'um\nDOIS\ntres\nquatro\n' > a.txt
   rm c.txt
   printf 'novo\nnovo2\n' > sub/novo.txt
   printf 'preparado\n' > d.txt && git add d.txt
   cd /tmp/clark-limpo && git init -q && printf 'x\n' > x.txt && git add -A && git commit -qm base
   ```

   O `/tmp/clark-diff` fica com quatro arquivos mudados:

   | Arquivo | Estado | Linhas |
   |---------|--------|--------|
   | `a.txt` | `M` | +2 -1 |
   | `c.txt` | `D` | +0 -1 |
   | `d.txt` | `A` (preparado com `git add`) | +1 -0 |
   | `sub/novo.txt` | `?` (não rastreado) | +2 -0 |

   O total é `+5 -2 4 ARQ`. O `/tmp/clark-limpo` é um repositório sem mudança e o `/tmp/clark-vazio`
   é uma pasta fora de repositório.

3. No CLARK, abra um agente em cada pasta: ⌘D, `Outra pasta…`, e no seletor do macOS ⌘⇧G para
   digitar o caminho. Abra também um quarto agente em `/tmp/clark-diff/sub`.

## A. Diff

- [ ] **A1. Resumo no cabeçalho e no card.** O agente de `/tmp/clark-diff` mostra `+5 -2 4 ARQ` no
  cabeçalho e no card da barra lateral: `+5` em verde, `-2` em vermelho, `4 ARQ` em cinza. Os
  agentes de `/tmp/clark-limpo` e de `/tmp/clark-vazio` não mostram resumo.

- [ ] **A2. Subpasta.** O agente de `/tmp/clark-diff/sub` mostra o mesmo `+5 -2 4 ARQ`: o diff é do
  repositório inteiro.

- [ ] **A3. Abrir a janela.** Com o agente de `/tmp/clark-diff` em foco, ⌘⇧D. Esperado: uma janela
  com o título `Diff — <nome do agente>`; abaixo do título, a raiz do repositório e `+5 -2 4 ARQ`;
  à esquerda os quatro arquivos, cada um com a letra do estado (`M` amarelo, `D` vermelho, `A` e
  `?` verdes), o caminho e a contagem à direita; o primeiro arquivo já vem escolhido e o diff dele
  aparece à direita. A janela principal continua atrás, com o agente rodando.

- [ ] **A4. Diff de cada arquivo.** Clique nos quatro arquivos, um por vez. Esperado: o diff
  unificado do arquivo, com linhas a mais em verde e linhas a menos em vermelho. Em `a.txt`
  aparecem `-dois`, `+DOIS` e `+quatro`. Em `c.txt` só a remoção de `some`. Em `sub/novo.txt` as
  duas linhas novas. Depois de um clique na lista, as setas ↑ e ↓ também trocam de arquivo.

- [ ] **A5. Menu do cabeçalho.** Feche a janela do diff. Botão direito no cabeçalho do agente,
  `Ver diff`. Esperado: a mesma janela. O item `Ver diff` do menu `Agentes` faz o mesmo.

- [ ] **A6. Janela única.** Com a janela do diff aberta, ponha em foco o agente de
  `/tmp/clark-limpo` e aperte ⌘⇧D. Esperado: a mesma janela troca de título e mostra
  `Nada mudou desde o último commit.`; não abre uma segunda janela. Com o agente de
  `/tmp/clark-vazio`: `Esta pasta não é um repositório git.`

- [ ] **A7. ⌘W na janela do diff.** Com a janela do diff na frente, ⌘W. Esperado: fecha só a janela
  do diff; nenhum agente fecha. Em seguida, sem clicar em nada, digite no teclado: o texto cai no
  terminal do agente em foco.

- [ ] **A8. Fechar o agente mostrado.** Abra o diff do agente de `/tmp/clark-vazio`, clique na
  janela principal e feche esse agente com ⌘W. Esperado: o agente fecha e a janela do diff fecha
  junto.

- [ ] **A9. Releitura ao voltar para o app.** No Terminal, rode `echo mais >> /tmp/clark-diff/b.txt`
  e volte para o CLARK. Esperado: em um ou dois segundos o resumo passa a `+6 -2 5 ARQ`, sem
  apertar nada. Com a janela do diff aberta, `b.txt` entra na lista.

- [ ] **A10. ⌘R, e nada de leitura periódica.** No Terminal, rode
  `(sleep 20; echo outra >> /tmp/clark-diff/b.txt) &` e volte para o CLARK antes dos 20 segundos.
  Espere uns 40 segundos sem sair do CLARK e sem pedir nada aos agentes de `/tmp/clark-diff`.
  Esperado: o resumo continua `+6 -2 5 ARQ`. Aperte ⌘R: passa a `+7 -2 5 ARQ`.

- [ ] **A11. Releitura quando o agente para.** No agente de `/tmp/clark-limpo`, peça ao `claude`
  para criar um arquivo `teste.txt` com três linhas. Esperado: quando o estado sai de `WORKING`,
  o resumo aparece sozinho, sem ⌘R e sem trocar de app: `+3 -0 1 ARQ`, se o `claude` não criar
  mais nada na pasta.

- [ ] **A12. Redimensionar.** Alargue e estreite a janela do diff. Esperado: a lista de arquivos
  mantém a largura e só o diff cresce ou encolhe. Um caminho que não cabe é cortado no começo, e
  o nome do arquivo continua visível.

- [ ] **A13. Posição lembrada.** Mova e redimensione a janela do diff, feche e abra de novo com
  ⌘⇧D. Esperado: mesma posição e mesmo tamanho. Repita depois de ⌘Q e de abrir o CLARK de novo.

- [ ] **A14. Cabeçalho apertado.** Abra agentes até a grade (⌘L) ficar com cabeçalhos estreitos, ou
  estreite a janela principal. Esperado: quando falta espaço, o nome da empresa fica e o resumo do
  diff some; nada se sobrepõe.

- [ ] **A15. Diff comprido e arquivo binário.** No Terminal:

  ```bash
  seq 1 5000 > /tmp/clark-diff/longo.txt
  head -c 4096 /dev/zero > /tmp/clark-diff/bin.dat
  ```

  Volte para o CLARK. Esperado: `longo.txt` entra com `+5K -0` e o diff dele rola até o fim sem
  travar; `bin.dat` entra com `—` no lugar da contagem. O resumo passa a `+5K -2 7 ARQ`.

- [ ] **A16. Repositório de verdade.** Abra o diff de um agente num projeto seu com mudanças.
  Esperado: os números batem com `git diff --shortstat HEAD` somado aos arquivos novos de
  `git status`; a janela abre sem demora perceptível; `git status` no Terminal não mostra nada que
  o CLARK tenha criado ou preparado.

## B. Projetos, apelidos, última sessão e ícone

- [ ] **B1. Começa no `GLOBAL`.** Feche todos os agentes, saia (⌘Q) e abra o CLARK. Esperado: um
  agente na home, com `GLOBAL` ao lado do nome, sem empresa. `! pwd` mostra a home.

- [ ] **B2. Clique no botão `PROJETO`.** Clique no botão da barra, sem usar o ⌘D. Esperado: o menu
  abre logo abaixo dele, sem demora, com `GLOBAL`, as empresas e `Outra pasta…`. O título do botão
  é sempre `PROJETO`.

- [ ] **B3. Submenu da empresa.** Abra uma empresa com vários projetos. Esperado, de cima para
  baixo: os apelidados; os projetos do primeiro nível e um submenu para cada pasta que guarda
  projetos mais fundos, com o nome dela (`Vendas ▸`); `Worktrees ▸`; `Outras pastas ▸`;
  `Pasta da empresa`. Nada de `node_modules` nem de pasta oculta. Passar o mouse num item mostra
  o caminho.

- [ ] **B3a. Grupo de uma pasta.** Abra o submenu de uma pasta que guarda vários projetos.
  Esperado: os projetos dela, pelo nome da pasta de cada um. Se a própria pasta é um projeto, ela
  é a primeira linha do submenu, separada das outras, e escolhê-la abre o agente nela. Uma pasta
  `projects` no meio do caminho não aparece no nome do submenu.

- [ ] **B3b. Worktrees.** Numa empresa com worktrees do git (`git worktree list` num dos
  repositórios mostra mais de uma linha), abra `Worktrees ▸`. Esperado: só elas, e nenhuma no meio
  dos projetos. Escolher uma abre o agente na pasta da worktree; `! git branch --show-current`
  mostra o branch dela.

- [ ] **B4. Abrir num projeto.** Escolha um projeto. Esperado: abre um agente novo naquela pasta, com
  o projeto grande na cor da empresa e a empresa em cinza: `AGENT 2  MEU PROJETO  EMPRESA`. O card da
  lista lateral traz o projeto numa linha própria. Rode `! pwd` para conferir a pasta.

- [ ] **B5. O `claude` enxerga o projeto.** No agente aberto no B4, rode `/memory`. Esperado: o
  `CLAUDE.md` (ou `AGENTS.md`) listado é o daquele projeto.

- [ ] **B6. ⌘N e ⌘⇧N.** Com o agente do B4 em foco, ⌘N abre um agente no `GLOBAL`, e ⌘⇧N abre outro
  na pasta do agente em foco. O botão direito no cabeçalho tem o mesmo `Novo agente nesta pasta`.

- [ ] **B7. Apelidar.** Botão direito no cabeçalho do agente do B4, `Apelidar projeto…`, digite um
  nome e Enter. Esperado: o cabeçalho e o card de todos os agentes daquele projeto trocam na hora; no
  menu `PROJETO`, o apelido aparece no topo do submenu da empresa. Abra um agente numa subpasta do
  mesmo repositório (`Outra pasta…`): ele mostra o mesmo apelido.

- [ ] **B8. O apelido fica.** ⌘Q e abra de novo. Esperado: o apelido continua no cabeçalho e no menu.
  Apelidar de novo com o campo vazio volta ao nome da pasta. No agente do `GLOBAL`, o item
  `Apelidar projeto…` fica apagado.

- [ ] **B9. Última sessão.** Escolha no menu um projeto em que você já conversou com o `claude`.
  Esperado: entre o cabeçalho e o terminal aparece a faixa `ULTIMA SESSAO` com a data (`HOJE`,
  `ONTEM` ou o dia), o título, o último pedido e o começo da última resposta; se a resposta falava do
  que ficou por fazer, essa linha vem em amarelo. O texto bate com a conversa de verdade.

- [ ] **B10. A faixa sai do caminho.** No agente do B9, digite qualquer tecla. Esperado: a faixa
  some e o terminal ocupa o espaço. Abra outro agente no mesmo projeto e clique na faixa: some também.

- [ ] **B11. Quando a faixa não aparece.** No `GLOBAL`; numa pasta em que o `claude` nunca rodou; e
  num agente restaurado ao reabrir o CLARK. Com dois agentes no mesmo projeto, a faixa do segundo não
  mostra a conversa que o primeiro está tendo agora.

- [ ] **B12. Painel estreito.** Passe para a grade (⌘L) com seis ou mais agentes de projetos de nome
  comprido. Esperado: o projeto e depois o nome passam para a letra pequena; `AGENT 1` e `AGENT 2`
  continuam distinguíveis e a etiqueta de estado não some.

- [ ] **B13. Linha de comando.** Com o CLARK fechado: `clark ~/alguma/pasta` restaura os agentes e
  abre mais um naquela pasta; um ⌘N depois disso abre no `GLOBAL`. `clark /nao/existe` abre o agente
  no `GLOBAL` e a barra de avisos diz que a pasta não foi encontrada.

- [ ] **B14. Ícone.** O dragão aparece no Dock, no ⌘Tab e no Finder (`~/Applications`), nítido nos
  tamanhos pequeno e grande.

## C. O que ficou do M1

O roteiro completo é a Task 15 de [`docs/plans/2026-10-11-clark-mac-m1-nucleo.md`](../plans/2026-10-11-clark-mac-m1-nucleo.md),
com 17 passos. Nenhum deles foi registrado como rodado. Os que mais pesam, por ordem:

- [ ] **C1. Restaurar (passo 9).** ⌘Q com agentes vivos mostra `Sair do CLARK?`. Ao abrir de novo
  voltam os mesmos agentes, nomes, pastas e conversas. `clark --fresh` não restaura nenhum.

- [ ] **C2. Notificação (passo 7).** Tarefa de uns dez segundos num agente, com outro app na
  frente. Esperado: `WORKING`, depois `DONE!`, a notificação `CLARK · <agente>` e a contagem no
  Dock. Clicar na notificação traz o CLARK com aquele agente em foco.

- [ ] **C3. Teclado ABNT (passo 4).** `ação, é, à, õ, ü, ç, 'aspas', "aspas"` no prompt do
  `claude` saem como digitados. Option+← e Option+→ pulam palavra.

- [ ] **C4. Segunda chamada (passo 16).** Com o app aberto, `clark /tmp` só traz a janela para a
  frente: nenhum agente novo.

- [ ] **C5. Duas empresas, dois ambientes (passos 5 e 6).** Siga o passo 5 do plano: a variável
  liberada só aparece no agente da empresa que a liberou, e o menu `Variáveis removidas (N)` lista
  só nomes.

- [ ] **C6. Os outros passos da Task 15,** na ordem do plano.

## D. Consumo do plano, aviso de fim de turno e estado SHELL

Estes passos pedem o [AiUsageBar](https://github.com/rafaelmgbh/ai-usage-bar) rodando no mesmo Mac.

- [ ] **D1. Medidor na barra.** Com a janela larga, olhe a barra superior. Esperado: entre as
  contagens e o botão `PROJETO`, `5H` e `7D`, cada um com uma barra de dez blocos e o percentual.
  Os números batem com o que o AiUsageBar mostra, com no máximo um minuto de atraso.

- [ ] **D2. Dica.** Pare o mouse sobre o medidor. Esperado: o percentual de cada janela com
  `renova em …` e a linha `Lido há N min pelo AiUsageBar`.

- [ ] **D3. Barra apertada.** Estreite a janela aos poucos. Esperado: primeiro o medidor perde as
  barras e fica só com os números; depois some. `AGENTS`, `WORKING`, `DONE` e `IDLE` só começam a
  sumir depois dele.

- [ ] **D4. Leitura velha.** Saia do AiUsageBar e espere 16 minutos (ou volte no dia seguinte).
  Esperado: o medidor inteiro em cinza, e a dica com `(desatualizado)`. Reabra o AiUsageBar: em até
  um minuto, ou ao voltar para o CLARK, as cores voltam.

- [ ] **D5. Sem o arquivo.** Com o AiUsageBar fechado, renomeie
  `~/Library/Caches/io.github.rafaelmgbh.ai-usage-bar/claude-usage.json` e volte para o CLARK.
  Esperado: o medidor some e nada mais muda. Desfaça a troca de nome.

- [ ] **D6. Um aviso só.** Com o AiUsageBar recompilado depois desta mudança, deixe um agente do
  CLARK terminar um turno de mais de 10 s com outro app na frente. Esperado: chega o aviso do
  CLARK e nenhum do AiUsageBar. Uma sessão do `claude` no iTerm continua avisando pelo AiUsageBar.

- [ ] **D7. Comando em segundo plano.** Num agente, peça: `rode sleep 90 em segundo plano e me
  devolva o controle`. Esperado: quando o turno acaba e o rodapé do Claude Code mostra `1 shell`,
  o cabeçalho e o card do agente mostram `SHELL...` em ciano, e não `IDLE`; a barra superior conta
  esse agente em `WORKING`. Quando o `sleep` termina, o Claude retoma o turno (`WORKING`) e o
  agente acaba em `IDLE` ou `DONE!`, sem `SHELL`.

- [ ] **D8. SHELL e o aviso.** Repita o D7 com outro app na frente. Esperado: o aviso de fim de
  turno chega como sempre e o card fica em `DONE!`; ao voltar para o agente, ele passa a `SHELL...`
  enquanto o `sleep` roda.

## E. Depois do teste

- [ ] **E1. `Tests/packaging.sh`.** Com o CLARK fechado (⌘Q), de dentro de `mac/`:
  `Tests/packaging.sh`. O script recusa rodar com o app aberto.

- [ ] **E2. Limpeza.** `rm -rf /tmp/clark-diff /tmp/clark-limpo /tmp/clark-vazio` e feche os agentes
  dessas pastas antes de sair, para eles não voltarem na restauração.

## Resultado

Anote aqui o que falhou, com o que apareceu na tela. Passo que falha vira teste automático e
correção antes do M2.

| Passo | Passou? | O que apareceu |
|-------|---------|----------------|
|       |         |                |

## Decisões que esperam o teste

O teste é a hora de confirmar ou trocar o que foi decidido sem consulta no diff:

- Atalhos ⌘⇧D (ver) e ⌘R (reler todos).
- Janela separada e única, em vez de um painel dentro da janela principal.
- Diff do repositório inteiro, e não só da subpasta do agente.
- Arquivos não rastreados entram na conta.
- Sem leitura periódica enquanto o agente trabalha.
- Com pouco espaço, a empresa fica e o resumo some.

E no que veio depois, também sem consulta:

- ⌘N sempre no `GLOBAL`, e ⌘⇧N para repetir a pasta do agente em foco.
- `clark PASTA` abre um agente lá e não vira padrão.
- Projeto é a pasta com git ou com instruções para agente, até quatro níveis abaixo da empresa.
- O apelido é do repositório e vale nas subpastas; fica no `config.json`.
- A última sessão sai do arquivo da conversa, sem modelo, e só aparece em conversa nova de projeto.
- No menu, cada pasta com projetos vira um submenu com o nome dela; worktree do git fica em
  `Worktrees`, fora da lista de projetos.
- O medidor de consumo lê o arquivo do AiUsageBar, sem rede e sem credencial no CLARK; os limites
  por modelo ficam de fora.
- `SHELL` é um estado próprio, em ciano e com os pontos andando, e conta em `WORKING` na barra.
- A faixa some na primeira tecla, e não fica guardada para rever.
- Card da lista lateral mais alto (104 px), com o projeto numa linha própria.

Fora do teste, segue aberta a ampliação dos nomes de segredo com `*_PASS`, `*_PWD` e `*_PAT`.
