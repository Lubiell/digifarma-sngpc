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

## Situação (17/10)
Implementado (PR #32), mas não ativado: a farmácia decidiu enviar o SNGPC só
pelo servidor. Sem computador cadastrado o agente não lê a rede. Para ativar
um dia, basta seguir esta spec a partir do COMPARTILHAR_XML.bat.

## Solução escolhida
B, e C quando o Digifarma responder. O agente ganha `pastas_xml_rede` no
config: uma lista de `{computador, senha}`. A cada sincronização ele conecta
(`net use`, sem gravar credencial no Windows), copia o XML de envio,
desconecta. Detalhes em "Mudanças na implementação".

## Mudanças na implementação (17/10)
- **Pasta compartilhada:** não é `enviados\`, que é criada pelo agente e só
  existe no servidor. É a pasta onde o Digifarma do computador grava o
  `SNGPC.XML` (o `.bat` acha sozinha, a padrão é
  `C:\Digifarma\Aplicativos\VerificaXML`).
- **Onde ficam as cópias:** a cada sincronização o agente copia o XML de
  lá para o `enviados\` do servidor como `sngpc_AAAA-MM-DD_<COMPUTADOR>.xml`.
  A conferência, os Aceites e a busca da fórmula do hash leem esses arquivos
  sem outra mudança. Vale o XML mais novo entre o do servidor e os da rede.
- **Caminho da senha:** o servidor não tem tela para digitar a senha. Ela é
  digitada no app (botão "XML de outro computador"), passa pelo pedido em
  `farmacia/comando` (que só os autorizados leem) e o agente a apaga dali
  na primeira passagem, antes de atender. Depois fica só no
  `agente_config.json`. O computador só é gravado no config se o agente
  conseguir ler a pasta de lá. Mesmo com a senha vazada, ela só serve a
  partir do IP do servidor, e só para ler.

## Fora de escopo
- Gravar, apagar ou mudar qualquer arquivo nos outros computadores. O acesso é
  somente leitura.
- Publicar no Firebase mais do que hoje. O XML não sobe; sobe só o resultado
  da conferência, como já acontece com o do servidor.
- Compartilhar outra pasta que não a do `SNGPC.XML`, ou dar acesso a qualquer
  outro usuário ou IP.
- Recuperar envios antigos: o Digifarma sobrescreve o `SNGPC.XML` a cada
  envio, então de cada computador só vem o último envio feito nele, e daí
  em diante cada novo.
- Domínio, Active Directory, OneDrive ou serviço de nuvem.

## Arquivos afetados
`agente/agente_auto.py`, `agente/teste_agente.py`,
`agente/COMPARTILHAR_XML.bat` (novo), `agente/regras-firebase.json` (ação
`pasta_rede`), `app.js`, `sw.js`, `teste-fumaca.js`, `PROGRESS.md`.

## Como saber que deu certo
- O `COMPARTILHAR_XML.bat` imprime o caminho, e do servidor
  `dir \\COMPUTADOR\SNGPC_XML$` lista os XML.
- Tentar gravar no compartilhamento a partir do servidor dá "acesso negado".
- A aba Servidor mostra "CAIXA: ok, último sngpc_…_CAIXA.xml", e o próximo
  envio feito no caixa ou no computador do farmacêutico entra na conferência
  do XML e nos Aceites.
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
