# Plano: dividir o agente_auto.py

O `agente_auto.py` tem ~7.600 linhas num arquivo só. Funciona e é testado,
mas ninguém novo consegue achar nada nele. Este é o plano para dividir **sem
derrubar o servidor**, que a farmácia mal alcança.

## Por que não dá para dividir de uma vez

1. **Atualização.** Até o PR que criou este plano, o botão "Atualizar o
   agente" baixava só o `agente_auto.py`. Um principal novo importando um
   módulo que o servidor nunca recebeu = agente parado, sem fila e sem o
   próprio botão para consertar.
   *Resolvido na etapa 1:* o atualizador lê `agente/arquivos.json`, baixa e
   confere todos os arquivos, importa o agente novo num processo à parte e,
   se ele não carregar, volta todos os arquivos.
2. **Testes que trocam funções.** O `teste_agente.py` substitui funções do
   módulo para simular o banco (`ag.consultar = ...`, 34 lugares). Depois da
   divisão, quem chama `consultar` dentro de `coleta.py` usa o `consultar` de
   `coleta`, não o de `agente_auto`: o teste trocaria a função errada e
   passaria a bater no banco de verdade. Cada etapa da divisão tem de mudar
   esses pontos para o módulo novo (`coleta.consultar = ...`).
3. **ATUALIZAR_AGENTE.bat.** O caminho manual baixa uma lista fixa
   (`agente_auto.py`, `mapa_xml.py`, `teste_agente.py`). Antes do primeiro
   módulo novo, ele precisa ler o `arquivos.json` também.

## Ordem

| Etapa | O quê | Pronto quando |
|---|---|---|
| 1 | Atualizador de vários arquivos + `arquivos.json` (feito) | O servidor atualizou pelo botão e a resposta lista os arquivos trocados |
| 2 | `ATUALIZAR_AGENTE.bat` lê o `arquivos.json` | Rodado uma vez no servidor |
| 3 | Um módulo por PR, **movendo funções sem mudar lógica**, e o módulo entra no `arquivos.json` no mesmo PR | Testes e CI verdes; servidor atualizou e a fila continuou rodando |

## Módulos (pelas seções que o arquivo já tem)

| Módulo | Linhas hoje | Conteúdo |
|---|---|---|
| `consultas.py` | 76–608 | `CONSULTAS` e os pedaços de SQL (receita, venda paga, controlado) |
| `infra.py` | 609–775 | log, config, conexão Firebird/Firebase, `consultar`, `executar` |
| `coleta.py` | 821–2831 | leitura do Digifarma, descoberta de colunas, `montar_inventario` |
| `publicacao.py` | 2832–3118 | publicar no Firebase, histórico, avisos no celular |
| `escrita.py` | parte de 3119–7459 | as únicas escritas no Digifarma (desmarcar, zerar, ajustar) e a trava de prazo |
| `servidor.py` | parte de 3119–7459 | atualizar o agente, regras, Anvisa.exe, tarefas agendadas |
| `relatorios.py` | parte de 3119–7459 | os modos de relatório (`--ponteiro`, `--pendentes`…) |
| `agente_auto.py` | 7460– | entrada: argumentos, fila e `principal()` — fica com este nome, que as tarefas agendadas e os .bat chamam |

Começar por `consultas.py`: só dados, sem funções que os testes troquem.
Deixar `escrita.py` por último entre os de lógica: é o que mexe no banco
da farmácia e merece a revisão mais calma.

## Regras para cada etapa

- Mover, não reescrever. Mudança de lógica vai em PR separado.
- O módulo entra no `arquivos.json` no mesmo PR em que nasce.
- Depois do merge, atualizar o servidor pelo botão e conferir na aba
  Servidor que o agente continuou passando (`vistoEm` andando) antes do
  próximo módulo.
