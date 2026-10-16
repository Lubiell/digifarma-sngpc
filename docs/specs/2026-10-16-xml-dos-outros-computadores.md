# Spec — agente lê os XML enviados pelos outros computadores
Data: 2026-10-16

## Problema
O SNGPC é transmitido pelo Digifarma de três computadores: servidor, caixa/balcão
e computador do farmacêutico. Cada um grava o XML enviado no próprio disco, e o
agente só lê a pasta `enviados\` do servidor. Por isso os envios feitos nos
outros dois computadores ficam de fora da conferência do XML e da aba Aceites,
e a tentativa de descobrir a fórmula do hash pode estar usando arquivos errados.
O XML tem nome e CPF de paciente e de prescritor.

## Alternativas
- **A. Cada computador empurra para o servidor.** Uma tarefa em cada computador
  copia o XML para uma pasta compartilhada do servidor. Custo: a senha de
  gravação no servidor fica guardada em dois computadores de balcão, e é preciso
  uma tarefa agendada em cada um.
- **B. O servidor puxa, só leitura (recomendada).** Em cada computador, um
  `COMPARTILHAR_XML.bat` rodado uma vez:
  - compartilha só a pasta `enviados\` como oculta (`SNGPC_XML$`), em modo
    SOMENTE LEITURA, para um usuário local próprio (`leitor_sngpc`) com senha
    forte gerada na hora;
  - libera o compartilhamento no firewall só para o IP do servidor;
  - imprime o nome do computador e o caminho.

  O agente lê `\\COMPUTADOR\SNGPC_XML$` com essa senha, guardada só no
  `agente_config.json` do servidor (onde já ficam as outras credenciais), e
  copia os XML para `enviados_rede\<COMPUTADOR>\` no servidor. Custo: ir uma
  vez a cada computador (presencial ou por acesso remoto). Também só lê
  enquanto o computador está ligado; o que ele já copiou fica.
- **C. Digifarma grava todos numa pasta do servidor.** É o item (e) do chamado.
  É a mais limpa, sem senha nova, mas depende do Digifarma e não tem prazo.
  O código de B atende C sem mudança: basta apontar a pasta.

## Solução escolhida
B, e C quando o Digifarma responder. O agente ganha `pastas_xml_rede` no
config: uma lista de `{caminho, usuario, senha}`. A cada sincronização ele
conecta (`net use`, sem gravar credencial no Windows), copia os XML de envio
novos, desconecta, e a conferência e os Aceites passam a ler `enviados\` mais
`enviados_rede\*\`. O relatório Login SNGPC passa a tentar a fórmula do hash
também nesses arquivos.

## Fora de escopo
- Gravar, apagar ou mudar qualquer arquivo nos outros computadores. O acesso é
  somente leitura.
- Publicar no Firebase mais do que hoje. O XML não sobe; sobe só o resultado
  da conferência, como já acontece com o do servidor.
- Compartilhar outra pasta que não `enviados\`, ou dar acesso a qualquer outro
  usuário ou IP.
- Domínio, Active Directory, OneDrive ou serviço de nuvem.

## Arquivos afetados
`agente/agente_auto.py`, `agente/teste_agente.py`,
`agente/COMPARTILHAR_XML.bat` (novo), `agente/teste_bat.py` ou `teste_bat.py`,
`PROGRESS.md`, `.gitignore` (`enviados_rede/`).

## Como saber que deu certo
- O `COMPARTILHAR_XML.bat` imprime o caminho, e do servidor
  `dir \\COMPUTADOR\SNGPC_XML$` lista os XML.
- Tentar gravar no compartilhamento a partir do servidor dá "acesso negado".
- Na aba XML aparecem os envios de 12, 14 e 15/10 feitos no caixa e no
  computador do farmacêutico.
- Testes simulam pasta de rede fora do ar e senha errada sem derrubar a
  sincronização, e confirmam que nenhuma senha vai para log, Firebase ou tela.

## Risco e volta atrás
- **Senha do `leitor_sngpc` vazada:** dá leitura dos XML daquele computador
  pela rede da loja, e só a partir do IP do servidor. Para trocar ou revogar,
  rode o `.bat` de novo com `/remover`, que apaga o compartilhamento, o usuário
  e a regra do firewall.
- **Computador desligado ou fora da rede:** o agente registra no log e segue
  com o que tem.
- **Desligar:** apague `pastas_xml_rede` do config. O agente volta a ler só o
  servidor.
