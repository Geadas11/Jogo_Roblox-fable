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
Parte A (build 0.5.0) — o monstro. Verificado fora do Studio. **Falta o teste no Studio** — `docs/05-terror.md`, secção 3.
- [x] Grelhas de navegação e visão calculadas no build (`tools/grids.luau` → `ServerStorage`)
- [x] `NavGrid`: A* e linha de vista exatos, célula a célula
- [x] `Brain`: patrulha, observar, investigar, procurar, perseguir, apanhar, desaparecer
- [x] `MonsterManager`: aparece às 3 AM longe e fora da vista; abre portas; fica mais rápido por hora
- [x] Corpo desenhado no cliente e movido suavemente; pose procedural
- [x] `NoiseService`: correr, portas batidas, objetos largados
- [x] `HidingService`: 9 esconderijos (cacifos, secretária, cabines)
- [x] `SurvivalService`: segunda oportunidade a solo, espectador em equipa, turno falhado
- [x] Correr com estamina; sinais de perigo no ecrã; sequência de captura (3 variações)
- [ ] **Teste no Studio (parte A)**

Parte B (build 0.5.1) — energia e luz. Verificado fora do Studio. **Falta o teste no Studio.**
- [x] `PowerManager`: 5 circuitos + emergência, disjuntores, gerador, falhas aleatórias e a falha das 4 AM
- [x] Tarefa *Restore the power* criada automaticamente em cada falha
- [x] `LightingController`: luzes por circuito, escurecer por hora, tremeluzir, tom vermelho em falha
- [x] Lanterna (`FlashlightService`, tecla F / botão LIGHT); o escuro reduz a visão do monstro, a lanterna denuncia
- [ ] **Teste no Studio (parte B)**

Revisão (build 0.5.2) — auditoria do código contra o prompt original. Testes automáticos **não corridos** (lune/rojo não instalados nesta máquina).
Playtest no Studio feito pelo Claude (1 jogador, código copiado para o place de `releases/`), confirmado: compila; turno arranca; limpar derrame; G faz barulho e esconder com esfregona não; escondido 45 s → o monstro foi ao esconderijo e apanhou; segunda oportunidade a solo; descrição da energia atualiza (disjuntor → falha geral → gerador → disjuntores); esfregona perdida volta no fim do turno; sem erros na consola.
- [x] Avisos de arranque `LightingStyle` / `PrioritizeLightingQuality` eliminados (só o Studio pode escrever essas propriedades; o servidor deixa de tentar quando já estão certas)
- [x] Esconder-se com um objeto na mão já não faz barulho (antes atraía o monstro direto ao esconderijo); objetos perdidos ao ser apanhado ou ao sair também não
- [x] Esconder-se deixou de ser seguro para sempre: quem fica escondido 45 s com o monstro na loja atrai-o ao esconderijo (`MonsterConfig.Behaviour.LongHideSeconds`, `Brain:Suspect`) + teste novo em `brain.spec`
- [x] *Clock out* em equipa: jogadores apanhados (a assistir) já não contam para o voto e não bloqueiam o fim do turno
- [x] A tarefa *Restore the power* atualiza a descrição em tempo real (ex.: um disjuntor caiu e depois veio a falha das 4 AM)
- [x] Tarefas que não conseguem arrancar limpam o que deixaram no mundo
- [x] As esfregonas voltam à manutenção no início de cada turno (antes uma esfregona perdida podia impedir limpar derrames)
- [ ] **Por testar (revisão 0.5.2)**: *Clock out* com dois jogadores, um deles apanhado (precisa de teste com 2 jogadores)

Build 0.6.0 — som, eventos, menu, detalhe gráfico. Testes: 233 passam; 1 falha só de tempo (`navgrid`, ~60 ms vs limite 45 ms nesta máquina; grelha idêntica à anterior).
Playtest no Studio pelo Claude (1 jogador): sem erros na consola; 19 sons carregam; aviso → menu → definições → multiplayer; slider de música altera o volume e é guardado no servidor; lanterna; nevoeiro na falha de energia; 9 eventos disparam (carrinho corrigido depois do teste).
- [x] Som: ambiente (zumbido, chuva, frigoríficos, camada de medo que cresce por hora), passos e presença do monstro, tensão/perseguição/stinger, sons de eventos — só parceiros licenciados (Pro Sound Effects, APM, DistroKid) → `Config/AudioConfig`
- [x] `EventManager`: luzes a tremer, apagão local, batidas, passos atrás de ti, porta que bate/aparece aberta, intercomunicador com texto distorcido, silhueta que foge quando olhada, produto que cai, carrinho que rola fora de vista. Nada às 12 AM; mais frequente por hora; silêncio propositado; pausa durante perseguições → `Config/EventConfig`
- [x] HUD: canto inferior direito com o que tens na mão e teclas (G largar, F lanterna, Shift correr); mira; prompts próprios (tecla + ação + barra de segurar), notificações e descrições já não são cortadas
- [x] Aviso inicial, menu principal (Single player / Multiplayer / How to play / Settings) com câmara cinematográfica; Single player = servidor privado (só no jogo publicado)
- [x] Definições: volumes (geral, música, ambiente, efeitos), sensibilidade, tremer de câmara, reduzir flashes; guardadas em DataStore (só no jogo publicado), tecla P durante o jogo
- [x] Nevoeiro escuro quando a zona onde estás fica sem luz; lanterna a seguir a câmara
- [x] Mapa: rótulos/tampas/gargalos em garrafas, latas e frascos, rótulos nas caixas, fruta com brilho, pés e variação, máquina de vending detalhada (9 422 peças no total)
- [ ] **Por confirmar a olho por ti**: prompts personalizados (a captura do Studio não mostra BillboardGuis), luz interior da vending (última correção), silhueta, intercomunicador, som em geral
- [ ] Single player e gravação de definições só funcionam no jogo publicado

Build 0.6.x (em curso) — 238 testes passam (navgrid só por tempo). **Ainda sem playtest no Studio.**
- [x] Andar 8 / correr 16, stamina 4,5 s, sem salto
- [x] Animações procedurais próprias (andar, correr, respirar, levar caixas) para jogadores R15/R6 e NPCs; corpo visível em 1.ª pessoa; balanço de câmara
- [x] Acordar sentado à mesa (piscar, levantar) após o menu
- [x] Prompt: contorno que enche dos dois lados; vista própria ao esconder (cacifo / secretária / cabine); cursor escondido a jogar
- [x] Marcas inventadas + ícones nos rótulos, preços nas prateleiras (verificado em captura)
- [x] Clientes NPC 12–2 AM (passeiam, caixas, saem; um pode ficar a olhar e desaparecer)
- [x] Monstro: corpo R15 do Roblox (alto, magro, gabardina, cara desenhada) — modelos da Creator Store rejeitados (um tinha backdoor)
- [x] Rótulos impressos na própria embalagem (caixas sem peça extra: −1 850 peças); nos frascos/latas a impressão fica ao centro da face (o Roblox não curva SurfaceGuis)
- [x] Tarefas cinematográficas: cartão de hora com barras de cinema, cartões "NEW TASK"/"TASK COMPLETE", prateleira enche nível a nível, derrame encolhe, luz de inspeção fica verde
- [x] Correções do playtest: avatares novos usam AnimationConstraint (não Motor6D) — animador suporta os dois; poses aplicadas em PreSimulation (o Animator repunha-as); `task` escondido por parâmetro em Inspect; impressões a flutuar em prateleiras vazias
- [T*] Playtest pelo Claude (1 jogador, Studio à frente): acordar (≈4 s, termina de pé à mesa), cliente NPC a andar animado, monstro novo, marcas e preços. *Não vistos*: prompts e vistas de esconderijo (a captura do Studio não mostra BillboardGui), corpo em 1.ª pessoa a olhar para baixo, cartões de hora
- [x] Cilindros: impressão sempre virada para o cliente e direita (dos dois lados do corredor), numa faixa central estreita para não flutuar — verificado no Studio dos dois lados do corredor
- [x] Mais realismo: caixas de reserva em cima das gôndolas, etiquetas SALE vermelhas, cartões salientes nas prateleiras, placas de piso molhado
- [x] Respiração ofegante com pouca stamina, "gasp" quando acaba, recuperar o fôlego (sons Pro Sound Effects) — testado a jogar: começa ao esgotar e acalma em ~8 s
- [x] Passos de todas as personagens, ao ritmo do andar/correr, posicionais (som de passos do próprio Roblox; os padrão ficam mudos) — testado
- [x] Eco suave (ReverbSoundEffect) nos efeitos dentro da loja
- [x] Música de terror no menu (APM "Unsure of Anything (B)"), desvanece ao entrar — testado
- [x] Interface de terror: letra Special Elite, cores dessaturadas, painéis com contorno vermelho-escuro, vinheta permanente, título do menu a tremeluzir — visto no Studio
- [x] Monstro = antigo funcionário: camisa amarela de manga curta, avental azul (peito + saia) com manchas de sangue a escorrer, crachá "HELLO, MY NAME IS WALTER" riscado, mãos ensanguentadas, olhos com olheiras vermelhas, boca aberta com dentes amarelados tortos e sangue a escorrer pelo queixo — visto em jogo no Studio
- [x] Máquina de venda: a luz sai só pelo vidro (5 tiras escondidas atrás das etiquetas, viradas para dentro, alcance curto), sem PointLights a iluminar paredes/chão — visto em jogo no Studio
- [x] Correções: ecrã de resultados já não fica tapado pela captura; candeeiros das caixas apagam no apagão; repor a luz no fim do turno já não conta como tarefa
- [x] Câmara: o bloqueio do rato em 1.ª pessoa é reposto a cada frame sempre que não há menu aberto (já não é preciso o botão direito) — testado: libertado à força, volta a LockCenter
- [x] Andar: balanço da cabeça bem mais visível (sobe/desce com a passada, afunda a cada pé, inclina de lado), mais forte a correr
- [x] Passos: a correr, um baque por cada pé a bater no chão, em sincronia com as pernas (≈3.7/s), mais som de sapatos mais alto e mais rápido; a andar fica o som suave
- [x] Sons mais baixos (grupos Ambient 0.7, Music 0.6, Effects 0.75); zumbido das lâmpadas ("ventilador") muito mais baixo; compressores só se ouvem perto
- [x] Ambiente variado: rangidos, o prédio a assentar, janelas/vidros a vibrar, trovões lá fora, pingos num balde, metal, arrastar ao longe — aleatórios a cada 10–28 s, à volta do jogador (Pro Sound Effects)
- [x] Esconder debaixo da secretária: sem nada a tapar o ecrã; o corpo fica sentado no chão encolhido (pose medida: cabe entre o chão e o tampo), virado para fora, olhos a 2.17 — testado em números; a captura 3D do Studio estava congelada nesta sessão
- [x] Chat começa fechado (continua acessível no botão do chat)
- [x] Teste completo no Studio: aviso sem chat, acordar, câmara presa, balanço (andar 0.16 / correr 0.43, inclinação 0.7°/1.7°), 4.3 passos/s a correr, sons novos todos carregam e tocam, vista debaixo da secretária (vista em imagem), turno, perseguição → apanhado → 2.ª oportunidade → apanhado → fim do turno, sem erros na consola
- [x] Produtos novos (map/Products.luau), modelos próprios: caixas de cereais (marca grande, tigela, "NEW!"), garrafas de vidro (líquido, ombro, gargalo, tampa), garrafas de plástico (água, cola, sumo), frascos com conteúdo e tampa, pacotes de leite com telhado, jarros com pega, sprays, champô, sacos de batatas com selagens, sacos dobrados, comida de animais, latas (empilhadas), iogurtes, rolos de papel higiénico em película, caixas pequenas/planas empilhadas; stock atrás da 1.ª fila nas caixas; paletes com caixas de cartão impressas; frigoríficos com leite/iogurtes
- [x] Portas dos frigoríficos e tampas das arcas em plástico transparente (o material Glass escondia os rótulos)
- [x] Desempenho: 15k peças no mapa; produtos custam ~1.8 ms/frame no Studio (rótulos até 16 studs, resolução menor, sem material Glass) — antes da otimização eram ~4 ms
- [x] Reposição: vidro/plástico voltam com a sua transparência (atributo Alpha); pausa entre prateleiras ajustada
- [x] Portas a rodar nas dobradiças (eixo calculado das duas poses; a do escritório deixou de girar à volta do meio da sala) + dobradiças visíveis
- [x] Lanterna com F sozinho (e P / Espaço / largar): só bloqueadas quando se escreve numa caixa de texto
- [x] Balanço da cabeça a correr mais suave
- [x] Aviso inicial com fade in/out automático (~6,5 s), sem botão
- [x] Debaixo da secretária a câmara começa virada para a porta da sala
- [x] Passos: o baque pesado passou para o monstro; os do jogador a correr ficaram leves
- [x] Saco do lixo a sério: corpo largo em baixo e irregular, gargalo franzido, nó, pontas do plástico caídas e laço amarelo como pega; pendurado da mão direita por uma rótula, balança ao andar/virar e assenta em ~1 s (medido); em 1.ª pessoa vê-se a mão a segurá-lo (o resto do braço fica escondido só no teu ecrã)
- [x] Anel do prompt: desenhado em píxeis exatos — começa no centro em baixo, sobe pelos dois lados e encontra-se no centro em cima (verificado frame a frame); "Esconder" demora 0,7 s para se ver o anel
- [x] Sons medidos um a um (PlaybackLoudness, ficheiro inteiro) e volumes acertados: falha de luz, trovão, arrastar ao longe, pancadas e música deixaram de abafar tudo
- [x] Som por proximidade: chuva nas janelas e portas exteriores (forte lá fora, ténue dentro), compressor em cada frigorífico + tremer ocasional do mais próximo, zumbido de algumas lâmpadas (só acesas), campainha da entrada quando entra/sai um cliente (APM)
- [x] Respiração: só a parte "heavy breathing" do ficheiro (1,0–3,4 s) em loop, um pouco mais baixa
- [x] Passos a correr mais leves (sapatos quase ao nível de andar, baque muito suave)
- Nota: com a janela do Studio em segundo plano o cliente não desenha frames (câmara/animações param) — não é um erro do jogo

Parte C — o estranho
- [ ] `EventManager`: eventos de terror por hora (portas, carrinhos, luzes, anúncios, silhuetas)
- [ ] Clientes NPC (normais e estranhos)
- [x] Clientes suspeitos (CustomerManager): anomalias de costas / a flutuar / alto demais / cabeça tombada / sem cara / a olhar fixamente / sem cabeça só nas câmaras; 15% à 0h, 35% à 1h, depois das 2h (loja fechada) só entram suspeitos até às 5h — verificado no Studio (alturas, pescoço 72°, 0 decals, anda de costas a −1.0)
- [x] Expulsar: "Ask to leave" (segurar 1,2 s) em qualquer cliente; suspeito olha para ti e sai a correr; normal sai ofendido e conta como erro; suspeito ignorado 150 s desaparece e o monstro ouve; contagem no ecrã de resultados — verificado no Studio
- [x] Câmaras de segurança (CameraService + CctvController): computador do escritório e monitor da sala dos funcionários; 8 câmaras com A/D, sair com E/Espaço; imagem verde, linhas, REC, hora, chuvisco; NO SIGNAL sem o circuito Staff; não te mexes enquanto vês; sai ao ser apanhado / fim do turno — verificado no Studio e em testes
- [x] Anel do E também nos prompts de clique (volta completa em 0,25 s); balanço da câmara ~5× menor a correr; respiração só nos últimos 18% de stamina e enquanto esgotado, para quando a stamina volta
- [x] Rato em primeira pessoa: nenhum botão usa GuiButton.Modal (os botões do menu escondidos com Modal deixavam o rato livre para sempre); um só sítio decide: ecrã aberto → cursor e rato livre, senão → escondido e preso ao centro
- [x] Anel do E: só nos prompts de segurar (portas são clique); o lado esquerdo era cortado pela BillboardGui (ficava 4 px fora) — tecla afastada 6 px, anel todo dentro (medido)
- [x] Clientes com cabelo, camisa e calças do catálogo (itens grátis feitos pela Roblox)
- Nota: no Studio, depois do Play, clicar uma vez com o botão esquerdo dentro da janela do jogo para o rato ficar preso (limitação do Studio)
- [x] Câmaras de segurança + anomalias
- [x] Revisão final (21/11/2026): as 6 tarefas jogadas de ponta a ponta no Studio (derrames, lixo, frigoríficos, reposição, caixas, energia), monstro (persegue, apanha, segunda oportunidade, fim de turno), esconderijos (cacifo, secretária), lanterna, portas, câmaras, clientes suspeitos e expulsão, sons e consola
- [x] Correções da revisão: luz por cima dos contentores do lixo (o pátio de trás estava totalmente às escuras); compressores dos frigoríficos calam-se quando o circuito Cold vai abaixo; prompt "Hide" diz Locker / Toilet stall / Under the desk
- Nota: o aviso "rbxassetid://203785492 failed" na consola vem de um plugin do Studio (áudio de outro criador), não do jogo

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
