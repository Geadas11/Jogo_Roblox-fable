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

Formata, corre os testes, gera o mapa, verifica-o e grava o place em `releases/`.

Os testes correm sobre um motor simulado. Servem para apanhar erros de código cedo; não
substituem o teste no Studio.
