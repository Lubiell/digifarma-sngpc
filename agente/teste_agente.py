# -*- coding: utf-8 -*-
"""
teste_agente.py — roda o agente com um banco simulado.

Não abre o Digifarma nem escreve no Firebase: substitui a função
consultar() por respostas fixas e confere o que sai. Serve para
validar uma alteração no agente_auto.py antes de levar ao servidor.

    python teste_agente.py
"""

import contextlib
import datetime
import io
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agente_auto as ag  # noqa: E402
import mapa_xml           # noqa: E402

XML_EXEMPLO = """<?xml version="1.0" encoding="UTF-8"?>
<mensagemSNGPC xmlns="urn:sngpc:anvisa">
 <transacao><medicamentos>
  <medicamento>
   <registroMSMedicamento>1.0033.0122.001-9</registroMSMedicamento>
   <descricaoMedicamento>CLONAZEPAM 2MG CX 30 CP</descricaoMedicamento>
   <numeroLoteMedicamento>L2345A</numeroLoteMedicamento>
   <quantidadeMedicamento>30</quantidadeMedicamento>
   <dataVenda>2026-08-09</dataVenda>
  </medicamento>
  <medicamento>
   <registroMSMedicamento>1.0033.0122.001-9</registroMSMedicamento>
   <descricaoMedicamento>CLONAZEPAM 2MG CX 30 CP</descricaoMedicamento>
   <numeroLoteMedicamento>L2345A</numeroLoteMedicamento>
   <quantidadeMedicamento>30</quantidadeMedicamento>
   <dataVenda>2026-08-09</dataVenda>
  </medicamento>
  <medicamento>
   <registroMSMedicamento>1.4444.0001.002-3</registroMSMedicamento>
   <descricaoMedicamento>ALPRAZOLAM 1MG CX 20 CP</descricaoMedicamento>
   <numeroLoteMedicamento>b77z</numeroLoteMedicamento>
   <quantidadeMedicamento>20</quantidadeMedicamento>
   <dataVenda>2026-08-09</dataVenda>
  </medicamento>
 </medicamentos></transacao>
</mensagemSNGPC>
"""

RESPOSTAS = {
    'ponteiros': [{'ULT_SAIDA_VENDA_NOTA_ID': 8821, 'ULT_ENTRADA_CAB_NOTA_ID': 3310,
                   'ULT_SAIDA_PERDA_ID': 0, 'ULT_SAIDA_TRANSFERENCIA_ID': 0,
                   'ULTIMO_ENVIO_SNGPC': datetime.date(2026, 8, 5),
                   'ENVIO_API': 'N', 'CNPJ': '00000000000000'}],
    'saidas_pendentes': [
        {'VENDA_NOTA_ID': 8830, 'DATA': datetime.date(2026, 8, 6), 'PRODUTO': 'CLONAZEPAM',
         'REGISTRO_MS': '1003301220019', 'COD_BARRAS': '789', 'NUM_LOTE': 'L2345A', 'QUANTIDADE': 30},
    ],
    'entradas_pendentes': [
        {'CAB_NOTA_ID': 3315, 'NOTA_FISCAL': '206800', 'DATA_RECEBIMENTO': datetime.date(2026, 8, 6),
         'PRODUTO': 'ALPRAZOLAM', 'REGISTRO_MS': '1444400010023', 'COD_BARRAS': '790',
         'NUM_LOTE': 'B77Z', 'QUANTIDADE': 20},
    ],
    'perdas_pendentes': [],
    'transferencias_pendentes': [],
    'saidas_periodo': [
        # bate com o XML real: 2 vendas do dia 04/08
        {'VENDA': 8801, 'DATA': datetime.date(2026, 8, 4), 'PRODUTO': 'ALPRAZOLAM',
         'REGISTRO_MS': '1023506630204', 'NUM_LOTE': '5F9779', 'QUANTIDADE': 1},
        # esta saiu no banco e NÃO foi para o XML
        {'VENDA': 8802, 'DATA': datetime.date(2026, 8, 4), 'PRODUTO': 'RIVOTRIL',
         'REGISTRO_MS': '1999900090011', 'NUM_LOTE': 'Z9', 'QUANTIDADE': 10},
    ],
    'vendas_problema': [
        {'VENDA': 8802, 'DATA': datetime.date(2026, 8, 4), 'PRODUTO': 'RIVOTRIL',
         'REGISTRO_MS': '1999900090011', 'QUANTIDADE': 10, 'NUM_LOTE': None,
         'RECEITA': None, 'VENDEDOR': 'BALCAO 2'},
    ],
    'inventario_sngpc': [
        {'REGISTRO_MS': '1023506630204', 'MEDICAMENTO': 'ALPRAZOLAM', 'LOTE': '5F9779',
         'QUANTIDADE': 8, 'DATA_ATUALIZACAO': '2026-08-05'},
        {'REGISTRO_MS': '1057306610050', 'MEDICAMENTO': 'ARIPIPRAZOL', 'LOTE': '2604608',
         'QUANTIDADE': 2, 'DATA_ATUALIZACAO': '2026-08-05'},
    ],
    'saldo_digifarma': [
        # 5 no Digifarma contra 8 na ANVISA -> falta 3
        {'PRODUTO_ID': 100, 'PRODUTO': 'ALPRAZOLAM', 'REGISTRO_MS': '1023506630204',
         'COD_BARRAS': '789', 'NUM_LOTE': '5F9779', 'LOTE_VENCIMENTO': datetime.date(2027, 9, 30), 'SALDO': 5},
        # bate certinho
        {'PRODUTO_ID': 200, 'PRODUTO': 'ARIPIPRAZOL', 'REGISTRO_MS': '1057306610050',
         'COD_BARRAS': '790', 'NUM_LOTE': '2604608', 'LOTE_VENCIMENTO': datetime.date(2027, 3, 31), 'SALDO': 2},
    ],
}

falhas = []


def conferir(titulo, condicao, detalhe=''):
    if condicao:
        print('  ok    ' + titulo)
    else:
        falhas.append(titulo)
        print('  FALHA ' + titulo + ('\n        ' + str(detalhe) if detalhe else ''))


def numero_ok(item):
    """Lote cujo saldo do Digifarma é diferente da foto: nunca é o caso
    "iguais com movimento"."""
    return item.get('saldoDigifarma') != item.get('saldoSngpc')


def principal():
    print('\nagente SNGPC\n------------')

    conferir('a transmissão leva o movimento do dia anterior',
             ag.anterior('2026-08-10') == '2026-08-09')
    conferir('data em formato brasileiro', ag.br('2026-08-10') == '10/08/2026')

    # ------------------------------------------------------------
    # XML: usa o arquivo real da farmácia se estiver na pasta,
    # senão o exemplo embutido
    # ------------------------------------------------------------
    pasta = tempfile.mkdtemp()
    caminho = os.path.join(pasta, 'SNGPC.XML')
    real = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'exemplo_SNGPC.XML')
    if os.path.exists(real):
        shutil.copy(real, caminho)
    else:
        with open(caminho, 'w', encoding='utf-8') as f:
            f.write(XML_EXEMPLO)

    lido = mapa_xml.ler(caminho)
    conferir('o cabeçalho do XML dá o período exato da transmissão',
             bool(lido['cabecalho'].get('dataInicio')), lido['cabecalho'])
    conferir('entrada e venda vão para baldes separados',
             set(lido['movimentos']) <= {'entrada', 'venda', 'perda', 'transferencia', 'outro'}
             and 'venda' in lido['movimentos'], list(lido['movimentos']))
    conferir('o total conta só as vendas, não as entradas',
             lido['total'] == round(sum(i['quantidade']
                                        for i in lido['movimentos']['venda'].values()), 3))
    conferir('lote casa mesmo com caixa diferente',
             all(k[1] == k[1].upper() for k in lido['itens']))

    # ------------------------------------------------------------
    # montagem completa
    # ------------------------------------------------------------
    config = dict(ag.CONFIG_PADRAO, pasta_xml=pasta)
    por_sql = {ag.CONSULTAS[k]: v for k, v in RESPOSTAS.items() if k in ag.CONSULTAS}

    def consultar_falso(conexao, sql, parametros=()):
        if 'RDB$RELATION_FIELDS' in sql:
            return [{'CAMPO': c} for c in ('LOTE_ID', 'PRODUTO_ID', 'NUM_LOTE', 'SALDO')]
        if sql in por_sql:
            return por_sql[sql]
        # o nome pelo M.S., para a venda que só está no XML
        if 'P.REGISTRO_MS IS NOT NULL' in sql:
            return [{'REGISTRO_MS': '1.0047.0434.016-8', 'PRODUTO': 'FLUOXETINA 20MG'}]
        # saldo_digifarma tem o {SALDO} trocado antes de rodar
        if 'FROM LOTES' in sql:
            return RESPOSTAS['saldo_digifarma']
        raise AssertionError('consulta não simulada:\n' + sql[:120])

    ag.consultar = consultar_falso
    dados = ag.montar_inventario(conexao=None, config=config)
    hoje = datetime.date.today().isoformat()

    conferir('lê os ponteiros do último envio',
             dados['envio']['ULT_SAIDA_VENDA_NOTA_ID'] == 8821)
    conferir('o período sai do cabeçalho do XML, não do nome do arquivo',
             dados['envio']['movimentosDe'] == lido['cabecalho']['dataInicio'], dados['envio'])
    conferir('descobre sozinho a coluna de saldo da tabela LOTES',
             dados['inventario'].get('colunaSaldo') == 'SALDO', dados['inventario'])
    conferir('o inventário vem do INVENTARIO_SNGPC (lado ANVISA)',
             dados['inventario']['itens'] == 2, dados['inventario'])

    diferencas = {i['ms']: i['diferenca'] for i in dados['itens']}
    conferir('diferença de saldo por M.S. + lote',
             diferencas.get('1023506630204') == -3.0, diferencas)
    conferir('a sincronização roda o veredito sem quebrar nos lotes comuns',
             not any(i.get('veredito') for i in dados['itens']
                     if numero_ok(i)), [i for i in dados['itens'] if i.get('veredito')])
    conferir('lote que bate não vira divergência',
             diferencas.get('1057306610050') == 0.0, diferencas)

    conferir('vendas pendentes saem pelo ponteiro, não por data',
             dados['resumoPendentes']['vendas'] == 1, dados['resumoPendentes'])
    conferir('entradas pendentes saem pelo ponteiro',
             dados['resumoPendentes']['entradas'] == 1, dados['resumoPendentes'])

    fora = [c for c in dados.get('conferencia_xml', []) if c['situacao'] == 'fora_do_xml']
    conferir('venda que não subiu no XML vira divergência',
             any(c['ms'] == '1999900090011' for c in fora), fora)
    so_xml = {c['ms']: c['descricao'] for c in dados.get('conferencia_xml', [])
              if c['situacao'] == 'so_no_xml'}
    conferir('venda que só está no XML mostra o nome do cadastro',
             so_xml.get('1004704340168') == 'FLUOXETINA 20MG', so_xml)
    conferir('entrada do XML não é confundida com venda',
             not any(c['ms'] == '1052500680092' for c in dados.get('conferencia_xml', [])))

    conferir('venda de controlado sem receita é classificada',
             dados['vendas_problema'][0]['motivo'] == 'sem_receita')

    conferir('o XML da transmissão é arquivado em enviados\\',
             os.path.exists(os.path.join(pasta, 'enviados', 'sngpc_%s.xml' % hoje)))
    conferir('mede há quanto tempo o Anvisa.exe não conclui',
             'precisaLogin' in dados['anvisa'], dados['anvisa'])

    # --- mesmo lote em dois M.S.: o cadastro mudou depois da transmissao ---
    banco = [{'ms': '1.1213.0443.003-4', 'lote': 'AB12', 'quantidade': 2,
              'descricao': 'OLANZAPINA 10MG', 'venda': 46505}]
    xml = {('1057306420030', 'AB12'): {'ms': '1057306420030', 'lote': 'AB12',
                                       'quantidade': 2.0, 'descricao': 'OLANZAPINA 10MG'}}
    casado = mapa_xml.comparar(xml, banco)
    conferir('mesmo lote em dois M.S. vira um aviso, não duas divergências',
             len(casado) == 1 and casado[0]['situacao'] == 'ms_trocado', casado)
    conferir('o aviso de M.S. trocado diz qual é o outro M.S.',
             casado and casado[0].get('outroMs') == '1057306420030', casado)

    # quantidade diferente nao e troca de M.S.: e divergencia de verdade
    banco_dif = [dict(banco[0], quantidade=3)]
    soltas = mapa_xml.comparar(xml, banco_dif)
    conferir('quantidade diferente no mesmo lote continua divergência',
             len(soltas) == 2 and not any(c['situacao'] == 'ms_trocado' for c in soltas), soltas)

    # lote diferente nao casa, mesmo com a quantidade igual
    outro_lote = {('1057306420030', 'ZZ99'): dict(list(xml.values())[0], lote='ZZ99')}
    separadas = mapa_xml.comparar(outro_lote, banco)
    conferir('lote diferente não é casado como M.S. trocado',
             len(separadas) == 2 and not any(c['situacao'] == 'ms_trocado' for c in separadas), separadas)

    # --- o relogio da atualizacao automatica ---
    carimbo = os.path.join(os.path.dirname(os.path.abspath(ag.__file__)),
                           ag.ARQUIVO_ULTIMA_ATUALIZACAO)
    guardado = open(carimbo, encoding='utf-8').read() if os.path.exists(carimbo) else None
    try:
        if os.path.exists(carimbo):
            os.remove(carimbo)
        conferir('sem carimbo, procura atualizacao', ag.hora_da_atualizacao()[1])

        agora_txt = datetime.datetime.now().isoformat(timespec='seconds')
        open(carimbo, 'w', encoding='utf-8').write(agora_txt)
        conferir('carimbo de agora, NAO procura', not ag.hora_da_atualizacao()[1])

        velho = datetime.datetime.now() - datetime.timedelta(
            hours=ag.HORAS_ENTRE_ATUALIZACOES + 1)
        open(carimbo, 'w', encoding='utf-8').write(velho.isoformat(timespec='seconds'))
        conferir('carimbo velho, procura de novo', ag.hora_da_atualizacao()[1])

        open(carimbo, 'w', encoding='utf-8').write('isto nao e data')
        conferir('carimbo ilegivel nao trava, procura', ag.hora_da_atualizacao()[1])

        # Atualizacao que falha tem de carimbar assim mesmo: sem isso, uma
        # falha persistente vira uma tentativa de download por hora.
        if os.path.exists(carimbo):
            os.remove(carimbo)
        guardado_fn = ag.atualizar_agente
        try:
            def explodir(_config):
                raise RuntimeError('sem rede')
            ag.atualizar_agente = explodir
            ag.atualizar_sozinho({})
        finally:
            ag.atualizar_agente = guardado_fn
        conferir('atualizacao que falha ainda carimba', os.path.exists(carimbo))
        conferir('e carimbada, nao tenta de novo na volta seguinte',
                 os.path.exists(carimbo) and not ag.hora_da_atualizacao()[1])
    finally:
        if guardado is None:
            if os.path.exists(carimbo):
                os.remove(carimbo)
        else:
            open(carimbo, 'w', encoding='utf-8').write(guardado)

    # --- sugestao de ponteiro: o ultimo dia do periodo nao vale por data ---
    # Em 10/10 o envio do dia 09 saiu com o dia aberto; as vendas seguintes,
    # tambem de 09/10, nao subiram, e a sugestao por data mandou acertar.
    def dados_ponteiro(vendas, ja_na_anvisa=()):
        return {'envio': {'movimentosAte': '2026-10-09'},
                'pendentes': {'vendas': vendas},
                'inventario': {'lotesJaNaAnvisa': [list(x) for x in ja_na_anvisa]}}

    def venda(n, data, lote):
        return {'id': n, 'data': data, 'ms': '1000000000001', 'lote': lote}

    corte, _, _ = ag.corte_por_data(dados_ponteiro(
        [venda(48252, '2026-10-09', 'A'), venda(48307, '2026-10-09', 'B')]))
    conferir('venda do ultimo dia do periodo, sem lote que confirme, nao vira sugestao',
             corte is None, corte)
    corte, _, quantas = ag.corte_por_data(dados_ponteiro(
        [venda(48200, '2026-10-08', 'A'), venda(48252, '2026-10-09', 'B')]))
    conferir('venda de dia ja fechado ainda vira sugestao, so ate ela',
             corte == 48200 and quantas == 1, (corte, quantas))
    corte, _, _ = ag.corte_por_data(dados_ponteiro(
        [venda(48252, '2026-10-09', 'A'), venda(48253, '2026-10-09', 'B')],
        ja_na_anvisa=[('1000000000001', 'A')]))
    conferir('ultimo dia entra quando os lotes confirmam, e so ate onde confirmam',
             corte == 48252, corte)

    # --- vistoEm sai mesmo quando o quadro do balcao falha ---
    # Em 10/10 a gravacao em farmacia/publico falhava e levava junto o
    # carimbo de passagem: o app dizia "agente nao publicou" com ele vivo.
    gravados = []

    class RefQuadro:
        def __init__(self, caminho):
            self.caminho = caminho

        def set(self, valor):
            if self.caminho.startswith('farmacia/publico'):
                raise RuntimeError('Permission denied')
            gravados.append(self.caminho)

    class DbQuadro:
        def reference(self, caminho):
            return RefQuadro(caminho)

    nomes = ('conectar_firebird', 'fechar', 'vendas_recentes', 'vendas_sem_receita_pendentes',
             'snapshot_diagnostico', 'entradas_recentes', 'retorno_sngpc', 'mudou',
             'vendas_publicas', 'notas_publicas', 'atualizar_envios_publicos', 'registrar')
    guardadas = {n: getattr(ag, n) for n in nomes}
    try:
        ag.conectar_firebird = lambda _c: None
        ag.fechar = lambda _c: None
        ag.vendas_recentes = lambda _c: [{'venda': 1}]
        ag.vendas_sem_receita_pendentes = lambda _c, _cfg: []
        ag.snapshot_diagnostico = lambda _c: {}
        ag.entradas_recentes = lambda _c, _p, config=None: []
        ag.retorno_sngpc = lambda _c: {}
        ag.mudou = lambda _caminho, _valor: True
        ag.vendas_publicas = lambda linhas: linhas
        ag.notas_publicas = lambda e: e
        ag.atualizar_envios_publicos = lambda _db: False
        ag.registrar = lambda _t: None
        ag.publicar_vendas_recentes({}, DbQuadro())
    finally:
        for n, f in guardadas.items():
            setattr(ag, n, f)
    conferir('a passagem do agente fica registrada mesmo com o quadro do balcao falhando',
             'farmacia/inventario/vistoEm' in gravados, gravados)
    conferir('as vendas recentes continuam sendo publicadas',
             'farmacia/inventario/vendasRecentes' in gravados, gravados)

    # --- busca nos XML: acha entrada por M.S., lote escrito diferente e outro M.S. ---
    pasta_busca = tempfile.mkdtemp()
    os.makedirs(os.path.join(pasta_busca, 'enviados'))
    exemplo = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'exemplo_SNGPC.XML')
    shutil.copy(exemplo, os.path.join(pasta_busca, 'enviados', 'sngpc_2026-08-05.xml'))
    cfg_busca = dict(ag.CONFIG_PADRAO, pasta_xml=pasta_busca)

    def busca(alvo, itens=None):
        guardado_fb = ag.conectar_firebase

        class RefItens:
            def get(self):
                return itens

        class DbItens:
            def reference(self, _caminho):
                return RefItens()
        saida_busca = io.StringIO()
        try:
            ag.conectar_firebase = lambda _c: DbItens()
            with contextlib.redirect_stdout(saida_busca):
                ag.modo_buscar_xml(cfg_busca, alvo)
        finally:
            ag.conectar_firebase = guardado_fb
        return saida_busca.getvalue()

    achado = busca('1052500680092')
    conferir('busca no XML acha a entrada pelo M.S.',
             'entrada' in achado and 'CLV4N003' in achado and 'sngpc_2026-08-05.xml' in achado, achado)
    conferir('busca no XML diz quando nao acha',
             'não aparece em nenhum dos 1 XML' in busca('9999999999999'))
    auto = busca('', itens=[
        {'ms': '1052500680092', 'lote': 'CLV4N003A', 'descricao': 'TESTE', 'diferenca': 3},
        {'ms': '1999999999999', 'lote': 'BRM6N009', 'descricao': 'OUTRO', 'diferenca': -1},
        {'ms': '1052500680092', 'lote': 'XYZ', 'descricao': 'BATE', 'diferenca': 0}])
    conferir('sem alvo, procura os lotes com divergencia e aponta lote escrito diferente',
             'lote escrito diferente' in auto and 'CLV4N003' in auto, auto)
    conferir('sem alvo, aponta o mesmo lote com outro M.S.',
             'mesmo lote, OUTRO M.S.' in auto, auto)
    conferir('sem alvo, lote sem divergencia fica de fora', 'BATE' not in auto, auto)
    saida_lote = io.StringIO()
    with contextlib.redirect_stdout(saida_lote):
        ag.modo_buscar_xml(cfg_busca, '1052500680092', so_lote=True)
    conferir('lote so de digitos, vindo da investigacao, e procurado como lote',
             'lote 1052500680092' in saida_lote.getvalue()
             and 'CLV4N003' not in saida_lote.getvalue(), saida_lote.getvalue())
    conferir('a busca nos XML nao imprime CPF nem CNPJ do cabecalho',
             '00000000191' not in achado + auto, achado)
    shutil.rmtree(pasta_busca, ignore_errors=True)

    # --teste imprimia a linha inteira da tabela SNGPC - EMAIL, SENHA e CPF
    # do responsavel - na tela do INSTALAR_AGENTE.bat.
    class RefFalsa:
        def set(self, _valor):
            pass

    class DbFalso:
        def reference(self, _caminho):
            return RefFalsa()

    guardados = (ag.conectar_firebird, ag.fechar, ag.conectar_firebase, ag.consultar)
    saida = io.StringIO()
    try:
        ag.conectar_firebird = lambda _config: None
        ag.fechar = lambda _conexao: None
        ag.conectar_firebase = lambda _config: DbFalso()
        ag.consultar = lambda _conexao, _sql, _parametros=(): [{
            'ULT_SAIDA_VENDA_NOTA_ID': 8821, 'EMAIL': 'fulano@teste.invalid',
            'SENHA': 'segredo-de-teste', 'CPF_RESPONSAVEL_SNGPC': '00000000191'}]
        with contextlib.redirect_stdout(saida):
            ag.modo_teste(dict(ag.CONFIG_PADRAO))
    finally:
        ag.conectar_firebird, ag.fechar, ag.conectar_firebase, ag.consultar = guardados
    impresso = saida.getvalue()
    conferir('o --teste nao imprime senha, e-mail nem CPF da tabela SNGPC',
             not any(x in impresso for x in ('segredo-de-teste', 'fulano@teste.invalid',
                                             '00000000191')))
    conferir('o --teste ainda mostra os ponteiros', 'ULT_SAIDA_VENDA_NOTA_ID' in impresso)

    # --- foto do inventario gravada ANTES do envio da manha (10/10) ---
    dt = datetime.datetime
    xml_09 = {'cabecalho': {'dataInicio': '2026-10-09'}, 'datas': ['2026-10-09']}
    xml_10 = {'cabecalho': {'dataInicio': '2026-10-10'}, 'datas': ['2026-10-10']}
    foto_hora = dt(2026, 10, 10, 7, 18, 40)
    conferir('foto 07:18 e envio 07:21: o movimento falta desde o dia anterior ao XML',
             ag.foto_sem_o_ultimo_envio('2026-10-10', foto_hora,
                                        [(dt(2026, 10, 10, 7, 21), xml_09)]) == '2026-10-08')
    conferir('Anvisa.exe sem rodar no dia seguinte: conta desde o XML MAIS ANTIGO apos a foto',
             ag.foto_sem_o_ultimo_envio('2026-10-10', foto_hora,
                                        [(dt(2026, 10, 11, 7, 21), xml_10),
                                         (dt(2026, 10, 10, 7, 21), xml_09)]) == '2026-10-08')
    conferir('entrada com data atrasada no XML nao recua o inicio: vale o cabecalho',
             ag.foto_sem_o_ultimo_envio('2026-10-10', foto_hora, [(
                 dt(2026, 10, 10, 7, 21),
                 {'cabecalho': {'dataInicio': '2026-10-09'},
                  'datas': ['2026-10-05', '2026-10-09']})]) == '2026-10-08')
    conferir('XML gerado antes da foto: a foto ja tem o envio',
             ag.foto_sem_o_ultimo_envio('2026-10-10', foto_hora,
                                        [(dt(2026, 10, 10, 7, 10), xml_09)]) is None)
    conferir('hora do log de outro dia que nao o da foto: nao afirma nada',
             ag.foto_sem_o_ultimo_envio('2026-10-10', dt(2026, 10, 9, 16, 33, 59),
                                        [(dt(2026, 10, 10, 7, 21), xml_09)]) is None)
    conferir('sem hora da foto ou sem data no XML: nao afirma nada',
             ag.foto_sem_o_ultimo_envio('2026-10-10', None, [(dt(2026, 10, 10, 7, 21), xml_09)])
             is None and ag.foto_sem_o_ultimo_envio(
                 '2026-10-10', foto_hora, [(dt(2026, 10, 10, 7, 21), {})]) is None)

    pedidos = []
    original_desde = ag.movimento_desde_a_foto
    try:
        ag.movimento_desde_a_foto = lambda _c, desde: (pedidos.append(desde)
                                                       or {('1642500090024', '26CQ145'): 1.0})
        correcao, base = ag.correcao_do_saldo(None, '2026-10-10', {('X', 'Y'): -1.0},
                                              '2026-10-09', '2026-10-08')
    finally:
        ag.movimento_desde_a_foto = original_desde
    conferir('foto antes do envio: a correcao conta desde a data certa, nao a fila',
             base == 'foto' and pedidos == ['2026-10-08']
             and correcao == {('1642500090024', '26CQ145'): 1.0},
             '%r %r %r' % (base, pedidos, correcao))
    correcao, base = ag.correcao_do_saldo(None, '2026-10-10', {('X', 'Y'): -1.0}, '2026-10-09')
    conferir('sem a hora, a foto em dia continua usando a fila', base == 'fila'
             and correcao == {('X', 'Y'): -1.0})
    try:
        ag.movimento_desde_a_foto = lambda _c, _desde: {}
        correcao, base = ag.correcao_do_saldo(None, '2026-10-10', {('X', 'Y'): -1.0},
                                              '2026-10-09', '2026-10-08')
    finally:
        ag.movimento_desde_a_foto = original_desde
    conferir('foto antes do envio sem movimento lido: nao volta para a fila errada',
             base == 'foto' and correcao == {})

    # xml_depois_da_foto com arquivos de verdade: so entra o gerado depois
    pasta_xml = os.path.join(pasta, 'xml_foto')
    os.makedirs(os.path.join(pasta_xml, 'enviados'))
    antes = os.path.join(pasta_xml, 'enviados', 'sngpc_2026-10-09.xml')
    depois = os.path.join(pasta_xml, 'SNGPC.XML')
    for caminho, quando in ((antes, dt(2026, 10, 9, 7, 21)), (depois, dt(2026, 10, 10, 7, 21))):
        shutil.copy('exemplo_SNGPC.XML', caminho)
        os.utime(caminho, (quando.timestamp(), quando.timestamp()))
    achados = ag.xml_depois_da_foto({'pasta_xml': pasta_xml}, foto_hora)
    conferir('so o XML gerado depois da foto entra na conta',
             [h for h, _ in achados] == [dt(2026, 10, 10, 7, 21)]
             and achados[0][1].get('cabecalho', {}).get('dataInicio') == '2026-08-04',
             repr([h for h, _ in achados]))

    # --- Log do Anvisa: Latin-1 e conclusao pela ultima execucao ---
    log = os.path.join(pasta, 'anvisa.log')
    with open(log, 'w', encoding='latin-1') as f:
        f.write('09/10/2026 16:33:26 - ============================Aplicação iniciada'
                '============================\n'
                '09/10/2026 16:33:31 - Site do SNGPC carregado, aguardando login\n'
                '10/10/2026 07:17:38 - ============================Aplicação iniciada'
                '============================\n'
                '10/10/2026 07:17:43 - Site do SNGPC carregado, aguardando login\n'
                '10/10/2026 07:18:35 - Listando o inventário\n'
                '10/10/2026 07:18:40 - Processo de sincronização finalizado, encerrando a aplicação\n'
                '10/10/2026 07:18:40 - processo finalizado - 07:18:40\n')
    linhas = ag.ler_log_anvisa(log)
    conclusao = ' '.join(ag.conclusao_log_anvisa(linhas))
    conferir('log em Latin-1 lido com acento', any('sincronização' in l for l in linhas))
    conferir('execucao que baixou o inventario nao vira "parou no login"',
             'terminou' in conclusao and '10/10/2026 07:18:40' in conclusao
             and 'PAROU' not in conclusao, conclusao)
    parada = linhas[:4]
    conferir('execucao que parou no site continua sendo dita como parada no login',
             'PAROU' in ' '.join(ag.conclusao_log_anvisa(parada)))
    original_achar = ag.achar_log_anvisa
    try:
        ag.achar_log_anvisa = lambda _config: log
        conferir('hora da foto sai do ultimo "sincronizacao finalizado"',
                 ag.hora_da_foto({}) == dt(2026, 10, 10, 7, 18, 40))
    finally:
        ag.achar_log_anvisa = original_achar

    # --- o laboratorio de cada medicamento, descoberto pelo esquema ---
    def banco_com_laboratorio(colunas_produtos, laboratorios=None):
        def falso(_conexao, sql, _parametros=()):
            if 'RDB$RELATION_FIELDS' in sql:
                tabelas = {'PRODUTOS': colunas_produtos}
                if laboratorios is not None:
                    tabelas['LABORATORIOS'] = ('LABORATORIO_ID', 'NOME_FANTASIA')
                return [{'TABELA': t, 'CAMPO': c}
                        for t, cs in tabelas.items() for c in cs]
            if 'RDB$RELATION_CONSTRAINTS' in sql:
                return []
            if 'FROM LABORATORIOS' in sql:
                return [{'CODIGO': k, 'NOME': v} for k, v in (laboratorios or {}).items()]
            if 'FROM PRODUTOS' in sql:
                return [{'PRODUTO_ID': 13139, 'REGISTRO_MS': '1.0573.0642.003-0',
                         'LABORATORIO': 7 if laboratorios is not None else 'EMS'}]
            raise AssertionError('consulta não simulada:\n' + sql[:120])
        return falso

    guardado = ag.consultar
    try:
        ag.consultar = banco_com_laboratorio(('PRODUTO_ID', 'REGISTRO_MS', 'LABORATORIO_ID'),
                                             {7: 'Aché'})
        por_produto, por_ms = ag.laboratorios_por_medicamento(None)
        conferir('laboratorio traduzido pelo cadastro de apoio',
                 por_produto.get('13139') == 'Aché' and por_ms.get('1057306420030') == 'Aché',
                 (por_produto, por_ms))
        itens = [{'codigo': 13139, 'ms': '1057306420030'},
                 {'codigo': '', 'ms': '1.0573.0642.003-0'},
                 {'codigo': 99, 'ms': '1111111111111'}]
        ag.anotar_laboratorio(itens, por_produto, por_ms)
        conferir('o laboratorio vai para o item pelo codigo ou pelo M.S.',
                 [i.get('laboratorio') for i in itens] == ['Aché', 'Aché', None], itens)

        ag.consultar = banco_com_laboratorio(('PRODUTO_ID', 'REGISTRO_MS', 'LABORATORIO'))
        conferir('laboratorio guardado por extenso no PRODUTOS sai como esta',
                 ag.laboratorios_por_medicamento(None)[0].get('13139') == 'EMS')

        # Digifarma: colunas da PRODUTOS com PROD_ na frente
        mapa = {'PRODUTOS': {'PRODUTO_ID', 'PROD_LABORATORIO_ID'},
                'LABORATORIOS': {'LABORATORIO_ID', 'NOME_FANTASIA'}}
        conferir('coluna com PROD_ na frente acha o cadastro de laboratorios',
                 ag.coluna_de_laboratorio(mapa) == ('PROD_LABORATORIO_ID', 'LABORATORIOS',
                                                    'NOME_FANTASIA', 'LABORATORIO_ID'),
                 ag.coluna_de_laboratorio(mapa))

        ag.consultar = banco_com_laboratorio(('PRODUTO_ID', 'REGISTRO_MS',
                                              'DATA_FABRICACAO'))
        conferir('sem coluna de laboratorio, nada e inventado',
                 ag.laboratorios_por_medicamento(None) == ({}, {}))
    finally:
        ag.consultar = guardado

    # --- nome do medicamento que veio só no XML (o XML não traz nome) ---
    guardado = ag.consultar
    try:
        ag.consultar = lambda _c, sql, _p=(): (
            [{'REGISTRO_MS': '1.0370.0540.005-2', 'PRODUTO': 'CLONAZEPAM 2MG TEUTO'},
             {'REGISTRO_MS': None, 'PRODUTO': 'SEM REGISTRO'}]
            if 'FROM PRODUTOS' in sql else [])
        ag.DESCRICOES.clear()
        ag.DESCRICOES[('1052500830027', 'OUTRO')] = 'SERTRALINA 50MG'
        itens = [{'ms': '1037005400052', 'lote': '5118223', 'descricao': ''},
                 {'ms': '1052500830027', 'lote': 'CLP3L028', 'descricao': ''},
                 {'ms': '1999999999999', 'lote': 'X', 'descricao': ''},
                 {'ms': '1037005400052', 'lote': 'Y', 'descricao': 'NOME DO BANCO'}]
        ag.descrever_pelo_cadastro(None, itens)
        conferir('item só no XML ganha o nome pelo M.S. (cadastro, depois ANVISA)',
                 [i['descricao'] for i in itens] == ['CLONAZEPAM 2MG TEUTO', 'SERTRALINA 50MG',
                                                     '', 'NOME DO BANCO'], itens)

        def banco_quebrado(_c, _sql, _p=()):
            raise RuntimeError('sem conexão')
        ag.consultar = banco_quebrado
        itens = [{'ms': '1052500830027', 'descricao': ''}]
        ag.descrever_pelo_cadastro(None, itens)
        conferir('falha no cadastro não derruba: usa o nome do inventário da ANVISA',
                 itens[0]['descricao'] == 'SERTRALINA 50MG', itens)
    finally:
        ag.consultar = guardado
        ag.DESCRICOES.clear()

    # --- arquivos de retorno da ANVISA (VerificaXML\retorno_sngpc) ---
    pasta_xml = tempfile.mkdtemp()
    try:
        os.makedirs(os.path.join(pasta_xml, 'retorno_sngpc'))
        os.makedirs(os.path.join(pasta_xml, 'enviados'))

        def escrever(rel, conteudo, quando, codificacao='utf-8'):
            caminho = os.path.join(pasta_xml, rel)
            with open(caminho, 'w', encoding=codificacao) as f:
                f.write(conteudo)
            os.utime(caminho, (quando, quando))

        escrever('retorno_sngpc/retorno_anvisa_2026_10_15_43.txt',
                 'Periodo 13/10/2026 a 13/10/2026\nERRO: lote 5R7387 inválido\n'
                 'Responsável CPF 123.456.789-09 fulano@farmacia.com\nSenha: segredo\n',
                 1760467000)
        escrever('retorno_sngpc/retorno_anvisa_2026_10_14_42.txt',
                 'Movimentação validada com sucesso', 1760380000, 'cp1252')
        escrever('enviados/retorno_que_nao_e.txt', 'não deveria aparecer', 1760500000)
        escrever('retorno_sngpc/outra_coisa.txt', 'não é retorno', 1760500000)

        retornos = ag.retornos_em_arquivo({'pasta_xml': pasta_xml})
        conferir('retornos da ANVISA: só os arquivos retorno*, fora da pasta enviados, do mais novo ao mais velho',
                 [r['arquivo'] for r in retornos]
                 == ['retorno_anvisa_2026_10_15_43.txt', 'retorno_anvisa_2026_10_14_42.txt'],
                 [r['arquivo'] for r in retornos])
        primeiro = retornos[0] if retornos else {}
        conferir('retorno publicado sem CPF, e-mail nem linha de senha',
                 '123.456.789-09' not in primeiro.get('texto', '')
                 and 'fulano@' not in primeiro.get('texto', '')
                 and 'segredo' not in primeiro.get('texto', '')
                 and 'lote 5R7387' in primeiro.get('texto', ''), primeiro)
        conferir('retorno separa as linhas que falam de erro',
                 primeiro.get('linhasDeErro') == ['ERRO: lote 5R7387 inválido'], primeiro)
        conferir('retorno gravado em cp1252 é lido com acento',
                 len(retornos) > 1 and retornos[1]['texto'] == 'Movimentação validada com sucesso'
                 and retornos[1]['linhasDeErro'] == [], retornos[1:])
        conferir('sem pasta do XML, nenhum retorno e nenhum erro',
                 ag.retornos_em_arquivo({'pasta_xml': '/nao/existe'}) == [])
    finally:
        shutil.rmtree(pasta_xml, ignore_errors=True)

    # --- histórico do dia: as mesmas contas do placar do app ---
    resumo = ag.resumo_do_dia({
        'atualizadoEm': '2026-10-13T10:00:00',
        'itens': [{'diferenca': 2, 'motivo': 'quantidade'}, {'diferenca': 0.0},
                  {'diferenca': -1, 'motivo': 'negativo'}, {'diferenca': 0.0004}],
        'resumoSaldo': {'quantidade': 1, 'negativo': 1},
        'conferencia_xml': [{'situacao': 'ok'}, {'situacao': 'fora_do_xml'}],
        'vendas_problema': [{'venda': 1}, {'venda': 2}, {'venda': 3}],
        'inventario': {'confianca': {'confiavel': False}},
    })
    conferir('o histórico conta como o placar (diferença ≠ 0, XML fora de ok, vendas)',
             (resumo['divergencias'], resumo['xml'], resumo['vendasProblema'])
             == (2, 1, 3), resumo)
    conferir('o histórico marca o dia de comparação prejudicada',
             resumo['confiavel'] is False and resumo['porMotivo'] == {'quantidade': 1, 'negativo': 1},
             resumo)
    conferir('dia sem nada publicado vira zeros, não erro',
             ag.resumo_do_dia({})['divergencias'] == 0 and ag.resumo_do_dia({})['confiavel'] is True)

    gravados = {}

    class RefHistorico:
        def __init__(self, caminho):
            self.caminho = caminho

        def set(self, valor):
            gravados[self.caminho] = valor

    class DbHistorico:
        def reference(self, caminho):
            return RefHistorico(caminho)

    ag.publicar_historico(DbHistorico(), {'itens': [{'diferenca': 1}]})
    hoje_hist = 'farmacia/historico/%s' % datetime.date.today().isoformat()
    conferir('um nó por dia em farmacia/historico/<data>',
             list(gravados) == [hoje_hist] and gravados[hoje_hist]['divergencias'] == 1,
             gravados)

    # --- avisos no celular (FCM simulado) ---
    enviados = []

    class TokenMorto(Exception):
        pass
    TokenMorto.__name__ = 'UnregisteredError'

    class MessagingFalso:
        class Message:
            def __init__(self, token, data, webpush):
                self.token, self.data, self.webpush = token, data, webpush

        def WebpushConfig(self, **k):
            return k

        def WebpushNotification(self, **k):
            return k

        def WebpushFCMOptions(self, **k):
            return k

        def send(self, mensagem):
            if mensagem.token == 'morto':
                raise TokenMorto('Requested entity was not found.')
            enviados.append((mensagem.token, mensagem.data['titulo'], mensagem.data['texto']))

    apagados = []

    class DbAvisos:
        def __init__(self, cadastro):
            self.cadastro = cadastro

        def reference(self, caminho):
            db = self

            class Ref:
                def get(self):
                    return db.cadastro

                def delete(self):
                    apagados.append(caminho)
            return Ref()

    pasta_avisos = tempfile.mkdtemp()
    guardados = (ag._messaging, ag.PASTA)
    try:
        ag._messaging = lambda: MessagingFalso()
        ag.PASTA = pasta_avisos
        celulares = DbAvisos({'a1': {'token': 'tok-1', 'em': 'x'}, 'a2': {'token': 'morto', 'em': 'x'}})
        venda = [{'venda': 46505, 'descricao': 'OLANZAPINA 10MG', 'ms': '1'}]

        ag.avisar_vendas_sem_receita(DbAvisos({}), venda)
        conferir('sem celular cadastrado, a venda não conta como avisada',
                 not enviados and not ag.ler_avisos().get('vendas'), ag.ler_avisos())

        ag.avisar_vendas_sem_receita(celulares, venda)
        conferir('venda sem receita nova vira aviso com o número da venda',
                 enviados == [('tok-1', 'Venda sem receita',
                               'Venda 46505: OLANZAPINA 10MG sem receita. Lance antes do próximo envio.')],
                 enviados)
        conferir('celular que desinstalou sai da lista', apagados == ['farmacia/notificacoes/a2'], apagados)

        enviados.clear()
        ag.avisar_vendas_sem_receita(celulares, venda)
        conferir('a mesma venda não é avisada de novo a cada 5 minutos', not enviados, enviados)

        ag.avisar_vendas_sem_receita(celulares, venda + [
            {'venda': 46510, 'descricao': 'A'}, {'venda': 46511, 'descricao': 'B'}])
        conferir('várias vendas novas viram um aviso só',
                 len(enviados) == 1 and '2 vendas' in enviados[0][2] and '46510, 46511' in enviados[0][2],
                 enviados)
        ag.avisar_vendas_sem_receita(celulares, [{'venda': 46511, 'descricao': 'B'}])
        conferir('venda corrigida sai da memória dos avisos',
                 ag.ler_avisos()['vendas'] == ['46511'], ag.ler_avisos())

        # a sincronização grava o resumo enquanto a fila trabalha nas vendas
        ag.gravar_avisos('resumo', '2026-10-14')
        ag.gravar_avisos('vendas', ['46511'])
        conferir('uma gravação dos avisos não apaga a chave da outra',
                 ag.ler_avisos() == {'resumo': '2026-10-14', 'vendas': ['46511']}, ag.ler_avisos())
        with open(os.path.join(pasta_avisos, ag.ARQUIVO_AVISOS), 'w') as f:
            f.write('[]')
        enviados.clear()
        ag.avisar_vendas_sem_receita(celulares, [{'venda': 50000, 'descricao': 'X'}])
        conferir('memória de avisos estragada não trava os avisos',
                 len(enviados) == 1 and ag.ler_avisos().get('vendas') == ['50000'], ag.ler_avisos())
        with open(os.path.join(pasta_avisos, ag.ARQUIVO_AVISOS), 'w') as f:
            f.write('{}')

        enviados.clear()
        com_pendencia = {'itens': [{'diferenca': 1}], 'vendas_problema': [], 'vendasSemReceita': [1]}
        cedo = datetime.datetime(2026, 10, 14, 7, 30)
        ag.avisar_resumo_do_dia(celulares, com_pendencia, cedo)
        conferir('o resumo do dia não sai de madrugada', not enviados)
        manha = datetime.datetime(2026, 10, 14, 8, 5)
        ag.avisar_resumo_do_dia(celulares, com_pendencia, manha)
        ag.avisar_resumo_do_dia(celulares, com_pendencia, manha + datetime.timedelta(hours=1))
        conferir('o resumo sai uma vez por dia, com os números',
                 len(enviados) == 1 and enviados[0][2].startswith('1 divergência(s) de saldo, 0 venda(s)'),
                 enviados)
        enviados.clear()
        ag.avisar_resumo_do_dia(celulares, {'itens': []}, datetime.datetime(2026, 10, 15, 9))
        conferir('dia sem pendência não manda resumo', not enviados, enviados)

        enviados.clear()
        recado = ag.atender_pedido({}, DbAvisos({'a1': {'token': 'tok-1', 'em': 'x'}}),
                                   {'acao': 'testar_aviso'})
        conferir('o botão de teste manda um aviso e diz quantos receberam',
                 len(enviados) == 1 and '1 de 1' in recado, recado)
        recado = ag.atender_pedido({}, DbAvisos({}), {'acao': 'testar_aviso'})
        conferir('teste sem celular cadastrado explica como ligar', 'Nenhum celular' in recado, recado)
    finally:
        ag._messaging, ag.PASTA = guardados
        shutil.rmtree(pasta_avisos, ignore_errors=True)

    # --- aviso de aceite marcado no app e de retorno de verdade da ANVISA ---
    class DbMemoria:
        """Firebase em memória: caminho 'a/b/c' sobre um dict aninhado."""

        def __init__(self, arvore, travar=()):
            self.arvore, self.travar = arvore, travar

        def reference(self, caminho):
            db = self
            partes = caminho.split('/')

            class Ref:
                def get(self):
                    no = db.arvore
                    for p in partes:
                        if not isinstance(no, dict) or p not in no:
                            return None
                        no = no[p]
                    return no

                def set(self, valor):
                    if any(caminho.startswith(t) for t in db.travar):
                        raise RuntimeError('Permission denied')
                    no = db.arvore
                    for p in partes[:-1]:
                        no = no.setdefault(p, {})
                    no[partes[-1]] = valor

                def delete(self):
                    no = db.arvore
                    for p in partes[:-1]:
                        no = no.get(p, {})
                    no.pop(partes[-1], None)
            return Ref()

    def girar_fila(db):
        ag.conectar_firebase = lambda _config: db
        ag.modo_fila({})

    pasta_avisos = tempfile.mkdtemp()
    guardados = (ag._messaging, ag.PASTA, ag.conectar_firebase, ag.atualizar_sozinho,
                 ag.publicar_vendas_recentes, ag.registrar)
    try:
        ag._messaging = lambda: MessagingFalso()
        ag.PASTA = pasta_avisos
        ag.atualizar_sozinho = lambda _config: None
        ag.publicar_vendas_recentes = lambda _config, _db: None
        ag.registrar = lambda _msg: None
        celular = {'a1': {'token': 'tok-1', 'em': 'x'}}
        antigo = {'status': 'aceito', 'por': 'Ana', 'em': '2026-10-01T10:00:00'}
        arvore = {'farmacia': {'notificacoes': celular, 'aceites': {'2026-09-30': antigo}}}
        db = DbMemoria(arvore)

        enviados.clear()
        girar_fila(db)
        conferir('aceite que já existia antes da atualização não vira aviso',
                 not enviados and arvore['farmacia']['avisado']['aceites'].get('2026-09-30')
                 == antigo['em'], (enviados, arvore['farmacia'].get('avisado')))

        arvore['farmacia']['aceites']['2026-10-14'] = {
            'status': 'aceito', 'por': 'Bia', 'em': '2026-10-15T09:00:00'}
        enviados.clear()
        girar_fila(db)
        girar_fila(db)
        conferir('a fila rodando duas vezes com o mesmo aceite avisa uma vez só',
                 enviados == [('tok-1', 'Envio aceito',
                               'Envio de 14/10/2026 marcado como ACEITO por Bia')], enviados)

        arvore['farmacia']['aceites']['2026-10-14'] = {
            'status': 'recusado', 'por': 'Bia', 'em': '2026-10-15T09:30:00',
            'erro': 'Quantidade vendida maior que o estoque. CPF 123.456.789-09'}
        enviados.clear()
        girar_fila(db)
        girar_fila(db)
        conferir('remarcar como recusado avisa de novo, uma vez, com o erro colado',
                 len(enviados) == 1 and enviados[0][1] == 'Envio recusado'
                 and enviados[0][2].startswith('Envio de 14/10/2026 marcado como RECUSADO por Bia — '
                                               'Quantidade vendida maior')
                 and '123.456' not in enviados[0][2], enviados)

        sem_celular = DbMemoria({'farmacia': {'aceites': {'2026-10-13': antigo},
                                              'avisado': {'aceites': {'_desde': 'x'}}}})
        enviados.clear()
        girar_fila(sem_celular)
        conferir('sem celular cadastrado, o aceite não conta como avisado',
                 not enviados and '2026-10-13' not in sem_celular.arvore['farmacia']['avisado']['aceites'],
                 sem_celular.arvore['farmacia']['avisado'])
        sem_celular.arvore['farmacia']['notificacoes'] = dict(celular)
        girar_fila(sem_celular)
        conferir('quem liga os avisos depois recebe o aceite que esperava', len(enviados) == 1, enviados)

        travado = DbMemoria({'farmacia': {'notificacoes': dict(celular),
                                          'aceites': {'2026-10-12': antigo},
                                          'avisado': {'aceites': {'_desde': 'x'}}}},
                            travar=('farmacia/avisado',))
        enviados.clear()
        girar_fila(travado)
        girar_fila(travado)
        conferir('sem conseguir gravar o "já avisei", não avisa (senão seria a cada minuto)',
                 not enviados, enviados)

        def sem_fcm():
            raise ImportError('firebase_admin.messaging')
        quebrado = DbMemoria({'farmacia': {'notificacoes': dict(celular),
                                           'aceites': {'2026-10-11': antigo},
                                           'avisado': {'aceites': {'_desde': 'x'}}}})
        ag._messaging = sem_fcm
        try:
            ag.avisar_aceites(quebrado)
        except ImportError:
            pass
        ag._messaging = lambda: MessagingFalso()
        conferir('envio que estoura desfaz a marca: o aceite não se perde calado',
                 '2026-10-11' not in quebrado.arvore['farmacia']['avisado']['aceites'],
                 quebrado.arvore['farmacia']['avisado'])

        vazio = {'arquivo': 'retorno_anvisa_2026_10_15_43.txt', 'linhasDeErro': [],
                 'texto': 'HASH: \nDATA TRANSMISSÃO: 30/12/1899\nDATA VALIDAÇÃO: 30/12/1899\n'
                          'INICIO PERIODO: 30/12/1899\nFIM DO PERIODO: 30/12/1899\nMSG DE RETORNO: \n'}
        so_data_zero = dict(vazio, texto=vazio['texto'].replace('HASH: ', 'HASH: 92606BDD')
                            .replace('MSG DE RETORNO: ', 'MSG DE RETORNO: Arquivo recebido'))
        real = dict(vazio, texto='HASH: 92606BDD\nDATA TRANSMISSÃO: 15/10/2026 08:01\n'
                                 'INICIO PERIODO: 13/10/2026\nFIM DO PERIODO: 14/10/2026\n'
                                 'MSG DE RETORNO: Arquivo com ERRO:\nlote L1 sem saldo\n')
        conferir('arquivo vazio do Digifarma não é retorno de verdade',
                 ag.retorno_de_verdade(vazio) is None)
        conferir('hash e mensagem com data 30/12/1899 não é retorno de verdade',
                 ag.retorno_de_verdade(so_data_zero) is None)
        conferir('a identidade do retorno vem do conteúdo (hash + data), não do nome',
                 ag.retorno_de_verdade(real)[0] == '92606BDD_151020260801'
                 and ag.retorno_de_verdade(dict(real, arquivo='outro.txt'))[0]
                 == ag.retorno_de_verdade(real)[0])

        arvore = {'farmacia': {'notificacoes': dict(celular)}}
        db = DbMemoria(arvore)
        ag.avisar_retornos(db, [vazio])
        enviados.clear()
        ag.avisar_retornos(db, [real, vazio])
        ag.avisar_retornos(db, [dict(real, arquivo='retorno_anvisa_2026_10_16_44.txt'), vazio])
        conferir('o mesmo retorno de verdade, visto em duas voltas e com outro nome, avisa uma vez',
                 enviados == [('tok-1', 'Resposta da ANVISA com erro',
                               'Período 13/10/2026 a 14/10/2026: Arquivo com ERRO: lote L1 sem saldo')],
                 enviados)
        enviados.clear()
        ag.avisar_retornos(DbMemoria({'farmacia': {'notificacoes': dict(celular)}}), [real])
        conferir('retorno que já estava na pasta antes da atualização não vira aviso', not enviados, enviados)

        # pasta do XML fora do ar na 1ª volta: não pode virar semente vazia
        pasta_xml = os.path.join(pasta_avisos, 'VerificaXML')
        arvore = {'farmacia': {'notificacoes': dict(celular)}}
        db = DbMemoria(arvore)
        nomes = ('conectar_firebird', 'fechar', 'vendas_recentes', 'vendas_sem_receita_pendentes',
                 'snapshot_diagnostico', 'entradas_recentes', 'retorno_sngpc', 'mudou',
                 'atualizar_envios_publicos', 'publicar_publico')
        guardadas = {n: getattr(ag, n) for n in nomes}
        try:
            ag.conectar_firebird = lambda _c: None
            ag.fechar = lambda _c: None
            ag.vendas_recentes = lambda _c: []
            ag.vendas_sem_receita_pendentes = lambda _c, _cfg: []
            ag.snapshot_diagnostico = lambda _c: {}
            ag.entradas_recentes = lambda _c, _p, config=None: []
            ag.retorno_sngpc = lambda _c: None
            ag.mudou = lambda _caminho, _valor: False
            ag.atualizar_envios_publicos = lambda _db: False
            ag.publicar_publico = lambda *_a, **_k: None
            enviados.clear()
            publicar_de_verdade = guardados[4]
            publicar_de_verdade({'pasta_xml': pasta_xml}, db)
            conferir('pasta do XML fora do ar não vira semente vazia de retornos',
                     'retorno' not in arvore['farmacia'].get('avisado', {}),
                     arvore['farmacia'].get('avisado'))
            os.makedirs(os.path.join(pasta_xml, 'retorno_sngpc'))
            with open(os.path.join(pasta_xml, 'retorno_sngpc', 'retorno_anvisa_2026_10_15_43.txt'),
                      'w', encoding='utf-8') as f:
                f.write(real['texto'])
            publicar_de_verdade({'pasta_xml': pasta_xml}, db)
            publicar_de_verdade({'pasta_xml': pasta_xml}, db)
            conferir('pasta que volta: o retorno que já estava lá entra como avisado, calado',
                     not enviados and list(arvore['farmacia']['avisado']['retorno'])
                     == ['92606BDD_151020260801', '_desde'], (enviados, arvore['farmacia'].get('avisado')))
        finally:
            for n, f in guardadas.items():
                setattr(ag, n, f)
    finally:
        (ag._messaging, ag.PASTA, ag.conectar_firebase, ag.atualizar_sozinho,
         ag.publicar_vendas_recentes, ag.registrar) = guardados
        shutil.rmtree(pasta_avisos, ignore_errors=True)

    # --- atualizador de vários arquivos, com volta atrás ---
    import json
    import urllib.error

    def agente_falso(extra=''):
        return 'CONSULTAS = {}\n%s\ndef principal():\n    pass\n' % extra + '#' * 20000

    def montar_servidor(arquivos_no_disco):
        pasta_srv = tempfile.mkdtemp()
        for nome, conteudo in arquivos_no_disco.items():
            with open(os.path.join(pasta_srv, nome), 'w', encoding='utf-8') as f:
                f.write(conteudo)
        return pasta_srv

    def ler(pasta_srv, nome):
        with open(os.path.join(pasta_srv, nome), encoding='utf-8') as f:
            return f.read()

    repositorio = {}

    def baixar_falso(url):
        nome = url.rsplit('/', 1)[1]
        if nome not in repositorio:
            raise urllib.error.HTTPError(url, 404, 'Not Found', {}, None)
        return repositorio[nome]

    antigo_agente, antigo_mapa = agente_falso('VERSAO = 1'), 'def comparar():\n    return 1\n'
    guardados = (ag.PASTA, ag.baixar_texto, ag.publicar_regras)
    pastas = []
    try:
        ag.baixar_texto = baixar_falso
        ag.publicar_regras = lambda _config: 'regras ok'

        # 1. lista nova com um módulo novo: tudo chega, backups ficam
        ag.PASTA = montar_servidor({'agente_auto.py': antigo_agente, 'mapa_xml.py': antigo_mapa})
        pastas.append(ag.PASTA)
        repositorio.clear()
        repositorio.update({
            'arquivos.json': json.dumps({'arquivos': {'agente_auto.py': 'def principal(',
                                                      'mapa_xml.py': 'def comparar(',
                                                      'coleta.py': 'def coletar('}}),
            'agente_auto.py': agente_falso('import coleta\nVERSAO = 2'),
            'mapa_xml.py': 'def comparar():\n    return 2\n',
            'coleta.py': 'def coletar():\n    return 2\n',
        })
        recado = ag.atualizar_agente({})
        conferir('atualizador baixa a lista do repositório, inclusive módulo novo',
                 'VERSAO = 2' in ler(ag.PASTA, 'agente_auto.py')
                 and ler(ag.PASTA, 'coleta.py').startswith('def coletar')
                 and 'return 2' in ler(ag.PASTA, 'mapa_xml.py'), recado)
        backups = sorted(n for n in os.listdir(ag.PASTA) if '_antes_de_' in n)
        conferir('cada arquivo trocado deixa backup com o nome de sempre',
                 [b.split('_antes_de_')[0] for b in backups] == ['agente_auto', 'mapa_xml'], backups)

        # 2. o principal novo importa um módulo que não veio: tudo volta
        ag.PASTA = montar_servidor({'agente_auto.py': antigo_agente, 'mapa_xml.py': antigo_mapa})
        pastas.append(ag.PASTA)
        repositorio.clear()
        repositorio.update({
            'arquivos.json': json.dumps({'arquivos': {'agente_auto.py': 'def principal(',
                                                      'mapa_xml.py': 'def comparar(',
                                                      'leitura.py': 'def ler('}}),
            'agente_auto.py': agente_falso('import modulo_que_nao_veio\nVERSAO = 3'),
            'mapa_xml.py': 'def comparar():\n    return 3\n',
            'leitura.py': 'def ler():\n    return 3\n',
        })
        try:
            ag.atualizar_agente({})
            conferir('agente novo que não carrega volta TODOS os arquivos', False)
        except RuntimeError as e:
            conferir('agente novo que não carrega volta TODOS os arquivos',
                     ler(ag.PASTA, 'agente_auto.py') == antigo_agente
                     and ler(ag.PASTA, 'mapa_xml.py') == antigo_mapa
                     and not os.path.exists(os.path.join(ag.PASTA, 'leitura.py'))
                     and 'voltou à versão anterior' in str(e)
                     and 'modulo_que_nao_veio' in str(e), e)

        # 3. lista com caminho para fora da pasta: recusada antes de tocar no disco
        repositorio['arquivos.json'] = json.dumps(
            {'arquivos': {'agente_auto.py': 'def principal(', '../fora.py': 'x'}})
        try:
            ag.atualizar_agente({})
            conferir('arquivos.json com caminho estranho é recusado', False)
        except RuntimeError as e:
            conferir('arquivos.json com caminho estranho é recusado',
                     'nome inválido' in str(e) and ler(ag.PASTA, 'agente_auto.py') == antigo_agente, e)

        # 4. sem arquivos.json no repositório: vale a lista fixa
        del repositorio['arquivos.json']
        repositorio.update({'agente_auto.py': agente_falso('VERSAO = 4'),
                            'mapa_xml.py': 'def comparar():\n    return 4\n'})
        ag.atualizar_agente({})
        conferir('sem arquivos.json, atualiza o agente e o mapa_xml',
                 'VERSAO = 4' in ler(ag.PASTA, 'agente_auto.py')
                 and 'return 4' in ler(ag.PASTA, 'mapa_xml.py'))

        # 5. erro de sintaxe em um arquivo: nada é trocado
        antes_do_erro = ler(ag.PASTA, 'agente_auto.py')
        repositorio.update({'agente_auto.py': agente_falso('VERSAO = 5'),
                            'mapa_xml.py': 'def comparar(:\n'})
        try:
            ag.atualizar_agente({})
            conferir('erro de sintaxe em qualquer arquivo: nada é trocado', False)
        except SyntaxError:
            conferir('erro de sintaxe em qualquer arquivo: nada é trocado',
                     ler(ag.PASTA, 'agente_auto.py') == antes_do_erro)

        # 6. nada mudou
        repositorio.update({'agente_auto.py': antes_do_erro,
                            'mapa_xml.py': 'def comparar():\n    return 4\n'})
        conferir('repositório igual ao servidor: diz que já está na mais nova',
                 'já estava' in ag.atualizar_agente({}))
    finally:
        ag.PASTA, ag.baixar_texto, ag.publicar_regras = guardados
        for p in pastas:
            shutil.rmtree(p, ignore_errors=True)

    # a lista de verdade, do repositório: passa na validação, e cada arquivo
    # listado existe aqui e tem o trecho que o atualizador vai exigir dele
    aqui = os.path.dirname(os.path.abspath(__file__))
    guardado = ag.baixar_texto
    try:
        ag.baixar_texto = lambda url: open(os.path.join(aqui, url.rsplit('/', 1)[1]),
                                           encoding='utf-8').read()
        lista = ag.lista_de_arquivos('repo')
        sem_marca = [n for n, marca in lista.items()
                     if marca not in open(os.path.join(aqui, n), encoding='utf-8').read()]
        conferir('o arquivos.json do repositório passa no atualizador e bate com os arquivos',
                 'agente_auto.py' in lista and not sem_marca, (lista, sem_marca))
    finally:
        ag.baixar_texto = guardado

    # --- desmarcar controlado pelo app ---
    escritos, ajustes = [], []

    def banco_desmarcar(psico='S', anti='N', tem_n=True):
        def falso(_conexao, sql, parametros=()):
            if 'WHERE PRODUTO_ID = ?' in sql:
                return [{'PRODUTO_ID': 13139, 'PRODUTO': 'OLANZAPINA 2,5MG',
                         'REGISTRO_MS': '1.0573.0642.003-0',
                         'PSICOTROPICO': psico, 'ANTIMICROBIANO': anti}]
            if "= 'N'" in sql:
                return [{'PRODUTO_ID': 1}] if tem_n else []
            if sql == ag.CONSULTAS['produtos_controlados']:
                return [{'PRODUTO_ID': 13139, 'PRODUTO': 'OLANZAPINA 2,5MG',
                         'REGISTRO_MS': '1057306420030', 'PSICOTROPICO': psico,
                         'ANTIMICROBIANO': anti},
                        {'PRODUTO_ID': 777, 'PRODUTO': 'OLANZAPINA 2,5MG GENERICO',
                         'REGISTRO_MS': '1057306420030', 'PSICOTROPICO': 'S',
                         'ANTIMICROBIANO': 'N'}]
            raise AssertionError('consulta não simulada:\n' + sql[:120])
        return falso

    guardados = (ag.consultar, ag.executar, ag.conectar_firebird, ag.fechar,
                 ag.modo_auto, ag.registrar_ajuste)
    ligada = {'permitir_ajuste_estoque': True}
    pedido = {'produtoId': '13139', 'desmarcar': 'ambos', 'pedidoPor': 'jefferson'}
    try:
        ag.executar = lambda _c, sql, p=(): escritos.append((sql, p)) or 1
        ag.conectar_firebird = lambda _config: None
        ag.fechar = lambda _c: None
        ag.modo_auto = lambda _config: None
        ag.registrar_ajuste = lambda _db, dados: ajustes.append(dados)

        ag.consultar = banco_desmarcar()
        try:
            ag.desmarcar_controlado({}, None, pedido)
            conferir('desmarcar com a escrita desligada é recusado', False)
        except RuntimeError as e:
            conferir('desmarcar com a escrita desligada é recusado',
                     'desligada' in str(e) and not escritos, e)

        recado = ag.desmarcar_controlado(ligada, None, pedido)
        conferir('desmarca só a coluna que estava marcada, só naquele produto',
                 len(escritos) == 1
                 and escritos[0][0].startswith("UPDATE PRODUTOS SET PSICOTROPICO = 'N' WHERE PRODUTO_ID = ?")
                 and 'ANTIMICROBIANO' not in escritos[0][0] and escritos[0][1] == (13139,),
                 escritos)
        conferir('o desmarcar fica registrado com o antes e o depois',
                 ajustes and ajustes[0]['tipo'] == 'desmarcar_controlado'
                 and ajustes[0]['colunas'] == [{'coluna': 'PSICOTROPICO', 'de': 'S', 'para': 'N'}]
                 and ajustes[0]['por'] == 'jefferson', ajustes)
        conferir('a resposta diz como voltar', 'marque a caixa de novo' in recado, recado)

        escritos.clear()
        ag.consultar = banco_desmarcar(psico='N', anti='N')
        recado = ag.desmarcar_controlado(ligada, None, pedido)
        conferir('produto já desmarcado não é alterado', not escritos and 'já não' in recado, recado)
        conferir('diz qual outro cadastro com o mesmo M.S. continua marcado',
                 'código 777' in recado, recado)

        ag.consultar = banco_desmarcar()

        def sincronizacao_quebrada(_config):
            raise RuntimeError('firebird caiu')
        ag.modo_auto = sincronizacao_quebrada
        recado = ag.desmarcar_controlado(ligada, None, pedido)
        conferir('sincronização falhando depois de desmarcar avisa que a lista demora',
                 'próxima sincronização' in recado and len(escritos) == 1, recado)
        escritos.clear()
        ag.modo_auto = lambda _config: None

        ag.consultar = banco_desmarcar(tem_n=False)
        try:
            ag.desmarcar_controlado(ligada, None, pedido)
            conferir('sem N no cadastro, não inventa o valor de desmarcado', False)
        except RuntimeError as e:
            conferir('sem N no cadastro, não inventa o valor de desmarcado',
                     not escritos and 'Desmarque no Digifarma' in str(e), e)

        try:
            ag.desmarcar_controlado(ligada, None, dict(pedido, desmarcar='tudo'))
            conferir('o que desmarcar inválido é recusado', False)
        except RuntimeError:
            conferir('o que desmarcar inválido é recusado', not escritos)

        for ruim in ('13139 OR 1=1', '', 'abc'):
            try:
                ag.desmarcar_controlado(ligada, None, dict(pedido, produtoId=ruim))
                conferir('código de produto inválido é recusado (%r)' % ruim, False)
            except RuntimeError:
                conferir('código de produto inválido é recusado (%r)' % ruim, not escritos)
    finally:
        (ag.consultar, ag.executar, ag.conectar_firebird, ag.fechar,
         ag.modo_auto, ag.registrar_ajuste) = guardados

    # ------------------------------------------------------------
    # investigar um lote: Digifarma igual ao SNGPC e o app acusando
    # ------------------------------------------------------------
    ms = '1234567890123'

    def dados_lote(vendas):
        return {
            'baseDaCorrecao': 'fila',
            'envio': {'ULT_SAIDA_VENDA_NOTA_ID': 90},
            'inventario': {'data': '2026-10-15', 'lotesJaNaAnvisa': [[ms, 'A1']]},
            'pendentes': {'vendas': vendas},
            'itens': [{'descricao': 'CLONAZEPAM 2MG', 'ms': ms, 'lote': 'A1',
                       'saldoDigifarma': 10.0, 'saldoSngpc': 10.0,
                       'movimentoDesdeEnvio': -2.0, 'esperadoSngpc': 8.0,
                       'diferenca': 2.0, 'motivo': 'quantidade'}],
        }

    def explicar(dados, filtro):
        balde = io.StringIO()
        with contextlib.redirect_stdout(balde):
            ag.explicar_lote(dados, filtro)
        return balde.getvalue()

    venda_a = {'id': 100, 'data': '2026-10-15', 'ms': ms, 'lote': 'a1', 'quantidade': 2}
    venda_b = {'id': 101, 'data': '2026-10-15', 'ms': '999999999999', 'lote': 'B', 'quantidade': 1}
    saida = explicar(dados_lote([venda_a, venda_b]), 'A1')
    conferir('lote igual dos dois lados com a venda no começo da fila: aviso falso',
             'aviso FALSO' in saida and 'nº 100' in saida and 'para 100' in saida, saida)

    saida = explicar(dados_lote([dict(venda_b, id=99), venda_a]), ms + ' A1')
    conferir('lote igual com a venda no meio da fila: erro compensado por acaso',
             'compensado por acaso' in saida and 'aviso FALSO' not in saida, saida)

    saida = explicar(dados_lote([venda_a]), 'ZZ9')
    conferir('lote fora da lista do Saldo é dito, não inventado',
             'não está na lista do Saldo' in saida, saida)
    foto = dict(dados_lote([venda_a, venda_b]), baseDaCorrecao='foto')
    saida = explicar(foto, ms + '|A1')
    conferir('conta pela foto não manda acertar o ponteiro',
             'aviso FALSO' not in saida and 'busca nos XML' in saida, saida)
    entrada = {'id': 7, 'data': '2026-10-15', 'ms': ms, 'lote': 'A1', 'quantidade': 1}
    mista = dados_lote([venda_a, venda_b])
    mista['pendentes']['entradas'] = [entrada]
    saida = explicar(mista, 'A1')
    conferir('entrada do lote na fila: não afirma aviso falso pela sequência de vendas',
             'aviso FALSO' not in saida, saida)
    numerico = dados_lote([])
    numerico['itens'][0]['lote'] = '000123456789'
    conferir('lote só de dígitos vindo do app (MS|LOTE) é lote, não M.S.',
             ag.lote_procurado(numerico['itens'][0], ms + '|123456789')
             and ag.lote_procurado(numerico['itens'][0], '000123456789'), numerico['itens'][0])
    conferir('lote com zeros à esquerda casa sem eles',
             ag.lote_procurado({'ms': ms, 'lote': '00036467'}, '36467'))
    saida = explicar(dict(dados_lote([]), itens=[]), 'A1')
    conferir('Saldo vazio não vira "o lote bate"',
             'apuração falhou' in saida and 'o lote bate' not in saida, saida)
    anotado = dados_lote([venda_a, venda_b])
    ag.anotar_vereditos(anotado)
    conferir('toda sincronização grava o veredito no lote: aviso falso e o corte',
             anotado['itens'][0].get('veredito') == 'aviso_falso'
             and anotado['itens'][0].get('vereditoCorte') == 100, anotado['itens'][0])
    anotado = dados_lote([dict(venda_b, id=99), venda_a])
    ag.anotar_vereditos(anotado)
    conferir('veredito gravado no lote: compensado por acaso, sem corte',
             anotado['itens'][0].get('veredito') == 'acaso'
             and 'vereditoCorte' not in anotado['itens'][0], anotado['itens'][0])
    comum = dados_lote([venda_a])
    comum['itens'][0].update(saldoDigifarma=7.0, saldoSngpc=5.0)
    ag.anotar_vereditos(comum)
    conferir('lote com saldos diferentes não ganha veredito de "iguais"',
             'veredito' not in comum['itens'][0], comum['itens'][0])
    conferir('o resumo de pendentes mantém os próprios rótulos',
             ag.NOME_PENDENTE.get('saidas') == 'VENDAS')
    conferir('M.S. errado com o lote certo não casa',
             not ag.lote_procurado({'ms': ms, 'lote': 'A1'}, '1111111111111|A1')
             and ag.lote_procurado({'ms': ms, 'lote': 'A1'}, 'a1'))

    # ------------------------------------------------------------
    # API oficial do SNGPC: só consulta, nada de segredo na saída
    # ------------------------------------------------------------
    SENHA, EMAIL, HASH, CNPJ = 'S3nh@Secreta', 'rt@farmacia.com.br', 'A1B2C3D4E5F6', '12345678000199'
    TOKEN = 'eyJtoken.muito.secreto'
    ag.ARQUIVO_TESTE_API = os.path.join(pasta, 'api_sngpc_ultimo_teste.txt')

    def tabela_sngpc(link='https://sngpc-api.anvisa.gov.br/', senha=SENHA, cnpj_na_config=False):
        def consultar_sngpc(conexao, sql, parametros=()):
            if 'RDB$RELATION_FIELDS' in sql:
                return [{'CAMPO': c} for c in ('EMAIL', 'SENHA', 'LINK_API')
                        + (() if cnpj_na_config else ('CNPJ',))
                        + ('HASH_MOVIMENTACAO', 'HASH_INVENTARIO')]
            if sql == ag.CONSULTAS['ponteiros']:
                return [{'CNPJ': CNPJ}]
            if 'FROM SNGPC' in sql:
                return [{'EMAIL': EMAIL, 'SENHA': senha, 'LINK_API': link, 'CNPJ': CNPJ,
                         'HASH_MOVIMENTACAO': HASH, 'HASH_INVENTARIO': ''}]
            raise AssertionError(sql)
        return consultar_sngpc

    def rodar_api(respostas, carimbo_antigo=True, **kw):
        pedidos = []
        if carimbo_antigo and os.path.exists(ag.ARQUIVO_TESTE_API):
            os.remove(ag.ARQUIVO_TESTE_API)

        def chamar(metodo, url, corpo=None, token=None, timeout=30):
            pedidos.append((metodo, url, corpo, token))
            return respostas.pop(0) if respostas else (None, 'URLError: sem rede')
        guardado = ag.consultar
        ag.consultar = tabela_sngpc(**kw)
        balde = io.StringIO()
        try:
            with contextlib.redirect_stdout(balde):
                ag.testar_api_sngpc(None, chamar=chamar)
        finally:
            ag.consultar = guardado
        return balde.getvalue(), pedidos

    def sem_segredo(saida):
        return not any(x in saida for x in (SENHA, EMAIL, HASH, CNPJ, TOKEN))

    resposta_ok = json.dumps({'hash': HASH, 'dataTransmissao': '2026-10-15T07:21:00',
                              'dataValidacao': '2026-10-15T09:42:00', 'situacao': 'Aceito',
                              'mensagemValidacao': 'Paciente Maria da Silva CPF 123.456.789-09, ' + EMAIL,
                              'retorno': {'chave': 'Q2hhdmVTZWNyZXRhRGFBTlZJU0E='}})
    saida, pedidos = rodar_api([(200, json.dumps(TOKEN)), (200, resposta_ok)])
    conferir('API: com token, consulta o envio e mostra situação e datas',
             'token (POST /v1/Authentication/GetToken): recebido' in saida
             and 'Aceito' in saida and '2026-10-15T09:42:00' in saida, saida)
    conferir('API: senha, token, e-mail, CNPJ, hash e CPF não aparecem na saída',
             sem_segredo(saida) and '123.456.789-09' not in saida, saida)
    conferir('API: texto livre e objeto aninhado não são publicados (nome de paciente)',
             'Maria da Silva' not in saida and 'Q2hhdmVTZWNyZXRh' not in saida
             and 'não publicado' in saida, saida)
    conferir('API: a consulta vai com o token e ao endereço da ANVISA',
             len(pedidos) == 2 and pedidos[1][3] == TOKEN
             and all(u.startswith('https://sngpc-api.anvisa.gov.br/') for _, u, _, _ in pedidos), pedidos)

    saida, pedidos = rodar_api([(200, json.dumps(TOKEN))], carimbo_antigo=False)
    conferir('API: segundo teste em menos de 10 minutos não faz login de novo',
             not pedidos and 'Espere' in saida, saida)

    saida, pedidos = rodar_api([(403, json.dumps({'title': 'Forbidden ' + SENHA}))])
    conferir('API: recusa do login é dita, sem consultar e sem vazar a senha',
             'NÃO veio — HTTP 403' in saida and len(pedidos) == 1 and sem_segredo(saida), saida)

    saida, pedidos = rodar_api([])
    conferir('API: sem rede não quebra o relatório',
             'sem resposta' in saida and sem_segredo(saida), saida)

    saida, pedidos = rodar_api([(200, json.dumps({'token': TOKEN})), (404, '')],
                               link='https://sngpc.anvisa.gov.br.exemplo.com/roubo')
    conferir('API: LINK_API fora da ANVISA não recebe o login',
             all(u.startswith('https://sngpc-api.anvisa.gov.br/') for _, u, _, _ in pedidos)
             and 'outro endereço' in saida, pedidos)
    conferir('API: só o host exato da API recebe o login',
             ag.base_da_api('https://outro.anvisa.gov.br') == ag.API_SNGPC_PADRAO
             and ag.base_da_api('https://x@evil.com') == ag.API_SNGPC_PADRAO
             and ag.base_da_api('https://SNGPC-API.anvisa.gov.br:8443/v1') == ag.API_SNGPC_PADRAO)
    conferir('API: não segue redirecionamento (o token não vai para outro host)',
             'SemRedirecionar' in open(ag.__file__, encoding='utf-8').read())

    saida, pedidos = rodar_api([(200, json.dumps(TOKEN)), (200, resposta_ok)], cnpj_na_config=True)
    conferir('API: sem CNPJ na tabela SNGPC, usa o da CONFIG e consulta o envio',
             'CONFIG.CNPJ' in saida and len(pedidos) == 2 and CNPJ in pedidos[1][1]
             and sem_segredo(saida), saida)

    saida, pedidos = rodar_api([], senha='')
    conferir('API: sem senha guardada não chama nada', not pedidos and 'nada a testar' in saida, saida)

    shutil.rmtree(pasta, ignore_errors=True)
    print('\n%s\n' % ('%d falha(s)' % len(falhas) if falhas else 'Tudo passou.'))
    return 1 if falhas else 0


if __name__ == '__main__':
    raise SystemExit(principal())
