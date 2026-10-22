/* Teste de fumaça — roda os dois app.js num DOM simulado.
   Objetivo: pegar erro de sintaxe, id de elemento que não existe no HTML
   e regressão nas funções de validade e busca, antes de publicar.

   uso: node teste-fumaca.js            (a partir da pasta do app)
        node teste-fumaca.js ../ESTOQUE
*/
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const pasta = path.resolve(process.argv[2] || '.');
const nome = path.basename(pasta);

let falhas = 0;
const ok = (t) => console.log('  ok    ' + t);
const erro = (t, e) => { falhas++; console.log('  FALHA ' + t + (e ? '\n        ' + e : '')); };
function conferir(titulo, fn) {
  try { fn(); ok(titulo); } catch (e) { erro(titulo, e.message); }
}
function igual(a, b, msg) {
  if (String(a) !== String(b)) throw new Error(`${msg}: esperado ${b}, veio ${a}`);
}

/* ---------- DOM simulado ---------- */
const idsUsados = new Set();

function elemento(id) {
  const el = {
    id, hidden: false, value: '', textContent: '', innerHTML: '',
    className: '', type: '', checked: false, style: {}, dataset: {},
    srcObject: null, min: '', inputMode: '',
    classList: { toggle() {}, add() {}, remove() {}, contains: () => false },
    appendChild(x) { return x; },
    append() {},
    removeChild() {},
    remove() {},
    setAttribute() {}, getAttribute: () => null,
    focus() {}, play: async () => {},
    addEventListener() {},
    querySelector: () => null,
    querySelectorAll: () => [],
    set onclick(v) { this._onclick = v; },
    get onclick() { return this._onclick; },
    set oninput(v) { this._oninput = v; },
    get oninput() { return this._oninput; },
    set onchange(v) { this._onchange = v; },
    get onchange() { return this._onchange; }
  };
  return el;
}

const cache = new Map();
const idsNoHtml = new Set(
  [...fs.readFileSync(path.join(pasta, 'index.html'), 'utf8').matchAll(/\bid="([^"]+)"/g)].map((m) => m[1])
);

const documento = {
  getElementById(id) {
    idsUsados.add(id);
    if (!cache.has(id)) cache.set(id, elemento(id));
    return cache.get(id);
  },
  createElement: (t) => elemento('<' + t + '>'),
  querySelectorAll: () => [],
  addEventListener() {}
};

const armazem = () => {
  const m = new Map();
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: (k) => m.delete(k)
  };
};

const gravados = [];
function refFalsa(caminho) {
  const r = {
    on: () => () => {},
    off() {},
    get: async () => ({ val: () => null }),
    set: async (v) => { gravados.push([caminho, v]); },
    update: async () => {},
    remove: async () => {},
    push: async () => ({ key: 'chave-teste' })
  };
  r.push = Object.assign(async () => ({ key: 'chave-teste' }), { key: 'chave-teste' });
  r.push = () => ({ key: 'chave-teste', then: (f) => Promise.resolve({ key: 'chave-teste' }).then(f) });
  return r;
}

const firebaseFalso = {
  initializeApp() {},
  auth: () => ({
    onAuthStateChanged() {},                    // não dispara: só queremos carregar
    signInWithEmailAndPassword: async () => {},
    signOut: async () => {}
  }),
  database: () => ({ ref: (c) => refFalsa(c) })
};

const contexto = {
  console,
  location: { protocol: 'https:', href: 'https://exemplo.test/' },
  document: documento,
  firebase: firebaseFalso,
  localStorage: armazem(),
  sessionStorage: armazem(),
  navigator: { mediaDevices: {}, serviceWorker: undefined },
  crypto: globalThis.crypto,
  TextEncoder,
  setTimeout, clearTimeout, requestAnimationFrame: () => {},
  module: { exports: {} }
};
contexto.window = contexto;
contexto.globalThis = contexto;
contexto.window.addEventListener = () => {};

console.log('\n' + nome + '\n' + '-'.repeat(nome.length));

/* ---------- 1. carrega o app.js ---------- */
let exportado = {};
conferir('app.js carrega sem erro de sintaxe nem elemento faltando', () => {
  const codigo = fs.readFileSync(path.join(pasta, 'app.js'), 'utf8');
  vm.createContext(contexto);
  new vm.Script(codigo, { filename: 'app.js' }).runInContext(contexto);
  exportado = contexto.module.exports;
});

/* ---------- 2. todo id usado existe no HTML ---------- */
conferir('todos os getElementById existem no index.html', () => {
  const orfaos = [...idsUsados].filter((id) => !idsNoHtml.has(id));
  if (orfaos.length) throw new Error('sem elemento no HTML: ' + orfaos.join(', '));
});

/* ---------- 3. JSON e manifest ---------- */
/* Aba sem secao e aba morta: o botao aparece, o usuario toca e a tela
   fica em branco. Secao sem aba e o contrario — a tela existe e nao ha
   como chegar nela. Os dois so aparecem usando o app, e nenhum da erro. */
conferir('toda aba da navegação tem a seção dela, e vice-versa', () => {
  const html = fs.readFileSync(path.join(pasta, 'index.html'), 'utf8');
  const abas = [...html.matchAll(/data-vista="([a-z]+)"/g)].map((m) => m[1]);
  const secoes = [...html.matchAll(/<section id="v-([a-z]+)"/g)].map((m) => m[1]);
  const semSecao = abas.filter((v) => !secoes.includes(v));
  const semAba = secoes.filter((v) => !abas.includes(v));
  if (semSecao.length) throw new Error('aba sem seção: ' + semSecao.join(', '));
  if (semAba.length) throw new Error('seção sem aba: ' + semAba.join(', '));
  if (!abas.length) throw new Error('nenhuma aba encontrada no index.html');
});

conferir('manifest.json é JSON válido e aponta para ícones existentes', () => {
  const m = JSON.parse(fs.readFileSync(path.join(pasta, 'manifest.json'), 'utf8'));
  m.icons.forEach((i) => {
    if (!fs.existsSync(path.join(pasta, i.src))) throw new Error('ícone faltando: ' + i.src);
  });
});

conferir('sw.js lista só arquivos que existem', () => {
  const sw = fs.readFileSync(path.join(pasta, 'sw.js'), 'utf8');
  const casca = [...sw.matchAll(/'\.\/([^']*)'/g)].map((m) => m[1]).filter(Boolean);
  casca.forEach((f) => {
    if (!fs.existsSync(path.join(pasta, f))) throw new Error('no cache mas não existe: ' + f);
  });
});

/* O aviso do agente chega como Web Push e quem o mostra e o sw.js. Push
   que nao vira notificacao o navegador pune, e aviso que nao aparece e
   venda sem receita indo para o envio. So no app que tem o handler. */
const textoSw = fs.readFileSync(path.join(pasta, 'sw.js'), 'utf8');
if (textoSw.includes("addEventListener('push'")) {
  conferir('aviso do agente (push) vira notificação na tela', () => {
    const ouvintes = {};
    const mostradas = [];
    const self = {
      addEventListener: (tipo, f) => { ouvintes[tipo] = f; },
      registration: { scope: 'https://exemplo/', showNotification: (t, o) => { mostradas.push([t, o.body]); return Promise.resolve(); } },
      clients: { matchAll: () => Promise.resolve([]), openWindow: () => Promise.resolve() },
      location: { origin: 'https://exemplo' },
      skipWaiting: () => Promise.resolve()
    };
    vm.runInNewContext(textoSw, { self, caches: {}, fetch: () => {}, URL, Promise, console });
    const empurrar = (dados) => ouvintes.push({ data: dados, waitUntil: () => {} });
    empurrar({ json: () => ({ notification: { title: 'Venda sem receita', body: 'Venda 46505' } }) });
    empurrar({ json: () => ({ data: { titulo: 'Conferência do dia', texto: '2 divergências' } }) });
    empurrar(null);
    igual(mostradas.map((m) => m.join(': ')).join(' | '),
      'Venda sem receita: Venda 46505 | Conferência do dia: 2 divergências | Farmácia SNGPC: Há pendências no SNGPC.',
      'avisos mostrados');
  });
}

/* ---------- 5. regressao: hidden tem que vencer o CSS ---------- */
conferir('elemento com hidden nao aparece, mesmo com display no CSS', () => {
  // Sem [hidden]{display:none !important}, uma regra de autor como
  // .modal{display:flex} ganha do [hidden]{display:none} do navegador
  // (folha do autor > folha do agente) e a tela escondida aparece.
  const css = fs.readFileSync(path.join(pasta, 'estilo.css'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '');
  const html = fs.readFileSync(path.join(pasta, 'index.html'), 'utf8');

  const display = new Map();
  for (const m of css.matchAll(/([^{}]+)\{([^}]*)\}/g)) {
    const d = /display\s*:\s*([a-z-]+)\s*(!important)?/.exec(m[2]);
    if (!d) continue;
    for (const sel of m[1].split(',')) {
      display.set(sel.trim(), { valor: d[1], forte: Boolean(d[2]) });
    }
  }

  const neutraliza = display.get('[hidden]');
  if (!neutraliza || neutraliza.valor !== 'none' || !neutraliza.forte) {
    throw new Error('falta [hidden]{display:none !important} no estilo.css');
  }

  const nascemHidden = [...html.matchAll(/<\w+[^>]*>/g)]
    .map((m) => m[0])
    .filter((tag) => /\shidden[\s>/]/.test(tag))
    .map((tag) => ({
      id: (/\bid="([^"]+)"/.exec(tag) || [, '(sem id)'])[1],
      classes: (/\bclass="([^"]*)"/.exec(tag) || [, ''])[1].split(/\s+/).filter(Boolean)
    }));

  if (!nascemHidden.length) throw new Error('nenhum elemento hidden no HTML — teste sem valor');

  const vazando = [];
  for (const el of nascemHidden) {
    for (const c of el.classes) {
      const regra = display.get('.' + c);
      if (regra && regra.valor !== 'none' && regra.forte) {
        vazando.push('#' + el.id + ' .' + c + '=display:' + regra.valor + ' !important');
      }
    }
  }
  if (vazando.length) throw new Error('aparece na tela apesar de hidden: ' + vazando.join(', '));
});

/* ---------- 6. aviso de file:// ---------- */
conferir('avisa quando a pagina e aberta por file://', () => {
  const codigo = fs.readFileSync(path.join(pasta, 'app.js'), 'utf8');
  if (!/location\.protocol\s*===\s*'file:'/.test(codigo)) {
    throw new Error('app.js nao trata a abertura por file://');
  }
  // roda de novo com file:// e confere que a barra de estado aparece
  const ctx = Object.assign({}, contexto, {
    location: { protocol: 'file:', href: 'file:///C:/x/index.html' },
    module: { exports: {} }
  });
  ctx.window = ctx;
  cache.clear();
  vm.createContext(ctx);
  new vm.Script(codigo, { filename: 'app.js (file://)' }).runInContext(ctx);
  const barra = cache.get('barra-estado');
  if (!barra || barra.hidden) throw new Error('a barra de estado devia aparecer em file://');
  if (!/file:\/\//.test(barra.textContent)) throw new Error('o aviso nao explica o problema');
});

/* ---------- 6. regras de negócio ---------- */
if (exportado.fimDaValidade) {
  conferir('validade MM/AA vale até o ÚLTIMO dia do mês', () => {
    const fim = exportado.fimDaValidade('02/24');   // ano bissexto
    igual(fim.getMonth(), 1, 'mês');
    igual(fim.getDate(), 29, 'dia');
    const fim2 = exportado.fimDaValidade('09/27');
    igual(fim2.getDate(), 30, 'dia de setembro');
    igual(exportado.fimDaValidade('13/27'), null, 'mês 13 deve ser inválido');
    igual(exportado.fimDaValidade('agosto'), null, 'texto solto deve ser inválido');
  });

  conferir('item vence só depois do último dia do mês', () => {
    const hoje = new Date();
    const mm = String(hoje.getMonth() + 1).padStart(2, '0');
    const aa = String(hoje.getFullYear() % 100).padStart(2, '0');
    const dias = exportado.diasAteVencer(mm + '/' + aa);
    if (dias < 0) throw new Error('o mês corrente não pode estar vencido (veio ' + dias + ')');
  });

  conferir('situação classifica vencido, baixo e em dia', () => {
    igual(exportado.situacao({ validade: '01/20', quantidade: 5 }), 'vencido', 'vencido');
    igual(exportado.situacao({ quantidade: 2, minimo: 5 }), 'baixo', 'estoque baixo');
    igual(exportado.situacao({ quantidade: 50, minimo: 5 }), 'ok', 'em dia');
  });
}

conferir('busca ignora acento e maiúscula', () => {
  const alvo = { nome: 'Diazepam Solução', ms: '1234', codigoBarras: '789', lote: 'A1', descricao: 'Diazepam Solução' };
  const campos = exportado.combina.length >= 3 ? ['descricao', 'ms', 'lote'] : null;
  const teste = campos
    ? exportado.combina(alvo, 'solucao', campos)
    : exportado.combina(alvo, 'SOLUCAO');
  if (!teste) throw new Error('não achou "solucao" em "Solução"');
});

if (exportado.pintarPonteiroSugerido) {
  conferir('ponteiro acertado a mao mostra o botao de desfazer, e so entao', () => {
    const criados = [];
    const original = documento.createElement;
    documento.createElement = (t) => { const e = original(t); criados.push(e); return e; };
    try {
      const botao = () => criados.find((e) => e.textContent === 'Desfazer o acerto');
      exportado.estado.inventario = { envio: { ponteiroForcado: true,
        ULT_SAIDA_VENDA_NOTA_ID: 48307, ponteiroDoDigifarma: 48251 } };
      exportado.pintarPonteiroSugerido();
      if (!botao()) throw new Error('com acerto ativo, sem botao de desfazer');
      if (typeof botao().onclick !== 'function') throw new Error('botao sem acao');
      criados.length = 0;
      exportado.estado.inventario = { envio: { ponteiroForcado: false } };
      exportado.pintarPonteiroSugerido();
      if (botao()) throw new Error('sem acerto, o botao de desfazer nao devia aparecer');
    } finally {
      documento.createElement = original;
      exportado.estado.inventario = {};
    }
  });
}

if (exportado.vendasPorDia) {
  conferir('vendas por dia: o dia mais novo primeiro, itens em ordem alfabética', () => {
    exportado.estado.inventario = { vendasRecentes: [
      { venda: 48746, quando: '2026-10-21T14:33:50', descricao: 'VENLAFAXINA 37,5MG', lote: 'CLV4N003' },
      { venda: 48718, quando: '2026-10-21T07:56:50', descricao: 'NORFLOXACINO 400 MG C/ 14 CPR', lote: 'A06A00426' },
      { venda: 48746, quando: '2026-10-21T14:33:50', descricao: 'ESCITALOPRAM OXALATO 20 MG', lote: '2605210' },
      { venda: 48769, quando: '2026-10-22T10:11:00', descricao: 'PARAC+CODEINA 30MG + 500MG', lote: 'B26C2630' },
      { venda: 48720, quando: '2026-10-21T08:27:16', descricao: 'CELECOXIBE 200MG 30CPS', lote: '47880040' },
      { venda: 1, quando: '', descricao: 'SEM DATA' }
    ] };
    try {
      const dias = exportado.vendasPorDia();
      igual(dias.map((d) => d.dia).join(','), '2026-10-22,2026-10-21', 'dias');
      igual(dias[1].itens.map((v) => v.descricao.split(' ')[0]).join(','),
        'CELECOXIBE,ESCITALOPRAM,NORFLOXACINO,VENLAFAXINA', 'ordem alfabética');
    } finally {
      exportado.estado.inventario = {};
    }
  });
}

if (exportado.pintarComando && exportado.pintarRelatorio) {
  conferir('pedido na fila e erro do agente aparecem tambem na aba Servidor', () => {
    const barra = documento.getElementById('fila-comando-servidor');
    try {
      exportado.estado.comando = { acao: 'xml', estado: 'erro', mensagem: 'pasta nao encontrada' };
      exportado.pintarComando();
      if (barra.hidden) throw new Error('erro do agente escondido na aba Servidor');
      if (!barra.textContent.includes('pasta nao encontrada')) throw new Error('sem a mensagem do erro');
      exportado.estado.comando = null;
      exportado.pintarComando();
      if (!barra.hidden) throw new Error('sem pedido, a barra devia sumir');
    } finally {
      exportado.estado.comando = null;
    }
  });

  conferir('app reaberto mostra a resposta do ultimo relatorio pedido', () => {
    const bloco = documento.getElementById('bloco-relatorio');
    try {
      exportado.estado.relatorioPedido = null;
      exportado.estado.comando = { acao: 'xml', estado: 'concluido', concluidoEm: '2026-10-10T16:40:00' };
      exportado.estado.relatorios = { xml: { texto: 'BUSCA NOS XML', em: '2026-10-10T16:40:00' } };
      bloco.hidden = true;
      exportado.pintarRelatorio();
      if (bloco.hidden) throw new Error('resposta do xml nao apareceu');
      igual(documento.getElementById('relatorio').textContent, 'BUSCA NOS XML', 'texto do relatorio');
    } finally {
      exportado.estado.comando = null;
      exportado.estado.relatorios = {};
    }
  });
}

if (exportado.retornoSemResposta) {
  conferir('retorno vazio do Digifarma (datas 30/12/1899) é reconhecido', () => {
    const vazio = 'HASH: \nDATA TRANSMISSÃO: 30/12/1899\nDATA VALIDAÇÃO: 30/12/1899\n'
      + 'INICIO PERIODO: 30/12/1899\nFIM DO PERIODO: 30/12/1899\nMSG DE RETORNO: \n'
      + '--------------------\n\nRETORNO COMPLETO: \n';
    igual(exportado.retornoSemResposta(vazio), true, 'modelo vazio');
    igual(exportado.retornoSemResposta(''), true, 'arquivo sem texto');
    igual(exportado.retornoSemResposta(vazio.replace('HASH: ', 'HASH: 92606BDD')), false, 'com hash');
    igual(exportado.retornoSemResposta(vazio + 'Arquivo aceito\n'), false, 'texto solto no fim');
    igual(exportado.retornoSemResposta('DATA VALIDAÇÃO: 14/10/2026 21:22'), false, 'data de verdade');
  });
}

if (exportado.detalheDoSaldo && exportado.pintarConfiancaDoSaldo) {
  conferir('saldo igual dos dois lados com movimento pendente mostra o movimento e não diz "saldos diferentes"', () => {
    const criados = [];
    const original = documento.createElement;
    documento.createElement = (t) => { const e = original(t); criados.push(e); return e; };
    try {
      const textos = () => criados.map((e) => e.textContent);
      exportado.detalheDoSaldo({ codigo: '13139', saldoDigifarma: 10, saldoSngpc: 10,
        movimentoDesdeEnvio: -2, esperadoSngpc: 8, diferenca: 2, motivo: 'quantidade',
        ms: '1234567890123', lote: 'AB12' }, 2);
      const t = textos();
      if (!t.includes('Movimento desde a foto') || !t.includes('-2')) throw new Error('movimento não aparece');
      if (!t.includes('SNGPC esperado hoje (foto + movimento)') || !t.includes('8')) throw new Error('esperado não aparece');
      if (t.some((x) => x.includes('com saldos diferentes'))) throw new Error('diz "saldos diferentes" com saldos iguais');
      if (!t.some((x) => x.includes('mesmo número'))) throw new Error('sem a explicação do caso');
      const investigar = criados.find((e) => e.textContent === 'Investigar este lote no servidor');
      if (!investigar) throw new Error('sem o botão de investigar o lote');
      gravados.length = 0;
      investigar.onclick();
      const pedido = gravados.find(([c]) => c === 'farmacia/comando');
      if (!pedido || pedido[1].acao !== 'saldo' || pedido[1].texto !== '1234567890123|AB12')
        throw new Error('pedido de investigação errado: ' + JSON.stringify(pedido));

      criados.length = 0;
      exportado.detalheDoSaldo({ codigo: '1', saldoDigifarma: 7, saldoSngpc: 5, diferenca: 2,
        motivo: 'quantidade', ms: '1', lote: 'X' }, 2);
      if (textos().includes('Movimento desde a foto')) throw new Error('sem movimento, a linha não devia aparecer');
      if (!textos().some((x) => x.includes('com saldos diferentes'))) throw new Error('divergência comum perdeu a nota');

      const barra = documento.getElementById('saldo-confianca');
      exportado.estado.inventario = { inventario: { confianca: { confiavel: true }, jaNaAnvisa: 3 } };
      exportado.pintarConfiancaDoSaldo();
      if (barra.hidden || !barra.innerHTML.includes('3 lote(s)')) throw new Error('lotes que já batem não avisados');
      exportado.estado.inventario = { inventario: { confianca: { confiavel: true }, jaNaAnvisa: 0 } };
      exportado.pintarConfiancaDoSaldo();
      if (!barra.hidden) throw new Error('sem motivo, a barra devia sumir');
    } finally {
      documento.createElement = original;
      exportado.estado.inventario = {};
    }
  });
}

if (exportado.gravarPedido && exportado.pintarRelatorio) {
  conferir('pedido na fila não é apagado por outro sem perguntar', () => {
    try {
      gravados.length = 0;
      exportado.estado.comando = { acao: 'saldo', estado: 'pendente', pedidoEm: '2026-10-16T09:10:00' };
      exportado.gravarPedido({ acao: 'sincronizar_vendas', estado: 'pendente' });
      if (gravados.some(([c]) => c === 'farmacia/comando')) throw new Error('gravou por cima sem confirmar');
      exportado.estado.comando = { acao: 'sincronizar_vendas', estado: 'pendente' };
      exportado.gravarPedido({ acao: 'sincronizar_vendas', estado: 'pendente' });
      if (!gravados.some(([c]) => c === 'farmacia/comando')) throw new Error('mesmo pedido repetido pediu confirmação');
      gravados.length = 0;
      exportado.estado.comando = { acao: 'saldo', estado: 'concluido' };
      exportado.gravarPedido({ acao: 'sincronizar_vendas', estado: 'pendente' });
      if (!gravados.some(([c, v]) => c === 'farmacia/comando' && v.acao === 'sincronizar_vendas'))
        throw new Error('com a fila livre, o pedido não foi gravado');
    } finally {
      exportado.estado.comando = null;
    }
  });

  conferir('relatório continua visível depois de um "Sincronizar vendas"', () => {
    try {
      exportado.estado.relatorioPedido = null;
      exportado.estado.comando = { acao: 'sincronizar_vendas', estado: 'concluido' };
      exportado.estado.relatorios = {
        xml: { texto: 'BUSCA ANTIGA', em: '2026-10-15T10:00:00' },
        saldo: { texto: 'POR QUE O APP ACUSA ESTE LOTE', em: '2026-10-16T09:12:00' }
      };
      exportado.pintarRelatorio();
      if (documento.getElementById('bloco-relatorio').hidden) throw new Error('resposta escondida');
      igual(documento.getElementById('relatorio').textContent, 'POR QUE O APP ACUSA ESTE LOTE', 'relatório mostrado');
      igual(documento.getElementById('relatorio-titulo').textContent, 'Último relatório recebido — saldo', 'título');
    } finally {
      exportado.estado.comando = null;
      exportado.estado.relatorios = {};
    }
  });
}

if (exportado.detalheDoSaldo) {
  conferir('veredito automático do agente aparece no detalhe do lote', () => {
    const criados = [];
    const original = documento.createElement;
    documento.createElement = (t) => { const e = original(t); criados.push(e); return e; };
    try {
      exportado.detalheDoSaldo({ codigo: '1', saldoDigifarma: 10, saldoSngpc: 10, movimentoDesdeEnvio: -2,
        esperadoSngpc: 8, diferenca: 2, motivo: 'quantidade', ms: '1', lote: 'A1',
        veredito: 'aviso_falso', vereditoCorte: 48251 }, 2);
      const t = criados.map((e) => e.textContent);
      if (!t.some((x) => x.includes('recebeu até a venda 48251'))) throw new Error('sem o veredito');
      if (t.some((x) => x.includes('compensado por acaso'))) throw new Error('nota genérica no lugar do veredito');
    } finally {
      documento.createElement = original;
    }
  });
}

if (exportado.detalheDoSaldo) {
  conferir('saldo: lote trocado e resto na tabela de lotes aparecem no detalhe (20/10)', () => {
    const textos = (item) => {
      const criados = [];
      const original = documento.createElement;
      documento.createElement = (t) => { const e = original(t); criados.push(e); return e; };
      try {
        exportado.detalheDoSaldo(item, item.diferenca);
      } finally {
        documento.createElement = original;
      }
      return criados.map((e) => e.textContent).join(' | ');
    };
    const inv = exportado.estado.inventario;
    try {
      exportado.estado.inventario = { controlados: [{ codigo: '67751', saldo: 1, saldoProduto: 0 }] };
      const amox = textos({ codigo: '68752', ms: '1235202730086', lote: 'DFG3073A', saldoDigifarma: 3,
        saldoSngpc: 0, diferenca: 3, motivo: 'anvisa_zerada_lote', saldoSngpcMs: 3,
        lotesDoMs: [{ lote: 'DFG3073A', digifarma: 3, sngpc: 0 }, { lote: 'DFG6142A', digifarma: 0, sngpc: 3 }] });
      if (!amox.includes('o Digifarma tem 3 no lote DFG3073A e a ANVISA tem 3 no lote DFG6142A')) throw new Error('lote trocado: ' + amox);
      if (!amox.includes('Outro lote deste M.S.: DFG6142A')) throw new Error('sem o lote irmão');
      const anvisa = textos({ codigo: '', ms: '1235202730086', lote: 'DFG6142A', saldoDigifarma: 0,
        saldoSngpc: 3, diferenca: -3, motivo: 'so_na_anvisa',
        lotesDoMs: [{ lote: 'DFG3073A', digifarma: 3, sngpc: 0 }, { lote: 'DFG6142A', digifarma: 0, sngpc: 3 }] });
      if (!anvisa.includes('o Digifarma tem 3 no lote DFG3073A e a ANVISA tem 3 no lote DFG6142A')) throw new Error('do lado da ANVISA: ' + anvisa);
      const quetros = textos({ codigo: '67751', ms: '1057304040109', lote: '2515965', saldoDigifarma: 1,
        saldoSngpc: 0, diferenca: 1, motivo: 'anvisa_zerada_produto' });
      if (!quetros.includes('Na tela do balcão o produto está zerado')) throw new Error('resto no lote: ' + quetros);
      if (!quetros.includes('Saldo do produto no balcão')) throw new Error('sem o saldo do balcão');
      const escitalopram = textos({ codigo: '27481', ms: '1052500450038', lote: 'BQ37M006', saldoDigifarma: 1,
        saldoSngpc: 0, diferenca: 1, motivo: 'anvisa_zerada_produto' });
      if (!escitalopram.includes('O M.S. inteiro está fora')) throw new Error('sem dado do balcão, segue o motivo: ' + escitalopram);
      // motivo já classificado pelo agente, sem lotesDoMs nem lista de Controlados
      exportado.estado.inventario = {};
      const doAgente = textos({ codigo: '68752', ms: '1235202730086', lote: 'DFG3073A', saldoDigifarma: 3,
        saldoSngpc: 0, diferenca: 3, motivo: 'lote_trocado', loteParceiro: 'DFG6142A' });
      if (!doAgente.includes('o Digifarma tem 3 no lote DFG3073A e a ANVISA tem 3 no lote DFG6142A')) throw new Error('lote_trocado do agente: ' + doAgente);
      const restoDoAgente = textos({ codigo: '67751', ms: '1057304040109', lote: '2515965', saldoDigifarma: 1,
        saldoSngpc: 0, diferenca: 1, motivo: 'resto_no_lote', saldoProduto: 0 });
      if (!restoDoAgente.includes('Na tela do balcão o produto está zerado')) throw new Error('resto_no_lote do agente: ' + restoDoAgente);
    } finally {
      exportado.estado.inventario = inv;
    }
  });
}

if (exportado.hashesDoTexto && exportado.envioDaApiPelaData) {
  conferir('aceites: tira os hashes do relatório colado e casa o envio pela data de recebimento', () => {
    const h = exportado.hashesDoTexto('CNPJ 44.744.950/0001-04 F191FB8D9B9B4415F7AE3891348B1D48 f191fb8d9b9b4415f7ae3891348b1d48 0123456789ABCDEF0123456789ABCDEF0');
    if (h.length !== 1 || h[0] !== 'F191FB8D9B9B4415F7AE3891348B1D48') throw new Error(JSON.stringify(h));
    try {
      exportado.estado.inventario = { apiSngpc: { envios: [
        { arquivo: '', transmissao: '2026-10-14T16:26:00', situacao: 'com_erro' },
        { arquivo: '2026-10-08', transmissao: '2026-10-08T17:00:07', situacao: 'validado' }] } };
      igual(exportado.envioDaApiPelaData('2026-10-14').situacao, 'com_erro', 'pela data');
      igual(exportado.envioDaApiPelaData('2026-10-08'), null, 'quem tem arquivo casa pelo arquivo');
      exportado.estado.inventario = {
        enviosConhecidos: ['2026-10-16'],
        periodosDeEnvio: { '2026-10-16': { de: '2026-10-15', ate: '2026-10-15' } },
        apiSngpc: { envios: [{ arquivo: '', de: '2026-10-15', ate: '2026-10-15', transmissao: '2026-10-17T08:00:00', situacao: 'validado' }] } };
      igual(JSON.stringify(exportado.datasDeEnvio()), '["2026-10-16"]', 'envio já casado pelo período não vira segunda linha');
      // 20/10: a recusa de 14/10 (período 13/10) foi resolvida pelo reenvio de 15/10 (13 a 14/10)
      const recusado = { arquivo: '', de: '2026-10-13', ate: '2026-10-13', transmissao: '2026-10-14T16:26:00', situacao: 'com_erro' };
      exportado.estado.inventario = { apiSngpc: { envios: [recusado,
        { arquivo: '', de: '2026-10-13', ate: '2026-10-14', transmissao: '2026-10-15T16:46:00', situacao: 'validado' }] } };
      igual(exportado.reenvioAceito(recusado)?.transmissao, '2026-10-15T16:46:00', 'reenvio aceito acha a recusa resolvida');
      exportado.estado.inventario = { apiSngpc: { envios: [recusado,
        { arquivo: '', de: '2026-10-14', ate: '2026-10-14', transmissao: '2026-10-15T16:46:00', situacao: 'validado' }] } };
      igual(exportado.reenvioAceito(recusado), null, 'período diferente não resolve a recusa');
      // 20/10: ULTIMO_ENVIO_SNGPC (18/10) é o fim do período, não o dia do envio (19/10)
      exportado.estado.inventario = {
        envio: { data: '2026-10-18', arquivoXml: 'sngpc_2026-10-19.xml' },
        enviosConhecidos: ['2026-10-17', '2026-10-19'] };
      igual(JSON.stringify(exportado.datasDeEnvio()), '["2026-10-19","2026-10-17"]', 'fim do período não vira envio fantasma');
      if (typeof document !== 'undefined' && exportado.pintarRetornos && document.getElementById('lista-retornos')) {
        exportado.estado.inventario = {
          retornoArquivos: [{ arquivo: 'retorno_anvisa_2026_10_15_43.txt', em: '2026-10-14T15:54:00',
            texto: 'HASH:\nMSG DE RETORNO:\nDATA: 30/12/1899', linhasDeErro: [] }],
          apiSngpc: { envios: [{ arquivo: '', transmissao: '2026-10-14T16:26:00', situacao: 'com_erro' }] } };
        exportado.pintarRetornos();
        const t = document.getElementById('lista-retornos').textContent;
        if (!t.includes('a API diz: RECUSADO')) throw new Error('retorno vazio não mostra a API: ' + t);
      }
    } finally {
      exportado.estado.inventario = {};
    }
  });
}

if (exportado.chaveDoPedido && exportado.envioDaApi) {
  conferir('pedidos diferentes não passam por repetidos; o pior envio do dia é o que vale', () => {
    const c = exportado.chaveDoPedido;
    if (c({ acao: 'config', chave: 'permitir_ajuste_estoque', valor: true, pedidoEm: 1 })
        === c({ acao: 'config', chave: 'permitir_ajuste_estoque', valor: false, pedidoEm: 2 }))
      throw new Error('ligar e desligar viraram o mesmo pedido');
    if (c({ acao: 'desmarcar_controlado', produtoId: 1 }) === c({ acao: 'desmarcar_controlado', produtoId: 2 }))
      throw new Error('dois produtos viraram o mesmo pedido');
    if (c({ acao: 'xml', texto: 'A', pedidoEm: 1, estado: 'pendente' }) !== c({ acao: 'xml', texto: 'A', pedidoEm: 9 }))
      throw new Error('dois toques no mesmo botão deveriam ser o mesmo pedido');
    try {
      exportado.estado.inventario = { apiSngpc: { envios: [
        { arquivo: '2026-10-20', transmissao: '2026-10-20T08:00:00', situacao: 'validado' },
        { arquivo: '2026-10-20', transmissao: '2026-10-20T07:00:00', situacao: 'com_erro' }] } };
      igual(exportado.envioDaApi('2026-10-20').situacao, 'com_erro', 'recusado no mesmo dia não vira aceito');
    } finally {
      exportado.estado.inventario = {};
    }
  });
}

if (exportado.datasBR) {
  conferir('datas AAAA-MM-DD viram DD/MM/AAAA no texto', () => {
    igual(exportado.datasBR('2026-10-13 a 2026-10-14'), '13/10/2026 a 14/10/2026', 'período');
    igual(exportado.datasBR('2027-03-31'), '31/03/2027', 'validade');
    igual(exportado.datasBR(undefined), '', 'vazio');
  });
}

if (exportado.comoLista) {
  conferir('lista do Firebase com buraco vira lista', () => {
    igual(JSON.stringify(exportado.comoLista({ 0: 'a', 2: 'b' })), '["a","b"]', 'objeto');
    igual(JSON.stringify(exportado.comoLista(null)), '[]', 'nulo');
  });
}

if (exportado.temSaldo) {
  conferir('controlados: só entra quem tem saldo em um dos dois saldos', () => {
    igual(exportado.temSaldo({ saldo: 3, saldoProduto: 0 }), true, 'só nos lotes');
    igual(exportado.temSaldo({ saldo: 0, saldoProduto: 2 }), true, 'só no PROD_SALDO');
    igual(exportado.temSaldo({ saldo: 0, saldoProduto: 0 }), false, 'zerado');
    igual(exportado.temSaldo({}), false, 'sem saldo informado');
    igual(exportado.temSaldo({ saldo: -1 }), false, 'negativo');
  });
}

if (exportado.doGrupo) {
  conferir('controlados: psicotrópico e antimicrobiano em listas separadas', () => {
    const ambos = { psicotropico: true, antimicrobiano: true };
    igual(exportado.doGrupo({ psicotropico: true }, 'psicotropico'), true, 'psico na lista de controlados');
    igual(exportado.doGrupo({ psicotropico: true }, 'antimicrobiano'), false, 'psico fora dos antimicrobianos');
    igual(exportado.doGrupo({ antimicrobiano: true }, 'psicotropico'), false, 'atb fora dos controlados');
    igual(exportado.doGrupo({ antimicrobiano: true }, 'antimicrobiano'), true, 'atb nos antimicrobianos');
    igual(exportado.doGrupo(ambos, 'psicotropico') && exportado.doGrupo(ambos, 'antimicrobiano'), true, 'as duas marcas nas duas listas');
  });
}

if (exportado.textoXmlRede) {
  conferir('servidor: mostra a situação do XML de cada computador, sem senha', () => {
    if (!exportado.textoXmlRede(undefined).includes('só o servidor')) throw new Error('vazio');
    const t = exportado.textoXmlRede([
      { computador: 'CAIXA', ok: true, arquivo: 'sngpc_2026-10-15_CAIXA.xml', em: '2026-10-17T08:00:00' },
      { computador: 'FARMA', ok: false, erro: 'não conectei em FARMA (O nome da rede não foi encontrado.)' }]);
    if (!t.includes('CAIXA: ok, último sngpc_2026-10-15_CAIXA.xml') || !t.includes('FARMA: FALHOU: não conectei'))
      throw new Error(t);
  });
}

if (exportado.textoDaAtualizacao) {
  conferir('servidor: mostra a última atualização do agente e o motivo da falha', () => {
    const vazio = exportado.textoDaAtualizacao(undefined);
    if (!vazio.includes('nenhuma registrada')) throw new Error('vazio: ' + vazio);
    const ok = exportado.textoDaAtualizacao({ em: '2026-10-16T20:40:00', ok: true, como: 'automática' });
    if (!ok.includes('(automática) — ok')) throw new Error('ok: ' + ok);
    const ruim = exportado.textoDaAtualizacao({ em: '2026-10-16T20:40:00', ok: false, como: 'botão', mensagem: 'o agente novo não carrega' });
    if (!ruim.includes('FALHOU: o agente novo não carrega') || !ruim.includes('(botão)')) throw new Error('falha: ' + ruim);
  });
}

if (exportado.envioDaApi && exportado.linhaDaApi) {
  conferir('aceite: resposta da API casa pelo arquivo e pelo período', () => {
    try {
      exportado.estado.inventario = {
        periodosDeEnvio: { '2026-10-15': { de: '2026-10-13', ate: '2026-10-14' } },
        apiSngpc: { envios: [
          { arquivo: '2026-10-08', de: '2026-10-07', ate: '2026-10-07', situacao: 'validado', validacao: '2026-10-08T23:00:02' },
          { arquivo: '', de: '2026-10-13', ate: '2026-10-14', situacao: 'validado', validacao: '2026-10-15T09:42:00' }
        ] }
      };
      igual(exportado.envioDaApi('2026-10-08').de, '2026-10-07', 'pelo arquivo');
      igual(exportado.envioDaApi('2026-10-15').de, '2026-10-13', 'pelo período');
      igual(exportado.envioDaApi('2026-10-12'), null, 'sem resposta');
      const t = exportado.linhaDaApi(exportado.envioDaApi('2026-10-15')).textContent;
      if (!t.includes('Validado sem erro pela ANVISA') || !t.includes('13/10/2026 a 14/10/2026'))
        throw new Error('linha da API: ' + t);
    } finally {
      exportado.estado.inventario = {};
    }
  });
}

conferir('texto que vai para innerHTML tem as tags escapadas', () => {
  if (!exportado.html) throw new Error('app.js não exporta html()');
  igual(exportado.html('<img src=x onerror="alert(1)">&\''),
    '&lt;img src=x onerror=&quot;alert(1)&quot;&gt;&amp;&#39;', 'escape');
  igual(exportado.html(null), '', 'nulo');
});

console.log(falhas ? `\n${falhas} falha(s)\n` : '\nTudo passou.\n');
process.exit(falhas ? 1 : 0);
