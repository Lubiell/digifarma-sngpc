# Spec — aceite do envio lido da API do SNGPC
Data: 2026-10-16

## Problema
O app não sabe sozinho se um envio foi aceito: o arquivo de retorno que o
Digifarma grava vem vazio (datas 30/12/1899), e a farmácia marca à mão na aba
Aceites. Sem saber QUANDO a ANVISA validou, o Saldo também não sabe se a foto
do inventário já contém o último envio — o lote 508023 (Digifarma 0, SNGPC 7,
foto de 15/10, envio de 15/10 aprovado) é o caso.

## Solução escolhida
O agente consulta a **API oficial do SNGPC** (`sngpc-api.anvisa.gov.br`), a
mesma por onde o Digifarma já envia (`ENVIO_API=S`), com o login que o
próprio Digifarma guarda na tabela SNGPC (EMAIL, SENHA, LINK_API, HASH).

Em duas etapas, a segunda só depois da primeira funcionar no servidor:

1. **Relatório "API SNGPC"** (botão na aba Servidor, só leitura): pede o token
   (`POST /v1/Authentication/GetToken`), acha o hash do último envio no banco
   e consulta o arquivo (`/v1/FileXml/ConsultaDadosArquivoXml/...`). Mostra
   só status HTTP, datas de transmissão/validação, situação e a mensagem de
   validação com CPF/nome tirados. É o que confirma os endereços e o formato,
   que a documentação pública não mostra.
2. **Automático**, com o formato confirmado: a cada sincronização o agente
   consulta os envios ainda sem resposta e grava o resultado em
   `farmacia/aceites` como `origem: 'api'` (a marcação à mão continua valendo
   e nunca é sobrescrita). A data/hora de validação passa a entrar na conta do
   Saldo: envio validado DEPOIS da foto quer dizer que a foto não tem aquele
   período, e a correção conta o movimento desde o início dele.

Por que não ler a página do site: o Anvisa.exe já faz isso e para no login do
gov.br por desenho da ANVISA; a página muda sem aviso. A API é o canal feito
para sistema.

## Fora de escopo
- Enviar arquivo ao SNGPC. O agente só CONSULTA; quem transmite segue sendo o
  Digifarma.
- Guardar, copiar ou publicar a senha, o token ou o hash: lidos do banco na
  hora, usados em memória, nunca no log, no Firebase ou na tela.
- Login gov.br, captcha ou automação de navegador.
- Mudar a marcação manual existente ou o formato de `farmacia/aceites` além do
  campo `origem`.

## Arquivos afetados
`agente/agente_auto.py`, `agente/teste_agente.py`, `app.js`,
`teste-fumaca.js`, `sw.js`, `agente/regras-firebase.json` (só se a etapa 2
precisar), `PROGRESS.md`.

## Como saber que deu certo
- Etapa 1: o relatório "API SNGPC" no celular mostra "token: ok" e a situação
  do envio de 15/10 batendo com o Relatório Status de Transmissão do site.
- Etapa 2: um envio novo aparece como aceito/recusado na aba Aceites sem
  ninguém marcar, com "pela API" e a data da validação; o lote 508023 deixa de
  divergir se a causa for a foto anterior à validação.
- Testes com respostas simuladas da API (sucesso, 401, 403/Cloudflare, tempo
  esgotado, JSON fora do esperado) e um teste que falha se senha, token ou
  hash aparecerem em qualquer saída.

## Risco e volta atrás
- A API recusar o login do agente (403/Cloudflare já relatado por outros
  sistemas): o relatório diz isso e nada mais muda — o app segue como hoje.
- Muitas consultas: no máximo uma por envio sem resposta a cada sincronização,
  e nenhuma depois da resposta final.
- Voltar atrás: `consultar_api_sngpc: false` no agente_config.json desliga
  tudo; o código antigo continua funcionando sem a API.
