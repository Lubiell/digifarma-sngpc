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
