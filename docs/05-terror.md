# Fase 5 — Terror

Estado: **parte A (o monstro) implementada, à espera do teu teste no Studio.** Build `0.5.0`.

A Fase 5 vem em partes. Esta primeira traz o essencial: **The Customer** — o monstro —, os
esconderijos, o ruído, correr com estamina e o que acontece quando alguém é apanhado. As
restantes peças (energia e falhas de luz, eventos estranhos, clientes NPC, câmaras de segurança)
são as partes B e C.

---

## 1. Como testar

1. Abre `releases/NightShiftSupermarket.rbxl` no Studio e carrega em **Play**.
2. Pica o ponto (*Clock in*).
3. O monstro só aparece às **3:00 AM**. Com o tempo normal isso são 12 minutos. Para testar já,
   antes de carregar em Play, abre `ReplicatedStorage.Shared.Config.MonsterConfig` e põe
   `ActiveFromHour = 0` (aparece logo ao picar o ponto), e/ou baixa `HourDurationSeconds` em
   `GameConfig`. **Não guardes essas alterações no ficheiro.**

### Controlos novos
| Ação | Teclado | Telemóvel |
|---|---|---|
| Correr (gasta estamina) | **Shift** esquerdo, mantido | botão **RUN** |
| Esconder-se | **E** num cacifo, debaixo da secretária do escritório ou na última cabine das casas de banho | prompt |
| Sair do esconderijo | **Espaço** | botão **LEAVE** |
| Escolher quem ver (apanhado, em equipa) | **← / →** | botões **< / >** |

Andar é silencioso (velocidade 10). Correr é mais rápido do que o monstro (17 contra 14,5), mas
faz barulho e só dura 5 segundos seguidos.

---

## 2. Como o monstro se comporta

Parece um cliente. Alto demais, braços compridos demais, cara quase normal.

| Estado | O que faz |
|---|---|
| **Patrulha** | Anda devagar entre pontos de toda a loja, armazém, casas de banho e lá fora. Às vezes para e olha à volta. |
| **"O que foi isso?"** | Se te vê de relance, para e vira-se para ti enquanto se decide. Perto decide depressa; longe, devagar. |
| **Observar** | Às vezes, quando te vê ao longe, fica simplesmente parado a olhar, com a cabeça a inclinar-se. Se sais da vista dele, desiste. |
| **Investigar** | Vai até um ruído: alguém a correr, uma porta batida por um jogador, algo largado no chão. |
| **Procurar** | Anda pela zona onde te perdeu; de vez em quando abre um esconderijo próximo. |
| **Perseguir** | Vai atrás de ti. Se te perde de vista durante 5 segundos, vai ao último sítio onde te viu e procura. |
| **Apanhar** | Se te alcança. Depois desaparece durante 20 segundos e volta noutro sítio, longe de todos. |

O que o faz ver-te: estares no campo de visão dele (120°, até 70 studs) **e** nada alto pelo meio
(paredes, prateleiras, estantes — o vidro e os balcões baixos não tapam). A menos de 6 studs
sente-te mesmo de costas. Esconder-se funciona — **exceto se ele te viu a entrar**: aí vai direto
ao esconderijo. Abre as portas fechadas que encontra pelo caminho. Fica 8% mais rápido a cada hora
depois das 3 AM.

### Quando alguém é apanhado
- A pessoa vê a sequência de captura (três variações).
- **Sozinho:** voltas à sala dos funcionários — uma vez por turno. À segunda, o turno acaba.
- **Em equipa:** ficas a ver um colega até à hora seguinte, e depois voltas ao trabalho. Se não
  sobrar ninguém a trabalhar, o turno acaba.
- O resumo do turno mostra o motivo e quantas vezes a equipa foi apanhada.
- O botão de *reset* do Roblox está desligado (seria uma fuga grátis).

---

## 3. Lista de verificação no Studio

- [ ] Arranque sem vermelho; `Server ready (build 0.5.0, 14 services, …)`; aparece
      `[NSS/Server/Hiding] 9 hiding spots`.
- [ ] O monstro aparece (às 3 AM, ou logo com `ActiveFromHour = 0`) e anda **suavemente**, sem
      saltos, sem atravessar paredes nem prateleiras.
- [ ] O corpo tem bom aspeto: alto, braços compridos, cabeça a inclinar quando está a olhar.
- [ ] Quando está perto, as bordas do ecrã escurecem; quando te persegue, as cores perdem cor.
- [ ] Atrás de uma prateleira não te vê; num corredor aberto à frente dele, vê.
- [ ] Correr perto dele chama-o; andar não.
- [ ] Esconder num cacifo: vês as ripas, ele passa e não te encontra (a não ser que te tenha visto entrar).
- [ ] **Espaço** ou **LEAVE** tira-te do esconderijo para um sítio livre.
- [ ] Ser apanhado: a sequência vê-se bem e não é demasiado brusca; voltas à sala dos funcionários.
- [ ] Segunda vez sozinho: o turno acaba com "You were caught.".
- [ ] Shift faz correr; a barra de estamina aparece e esgota-se.
- [ ] Com dois jogadores: o apanhado fica a ver o outro e volta na hora seguinte.

### O que quero saber
1. Assusta? Ou é só irritante?
2. Está demasiado rápido / lento / atento / distraído?
3. O aspeto do corpo funciona, mesmo sendo feito de blocos?

---

## 4. Decisões técnicas

| Tema | Decisão | Porquê |
|---|---|---|
| Navegação | Grelha própria (1 stud por célula), calculada a partir do mapa no build e gravada em `ServerStorage.NavGrid` / `SightGrid`, em vez do `PathfindingService`. | O mapa é estático e plano. A grelha comporta-se igual no Studio e nos testes automáticos, por isso todas as rotas são verificadas antes de cada entrega. O `PathfindingService` só existe dentro do Studio e eu não o consigo testar. |
| Movimento | O servidor move uma peça invisível 10× por segundo; cada cliente desenha o corpo e desliza-o atrás dela a cada frame. | Movimento suave sem depender de física nem de animações carregadas. |
| Aspeto | Corpo feito de peças, posto em pose por código (passada rígida, braços pendurados, cabeça a inclinar). | Funciona já, sem assets. Pode ser trocado por um modelo e animações reais na Fase 6 sem mexer na IA. |
| Personagens | `CharacterAutoLoads` desligado; o servidor carrega as personagens. | Para um jogador apanhado não reaparecer sozinho a meio da loja. |
| Sem áudio | Os sinais de perigo são visuais (bordas escuras, cor). | Não há assets de áudio ainda; o som é da Fase 6. |

Afinação: `ReplicatedStorage.Shared.Config.MonsterConfig` (velocidades, sentidos, ruídos, tempos).

---

## 5. O que eu verifiquei — e o que não verifiquei

**Verificado aqui** (`./scripts/check.sh`, 198 verificações):
- **Rotas:** 600 percursos entre pontos de patrulha por todo o mapa, sem atravessar obstáculos
  (a verificação é exata, célula a célula). Todos os pontos de patrulha são alcançáveis.
- **Comportamento:** patrulha 4 minutos seguidos sem entrar em paredes e percorre a loja toda; vê
  num corredor aberto e não vê através de prateleiras nem de costas; investiga ruídos; perde o
  rasto quando sais da vista; encontra quem se esconde sem ser visto cerca de 1 vez em 3; apanha
  quem se esconde à frente dele; para e fica a olhar em cerca de metade dos encontros ao longe.
- **Integração no mapa real:** aparece às 3 AM longe e fora da vista; captura, segunda
  oportunidade, turno falhado sozinho e em equipa, espectador e regresso na hora seguinte; cada
  esconderijo dá para entrar e sair para um sítio livre; portas fechadas são abertas; correr faz
  ruído e andar não; o ecrã escurece e perde cor; uma noite inteira sem avisos.
- Sabotei este código de 11 maneiras; à primeira os testes detetavam 7. Reforcei os testes e agora
  detetam as 11.

**Não verificado — só o Studio pode confirmar:**
- O aspeto e a suavidade do movimento, a sequência de captura, as ripas do esconderijo.
- Ancorar e teletransportar a personagem no Roblox real (esconder, apanhar).
- Desligar o botão de *reset* (depende dos scripts internos do Roblox estarem prontos).
- Correr com Shift e o botão RUN (o simulador não tem teclado nem toque).
- Se é divertido e assustador — isso é contigo.
