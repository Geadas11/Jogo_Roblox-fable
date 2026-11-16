# Fase 4 — Jogabilidade base

Estado: **parte A e parte B implementadas, à espera do teu teste no Studio.** Build `0.4.1`.

Já é um jogo, embora sem terror: picas o ponto, o relógio da noite corre das 12 AM às 6 AM,
recebes tarefas de supermercado a cada hora, fazes o trabalho e no fim vês o resumo do turno.

---

## 1. Como jogar esta versão

1. Abre `releases/NightShiftSupermarket.rbxl` no Roblox Studio e carrega em **Play** (F5).
2. Apareces na sala dos funcionários. No topo do ecrã lê-se **OFF SHIFT**.
3. Vai ao **relógio de ponto** — a caixa preta com visor verde na parede, ao lado da porta — e
   mantém **E** premido: *Clock in*.
4. O relógio passa a **12:00 AM** e aparecem duas tarefas no canto superior esquerdo.
5. Faz as tarefas (ver abaixo). A cada hora de jogo chegam mais duas.
6. Às **6:00 AM** o turno acaba e aparece o resumo; 20 segundos depois voltas ao estado inicial
   e podes picar o ponto outra vez.

Uma hora de jogo dura 4 minutos reais; o turno completo dura 24 minutos.

> Para testar mais depressa, muda `HourDurationSeconds` em
> `ReplicatedStorage.Shared.Config.GameConfig` (por exemplo para `30`) **antes** de carregar em
> Play. É uma alteração só para o teu teste; não a guardes no ficheiro.

### Controlos
| Ação | Teclado | Telemóvel |
|---|---|---|
| Interagir (portas, objetos, tarefas) | **E** (manter premido quando a barra aparece) | tocar no botão do prompt |
| Largar o que levas na mão | **G** | botão **DROP** |

### As três tarefas
| Tarefa | O que fazer |
|---|---|
| **Restock shelves** | Algumas secções de prateleira ficam vazias. Vai ao **armazém**, pega numa caixa (*Pick up*), leva-a à prateleira vazia e usa *Restock*. Uma caixa por secção. A tarefa diz em que corredores. |
| **Clean up spills** | Aparecem poças no chão. Vai à **manutenção** buscar uma **esfregona** (há duas, ao lado do balde amarelo) e usa *Clean* em cada poça. A esfregona não se gasta. |
| **Check the coolers** | Alguns frigoríficos e arcas têm uma **luz âmbar** por cima. Vai até cada um e usa *Inspect*. |

Só levas **uma coisa de cada vez**: com a esfregona na mão não consegues pegar numa caixa. Larga
com **G**. Com mais jogadores cada tarefa tem mais unidades de trabalho.

---

## 2. Lista de verificação no Studio

Com a janela **Output** aberta (*View → Output*).

### A. Portas e relógio
- [ ] Arranque sem linhas vermelhas; `Server ready (build 0.4.1, 10 services, …)`.
- [ ] As portas abrem e fecham com **E** (*Open* / *Close*).
- [ ] A saída de emergência (porta vermelha, parede leste) não tem prompt.
- [ ] Picar o ponto: o relógio começa em `12:00 AM` e avança; aparece a mensagem de início.
- [ ] O prompt do relógio de ponto desaparece durante o turno.
- [ ] Os tetos já não se atravessam ao saltar.

### B. Tarefas
- [ ] Aparecem duas tarefas ao começar, com contagem `0/N`.
- [ ] **Restock:** há prateleiras vazias nos corredores indicados e caixas no armazém; a caixa vê-se
      à tua frente enquanto a levas; ao repor, os produtos reaparecem e a contagem sobe.
- [ ] Tentar repor sem caixa mostra um aviso.
- [ ] **Spills:** sem esfregona aparece um aviso; com esfregona a poça desaparece.
- [ ] **Coolers:** as luzes âmbar veem-se bem; apagam-se ao inspecionar.
- [ ] Com as mãos ocupadas, tentar pegar noutra coisa mostra "Your hands are full".
- [ ] **G** larga o objeto no chão à tua frente e podes voltar a pegar nele.
- [ ] Ao completar uma tarefa aparece `Task complete: … +$…`.
- [ ] Às 6:00 AM aparece o resumo com tarefas feitas e dinheiro; depois, as prateleiras estão
      cheias, as poças e as caixas desapareceram e podes começar outro turno.

### C. Dois jogadores (*Test* → 2 jogadores → *Start*)
- [ ] Ambos veem o mesmo relógio e a mesma lista de tarefas.
- [ ] O que um faz (porta, prateleira reposta, poça limpa) aparece ao outro.
- [ ] Dois jogadores não conseguem pegar no mesmo objeto.

### O que quero saber
1. O relógio de ponto encontra-se bem? Percebe-se o que fazer a seguir?
2. As tarefas são claras? Demasiado fáceis, demasiado chatas, demasiado longas?
3. O ritmo (4 minutos por hora) parece-te bem?
4. A caixa e a esfregona veem-se bem na mão, ou tapam demasiado o ecrã?

---

## 3. O que foi implementado

| Sistema | Onde | O que faz |
|---|---|---|
| Interações | `Server/Services/InteractionService` | Todos os prompts são criados aqui. O servidor só aceita uma interação se o jogador estiver vivo, na sessão, perto o suficiente e a um ritmo humano. |
| Portas | `…/DoorService` | Abre e fecha usando as duas poses guardadas no mapa. |
| Sessão | `…/GameManager` | Lobby → Turno → Resultados → Lobby. Se todos saírem, o turno é abandonado. |
| Relógio | `…/ShiftManager`, `Shared/ShiftClock` | Decide a hora; nunca salta horas. Todos os clientes desenham o mesmo relógio a partir do relógio sincronizado do servidor. |
| Transporte | `…/CarryService` | Um objeto por jogador; o que alguém leva fica no mundo se essa pessoa sair ou morrer. Objetos largados não bloqueiam a passagem. |
| Ferramentas | `…/ToolService` | Coloca as esfregonas na manutenção. |
| Tarefas | `…/TaskManager`, `…/Tasks/*`, `Shared/Config/TaskDefinitions` | Sorteia tarefas a cada hora, conta o progresso, paga a recompensa uma única vez, limpa o mundo no fim do turno. |
| HUD | `Client/Controllers/HudController`, `ObjectivesController`, `Client/UI/Theme` | Relógio, estado, notificações, lista de objetivos, indicador do que levas, resumo do turno. |

Acrescentar um tipo de tarefa novo é: uma entrada em `TaskDefinitions` e um módulo em `Tasks/`
com `Begin` e `Cleanup`. O resto (sorteio, progresso, recompensa, HUD) já existe.

### Limites conhecidos desta versão
- **O dinheiro ainda não é guardado** nem serve para nada: é só a contagem do turno. A progressão
  e a gravação de dados são da Fase 7.
- **Os prompts têm o aspeto predefinido do Roblox.** O estilo próprio vem com a interface, na Fase 6.
- **Não há animações** de pegar, repor ou limpar; o objeto simplesmente aparece à frente do jogador.
- **As portas movem-se pelo servidor**, o que pode parecer ligeiramente aos solavancos. Passa a ser
  animado no cliente quando houver som e polimento.
- Faltam tipos de tarefa do design: lixo, carrinhos abandonados, entregas, caixas registadoras,
  inventário. Usam os mesmos mecanismos e entram a seguir.

---

## 4. O que eu verifiquei — e o que não verifiquei

**Verificado aqui** (`./scripts/check.sh`):
- 146 verificações automáticas passam. As novas correm o servidor e o cliente verdadeiros contra o
  **mapa real** num motor simulado: portas, picar o ponto, horas, fim de turno, as três tarefas de
  ponta a ponta, transporte, entrada a meio do turno, cinco jogadores.
- Tentativas de batota simuladas e recusadas: abrir portas ou repor prateleiras do outro lado do
  mapa, interagir morto ou sem estar na sessão, martelar o mesmo prompt, pegar num objeto que
  outro já leva, repor sem caixa ou com a esfregona, pedir a lista de tarefas em excesso.
- Sabotei o código novo de 17 maneiras; os testes detetaram as 17.
- Todos os elementos da API do Roblox usados existem nas definições atuais.

**Não verificado — só o Studio pode confirmar:**
- Tudo o que é visual: o HUD no ecrã, o aspeto dos prompts, a posição da caixa e da esfregona na
  mão, o movimento das portas.
- A tecla **G** e o botão **DROP** (o simulador não reproduz teclado nem toque).
- O comportamento da física ao levar um objeto preso à personagem.
- O jogo com dois clientes reais.
