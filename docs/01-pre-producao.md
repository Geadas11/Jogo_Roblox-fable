# NIGHT SHIFT: SUPERMARKET — Pré-produção (Fase 1)

Estado: **aprovado.** Decisões fechadas: fluxo com Rojo; primeira pessoa fixa; texto e UI em
inglês; experiência publicada num grupo (animações e áudio têm de ser carregados com o grupo
como criador). As regras da secção 1.4 ficam como propostas até indicação em contrário.

Índice: [1. Análise técnica](#1-análise-técnica) · [2. Roadmap](#2-roadmap) ·
[3. Hierarquia do Explorer](#3-hierarquia-do-explorer) · [4. Assets](#4-assets-necessários) ·
[5. Plugins e ferramentas](#5-plugins-e-ferramentas) · [6. Sistemas e dependências](#6-sistemas-e-dependências) ·
[7. Ordem de implementação](#7-ordem-de-implementação) · [8. Limitações e soluções](#8-limitações-técnicas-e-soluções) ·
[9. Como começar](#9-como-começar)

---

## 0. O que eu posso e não posso fazer

Isto condiciona tudo o resto, por isso vem primeiro.

| | |
|---|---|
| **Não tenho acesso ao Roblox Studio.** | Trabalho neste repositório Git. Não consigo abrir o Studio, colocar Parts, carregar em Play, nem publicar. |
| **Não consigo verificar asset IDs.** | Áudio, animações, meshes e texturas têm de ser escolhidos/carregados por ti. Eu deixo "slots" com nome em `Config` e digo exatamente o que cada um precisa. Nunca vou escrever um ID inventado. |
| **Não consigo testar em jogo.** | Posso verificar o código estaticamente (lint, tipos) e correr testes unitários da lógica pura fora do Studio. Tudo o que depende do motor (pathfinding, luz, rede, DataStore) és tu que testas, com as checklists que eu forneço. Só marco algo como "testado" quando tu confirmares. |
| **O que entrego de facto** | Todo o código Luau, um gerador do mapa (ver 1.3), configuração do projeto, checklists de teste e instruções passo-a-passo para tudo o que tem de ser feito à mão no Studio. |

---

## 1. Análise técnica

### 1.1 Âmbito real

O documento de design descreve cerca de 20 sistemas interligados. O código é a parte mais
previsível. Os três riscos que decidem se o jogo parece "profissional" são outros:

1. **Arte do ambiente.** Um supermercado credível precisa de meshes (prateleiras, frigoríficos,
   carrinhos, caixas) e de dezenas de variações de produto. Com Parts consegue-se um layout
   jogável; a qualidade visual final exige modelação (Blender) ou assets verificados da Creator Store.
2. **Animações e o modelo do monstro.** Só funcionam animações carregadas pela conta (ou grupo)
   dona da experiência. São trabalho manual teu no Animation Editor ou Blender.
3. **Áudio.** O Roblox só deixa tocar áudio que seja teu, que te tenha sido concedido, ou áudio
   público da Creator Store. A seleção tem de ser feita e ouvida por ti no Studio.

Por isso o plano é: **primeiro tudo jogável com geometria simples e sem assets externos**,
depois substituir peça a peça por arte final, sem tocar na lógica.

### 1.2 Decisões de arquitetura

| Tema | Decisão | Porquê |
|---|---|---|
| Fluxo de trabalho | **Rojo** sincroniza `src/` do repositório para o Studio. O mapa vive no ficheiro `.rbxl`. | É a única forma de eu produzir a implementação real em vez de blocos de código para colar. Dá histórico Git. |
| Estrutura de scripts | **Um** `Script` no servidor e **um** `LocalScript` no cliente; tudo o resto são `ModuleScript`s com ciclo `Init()` → `Start()`. | Ordem de arranque determinística, sem corridas entre scripts. |
| Autoridade | Servidor decide tudo o que importa (tarefas, dano, recompensas, eventos, relógio). O cliente só pede e apresenta. | Requisito 20 do design. |
| Rede | Módulo `Net` único: cada remote tem validador de tipos, limite de frequência por jogador e verificação de distância/estado no servidor. | Impede spam e pedidos forjados num só sítio, em vez de validações espalhadas. |
| Estado partilhado | Estado global da ronda em **Attributes** de uma pasta em `ReplicatedStorage` (hora, energia por zona, dificuldade); listas (tarefas) por remote com *snapshot* inicial. | Attributes replicam sozinhos e resolvem a entrada tardia de jogadores sem código extra. |
| Marcação do mapa | **CollectionService tags + Attributes** (`Shelf`, `Spill`, `HidingSpot`, `CCTVCamera`, `LightFixture`, `PatrolNode`…). O código nunca procura objetos por nome/caminho. | Podes reconstruir ou embelezar o mapa sem partir scripts. |
| Câmara do jogador | **Primeira pessoa fixa.** | Terror funciona melhor; simplifica "o jogador está a olhar para X?" e a deteção. |
| UI | Construída **por código** em módulos de cliente, com um tema central (`UITheme`). `StarterGui` fica praticamente vazio. | Versionável em Git, consistente, e eu não consigo desenhar no Studio. Desvio consciente da hierarquia sugerida. |
| IA do monstro | Máquina de estados em módulos (um por estado) + `PathfindingService`; dono de rede = servidor; tick adaptativo (mais lento quando ninguém está perto). | Requisitos 9 e 28. |
| Dados | `DataManager` próprio: `UpdateAsync`, *session lock*, repetição com espera crescente, versão de esquema, e **nunca grava se o carregamento falhou**. | Sem dependências externas. Alternativa madura se preferires: ProfileStore (open-source). |
| Definições | Guardadas no perfil do jogador (DataStore). | O Roblox não tem armazenamento local no cliente; "guardar localmente" não é possível. |
| Duração | 6 horas × 4 min = **24 min** por turno, configurável. | Dentro dos 20–30 min pedidos. |

### 1.3 Como o mapa é construído

Três camadas:

1. **Gerador de greybox** (`map/`, corrido por `tools/build.luau`): cria o edifício completo com
   Parts — todas as áreas, corredores, portas, pontos de patrulha, câmaras, esconderijos — já com
   tags e Attributes, e grava-o diretamente no ficheiro do place. (O plano inicial era correres um
   script na Command Bar; gerar o ficheiro do meu lado poupa-te esse passo e deixa-me verificar o
   resultado antes de to entregar.)
2. **Dressing manual**: substituis os blocos por meshes/modelos, mantendo as tags.
3. **Detalhe ambiental**: decalques, sujidade, cartazes, pistas da história.

Assim a Fase 3 produz um layout jogável real e a lógica pode avançar sem esperar pela arte.

### 1.4 Regras de jogo que o design deixa em aberto (proposta)

- **Morte em co-op:** o jogador apanhado fica em modo espectador e regressa na mudança de hora
  seguinte, se houver pelo menos um colega vivo. Todos mortos = turno falhado.
- **Morte a solo:** uma "segunda oportunidade" por turno em Easy/Normal, nenhuma em Hard/Nightmare.
- **Entrada tardia:** entra diretamente na sala dos funcionários; recompensa proporcional ao tempo jogado.
- **Dificuldade:** votada no lobby antes do turno; o anfitrião do servidor privado decide.
- **Final "o turno não acabou":** variação rara (configurável) em que às 6:00 as portas não abrem e
  há uma hora extra curta. Só depois de o jogador já ter completado pelo menos um turno normal.

---

## 2. Roadmap

Cada fase só fecha quando o critério de saída for verificado **por ti no Studio**.

| Fase | Entregáveis | Critério de saída |
|---|---|---|
| **1. Pré-produção** | Este documento; checklist de progresso. | Aprovas as decisões das secções 1.2–1.4. |
| **2. Setup** | Projeto Rojo; pastas; `Config`; `Net` + remotes; bootstrap servidor/cliente; grupos de colisão; perfil base de `Lighting`; lint/formatador. | Rojo liga, Play arranca sem erros no Output, os dois lados imprimem "pronto". |
| **3. Ambiente** | Gerador de greybox; 9 áreas navegáveis; spawns; nós de patrulha; iluminação base por zona. | Percorre-se o mapa todo a pé; nenhuma colisão em falta; navmesh cobre o interior. |
| **4. Jogabilidade base** | Interações; `ShiftManager` (relógio); `TaskManager` + 6–8 tarefas; HUD; transporte de objetos; sincronização multi-jogador. | Um turno completo sem terror, a solo e com 2 jogadores (Test → Start Server). |
| **5. Terror** | Monstro + IA; deteção (visão/som/proximidade); esconderijos; `EventManager`; clientes NPC; CCTV; sistema elétrico. | Monstro patrulha, investiga, persegue e perde o rasto; a falha de energia das 4:00 é reparável a solo. |
| **6. Apresentação** | Introdução cinemática; progressão de luz por hora; áudio dinâmico; animações; ecrã de morte; cinemática de fim de turno; menu principal. | Sessão completa menu → intro → turno → resultados sem placeholders visíveis. |
| **7. Progressão e polimento** | DataStore; XP/níveis/patentes; cosméticos; definições; dificuldades; monetização; variações de turno. | Dados persistem entre sessões; falha simulada de DataStore não apaga progresso. |
| **8. Testes** | Checklists da secção 29 do design executadas; correção de bugs; perfil de desempenho. | 6 jogadores, emulação móvel, tentativas de exploit — tudo registado em `PROGRESS.md`. |
| **9. Lançamento** | Ícone, miniaturas, descrição, tutorial, ecrã de carregamento, questionário de maturidade, definições finais. | Experiência pública. |

---

## 3. Hierarquia do Explorer

`[Rojo]` = gerido pelo repositório. `[Studio]` = vive no ficheiro do place.

```
ReplicatedStorage
├── Shared                         [Rojo]  src/shared
│   ├── Config
│   │   ├── GameConfig             duração, nº jogadores, regras de morte
│   │   ├── HourConfig             o que cada hora desbloqueia (luz, eventos, monstro)
│   │   ├── DifficultyConfig       multiplicadores por dificuldade
│   │   ├── TaskDefinitions        catálogo de tarefas (dados, não lógica)
│   │   ├── EventDefinitions       catálogo de eventos de terror
│   │   ├── MonsterConfig          sentidos, velocidades, tempos por estado
│   │   ├── ProgressionConfig      curva de XP, patentes, desbloqueios
│   │   ├── AudioConfig            slots de som → asset ID (preenchidos por ti)
│   │   └── AnimationConfig        slots de animação → asset ID (preenchidos por ti)
│   ├── Net
│   │   ├── Definitions            catálogo de todos os remotes
│   │   └── Check                  validadores de argumentos
│   ├── SessionState               estado da sessão (Attributes em ReplicatedStorage.State)
│   └── Util                       Loader, Log, Signal, Trove, DeepFreeze (+ o que for preciso)
├── Remotes                        criados pelo servidor no arranque
│   ├── Events
│   └── Functions
├── State                          Attributes replicados da ronda
└── Assets                         [Studio]
    ├── Models / Audio / Animations / UI

ServerScriptService
└── Server                         [Rojo]  src/server
    ├── Main (Script)              único ponto de entrada
    ├── Net (+ Gate, RateLimiter)  cria os remotes; valida e limita pedidos dos clientes
    └── Services
        ├── CollisionService       grupos de colisão
        ├── EnvironmentService     iluminação base; verificação de definições do place
        ├── GameManager            lobby ↔ turno ↔ resultados
        ├── ShiftManager           relógio, transições de hora
        ├── PlayerManager          estado por jogador, spawn, morte, espectador
        ├── InteractionService     valida todas as interações
        ├── TaskManager  +  Tasks/ um módulo por tipo de tarefa
        ├── PowerManager           zonas, disjuntores, falhas
        ├── NoiseService           ruído gerado por jogadores → monstro
        ├── MonsterManager + States/  um módulo por estado da IA
        ├── CustomerManager + Behaviors/
        ├── EventManager + Events/ um módulo por evento
        ├── SecurityManager        CCTV e anomalias
        ├── HidingService
        ├── ProgressionService     XP, dinheiro, recompensas
        ├── DataManager            DataStore
        └── MonetizationService    passes e produtos

ServerStorage                      [Studio]
├── Monsters / NPCs / Tools / MapAssets

StarterPlayer
├── StarterPlayerScripts
│   └── Client                     [Rojo]  src/client
│       ├── Main (LocalScript)
│       ├── Net                        acesso do cliente aos remotes
│       ├── Controllers
│       │   ├── CameraController       1ª pessoa, abanão, esconderijo
│       │   ├── InteractionController
│       │   ├── LightingController     perfis por zona/hora, tremeluzir
│       │   ├── AudioController        camadas dinâmicas, SoundGroups
│       │   ├── CinematicController    intro, morte, fim de turno
│       │   ├── CCTVController
│       │   ├── EffectsController      eventos locais de terror
│       │   └── SettingsController
│       └── UI
│           ├── UITheme
│           ├── MainMenu / HUD / TaskList / CCTVView
│           ├── SettingsMenu / DeathScreen / ResultsScreen / Subtitles
└── StarterCharacterScripts        (vazio; lógica do personagem fica nos Controllers)

Workspace
├── Map                            [gerado por map/ — não editar à mão]
│   ├── Structure                  chão, paredes, tetos, portas, montras
│   ├── ShopFloor / Storage / Maintenance / Electrical / ColdStorage
│   ├── StaffCorridor / Office / EmployeeRoom / BathroomA / BathroomB
│   ├── Exterior                   parque, traseiras, becos, limites
│   ├── Lights                     luzes de teto por zona
│   └── Markers                    zonas, patrulha, clientes, tarefas, CCTV, spawns
├── NPCs                           criados em runtime
└── Monster                        criado em runtime
```

Acrescentei em relação à tua sugestão: `ElectricalRoom` (a fase das 4:00 precisa de um destino
físico), `NoiseService`, `HidingService`, `InteractionService`, `ProgressionService`,
`CollisionService`, `EnvironmentService`, `LightingController` e a pasta `State`.

Os tipos Luau ficam junto do módulo que os define, em vez de num módulo `Types` central. A parte
do `Net` que valida pedidos vive no servidor, para não ser replicada para os clientes.

---

## 4. Assets necessários

Nenhum ID está escolhido. Coluna "Quem": **Tu** = tens de criar/carregar/escolher; **Código** = eu gero sem asset.

### Modelos 3D
| Asset | Quem | Nota |
|---|---|---|
| Edifício, paredes, chão, teto | Código (greybox) → Tu (dressing) | |
| Prateleiras (3–4 variantes), frigoríficos, arcas, caixas registadoras, carrinhos, cestos | Tu | Blender ou Creator Store verificada, sem scripts |
| Produtos (15–25 embalagens distintas) | Tu | Podem ser caixas com texturas diferentes |
| Mobiliário (cacifos, mesas, secretária, monitores, micro-ondas, máquina de venda) | Tu | |
| Carros, candeeiros de rua, contentores | Tu | |
| **O Cliente** (monstro) | Tu | Rig R15 com proporções alongadas é o caminho mais barato; rig próprio dá melhor resultado |
| NPCs clientes (4–6 aparências) | Código | `HumanoidDescription` com roupa do catálogo |

### Texturas
Azulejo de chão, teto falso, parede pintada, metal, cartão, vidro sujo (PBR via `SurfaceAppearance`
ou `MaterialVariant`); cartazes, etiquetas de preço, logótipo da loja, documentos da história (decalques). **Tu.**

### Animações (todas **Tu**; têm de pertencer à conta/grupo dono da experiência)
- Jogador: agachar, esconder, pegar, repor, limpar, usar computador, ser apanhado. Andar/correr usam as predefinidas do Roblox.
- Monstro: parado, andar, correr, olhar em volta, investigar, atacar (2–3 variantes).
- NPC: andar (predefinida), examinar prateleira, pegar em produto.
- **Sem asset:** a rotação lenta da cabeça do monstro e o "ficar imóvel" faço por código (Motor6D do pescoço).

Explico o processo de criação e upload na Fase 6. Até lá o jogo funciona sem elas.

### Áudio (todos **Tu**, a partir da Creator Store ou originais)
- Ambiente: zumbido fluorescente, frigoríficos, ventilação, chuva, trânsito distante, estalidos do edifício.
- Interação: portas, carrinho, colocar produto, caixa a cair, registadora, esfregona, passos por superfície.
- Terror: passos distantes, respiração, arranhar, sussurros, impacto metálico, anúncio distorcido, vocalizações do monstro.
- Música: drone ambiente, camada de tensão, perseguição, intro, fim de turno.

### UI
Ícones (tarefa, energia, câmara, esconder), logótipo/título, ruído estático de CCTV. Tipos de letra:
só os incluídos no Roblox (`Enum.Font` / `Font.fromName`).

### Loja
Ícone 512×512, 3+ miniaturas 1920×1080, passes e produtos criados no Creator Dashboard.

---

## 5. Plugins e ferramentas

| Ferramenta | Necessária? | Para quê |
|---|---|---|
| **Rojo** (plugin do Studio + executável) | **Sim** | Sincronizar o código deste repositório. Open-source, muito usado. Gratuito. |
| **Git** | Sim | Já em uso. |
| VS Code + extensão Luau LSP | Recomendado | Se quiseres ler/editar o código com erros de tipo assinalados. |
| Selene, StyLua | Do meu lado | Lint e formatação; não precisas de instalar. |
| Animation Editor (incluído no Studio) | Sim, na Fase 6 | Animações. Suficiente para o que precisamos. |
| Blender | Opcional | Meshes próprias e, se quiseres, o monstro. |
| Moon Animator 2 | **Não recomendo por agora** | É pago. A intro é feita com câmara por script; o editor incluído chega para os personagens. Reavaliar só se o Animation Editor se revelar limitativo. |
| Plugins de construção (Archimedes, GapFill, etc.) | Opcional | Úteis no dressing manual. Verifica autor e listagem antes de instalar; nada no projeto depende deles. |

Nada disto envolve compras. Não instalo nem recomendo instalar mais nada sem te perguntar.

---

## 6. Sistemas e dependências

| # | Sistema | Depende de | Notas |
|---|---|---|---|
| 1 | Config / Types / Util | — | Base de tudo |
| 2 | Net (remotes + validação) | 1 | |
| 3 | PlayerManager | 1, 2 | Estado: vivo, escondido, a transportar, morto |
| 4 | GameManager (sessão) | 3 | Lobby, início, fim, saída de jogadores |
| 5 | ShiftManager (relógio) | 4 | Emite `HourChanged`; quase tudo o resto escuta |
| 6 | InteractionService | 2, 3 | Distância, linha de vista, cooldown |
| 7 | TaskManager | 5, 6 | Sorteia do catálogo por hora e nº de jogadores |
| 8 | HUD / TaskList | 2, 5, 7 | |
| 9 | PowerManager | 5, 6 | Zonas → luzes, frigoríficos, CCTV, portas |
| 10 | LightingController | 5, 9 | Perfis por zona e hora |
| 11 | NoiseService | 3, 6 | Correr, deixar cair, portas |
| 12 | HidingService | 3, 6 | |
| 13 | MonsterManager | 3, 5, 9, 11, 12, navegação do mapa | O sistema mais complexo |
| 14 | CustomerManager | 5, navegação | Partilha utilitários de pathfinding com 13 |
| 15 | EventManager | 5, 9, 13 (estado), 14 | Orçamento de tensão + cooldowns |
| 16 | SecurityManager / CCTV | 9, 15 | |
| 17 | AudioController | 5, 13, 15 | Intensidade segue o estado do monstro |
| 18 | CinematicController | 4, 10, 17 | Intro, morte, fim |
| 19 | DataManager | 3 | |
| 20 | ProgressionService | 7, 19 | |
| 21 | Dificuldade | atravessa 7, 13, 15 | Só dados em `DifficultyConfig` |
| 22 | Definições | 19, 10, 17 | |
| 23 | Monetização | 19, 20 | Só cosmético |

---

## 7. Ordem de implementação

1. Projeto Rojo, `Config`, `Util`, `Net`, bootstrap (Fase 2)
2. Gerador de greybox + tags (Fase 3)
3. `PlayerManager` → `GameManager` → `ShiftManager` + relógio no HUD
4. `InteractionService` + transporte de objetos
5. `TaskManager` com 2 tarefas (repor, limpar) → validar o ciclo → restantes tarefas
6. `PowerManager` + `LightingController`
7. `NoiseService`, `HidingService`
8. Monstro: patrulha → sentidos → investigar/procurar → perseguir/atacar → esconderijos
9. `EventManager` com eventos de baixa intensidade → restantes
10. Clientes NPC (normais → estranhos)
11. CCTV + anomalias
12. Áudio dinâmico, intro, morte, fim de turno, menu
13. DataStore → progressão → definições → dificuldades → monetização
14. Testes sistemáticos, otimização, lançamento

O monstro vem depois da energia, do ruído e dos esconderijos porque a IA consome os três.

---

## 8. Limitações técnicas e soluções

| Limitação do Roblox | Solução |
|---|---|
| **Não há render-to-texture.** Um monitor não pode mostrar uma câmara ao vivo com iluminação real. | Ao usar o computador, a câmara do jogador passa para o ponto CCTV, com overlay (grão, linhas, timestamp, nome). Os monitores decorativos mostram estática. `ViewportFrame` fica de fora: não tem sombras nem luz e duplica geometria. |
| **Anomalias só visíveis nas câmaras**, sem inconsistência entre jogadores. | O servidor decide (câmara, tipo, janela de tempo, posição). Cada cliente que esteja nessa câmara cria a figura localmente. Todos os observadores veem o mesmo; quem está no local não vê nada. |
| **Não há espelhos/reflexos reais.** | Casa de banho com sala espelhada duplicada atrás do vidro para um evento específico, ou espelhos sujos com silhueta. Decidir na Fase 5 conforme o custo. |
| **Não há API para saber "quão iluminado" está um ponto.** | Nível de luz por zona (Attribute mantido pelo `PowerManager`) + lanterna ligada/desligada entram na fórmula de visibilidade. |
| **"Mover objetos quando ninguém olha".** | Com 1ª pessoa, o servidor estima o campo de visão pela orientação da cabeça + raycast. É só cosmético, por isso a imprecisão é aceitável. |
| **Pathfinding falha ou encrava** (portas, cantos apertados). | `PathfindingModifier` nas portas, recálculo limitado no tempo, deteção de bloqueio com replaneamento, e recurso a nós de patrulha. O monstro nunca se teletransporta para perto de jogadores. |
| **Luzes com sombra são caras**, sobretudo em telemóvel. | Tubos fluorescentes como Parts `Neon` + poucas `SurfaceLight` por zona; sombras só em luzes-chave; níveis de qualidade reduzem luzes ativas. Tremeluzir corre no cliente com semente do servidor. |
| **`Lighting.Technology` foi substituído** por `LightingStyle` + `PrioritizeLightingQuality`. | Confirmado na Fase 2: o antigo `Future` equivale a `Realistic` + qualidade prioritária. É isso que o perfil base pede; se o Studio não deixar escrever por script, define-se à mão (ver `02-setup.md`). |
| **Privacidade de áudio e posse de animações.** | Slots em `AudioConfig`/`AnimationConfig`; slot vazio = sistema continua a funcionar em silêncio/sem animação, com aviso no Output. |
| **Oclusão de áudio** não é automática nos `Sound` clássicos. | Raycast entre ouvinte e monstro → filtro passa-baixo. Avaliar a nova API de áudio na Fase 6. |
| **DataStore não funciona em Studio** sem "Enable Studio Access to API Services", nem em places não publicados. | Instruções na Fase 7; modo simulado em memória para desenvolvimento. |
| **StreamingEnabled** pode fazer com que objetos não existam no cliente quando um script os procura. | Ligado, com modelos críticos marcados como `Persistent`; clientes reagem a tags (`GetInstanceAddedSignal`) em vez de assumir que tudo existe. |
| **Chamar o nome do jogador.** | Só texto com `DisplayName` em legendas do intercomunicador. Sem voz sintetizada, sem dados privados. |
| **Maturidade do conteúdo.** Terror afeta a classificação e quem pode jogar. | Sem sangue nem violência gráfica; preencher o questionário com rigor na Fase 9. |
| **Telemóvel.** | Interações por `ProximityPrompt` (toque nativo), botões de correr/agachar/lanterna no ecrã, UI com `UIScale` e zonas seguras. |

---

## 9. Como começar

A Fase 1 está fechada. A Fase 2 está implementada: instruções de ligação e lista de verificação
em [`02-setup.md`](02-setup.md).
