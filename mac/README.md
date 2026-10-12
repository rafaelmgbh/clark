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
| `PASTA` | Pasta dos agentes novos. Sem ela, vale a do último projeto aberto. |
| `-n N` | Abre N agentes novos, de 0 a 16. |
| `--fresh` | Não restaura os agentes da última vez. |
| `--` | O que vier depois vai para o `claude` de todos os agentes. |

Ao reabrir, o CLARK restaura os agentes com as mesmas conversas (`claude --resume`). Se a pasta de
um agente não existe mais, ele abre na home, numa conversa nova.

Com o CLARK já aberto, `clark` só traz a janela para a frente: as opções são ignoradas.

### Projetos

O botão `PROJETO` da barra (⌘D) lista as empresas e, dentro de cada uma, as pastas de projeto.
Escolher um projeto abre um agente nele, como se o `claude` tivesse sido chamado dentro da pasta.

- `GLOBAL` abre o agente na home, sem projeto. A empresa dele é `AVULSO`.
- O primeiro item de cada empresa é a pasta da própria empresa.
- Uma pasta que não é repositório git e guarda repositórios vira um submenu com o que há dentro dela.
- `Outra pasta…` abre o seletor de pastas do macOS.

A lista é lida do disco cada vez que o menu abre: são as subpastas das `roots` e os `paths` do
`companies.json` (veja [Empresas](#empresas)). O ⌘N repete o último projeto escolhido. Com os 16
agentes abertos, escolher um projeto só troca a pasta do próximo agente.

### Diff

O cabeçalho e o card de cada agente mostram o que mudou no repositório da pasta dele desde o
último commit: `+12 -3 4 ARQ` são 12 linhas a mais e 3 a menos, em 4 arquivos. Repositório sem
mudança e pasta fora de repositório não mostram nada.

O ⌘⇧D abre a janela do diff do agente em foco: à esquerda os arquivos mudados, à direita o diff do
arquivo escolhido. O botão direito no cabeçalho de um agente tem o mesmo `Ver diff`. A janela é
uma só: pedir o diff de outro agente troca o conteúdo dela.

- O diff é do repositório inteiro, mesmo com o agente numa subpasta. Entram as mudanças já
  preparadas com `git add` e os arquivos novos ainda não rastreados; os ignorados ficam de fora.
- O CLARK relê o repositório quando o agente abre, quando ele para de trabalhar, quando o CLARK
  volta para a frente e no ⌘R. Não há leitura periódica.
- O CLARK só lê: não prepara, não desfaz e não grava nada no repositório.
- Arquivo binário entra na lista sem contagem de linhas. Link simbólico novo também, e o diff dele
  mostra para onde o link aponta, não o conteúdo do destino.
- Diff com mais de 1 MiB ou de 20 mil linhas é cortado, com um aviso no fim.

### Atalhos

| Atalho | Ação |
|--------|------|
| ⌘N | Novo agente |
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
O que os testes não cobrem (tela, teclado, o `claude` de verdade) tem roteiro manual em
[`docs/testes/2026-10-12-roteiro-manual.md`](docs/testes/2026-10-12-roteiro-manual.md).

## Limitações do M1

- Só o tema `dark`. Os temas `white` e `magick`, a tela de abertura e os dragões ficam para o M3.
- A fila de trabalho (`/paralelo` e `/to-dev`) fica para o M2.
- Renomear um agente não muda o `CLARK_AGENT` do processo que já está rodando.
- Os avisos da interface saem sem acento, porque a fonte de pixels só tem ASCII.

## Licença

MIT, a mesma do projeto original. Veja [`LICENSE`](../LICENSE).
