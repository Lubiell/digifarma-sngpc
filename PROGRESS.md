# PROGRESS — digifarma-sngpc
Atualizado: 2026-10-16 | Máquina: nuvem (Claude Code)

## Estado atual
App no ar em GitHub Pages. Agente parado no servidor desde 10/09 (ver
"Pendências no servidor"). Novo `agente/ACESSO_REMOTO.bat` para entrar no
servidor de longe, ainda não executado no Windows.

## Feito
- 16/10: Saldo com Digifarma = SNGPC acusado como errado. A diferença é
  contra foto + movimento desde a foto, e a tela não mostrava o movimento
  (PR #20: mostra movimento e esperado, nota própria, barra conta os
  jaNaAnvisa). Botão "Investigar este lote no servidor" no detalhe (PR #21):
  relatório `saldo` com `MS|LOTE` dá a conta, a fila do lote, um veredito
  (aviso falso / compensado por acaso / em aberto) e a busca nos XML.
  Testado no Chromium com dados de exemplo; falta ver com dado real.
- 16/10: a resposta da investigação não apareceu no celular: um "Sincronizar
  vendas" sobrescreveu/escondeu o pedido `saldo` (farmacia/comando guarda um
  pedido só). Agora: o app pergunta antes de substituir pedido pendente; a
  aba Servidor mostra o último relatório recebido; e o agente grava o
  veredito em cada lote a cada sincronização (`veredito`, `vereditoCorte`),
  que aparece no detalhe do Saldo sem pedir nada.
- 16/10: aceite automático pela API oficial do SNGPC, aprovado pela farmácia
  (spec em docs/specs/2026-10-16-aceite-pela-api-sngpc.md). Etapa 1 feita: o
  botão "Login SNGPC" testa o token e consulta o último envio com o login que
  o Digifarma guarda (nada de segredo na saída). Endereços vêm de fórum, não da
  doc oficial; a nuvem leva 403 da Cloudflare, então só o servidor confirma.
  Etapa 2 (marcar sozinho e usar a data de validação no Saldo) espera essa
  resposta.
- 16/10: etapa 1 confirmou a API no servidor (token ok; resposta é JSON
  dentro de texto, com datas de transmissão/validação; HASH_ULT_ENVIO parado
  no envio de 07/10). Etapa 2 feita: de hora em hora o agente consulta os
  envios (o último do Digifarma e os arquivados, se a fórmula do hash for
  achada), guarda em api_sngpc_cache.json e publica em apiSngpc; a aba Aceites
  mostra "Validado sem erro pela ANVISA"; envio validado depois da foto entra
  na correção do Saldo (fotoAntesDaValidacao). Falta: ver no servidor se a
  fórmula do hash bate e se o lote 508023 deixa de divergir.
- 16/10: o servidor mostrou que a fórmula do hash não bate com o XML e que a
  API tem só 3 endereços (GetToken, Consulta, Enviar): não há listagem de
  envios. O Login SNGPC agora procura colunas HASH em todas as tabelas do
  Digifarma (só contagens) para achar um histórico dos hashes.
- 16/10: o lote 508023 deixou de divergir com a foto de 16/10 (era a foto).
  Atualização automática: o agente confere o GitHub a cada 10 min (GET com
  If-None-Match, 304 sem corpo) e troca sozinho quando o arquivo muda; a
  aba Servidor mostra "Última atualização" com data, origem e motivo da
  falha. Vale depois que o servidor receber esta versão uma vez (botão ou a
  troca diária de 20 h).
- 17/10: os envios saem de três computadores (servidor, caixa, farmacêutico),
  e o XML fica no disco de quem enviou. Spec aprovada
  (docs/specs/2026-10-16-xml-dos-outros-computadores.md): o
  agente/COMPARTILHAR_XML.bat, rodado uma vez em cada computador, compartilha
  a pasta do SNGPC.XML como SNGPC_XML$, somente leitura, para o usuário
  leitor_sngpc e só para o IP do servidor; no app, "XML de outro computador"
  cadastra nome e senha; o agente traz o XML para enviados\ do servidor
  (sngpc_AAAA-MM-DD_<PC>.xml). O PowerShell do .bat não foi executado aqui
  (sem Windows): o primeiro uso é o teste.
- 17/10: decisão da farmácia: os envios ao SNGPC passam a sair SÓ do servidor.
  O COMPARTILHAR_XML.bat não será rodado; o código de rede fica parado (sem
  computador em pastas_xml_rede não faz nada). Teste pendente: depois do
  próximo envio pelo servidor, rodar Login SNGPC — se HASH_ULT_ENVIO mudar,
  os envios do balcão eram a causa do hash parado desde 08/10 e o aceite
  passa a vir sozinho pela API; se não mudar, mandar o chamado ao Digifarma.
- 17/10: Login SNGPC mostrou que o Digifarma só guarda o hash do último envio
  (nenhuma outra tabela com HASH). O Relatório Status de Transmissão do site
  mostra o de todos: na aba Aceites, "Colar relatório da ANVISA" manda os
  hashes ao agente, que consulta cada um na API; sem marcação manual, o selo
  mostra o que a ANVISA respondeu. O relatório de 17/10 mostrou o envio de
  14/10 (movimento de 13/10) RECUSADO: Escitalopram 1.0525.0045.003-8, lote
  BQ37M006, venda maior que o estoque; o de 15/10 ainda sem validação.
- 17/10: "Buscar nos XML" com um lote traz no fim a ficha do lote lida do
  banco do Digifarma (entradas, vendas, perdas e transferências desde o
  início, saldo linha a linha, se passou do ponteiro) e compara cada período
  de XML guardado com o Digifarma, apontando onde diferem e o que caiu em
  dias sem XML. Para achar a diferença de 2 do BQ37M006 antes de 13/10.
  Resultado: o lote fecha em 0 no Digifarma (36 entram, 18 perda, 18
  vendas); a "diferença" era XML faltando. O 13/10 foi aceito no envio de
  15/10 (período 13–14/10). Lote regularizado.
- 17/10: relatório "Log do agente (7 dias)" na aba Servidor: por dia, as
  horas sem nenhuma linha (agente parado) e as mensagens, com e-mail, senha,
  token, hash, CPF e CNPJ mascarados. O agente passa a registrar "XML de
  envio arquivado" — para saber por que os XML de 14 e 15/10 não estão no
  servidor.
- 16/10: aviso no celular quando um envio é marcado como aceito/recusado no
  app (fila compara farmacia/aceites com farmacia/avisado/aceites pelo
  carimbo "em") e quando o arquivo de retorno traz resposta de verdade
  (hash + mensagem + data que não é 30/12/1899; identidade = hash + data do
  conteúdo, em farmacia/avisado/retorno). Regra nova `avisado` nas regras
  do Firebase (só o agente lê/escreve), publicada pelo próprio agente ao
  se atualizar. Na 1ª volta o que já existe entra como avisado, calado.
- `agente/ACESSO_REMOTO.bat`: testa admin, placa, OpenVPN, edição do Windows,
  OpenSSH, portas 22/3389, AnyDesk/TeamViewer e as 3 tarefas; liga SSH
  (PowerShell como shell), firewall da 22 só para rede local + VPN, RDP se
  for Pro; imprime o comando do Termux e grava `acesso_remoto_*.txt`.
  Opção `R` no FARMACIA.bat e no menu.ps1.

## Em andamento
- 10/10: LIGAR_FIREWALL.bat ligou o firewall (estava desligado nos 3 perfis)
  com a rede local 192.168.100.0/24 e as duas placas TAP liberadas; o PC é
  cliente da VPN (faixa 12.4.29.0/24). Em seguida o ACESSO_REMOTO.bat ligou
  SSH (22, PowerShell) e RDP (3389, NLA), presos à rede local e à placa da
  VPN. Falta: confirmar Digifarma nos terminais; a conta precisa de senha
  para o login remoto; testar de fora pela VPN (o celular precisa alcançar
  12.4.29.2 pelo túnel); reservar o IP 192.168.100.8 no roteador (DHCP).

## Pendências no servidor
- 10/10: chave nova do Firebase (código 4107a7…) instalada; INSTALAR_AGENTE
  testou Firebird e Firebase, sincronizou e recriou AgenteSNGPC (hora em
  hora) e AgenteSNGPC_Fila (5 min). Chaves sem uso excluídas no console
  (b111d4f8… em FARMACIA/estoque-remedios-7b785, 7376ea2a2a… em
  estoque-remedios); só a 4107a7… está ativa. Falta: conferir a fila pelo
  app; apagar a cópia estoque-remedios-7b785-firebase-adminsdk-*.json que
  sobrou na pasta do agente.
- A senha do SNGPC apareceu na tela do --teste (corrigido neste PR) e foi
  copiada para a conversa: trocar a senha do SNGPC/ANVISA.
- Acesso de fora: a VPN (15.228.76.94, AWS) é de fornecedor; SSH só na
  loja, por chave (conta continua sem senha). Fora da loja: app + fila.
- Mover a pasta do Desktop para C:\FARMACIA-SNGPC (conferir antes o
  caminho da chave no agente_config.json).
- Anvisa.exe: AnvisaSNGPC_Login rodou com sucesso em 10/10 07:00.

## Tentado e não deu certo
- Lógica de rede/firewall em CMD puro: frágil demais. O ACESSO_REMOTO.bat
  usa um bloco PowerShell no próprio arquivo.

## Como rodar / publicar
- Testes: `python3 teste_bat.py`, `cd agente && python3 teste_agente.py`,
  `node teste-fumaca.js`.
- O menu baixa as ferramentas da branch `main`: opção nova só chega ao
  servidor depois do merge.
