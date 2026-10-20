/* FARMÁCIA — SNGPC
   Conferência Digifarma × SNGPC. O app só LÊ farmacia/inventario:
   quem escreve ali é o agente que roda no servidor da farmácia.
   O app escreve em farmacia/aceites, farmacia/comando, farmacia/config
   e farmacia/operadores.

   Regras do projeto respeitadas aqui:
   - senha do app guardada como hash SHA-256 em farmacia/config (nunca no código);
   - nada de prompt()/confirm() nativos: modais próprios;
   - localStorage só para preferência do aparelho;
   - o aceite da ANVISA é marcado à mão, com nome de quem marcou.
*/
'use strict';

/* ============================================================
   1. CONFIGURAÇÃO
   ============================================================ */
const CONFIG_FIREBASE = {
  apiKey: 'AIzaSyC3nXsBC2ARX8IOLITHUtovPn4DONEQe7g',
  authDomain: 'estoque-remedios-7b785.firebaseapp.com',
  databaseURL: 'https://estoque-remedios-7b785-default-rtdb.firebaseio.com',
  projectId: 'estoque-remedios-7b785',
  storageBucket: 'estoque-remedios-7b785.firebasestorage.app',
  messagingSenderId: '1005921072336',
  appId: '1:1005921072336:web:964ca0ae079b5e796e5ad5'
};

const CHAVE_OPERADOR = 'farmacia.operador';
const CHAVE_SESSAO = 'farmacia.senhaOk';   // só nesta sessão do aparelho

firebase.initializeApp(CONFIG_FIREBASE);
const auth = firebase.auth();
const db = firebase.database();

/* ============================================================
   2. ESTADO
   ============================================================ */
const estado = {
  operador: null,
  inventario: {},   // farmacia/inventario
  aceites: {},      // farmacia/aceites
  comando: null,    // farmacia/comando
  config: {},       // farmacia/config
  operadores: [],
  vista: 'painel',
  buscaSaldo: '',
  buscaXml: '',
  buscaControlados: '',
  grupoControlados: 'psicotropico',   // ou 'antimicrobiano'
  relatorios: {},       // farmacia/relatorios
  historico: {},        // farmacia/historico (ultimos 30 dias)
  relatorioPedido: null,
  abertos: new Set()
};

/* ============================================================
   3. UTILIDADES
   ============================================================ */
const $ = (id) => document.getElementById(id);
const criar = (t, c) => { const e = document.createElement(t); if (c) e.className = c; return e; };
const esc = (s) => String(s ?? '');
/* esc so vira texto; o que vai para innerHTML passa por html(), que escapa as tags */
const html = (s) => esc(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const agora = () => new Date().toISOString();

function avisar(texto, ms = 2800) {
  const el = $('aviso');
  el.textContent = texto;
  el.hidden = false;
  clearTimeout(avisar._t);
  avisar._t = setTimeout(() => { el.hidden = true; }, ms);
}

function dataHora(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (isNaN(d)) return esc(iso);
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' });
}

function dataBR(iso) {
  if (!iso) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : esc(iso);
}

/* Troca toda data AAAA-MM-DD de um texto por DD/MM/AAAA (validade, período). */
function datasBR(t) {
  return String(t ?? '').replace(/(\d{4})-(\d{2})-(\d{2})/g, '$3/$2/$1');
}

function normalizar(s) {
  return String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

function combina(obj, termo, campos) {
  if (!termo) return true;
  const t = normalizar(termo);
  return campos.some((c) => normalizar(obj[c]).includes(t));
}

async function sha256(texto) {
  const bytes = new TextEncoder().encode(texto);
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/* O Firebase devolve lista com buraco como objeto {0:..., 2:...}. */
function comoLista(v) {
  if (!v) return [];
  return (Array.isArray(v) ? v : Object.values(v)).filter(Boolean);
}

function lista(no) {
  const v = estado.inventario?.[no];
  if (!v) return [];
  return Array.isArray(v) ? v.filter(Boolean) : Object.values(v);
}

/* ============================================================
   4. MODAIS
   ============================================================ */
let fecharModalAtual = null;

function abrirModal({ titulo, corpo, acoes }) {
  const quemAbriu = document.activeElement;
  $('modal-titulo').textContent = titulo;
  const alvo = $('modal-corpo');
  alvo.innerHTML = '';
  if (typeof corpo === 'string') alvo.innerHTML = corpo;
  else if (corpo) alvo.appendChild(corpo);

  const barra = $('modal-acoes');
  barra.innerHTML = '';
  (acoes || []).forEach((a) => {
    const b = criar('button', 'botao ' + (a.estilo || 'botao-fantasma'));
    b.textContent = a.texto;
    b.onclick = () => a.aoClicar?.();
    barra.appendChild(b);
  });
  $('modal').hidden = false;
  fecharModalAtual = () => {
    $('modal').hidden = true; fecharModalAtual = null;
    if (recarregarAoFecharModal) window.location.reload();
    // o foco volta para quem abriu, senao o teclado cai no topo da pagina
    if (quemAbriu && typeof quemAbriu.focus === 'function' && document.contains(quemAbriu)) quemAbriu.focus();
  };
  const primeiro = alvo.querySelector('input, select, textarea');
  if (primeiro) setTimeout(() => primeiro.focus(), 60);
}

function fecharModal() { fecharModalAtual?.(); }

/* Tab e Shift+Tab ficam dentro do modal aberto: sem isto o foco ia para a
   pagina de tras, que o modal cobre. */
document.addEventListener('keydown', (ev) => {
  if (ev.key !== 'Tab' || $('modal').hidden) return;
  const focaveis = [...$('modal').querySelectorAll('button, input, textarea, select, a[href], [tabindex]:not([tabindex="-1"])')]
    .filter((e) => !e.disabled && e.offsetParent !== null);
  if (!focaveis.length) return;
  const primeiro = focaveis[0], ultimo = focaveis[focaveis.length - 1];
  if (ev.shiftKey && document.activeElement === primeiro) { ev.preventDefault(); ultimo.focus(); }
  else if (!ev.shiftKey && document.activeElement === ultimo) { ev.preventDefault(); primeiro.focus(); }
  else if (!$('modal').contains(document.activeElement)) { ev.preventDefault(); primeiro.focus(); }
});

function confirmar(titulo, texto, textoOk = 'Confirmar', estilo = 'botao-principal') {
  return new Promise((resolve) => {
    abrirModal({
      titulo,
      corpo: `<p class="sublinha">${html(texto)}</p>`,
      acoes: [
        { texto: 'Cancelar', aoClicar: () => { fecharModal(); resolve(false); } },
        { texto: textoOk, estilo, aoClicar: () => { fecharModal(); resolve(true); } }
      ]
    });
  });
}

document.addEventListener('keydown', (e) => { if (e.key === 'Escape') fecharModal(); });
$('modal').addEventListener('click', (e) => { if (e.target.id === 'modal') fecharModal(); });

/* ============================================================
   5. ENTRAR
   ============================================================ */
$('btn-entrar').onclick = async () => {
  const erro = $('login-erro');
  erro.hidden = true;
  const email = $('login-email').value.trim();
  const senha = $('login-senha').value;
  if (!email || !senha) { erro.textContent = 'Preencha e-mail e senha.'; erro.hidden = false; return; }
  $('btn-entrar').disabled = true;
  try {
    await auth.signInWithEmailAndPassword(email, senha);
  } catch (e) {
    const c = e?.code || '';
    erro.textContent = c.includes('invalid-credential') || c.includes('wrong-password') || c.includes('user-not-found')
      ? 'E-mail ou senha não conferem.'
      : 'Não foi possível entrar: ' + (e?.message || c);
    erro.hidden = false;
  } finally {
    $('btn-entrar').disabled = false;
  }
};
$('login-senha').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('btn-entrar').click(); });

$('btn-sair').onclick = async () => {
  if (!(await confirmar('Sair do app', 'Você vai precisar entrar de novo e digitar a senha da farmácia.', 'Sair', 'botao-perigo'))) return;
  sessionStorage.removeItem(CHAVE_SESSAO);
  desligarEscutas();
  await auth.signOut();
};

auth.onAuthStateChanged(async (user) => {
  if (!user) {
    desligarEscutas();
    ['app', 'tela-senha', 'tela-operador'].forEach((id) => { $(id).hidden = true; });
    $('tela-login').hidden = false;
    $('login-senha').value = '';
    return;
  }
  $('tela-login').hidden = true;
  ligarEscutas();
  await portaDaSenha();
});

/* ============================================================
   6. SENHA DO APP (hash em farmacia/config)
   ============================================================ */
async function portaDaSenha() {
  if (sessionStorage.getItem(CHAVE_SESSAO) === '1') { escolherOperador(); return; }
  let salvo = null;
  try {
    salvo = (await db.ref('farmacia/config/senhaHash').get()).val();
  } catch (e) {
    $('barra-estado').textContent = 'Sem acesso a farmacia/config — verifique se o seu UID está em farmacia/autorizados.';
    $('barra-estado').hidden = false;
  }
  $('tela-senha').hidden = false;
  $('senha-primeira').hidden = !!salvo;
  $('senha-app').value = '';
  $('senha-app').focus();
}

$('btn-senha').onclick = async () => {
  const erro = $('senha-erro');
  erro.hidden = true;
  const digitada = $('senha-app').value;
  if (!digitada) { erro.textContent = 'Digite a senha.'; erro.hidden = false; return; }
  const salvo = (await db.ref('farmacia/config/senhaHash').get()).val();
  if (!salvo) { erro.textContent = 'Ainda não há senha definida. Use o botão abaixo para definir esta.'; erro.hidden = false; $('senha-primeira').hidden = false; return; }
  if (await sha256(digitada) !== salvo) { erro.textContent = 'Senha incorreta.'; erro.hidden = false; return; }
  sessionStorage.setItem(CHAVE_SESSAO, '1');
  $('tela-senha').hidden = true;
  escolherOperador();
};
$('senha-app').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('btn-senha').click(); });

$('btn-definir-senha').onclick = async () => {
  const nova = $('senha-app').value;
  if (nova.length < 6) { $('senha-erro').textContent = 'Use pelo menos 6 caracteres.'; $('senha-erro').hidden = false; return; }
  if (!(await confirmar('Definir senha da farmácia', 'Esta senha passa a valer para todo mundo que abrir o app. Só o hash é guardado.', 'Definir'))) return;
  await db.ref('farmacia/config').update({ senhaHash: await sha256(nova), senhaDefinidaEm: agora() });
  sessionStorage.setItem(CHAVE_SESSAO, '1');
  $('tela-senha').hidden = true;
  avisar('Senha definida.');
  escolherOperador();
};

$('btn-config').onclick = () => {
  const corpo = criar('div');
  corpo.innerHTML = `
    <label class="campo"><span>Senha atual</span><input id="c-atual" type="password" autocomplete="off"></label>
    <label class="campo"><span>Nova senha</span><input id="c-nova" type="password" autocomplete="off"></label>
    <p id="c-erro" class="aviso-erro" hidden></p>
    <p class="nota">Só o hash SHA-256 vai para o banco, em <code>farmacia/config</code>.
    A senha em si não fica no código nem no aparelho.</p>
  `;
  abrirModal({
    titulo: 'Senha da farmácia',
    corpo,
    acoes: [
      { texto: 'Fechar', aoClicar: fecharModal },
      {
        texto: 'Trocar senha', estilo: 'botao-principal', aoClicar: async () => {
          const erro = $('c-erro');
          erro.hidden = true;
          const atual = $('c-atual').value, nova = $('c-nova').value;
          const salvo = (await db.ref('farmacia/config/senhaHash').get()).val();
          if (salvo && await sha256(atual) !== salvo) { erro.textContent = 'Senha atual incorreta.'; erro.hidden = false; return; }
          if (nova.length < 6) { erro.textContent = 'A nova senha precisa de pelo menos 6 caracteres.'; erro.hidden = false; return; }
          await db.ref('farmacia/config').update({ senhaHash: await sha256(nova), senhaDefinidaEm: agora(), senhaDefinidaPor: estado.operador });
          fecharModal();
          avisar('Senha trocada.');
        }
      }
    ]
  });
};

/* ============================================================
   7. OPERADOR
   ============================================================ */
function escolherOperador() {
  const salvo = localStorage.getItem(CHAVE_OPERADOR);
  if (salvo) { entrarNoApp(salvo); return; }
  $('tela-operador').hidden = false;
  pintarOperadores();
}

function pintarOperadores() {
  const alvo = $('lista-operadores');
  if (!alvo) return;
  alvo.innerHTML = '';
  estado.operadores.forEach((nome) => {
    const b = criar('button', 'chip');
    b.textContent = nome;
    b.onclick = () => entrarNoApp(nome);
    alvo.appendChild(b);
  });
}

$('btn-operador').onclick = async () => {
  const nome = $('operador-novo').value.trim();
  if (!nome) { avisar('Escolha um nome ou digite um novo.'); return; }
  if (!estado.operadores.includes(nome)) {
    await db.ref('farmacia/operadores').set([...estado.operadores, nome].sort((a, b) => a.localeCompare(b, 'pt-BR')));
  }
  entrarNoApp(nome);
};

function entrarNoApp(nome) {
  estado.operador = nome;
  localStorage.setItem(CHAVE_OPERADOR, nome);
  $('rotulo-operador').textContent = 'Conferindo: ' + nome;
  $('tela-operador').hidden = true;
  $('app').hidden = false;
  pintar();
}

/* ============================================================
   8. SINCRONIZAÇÃO (só leitura do inventário)
   ============================================================ */
const escutas = [];

function escutar(caminho, aoMudar) {
  const ref = db.ref(caminho);
  const cb = ref.on('value',
    (s) => aoMudar(s.val()),
    (e) => {
      $('barra-estado').textContent = 'Sem acesso a ' + caminho + ' — confira as regras do Firebase e se o seu UID está em farmacia/autorizados.';
      $('barra-estado').hidden = false;
      console.error(caminho, e);
    });
  escutas.push({ ref, cb });
}

/* Laboratorio pelo registro M.S. Os digitos 2 a 5 do M.S. sao o numero da
   empresa detentora na ANVISA (1.0235 e a EMS, 1.0573 o Ache); a tabela
   laboratorios.json sai dos dados abertos da ANVISA
   (ferramentas/gerar_laboratorios.py). O laboratorio que o agente le no
   Digifarma, quando vem, tem preferencia. */
let tabelaLaboratorios = null;
if (typeof fetch === 'function') {
  fetch('laboratorios.json')
    .then((r) => (r.ok ? r.json() : null))
    .then((t) => { tabelaLaboratorios = t; if (estado.inventario) { anotarLaboratorios(); pintar(); } })
    .catch(() => {});
}

function laboratorioPeloMs(ms) {
  const d = String(ms || '').replace(/\D/g, '');
  if (!tabelaLaboratorios || d.length < 9) return '';
  return tabelaLaboratorios.registros?.[d.slice(0, 9)]
    || tabelaLaboratorios.empresas?.[d.slice(1, 5)] || '';
}

function anotarLaboratorios() {
  ['itens', 'conferencia_xml', 'vendas_problema', 'vendasRecentes'].forEach((no) => {
    lista(no).forEach((i) => {
      if (i && !i.laboratorio) {
        const nome = laboratorioPeloMs(i.ms);
        if (nome) i.laboratorio = nome;
      }
    });
  });
}

function ligarEscutas() {
  if (escutas.length) return;
  escutar('farmacia/inventario', (v) => { estado.inventario = v || {}; anotarLaboratorios(); pintar(); });
  escutar('farmacia/aceites', (v) => { estado.aceites = v || {}; if (estado.vista === 'aceites') pintarAceites(); });
  escutar('farmacia/comando', (v) => { estado.comando = v; pintarComando(); });
  escutar('farmacia/config', (v) => { estado.config = v || {}; if (estado.vista === 'servidor') pintarAvisos(); });
  escutar('farmacia/relatorios', (v) => {
    estado.relatorios = v || {};
    if (estado.vista === 'servidor') pintarRelatorio();
  });
  // So os ultimos 30 dias: o no cresce um registro por dia.
  const historico = db.ref('farmacia/historico').limitToLast(30);
  const cbHistorico = historico.on('value',
    (s) => { estado.historico = s.val() || {}; pintarEvolucao(); },
    (e) => console.error('farmacia/historico', e));
  escutas.push({ ref: historico, cb: cbHistorico });
  escutar('farmacia/operadores', (v) => {
    estado.operadores = Array.isArray(v) ? v.filter(Boolean) : Object.values(v || {});
    pintarOperadores();
  });
}

function desligarEscutas() {
  escutas.forEach(({ ref, cb }) => ref.off('value', cb));
  escutas.length = 0;
}

/* ============================================================
   9. BOTÕES QUE PEDEM AO AGENTE (farmacia/comando)
   ============================================================ */
/* farmacia/comando guarda UM pedido. Gravar por cima de um que o agente
   ainda nao atendeu apagava o primeiro sem aviso: foi assim que a
   investigacao de um lote sumiu, trocada por um "Sincronizar vendas" antes
   da passagem do agente. Devolve false quando a pessoa desiste. */
function chaveDoPedido(p) {
  const fora = new Set(['pedidoEm', 'pedidoPor', 'estado', 'senha', 'mensagem', 'concluidoEm']);
  return JSON.stringify(Object.keys(p || {}).filter((k) => !fora.has(k)).sort()
    .map((k) => [k, p[k] === undefined || p[k] === null ? '' : p[k]]));
}

async function gravarPedido(pedido) {
  const c = estado.comando;
  // o mesmo pedido de novo (dois toques no botao) nao apaga nada. "O mesmo"
  // e tudo menos quando e quem: so acao+texto tratava ligar e desligar um
  // config, ou dois produtos diferentes, como repetidos, e apagava calado
  const repetido = c && chaveDoPedido(c) === chaveDoPedido(pedido);
  if (c && c.estado === 'pendente' && !repetido && !(await confirmar('Já há um pedido na fila',
    'O agente ainda não atendeu “' + c.acao + '”, pedido em ' + dataHora(c.pedidoEm)
    + '. Mandar este agora apaga aquele.', 'Substituir'))) return false;
  await db.ref('farmacia/comando').set(pedido);
  return true;
}

async function pedirAoAgente(acao, rotulo) {
  if (!(await gravarPedido({
    acao,                    // 'sincronizar_vendas' | 'atualizar_envio'
    pedidoEm: agora(),
    pedidoPor: estado.operador,
    estado: 'pendente'
  }))) return;
  avisar(rotulo + ' pedido. O agente atende na próxima passagem dele.');
}

$('btn-sincronizar').onclick = () => pedirAoAgente('sincronizar_vendas', 'Sincronizar vendas');
$('btn-atualizar-envio').onclick = () => pedirAoAgente('atualizar_envio', 'Atualizar envio');

function textoDoComando() {
  const c = estado.comando;
  if (!c) return '';
  if (c.estado === 'concluido') {
    return c.concluidoEm ? `Último pedido (${c.acao}) atendido em ${dataHora(c.concluidoEm)}.` : '';
  }
  if (c.estado === 'erro') {
    return `O agente não conseguiu atender “${c.acao}”: ${c.mensagem || 'sem detalhe'}.`;
  }
  return `Pedido “${c.acao}” na fila desde ${dataHora(c.pedidoEm)}`
    + (estado.inventario?.vistoEm ? ` — o agente passou por aqui ${dataHora(estado.inventario.vistoEm)}.` : '.');
}

/* A barra aparece tambem na aba Servidor: e la que os relatorios sao
   pedidos, e so na Situacao ninguem via que o pedido estava na fila ou
   tinha dado erro - parecia que o botao nao fazia nada. */
function pintarComando() {
  const t = textoDoComando();
  ['fila-comando', 'fila-comando-servidor'].forEach((id) => {
    const barra = $(id);
    barra.textContent = t;
    barra.hidden = !t;
  });
  if (estado.vista === 'servidor') pintarRelatorio();
}

/* ============================================================
   10. NAVEGAÇÃO
   ============================================================ */
function irPara(vista) {
  estado.vista = vista;
  document.querySelectorAll('.nav-item').forEach((x) => x.classList.toggle('nav-ativo', x.dataset.vista === vista));
  document.querySelectorAll('.vista').forEach((v) => { v.hidden = v.id !== 'v-' + vista; });
  pintar();
  // aba nova comeca do topo: "Investigar este lote" no meio do Saldo deixava
  // a pessoa no meio da aba Servidor, sem ver a resposta
  window.scrollTo(0, 0);
}
document.querySelectorAll('.nav-item').forEach((b) => { b.onclick = () => { irPara(b.dataset.vista); fecharMenu(); }; });

/* Menu das abas: abre pelo botao do topo, fecha ao escolher, tocar fora
   ou Esc. O foco volta para o botao, para quem navega pelo teclado. */
function abrirMenu() {
  $('menu-abas').classList.add('aberta');
  $('fundo-menu').hidden = false;
  $('btn-menu').setAttribute('aria-expanded', 'true');
  document.querySelector('.nav-item.nav-ativo')?.focus?.();
}
function fecharMenu() {
  if (!$('menu-abas').classList.contains('aberta')) return;
  $('menu-abas').classList.remove('aberta');
  $('fundo-menu').hidden = true;
  $('btn-menu').setAttribute('aria-expanded', 'false');
  $('btn-menu').focus?.();
}
$('btn-menu').onclick = () => ($('menu-abas').classList.contains('aberta') ? fecharMenu() : abrirMenu());
$('fundo-menu').onclick = fecharMenu;
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') fecharMenu(); });

/* Com o menu fechado os selos das abas somem da vista: o botao mostra "!"
   quando alguma aba tem pendencia. */
function pintarSeloMenu() {
  $('selo-menu').hidden = ![...document.querySelectorAll('.navegacao .selo')].some((s) => !s.hidden);
}
if (typeof MutationObserver !== 'undefined') {
  new MutationObserver(pintarSeloMenu).observe($('menu-abas'), { subtree: true, attributes: true, attributeFilter: ['hidden'] });
}
document.querySelectorAll('[data-ir]').forEach((b) => { b.onclick = () => irPara(b.dataset.ir); });
$('busca-saldo').oninput = (e) => { estado.buscaSaldo = e.target.value; pintarSaldo(); };
$('busca-controlados').oninput = (e) => { estado.buscaControlados = e.target.value; pintarControlados(); };
['psicotropico', 'antimicrobiano'].forEach((g) => {
  $('grupo-' + g).onclick = () => { estado.grupoControlados = g; pintarControlados(); };
});
$('busca-xml').oninput = (e) => { estado.buscaXml = e.target.value; pintarXml(); };

/* ============================================================
   11. DESENHO
   ============================================================ */
function divergenciasDeSaldo() {
  return lista('itens').filter((i) => Number(i.diferenca || 0) !== 0);
}
function pendenciasXml() {
  return lista('conferencia_xml').filter((c) => c && c.situacao !== 'ok');
}
function vendasProblema() {
  return lista('vendas_problema');
}

function pintar() {
  if (!estado.operador) return;
  const s = divergenciasDeSaldo().length, x = pendenciasXml().length, v = vendasProblema().length;
  [['selo-saldo', s], ['selo-xml', x], ['selo-vendas', v]].forEach(([id, n]) => {
    const el = $(id); el.textContent = n; el.hidden = n === 0;
  });
  $('n-saldo').textContent = s;
  $('n-xml').textContent = x;
  $('n-vendas').textContent = v;
  document.querySelectorAll('.cartao-numero').forEach((c) => {
    const n = Number(c.querySelector('strong').textContent) || 0;
    c.classList.toggle('alerta', n > 0);
  });

  const carimbo = estado.inventario?.atualizadoEm;
  $('carimbo').textContent = carimbo
    ? 'Dados do Digifarma de ' + dataHora(carimbo) + (estado.inventario?.inventario?.data ? ' · inventário de ' + dataBR(estado.inventario.inventario.data) : '')
    : 'O agente ainda não publicou nada. Rode o INSTALAR_AGENTE.bat no servidor.';

  pintarEnvio();
  pintarEvolucao();
  pintarPendentes();
  if (estado.vista === 'saldo') pintarSaldo();
  if (estado.vista === 'controlados') pintarControlados();
  if (estado.vista === 'xml') pintarXml();
  if (estado.vista === 'vendas') pintarVendas();
  if (estado.vista === 'aceites') pintarAceites();
  pintarAgenteParado();
  avisarDadoVelho();
  if (estado.vista === 'servidor') pintarServidor();
}

const ROTULO_PENDENTE = {
  vendas: 'Vendas', entradas: 'Entradas',
  perdas: 'Perdas', transferencias: 'Transferências'
};

/* Os numeros do placar dia a dia (farmacia/historico, gravado pelo agente).
   Sem isto "14 divergencias" nao diz se a conferencia esta ganhando ou
   perdendo. Dia em que a comparacao estava prejudicada vai marcado. */
function pintarEvolucao() {
  const dl = $('dados-evolucao');
  const resumo = $('evolucao-resumo');
  if (!dl) return;
  dl.innerHTML = '';
  const dias = Object.keys(estado.historico || {}).sort().reverse();
  if (!dias.length) {
    resumo.textContent = 'O agente ainda não gravou nenhum dia. O histórico começa na próxima sincronização.';
    return;
  }
  const hoje = estado.historico[dias[0]];
  const base = dias.find((d) => d <= anteriorEmDias(dias[0], 7));
  const antes = base ? estado.historico[base] : null;
  const variacao = (agora, ant) => {
    const d = Number(agora || 0) - Number(ant || 0);
    return d === 0 ? 'igual' : (d > 0 ? '+' + d : String(d));
  };
  resumo.textContent = antes
    ? 'Divergências de saldo: ' + (hoje.divergencias ?? 0) + ' em ' + dataBR(dias[0])
      + ' (' + variacao(hoje.divergencias, antes.divergencias) + ' desde ' + dataBR(base) + '). '
      + 'Vendas com problema: ' + (hoje.vendasProblema ?? 0)
      + ' (' + variacao(hoje.vendasProblema, antes.vendasProblema) + ').'
    : 'Ainda não há uma semana de histórico para comparar.';
  dias.slice(0, 14).forEach((d) => {
    const h = estado.historico[d] || {};
    const dt = criar('dt'); dt.textContent = dataBR(d);
    const dd = criar('dd');
    dd.textContent = (h.divergencias ?? 0) + ' saldo · ' + (h.xml ?? 0) + ' XML · '
      + (h.vendasProblema ?? 0) + ' vendas' + (h.confiavel === false ? ' · comparação prejudicada' : '');
    dl.append(dt, dd);
  });
}

function anteriorEmDias(iso, n) {
  const d = new Date(iso + 'T12:00:00');
  d.setDate(d.getDate() - n);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}

function pintarPendentes() {
  const dl = $('dados-pendentes');
  if (!dl) return;
  dl.innerHTML = '';
  const resumo = estado.inventario?.resumoPendentes;
  if (!resumo) {
    const dt = criar('dt'); dt.textContent = 'Sem dados';
    const dd = criar('dd'); dd.textContent = 'o agente ainda não publicou';
    dl.append(dt, dd);
    return;
  }
  Object.entries(ROTULO_PENDENTE).forEach(([chave, rotulo]) => {
    const dt = criar('dt'); dt.textContent = rotulo;
    const dd = criar('dd');
    const n = Number(resumo[chave] || 0);
    dd.textContent = n === 0 ? 'nada pendente' : n + ' movimento(s)';
    dl.append(dt, dd);
  });
}

function textoSobreAnvisa() {
  const a = estado.inventario?.anvisa;
  if (!a || !a.precisaLogin) return '';
  const dias = a.diasSemSincronizar;
  return dias === null || dias === undefined
    ? 'O inventário da ANVISA nunca foi baixado. Abra o Anvisa.exe no servidor e faça o login no site do SNGPC.'
    : `O inventário da ANVISA está com ${dias} dia(s). Abra o Anvisa.exe no servidor e faça o login — ele para na tela de login e não anda sozinho.`;
}

function pintarEnvio() {
  const e = estado.inventario?.envio || {};
  const dl = $('dados-envio');
  dl.innerHTML = '';
  const linhas = [
    ['Data do envio', dataBR(e.data)],
    ['Movimentos de', e.movimentosDe ? dataBR(e.movimentosDe) + ' a ' + dataBR(e.movimentosAte) : '—'],
    ['Envio por API', e.envioPorApi ? 'ligado no Digifarma' : 'desligado (envio manual)'],
    ['Última venda transmitida', e.ULT_SAIDA_VENDA_NOTA_ID ?? '—'],
    ['Última entrada transmitida', e.ULT_ENTRADA_CAB_NOTA_ID ?? '—'],
    ['XML arquivado', e.arquivoXml || '—']
  ];
  linhas.forEach(([k, v]) => {
    const dt = criar('dt'); dt.textContent = k;
    const dd = criar('dd'); dd.textContent = esc(v);
    dl.append(dt, dd);
  });
}

/* --- linha expansível com tarja --- */
function linha({ chave, titulo, meta, tarja, tarjaClasse, detalhe }) {
  const el = criar('div', 'linha');

  const cabeca = criar('button', 'linha-cabeca');
  const t = criar('p', 'linha-titulo'); t.textContent = titulo;
  cabeca.appendChild(t);
  const m = criar('p', 'linha-meta');
  meta.filter(Boolean).forEach((x) => { const s = criar('span'); s.textContent = x; m.appendChild(s); });
  cabeca.appendChild(m);
  cabeca.setAttribute('aria-expanded', String(estado.abertos.has(chave)));
  el.appendChild(cabeca);

  const faixa = criar('div', 'linha-tarja ' + (tarjaClasse || ''));
  const esquerda = criar('span'); esquerda.textContent = tarja[0];
  const direita = criar('span'); direita.textContent = tarja[1];
  faixa.append(esquerda, direita);
  el.appendChild(faixa);

  const caixa = criar('div', 'linha-detalhe');
  caixa.appendChild(detalhe);
  caixa.hidden = !estado.abertos.has(chave);
  el.appendChild(caixa);

  cabeca.onclick = () => {
    const aberto = !caixa.hidden;
    caixa.hidden = aberto;
    cabeca.setAttribute('aria-expanded', String(!aberto));
    if (aberto) estado.abertos.delete(chave); else estado.abertos.add(chave);
  };
  return el;
}

function definicoes(pares) {
  const d = criar('div');
  const dl = criar('dl');
  pares.filter(([, v]) => v !== undefined && v !== null && v !== '').forEach(([k, v]) => {
    const dt = criar('dt'); dt.textContent = k;
    const dd = criar('dd'); dd.textContent = esc(v);
    dl.append(dt, dd);
  });
  d.appendChild(dl);
  return d;
}

/* O motivo diz o que se OBSERVA, nunca a causa: um lote ausente do
   inventario da ANVISA quer dizer saldo zero la, e zero tanto pode ser
   entrada que nao subiu quanto saldo errado no Digifarma. Afirmar a causa
   na etiqueta manda gente conferir prateleira a toa. */
const MOTIVO_SALDO = {
  negativo: ['Saldo negativo no Digifarma', 'Lote com saldo abaixo de zero. Isso é erro de escrituração, não de prateleira.'],
  lote_em_dois_ms: ['Mesmo lote em dois registros M.S.', 'Lote é numeração de fabricante: dois fabricantes podem usar o mesmo número. Confira o fabricante na caixa antes de mexer em cadastro.'],
  so_na_anvisa: ['Só aparece na ANVISA', 'A ANVISA tem saldo deste lote e o Digifarma não o conhece.'],
  quantidade: ['Quantidade diferente', 'Os dois lados conhecem o lote, com saldos diferentes.'],
  anvisa_zerada_lote: ['Lote zerado na ANVISA', 'O M.S. está no inventário, este lote não. Costuma ser entrada ainda não transmitida.'],
  anvisa_zerada_produto: ['Produto zerado na ANVISA', 'O M.S. inteiro está fora do inventário da ANVISA.'],
  lote_trocado: ['Lote com número diferente', 'O mesmo M.S. tem a mesma quantidade em outro lote do outro lado. Confira o lote impresso na caixa.'],
  resto_no_lote: ['Resto na tabela de lotes', 'Produto zerado no balcão e na ANVISA; o saldo está só na tabela de lotes do Digifarma.'],
  sem_ms: ['Produto sem registro M.S.', 'Sem M.S. cadastrado não dá para comparar com a ANVISA.']
};
const ORDEM_MOTIVO = ['negativo', 'lote_em_dois_ms', 'lote_trocado', 'so_na_anvisa', 'quantidade',
                      'anvisa_zerada_lote', 'anvisa_zerada_produto', 'resto_no_lote', 'sem_ms'];

/* Por que a comparacao de saldo pode nao valer. A chave vem do agente;
   a frase e daqui, porque quem escreve frase e a tela. */
const MOTIVO_CONFIANCA = {
  sem_inventario: 'O inventário da ANVISA nunca foi baixado, então não há com o que comparar.',
  foto_anterior_ao_envio: 'O inventário da ANVISA é anterior ao último envio. O que subiu nesse meio já passou do ponteiro e não entra em "falta transmitir" — fica contado em lugar nenhum e aparece como sobra.',
  lote_recusado: 'Um lote foi recusado pela ANVISA. A recusa derruba o envio inteiro, mas o ponteiro do Digifarma andou assim mesmo: ele considera transmitido o que a ANVISA não registrou.',
  pendente_sem_lote: 'Há movimento pendente sem número de lote. Sem lote ele não soma a lote nenhum e some da conta.',
  pendente_sem_casar: 'Há movimento pendente com M.S. ou lote grafado diferente do cadastro, que não casou com nenhum lote dos dois lados.'
};

function pintarConfiancaDoSaldo() {
  const barra = $('saldo-confianca');
  const foto = $('saldo-foto');
  const c = estado.inventario?.inventario?.confianca;
  const inv = estado.inventario?.inventario || {};

  foto.hidden = !inv.data;
  if (inv.data) {
    foto.textContent = 'O inventário da ANVISA é uma foto, de '
      + dataBR(inv.data) + '. A conta é: essa foto mais o que ainda não subiu.';
  }

  const frases = (c && !c.confiavel ? c.motivos || [] : []).map((m) => MOTIVO_CONFIANCA[m] || m);
  // O agente conta os lotes que batem com a ANVISA SEM o movimento pendente,
  // mas so dizia isso no log do servidor. E o sinal de que a mesma venda
  // pode estar sendo descontada duas vezes.
  if (inv.fotoAntesDaValidacao) {
    frases.push('A ANVISA validou um envio depois desta foto: a conta soma o movimento desde '
      + dataBR(inv.fotoAntesDaValidacao) + ', que a foto ainda não tem.');
  }
  const jaNaAnvisa = Number(inv.jaNaAnvisa || 0);
  if (jaNaAnvisa) {
    frases.push(jaNaAnvisa + ' lote(s) com movimento pendente batem com a ANVISA sem ele. '
      + 'Se esse movimento já foi transmitido (envio por outra máquina, ponteiro atrasado), '
      + 'a divergência deles é falsa: a conta desconta a mesma venda duas vezes.');
  }
  if (!frases.length) { barra.hidden = true; return; }
  barra.innerHTML = '<strong>Estes números podem não ser divergência de estoque.</strong><br>'
    + frases.map(html).join('<br>');
  barra.hidden = false;
}

/* O laboratorio vem do cadastro do Digifarma, lido pelo agente. Quando
   nenhum item traz o laboratorio, a tela diz por que, em vez de so faltar:
   agente antigo, coluna nao achada ou cadastro de apoio nao achado. */
function pintarAvisoLaboratorio(itens) {
  const p = $('saldo-laboratorio');
  if (!itens.length || itens.some((i) => i.laboratorio)) { p.hidden = true; return; }
  const lab = estado.inventario?.diagnostico?.quem?.laboratorio;
  let texto;
  if (!lab) {
    texto = 'Laboratório: o agente do servidor ainda não manda esse dado. '
      + 'Atualize o agente (aba Servidor) e espere a próxima sincronização.';
  } else if (!lab.coluna) {
    texto = 'Laboratório: o agente não achou a coluna no cadastro de produtos. '
      + 'Colunas da PRODUTOS: ' + (lab.colunasDaTabela || []).join(', ')
      + ((lab.tabelasParecidas || []).length
        ? '. Tabelas parecidas: ' + lab.tabelasParecidas
          .map((t) => t.tabela + ' (' + (t.colunas || []).join(', ') + ')').join('; ')
        : '. Nenhuma tabela com LABORAT ou FABRIC no nome.');
  } else {
    texto = 'Laboratório: o agente achou a coluna PRODUTOS.' + lab.coluna
      + ', mas ela veio vazia nos produtos desta lista.';
  }
  p.textContent = texto;
  p.hidden = false;
}

/* Digifarma e foto do SNGPC com o MESMO numero, e mesmo assim divergencia:
   a diferenca e contra a foto MAIS o movimento que o agente acha que ainda
   nao esta nela. Sem mostrar esse movimento a tela dizia "saldos diferentes"
   com dois saldos iguais lado a lado. */
function bateSoSemMovimento(i) {
  return Number(i.movimentoDesdeEnvio || 0) !== 0
    && Number(i.saldoDigifarma || 0) === Number(i.saldoSngpc || 0);
}

const NOTA_BATE_SO_SEM_MOVIMENTO = 'Hoje o Digifarma e a foto do SNGPC mostram o mesmo número. '
  + 'A diferença vem do movimento acima, que o agente conta como ainda fora da foto. '
  + 'Se ele ainda não subiu, depois do envio o SNGPC fica com o "esperado" e passa a divergir: '
  + 'há erro no lote, compensado por acaso. Se ele já foi transmitido (envio por outra máquina '
  + 'ou ponteiro atrasado), o lote está certo e este aviso é falso. Confira no Relatório '
  + 'Status de Transmissão do site da ANVISA antes de mexer no estoque.';

/* O veredito vem do agente a cada sincronizacao (anotar_vereditos), com a
   mesma conta do relatorio do lote: as duas telas nao podem discordar. */
const VEREDITO_SALDO = {
  aviso_falso: ['Aviso falso provável', (i) => 'As vendas deste lote já constam na ANVISA: o site '
    + 'recebeu até a venda ' + i.vereditoCorte + ' e o ponteiro deste Digifarma não andou (envio '
    + 'feito por outra máquina). A conta desconta a mesma venda duas vezes. Confira no Relatório '
    + 'Status de Transmissão do site e acerte o ponteiro para ' + i.vereditoCorte
    + ' (aba Servidor, "Acertar o ponteiro"). Não mexa no estoque.'],
  acaso: ['Erro compensado por acaso', (i) => 'As vendas deste lote ainda não subiram: estão no meio '
    + 'da fila, com vendas mais antigas que não batem. Hoje os números coincidem por acaso; depois do '
    + 'envio o SNGPC fica com ' + i.esperadoSngpc + ' e o Digifarma com ' + i.saldoDigifarma
    + '. Conte a prateleira.']
};

/* O lote que so o Digifarma tem e o que so a ANVISA tem, no mesmo M.S. e
   com a mesma quantidade: e o mesmo estoque com numero de lote diferente
   (20/10: AMOX+CLAVU com 3 no DFG3073A no Digifarma e 3 no DFG6142A na
   ANVISA). O app dizia "entrada ainda nao transmitida", e a entrada tinha
   subido havia mais de um mes. */
function loteTrocado(i) {
  const lotes = comoLista(i.lotesDoMs);
  const digi = Number(i.saldoDigifarma || 0);
  const sngpc = Number(i.saldoSngpc || 0);
  if (digi > 0 && !sngpc) {
    return lotes.find((l) => l.lote !== i.lote && !Number(l.digifarma || 0)
      && Number(l.sngpc || 0) === digi) || null;
  }
  if (sngpc > 0 && !digi) {
    return lotes.find((l) => l.lote !== i.lote && !Number(l.sngpc || 0)
      && Number(l.digifarma || 0) === sngpc) || null;
  }
  return null;
}

/* PROD_SALDO, o saldo que a tela do balcao mostra, vem na lista de
   Controlados; a comparacao usa a soma dos lotes. 20/10: QUETROS com 1 no
   lote, zerado no balcao e na ANVISA. */
function saldoDoProduto(i) {
  if (!i.codigo) return null;
  const c = listaControlados().find((x) => String(x.codigo) === String(i.codigo));
  return c && c.saldoProduto !== undefined && c.saldoProduto !== null
    ? Number(c.saldoProduto) : null;
}

function detalheDoSaldo(i, dif) {
  const movimento = Number(i.movimentoDesdeEnvio || 0);
  const produto = saldoDoProduto(i) ?? (i.saldoProduto !== undefined ? Number(i.saldoProduto) : null);
  const totalLotes = Number(i.saldoDigifarmaMs ?? i.saldoDigifarma ?? 0);
  // o agente ja classifica (lote_trocado/resto_no_lote); a conta daqui vale
  // enquanto o agente do servidor for antigo
  const trocado = loteTrocado(i) || (i.loteParceiro ? { lote: i.loteParceiro } : null);
  const pares = [
    ['Código', i.codigo],
    ['Laboratório', i.laboratorio],
    ['Saldo Digifarma', i.saldoDigifarma],
    ['Saldo do produto no balcão (Digifarma)', produto !== null && produto !== totalLotes ? produto : ''],
    ['Saldo do inventário SNGPC (foto)', i.saldoSngpc],
    ['Movimento desde a foto', movimento ? (movimento > 0 ? '+' : '') + movimento : ''],
    ['SNGPC esperado hoje (foto + movimento)', movimento ? i.esperadoSngpc : ''],
    ['Diferença', (dif > 0 ? '+' : '') + dif],
    ['Registro M.S.', i.ms],
    ['Código de barras', i.ean],
    ['Lote', i.lote],
    ['Validade', i.validade],
    ['Classe', i.classe]
  ];
  comoLista(i.lotesDoMs).forEach((l) => {
    if (l.lote !== i.lote) {
      pares.push(['Outro lote deste M.S.: ' + l.lote, 'Digifarma ' + Number(l.digifarma || 0)
        + ' · SNGPC ' + Number(l.sngpc || 0)]);
    }
  });
  if (i.motivo === 'lote_em_dois_ms') {
    pares.push(['Outro M.S. com este lote', i.outroMs]);
    pares.push(['Total do lote no Digifarma', i.totalDigifarmaLote]);
    pares.push(['Total do lote na ANVISA', i.totalSngpcLote]);
  }
  const d = definicoes(pares);
  const nota = criar('p', 'motivo');
  if (i.motivo === 'lote_em_dois_ms') {
    // Os totais batendo mudam o que a farmacia tem de fazer: nao e conferir
    // prateleira, e ver em qual cadastro a entrada foi lancada.
    nota.textContent = i.totaisBatem
      ? 'Os totais do lote batem nos dois lados: a farmácia tem a quantidade certa, repartida entre os cadastros de um jeito diferente. É lançamento no cadastro errado, não falta de mercadoria.'
      : MOTIVO_SALDO.lote_em_dois_ms[1];
  } else if (i.motivo === 'resto_no_lote'
      || (produto === 0 && totalLotes > 0 && !Number(i.saldoSngpcMs ?? i.saldoSngpc ?? 0))) {
    nota.textContent = 'Na tela do balcão o produto está zerado, e na ANVISA também: os dois batem. '
      + 'O saldo ' + totalLotes + ' é resto na tabela de lotes do Digifarma, que não acompanhou a baixa. '
      + 'Não é divergência com a ANVISA: não mexa na escrituração.';
  } else if (trocado) {
    const q = Number(i.saldoDigifarma || 0) || Number(i.saldoSngpc || 0);
    const [noDigi, naAnvisa] = Number(i.saldoDigifarma || 0) ? [i.lote, trocado.lote] : [trocado.lote, i.lote];
    nota.textContent = 'Provável número de lote diferente: o Digifarma tem ' + q + ' no lote ' + noDigi
      + ' e a ANVISA tem ' + q + ' no lote ' + naAnvisa + ', do mesmo M.S. É o mesmo estoque com o lote '
      + 'registrado de outro jeito. Confira o lote impresso na caixa antes de mexer.';
  } else if (VEREDITO_SALDO[i.veredito]) {   // lote_em_dois_ms vem antes: e cadastro
    nota.textContent = VEREDITO_SALDO[i.veredito][1](i);
  } else if (bateSoSemMovimento(i)) {
    nota.textContent = NOTA_BATE_SO_SEM_MOVIMENTO;
  } else {
    nota.textContent = MOTIVO_SALDO[i.motivo]?.[1] || '';
  }
  if (nota.textContent) d.appendChild(nota);
  if (i.lote) {
    const b = criar('button', 'botao botao-secundario');
    b.textContent = 'Investigar este lote no servidor';
    b.onclick = () => investigarLote(i);
    d.appendChild(b);
  }
  // So produto do cadastro (com codigo) e marcado como controlado: o lote
  // que so existe na ANVISA nao tem o que desmarcar no Digifarma.
  if (i.codigo && i.classe) {
    const b = criar('button', 'botao botao-perigo');
    b.textContent = 'Desmarcar controlado/antibiótico no Digifarma';
    b.onclick = () => pedirDesmarcar(i);
    d.appendChild(b);
  }
  return d;
}

/* Pede ao agente o relatorio "saldo" do lote: como o saldo foi apurado no
   banco, o movimento que entrou na conta, o veredito (aviso falso, erro
   compensado por acaso, falta ou sobra) e se o lote aparece nos XML
   transmitidos. Sem digitar nada: M.S. e lote vao do proprio item. */
function investigarLote(i) {
  return gravarPedido({
    acao: 'saldo', texto: (i.ms || '') + '|' + i.lote,
    pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
  }).then((ok) => {
    if (!ok) return;
    estado.relatorioPedido = 'saldo';
    avisar('Investigação do lote ' + i.lote + ' pedida. A resposta aparece na aba Servidor.');
    irPara('servidor');
  }).catch((e) => avisar('O Firebase recusou o pedido: ' + (e.message || e)));
}

/* Desmarcar psicotropico/antimicrobiano de UM produto, pelo agente. E a
   caixa do cadastro do Digifarma, feita do celular: o produto sai do SNGPC.
   So com a escrita liberada (aba Servidor), que se fecha sozinha. */
function pedirDesmarcar(i, sugerido) {
  if (!estado.inventario?.escrita?.ligada) {
    abrirModal({
      titulo: 'Escrita no Digifarma desligada',
      corpo: (() => {
        const p = criar('p', 'sublinha');
        p.textContent = 'Para desmarcar, ligue a escrita na aba Servidor, bloco "Escrita no '
          + 'Digifarma". Ela vale 60 minutos e depois se fecha sozinha.';
        return p;
      })(),
      acoes: [
        { texto: 'Fechar', aoClicar: fecharModal },
        { texto: 'Ir para Servidor', estilo: 'botao-principal', aoClicar: () => { fecharModal(); irPara('servidor'); } }
      ]
    });
    return;
  }
  const corpo = criar('div');
  const p = criar('p', 'sublinha');
  p.textContent = (i.descricao || 'Produto') + ' (código ' + i.codigo + '). Desmarcado, o produto '
    + 'sai do SNGPC: as vendas dele deixam de ser escrituradas. Use só para produto marcado '
    + 'por engano. Para voltar, marque a caixa de novo no cadastro do Digifarma.';
  const rotulo = criar('label', 'campo');
  const span = criar('span'); span.textContent = 'Desmarcar';
  const sel = criar('select');
  [['ambos', 'Psicotrópico e antimicrobiano'], ['psicotropico', 'Só psicotrópico'],
   ['antimicrobiano', 'Só antimicrobiano']].forEach(([v, t]) => {
    const o = criar('option'); o.value = v; o.textContent = t; sel.appendChild(o);
  });
  // Vindo da lista de um grupo, ja sugere desmarcar so aquela marca.
  if (sugerido) sel.value = sugerido;
  rotulo.append(span, sel);
  corpo.append(p, rotulo);
  abrirModal({
    titulo: 'Desmarcar no Digifarma',
    corpo,
    acoes: [
      { texto: 'Cancelar', aoClicar: fecharModal },
      { texto: 'Desmarcar', estilo: 'botao-perigo', aoClicar: () => {
        fecharModal();
        gravarPedido({
          acao: 'desmarcar_controlado', produtoId: String(i.codigo), desmarcar: sel.value,
          pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
        }).then((ok) => ok && avisar('Pedido enviado. O agente desmarca na próxima passagem dele.'))
          .catch((e) => avisar('O Firebase recusou o pedido: ' + (e.message || e)));
      } }
    ]
  });
}

/* ============================================================
   ABA CONTROLADOS
   ============================================================
   Espelha a aba Saldo na forma: mesma linha expansivel, mesma busca,
   mesmo detalhe. Muda o que lista — ali e quem DIVERGE da ANVISA,
   aqui e todo controlado do cadastro que tem saldo no Digifarma,
   divergindo ou nao. Os de saldo zero ficam de fora (temSaldo).

   Duas listas separadas, escolhidas pelos botoes: Controlados
   (PSICOTROPICO='S') e Antimicrobianos (ANTIMICROBIANO='S'). Produto
   com as duas marcas aparece nas duas. */
function listaControlados() {
  const v = estado.inventario?.controlados;
  if (!v) return [];
  return Array.isArray(v) ? v.filter(Boolean) : Object.values(v);
}

/* So entra quem tem saldo no Digifarma. Vale qualquer um dos dois saldos:
   a soma dos lotes (a do SNGPC) ou o PROD_SALDO (o da tela do balcao).
   Quando discordam, o produto fica — e justamente o caso a conferir. */
function temSaldo(c) {
  return Number(c.saldo || 0) > 0 || Number(c.saldoProduto || 0) > 0;
}

function doGrupo(c, grupo) {
  return grupo === 'antimicrobiano' ? !!c.antimicrobiano : !!c.psicotropico;
}

function classeDoControlado(c) {
  if (c.psicotropico && c.antimicrobiano) return 'Psicotrópico e antimicrobiano';
  if (c.psicotropico) return 'Psicotrópico';
  if (c.antimicrobiano) return 'Antimicrobiano';
  return 'Sem marca';
}

function pintarControlados() {
  const alvo = $('lista-controlados');
  if (!alvo) return;
  alvo.innerHTML = '';

  const aviso = $('controlados-aviso');
  const comSaldo = listaControlados().filter(temSaldo);
  const grupo = estado.grupoControlados;
  const todos = comSaldo.filter((c) => doGrupo(c, grupo));
  [['psicotropico', 'Controlados'], ['antimicrobiano', 'Antimicrobianos']].forEach(([g, nome]) => {
    const b = $('grupo-' + g);
    b.textContent = nome + ' (' + comSaldo.filter((c) => doGrupo(c, g)).length + ')';
    b.setAttribute('aria-pressed', String(g === grupo));
  });
  if (!estado.inventario?.controlados) {
    // Lista ausente nao e lista vazia: o agente pode ser antigo ou a
    // consulta pode ter falhado. Dizer "nenhum controlado" aqui seria
    // afirmar o que nao se sabe, e logo sobre o que vai ser desmarcado.
    aviso.textContent = 'O agente ainda não publicou a lista de controlados. '
      + 'Atualize o agente na aba Servidor e sincronize.';
    aviso.hidden = false;
  } else {
    aviso.hidden = true;
  }

  const itens = todos
    .filter((c) => combina(c, estado.buscaControlados, ['descricao', 'ms', 'ean', 'codigo']))
    .sort((a, b) => String(a.descricao || '').localeCompare(String(b.descricao || ''), 'pt-BR'));

  $('controlados-vazio').hidden = itens.length > 0 || !!estado.buscaControlados
    || !estado.inventario?.controlados;

  const selo = $('selo-controlados');
  if (selo) { selo.textContent = comSaldo.length; selo.hidden = comSaldo.length === 0; }

  itens.forEach((c, n) => {
    const saldo = Number(c.saldo || 0);
    const outro = Number(c.saldoProduto || 0);
    alvo.appendChild(linha({
      chave: 'ctrl:' + (c.codigo || n),
      titulo: c.descricao || ('Código ' + (c.codigo || '?')),
      meta: [
        c.codigo && 'Cód. ' + c.codigo,
        c.ms && 'M.S. ' + c.ms,
        c.ean && 'EAN ' + c.ean
      ],
      tarja: [classeDoControlado(c), 'saldo ' + saldo],
      tarjaClasse: saldo > 0 ? 'sobra' : 'falta',
      detalhe: detalheDoControlado(c, saldo, outro)
    }));
  });

  if (!itens.length && estado.buscaControlados) {
    const p = criar('p', 'vazio');
    p.textContent = 'Nada encontrado para “' + estado.buscaControlados + '”.';
    alvo.appendChild(p);
  }
}

function detalheDoControlado(c, saldo, outro) {
  const d = definicoes([
    ['Código do Digifarma', c.codigo],
    ['Registro M.S.', c.ms],
    ['Código de barras', c.ean],
    ['Psicotrópico', c.psicotropico ? 'SIM' : 'não'],
    ['Antimicrobiano', c.antimicrobiano ? 'SIM' : 'não'],
    ['Saldo pela soma dos lotes', saldo],
    ['Saldo do produto (PROD_SALDO)', outro]
  ]);

  // Os dois saldos discordando e sinal de que um dos lados esta errado;
  // quem for desmarcar precisa ver isso antes, nao depois.
  if (Math.abs(saldo - outro) >= 0.001) {
    const nota = criar('p', 'motivo');
    nota.textContent = 'Os dois saldos que o Digifarma guarda não batem: a soma dos lotes dá '
      + saldo + ' e o total do produto dá ' + outro + '. A tela do balcão lê o segundo; '
      + 'a comparação com o SNGPC usa o primeiro.';
    d.appendChild(nota);
  }

  const b = criar('button', 'botao botao-perigo');
  b.textContent = 'Desmarcar controlado/antibiótico no Digifarma';
  b.onclick = () => pedirDesmarcar(c, estado.grupoControlados);
  d.appendChild(b);
  return d;
}

function pintarSaldo() {
  const alvo = $('lista-saldo');
  alvo.innerHTML = '';
  pintarConfiancaDoSaldo();
  const peso = (i) => {
    const p = ORDEM_MOTIVO.indexOf(i.motivo);
    return p < 0 ? ORDEM_MOTIVO.length : p;
  };
  const itens = divergenciasDeSaldo()
    .filter((i) => combina(i, estado.buscaSaldo, ['descricao', 'laboratorio', 'ms', 'ean', 'lote', 'codigo']))
    .sort((a, b) => peso(a) - peso(b)
      || Math.abs(Number(b.diferenca || 0)) - Math.abs(Number(a.diferenca || 0)));
  $('saldo-vazio').hidden = itens.length > 0 || !!estado.buscaSaldo;
  pintarAvisoLaboratorio(itens);

  itens.forEach((i, n) => {
    const dif = Number(i.diferenca || 0);
    alvo.appendChild(linha({
      chave: 'saldo:' + (i.codigo || n) + ':' + (i.lote || ''),
      titulo: i.descricao || i.codigo || '(sem descrição)',
      meta: [
        i.laboratorio && 'Lab. ' + i.laboratorio,
        i.ms && 'M.S. ' + i.ms,
        i.ean && 'EAN ' + i.ean,
        i.lote && 'Lote ' + i.lote,
        i.validade && 'Val. ' + datasBR(i.validade)
      ],
      tarja: [(i.motivo !== 'lote_em_dois_ms' && VEREDITO_SALDO[i.veredito]?.[0])
              || (bateSoSemMovimento(i) && 'Iguais hoje, com movimento pendente')
              || MOTIVO_SALDO[i.motivo]?.[0] || (dif < 0 ? 'Falta no Digifarma' : 'Sobra no Digifarma'),
              (dif > 0 ? '+' : '') + dif],
      tarjaClasse: dif < 0 ? 'falta' : 'sobra',
      detalhe: detalheDoSaldo(i, dif)
    }));
  });

  if (!itens.length && estado.buscaSaldo) {
    const p = criar('p', 'vazio');
    p.textContent = 'Nada encontrado para “' + estado.buscaSaldo + '”.';
    alvo.appendChild(p);
  }
}

/* "0 divergencias" tanto pode ser conferencia limpa quanto conferencia que
   nao aconteceu - sem XML, sem periodo, ou sem venda no periodo. O mesmo
   zero enganoso que fez 4135 sobras parecerem divergencia. */
function pintarConfiancaDoXml() {
  const barra = $('xml-confianca');
  const r = estado.inventario?.conferenciaXmlResumo;
  if (!r || r.conferiu !== false) { barra.hidden = true; return; }
  barra.innerHTML = '<strong>A conferência do XML não aconteceu.</strong><br>'
    + html(r.porque || 'o agente não disse por quê')
    + '<br>Então a lista vazia abaixo não quer dizer que está tudo certo.';
  barra.hidden = false;
}

function detalheDoXml(c) {
  const pares = [
    ['Laboratório', c.laboratorio],
    ['Registro M.S.', c.ms],
    ['Lote', c.lote],
    ['Quantidade no banco', c.qtdBanco],
    ['Quantidade no XML', c.qtdXml],
    ['Período conferido', c.periodo],
    ['Arquivo XML', c.arquivo],
    ['Vendas envolvidas', Array.isArray(c.vendas) ? c.vendas.join(', ') : c.vendas]
  ];
  if (c.situacao === 'ms_trocado') pares.splice(1, 0, ['M.S. que subiu no XML', c.outroMs]);
  const d = definicoes(pares);
  if (c.situacao === 'ms_trocado') {
    const nota = criar('p', 'motivo');
    nota.textContent = 'O mesmo lote saiu por um M.S. no Digifarma e por outro no XML. '
      + 'Acontece quando o cadastro foi corrigido depois da transmissão: o movimento subiu '
      + 'com o M.S. que valia na hora. O XML já transmitido não se conserta.';
    d.appendChild(nota);
  }
  return d;
}

function pintarXml() {
  const alvo = $('lista-xml');
  alvo.innerHTML = '';
  pintarConfiancaDoXml();
  const itens = pendenciasXml()
    .filter((c) => combina(c, estado.buscaXml, ['descricao', 'laboratorio', 'ms', 'lote']));
  $('xml-vazio').hidden = itens.length > 0 || !!estado.buscaXml;

  const ROTULO = {
    fora_do_xml: ['Saiu no banco e não está no XML', 'falta'],
    so_no_xml: ['Está no XML e não achei no banco', 'sobra'],
    quantidade: ['Quantidade diferente', 'sobra'],
    ms_trocado: ['Mesmo lote, M.S. diferente no XML', 'sobra']
  };

  itens.forEach((c, n) => {
    const [rotulo, classe] = ROTULO[c.situacao] || ['Divergência', 'falta'];
    alvo.appendChild(linha({
      chave: 'xml:' + (c.ms || n) + ':' + (c.lote || ''),
      titulo: c.descricao || ('M.S. ' + (c.ms || '?')),
      meta: [
        c.laboratorio && 'Lab. ' + c.laboratorio,
        c.ms && 'M.S. ' + c.ms,
        c.lote && 'Lote ' + c.lote,
        c.periodo && 'Período ' + datasBR(c.periodo)
      ],
      tarja: [rotulo, `banco ${c.qtdBanco ?? 0} · xml ${c.qtdXml ?? 0}`],
      tarjaClasse: classe,
      detalhe: detalheDoXml(c)
    }));
  });

  if (!itens.length && estado.buscaXml) {
    const p = criar('p', 'vazio');
    p.textContent = 'Nada encontrado para “' + estado.buscaXml + '”.';
    alvo.appendChild(p);
  }
}

/* As vendas de controlado de hoje, com a receita lancada ou nao. O agente
   publica isto a cada passagem da fila (vendasRecentes, 7 dias, uma linha
   por lote), mas a tela so mostrava as vendas com problema: venda certa,
   com receita ja lancada, nao aparecia em lugar nenhum, e quem conferia o
   dia nao tinha como ver que ela tinha entrado. */
function hojeLocal() {
  const d = new Date();
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0')
    + '-' + String(d.getDate()).padStart(2, '0');
}

function vendasDeHoje() {
  const hoje = hojeLocal();
  return lista('vendasRecentes')
    .filter((v) => String(v.quando || '').slice(0, 10) === hoje)
    .sort((a, b) => String(b.quando || '').localeCompare(String(a.quando || '')));
}

function pintarVendasDeHoje() {
  const alvo = $('lista-vendas-hoje');
  alvo.innerHTML = '';
  const publicado = Boolean(estado.inventario?.vendasRecentes);
  const em = estado.inventario?.vendasRecentesEm;
  $('vendas-hoje-quando').textContent = !publicado
    ? 'O agente ainda não publicou as vendas recentes.'
    : 'Uma linha por lote vendido.' + (em ? ' Lista atualizada em ' + dataHora(em) + '.' : '');
  const itens = vendasDeHoje();
  $('vendas-hoje-vazio').hidden = itens.length > 0 || !publicado;

  itens.forEach((v, n) => {
    const hora = String(v.quando || '').slice(11, 16);
    alvo.appendChild(linha({
      chave: 'hoje:' + (v.venda ?? n) + ':' + (v.lote || n),
      titulo: v.descricao || ('Venda ' + (v.venda ?? '?')),
      meta: [hora, v.venda && 'Venda ' + v.venda, v.laboratorio && 'Lab. ' + v.laboratorio,
             v.lote ? 'Lote ' + v.lote : 'Sem lote', v.vendedor],
      tarja: [v.receita ? 'Receita lançada' : 'Falta lançar a receita', 'Qtd ' + (v.quantidade ?? '—')],
      tarjaClasse: v.receita ? 'ok' : 'sobra',
      detalhe: definicoes([
        ['Venda', v.venda],
        ['Hora', hora],
        ['Produto', v.descricao],
        ['Laboratório', v.laboratorio],
        ['Registro M.S.', v.ms],
        ['Lote', v.lote],
        ['Quantidade', v.quantidade],
        ['Atendeu', v.vendedor],
        ['Receita', v.receita ? 'lançada no Digifarma' : 'ainda não lançada']
      ])
    }));
  });
}

function pintarVendas() {
  pintarVendasDeHoje();
  const alvo = $('lista-vendas');
  alvo.innerHTML = '';
  const itens = vendasProblema();
  $('vendas-vazio').hidden = itens.length > 0;

  const MOTIVO = {
    sem_receita: 'Controlado vendido sem receita escriturada (VENDAS_PSICOTROPICOS).',
    sem_lote: 'Item sem lote informado (ITEM_VENDAS_LOTES).',
    sem_ms: 'Produto sem registro M.S. cadastrado.'
  };

  itens.forEach((v, n) => {
    const detalhe = definicoes([
      ['Venda', v.venda],
      ['Data', dataBR(v.data)],
      ['Produto', v.descricao],
      ['Laboratório', v.laboratorio],
      ['Registro M.S.', v.ms],
      ['Lote', v.lote],
      ['Quantidade', v.quantidade],
      ['Operador da venda', v.operador]
    ]);
    const nota = criar('p', 'motivo');
    nota.textContent = MOTIVO[v.motivo] || v.motivo || 'Pendência não classificada.';
    detalhe.appendChild(nota);

    alvo.appendChild(linha({
      chave: 'venda:' + (v.venda || n),
      titulo: v.descricao || ('Venda ' + (v.venda ?? '?')),
      meta: [v.data && dataBR(v.data), v.laboratorio && 'Lab. ' + v.laboratorio,
             v.ms && 'M.S. ' + v.ms, v.lote ? 'Lote ' + v.lote : 'Sem lote'],
      tarja: ['Corrigir no Digifarma antes do próximo envio', 'Venda ' + (v.venda ?? '—')],
      tarjaClasse: 'falta',
      detalhe
    }));
  });
}

/* ============================================================
   11b. SERVIDOR
   ============================================================ */
const MINUTOS_ATE_PARADO = 30;
/* Acima disto o dado deixa de servir para conferir prateleira: o
   Digifarma andou e a tela nao. Um dia ja e muito num sistema que
   transmite todo dia. */
const HORAS_ATE_VELHO = 24;

function minutosDesde(iso) {
  if (!iso || typeof iso !== 'string') return null;
  const d = new Date(iso);
  if (isNaN(d)) return null;
  return Math.floor((Date.now() - d.getTime()) / 60000);
}

/* O aviso de agente parado olha vistoEm, nao atualizadoEm.
   atualizadoEm so muda quando o RESULTADO muda, e num dia sem movimento
   ele fica parado de proposito: usa-lo aqui acusava agente morto com o
   agente vivo. vistoEm e gravado a cada volta, mude o que mudar. */
/* O numero velho e pior que numero nenhum: ele parece atual.
   Em 08/10 a tela mostrava Saldo 5, XML 8 e Vendas 27 que eram de
   10/09 - quase um mes de vendas e entradas que o app nao sabia que
   existiam, sem nada na tela dizendo isso. */
function textoDadoVelho() {
  const quando = estado.inventario?.atualizadoEm;
  const min = minutosDesde(quando);
  if (min === null || min < HORAS_ATE_VELHO * 60) return '';
  const dias = Math.floor(min / 1440);
  const idade = dias >= 1 ? dias + ' dia(s)' : Math.floor(min / 60) + ' hora(s)';
  return 'ATENÇÃO: estes números são de ' + dataHora(quando)
    + ' — ' + idade + ' atrás. O agente não publicou desde então, então as '
    + 'vendas e entradas desse período NÃO estão aqui. Não use para conferir '
    + 'prateleira nem para decidir transmissão.';
}

/* A barra de estado mostra o dado velho E o inventario da ANVISA velho,
   juntos, e some sozinha quando os dois passam. So mexe no que ela mesma
   pos: aviso de permissao e de sem internet continuam onde estao. */
function avisarDadoVelho() {
  const barra = $('barra-estado');
  const partes = [textoDadoVelho(), textoSobreAnvisa()].filter(Boolean);
  if (partes.length) {
    barra.textContent = partes.join(' ');
    barra.dataset.origem = 'dados';
    barra.hidden = false;
    return true;
  }
  if (barra.dataset.origem === 'dados') {
    barra.hidden = true;
    barra.dataset.origem = '';
  }
  return false;
}

function pintarAgenteParado() {
  const barra = $('agente-parado');
  const selo = $('selo-servidor');
  const min = minutosDesde(estado.inventario?.vistoEm);
  const parado = min !== null && min >= MINUTOS_ATE_PARADO;
  if (min === null) {
    barra.className = 'barra-aviso';
    barra.textContent = 'O agente ainda não registrou passagem. Se acabou de atualizar, espere alguns minutos.';
    barra.hidden = false;
  } else if (parado) {
    barra.className = 'barra-aviso grave';
    barra.textContent = 'O agente não dá sinal há ' + min + ' minuto(s). '
      + 'Passando de ' + MINUTOS_ATE_PARADO + ', vale conferir se o servidor está ligado.';
    barra.hidden = false;
  } else {
    barra.hidden = true;
  }
  selo.hidden = !parado;
}

function pintarPonteiroSugerido() {
  const alvo = $('ponteiro-sugerido');
  alvo.innerHTML = '';

  /* Acerto feito: mostrar e deixar desfazer. Em 10/10 o acerto para 48307
     estava errado - as vendas nao tinham subido - e o Saldo foi de 10 para
     25 divergencias. Nao havia botao para voltar: so editando o Firebase
     na mao ou indo ao servidor. Acerto que nao se desfaz de longe fica. */
  const envio = estado.inventario?.envio || {};
  if (envio.ponteiroForcado) {
    alvo.appendChild(definicoes([
      ['Tratando como enviado até a venda', envio.ULT_SAIDA_VENDA_NOTA_ID],
      ['O Digifarma diz', envio.ponteiroDoDigifarma]
    ]));
    const nota = criar('p', 'motivo');
    nota.textContent = 'O ponteiro foi acertado à mão. Se a foto do inventário da ANVISA '
      + 'ainda não tem essas vendas (foto baixada antes do envio), elas saem da conta e cada '
      + 'lote vendido aparece como divergência no Saldo. Desfazer só muda a conta do agente; '
      + 'nada é gravado no Digifarma.';
    alvo.appendChild(nota);
    const desfazer = criar('button', 'botao botao-secundario');
    desfazer.textContent = 'Desfazer o acerto';
    desfazer.onclick = async () => {
      if (!(await confirmar('Desfazer o acerto do ponteiro',
        'O agente volta a usar o ponteiro do próprio Digifarma'
        + (envio.ponteiroDoDigifarma ? ' (' + envio.ponteiroDoDigifarma + ')' : '')
        + ' e recalcula o Saldo.', 'Desfazer'))) return;
      if (!(await gravarPedido({
        acao: 'config', chave: 'transmitido_ate_venda', valor: '0',
        pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
      }))) return;
      avisar('Pedido enviado. O agente atende na próxima passagem dele.');
    };
    alvo.appendChild(desfazer);
    return;
  }

  const p = estado.inventario?.ponteiroSugerido;
  if (!p || p.corte === undefined || p.corte === null) {
    const txt = criar('p', 'sublinha');
    txt.textContent = 'Nada a acertar: o ponteiro do Digifarma bate com o que a ANVISA já recebeu.';
    alvo.appendChild(txt);
    return;
  }
  alvo.appendChild(definicoes([
    ['Número sugerido', p.corte],
    ['Cobre movimentos até', dataBR(p.ate)],
    ['Vendas que ficariam presas', p.presas]
  ]));
  const nota = criar('p', 'motivo');
  nota.textContent = 'O ponteiro do Digifarma está atrás do que o site já recebeu. '
    + 'Sem acertar, as mesmas vendas sobem de novo no próximo envio.';
  alvo.appendChild(nota);

  const b = criar('button', 'botao botao-principal');
  b.textContent = 'Acertar o ponteiro para ' + p.corte;
  b.onclick = async () => {
    if (!(await confirmar('Acertar o ponteiro',
      'Isto manda o agente gravar ' + p.corte + ' como última venda transmitida. '
      + 'Só faça se o site da ANVISA já aceitou tudo até ' + dataBR(p.ate) + '.',
      'Acertar'))) return;
    // acao 'config' com chave de CONFIG_REMOTO: e o protocolo que o agente
    // ja atende. Nao inventar acao nova - acao que o agente nao conhece
    // vira botao que nao faz nada, e ninguem descobre.
    if (!(await gravarPedido({
      acao: 'config', chave: 'transmitido_ate_venda', valor: String(p.corte),
      pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
    }))) return;
    avisar('Pedido enviado. O agente atende na próxima passagem dele.');
  };
  alvo.appendChild(b);
}

function pintarEscrita() {
  const e = estado.inventario?.escrita || {};
  const dl = $('dados-escrita');
  dl.innerHTML = '';
  [['Escrita', estado.inventario?.escrita ? (e.ligada ? 'LIGADA' : 'desligada') : 'o agente não publicou'],
   ['Prazo', e.ligada ? (e.semPrazo ? 'sem prazo' : (e.ate ? 'até ' + dataHora(e.ate) : '—')) : '—']
  ].forEach(([k, v]) => {
    const dt = criar('dt'); dt.textContent = k;
    const dd = criar('dd'); dd.textContent = esc(v);
    dl.append(dt, dd);
  });
}

/* Campo sem valor NAO some: some vira painel em branco, que nao
   distingue "o agente nao publicou isto" de "o app esta quebrado".
   Cada linha ausente diz o que falta e o que destrava. */
/* O agente confere o GitHub de 10 em 10 minutos e troca sozinho; aqui
   aparece quando foi a ultima troca e, se falhou, por que. */
function textoDaAtualizacao(u) {
  if (!u || !u.em) return 'nenhuma registrada ainda (o agente confere o GitHub de 10 em 10 min)';
  return dataHora(u.em) + ' (' + (u.como || 'automática') + ') — '
    + (u.ok ? 'ok' : 'FALHOU: ') + (u.ok ? '' : (u.mensagem || 'sem mensagem'));
}

function pintarAgente() {
  const a = estado.inventario?.agente || {};
  const dl = $('dados-agente');
  dl.innerHTML = '';

  const semNada = !estado.inventario || !Object.keys(estado.inventario).length;
  const linhas = semNada
    ? [['Situação', 'Não chegou nada de farmacia/inventario. Ou o agente nunca publicou, ou este login não tem permissão de leitura.']]
    : [
      ['Arquivo do agente', a.bytes ? a.bytes + ' bytes · ' + (a.hash || '') : 'o agente não publicou — versão antiga no servidor'],
      ['Agente gravado em', a.em ? dataHora(a.em) : '—'],
      ['Última atualização', textoDaAtualizacao(a.ultimaAtualizacao)],
      ['XML de outros computadores', textoXmlRede(estado.inventario?.xmlRede)],
      ['Última passagem', estado.inventario?.vistoEm ? dataHora(estado.inventario.vistoEm) : 'o agente não publicou vistoEm — versão antiga no servidor'],
      ['Último resultado', estado.inventario?.atualizadoEm ? dataHora(estado.inventario.atualizadoEm) : '—'],
      ['Conta de serviço', a.chave?.conta || '—'],
      ['Projeto', a.chave?.projeto || '—'],
      // Qual das chaves do console este agente usa. Sem isto, apagar as
      // chaves vazadas vira adivinhacao: apagar a errada derruba o agente.
      ['Chave em uso', a.chave?.id || 'o agente não publicou a identidade da chave']
    ];

  linhas.forEach(([k, v]) => {
    const dt = criar('dt'); dt.textContent = k;
    const dd = criar('dd'); dd.textContent = esc(v);
    dl.append(dt, dd);
  });

  if (!semNada && !a.chave?.id) {
    const nota = criar('p', 'motivo');
    nota.textContent = 'Para estes campos aparecerem, o servidor precisa estar com o agente '
      + 'atualizado. Rode o APONTAR_SERVIDOR.bat na pasta do agente: os .bat que estão lá '
      + 'ainda baixam do repositório antigo, que saiu do ar.';
    dl.parentNode.appendChild(nota);
  }
}

/* Cada botao manda um pedido que o agente JA atende. Nenhuma acao
   inventada aqui: acao que o agente nao conhece vira botao que nao faz
   nada, e o teste_bat.py cruza as duas listas por isso. */
const ACOES_SERVIDOR = [
  ['atualizar_agente', 'Atualizar o agente', 'Baixa a versão mais nova do GitHub e troca, conferindo antes. É o ATUALIZAR_AGENTE.bat.'],
  ['anvisa', 'Abrir o Anvisa.exe', 'Abre o programa da ANVISA no servidor. Ele para na tela de login do SNGPC, por desenho da ANVISA.'],
  ['arrumar_tarefa_anvisa', 'Arrumar a tarefa do Anvisa', 'Reescreve a tarefa agendada AnvisaSNGPC_Login quando ela aponta para caminho errado.']
];

const RELATORIOS_SERVIDOR = [
  ['resumo', 'Resumo'], ['pendentes', 'Pendentes'], ['ponteiro', 'Ponteiro'],
  ['tarefas', 'Tarefas'], ['negativos', 'Negativos'], ['inventario', 'Inventario'],
  ['login_sngpc', 'Login SNGPC'], ['retorno_anvisa', 'Retorno ANVISA'],
  ['log_anvisa', 'Log do Anvisa'], ['log_agente', 'Log do agente (7 dias)'],
  ['colunas', 'Colunas do banco']
];

function pedirRelatorio(acao, rotulo) {
  return gravarPedido({
    acao, pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
  }).then((ok) => {
    if (!ok) return;
    estado.relatorioPedido = acao;
    avisar(rotulo + ' pedido. O agente atende na próxima passagem dele.');
  });
}

function pintarFerramentas() {
  const alvo = $('ferramentas');
  alvo.innerHTML = '';

  ACOES_SERVIDOR.forEach(([acao, rotulo, explica]) => {
    const b = criar('button', 'botao botao-secundario');
    b.textContent = rotulo;
    b.title = explica;
    b.onclick = async () => {
      if (!(await confirmar(rotulo, explica, 'Pedir'))) return;
      await pedirRelatorio(acao, rotulo);
    };
    alvo.appendChild(b);
  });

  // Ligar pelo app vale 60 minutos e se fecha sozinho (o agente grava o
  // prazo). Sem isso, desmarcar controlado pelo celular dependeria de
  // alguem no servidor, que a farmacia nem sempre alcanca.
  if (estado.inventario?.escrita && !estado.inventario.escrita.ligada) {
    const b = criar('button', 'botao botao-secundario');
    b.textContent = 'Ligar a escrita por 60 minutos';
    b.onclick = async () => {
      if (!(await confirmar('Ligar a escrita no Digifarma',
        'Libera, por 60 minutos, desmarcar controlado/antibiótico pelo app. '
        + 'Depois se fecha sozinha.', 'Ligar'))) return;
      await gravarPedido({
        acao: 'config', chave: 'permitir_ajuste_estoque', valor: 'true',
        pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
      }).then((ok) => ok && avisar('Pedido de ligar enviado. O agente atende na próxima passagem dele.'))
        .catch((e) => avisar('O Firebase recusou o pedido: ' + (e.message || e)));
    };
    alvo.appendChild(b);
  }

  // Desligar antes do prazo tambem e pelo app.
  if (estado.inventario?.escrita?.ligada) {
    const b = criar('button', 'botao botao-perigo');
    b.textContent = 'Desligar a escrita agora';
    b.onclick = async () => {
      if (!(await confirmar('Desligar a escrita no Digifarma',
        'Fecha a porta que permite alterar o Digifarma (desmarcar controlado, '
        + 'zerar lote negativo, gravar contagem).', 'Desligar', 'botao-perigo'))) return;
      if (!(await gravarPedido({
        acao: 'config', chave: 'permitir_ajuste_estoque', valor: 'false',
        pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
      }))) return;
      avisar('Pedido de desligar enviado.');
    };
    alvo.appendChild(b);
  }

  RELATORIOS_SERVIDOR.forEach(([acao, rotulo]) => {
    const b = criar('button', 'botao botao-fantasma');
    b.textContent = rotulo;
    b.onclick = () => pedirRelatorio(acao, 'Relatorio ' + rotulo);
    alvo.appendChild(b);
  });

  /* Busca nos XML de transmissao: "essa entrada subiu? com que M.S.? com
     que lote?". Vazio procura os lotes com divergencia no Saldo. */
  const busca = criar('button', 'botao botao-fantasma');
  busca.textContent = 'Buscar nos XML';
  busca.onclick = () => {
    const corpo = criar('div');
    const p = criar('p', 'sublinha');
    p.textContent = 'M.S. ou lote. Em branco, procura todos os lotes com divergência no Saldo.';
    const campo = criar('input', 'busca');
    campo.type = 'search';
    campo.placeholder = 'Ex.: 1004313820110 ou DFG3073A';
    campo.setAttribute('aria-label', 'M.S. ou lote para buscar nos XML');
    corpo.append(p, campo);
    campo.onkeydown = (ev) => {
      if (ev.key === 'Enter') { ev.preventDefault(); document.querySelector('#modal-acoes .botao-principal')?.click(); }
    };
    abrirModal({
      titulo: 'Buscar nos XML',
      corpo,
      acoes: [
        { texto: 'Cancelar', aoClicar: fecharModal },
        { texto: 'Buscar', estilo: 'botao-principal', aoClicar: () => {
          fecharModal();
          gravarPedido({
            acao: 'xml', texto: campo.value.trim(),
            pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
          }).then((ok) => {
            if (!ok) return;
            estado.relatorioPedido = 'xml';
            avisar('Busca pedida. O agente atende na próxima passagem dele.');
          })
            .catch((e) => avisar('O Firebase recusou o pedido: ' + (e.message || e)));
        } }
      ]
    });
  };
  alvo.appendChild(busca);

  /* O caixa e o computador do farmaceutico tambem transmitem, e o XML fica
     no disco de quem enviou. Depois do COMPARTILHAR_XML.bat naquele
     computador, aqui se digita o nome e a senha que ele mostrou. A senha
     passa pelo pedido e o agente a apaga dali na primeira passagem. */
  const rede = criar('button', 'botao botao-fantasma');
  rede.textContent = 'XML de outro computador';
  rede.onclick = () => {
    const corpo = criar('div');
    const p = criar('p', 'sublinha');
    p.textContent = 'Nome e senha que o COMPARTILHAR_XML.bat mostrou no outro computador. '
      + 'Senha em branco tira o computador da lista.';
    const nome = criar('input', 'busca');
    nome.placeholder = 'Nome do computador, ex.: CAIXA-01';
    nome.setAttribute('aria-label', 'Nome do computador');
    nome.autocomplete = 'off';
    const senha = criar('input', 'busca');
    senha.type = 'password';
    senha.placeholder = 'Senha';
    senha.setAttribute('aria-label', 'Senha do compartilhamento');
    senha.autocomplete = 'new-password';
    corpo.append(p, nome, senha);
    abrirModal({
      titulo: 'XML de outro computador',
      corpo,
      acoes: [
        { texto: 'Cancelar', aoClicar: fecharModal },
        { texto: 'Gravar', estilo: 'botao-principal', aoClicar: () => {
          const computador = nome.value.trim().toUpperCase();
          if (!/^[A-Z0-9][A-Z0-9_-]{0,14}$/.test(computador)) {
            avisar('Nome de computador inválido: use o que o COMPARTILHAR_XML.bat mostrou.');
            return;
          }
          fecharModal();
          gravarPedido({
            acao: 'pasta_rede', texto: computador, senha: senha.value,
            pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
          }).then((ok) => {
            if (ok) avisar('Pedido gravado. O agente testa a leitura na próxima passagem dele.');
          })
            .catch((e) => avisar('O Firebase recusou o pedido: ' + (e.message || e)));
        } }
      ]
    });
  };
  alvo.appendChild(rede);
}

/* Situacao de cada computador cadastrado, como o agente publicou. */
function textoXmlRede(lista) {
  if (!Array.isArray(lista) || !lista.length) return 'nenhum computador cadastrado (só o servidor)';
  return lista.map((l) => (l.computador || '?') + ': '
    + (l.ok ? (l.arquivo ? 'ok, último ' + l.arquivo : 'ok, sem XML de envio lá')
      : 'FALHOU: ' + (l.erro || 'sem mensagem'))
    + (l.em ? ' (' + dataHora(l.em) + ')' : '')).join(' · ');
}

function relatorioMaisNovo() {
  const lista = Object.entries(estado.relatorios || {}).filter(([, r]) => r && r.texto);
  lista.sort((a, b) => String(b[1].em || '').localeCompare(String(a[1].em || '')));
  return lista.length ? lista[0][0] : '';
}

function pintarRelatorio() {
  const bloco = $('bloco-relatorio');
  // Quem fechou e abriu o app perdeu o relatorioPedido, que fica so na
  // memoria; o ultimo pedido da fila diz qual relatorio mostrar.
  let acao = estado.relatorioPedido || estado.comando?.acao;
  // Um "Sincronizar vendas" depois do relatorio escondia a resposta, que
  // continuava no Firebase: sem relatorio do ultimo pedido, vale o mais novo
  // - com titulo que nao o faz passar pela resposta do pedido de agora.
  let anterior = false;
  if (!(acao && estado.relatorios?.[acao]?.texto)) { acao = relatorioMaisNovo(); anterior = true; }
  const r = acao && estado.relatorios?.[acao];
  if (!r || !r.texto) { bloco.hidden = true; return; }
  // pedido novo ainda na fila e o relatorio guardado e de antes dele: e o
  // antigo, nao a resposta (Investigar outro lote mostrava o lote anterior)
  const c = estado.comando;
  const esperando = c && c.estado === 'pendente' && c.acao === acao
    && String(r.em || '') < String(c.pedidoEm || '');
  if (esperando) anterior = true;
  $('relatorio-titulo').textContent = (esperando ? 'Relatório ANTERIOR (o agente ainda vai responder o pedido de agora) — '
    : (anterior ? 'Último relatório recebido — ' : 'Resposta do servidor — ')) + acao;
  $('relatorio-em').textContent = 'gerado em ' + dataHora(r.em)
    + (r.cortado ? ' · texto cortado por ser muito longo' : '');
  $('relatorio').textContent = r.texto;
  const copiar = $('copiar-relatorio');
  if (copiar) copiar.onclick = () => copiarTexto(r.texto);
  bloco.hidden = false;
}

/* No celular a caixa do relatorio corta o texto e rolar dentro dela para
   selecionar e dificil: o botao copia tudo de uma vez para colar no chat. */
function copiarTexto(t) {
  const ok = () => avisar('Relatório copiado. É só colar onde quiser.');
  if (navigator.clipboard?.writeText) {
    navigator.clipboard.writeText(t).then(ok).catch(() => copiarAntigo(t, ok));
  } else {
    copiarAntigo(t, ok);
  }
}

function copiarAntigo(t, ok) {
  const area = document.createElement('textarea');
  area.value = t;
  area.setAttribute('readonly', '');
  area.style.position = 'fixed';
  area.style.opacity = '0';
  document.body.appendChild(area);
  area.select();
  let deu = false;
  try { deu = document.execCommand('copy'); } catch (e) { deu = false; }
  area.remove();
  if (deu) ok(); else avisar('Não consegui copiar. Toque e segure no texto do relatório para selecionar.');
}

/* ============================================================
   11c. AVISOS NO CELULAR (Firebase Cloud Messaging)
   ============================================================ */
/* A chave publica de Web Push (VAPID) e gerada no console do Firebase:
   Configuracoes do projeto > Cloud Messaging > Certificados push da Web.
   E publica por natureza (vai para o navegador); fica em farmacia/config
   para ser colada pelo app, sem publicar versao nova. */
const CHAVE_AVISO_LOCAL = 'farmacia.aviso';

function avisosSuportados() {
  return 'Notification' in window && 'serviceWorker' in navigator
    && typeof firebase.messaging === 'function';
}

function pintarAvisos() {
  const p = $('avisos-estado');
  const alvo = $('avisos-acoes');
  if (!p || !alvo) return;
  alvo.innerHTML = '';
  const chave = estado.config?.vapidKey;
  const ligado = localStorage.getItem(CHAVE_AVISO_LOCAL);
  const botao = (texto, estilo, acao) => {
    const b = criar('button', 'botao ' + estilo);
    b.textContent = texto;
    b.onclick = acao;
    alvo.appendChild(b);
  };

  if (!avisosSuportados()) {
    p.textContent = 'Este navegador não recebe avisos. No iPhone: Compartilhar > Adicionar à Tela de Início, e abra o app por lá.';
    return;
  }
  if (!chave) {
    p.textContent = 'Falta a chave de avisos do Firebase (uma vez só, para todos os celulares).';
    botao('Colar a chave de avisos', 'botao-secundario', pedirChaveDeAviso);
    return;
  }
  if (Notification.permission === 'denied') {
    p.textContent = 'Os avisos foram bloqueados neste celular. Libere nas configurações do navegador para este site.';
    return;
  }
  p.textContent = ligado && Notification.permission === 'granted'
    ? 'Avisos ligados neste celular desde ' + dataHora(ligado) + '.'
    : 'Avisos desligados neste celular.';
  botao(ligado ? 'Religar avisos' : 'Ligar avisos neste celular', 'botao-secundario', ligarAvisos);
  if (ligado) {
    botao('Mandar um aviso de teste', 'botao-fantasma', () => pedirRelatorio('testar_aviso', 'Aviso de teste'));
  }
}

function pedirChaveDeAviso() {
  const corpo = criar('div');
  const p = criar('p', 'sublinha');
  p.textContent = 'No console do Firebase: Configurações do projeto > Cloud Messaging > '
    + 'Certificados push da Web > Gerar par de chaves. Copie a chave e cole aqui.';
  const campo = criar('input', 'busca');
  campo.placeholder = 'Chave pública (começa com B…)';
  campo.setAttribute('aria-label', 'Chave pública de avisos');
  corpo.append(p, campo);
  abrirModal({
    titulo: 'Chave de avisos',
    corpo,
    acoes: [
      { texto: 'Cancelar', aoClicar: fecharModal },
      { texto: 'Salvar', estilo: 'botao-principal', aoClicar: () => {
        const v = campo.value.trim();
        // chave VAPID publica: base64url de 65 bytes, ~87 caracteres
        if (!/^[A-Za-z0-9_-]{80,100}$/.test(v)) { avisar('Isso não parece a chave pública de Web Push.'); return; }
        fecharModal();
        db.ref('farmacia/config').update({ vapidKey: v })
          .then(() => avisar('Chave salva. Agora ligue os avisos neste celular.'))
          .catch((e) => avisar('O Firebase recusou: ' + (e.message || e)));
      } }
    ]
  });
}

async function ligarAvisos() {
  try {
    const permissao = await Notification.requestPermission();
    if (permissao !== 'granted') { avisar('Sem permissão, o celular não recebe avisos.'); pintarAvisos(); return; }
    const registro = await navigator.serviceWorker.ready;
    const token = await firebase.messaging().getToken({
      vapidKey: estado.config.vapidKey, serviceWorkerRegistration: registro
    });
    if (!token) throw new Error('o Firebase não devolveu o token');
    const id = (await sha256(token)).slice(0, 24);
    await db.ref('farmacia/notificacoes/' + id).set({
      token, em: agora(), operador: estado.operador || '', aparelho: navigator.userAgent.slice(0, 120)
    });
    localStorage.setItem(CHAVE_AVISO_LOCAL, agora());
    avisar('Avisos ligados. Use "Mandar um aviso de teste" para conferir.');
  } catch (e) {
    avisar('Não consegui ligar os avisos: ' + (e.message || e));
  }
  pintarAvisos();
}

function pintarServidor() {
  pintarAvisos();
  pintarFerramentas();
  pintarRelatorio();
  pintarAgenteParado();
  pintarPonteiroSugerido();
  pintarEscrita();
  pintarAgente();
}

/* ============================================================
   12. ACEITES
   ============================================================ */
function datasDeEnvio() {
  const datas = new Set(Object.keys(estado.aceites || {}));
  // envio.data e o ULTIMO_ENVIO_SNGPC do Digifarma, que e o FIM do periodo,
  // nao o dia da transmissao (20/10: periodo 17 a 18/10 transmitido em 19/10
  // virou uma linha "Envio de 18/10" que nunca existiu). Com XML arquivado,
  // a data do envio e a do arquivo, que ja entra pelos enviosConhecidos.
  const envio = estado.inventario?.envio;
  const doXml = String(envio?.arquivoXml || '').match(/^sngpc_(\d{4}-\d{2}-\d{2})/i);
  if (doXml) datas.add(doXml[1]);
  else if (envio?.data) datas.add(String(envio.data).slice(0, 10));
  lista('enviosConhecidos').forEach((d) => datas.add(String(d).slice(0, 10)));
  // envio que so a API conhece (feito em outro computador, ou antes do
  // agente arquivar): entra pela data em que a ANVISA recebeu
  // (so se nenhuma linha que ja existe casou com ele pelo arquivo ou periodo,
  // senao o mesmo envio apareceria duas vezes)
  const jaCasados = new Set([...datas].map((d) => envioDaApi(d)).filter(Boolean));
  comoLista(estado.inventario?.apiSngpc?.envios).forEach((e) => {
    if (e.transmissao && !jaCasados.has(e)) datas.add(String(e.transmissao).slice(0, 10));
  });
  return [...datas].filter(Boolean).sort().reverse();
}

/* O arquivo que o Digifarma grava quando nao recebeu nada: so os rotulos
   ("HASH:", "MSG DE RETORNO:") com valor vazio, e as datas em 30/12/1899,
   que e a data zero do Delphi. Visto com dado real em 15/10/2026, no envio
   que a ANVISA recusou: o arquivo nao trazia nem o hash nem o erro. */
function retornoSemResposta(texto) {
  const linhas = String(texto || '').split(/\r?\n/)
    .map((l) => l.trim()).filter((l) => l && !/^-+$/.test(l));
  return linhas.every((l) => {
    const m = l.match(/^[^:]+:\s*(.*)$/);
    return Boolean(m) && (m[1] === '' || /^30\/12\/1899\b/.test(m[1]));
  });
}

/* O que a ANVISA respondeu, como o Digifarma gravou em arquivo
   (VerificaXML\retorno_sngpc). O agente manda o texto (sem CPF, e-mail nem
   senha) e as linhas que falam de erro; a tela mostra como veio. */
function pintarRetornos() {
  const alvo = $('lista-retornos');
  const estadoTexto = $('retornos-estado');
  if (!alvo) return;
  alvo.innerHTML = '';
  const publicado = Array.isArray(estado.inventario?.retornoArquivos);
  const retornos = lista('retornoArquivos');
  estadoTexto.textContent = !publicado
    ? 'O agente do servidor ainda não manda as respostas. Atualize o agente na aba Servidor.'
    : (retornos.length ? 'Os arquivos de retorno mais recentes, do mais novo para o mais velho.'
      : 'Nenhum arquivo de retorno na pasta do Digifarma.');
  retornos.slice(0, 5).forEach((r, n) => {
    const temErro = (r.linhasDeErro || []).length > 0;
    const vazio = !temErro && retornoSemResposta(r.texto);
    // o arquivo do Digifarma veio vazio, mas a API pode ter a resposta do
    // envio daquele dia: e ela que vale na tarja
    const diaDoRetorno = String(r.em || '').slice(0, 10);
    const daApi = vazio ? (envioDaApi(diaDoRetorno) || envioDaApiPelaData(diaDoRetorno)) : null;
    const corpo = criar('div');
    const reenvio = reenvioAceito(daApi);
    if (daApi) corpo.appendChild(linhaDaApi(daApi));
    if (reenvio) {
      const nota = criar('p', 'sublinha');
      nota.textContent = 'O período foi reenviado em ' + dataHora(reenvio.transmissao)
        + ' e aceito pela ANVISA. Esta recusa já está resolvida.';
      corpo.appendChild(nota);
    }
    if (vazio && !daApi) {
      const nota = criar('p', 'motivo');
      nota.textContent = 'O Digifarma gravou este arquivo sem a resposta da ANVISA: hash e mensagem '
        + 'em branco, e 30/12/1899 é a data zero do Digifarma (data vazia). Não quer dizer que o envio '
        + 'foi aceito. Confira no site da ANVISA, em Relatório Status de Transmissão, e marque o '
        + 'envio abaixo; se foi recusado, cole o erro na marcação.';
      corpo.appendChild(nota);
    }
    if (temErro) {
      const nota = criar('p', 'motivo');
      nota.textContent = 'Linhas com erro: ' + r.linhasDeErro.join(' | ');
      corpo.appendChild(nota);
    }
    const pre = criar('pre', 'texto-retorno');
    pre.textContent = (r.texto || '(arquivo vazio)') + (r.cortado ? '\n(... cortado)' : '');
    corpo.appendChild(pre);
    alvo.appendChild(linha({
      chave: 'retorno:' + (r.arquivo || n),
      titulo: 'Resposta de ' + dataHora(r.em),
      meta: [r.arquivo],
      tarja: [temErro ? 'Tem erro — abra para ver'
        : reenvio ? 'Recusado, mas reenviado e aceito em ' + dataBR(String(reenvio.transmissao).slice(0, 10))
        : (daApi ? TARJA_DA_API[daApi.situacao] || 'Arquivo vazio — veja a resposta da API'
          : (vazio ? 'Vazio — sem resposta da ANVISA' : 'Sem erro aparente')), ''],
      tarjaClasse: temErro ? 'falta'
        : reenvio ? 'ok'
        : (daApi ? ({ validado: 'ok', com_erro: 'falta' }[daApi.situacao] || 'sobra')
          : (vazio ? 'sobra' : 'ok')),
      detalhe: corpo
    }));
  });
}

/* O que a API oficial do SNGPC respondeu de cada envio, consultado pelo
   agente de hora em hora (farmacia/inventario/apiSngpc). Casa pelo arquivo
   arquivado e, na falta dele, pelo periodo. A marcacao a mao continua sendo
   a da farmacia: a API so diz o que a ANVISA tem. */
const SITUACAO_API = {
  validado: ['Validado sem erro pela ANVISA', 'estado-aceito'],
  com_erro: ['Validado COM erro pela ANVISA — veja a mensagem no site', 'estado-recusado'],
  processando: ['Recebido, a ANVISA ainda não validou', 'estado-pendente']
};

function envioDaApi(data) {
  const envios = comoLista(estado.inventario?.apiSngpc?.envios);
  const periodo = estado.inventario?.periodosDeEnvio?.[data];
  // dois envios do mesmo arquivo/dia (reenvio, ou servidor e caixa): vale o
  // pior, para um recusado nunca aparecer como aceito
  const doArquivo = piorEnvio(envios.filter((e) => e.arquivo === data));
  if (doArquivo || !periodo) return doArquivo || null;
  // pelo periodo, so entre os que nao tem arquivo, e o mais recente: num
  // reenvio do mesmo periodo (erro, depois ok) vale a ultima resposta
  const mesmos = envios.filter((e) => !e.arquivo && e.de
    && e.de === String(periodo.de || '').slice(0, 10)
    && e.ate === String(periodo.ate || '').slice(0, 10));
  mesmos.sort((x, y) => String(y.transmissao || '').localeCompare(String(x.transmissao || '')));
  return mesmos[0] || null;
}

/* Sem arquivo e sem periodo: a data do envio e a data em que a ANVISA
   recebeu. E o caso dos envios colados do Relatorio Status de Transmissao. */
function envioDaApiPelaData(data) {
  // linha com periodo conhecido casa pelo periodo (envioDaApi), nunca por aqui:
  // outro envio recebido no mesmo dia pode ser de outro periodo
  if (estado.inventario?.periodosDeEnvio?.[data]) return null;
  return piorEnvio(comoLista(estado.inventario?.apiSngpc?.envios)
    .filter((e) => !e.arquivo && String(e.transmissao || '').slice(0, 10) === data));
}

const GRAVIDADE_API = { com_erro: 3, processando: 2, validado: 1 };
function piorEnvio(lista) {
  if (!lista.length) return null;
  return [...lista].sort((x, y) => (GRAVIDADE_API[y.situacao] || 0) - (GRAVIDADE_API[x.situacao] || 0)
    || String(y.transmissao || '').localeCompare(String(x.transmissao || '')))[0];
}

const ESTADO_DA_API = { validado: 'aceito', com_erro: 'recusado' };
const TARJA_DA_API = {
  validado: 'Arquivo vazio, mas a API diz: ACEITO',
  com_erro: 'Arquivo vazio, mas a API diz: RECUSADO',
  processando: 'Arquivo vazio; a ANVISA ainda não validou'
};

/* Envio recusado cujo periodo subiu de novo depois e foi aceito: a recusa
   ja esta resolvida. 20/10: o envio recebido em 14/10 (periodo 13/10) foi
   recusado e o de 15/10 (13 a 14/10) aceito, e a tela seguia mostrando o
   14/10 em vermelho como se faltasse fazer algo. */
function reenvioAceito(e) {
  if (!e || e.situacao !== 'com_erro' || !e.de) return null;
  const ate = e.ate || e.de;
  return comoLista(estado.inventario?.apiSngpc?.envios)
    .filter((v) => v.situacao === 'validado' && v.de && v.de <= e.de && (v.ate || v.de) >= ate
      && String(v.transmissao || '') > String(e.transmissao || ''))
    .sort((x, y) => String(x.transmissao || '').localeCompare(String(y.transmissao || '')))[0] || null;
}

function linhaDaApi(e) {
  const p = criar('p', 'sublinha');
  p.style.margin = '2px 0 0';
  const [texto] = SITUACAO_API[e.situacao] || ['Situação desconhecida na API'];
  p.textContent = texto
    + (e.validacao ? ' em ' + dataHora(e.validacao) : '')
    + (e.de ? ' · período ' + dataBR(e.de) + (e.ate && e.ate !== e.de ? ' a ' + dataBR(e.ate) : '') : '');
  return p;
}

function pintarResumoApi() {
  const api = estado.inventario?.apiSngpc;
  const p = $('aceites-api');
  if (!p) return;
  if (!api || !api.consultadoEm) { p.hidden = true; return; }
  p.textContent = 'API da ANVISA consultada pelo agente em ' + dataHora(api.consultadoEm)
    + (api.erro ? ' — ' + api.erro + '.' : '.')
    + (api.formulaDoHash ? '' : ' O Digifarma só guarda o último envio: para os outros, toque em '
      + '"Colar relatório da ANVISA".');
  p.hidden = false;
}

/* O Digifarma so guarda o hash do ultimo envio; o Relatorio Status de
   Transmissao do site mostra o de todos. Colado aqui, o agente consulta cada
   um na API oficial e os Aceites se preenchem. Os hashes passam pelo pedido
   e o agente os apaga dali na primeira passagem. */
function hashesDoTexto(t) {
  // sem lookbehind: Safari anterior ao 16.4 nao carrega o app.js inteiro
  return [...new Set((String(t || '').match(/[0-9a-f]+/gi) || [])
    .filter((h) => h.length === 32).map((h) => h.toUpperCase()))];
}

function colarRelatorioAnvisa() {
  const corpo = criar('div');
  const p = criar('p', 'sublinha');
  p.textContent = 'No site do SNGPC, abra o Relatório Status de Transmissão, selecione a página '
    + 'toda, copie e cole aqui. O agente consulta cada envio na ANVISA e marca os Aceites.';
  const campo = criar('textarea', 'busca');
  campo.rows = 6;
  campo.placeholder = 'Cole aqui o relatório (ou só os códigos de Hash Identificação)';
  campo.setAttribute('aria-label', 'Relatório Status de Transmissão colado');
  const conta = criar('p', 'sublinha');
  campo.oninput = () => { conta.textContent = hashesDoTexto(campo.value).length + ' envio(s) encontrado(s)'; };
  corpo.append(p, campo, conta);
  abrirModal({
    titulo: 'Colar relatório da ANVISA',
    corpo,
    acoes: [
      { texto: 'Cancelar', aoClicar: fecharModal },
      { texto: 'Enviar', estilo: 'botao-principal', aoClicar: () => {
        const hashes = hashesDoTexto(campo.value);
        if (!hashes.length) { avisar('Nenhum código de Hash Identificação no texto colado.'); return; }
        fecharModal();
        gravarPedido({
          acao: 'hashes_anvisa', texto: hashes.slice(0, 40).join(' '),
          pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
        }).then((ok) => {
          if (ok) avisar((hashes.length > 40
            ? 'Mandei os 40 primeiros de ' + hashes.length + ' (os mais recentes do relatório). '
            : hashes.length + ' envio(s) enviado(s) ao agente. ') + 'Em até 5 minutos os Aceites se atualizam.');
        })
          .catch((e) => avisar('O Firebase recusou o pedido: ' + (e.message || e)));
      } }
    ]
  });
}

function pintarAceites() {
  pintarRetornos();
  pintarResumoApi();
  const alvo = $('lista-aceites');
  alvo.innerHTML = '';
  const colar = criar('button', 'botao botao-secundario');
  colar.textContent = 'Colar relatório da ANVISA';
  colar.onclick = colarRelatorioAnvisa;
  alvo.appendChild(colar);
  const datas = datasDeEnvio();
  $('aceites-vazio').hidden = datas.length > 0;

  datas.forEach((data) => {
    const a = estado.aceites?.[data] || {};
    const daApi = envioDaApi(data) || envioDaApiPelaData(data);
    // a marcacao a mao manda; sem ela, vale o que a ANVISA respondeu na API
    const pelaApi = !a.status && daApi && ESTADO_DA_API[daApi.situacao];
    const estadoAtual = a.status || pelaApi || 'pendente';
    const el = criar('div', 'aceite');

    const esquerda = criar('div');
    const d = criar('p', 'aceite-data');
    d.textContent = 'Envio de ' + dataBR(data);
    esquerda.appendChild(d);
    const sub = criar('p', 'sublinha');
    sub.style.margin = '2px 0 0';
    sub.textContent = a.por ? `${estadoAtual === 'aceito' ? 'Aceite' : 'Recusa'} marcada por ${a.por} em ${dataHora(a.em)}`
      : (pelaApi ? 'Pela API da ANVISA, sem ninguém marcar' : 'Ainda não conferido no site da ANVISA');
    esquerda.appendChild(sub);
    // marcacao a mao que discorda da ANVISA: a mao continua mandando, mas
    // nao pode passar calada (17/10: envio de 14/10 marcado aceito, API recusado)
    const daApiEstado = daApi && ESTADO_DA_API[daApi.situacao];
    if (a.status && daApiEstado && daApiEstado !== a.status) {
      const conflito = criar('p', 'motivo');
      conflito.textContent = 'Atenção: marcado à mão como ' + a.status.toUpperCase()
        + ', mas a ANVISA respondeu ' + daApiEstado.toUpperCase() + '. Confira no site e corrija a marcação.';
      esquerda.appendChild(conflito);
    }
    if (estadoAtual === 'recusado' && a.erro) {
      const erro = criar('p', 'motivo');
      erro.textContent = 'Erro da ANVISA: ' + a.erro;
      esquerda.appendChild(erro);
    }
    if (daApi) esquerda.appendChild(linhaDaApi(daApi));
    const reenvio = reenvioAceito(daApi);
    if (reenvio && estadoAtual === 'recusado') {
      const r = criar('p', 'sublinha');
      r.style.margin = '2px 0 0';
      r.textContent = 'Reenviado em ' + dataHora(reenvio.transmissao) + ' e aceito: recusa já resolvida.';
      esquerda.appendChild(r);
    }
    el.appendChild(esquerda);

    const direita = criar('div');
    direita.style.display = 'flex';
    direita.style.gap = '8px';
    direita.style.alignItems = 'center';
    direita.style.flexWrap = 'wrap';

    const selo = criar('span', 'estado estado-' + estadoAtual);
    selo.textContent = { aceito: 'Aceito', recusado: 'Recusado', pendente: 'Pendente' }[estadoAtual];
    direita.appendChild(selo);

    if (estadoAtual !== 'aceito') {
      const ok = criar('button', 'botao botao-secundario');
      ok.textContent = 'Marcar aceito';
      ok.onclick = () => marcarAceite(data, 'aceito');
      direita.appendChild(ok);
    }
    if (estadoAtual !== 'recusado') {
      const nao = criar('button', 'botao botao-fantasma');
      nao.textContent = 'Marcar recusado';
      nao.onclick = () => marcarAceite(data, 'recusado');
      direita.appendChild(nao);
    } else {
      const editar = criar('button', 'botao botao-fantasma');
      editar.textContent = a.erro ? 'Editar erro' : 'Anotar erro';
      editar.onclick = () => marcarAceite(data, 'recusado');
      direita.appendChild(editar);
    }
    el.appendChild(direita);
    alvo.appendChild(el);
  });
}

async function marcarAceite(data, status) {
  if (status === 'recusado') { pedirRecusa(data); return; }
  const texto = `Confirma que o envio de ${dataBR(data)} aparece como aceito no site da ANVISA?`;
  if (!(await confirmar('Marcar ' + status, texto, 'Marcar', 'botao-principal'))) return;
  gravarAceite(data, { status, por: estado.operador, em: agora() });
}

/* Mesmo limite das regras do Firebase (farmacia/aceites/$data/erro). */
const LIMITE_ERRO_ACEITE = 2000;

/* A recusa pede o erro que o site da ANVISA mostrou: o arquivo de retorno
   do Digifarma vem vazio, e sem isto o "por que" da recusa se perdia. */
function pedirRecusa(data) {
  const anterior = estado.aceites?.[data]?.erro || '';
  const corpo = criar('div');
  const p = criar('p', 'sublinha');
  p.textContent = `Envio de ${dataBR(data)} recusado. Cole o erro que aparece no site da ANVISA `
    + '(Relatório Status de Transmissão). Pode deixar em branco.';
  const campo = criar('textarea', 'busca');
  campo.rows = 5;
  campo.maxLength = LIMITE_ERRO_ACEITE;
  campo.placeholder = 'Ex.: A quantidade vendida (1) do produto ... do lote ... é maior que a quantidade em estoque.';
  campo.setAttribute('aria-label', 'Erro que a ANVISA mostrou');
  campo.value = anterior;
  corpo.append(p, campo);
  abrirModal({
    titulo: 'Marcar recusado',
    corpo,
    acoes: [
      { texto: 'Cancelar', aoClicar: fecharModal },
      { texto: 'Marcar recusado', estilo: 'botao-perigo', aoClicar: () => {
        const erro = campo.value.trim().slice(0, LIMITE_ERRO_ACEITE);
        fecharModal();
        const registro = { status: 'recusado', por: estado.operador, em: agora() };
        if (erro) registro.erro = erro;
        gravarAceite(data, registro);
      } }
    ]
  });
}

async function gravarAceite(data, registro) {
  try {
    await db.ref('farmacia/aceites/' + data).set(registro);
    avisar('Envio de ' + dataBR(data) + ' marcado como ' + registro.status + '.');
  } catch (e) {
    // Regra velha no Firebase recusa o campo "erro" até o servidor publicar
    // as novas, o que acontece no botão Atualizar o agente.
    avisar(registro.erro
      ? 'O Firebase recusou a marcação com o erro. Na aba Servidor, toque em Atualizar o agente '
        + '(ele publica as regras novas) e tente de novo.'
      : 'O Firebase recusou: ' + (e.message || e));
  }
}

/* ============================================================
   13. PWA
   ============================================================ */
/* Versao nova se instala sozinha. O sw.js e cache-first: sem isto, o
   celular abria a copia antiga ate alguem fechar e abrir o app duas vezes,
   e a tela nova de um conserto simplesmente nao aparecia. Agora, a cada
   abertura e a cada volta ao app, ele pergunta se ha versao nova; o sw
   novo assume (skipWaiting + clients.claim) e a pagina recarrega uma vez.
   Com um modal aberto, espera ele fechar para nao perder o que se digitava. */
let recarregarAoFecharModal = false;

function recarregarParaVersaoNova() {
  if (!$('modal').hidden) { recarregarAoFecharModal = true; return; }
  window.location.reload();
}

// Em http:// sem ser localhost (o IP da rede da loja) a propriedade existe
// e vem vazia: o navegador so libera service worker em origem segura.
if (navigator.serviceWorker) {
  // sem controlador antes = primeira instalacao, nao e versao nova
  const tinhaVersao = Boolean(navigator.serviceWorker.controller);
  let recarregou = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!tinhaVersao || recarregou) return;
    recarregou = true;
    recarregarParaVersaoNova();
  });
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').then((registro) => {
      const procurar = () => registro.update().catch(() => {});
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') procurar();
      });
      setInterval(procurar, 60 * 60 * 1000);
    }).catch((e) => console.warn('Service worker não registrado:', e));
  });
}
window.addEventListener('offline', () => {
  $('barra-estado').textContent = 'Sem internet — os números na tela são os últimos que chegaram.';
  $('barra-estado').dataset.origem = 'rede';
  $('barra-estado').hidden = false;
});
window.addEventListener('online', () => {
  $('barra-estado').hidden = true;
  $('barra-estado').dataset.origem = '';
  // voltar a internet nao torna o dado recente: se estava velho, continua.
  avisarDadoVelho();
});

/* ============================================================
   AVISO DE file://
   ============================================================
   Aberto por duplo clique (file://), o navegador bloqueia
   camera, service worker e o login do Firebase. Precisa ser
   servido por http(s) — GitHub Pages ou um servidor local. */
if (location.protocol === 'file:') {
  const barra = document.getElementById('barra-estado');
  const texto = 'Esta página foi aberta direto do arquivo (file://). '
    + 'Nesse modo o navegador bloqueia o login, a câmera e o funcionamento offline. '
    + 'Publique no GitHub Pages ou rode um servidor local na pasta: python -m http.server 8000';
  if (barra) { barra.textContent = texto; barra.hidden = false; }
  const erro = document.getElementById('login-erro');
  if (erro) { erro.textContent = texto; erro.hidden = false; }
}

/* exposto para o teste de fumaça */
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { normalizar, combina, dataBR, estado, pintarPonteiroSugerido, vendasDeHoje,
    pintarComando, pintarRelatorio, retornoSemResposta, detalheDoSaldo, pintarConfiancaDoSaldo, gravarPedido, pintarSaldo, envioDaApi, linhaDaApi, textoDaAtualizacao, textoXmlRede, hashesDoTexto, envioDaApiPelaData, reenvioAceito, pintarAceites, datasDeEnvio, pintarRetornos, chaveDoPedido, envioDaApi, avisarDadoVelho, pintarRelatorio, comoLista, datasBR, temSaldo, doGrupo, html };
}
