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
  relatorios: {},       // farmacia/relatorios
  relatorioPedido: null,
  abertos: new Set()
};

/* ============================================================
   3. UTILIDADES
   ============================================================ */
const $ = (id) => document.getElementById(id);
const criar = (t, c) => { const e = document.createElement(t); if (c) e.className = c; return e; };
const esc = (s) => String(s ?? '');
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
  fecharModalAtual = () => { $('modal').hidden = true; fecharModalAtual = null; };
  const primeiro = alvo.querySelector('input, select, textarea');
  if (primeiro) setTimeout(() => primeiro.focus(), 60);
}

function fecharModal() { fecharModalAtual?.(); }

function confirmar(titulo, texto, textoOk = 'Confirmar', estilo = 'botao-principal') {
  return new Promise((resolve) => {
    abrirModal({
      titulo,
      corpo: `<p class="sublinha">${esc(texto)}</p>`,
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

function ligarEscutas() {
  if (escutas.length) return;
  escutar('farmacia/inventario', (v) => { estado.inventario = v || {}; pintar(); });
  escutar('farmacia/aceites', (v) => { estado.aceites = v || {}; if (estado.vista === 'aceites') pintarAceites(); });
  escutar('farmacia/comando', (v) => { estado.comando = v; pintarComando(); });
  escutar('farmacia/config', (v) => { estado.config = v || {}; });
  escutar('farmacia/relatorios', (v) => {
    estado.relatorios = v || {};
    if (estado.vista === 'servidor') pintarRelatorio();
  });
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
async function pedirAoAgente(acao, rotulo) {
  await db.ref('farmacia/comando').set({
    acao,                    // 'sincronizar_vendas' | 'atualizar_envio'
    pedidoEm: agora(),
    pedidoPor: estado.operador,
    estado: 'pendente'
  });
  avisar(rotulo + ' pedido. O agente atende na próxima passagem dele.');
}

$('btn-sincronizar').onclick = () => pedirAoAgente('sincronizar_vendas', 'Sincronizar vendas');
$('btn-atualizar-envio').onclick = () => pedirAoAgente('atualizar_envio', 'Atualizar envio');

function pintarComando() {
  const barra = $('fila-comando');
  const c = estado.comando;
  if (!c || c.estado === 'concluido') {
    if (c?.estado === 'concluido' && c.concluidoEm) {
      barra.textContent = `Último pedido (${c.acao}) atendido em ${dataHora(c.concluidoEm)}.`;
      barra.hidden = false;
    } else {
      barra.hidden = true;
    }
    return;
  }
  if (c.estado === 'erro') {
    barra.textContent = `O agente não conseguiu atender “${c.acao}”: ${c.mensagem || 'sem detalhe'}.`;
  } else {
    barra.textContent = `Pedido “${c.acao}” na fila desde ${dataHora(c.pedidoEm)}`
      + (estado.inventario?.vistoEm ? ` — o agente passou por aqui ${dataHora(estado.inventario.vistoEm)}.` : '.');
  }
  barra.hidden = false;
}

/* ============================================================
   10. NAVEGAÇÃO
   ============================================================ */
function irPara(vista) {
  estado.vista = vista;
  document.querySelectorAll('.nav-item').forEach((x) => x.classList.toggle('nav-ativo', x.dataset.vista === vista));
  document.querySelectorAll('.vista').forEach((v) => { v.hidden = v.id !== 'v-' + vista; });
  pintar();
}
document.querySelectorAll('.nav-item').forEach((b) => { b.onclick = () => irPara(b.dataset.vista); });
document.querySelectorAll('[data-ir]').forEach((b) => { b.onclick = () => irPara(b.dataset.ir); });
$('busca-saldo').oninput = (e) => { estado.buscaSaldo = e.target.value; pintarSaldo(); };
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
  pintarPendentes();
  avisarSobreAnvisa();
  if (estado.vista === 'saldo') pintarSaldo();
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

function avisarSobreAnvisa() {
  const a = estado.inventario?.anvisa;
  const barra = $('barra-estado');
  if (!a || !a.precisaLogin) return;
  const dias = a.diasSemSincronizar;
  barra.textContent = dias === null || dias === undefined
    ? 'O inventário da ANVISA nunca foi baixado. Abra o Anvisa.exe no servidor e faça o login no site do SNGPC.'
    : `O inventário da ANVISA está com ${dias} dia(s). Abra o Anvisa.exe no servidor e faça o login — ele para na tela de login e não anda sozinho.`;
  barra.hidden = false;
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
  negativo: ['Saldo negativo no Digifarma', 'Lote com saldo abaixo de zero. Isso e erro de escrituracao, nao de prateleira.'],
  lote_em_dois_ms: ['Mesmo lote em dois registros M.S.', 'Lote e numeracao de fabricante: dois fabricantes podem usar o mesmo numero. Confira o fabricante na caixa antes de mexer em cadastro.'],
  so_na_anvisa: ['So aparece na ANVISA', 'A ANVISA tem saldo deste lote e o Digifarma nao o conhece.'],
  quantidade: ['Quantidade diferente', 'Os dois lados conhecem o lote, com saldos diferentes.'],
  anvisa_zerada_lote: ['Lote zerado na ANVISA', 'O M.S. esta no inventario, este lote nao. Costuma ser entrada ainda nao transmitida.'],
  anvisa_zerada_produto: ['Produto zerado na ANVISA', 'O M.S. inteiro esta fora do inventario da ANVISA.'],
  sem_ms: ['Produto sem registro M.S.', 'Sem M.S. cadastrado nao da para comparar com a ANVISA.']
};
const ORDEM_MOTIVO = ['negativo', 'lote_em_dois_ms', 'so_na_anvisa', 'quantidade',
                      'anvisa_zerada_lote', 'anvisa_zerada_produto', 'sem_ms'];

/* Por que a comparacao de saldo pode nao valer. A chave vem do agente;
   a frase e daqui, porque quem escreve frase e a tela. */
const MOTIVO_CONFIANCA = {
  sem_inventario: 'O inventario da ANVISA nunca foi baixado, entao nao ha com o que comparar.',
  foto_anterior_ao_envio: 'O inventario da ANVISA e anterior ao ultimo envio. O que subiu nesse meio ja passou do ponteiro e nao entra em "falta transmitir" — fica contado em lugar nenhum e aparece como sobra.',
  lote_recusado: 'Um lote foi recusado pela ANVISA. A recusa derruba o envio inteiro, mas o ponteiro do Digifarma andou assim mesmo: ele considera transmitido o que a ANVISA nao registrou.',
  pendente_sem_lote: 'Ha movimento pendente sem numero de lote. Sem lote ele nao soma a lote nenhum e some da conta.',
  pendente_sem_casar: 'Ha movimento pendente com M.S. ou lote grafado diferente do cadastro, que nao casou com nenhum lote dos dois lados.'
};

function pintarConfiancaDoSaldo() {
  const barra = $('saldo-confianca');
  const foto = $('saldo-foto');
  const c = estado.inventario?.inventario?.confianca;
  const inv = estado.inventario?.inventario || {};

  foto.hidden = !inv.data;
  if (inv.data) {
    foto.textContent = 'O inventario da ANVISA e uma foto, de '
      + dataBR(inv.data) + '. A conta e: essa foto mais o que ainda nao subiu.';
  }

  if (!c || c.confiavel) { barra.hidden = true; return; }
  const frases = (c.motivos || []).map((m) => MOTIVO_CONFIANCA[m] || m);
  barra.innerHTML = '<strong>Estes numeros podem nao ser divergencia de estoque.</strong><br>'
    + frases.map(esc).join('<br>');
  barra.hidden = false;
}

function detalheDoSaldo(i, dif) {
  const pares = [
    ['Código', i.codigo],
    ['Saldo Digifarma', i.saldoDigifarma],
    ['Saldo do inventário SNGPC', i.saldoSngpc],
    ['Diferença', (dif > 0 ? '+' : '') + dif],
    ['Registro M.S.', i.ms],
    ['Código de barras', i.ean],
    ['Lote', i.lote],
    ['Validade', i.validade],
    ['Classe', i.classe]
  ];
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
      ? 'Os totais do lote batem nos dois lados: a farmacia tem a quantidade certa, repartida entre os cadastros de um jeito diferente. E lancamento no cadastro errado, nao falta de mercadoria.'
      : MOTIVO_SALDO.lote_em_dois_ms[1];
  } else {
    nota.textContent = MOTIVO_SALDO[i.motivo]?.[1] || '';
  }
  if (nota.textContent) d.appendChild(nota);
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
    .filter((i) => combina(i, estado.buscaSaldo, ['descricao', 'ms', 'ean', 'lote', 'codigo']))
    .sort((a, b) => peso(a) - peso(b)
      || Math.abs(Number(b.diferenca || 0)) - Math.abs(Number(a.diferenca || 0)));
  $('saldo-vazio').hidden = itens.length > 0 || !!estado.buscaSaldo;

  itens.forEach((i, n) => {
    const dif = Number(i.diferenca || 0);
    alvo.appendChild(linha({
      chave: 'saldo:' + (i.codigo || n) + ':' + (i.lote || ''),
      titulo: i.descricao || i.codigo || '(sem descrição)',
      meta: [
        i.ms && 'M.S. ' + i.ms,
        i.ean && 'EAN ' + i.ean,
        i.lote && 'Lote ' + i.lote,
        i.validade && 'Val. ' + i.validade
      ],
      tarja: [MOTIVO_SALDO[i.motivo]?.[0] || (dif < 0 ? 'Falta no Digifarma' : 'Sobra no Digifarma'),
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
    + esc(r.porque || 'o agente não disse por quê')
    + '<br>Então a lista vazia abaixo não quer dizer que está tudo certo.';
  barra.hidden = false;
}

function detalheDoXml(c) {
  const pares = [
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
    .filter((c) => combina(c, estado.buscaXml, ['descricao', 'ms', 'lote']));
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
        c.ms && 'M.S. ' + c.ms,
        c.lote && 'Lote ' + c.lote,
        c.periodo && 'Período ' + c.periodo
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

function pintarVendas() {
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
      meta: [v.data && dataBR(v.data), v.ms && 'M.S. ' + v.ms, v.lote ? 'Lote ' + v.lote : 'Sem lote'],
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
function avisarDadoVelho() {
  const barra = $('barra-estado');
  const quando = estado.inventario?.atualizadoEm;
  const min = minutosDesde(quando);
  if (min === null || min < HORAS_ATE_VELHO * 60) return false;

  const dias = Math.floor(min / 1440);
  const idade = dias >= 1 ? dias + ' dia(s)' : Math.floor(min / 60) + ' hora(s)';
  barra.textContent = 'ATENÇÃO: estes números são de ' + dataHora(quando)
    + ' — ' + idade + ' atrás. O agente não publicou desde então, então as '
    + 'vendas e entradas desse período NÃO estão aqui. Não use para conferir '
    + 'prateleira nem para decidir transmissão.';
  barra.hidden = false;
  return true;
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
    nota.textContent = 'O ponteiro foi acertado à mão. Se o site da ANVISA não recebeu '
      + 'essas vendas, elas saem da conta e cada lote vendido aparece como divergência '
      + 'no Saldo. Desfazer só muda a conta do agente; nada é gravado no Digifarma.';
    alvo.appendChild(nota);
    const desfazer = criar('button', 'botao botao-secundario');
    desfazer.textContent = 'Desfazer o acerto';
    desfazer.onclick = async () => {
      if (!(await confirmar('Desfazer o acerto do ponteiro',
        'O agente volta a usar o ponteiro do próprio Digifarma'
        + (envio.ponteiroDoDigifarma ? ' (' + envio.ponteiroDoDigifarma + ')' : '')
        + ' e recalcula o Saldo.', 'Desfazer'))) return;
      await db.ref('farmacia/comando').set({
        acao: 'config', chave: 'transmitido_ate_venda', valor: '0',
        pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
      });
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
    await db.ref('farmacia/comando').set({
      acao: 'config', chave: 'transmitido_ate_venda', valor: String(p.corte),
      pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
    });
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
  ['atualizar_agente', 'Atualizar o agente', 'Baixa a versao mais nova do GitHub e troca, conferindo antes. E o ATUALIZAR_AGENTE.bat.'],
  ['anvisa', 'Abrir o Anvisa.exe', 'Abre o programa da ANVISA no servidor. Ele para na tela de login do SNGPC, por desenho da ANVISA.'],
  ['arrumar_tarefa_anvisa', 'Arrumar a tarefa do Anvisa', 'Reescreve a tarefa agendada AnvisaSNGPC_Login quando ela aponta para caminho errado.']
];

const RELATORIOS_SERVIDOR = [
  ['resumo', 'Resumo'], ['pendentes', 'Pendentes'], ['ponteiro', 'Ponteiro'],
  ['tarefas', 'Tarefas'], ['negativos', 'Negativos'], ['inventario', 'Inventario'],
  ['login_sngpc', 'Login SNGPC'], ['retorno_anvisa', 'Retorno ANVISA'],
  ['log_anvisa', 'Log do Anvisa'], ['colunas', 'Colunas do banco']
];

function pedirRelatorio(acao, rotulo) {
  estado.relatorioPedido = acao;
  return db.ref('farmacia/comando').set({
    acao, pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
  }).then(() => avisar(rotulo + ' pedido. O agente atende na proxima passagem dele.'));
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

  // Desligar a escrita e de mao unica: o app fecha a porta, nunca abre.
  // Ligar continua sendo ato local no servidor, que e a direcao perigosa.
  if (estado.inventario?.escrita?.ligada) {
    const b = criar('button', 'botao botao-perigo');
    b.textContent = 'Desligar a escrita agora';
    b.onclick = async () => {
      if (!(await confirmar('Desligar a escrita no Digifarma',
        'Fecha a porta que permite zerar lote negativo e gravar contagem. '
        + 'Religar so no servidor.', 'Desligar', 'botao-perigo'))) return;
      await db.ref('farmacia/comando').set({
        acao: 'config', chave: 'permitir_ajuste_estoque', valor: 'false',
        pedidoEm: agora(), pedidoPor: estado.operador, estado: 'pendente'
      });
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
}

function pintarRelatorio() {
  const bloco = $('bloco-relatorio');
  const acao = estado.relatorioPedido;
  const r = acao && estado.relatorios?.[acao];
  if (!r || !r.texto) { bloco.hidden = true; return; }
  $('relatorio-titulo').textContent = 'Resposta do servidor — ' + acao;
  $('relatorio-em').textContent = 'gerado em ' + dataHora(r.em)
    + (r.cortado ? ' · texto cortado por ser muito longo' : '');
  $('relatorio').textContent = r.texto;
  bloco.hidden = false;
}

function pintarServidor() {
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
  const envio = estado.inventario?.envio?.data;
  if (envio) datas.add(String(envio).slice(0, 10));
  lista('enviosConhecidos').forEach((d) => datas.add(String(d).slice(0, 10)));
  return [...datas].filter(Boolean).sort().reverse();
}

function pintarAceites() {
  const alvo = $('lista-aceites');
  alvo.innerHTML = '';
  const datas = datasDeEnvio();
  $('aceites-vazio').hidden = datas.length > 0;

  datas.forEach((data) => {
    const a = estado.aceites?.[data] || {};
    const estadoAtual = a.status || 'pendente';
    const el = criar('div', 'aceite');

    const esquerda = criar('div');
    const d = criar('p', 'aceite-data');
    d.textContent = 'Envio de ' + dataBR(data);
    esquerda.appendChild(d);
    const sub = criar('p', 'sublinha');
    sub.style.margin = '2px 0 0';
    sub.textContent = a.por ? `${estadoAtual === 'aceito' ? 'Aceite' : 'Recusa'} marcada por ${a.por} em ${dataHora(a.em)}` : 'Ainda não conferido no site da ANVISA';
    esquerda.appendChild(sub);
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
    }
    el.appendChild(direita);
    alvo.appendChild(el);
  });
}

async function marcarAceite(data, status) {
  const texto = status === 'aceito'
    ? `Confirma que o envio de ${dataBR(data)} aparece como aceito no site da ANVISA?`
    : `Confirma que o envio de ${dataBR(data)} foi recusado? Vale anotar a recusa para conferir as vendas do período.`;
  if (!(await confirmar('Marcar ' + status, texto, 'Marcar', status === 'aceito' ? 'botao-principal' : 'botao-perigo'))) return;
  await db.ref('farmacia/aceites/' + data).set({ status, por: estado.operador, em: agora() });
  avisar('Envio de ' + dataBR(data) + ' marcado como ' + status + '.');
}

/* ============================================================
   13. PWA
   ============================================================ */
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch((e) => console.warn('Service worker não registrado:', e));
  });
}
window.addEventListener('offline', () => {
  $('barra-estado').textContent = 'Sem internet — os números na tela são os últimos que chegaram.';
  $('barra-estado').hidden = false;
});
window.addEventListener('online', () => {
  $('barra-estado').hidden = true;
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
  const texto = 'Esta pagina foi aberta direto do arquivo (file://). '
    + 'Nesse modo o navegador bloqueia o login, a camera e o funcionamento offline. '
    + 'Publique no GitHub Pages ou rode um servidor local na pasta: python -m http.server 8000';
  if (barra) { barra.textContent = texto; barra.hidden = false; }
  const erro = document.getElementById('login-erro');
  if (erro) { erro.textContent = texto; erro.hidden = false; }
}

/* exposto para o teste de fumaça */
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { normalizar, combina, dataBR, estado, pintarPonteiroSugerido };
}
