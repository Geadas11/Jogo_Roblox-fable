# Progresso — NIGHT SHIFT: SUPERMARKET

Legenda: `[ ]` por fazer · `[~]` em curso · `[x]` implementado · `[T]` implementado **e testado no Studio pelo dono do projeto**

Nada é marcado `[T]` sem confirmação de teste real.

## Fase 1 — Pré-produção
- [x] Análise técnica, roadmap, hierarquia, assets, plugins, dependências, limitações → `docs/01-pre-producao.md`
- [x] Decisões aprovadas: fluxo Rojo · 1ª pessoa fixa · jogo em inglês · experiência num grupo
- [ ] Regras da secção 1.4 (morte, entrada tardia, dificuldade, final alternativo) — propostas, por confirmar

## Fase 2 — Setup (build 0.2.0)
Verificado fora do Studio com `./scripts/check.sh` (compilação, build Rojo, 75 testes em motor simulado).
**Falta o teste no Studio** — lista em `docs/02-setup.md`, secção 4.
- [x] Projeto Rojo e estrutura de pastas
- [x] Config (`GameConfig`, `CollisionGroups`, `LightingConfig`) e Util (`Loader`, `Log`, `Signal`, `Trove`, `DeepFreeze`)
- [x] Net: catálogo de remotes, validação de argumentos, limite de frequência por jogador
- [x] SessionState (estado replicado por Attributes)
- [x] Bootstrap servidor / cliente com ordem de arranque explícita
- [x] Grupos de colisão (`CollisionService`) aplicados às personagens (`PlayerManager`)
- [x] Perfil base de Lighting (`EnvironmentService`) — valores por afinar na Fase 3
- [x] Câmara em 1ª pessoa (`CameraController`)
- [x] Testes automáticos e script de verificação
- [ ] Análise de tipos Luau (analisador não instalado neste ambiente)
- [ ] **Teste no Studio: A arranque · B dois jogadores · C segurança · D definições do place**

## Fase 3 — Ambiente
- [ ] Gerador de greybox
- [ ] Entrada · Loja · Caixas · Armazém · Sala dos funcionários · Escritório · Refrigeração · Casas de banho · Sala elétrica · Parque
- [ ] Tags e Attributes · nós de navegação · pontos CCTV · spawns

## Fase 4 — Jogabilidade base
- [ ] PlayerManager · GameManager · ShiftManager
- [ ] InteractionService · transporte de objetos
- [ ] TaskManager + tarefas
- [ ] HUD

## Fase 5 — Terror
- [ ] PowerManager · LightingController
- [ ] NoiseService · HidingService
- [ ] Monstro (estados, sentidos, pathfinding)
- [ ] EventManager + eventos
- [ ] Clientes NPC
- [ ] CCTV + anomalias

## Fase 6 — Apresentação
- [ ] Intro cinemática · menu principal
- [ ] Áudio dinâmico · animações
- [ ] Ecrã de morte · fim de turno

## Fase 7 — Progressão e polimento
- [ ] DataManager · progressão · cosméticos
- [ ] Definições · dificuldades · monetização · variações de turno

## Fase 8 — Testes
- [ ] Jogabilidade · multi-jogador · dados · desempenho · segurança · visual

## Fase 9 — Lançamento
- [ ] Ícone · miniaturas · descrição · tutorial · ecrã de carregamento · questionário de maturidade
