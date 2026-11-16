# Fase 2 — Setup do projeto

Estado: **aprovado pelo dono do projeto depois de ver a pré-visualização** (os testes B, C e D da
secção 4 não foram confirmados individualmente). Build `0.2.0`.

Esta fase não tem jogabilidade. Entrega a fundação em que tudo o resto assenta: ligação
Rojo, arranque ordenado de servidor e cliente, camada de rede com validação, estado
partilhado, grupos de colisão e a iluminação base.

---

## 1. O que foi criado e onde fica no Explorer

O Rojo cria e mantém estas três pastas. **Não edites scripts dentro delas no Studio** — o Rojo
repõe o que está no repositório. Tudo o resto (Workspace, Lighting, assets) é teu no Studio.

| Ficheiro no repositório | Local no Explorer | Tipo | Para que serve |
|---|---|---|---|
| `src/server/Main.server.luau` | `ServerScriptService.Server.Main` | Script | Único ponto de entrada do servidor |
| `src/server/Net/` | `ServerScriptService.Server.Net` (+ `Gate`, `RateLimiter`) | ModuleScript | Cria os remotes; valida e limita tudo o que chega dos clientes |
| `src/server/Services/CollisionService.luau` | `…Server.Services.CollisionService` | ModuleScript | Regista os grupos de colisão |
| `src/server/Services/EnvironmentService.luau` | `…Server.Services.EnvironmentService` | ModuleScript | Aplica a iluminação base; avisa sobre definições do place |
| `src/server/Services/PlayerManager.luau` | `…Server.Services.PlayerManager` | ModuleScript | Registo de cada jogador; marca "pronto"; colisão das personagens |
| `src/client/Main.client.luau` | `StarterPlayer.StarterPlayerScripts.Client.Main` | LocalScript | Único ponto de entrada do cliente |
| `src/client/Net.luau` | `…Client.Net` | ModuleScript | Acesso do cliente aos remotes |
| `src/client/Controllers/CameraController.luau` | `…Client.Controllers.CameraController` | ModuleScript | Fixa a câmara em primeira pessoa |
| `src/shared/Config/GameConfig.luau` | `ReplicatedStorage.Shared.Config.GameConfig` | ModuleScript | Valores globais ajustáveis |
| `src/shared/Config/CollisionGroups.luau` | `…Shared.Config.CollisionGroups` | ModuleScript | Grupos e pares que não colidem |
| `src/shared/Config/LightingConfig.luau` | `…Shared.Config.LightingConfig` | ModuleScript | Perfil de iluminação base (meia-noite) |
| `src/shared/Net/Definitions.luau` | `…Shared.Net.Definitions` | ModuleScript | Catálogo de todos os remotes do jogo |
| `src/shared/Net/Check.luau` | `…Shared.Net.Check` | ModuleScript | Validadores dos argumentos de rede |
| `src/shared/SessionState.luau` | `…Shared.SessionState` | ModuleScript | Estado da sessão replicado por Attributes |
| `src/shared/Util/*.luau` | `…Shared.Util.*` | ModuleScript | `Loader`, `Log`, `Signal`, `Trove`, `DeepFreeze` |

Criados **em runtime** pelo servidor (só existem com o jogo a correr):

- `ReplicatedStorage.Remotes.Events.ClientReady` (RemoteEvent) e `ReplicatedStorage.Remotes.Functions`
- `ReplicatedStorage.State` (Folder com os Attributes `Phase` e `BuildVersion`)
- Em `Lighting`: `Atmosphere`, `Grade` (ColorCorrection) e `Bloom`

### Regras que este código impõe daqui em diante
- **Um remote novo = uma entrada em `Definitions`**, com quem o envia, validador por argumento e
  limite de frequência. O servidor recusa arrancar se um remote de cliente não tiver limite.
- **Um serviço novo = uma linha na ordem de arranque** em `Main`. Se existir mas não estiver
  listado, aparece um aviso no Output.
- **O servidor nunca invoca o cliente** (`InvokeClient`): um cliente pode simplesmente não responder.

### Grupos de colisão
`Player`, `Monster`, `Npc`, `CarriedItem`. Jogadores não colidem entre si, nem com NPCs, nem com
o monstro (o "apanhar" é decidido pelo servidor por distância e linha de vista, não por física).
Tudo colide com o mapa. Para mudar: `Config/CollisionGroups`.

### Iluminação
O Roblox substituiu `Lighting.Technology` por duas propriedades. O antigo **Future** corresponde a
`LightingStyle = Realistic` + `PrioritizeLightingQuality = true`, que é o que o perfil pede
(confirmado no anúncio da equipa de rendering e nas definições atuais da API).

Os valores do perfil foram escolhidos no papel — ainda não há mapa para os afinar. Vão mudar na
Fase 3. Em runtime, qualquer efeito de pós-processamento em `Lighting` que não faça parte do
perfil é desligado (com uma linha no Output), para o aspeto não depender do template do Studio.
Nada é gravado no ficheiro do place.

---

## 2. Ver o estado atual sem instalar nada

Não precisas do Rojo para ver e testar o jogo. O ficheiro `releases/NightShiftSupermarket.rbxl`
tem tudo lá dentro — código e mapa.

1. Descarrega-o e abre-o no Roblox Studio (duplo clique, ou *File → Open from File*).
2. *View → Output*.
3. Carrega em **Play** (F5).

Cada vez que eu entregar uma versão nova, este ficheiro é substituído.

---

## 3. Ligar o Studio ao repositório

Faz isto uma vez, quando quiseres começar a trabalhar no place definitivo.

1. **Obter o repositório no teu computador.** Com o GitHub Desktop: *Clone repository* →
   `Geadas11/Jogo_Roblox-fable` → muda para o ramo `claude/new-session-w2u9nq`.
2. **Instalar o Rojo 7.7.1.** Em <https://github.com/rojo-rbx/rojo/releases/tag/v7.7.1> descarrega
   o zip para o teu sistema, extrai o executável `rojo` para a pasta do projeto (ou para um sítio
   no PATH).
3. Abre um terminal **na pasta do projeto** e instala o plugin do Studio com a mesma versão:

   ```bash
   rojo plugin install
   ```

4. Inicia o servidor de sincronização e deixa a janela aberta:

   ```bash
   rojo serve
   ```

5. No **Roblox Studio**: *New* → **Baseplate**. Separador *Plugins* → **Rojo** → **Connect**.
   Devem aparecer `Shared`, `Server` e `Client` nos locais da tabela acima.
6. Guarda o place no grupo: *File → Publish to Roblox As…* → escolhe o **grupo** como criador.

Sempre que eu entregar código novo: atualizas o repositório (GitHub Desktop → *Fetch/Pull*),
`rojo serve`, **Connect**. A versão aparece no Output, por isso vês logo se está atualizado.

> Em Team Create, só uma pessoa de cada vez deve ter o Rojo ligado. Os restantes recebem os
> scripts pelo próprio Team Create.

---

## 4. Lista de verificação (é isto que fecha a Fase 2)

Abre a janela **Output** (*View → Output*).

### A. Arranque — carrega em Play (F5)
- [ ] Nenhuma linha vermelha de erro.
- [ ] `[NSS/Server/Main] Server ready (build 0.2.0, 3 services, … ms)`
- [ ] `[NSS/Server/Players] <o teu nome> is ready (1 in session)`
- [ ] `[NSS/Client/Main] Client ready (build 0.2.0, 1 controllers)`
- [ ] A câmara está em primeira pessoa e não deixa afastar o zoom.
- [ ] O mundo está escuro, de noite, com névoa ligeira.
- [ ] Na vista de servidor, existem `ReplicatedStorage.Remotes` e `ReplicatedStorage.State`
      (este com os Attributes `Phase = Lobby` e `BuildVersion = 0.2.0`).

É normal aparecer `Server size is … players, the game is designed for 6` e uma ou mais linhas
`Disabled … not part of the lighting profile`.

**Se aparecer** `Could not set Lighting.LightingStyle` ou `Lighting.LightingStyle is …, expected
Realistic`: seleciona `Lighting` no Explorer e define à mão `LightingStyle = Realistic` e
`PrioritizeLightingQuality` ligado. Diz-me, para eu registar que tem de ser manual.

### B. Dois jogadores
*Test* → escolhe **2 jogadores** → *Start*.
- [ ] O Output do servidor mostra dois `is ready`, o segundo com `(2 in session)`.
- [ ] Os dois jogadores atravessam-se sem se empurrarem.

### C. Segurança — o servidor recusa pedidos inválidos
Com o jogo a correr, na vista de **cliente**, cola na *Command Bar*:

```lua
game.ReplicatedStorage.Remotes.Events.ClientReady:FireServer("hack")
```

- [ ] Output do **servidor**: aviso `Rejected ClientReady from … : expected at most 0 arguments, got 1`.

Espera uns 10 segundos e cola:

```lua
for i = 1, 50 do game.ReplicatedStorage.Remotes.Events.ClientReady:FireServer() end
```

- [ ] Output do servidor: **um único** aviso com `rate limit exceeded` (não 50).

### D. Definições do place
- [ ] *Game Settings → Places*: máximo de **6** jogadores (o nome exato do menu pode variar; só
      fica disponível depois de o place estar publicado).

Quando me disseres o resultado de A–D, marco a fase como testada e avanço para a Fase 3.

---

## 5. O que eu verifiquei — e o que não verifiquei

**Verificado aqui, fora do Studio** (`./scripts/check.sh`):
- Os 21 ficheiros compilam; o projeto Rojo constrói um `.rbxl` válido.
- 75 testes automáticos passam: validadores, limite de frequência, catálogo de remotes, `Signal`,
  `Trove`, `Loader`, `SessionState`, e uma simulação do arranque completo (servidor → jogador
  entra → cliente arranca), incluindo 6 jogadores, saída de jogadores, argumentos forjados e spam.
- Sabotei o código de 11 maneiras diferentes; os testes detetaram as 11.
- Todos os métodos, classes, propriedades e enums do Roblox usados existem nas definições atuais
  da API.

**Não verificado — só o Studio pode confirmar:**
- A simulação usa um motor falso escrito por mim (`tests/engine.luau`). Prova que o código corre e
  que as peças encaixam; **não prova** nada sobre o comportamento real do Roblox.
- Se `LightingStyle` pode ser escrito por script (há tratamento para o caso de não poder).
- O aspeto real da iluminação.
- A análise de tipos do Luau **não foi executada** (não consegui instalar o analisador neste
  ambiente). O código corre na mesma, mas a janela *Script Analysis* do Studio pode mostrar
  avisos de tipos. Se mostrar, envia-mos.

---

## 6. Nota sobre o grupo

Como a experiência vai ser publicada no grupo:
- Animações e áudio têm de ser carregados **com o grupo como criador**, senão não tocam. Volto a
  isto na Fase 6, com os passos.
- Passes e produtos são criados na experiência do grupo; as receitas vão para os fundos do grupo.
- Quem editar o place precisa da permissão de edição no grupo.
