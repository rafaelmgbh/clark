# Roteiro manual: diff, projetos e o que ficou do M1

Escrito em 2026-10-12 para a próxima sessão de teste. Quem roda é o dono da máquina: o roteiro
usa a tela, o teclado e a conta do `claude`. Nada aqui é automatizado.

## O que já está conferido e o que não está

| Parte | Automático | Na tela |
|-------|------------|---------|
| Diff do agente (`dcea13e`) | 324 testes verdes, 8 mutações mortas, imagens renderizadas nos testes | nunca |
| Menu de projetos (`443277d`) | coberto pelos testes | nunca; nem o clique no botão `PROJETO` |
| Ícone do dragão (`7fa1ec6`) | coberto pelos testes | nunca |
| Núcleo do M1 (`80cb7e8`) | coberto pelos testes | em uso, mas o roteiro da Task 15 do plano nunca foi rodado inteiro |
| `Tests/packaging.sh` depois do diff | não rodou: exige o CLARK fechado | não se aplica |

Os commits estão na `origin/main` (`dcea13e`). O app instalado em `~/Applications/Clark.app` já é
a compilação com o diff: em 2026-10-11 o executável instalado era idêntico ao do `dist/`.

## Preparação

1. Confirme a versão instalada: o menu `Agentes` tem os itens `Ver diff` e `Atualizar diff`. Se não
   tiver, saia do CLARK (⌘Q) e rode, de dentro de `mac/`:

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

## B. Projetos e ícone

- [ ] **B1. Clique no botão `PROJETO`.** Clique no botão da barra, sem usar o ⌘D. Esperado: o menu
  abre logo abaixo dele, com `GLOBAL`, as empresas e `Outra pasta…`.

- [ ] **B2. Abrir num projeto.** Escolha um projeto de uma empresa. Esperado: abre um agente novo
  naquela pasta, com o nome e a cor da empresa no cabeçalho. Rode `! pwd` no agente para conferir.

- [ ] **B3. `GLOBAL`.** Esperado: o agente abre na home, com a empresa `AVULSO`.

- [ ] **B4. Pasta que guarda repositórios.** Uma pasta que não é repositório git e tem repositórios
  dentro aparece como submenu.

- [ ] **B5. ⌘N repete.** Depois de escolher um projeto, ⌘N abre outro agente na mesma pasta.

- [ ] **B6. Ícone.** O dragão aparece no Dock, no ⌘Tab e no Finder (`~/Applications`), nítido nos
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

## D. Depois do teste

- [ ] **D1. `Tests/packaging.sh`.** Com o CLARK fechado (⌘Q), de dentro de `mac/`:
  `Tests/packaging.sh`. O script recusa rodar com o app aberto.

- [ ] **D2. Limpeza.** `rm -rf /tmp/clark-diff /tmp/clark-limpo /tmp/clark-vazio` e feche os agentes
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

Fora do teste, segue aberta a ampliação dos nomes de segredo com `*_PASS`, `*_PWD` e `*_PAT`.
