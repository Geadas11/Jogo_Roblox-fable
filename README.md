# NIGHT SHIFT: SUPERMARKET

Jogo cooperativo de terror e sobrevivência para Roblox (até 6 jogadores).
O código vive neste repositório e é sincronizado para o Roblox Studio com o [Rojo](https://rojo.space/).

- **Estado do projeto:** [`PROGRESS.md`](PROGRESS.md)
- **Plano e decisões:** [`docs/01-pre-producao.md`](docs/01-pre-producao.md)
- **Fase atual — o monstro, como testar:** [`docs/05-terror.md`](docs/05-terror.md)
- **Como jogar (tarefas, turno):** [`docs/04-jogabilidade.md`](docs/04-jogabilidade.md)
- **O mapa:** [`docs/03-ambiente.md`](docs/03-ambiente.md)
- **Fundação do código e ligação por Rojo:** [`docs/02-setup.md`](docs/02-setup.md)

## Jogar / testar

Abre [`releases/NightShiftSupermarket.rbxl`](releases/NightShiftSupermarket.rbxl) no Roblox Studio e
carrega em Play. O ficheiro contém o código e o mapa.

## Desenvolver com o Studio aberto (Rojo, sincronização ao vivo)

Uma só janela do Studio, sempre a mesma:

1. Num terminal na pasta do projeto:
   `powershell -ExecutionPolicy Bypass -File scripts\serve.ps1`
   (corre `rojo serve serve.project.json` na porta 34872; deixa-o aberto).
2. No Studio, abre `releases/NightShiftSupermarket.rbxl` uma vez.
3. Separador **Plugins → Rojo → Connect**.

A partir daí:
- tudo o que muda em `src/` aparece no Studio na hora;
- depois de mudar `map/`, corre `.tools\lune.exe run tools/build`: o mapa e as grelhas do
  monstro (`build/*.rbxm`) são enviados para a mesma janela, sem a reabrir.

Plugin: **Rojo** da Creator Store (versão 7.7.x, igual à de `rokit.toml`). Na primeira ligação
o Studio pede permissão de **Script Injection** — aceita, ou ativa-a em
Plugins → Manage Plugins → Rojo; sem ela o Rojo liga-se mas não consegue escrever os scripts.
As ferramentas (`rojo`, `lune`, `stylua`, versões de `rokit.toml`) estão em `.tools/`, fora do Git.

## Estrutura

| Pasta | Vai para |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
| `map` | gerador do supermercado; produz `Workspace.Map` |
| `tools` | construção do ficheiro do place |
| `tests` | testes que correm fora do Studio |
| `releases` | o place construído, pronto a abrir |

## Verificações automáticas

Com as ferramentas de `rokit.toml` instaladas (`rojo`, `stylua`, `lune`):

```bash
./scripts/check.sh
```

No Windows: `powershell -ExecutionPolicy Bypass -File scripts\check.ps1`

Formata, corre os testes, gera o mapa, verifica-o e grava o place em `releases/`.

Os testes correm sobre um motor simulado. Servem para apanhar erros de código cedo; não
substituem o teste no Studio.
