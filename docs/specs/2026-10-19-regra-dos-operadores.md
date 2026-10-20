# Spec — quem pode ler e gravar a lista de operadores
Data: 2026-10-19

## Problema
Em `agente/regras-firebase.json`, `farmacia/operadores` aceita leitura e
gravação de **qualquer conta logada que não seja anônima**. Todos os outros
nós que o app grava exigem o UID em `farmacia/autorizados`. O mesmo vale para
a leitura de `farmacia/autorizados` (a lista de UIDs com acesso).

O app entra com e-mail e senha do Firebase (`signInWithEmailAndPassword`), e a
chave web do Firebase é pública no `app.js` — é assim que o Firebase funciona.
Se o cadastro de contas estiver ligado no projeto (o padrão do provedor
e-mail/senha), qualquer pessoa pode criar uma conta pela API e:

- apagar ou trocar a lista de operadores (o nome que assina cada aceite e
  cada pedido ao agente);
- incluir nomes falsos, que passam a aparecer para quem marca um aceite;
- ler a lista de UIDs autorizados.

Não dá acesso ao inventário, aos aceites nem à fila do agente. [verificar] se o
cadastro de contas está ligado no console (Authentication > Settings >
Ações do usuário > "Ativar criação (inscrição)").

## Alternativas
- **A. Exigir `autorizados` também em `operadores` (recomendada, junto com B).**
  `.read` e `.write` de `operadores` passam a ser iguais aos de `config`;
  `autorizados` passa a ser lido só pelo próprio UID
  (`autorizados/$uid`), já que o app não lê a lista inteira (só o agente, que
  usa a conta de serviço e não passa pelas regras). Custo: uma pessoa logada
  mas ainda não autorizada deixa de ver a lista de operadores — hoje ela já
  não vê nada do resto do app, então nada muda na prática.
- **B. Desligar o cadastro de contas no console do Firebase.** Sem código.
  Fecha a porta para contas novas criadas de fora; contas novas da farmácia
  passam a ser criadas pelo console. Custo: um passo manual seu, uma vez.
- **C. Deixar como está.** O dano possível é baixo (nomes e a lista de UIDs),
  mas é o único nó gravável por quem não é da farmácia.

## Recomendação
A + B. A protege mesmo que o cadastro volte a ser ligado; B tira o atacante
antes das regras.

## Como fica (A)
- `regras-firebase.json`: `operadores` com a mesma condição de `config`;
  `autorizados` com `"$uid": {".read": "auth != null && auth.uid === $uid"}`
  e `.write: false`.
- `teste_bat.py` já confere o protocolo app × agente × regras; ganha a
  conferência de que nenhum nó gravável pelo app fica sem `autorizados`.
- As regras chegam ao Firebase quando o agente roda `--regras` (o
  `ATUALIZAR_AGENTE.bat` faz isso no passo 5), ou colando no console.

## Plano de volta
Republicar o `regras-firebase.json` anterior (o do commit antes desta
mudança) pelo console ou pelo `--regras`. Nenhum dado é apagado nem
convertido.

## Descoberto depois do ok (20/10)
O README diz que `farmacia/operadores` é **compartilhado com o app ESTOQUE**,
e o nó `estoque` deixa ler e gravar qualquer conta não anônima — não só as de
`autorizados`. Aplicar A como está pode tirar a lista de operadores de quem
usa o ESTOQUE sem estar em `autorizados`, e o código do ESTOQUE não estava
acessível para conferir o que ele lê (`operadores`, `autorizados`, `agentes`).

Por isso A ficou parado. B continua valendo e fecha a mesma porta para os dois
apps, inclusive para o nó `estoque`, que tem o mesmo problema. A volta quando
der para ler o ESTOQUE ou confirmar que todos os usuários dele estão em
`autorizados`.

## Aplicado (20/10)
A farmácia confirmou que todos os usuários do ESTOQUE estão em
`autorizados`, e A foi aplicado. `teste_bat.py` passou a recusar qualquer
`.read`/`.write` em `farmacia/` que não exija `autorizados`, `agentes` ou o
próprio UID. Ficou de fora, como exceção explícita no teste, a leitura de
`farmacia/agentes`, aberta do mesmo jeito: não estava nesta spec.

Depois, a pedido da farmácia, `farmacia/agentes` foi fechado do mesmo
jeito que `autorizados` (cada conta lê só o próprio UID). Nem o app nem o
agente leem essa lista, e o teste deixou de ter a exceção.

## Fora do escopo
Login, senha da farmácia, regras dos outros nós.
