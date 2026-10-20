# digifarma-sngpc — regras para o Claude

## Merge
- PR com o CI (`testes`) verde e os três testes locais passando tem merge
  automático, mesmo tocando dado de saúde. Decisão da farmácia em 2026-10-20.
- Fica em RASCUNHO, com spec em `docs/specs/` e sem merge até o ok da farmácia,
  o PR que mexer em:
  - regras do Firebase (`agente/regras-firebase.json`);
  - schema ou migração de dado;
  - envio ou formato de arquivo para a Anvisa (XML e API do SNGPC).

## Testes locais
```
cd agente && python3 teste_agente.py
python3 teste_bat.py
node teste-fumaca.js
```
