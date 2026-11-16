# Progresso — NIGHT SHIFT: SUPERMARKET

Legenda: `[ ]` por fazer · `[~]` em curso · `[x]` implementado · `[T]` implementado **e testado no Studio pelo dono do projeto**

Nada é marcado `[T]` sem confirmação de teste real.

## Fase 1 — Pré-produção
- [x] Análise técnica, roadmap, hierarquia, assets, plugins, dependências, limitações → `docs/01-pre-producao.md`
- [x] Decisões aprovadas: fluxo Rojo · 1ª pessoa fixa · jogo em inglês · experiência num grupo
- [ ] Regras da secção 1.4 (morte, entrada tardia, dificuldade, final alternativo) — propostas, por confirmar

## Fase 2 — Setup (build 0.2.0)
Verificado fora do Studio (compilação, build Rojo, testes em motor simulado).
O dono do projeto abriu a pré-visualização no Studio e aprovou ("gostei como está").
- [x] Projeto Rojo e estrutura de pastas
- [x] Config (`GameConfig`, `CollisionGroups`, `LightingConfig`) e Util (`Loader`, `Log`, `Signal`, `Trove`, `DeepFreeze`)
- [x] Net: catálogo de remotes, validação de argumentos, limite de frequência por jogador
- [x] SessionState (estado replicado por Attributes)
- [x] Bootstrap servidor / cliente com ordem de arranque explícita
- [x] Grupos de colisão (`CollisionService`) aplicados às personagens (`PlayerManager`)
- [x] Perfil base de Lighting (`EnvironmentService`)
- [x] Câmara em 1ª pessoa (`CameraController`)
- [x] Testes automáticos e script de verificação
- [T] Arranque no Studio (visto e aprovado pelo dono do projeto)
- [ ] Testes no Studio não confirmados individualmente: dois jogadores · segurança (pedidos forjados e spam) · máximo de 6 jogadores
- [ ] Análise de tipos Luau (analisador não instalado neste ambiente)

## Fase 3 — Ambiente (build 0.3.0)
Verificado fora do Studio com `./scripts/check.sh`: o place é gerado, relido e todos os pontos são alcançáveis a pé numa simulação.
**Falta o teste no Studio** — lista em `docs/03-ambiente.md`, secção 3.
- [x] Gerador do mapa (`map/`) e construção do place (`tools/build.luau` → `releases/NightShiftSupermarket.rbxl`)
- [x] Entrada · Loja · Caixas · Armazém · Manutenção · Sala elétrica · Câmara fria e congelador
- [x] Corredor do pessoal · Escritório · Sala dos funcionários · Casas de banho
- [x] Parque de estacionamento · Traseiras · Becos · Limites · Mundo ao longe
- [x] Tags e Attributes (`Config/Tags`) · zonas · pontos de patrulha e de clientes · pontos de tarefas
- [x] 8 câmaras de segurança · 6 spawns · 63 luzes com zona e circuito
- [x] Verificação automática de caminhabilidade e planta (`docs/floor-plan.svg`)
- [T] Teste no Studio pelo dono do projeto: mapa percorrido, luz e escala aprovadas
- [x] Correção (build 0.3.1): os tetos eram atravessáveis ao saltar — agora são sólidos; letreiros suspensos subidos — **por confirmar no Studio**
- [ ] Dressing (meshes, texturas, detalhe ambiental) — depois da jogabilidade base

## Fase 4 — Jogabilidade base
Verificado fora do Studio (testes sobre o mapa real em motor simulado). **Falta o teste no Studio.**

Parte A (build 0.4.0) — sessão e interações
- [x] `InteractionService`: prompts criados só pelo servidor; valida distância, estado do jogador e ritmo
- [x] `DoorService`: portas abrem e fecham (a saída de emergência fica trancada)
- [x] `GameManager`: Lobby → Turno → Resultados → Lobby; o turno começa ao picar o ponto
- [x] `ShiftManager`: relógio das 12 AM às 6 AM, uma hora de cada vez
- [x] HUD: relógio, estado, notificações, resumo do fim de turno
- [T] Teste no Studio pelo dono do projeto (portas, picar o ponto, relógio)

Parte B (build 0.4.1) — tarefas
- [x] `CarryService`: transporte de um objeto de cada vez; largar com G / botão
- [x] `ToolService`: esfregonas na manutenção
- [x] `TaskManager` + tarefas: repor prateleiras, limpar derrames, verificar frigoríficos
- [x] Lista de objetivos e indicador de transporte no HUD; resumo do turno com tarefas e dinheiro
- [T] Teste no Studio pelo dono do projeto: turno a solo, tarefas e transporte aprovados; teto confirmado

Parte C (build 0.4.3) — seguimento do teste
- [x] Terminar o turno mais cedo no relógio de ponto (*Clock out*; em equipa, por voto unânime) — pedido no teste: "não sei onde acabar o turno"
- [x] O HUD e a mensagem de início dizem que o turno acaba às 6 AM; o resumo mostra a hora real de saída
- [x] Tarefas novas: levar o lixo aos contentores, fechar as caixas registadoras
- [x] Tarefas "ir ver N coisas" passam a ser configuração (`Inspect` + `Params`)
- [ ] **Teste no Studio (parte C)**: Clock out · as duas tarefas novas
- [ ] **Teste no Studio com dois jogadores** (nunca confirmado)
- [ ] Tarefas ainda em falta: carrinhos abandonados, entregas, inventário (as de manutenção vêm com a Fase 5)

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
