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
./build.sh      # gera dist/Clark.app, com o ícone
./install.sh    # copia para ~/Applications e cria o atalho ~/.local/bin/clark
```

O `install.sh` não sobrescreve um `clark` que não seja o dele e não instala com o CLARK aberto.

Para remover, apague `~/Applications/Clark.app` e `~/.local/bin/clark`. As preferências ficam em
`~/.config/clark/`.

O ícone é o dragão do CLARK, desenhado pelo próprio app: o `build.sh` chama
`Clark --export-icon ARQUIVO --icon-size N` para cada tamanho e monta o `.icns` com o `iconutil`.

O app é assinado só localmente (assinatura ad hoc). Para o macOS, cada compilação é um app novo:
depois de recompilar, ele pode pedir de novo as permissões de notificação e de acesso a pastas.

## Uso

```
clark [PASTA] [-n N] [--fresh] [--version] [-- argumentos extras do claude]
```

| Opção | O que faz |
|-------|-----------|
| `PASTA` | Abre um agente nessa pasta; com `-n`, N agentes. Se ela não existe, abrem no `GLOBAL`, com um aviso. |
| `-n N` | Abre N agentes novos, de 0 a 16. Sem `PASTA`, no `GLOBAL`. |
| `--fresh` | Não restaura os agentes da última vez. |
| `--` | O que vier depois vai para o `claude` de todos os agentes. |

Ao reabrir, o CLARK restaura os agentes com as mesmas conversas (`claude --resume`). Se a pasta de
um agente não existe mais, ele abre na home, numa conversa nova. Sem agente para restaurar e sem
pedido na linha de comando, o CLARK abre um agente no `GLOBAL`.

Com o CLARK já aberto, `clark` só traz a janela para a frente: as opções são ignoradas.

### Projetos

Todo agente trabalha numa pasta, e o `claude` dele roda dentro dela: é dali que saem o `CLAUDE.md`,
o `AGENTS.md`, o `.claude/` e os arquivos que o agente lê.

O cabeçalho do agente diz de quem ele é em três etiquetas, nesta ordem: a empresa, na cor dela; o
projeto; e o nome do agente: `ACME` `PORTAL DE COMPRAS` `AGENT 2`. O agente fora de toda empresa
leva `GLOBAL` no lugar dela, e o projeto com o mesmo nome da empresa não se repete. Quando falta
largura, a empresa vira um quadrado da cor dela, depois o projeto é cortado e sai, e só no fim o
nome do agente é cortado, pelo começo: o fim é o que distingue `AGENT 1` de `AGENT 2`. O card da
lista lateral traz o nome, o projeto numa linha própria, na cor da empresa, e a empresa em cinza.

O CLARK começa no `GLOBAL`: um agente na home, para o que não é de projeto nenhum. O ⌘N e o
`+ AGENT` também abrem no `GLOBAL`. Para trabalhar num projeto, use o botão `PROJETO` da barra (⌘D):

- `Mais usados`, no topo, traz até cinco pastas em que o Claude Code mais foi usado nos últimos 30
  dias: a mais usada primeiro e, no empate, a usada por último. A conta sai das conversas que o
  Claude Code guarda de cada pasta, sem chamar modelo nenhum, e vale também para o que foi aberto
  fora do CLARK. Entra tudo o que o menu oferece nas empresas e as pastas apelidadas; o projeto vem
  com a empresa na frente (`Acme › Api`). O `GLOBAL` não entra na conta, e sem conversa nenhuma o
  bloco não aparece.
- `GLOBAL` abre um agente na home.
- Cada empresa é um submenu com os projetos dela. Escolher um abre um agente na pasta do projeto.
- Projeto é a pasta com repositório git ou com instruções para agente (`CLAUDE.md`, `AGENTS.md`,
  `.claude`), até quatro níveis abaixo da pasta da empresa. Os do primeiro nível vêm soltos. Os mais
  fundos ficam num submenu com o nome da pasta que os guarda (`Vendas ▸`). Pasta que só organiza
  (`projects`, `projetos`, `repos`, `apps`, `packages`, `src`) não entra no nome. Se dois submenus
  ficariam com o mesmo nome, entram as pastas de fora até eles se distinguirem (`Sistemas › Vendas`).
- O projeto que tem outros projetos dentro vira o submenu deles e abre pela primeira linha desse
  submenu.
- `Worktrees` junta as worktrees do git. Cada uma é um branch de um projeto que já está na lista,
  e por isso não aparece no meio dos projetos. A worktree com apelido fica com os apelidados.
- `Outras pastas` junta as pastas do primeiro nível que não são projeto, e `Pasta da empresa` abre
  na pasta da própria empresa.
- A empresa que é ela mesma um repositório, ou que não tem nada dentro, abre direto, sem submenu.
- `Outra pasta…` abre o seletor de pastas do macOS.

O ⌘⇧N (`Novo agente nesta pasta`, também no botão direito do cabeçalho) abre outro agente na pasta
do agente em foco. Com os 16 agentes abertos, nada abre e a barra avisa.

A lista é lida do disco cada vez que o menu abre: são as subpastas das `roots` e os `paths` do
`companies.json` (veja [Empresas](#empresas)). A busca não entra em repositório nem em pasta de
dependências (`node_modules`, `vendor`, `venv`, `dist`, `build` e parecidas).

**Apelidos.** O nome do projeto é o da pasta, arrumado: `portal_compras` vira `Portal Compras`.
Para trocar, clique com o botão direito no cabeçalho do agente e escolha `Apelidar projeto…` (o item
também está no menu `Agentes`). O apelido passa a valer no menu, no cabeçalho e no card, sobe para o
topo do submenu da empresa e fica em `project_names` no `~/.config/clark/config.json`. Ele é do
repositório: vale para qualquer subpasta. Apelido vazio volta ao nome da pasta.

**Última sessão.** O agente que começa uma conversa nova num projeto mostra, entre o cabeçalho e o
terminal, a faixa `ULTIMA SESSAO` com o que ficou da conversa anterior do Claude Code naquela pasta:
quando foi, o título, o último pedido, o começo da última resposta e, em amarelo, a linha que fala
do que ficou pendente, quando há. A faixa some na primeira tecla ou com um clique. O texto sai do
arquivo da conversa, sem chamar modelo nenhum. Ela não aparece no `GLOBAL`, em conversa retomada,
nem quando a pasta não tem conversa anterior; as conversas dos agentes abertos não contam.

### Diff

O cabeçalho e o card de cada agente mostram o que mudou no repositório da pasta dele desde o
último commit: `+12 -3 4 ARQ` são 12 linhas a mais e 3 a menos, em 4 arquivos. Repositório sem
mudança e pasta fora de repositório não mostram nada.

O ⌘⇧D abre a janela do diff do agente em foco: à esquerda os arquivos mudados, à direita o diff do
arquivo escolhido. O botão direito no cabeçalho de um agente tem o mesmo `Ver diff`. A janela é
uma só: pedir o diff de outro agente troca o conteúdo dela.

Clicar no resumo do cabeçalho abre, à direita do terminal daquele agente, a coluna `ALTERADOS`: os
arquivos em grupos (`MODIFICADOS`, `NOVOS`, `REMOVIDOS`, `NAO RASTREADOS`), cada um com o nome, a
pasta embaixo e as linhas a mais e a menos. Clicar num arquivo abre a janela do diff já nele. O `R`
relê e o `X` fecha; outro clique no resumo também fecha. O botão direito no cabeçalho tem o mesmo
`Arquivos alterados`. Cada agente tem a sua coluna, e ela não tira o foco do terminal. Em painel
com menos de 602 pontos de largura a coluna não cabe ao lado do terminal: o clique abre a janela
do diff.

- O diff é do repositório inteiro, mesmo com o agente numa subpasta. Entram as mudanças já
  preparadas com `git add` e os arquivos novos ainda não rastreados; os ignorados ficam de fora.
- O CLARK relê o repositório quando o agente abre, quando ele para de trabalhar, quando o CLARK
  volta para a frente e no ⌘R. Não há leitura periódica.
- O CLARK só lê: não prepara, não desfaz e não grava nada no repositório.
- Arquivo binário entra na lista sem contagem de linhas. Link simbólico novo também, e o diff dele
  mostra para onde o link aponta, não o conteúdo do destino.
- Diff com mais de 1 MiB ou de 20 mil linhas é cortado, com um aviso no fim.

### Consumo do plano

Se o [AiUsageBar](https://github.com/rafaelmgbh/ai-usage-bar) roda no mesmo Mac, a barra superior
mostra o consumo do plano do Claude, entre as contagens e os botões: `5H` e `7D`, cada um com uma
barra de dez blocos e o percentual. A cor é verde até 79%, amarela de 80% a 94% e vermelha de 95%
em diante. A dica do medidor diz em quanto tempo cada janela renova e de quando é a leitura.

O CLARK não consulta a Anthropic nem lê credencial. Uma vez por minuto, e sempre que você volta
para o app, ele relê o arquivo que o AiUsageBar mantém em
`~/Library/Caches/io.github.rafaelmgbh.ai-usage-bar/claude-usage.json`, que só tem percentuais e
horas de renovação. Vale a conta padrão do Claude Code; sem ela no arquivo, a conta lida por último.

- Leitura com mais de 15 minutos sai apagada; com mais de um dia, o medidor some.
- Janela que renovou depois da leitura mostra `0%`. Se a leitura já era velha, mostra `--`: o que
  foi gasto desde a renovação ninguém leu.
- Com a barra apertada, o medidor perde as barras e fica só com os números. Sem espaço nem para
  eles, some: as contagens de agentes têm a preferência.
- Sem o AiUsageBar não há medidor, e nada mais muda.

### Atalhos

| Atalho | Ação |
|--------|------|
| ⌘N | Novo agente no `GLOBAL` |
| ⌘⇧N | Novo agente na pasta do agente em foco |
| ⌘D | Abrir um agente num projeto |
| ⌘⇧D | Ver o diff do agente em foco |
| ⌘R | Reler o diff de todos os agentes |
| ⌘W | Fechar o agente em foco |
| ⌘L | Alternar entre foco e grade |
| ⌘↩ | Zoom no agente |
| ⌘1 a ⌘9 | Ir para o agente pelo número |
| ⌘{ e ⌘} | Agente anterior e próximo |
| ⌘+, ⌘- e ⌘0 | Tamanho da fonte |

Dois cliques no cabeçalho do agente renomeiam. O botão `[ ]` do cabeçalho dá zoom e o `x` fecha.

No terminal, ⌘-clique num endereço `http` ou `https` abre o navegador. Esses endereços aparecem
sublinhados em azul. O que não tem sublinhado (caminho de arquivo, `file:`, `ssh:`) o clique não
abre.

### Estados

| Estado | Significado |
|--------|-------------|
| `WORKING` | O agente está escrevendo. |
| `DONE!` | Terminou um trabalho e espera você. O Dock mostra a contagem; com o CLARK em segundo plano, vem também uma notificação com o nome do agente e, embaixo, a empresa e o projeto dele (`Acme › Api`). |
| `IDLE` | Parado. |
| `SHELL` | Parado, com um comando que o Claude deixou rodando em segundo plano: o `1 shell` do rodapé do Claude Code. Na barra superior conta em `WORKING`. |
| `GAME OVER` | O processo saiu. Enter abre de novo na mesma conversa. |

A faixa vermelha `SEM PERMISSOES` aparece no agente aberto com
`--dangerously-skip-permissions` ou `--permission-mode bypassPermissions`.

A etiqueta azul `REMOTO`, ao lado do estado no cabeçalho e na linha de detalhe do card, avisa que
o controle remoto do Claude Code (`/remote-control`) está ligado naquele agente: a conversa também
pode ser tocada do celular ou de claude.ai/code. Ela aparece e some em até um segundo depois de
ligar ou desligar. No cabeçalho apertado sai primeiro o resumo do diff; sem espaço nem para ela, o
aviso fica só no card. O CLARK lê isso de um arquivo interno do Claude Code: se o formato mudar, a
etiqueta deixa de aparecer e nada mais muda.

## Empresas

Sem configuração, a primeira pasta abaixo de `~/Projetos` é a empresa do agente:
um agente em `~/Projetos/acme/api` é da empresa `acme`. Fora dali o agente não é de empresa
nenhuma: o cabeçalho mostra `GLOBAL`, e é esse o valor de `CLARK_COMPANY`.

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
- `color`: cor da empresa, a da etiqueta dela no cabeçalho. Só vale em empresa declarada com
  `paths`. Sem ela, a cor sai do nome, e duas empresas podem cair na mesma; nesse caso declare as
  duas com `color`.
- `env_allow`: veja a seção seguinte.

No card, agentes da mesma empresa ganham tons mais escuros da mesma cor. A etiqueta do cabeçalho
fica sempre na cor da empresa.

## Ambiente dos agentes

Cada agente nasce com o ambiente do seu shell de login, menos:

1. as variáveis de sessão do Claude Code que abriu o CLARK, para o agente não se achar uma
   subsessão;
2. as variáveis com nome de segredo: `*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*PASSWD*`,
   `*CREDENTIAL*`, `AWS_*`, `PG*`, `*_DSN`, `DATABASE_URL`, `*_PASS`, `*_PWD` e `*_PAT`. Os três
   últimos só valem no fim do nome: `SMTP_PASS` sai, `PWD` e `PATH` ficam.

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
O que os testes não cobrem (tela, teclado, o `claude` de verdade) tem roteiro manual em
[`docs/testes/2026-10-12-roteiro-manual.md`](docs/testes/2026-10-12-roteiro-manual.md).

## Limitações do M1

- Só o tema `dark`. Os temas `white` e `magick`, a tela de abertura e os dragões ficam para o M3.
- A fila de trabalho (`/paralelo` e `/to-dev`) fica para o M2.
- Renomear um agente não muda o `CLARK_AGENT` do processo que já está rodando.
- Os avisos da interface saem sem acento, porque a fonte de pixels só tem ASCII.
- O link que começa mais de oito linhas acima da tela aparece sem sublinhado. O ⌘-clique abre do
  mesmo jeito.

## Licença

MIT, a mesma do projeto original. Veja [`LICENSE`](../LICENSE).
