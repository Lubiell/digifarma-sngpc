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

if (exportado.vendasDeHoje) {
  conferir('vendas de hoje: so as de hoje, com e sem receita, a mais nova primeiro', () => {
    const d = new Date();
    const hoje = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0')
      + '-' + String(d.getDate()).padStart(2, '0');
    exportado.estado.inventario = { vendasRecentes: [
      { venda: 1, quando: '2000-01-01T10:00:00', receita: true },
      { venda: 2, quando: hoje + 'T09:00:00', receita: true },
      { venda: 3, quando: hoje + 'T11:30:00', receita: false }
    ] };
    try {
      const v = exportado.vendasDeHoje();
      igual(v.map((x) => x.venda).join(','), '3,2', 'vendas de hoje');
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

console.log(falhas ? `\n${falhas} falha(s)\n` : '\nTudo passou.\n');
process.exit(falhas ? 1 : 0);
