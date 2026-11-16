# NIGHT SHIFT: SUPERMARKET

Jogo cooperativo de terror e sobrevivência para Roblox (até 6 jogadores).
O código vive neste repositório e é sincronizado para o Roblox Studio com o [Rojo](https://rojo.space/).

- **Estado do projeto:** [`PROGRESS.md`](PROGRESS.md)
- **Plano e decisões:** [`docs/01-pre-producao.md`](docs/01-pre-producao.md)
- **Ligar o Studio e testar a fase atual:** [`docs/02-setup.md`](docs/02-setup.md)

## Estrutura

| Pasta | Vai para |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
| `tests` | não vai para o jogo; testes que correm fora do Studio |

O mapa e os assets vivem no ficheiro do place, no Studio.

## Verificações automáticas

Com as ferramentas de `rokit.toml` instaladas (`rojo`, `stylua`, `lune`):

```bash
./scripts/check.sh
```

Os testes correm sobre um motor simulado. Servem para apanhar erros de código cedo; não
substituem o teste no Studio.
