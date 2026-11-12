# Spec — hospedagem no Cloudflare Pages
Data: 2026-10-23

## Problema
O app e os downloads do agente dependem do repositório ser público
(`lubiell.github.io` e `raw.githubusercontent.com`). Tornar o repositório
privado tira o app do ar e quebra a atualização e a instalação do agente
em todos os computadores da farmácia.

## Solução escolhida
Publicar o repositório no Cloudflare Pages (`https://digifarma-sngpc.pages.dev`),
com o app na raiz e os `.bat`, `agente/` e `ferramentas/` nos mesmos caminhos
de hoje. Só o que é baixado fica público. Código-fonte, histórico, PRs e specs
ficam privados no GitHub.

Descartado: exigir login para baixar (token em cada máquina ou Cloudflare
Access). Esconderia também os `.bat`, mas põe credencial em cada computador
e complica a instalação.

Mudanças:
1. `ferramentas/montar_site.py` copia o repositório para `_site/`, sem `docs/`,
   `.github/`, `CLAUDE.md`, `PROGRESS.md`, `README.md`, `teste_bat.py` e
   `teste-fumaca.js`. Build no Cloudflare: `python3 ferramentas/montar_site.py`,
   saída `_site`.
2. Trocar a base de download (`CRU`, `$CRU`, `REPO_CRU`) nos 13 pontos para
   `https://digifarma-sngpc.pages.dev` e o `URL_APP` do agente para o endereço
   novo.
3. O `index.html` aberto em `lubiell.github.io` redireciona para o endereço
   novo, para os celulares com o app instalado migrarem sozinhos.

Ordem (é ela que evita parar a farmácia):
1. O dono cria o projeto no Cloudflare ligado ao GitHub (branch de produção `main`).
2. O PR é validado pela prévia do Cloudflare e então recebe o merge.
3. Esperar todos os computadores rodarem o `ATUALIZAR_AGENTE`, ou o
   próprio agente se atualizar, e conferir no log que baixaram do endereço novo.
4. Só então o repositório vira privado.

## Fora de escopo
- O "módulo de receitas" citado no `sw.js` (não está neste repositório).
- Domínio próprio, Cloudflare Access e mudança nas regras do Firebase.
- Mexer no conteúdo dos downloads: só muda o endereço.

## Arquivos afetados
`ferramentas/montar_site.py` (novo), `index.html`, `sw.js` (versão),
`menu.ps1`, `FARMACIA.bat`, `ACHAR_APPJS.bat`, `agente/agente_auto.py`,
`agente/ATUALIZAR_AGENTE.bat`, `agente/APONTAR_SERVIDOR.bat`,
`agente/INSTALAR_CHAVE.bat`, `agente/CONSERTAR_TUDO.bat`,
`agente/SERVIDOR_AGORA.bat`, `agente/COMPARTILHAR_XML.bat`.

## Como saber que deu certo
- Os três testes locais e o CI passam.
- Na prévia do Cloudflare: o app abre e faz login, e `agente/arquivos.json`,
  `agente/agente_auto.py` e `FARMACIA.bat` são baixados com conteúdo idêntico
  ao da `main`. `docs/` e `CLAUDE.md` dão 404.
- Depois do merge, o `ATUALIZAR_AGENTE` num computador da farmácia baixa do
  endereço novo.

## Risco e volta atrás
- Computador que nunca atualizar antes do repositório virar privado fica sem
  atualização. Volta: deixar o repositório público de novo, que o endereço
  antigo volta a funcionar na hora.
- Avisos (push) do app: o token é por endereço, então cada celular precisa
  abrir o app novo e permitir os avisos de novo.
- App instalado no celular pelo endereço antigo: o redirecionamento leva para
  o novo, mas pode ser preciso reinstalar o ícone.
- Reverter o código: revert do PR. Os dois endereços funcionam enquanto o
  repositório estiver público.
