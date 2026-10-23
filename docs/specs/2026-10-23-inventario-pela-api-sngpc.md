# Spec — inventário da ANVISA pela API (etapa 1: sondagem)
Data: 2026-10-23

## Problema
O inventário da ANVISA só entra no Digifarma pelo `Anvisa.exe`, que é
automação de navegador e **para no login do gov.br**. É o único passo da
corrente do SNGPC que ainda exige uma pessoa na loja — transmitir e saber se
a ANVISA aceitou já são automáticos (`ENVIO_API=S` e a consulta à API das
specs de 16 e 17/10). Última conclusão conhecida do `Anvisa.exe`: 10/10 07:00.
Com a foto velha, o Saldo compara contra um inventário desatualizado.

O SSH ligado em 23/10 **não resolve isto**: o `Anvisa.exe` precisa de sessão
gráfica, e o RDP depende de senha na conta — que a farmácia decidiu não ter.

## Solução escolhida
Etapa 1, **só leitura**: relatório "Inventário pela API" (botão na aba
Servidor) que pergunta à API oficial do SNGPC se existe endpoint que devolva
o inventário/estoque. Reaproveita o token que o agente já sabe obter
(`POST /v1/Authentication/GetToken`) com EMAIL/SENHA/LINK_API lidos da tabela
`SNGPC` na hora. Para cada caminho candidato, registra apenas o status HTTP e
se a resposta é JSON com itens de estoque. Não grava nada em lugar nenhum.

Por que esta e não as outras: automatizar o login gov.br já foi recusado em
16/10 com motivo (o site muda sem aviso, a ANVISA exige pessoa por desenho) e
depende de um binário do Digifarma que não controlamos; aceitar o manual não
fecha nada. A API é o canal feito para sistema, e o agente **já autentica
nela com sucesso**.

A etapa 2 — buscar o inventário por ali a cada sincronização — só existe
depois que esta responder, e **com spec própria**, porque envolve decidir
onde o inventário passa a morar (publicar no Firebase, sem escrever em
`INVENTARIO_SNGPC`: gravar no banco do Digifarma seria uma exceção nova à
regra de só-SELECT).

## Fora de escopo
- Enviar ou transmitir qualquer coisa à ANVISA. Só consulta.
- Login gov.br, captcha, automação de navegador, mexer no `Anvisa.exe` ou
  nas tarefas agendadas.
- Escrever no banco do Digifarma — inclusive em `INVENTARIO_SNGPC`.
- Guardar, logar ou publicar senha, token ou hash.
- Varrer endpoints por tentativa e erro: a lista é pequena, fixa e revisada
  antes de rodar.
- Mudar o que a aba Aceites ou o Saldo já fazem.

## Arquivos afetados
`agente/agente_auto.py`, `agente/teste_agente.py`, `app.js`,
`teste-fumaca.js`, `agente/regras-firebase.json` (ação nova do relatório),
`PROGRESS.md`.

## Como saber que deu certo
- O relatório roda no servidor e mostra, por caminho candidato, o status HTTP
  e se veio JSON com itens de estoque.
- **Sucesso não é achar o endpoint**: é encerrar a dúvida com evidência. Um
  relatório dizendo "os N caminhos responderam 404" é resultado válido e
  fecha a questão.
- Teste que falha se senha, token ou hash aparecerem em qualquer saída.
- Testes com respostas simuladas: 200 com JSON de estoque, 200 fora do
  formato, 401, 403/Cloudflare, 404 e tempo esgotado.

## Risco e volta atrás
- **O risco sério:** bater em caminhos inexistentes pode irritar o
  WAF/Cloudflare da ANVISA e bloquear o login que o Digifarma usa para
  TRANSMITIR. Se o envio parar, a farmácia fica em falta com a ANVISA.
  Contenção: no máximo 6 caminhos, uma tentativa cada, com intervalo; só sob
  demanda pelo botão, **nunca** na sincronização automática; para tudo no
  primeiro 403.
- Volta atrás: é relatório sob demanda — não apertar o botão já é o
  desligamento. `consultar_api_sngpc: false` continua desligando a API toda.
- Pendência de segurança relacionada (PROGRESS.md): a senha do SNGPC foi
  exposta e precisa ser trocada. O agente lê a senha do banco a cada
  execução, então trocá-la não quebra nada aqui.
