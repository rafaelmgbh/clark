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
| Coluna de arquivos alterados (commit seguinte ao `7cc4de7`) | 500 testes verdes, 78 mutações mortas, imagens renderizadas nos testes | nunca |
| Aviso de controle remoto (commit seguinte ao `9bdf093`) | 515 testes verdes, 26 mutações mortas, imagem renderizada nos testes, campo do arquivo de sessão conferido em sessões reais | nunca |
| Cabeçalho em etiquetas, `Mais usados` no menu e links sublinhados (os três commits seguintes ao do aviso de controle remoto) | 580 testes verdes, 102 mutações mortas (30 do cabeçalho, 24 do menu, 48 dos links), imagens renderizadas nos testes, custo da leitura dos links medido no build otimizado | nunca |
| Agente em segundo plano não dispara o aviso de agente pronto (correção do aviso falso) | 592 testes verdes, o aviso falso reproduzido em teste antes da correção, a correção ingênua (que atrasaria o aviso de verdade) morta por dois testes, `status` do arquivo de sessão conferido numa sessão real com agentes em segundo plano | nunca |
| Menu `PROJETO` em cascata desenhado pelo app, com as empresas em maiúsculas e na cor delas (`250850e`) | 656 testes verdes, 16 de 17 mutações mortas (a que sobra é o repasse do tema ao menu: só existe o `dark`), imagem do menu renderizada com as pastas reais | nunca: o cursor, o teclado e o clique fora só foram exercitados nos testes |
| Botão `PROJETO` fora da barra: ⌘D abre o `+ AGENT` já na cascata `Projeto`, `Mais usados` agrupado por empresa e clique na empresa abrindo na pasta dela (commit seguinte ao `5d701c7`) | 714 testes verdes, inclusive o ⌘D até abrir o projeto pelo teclado e o recuo desenhado | nunca: B2, B2a, B2g e B6 |
| Ícone do dragão (`7fa1ec6`) | coberto pelos testes | nunca |
| Núcleo do M1 (`80cb7e8`) | coberto pelos testes | em uso, mas o roteiro da Task 15 do plano nunca foi rodado inteiro |
| Atualização automática pelo `update.sh` (commit seguinte ao `a204bab`) | 695 testes verdes; `Tests/packaging.sh` verde nos 11 passos, inclusive compilar o HEAD e reinstalar numa HOME de mentira | nunca: o app fechando e reaberto pelo Dock (E3) |
| `Tests/packaging.sh` | verde em 2026-10-14, com o CLARK aberto | não se aplica |

Os commits estão na `origin/main` (`dcea13e`). O app instalado em `~/Applications/Clark.app` já é
a compilação com o diff: em 2026-10-11 o executável instalado era idêntico ao do `dist/`.

## Preparação

1. Confirme a versão instalada: o menu `Agentes` tem os itens `Ver diff`, `Atualizar diff` e
   `Apelidar projeto…`, e o botão direito no cabeçalho de um agente tem `Arquivos alterados`. Se
   faltar algum, saia do CLARK (⌘Q) e rode, de dentro de `mac/`:

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

3. No CLARK, abra um agente em cada pasta: ⌘N, `Outra pasta…`, e no seletor do macOS ⌘⇧G para
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
  estreite a janela principal. Esperado: quando falta espaço, some primeiro o resumo do diff; depois
  a etiqueta da empresa vira um quadrado da cor dela, o projeto é cortado e sai, e o nome do agente
  é o último a ser cortado, pelo começo (`…NT 2`); nada se sobrepõe.

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

### Coluna de arquivos alterados

Estes passos usam o mesmo `/tmp/clark-diff`, no estado da preparação. Os passos A9 a A15 mexem
nele. Para os números abaixo baterem, desfaça o que eles fizeram e aperte ⌘R no CLARK:

```bash
cd /tmp/clark-diff && git checkout -q -- b.txt && rm -f longo.txt bin.dat teste.txt e.txt
```

- [ ] **A17. Abrir pelo resumo.** Com a janela larga e o agente de `/tmp/clark-diff` em foco, clique
  no `+5 -2 4 ARQ` do cabeçalho. Esperado: abre uma coluna à direita do terminal, com
  `ALTERADOS 4` no topo e os botões `R` e `X`; o terminal estreita e o `claude` se redesenha na
  largura nova; o cabeçalho segue no estado em que estava, sem passar por `WORKING`. Sem clicar em
  mais nada, digite: o texto cai no terminal.

- [ ] **A18. Grupos e linhas.** Esperado, de cima para baixo: `MODIFICADOS 1` com `M`, `a.txt` e
  `+2 -1`; `NOVOS 1` com `A`, `d.txt` e `+1 -0`; `REMOVIDOS 1` com `D`, `c.txt` e `+0 -1`;
  `NAO RASTREADOS 1` com `?`, `novo.txt`, `+2 -0` e `sub` na linha de baixo. As letras têm as
  cores da janela do diff (`M` amarelo, `D` vermelho, `A` e `?` verdes). O mouse acende a linha de
  um arquivo, e não a do título de um grupo.

- [ ] **A19. Clique num arquivo.** Clique em `c.txt` na coluna. Esperado: a janela do diff abre com
  `c.txt` escolhido na lista e a remoção de `some` à direita. Sem fechar a janela, volte ao CLARK
  e clique em `novo.txt` na coluna: a janela passa para ele.

- [ ] **A20. Fechar.** Clique no `X`. Esperado: a coluna some e o terminal volta à largura toda.
  Abra de novo pelo resumo e feche com outro clique no resumo. Um duplo clique no resumo abre e
  fecha a coluna, e não abre o campo de renomear.

- [ ] **A21. Menu do cabeçalho.** Botão direito no cabeçalho, `Arquivos alterados`. Esperado: a
  coluna abre. Abra o menu de novo: o item vem marcado, e escolhê-lo fecha a coluna.

- [ ] **A22. Uma coluna por agente.** Com a coluna aberta no agente de `/tmp/clark-diff`, ponha em
  foco o agente de `/tmp/clark-diff/sub`. Esperado: ele está sem coluna. Volte ao primeiro: a
  coluna dele continua aberta.

- [ ] **A23. Painel estreito.** Com a coluna aberta, estreite a janela principal aos poucos.
  Esperado: quando o terminal ficaria com menos de 320 pontos, a coluna some e o terminal toma a
  largura toda; alargando, ela volta sozinha. Num painel estreito em que o resumo ainda aparece
  (na grade, ⌘L, com vários agentes), clique no resumo: abre a janela do diff, e não a coluna.

- [ ] **A24. Reler.** Com a coluna aberta, rode no Terminal
  `(sleep 15; echo x > /tmp/clark-diff/e.txt) &` e volte para o CLARK antes dos 15 segundos.
  Espere uns 30 segundos. Esperado: a coluna não muda sozinha. Clique no `R`: o título vira
  `ALTERADOS 5` e `e.txt` entra em `NAO RASTREADOS 2`, sem a linha da pasta, porque está na raiz.

- [ ] **A25. Avisos.** No agente de `/tmp/clark-limpo`, botão direito no cabeçalho e
  `Arquivos alterados`. Esperado: a coluna abre com `ALTERADOS 0` e `NADA MUDOU`. No de
  `/tmp/clark-vazio`: `ALTERADOS` e `FORA DE REPOSITORIO GIT`.

- [ ] **A26. Com a faixa da última sessão.** Abra um agente novo num projeto que já teve conversa,
  para a faixa `ULTIMA SESSAO` aparecer, e abra a coluna pelo menu do cabeçalho. Esperado: a faixa
  fica com a largura toda e a coluna começa abaixo dela, ao lado do terminal.

## B. Projetos, apelidos, última sessão e ícone

- [ ] **B1. Começa no `GLOBAL`.** Feche todos os agentes, saia (⌘Q) e abra o CLARK. Esperado: um
  agente na home, com duas etiquetas no cabeçalho, `GLOBAL` em cinza e `AGENT 1`. `! pwd` mostra a
  home.

- [ ] **B2. ⌘D.** A barra tem só `FOCO` e `+ AGENT` à direita, sem `PROJETO`. Aperte ⌘D. Esperado:
  sem demora, o menu do `+ AGENT` abre logo abaixo dele (`GLOBAL`, `Projeto`, `Digitar pasta…`,
  `Outra pasta…`), com a cascata `Projeto` já aberta ao lado e a primeira linha dela destacada: dá
  para seguir com ↓ e Enter sem tocar no mouse. A cascata traz `Mais usados` no topo, depois
  `EMPRESAS` com uma linha por empresa.

- [ ] **B2b. Cara do menu.** Com o menu aberto, olhe o desenho. Esperado: fundo escuro com moldura e
  sombra dura, a mesma letra dos botões; `MAIS USADOS` e `EMPRESAS` em letra pequena e cinza; as
  empresas em maiúsculas, cada uma com um quadradinho na cor dela (a mesma da etiqueta no cabeçalho
  dos agentes) e um `>` na ponta; a linha sob o cursor fica mais clara, com uma barra laranja à esquerda. Nada do
  menu cinza do macOS.

- [ ] **B2c. Cascata com o cursor.** Pare o cursor numa empresa. Esperado: o submenu abre ao lado,
  sem clique, com a primeira linha na altura da empresa. Vá na diagonal até uma linha lá embaixo do
  submenu, passando por cima de outras empresas: o submenu não troca no caminho. Agora pare numa
  outra empresa: o submenu troca depois de um instante. Dentro do submenu, pare numa linha com `>`
  (`Worktrees`, `Outras pastas` ou uma pasta com projetos): abre o terceiro nível.

- [ ] **B2d. Teclado.** Abra o menu com ⌘D e não toque no mouse. Esperado: ↓ e ↑ andam pelas linhas,
  pulando os títulos, os nomes de empresa dos `Mais usados` e os traços, e dão a volta no fim; →
  numa empresa entra no submenu, com a primeira linha destacada; ← volta para a empresa, e outro ←
  volta para `Projeto`; Enter num projeto abre o agente e fecha o menu; Enter numa empresa abre o
  agente na pasta dela (B2g); Esc fecha tudo. Digite letras com o menu aberto: nada chega ao
  terminal.

- [ ] **B2e. Fechar sem escolher.** Abra o menu e clique no terminal. Esperado: o menu fecha e o
  clique não seleciona texto nem troca de agente. Abra de novo e clique no próprio botão `+ AGENT`:
  fecha, sem reabrir. Abra e aperte ⌘D: fecha. Abra e troque de app com ⌘Tab: ao voltar, o menu não
  está mais lá. Em todos os casos o foco continua no terminal: dá para digitar em seguida.

- [ ] **B2f. Bordas da tela.** Arraste a janela do CLARK até o botão `+ AGENT` ficar perto da borda
  direita da tela e abra uma empresa. Esperado: o submenu abre à esquerda do menu, inteiro na tela.
  Com a janela baixa na tela, abra a empresa com mais projetos: o submenu sobe para caber e, se ainda
  assim não couber, rola com a roda do mouse ou com ↓, mostrando uma seta laranja no canto de onde
  há mais linhas.

- [ ] **B2a. Mais usados.** No topo da cascata, confira o bloco `Mais usados`. Esperado: até cinco
  pastas em que você mais usou o Claude Code no último mês, dentro ou fora do CLARK, juntas sob o
  nome da empresa: uma linha apagada, em maiúsculas e com o quadradinho da cor dela, e os projetos
  embaixo, um pouco para a direita, só com o nome (`Natutec`, sem `N1 Labs ›`). A empresa da pasta
  mais usada vem primeiro. A pasta da própria empresa aparece como `Pasta da empresa`. A home não
  está entre elas; passar o mouse num projeto mostra o caminho. Clique no nome da empresa: nada
  acontece. Escolha um projeto: abre um agente naquela pasta, igual a escolher pelo submenu da
  empresa. O título `Mais usados` não é clicável.

- [ ] **B2g. Clique na empresa.** Em `EMPRESAS`, clique numa empresa (`N1 LABS`, `SULIVAM`), sem
  esperar o submenu. Esperado: o menu fecha e abre um agente na pasta da empresa; `! pwd` mostra a
  pasta dela. Passar o mouse na
  linha mostra o caminho e abre o submenu ao lado, como antes. Uma empresa com mais de uma pasta no
  `companies.json` só abre o submenu, sem agente.

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
  três etiquetas no cabeçalho, nesta ordem: a empresa na cor dela, o projeto e o nome do agente
  (`EMPRESA` `MEU PROJETO` `AGENT 2`), com a cara dos botões `FOCO` e `+ AGENT`. O card da
  lista lateral traz o projeto numa linha própria. Rode `! pwd` para conferir a pasta.

- [ ] **B5. O `claude` enxerga o projeto.** No agente aberto no B4, rode `/memory`. Esperado: o
  `CLAUDE.md` (ou `AGENTS.md`) listado é o daquele projeto.

- [ ] **B6. ⌘N e ⌘⇧N.** Com o agente do B4 em foco, ⌘N abre sob o `+ AGENT` o menu `GLOBAL`,
  `Projeto`, `Digitar pasta…`, `Outra pasta…`, sem nenhuma cascata aberta; `GLOBAL` abre na home,
  `Outra pasta…` abre o seletor de pastas do macOS, e ⌘⇧N abre outro na pasta do agente em foco.
  O botão direito no cabeçalho tem o mesmo `Novo agente nesta pasta`.

- [ ] **B6a. + AGENT.** Clique no `+ AGENT`: o mesmo menu do ⌘N, logo abaixo do botão, sem abrir
  agente ainda. `Projeto` em cascata mostra `Mais usados` e as empresas, como no ⌘D;
  escolher um projeto abre o agente nele. `Digitar pasta…` mostra um campo sob o botão:
  `~/Projetos/Sulivam/larys` + Enter abre lá; com um agente em foco num repo, `docs` + Enter abre a
  subpasta dele; uma pasta que não existe só dá o aviso; Esc ou clicar fora fecha sem abrir.

- [ ] **B7. Apelidar.** Botão direito no cabeçalho do agente do B4, `Apelidar projeto…`, digite um
  nome e Enter. Esperado: o cabeçalho e o card de todos os agentes daquele projeto trocam na hora; na
  cascata `Projeto`, o apelido aparece no topo do submenu da empresa. Abra um agente numa subpasta do
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
  abre mais um naquela pasta; um ⌘N › `GLOBAL` depois disso abre na home. `clark /nao/existe` abre o agente
  no `GLOBAL` e a barra de avisos diz que a pasta não foi encontrada.

- [ ] **B14. Ícone.** O dragão aparece no Dock, no ⌘Tab e no Finder (`~/Applications`), nítido nos
  tamanhos pequeno e grande.

## C. O que ficou do M1

O roteiro completo é a Task 15 de [`docs/plans/2026-10-11-clark-mac-m1-nucleo.md`](../plans/2026-10-11-clark-mac-m1-nucleo.md),
com 17 passos. Nenhum deles foi registrado como rodado. Os que mais pesam, por ordem:

- [ ] **C1. Restaurar (passo 9).** ⌘Q com agentes vivos mostra `Sair do CLARK?`. Ao abrir de novo
  voltam os mesmos agentes, nomes, pastas e conversas. `clark --fresh` não restaura nenhum.

- [ ] **C2. Notificação (passo 7).** Tarefa de uns dez segundos num agente, com outro app na
  frente. Esperado: `WORKING`, depois `DONE!`, a notificação `CLARK · <agente>` com a empresa e o
  projeto na linha de baixo (`Acme › Api`; nada no agente do `GLOBAL`) e a contagem no Dock. Clicar
  na notificação traz o CLARK com aquele agente em foco.

- [ ] **C3. Teclado ABNT (passo 4).** `ação, é, à, õ, ü, ç, 'aspas', "aspas"` no prompt do
  `claude` saem como digitados. Option+← e Option+→ pulam palavra.

- [ ] **C4. Segunda chamada (passo 16).** Com o app aberto, `clark /tmp` só traz a janela para a
  frente: nenhum agente novo.

- [ ] **C5. Duas empresas, dois ambientes (passos 5 e 6).** Siga o passo 5 do plano: a variável
  liberada só aparece no agente da empresa que a liberou, e o menu `Variáveis removidas (N)` lista
  só nomes.

- [ ] **C6. Os outros passos da Task 15,** na ordem do plano.

## D. Consumo do plano, aviso de fim de turno, estado SHELL, controle remoto e links

Estes passos pedem o [AiUsageBar](https://github.com/rafaelmgbh/ai-usage-bar) rodando no mesmo Mac.

- [ ] **D1. Medidor na barra.** Com a janela larga, olhe a barra superior. Esperado: entre as
  contagens e o botão `FOCO`, `5H` e `7D`, cada um com uma barra de dez blocos e o percentual.
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

- [ ] **D9. Controle remoto.** Num agente, digite `/remote-control`. Esperado: em até um segundo,
  a etiqueta azul `REMOTO` aparece ao lado do estado no cabeçalho e na linha de detalhe do card
  daquele agente, e só dele; o estado do agente não muda por causa dela. Digite `/remote-control`
  de novo e desconecte. Esperado: a etiqueta some em até um segundo.

- [ ] **D10. REMOTO enquanto trabalha e no aperto.** Com o controle remoto ligado, mande do celular
  ou de claude.ai/code um pedido demorado. Esperado: a etiqueta continua durante o `WORKING`.
  Passe para a grade com vários agentes, ou estreite a janela aos poucos. Esperado: no cabeçalho
  some primeiro o resumo do diff e só depois a etiqueta; as etiquetas da empresa, do projeto e do
  nome não encolhem por causa dela.

- [ ] **D11. REMOTO e GAME OVER.** Com o controle remoto ligado, saia do Claude (`/exit`).
  Esperado: `GAME OVER` sem a etiqueta. Enter reabre a conversa, e a etiqueta só volta se o
  controle remoto voltar (com `Enable Remote Control for all sessions` ligado no `/config`, ele
  volta sozinho).

- [ ] **D12. Links sublinhados.** Num agente, peça: `escreva o endereço https://example.com/a, o
  caminho ~/Projetos e um endereço de mais de duas linhas`. Esperado: os dois endereços aparecem
  sublinhados em azul, o comprido em todas as linhas que ocupa; o caminho, não. ⌘-clique num
  endereço sublinhado abre o navegador nele; ⌘-clique no caminho não abre nada.

- [ ] **D13. Links e a tela.** Com links na tela, role o histórico para cima e para baixo, mude o
  tamanho da janela, passe para a grade e use ⌘+ e ⌘-. Esperado: o traço acompanha o texto, sem
  ficar para trás nem aparecer debaixo de outro texto. Selecionar e copiar um endereço sublinhado
  funciona como antes.

- [ ] **D14. Agente em segundo plano não avisa antes da hora.** Com outro app na frente, peça num
  agente: `dispare um agente em segundo plano que espere um minuto e me devolva o controle`.
  Esperado: o turno acaba, o rodapé do Claude Code mostra o agente em segundo plano, e o card do
  CLARK continua em `WORKING`, sem `DONE!` e sem notificação, mesmo com a tela parada. Quando o
  agente em segundo plano termina, o Claude retoma o turno, e só no fim dele vêm o `DONE!` e a
  notificação, uma vez só.

- [ ] **D15. Pedido de permissão ainda avisa.** Com outro app na frente, peça num agente sem
  `SEM PERMISSOES` algo que exija aprovação, como editar um arquivo. Esperado: quando o Claude Code
  para no pedido de permissão, o card vai a `DONE!` e a notificação chega, como antes.

## E. Depois do teste

- [ ] **E1. `Tests/packaging.sh`.** De dentro de `mac/`: `Tests/packaging.sh`. Desde a atualização
  automática, roda com o CLARK aberto e leva alguns minutos, porque compila o app de novo numa HOME
  de mentira.

- [ ] **E3. Atualização ao fechar.** Com um commit novo que mexa em `mac/`, saia do CLARK (⌘Q) e
  acompanhe `tail -f ~/Library/Logs/Clark/update.log` até `CLARK atualizado para <commit>`. Abra
  pelo Dock. Esperado: o app abre na versão nova, sem alerta do macOS, com os agentes de antes.
  Saia de novo sem commit novo: o log fica vazio e nada é compilado.

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

- ⌘N sempre no `GLOBAL`, e ⌘⇧N para repetir a pasta do agente em foco. (Depois: ⌘N e `+ AGENT`
  perguntam `GLOBAL`, `Projeto` ou `Digitar pasta…`.)
- `clark PASTA` abre um agente lá e não vira padrão.
- Projeto é a pasta com git ou com instruções para agente, até quatro níveis abaixo da empresa.
- O apelido é do repositório e vale nas subpastas; fica no `config.json`.
- A última sessão sai do arquivo da conversa, sem modelo, e só aparece em conversa nova de projeto.
- No menu, cada pasta com projetos vira um submenu com o nome dela; worktree do git fica em
  `Worktrees`, fora da lista de projetos.
- O medidor de consumo lê o arquivo do AiUsageBar, sem rede e sem credencial no CLARK; os limites
  por modelo ficam de fora.
- `SHELL` é um estado próprio, em ciano e com os pontos andando, e conta em `WORKING` na barra.
- Com agente em segundo plano trabalhando, o agente fica em `WORKING` e o aviso só vem quando a
  sessão desocupa. Com comando em segundo plano (`SHELL`), o aviso do fim do turno continua.
- A faixa some na primeira tecla, e não fica guardada para rever.
- Card da lista lateral mais alto (104 px), com o projeto numa linha própria.
- Na coluna de arquivos alterados: em painel estreito o clique no resumo abre a janela do diff, e a
  coluna pede 320 pontos de terminal; o menu do cabeçalho tem `Arquivos alterados`; arquivo da raiz
  fica numa linha mais baixa, sem a pasta; a coluna não é lembrada ao reabrir o app.

- No cabeçalho: empresa, projeto e nome do agente como etiquetas, nessa ordem; só a da empresa
  leva cor, a mesma em todos os agentes dela (o tom por agente fica no card); fora de empresa a
  palavra é `GLOBAL`, que substituiu `AVULSO` também em `CLARK_COMPANY`; o quadrado colorido saiu;
  as etiquetas não clicam.
- No menu `PROJETO`: `Mais usados` conta as conversas que o Claude Code guarda de cada pasta nos
  últimos 30 dias, e não o que foi aberto pelo CLARK; cinco linhas; o `GLOBAL` fica de fora.
  (Depois: o botão `PROJETO` saiu da barra e o menu virou a cascata `Projeto` do `+ AGENT`, que o
  ⌘D abre já aberta; `Mais usados` agrupado sob o nome da empresa; clicar na empresa abre na pasta
  dela.)
- No aviso de controle remoto: a palavra `REMOTO` em azul, no cabeçalho e no card; sem clique e
  sem o endereço da sessão; no cabeçalho apertado o resumo do diff sai antes dela.

A ampliação dos nomes de segredo com `*_PASS`, `*_PWD` e `*_PAT` foi aprovada e entrou em
2026-10-12. Se um agente parar de autenticar depois dela, o menu do agente mostra o nome removido,
e o conserto é listar esse nome em `env_allow`.
