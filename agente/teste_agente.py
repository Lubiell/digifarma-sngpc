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
    conferir('lote que bate não vira divergência',
             diferencas.get('1057306610050') == 0.0, diferencas)

    conferir('vendas pendentes saem pelo ponteiro, não por data',
             dados['resumoPendentes']['vendas'] == 1, dados['resumoPendentes'])
    conferir('entradas pendentes saem pelo ponteiro',
             dados['resumoPendentes']['entradas'] == 1, dados['resumoPendentes'])

    fora = [c for c in dados.get('conferencia_xml', []) if c['situacao'] == 'fora_do_xml']
    conferir('venda que não subiu no XML vira divergência',
             any(c['ms'] == '1999900090011' for c in fora), fora)
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

    shutil.rmtree(pasta, ignore_errors=True)
    print('\n%s\n' % ('%d falha(s)' % len(falhas) if falhas else 'Tudo passou.'))
    return 1 if falhas else 0


if __name__ == '__main__':
    raise SystemExit(principal())
