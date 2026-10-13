# Manual de balcão — app FARMÁCIA SNGPC

Uma página de consulta rápida. O app roda num celular só, o do responsável.
Ele **só mostra**: quem corrige é o Digifarma. Corrija antes do próximo
envio.

## Rotina do dia

0. **Uma vez só:** Servidor → **Ligar avisos neste celular** e depois
   **Mandar um aviso de teste**. O celular passa a avisar a venda sem
   receita na hora, e de manhã manda o resumo do dia.
1. **Vendas → Com problema.** Toda venda listada ali vai ser recusada ou
   escriturada errada no próximo envio. Corrija no Digifarma **antes** do
   envio. Esta é a prioridade do dia.
2. **Vendas → Vendas de hoje.** "Falta lançar a receita" = lance a receita no
   Digifarma.
3. **Saldo.** Confira na prateleira só os itens que aparecem ali (ver tabela).
4. **Servidor.** Se a aba tiver um **!** ou o aviso "o agente não dá sinal
   há N minutos", o servidor parou de mandar dados: os números da tela não
   valem para conferir prateleira até ele voltar.

## Vendas → Com problema

| Aviso | O que fazer no Digifarma |
|---|---|
| Controlado vendido sem receita escriturada | Lance a receita da venda (número da venda na tela). |
| Item sem lote informado | Informe o lote vendido na venda. |
| Produto sem registro M.S. cadastrado | Corrija o cadastro do produto (registro M.S. da caixa). |

## Saldo (diferença entre o Digifarma e a ANVISA)

**+** = sobra no Digifarma, **−** = falta no Digifarma. Antes de mexer em
qualquer coisa, **conte a prateleira**.

| Aviso | O que significa | O que fazer |
|---|---|---|
| Saldo negativo no Digifarma | Erro de lançamento, não de prateleira | Ache o lançamento errado no Digifarma. |
| Mesmo lote em dois registros M.S. | O mesmo lote está em dois cadastros | Leia o laboratório na caixa. "Os totais batem" = foi lançado no cadastro errado, não falta mercadoria. |
| Só aparece na ANVISA | A ANVISA tem o lote; o Digifarma não | Procure a entrada desse lote (nota fiscal). |
| Quantidade diferente | Os dois conhecem o lote, com números diferentes | Conte a prateleira e confira as vendas e entradas recentes do lote no Digifarma. |
| Lote zerado na ANVISA | Costuma ser entrada ainda não transmitida | Normalmente some depois do próximo envio. |
| Produto zerado na ANVISA | O registro inteiro não está no inventário | Confira se a entrada foi transmitida. |
| Produto sem registro M.S. | Sem M.S. não dá para comparar | Corrija o cadastro. |

**Barra amarela "Estes números podem não ser divergência de estoque":** a
comparação está prejudicada (inventário da ANVISA velho, envio recusado…).
Não acerte estoque enquanto ela estiver na tela.

## XML (o que saiu no banco × o que subiu no envio)

| Aviso | O que fazer |
|---|---|
| Saiu no banco e não está no XML | A venda não subiu: veja se o envio foi recusado. |
| Está no XML e não achei no banco | Venda cancelada ou alterada depois do envio: avise o responsável. |
| Mesmo lote, M.S. diferente no XML | O cadastro mudou depois do envio. O XML já enviado não se conserta. |

## Desmarcar controlado/antibiótico (só produto marcado por engano)

1. **Servidor → Ligar a escrita por 60 minutos** (fecha sozinha).
2. **Saldo →** abra o produto → **Desmarcar controlado/antibiótico no Digifarma**.
3. Confira no cadastro do Digifarma. Para voltar atrás: marque a caixa de
   novo no Digifarma.

Desmarcado, o produto **sai do SNGPC**. Nunca use para "sumir" com divergência.
