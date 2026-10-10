# PROGRESS — digifarma-sngpc
Atualizado: 2026-10-09 | Máquina: nuvem (Claude Code)

## Estado atual
App no ar em GitHub Pages. Agente parado no servidor desde 10/09 (ver
"Pendências no servidor"). Novo `agente/ACESSO_REMOTO.bat` para entrar no
servidor de longe, ainda não executado no Windows.

## Feito
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

## Pendências no servidor (agente parado desde 10/09)
1. `chave-firebase.json` não existe na pasta do agente (sumiu com uma pasta
   apagada): é o "Último resultado: 1" da fila. Chave nova já criada no
   console; instalar: Downloads -> chave-firebase.json na pasta do agente.
2. Tarefa `AgenteSNGPC` aponta para uma pasta
   (`C:\Digifarma\Aplicativos\VerificaXML --auto`), erro -2147024891.
   Conserto: INSTALAR_AGENTE.bat como admin dentro da pasta do agente.
3. Anvisa.exe nunca completou: sem anvisa.log, última tentativa 08/09.
4. Mover a pasta do Desktop para `C:\FARMACIA-SNGPC` (já sumiu 2x).

## Tentado e não deu certo
- Lógica de rede/firewall em CMD puro: frágil demais. O ACESSO_REMOTO.bat
  usa um bloco PowerShell no próprio arquivo.

## Como rodar / publicar
- Testes: `python3 teste_bat.py`, `cd agente && python3 teste_agente.py`,
  `node teste-fumaca.js`.
- O menu baixa as ferramentas da branch `main`: opção nova só chega ao
  servidor depois do merge.
