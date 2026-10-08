# -*- coding: utf-8 -*-
"""Confere os tropecos de .bat que ja quebraram este projeto antes.

Cada checagem aqui existe porque a falha correspondente aconteceu de
verdade: .bat gravado com LF perdendo os rotulos de goto, parenteses
dentro de bloco abortando o script, "^|" chegando literal dentro de
aspas, e "(S/N)" fechando o if no meio da pergunta.
"""
import glob
import re
import sys

ALVOS = sorted(glob.glob('agente/*.bat')) + sorted(glob.glob('*.bat'))


def sem_comentario(linha):
    corte = re.match(r'\s*(rem|::)\s', linha, re.I)
    return '' if corte else linha


def checar(nome, bruto):
    falhas = []
    linhas = bruto.split('\r\n')

    # 1. CRLF em toda linha. LF sozinho faz o CMD perder rotulo de goto.
    if bruto.count(b'\n'.decode()) != bruto.count('\r\n'):
        falhas.append('tem linha com LF sozinho')

    # 2. todo goto aponta para rotulo que existe
    rotulos = {m.group(1).upper() for m in re.finditer(r'(?m)^\s*:(\w+)', bruto)}
    for m in re.finditer(r'(?i)\bgoto\s+(\w+)', bruto):
        if m.group(1).upper() not in rotulos and m.group(1).lower() != 'eof':
            falhas.append('goto %s sem rotulo' % m.group(1))

    # 3. "^|" dentro de aspas chega literal, nao escapado
    for n, linha in enumerate(linhas, 1):
        for trecho in re.findall(r'"[^"]*"', sem_comentario(linha)):
            if '^|' in trecho:
                falhas.append('linha %d: ^| dentro de aspas' % n)

    # 4. (S/N) fecha o bloco do if no meio da pergunta. Entre aspas e no
    #    nivel de cima o CMD aguenta; dentro de bloco, ou solto, quebra.
    pergunta = re.compile(r'\(\s*[SsNn]\s*/\s*[SsNn]\s*\)')
    prof_sn = 0
    for n, linha in enumerate(linhas, 1):
        limpa = sem_comentario(linha)
        if pergunta.search(limpa):
            protegida = not pergunta.search(re.sub(r'"[^"]*"', '', limpa))
            # no nivel de cima um echo so imprime: nao ha bloco para
            # fechar. Dentro de bloco, ou num set /p solto, quebra.
            so_texto = prof_sn == 0 and re.match(r'\s*echo\b', limpa, re.I)
            if not so_texto and (prof_sn > 0 or not protegida):
                falhas.append('linha %d: (S/N) em lugar que quebra o CMD' % n)
        if not re.match(r'\s*echo\b', limpa, re.I):
            fora = re.sub(r'"[^"]*"', '', re.sub(r'\^.', '', limpa))
            prof_sn = max(prof_sn + fora.count('(') - fora.count(')'), 0)

    # 5. ! exige delayed expansion ligado
    if re.search(r'![A-Za-z_]\w*!', bruto) and 'enabledelayedexpansion' not in bruto.lower():
        falhas.append('usa !var! sem enabledelayedexpansion')

    # 6. parentese cru em echo dentro de bloco aborta o bloco
    profundidade = 0
    for n, linha in enumerate(linhas, 1):
        limpa = sem_comentario(linha)
        if profundidade > 0 and re.match(r'\s*echo\b', limpa, re.I):
            cru = re.sub(r'\^.', '', limpa)
            if '(' in cru or ')' in cru:
                falhas.append('linha %d: parentese cru em echo dentro de bloco' % n)
        # echo consome o resto da linha: no nivel de cima os parenteses
        # dele sao texto e nao abrem bloco. Contar faria a profundidade
        # das linhas seguintes andar errada.
        if not re.match(r'\s*echo\b', limpa, re.I):
            fora_de_aspas = re.sub(r'"[^"]*"', '', re.sub(r'\^.', '', limpa))
            profundidade += fora_de_aspas.count('(') - fora_de_aspas.count(')')
            profundidade = max(profundidade, 0)

    # 7. apagar com curinga, ou rmdir /s em caminho fixo, varre o que
    #    nao era para varrer. Apagar arquivo proprio, nomeado, pode.
    for n, linha in enumerate(linhas, 1):
        limpa = sem_comentario(linha)
        if not re.search(r'(?im)^\s*(if\s+[^&|]*?\s)?(del|rmdir|rd)\s', limpa):
            continue
        alvo = limpa[re.search(r'(?i)\b(del|rmdir|rd)\s', limpa).end():]
        if re.search(r'[*?]', alvo):
            falhas.append('linha %d: apaga com curinga' % n)
        elif re.search(r'(?i)\b(rmdir|rd)\b', limpa) and '/s' in limpa.lower() and '%' not in alvo:
            falhas.append('linha %d: rmdir /s em caminho fixo' % n)

    # 7b. skip=0 nao existe: o for /f exige 1 ou mais e aborta a linha
    #     com "delims=" foi inesperado neste momento". Quebrou de verdade
    #     no LIMPAR.bat, e o efeito era silencioso: os padroes que
    #     guardam zero arquivos nunca eram listados.
    for n, linha in enumerate(linhas, 1):
        if re.search(r'(?i)skip=0\b', sem_comentario(linha)):
            falhas.append('linha %d: for /f com skip=0, que o CMD recusa' % n)

    # 8. curl sempre com -f, senao pagina de erro do GitHub passa como
    #    sucesso e sobrescreve o agente. So vale para curl INVOCADO: a
    #    palavra dentro de um echo e texto na tela, nao comando.
    for n, linha in enumerate(linhas, 1):
        limpa = sem_comentario(linha)
        chamada = re.search(r'(?i)(?:^|[&|(]|\bcall\s+|\bdo\s+)\s*"?curl"?\s', limpa)
        if not chamada:
            continue
        flags = re.findall(r'(?<!\S)-{1,2}([a-zA-Z-]+)', limpa[chamada.end():])
        if not any('f' in g or g == 'fail' for g in flags):
            falhas.append('linha %d: curl sem -f' % n)

    return falhas


def checar_ordem(bruto):
    """A chave tem de sair da copia ANTES do zip fechar."""
    tira = bruto.lower().find('private key')
    fecha = bruto.lower().find('tar -a -c -f')
    if tira < 0 or fecha < 0:
        return ['nao achei o passo da chave ou o passo do zip']
    if tira > fecha:
        return ['o zip fecha ANTES de tirar a chave da copia']
    return []


# caminhos que nunca podem entrar no repositorio. O .gitignore que os
# barrava ja se perdeu uma vez, por um comando que falhou antes de
# grava-lo, e o commit seguinte afirmou uma protecao que nao existia.
PROIBIDOS = [
    'agente/agente_config.json',
    'agente/chave-firebase.json',
    'agente/estoque-remedios-7b785-firebase-adminsdk-fbsvc-46c4f55041.json',
    'agente/sngpc_VisualizaArquivoXML.xml',
    'agente/agente.log',
]
LIBERADOS = [
    'agente/agente_auto.py',
    'agente/mapa_xml.py',
    'agente/regras-firebase.json',
    'agente/exemplo_SNGPC.XML',
]


def conferir_gitignore():
    """Credencial e dado de paciente barrados; codigo passando."""
    import subprocess
    falhas = []

    def barrado(caminho):
        # --no-index e obrigatorio: sem ele o check-ignore cala sobre
        # arquivo ja rastreado, e a metade 'liberados' deste teste
        # nunca acusaria nada.
        return subprocess.run(
            ['git', 'check-ignore', '-q', '--no-index', caminho]).returncode == 0

    for caminho in PROIBIDOS:
        if not barrado(caminho):
            falhas.append('o .gitignore NAO barra %s' % caminho)
    for caminho in LIBERADOS:
        if barrado(caminho):
            falhas.append('o .gitignore barra o codigo %s' % caminho)
    for f in falhas:
        print('  FALHA .gitignore: %s' % f)
    if not falhas:
        print('  OK    .gitignore (%d barrados, %d liberados)' % (len(PROIBIDOS), len(LIBERADOS)))
    return falhas


# A URL do repositorio estava em seis lugares, em quatro arquivos. Quando
# a conta antiga foi bloqueada, cada um deles virou um 404 para consertar
# a mao. Agora cada arquivo declara a base uma vez, e os quatro tem de
# concordar: trocar de repositorio passa a ser quatro linhas, nao seis
# lugares para procurar.
ARQUIVOS_COM_URL = [
    'agente/agente_auto.py',
    'agente/ATUALIZAR_AGENTE.bat',
    'agente/CONSERTAR_TUDO.bat',
    'agente/SERVIDOR_AGORA.bat',
    'agente/APONTAR_SERVIDOR.bat',
    'ACHAR_APPJS.bat',
    'agente/INSTALAR_CHAVE.bat',
]
BASE = re.compile(r'raw\.githubusercontent\.com/([^/\s"\']+)/([^/\s"\']+)')


def conferir_url_do_repositorio():
    """Uma base por arquivo, e todas apontando para o mesmo repositorio."""
    falhas = []
    donos = {}
    for nome in ARQUIVOS_COM_URL:
        try:
            bruto = open(nome, encoding='cp1252' if nome.endswith('.bat') else 'utf-8',
                         newline='').read()
        except FileNotFoundError:
            falhas.append('%s nao existe' % nome)
            continue
        achados = []
        for linha in bruto.replace('\r\n', '\n').split('\n'):
            achados += BASE.findall(sem_comentario(linha))
        if not achados:
            falhas.append('%s nao declara a base do repositorio' % nome)
            continue
        if len(achados) > 1:
            falhas.append('%s repete a base %d vezes; devia declarar uma' % (nome, len(achados)))
        donos[nome] = achados[0]

    distintos = set(donos.values())
    if len(distintos) > 1:
        falhas.append('arquivos apontando para repositorios diferentes: %s' % sorted(
            '%s -> %s/%s' % (n, d[0], d[1]) for n, d in sorted(donos.items())))

    for f in falhas:
        print('  FALHA url do repositorio: %s' % f)
    if not falhas:
        dono = '/'.join(distintos.pop())
        print('  OK    url do repositorio (%d arquivos, todos em %s)' % (len(donos), dono))
    return falhas


def conferir_protocolo_do_app():
    """O que o app pede, o agente atende?

    Quase entrou um botao "Acertar o ponteiro" mandando acao
    'acertar_ponteiro', que o agente nao conhece: o pedido ficaria para
    sempre em farmacia/comando e a tela diria "na fila" sem nada
    acontecer. Botao que nao faz nada e pior que botao nenhum, porque
    ninguem descobre. O certo era acao 'config' com chave
    'transmitido_ate_venda', que ja existia.
    """
    falhas = []
    try:
        agente = open('agente/agente_auto.py', encoding='utf-8').read()
        app = open('app.js', encoding='utf-8').read()
    except FileNotFoundError as e:
        print('  -- protocolo do app: %s, pulando' % e.filename)
        return []

    aceitas = set(re.findall(r"acao == '([a-z_]+)'", agente))
    for grupo in re.findall(r"acao in \(([^)]+)\)", agente):
        aceitas |= set(re.findall(r"'([a-z_]+)'", grupo))
    # Os botoes das ferramentas declaram a acao dentro de um array, nao
    # num campo acao:. Sem ler ACOES_SERVIDOR esta checagem fica cega
    # justamente para os botoes novos - foi o que aconteceu.
    def da_lista(nome):
        m = re.search(r"const %s = \[(.*?)\n\];" % nome, app, re.S)
        return set(re.findall(r"\[\s*'([a-z_]+)'", m.group(1))) if m else set()

    mandadas = (set(re.findall(r"acao: '([a-z_]+)'", app))
                | set(re.findall(r"pedirAoAgente\('([a-z_]+)'", app))
                | da_lista('ACOES_SERVIDOR'))
    relatorios_app = da_lista('RELATORIOS_SERVIDOR')
    relatorios_agente = set(re.findall(r"^\s+'([a-z_]+)': lambda config, alvo",
                                       agente, re.M))
    for fora in sorted(relatorios_app - relatorios_agente):
        falhas.append("o app pede o relatorio '%s' e o agente nao tem" % fora)
    for orfa in sorted(mandadas - aceitas):
        falhas.append("o app manda a acao '%s' e o agente nao atende" % orfa)

    # CONFIG_REMOTO nao e a lista toda: aplicar_config trata
    # permitir_ajuste_estoque num caso proprio, que retorna antes de
    # consultar o dicionario. Exigir so o dicionario acusaria o app por
    # usar um caminho que o agente tem de proposito.
    permitidas = (set(re.findall(r"'([a-z_]+)': '(?:inteiro|texto|modo)'", agente))
                  | set(re.findall(r"if chave == '([a-z_]+)'", agente)))
    pedidas = set(re.findall(r"chave: '([a-z_]+)'", app))
    for fora in sorted(pedidas - permitidas):
        falhas.append("o app pede a chave de config '%s', fora de CONFIG_REMOTO" % fora)

    for f in falhas:
        print('  FALHA protocolo do app: %s' % f)
    if not falhas:
        print('  OK    protocolo do app (%d acao(oes), %d relatorio(s), %d chave(s))'
              % (len(mandadas), len(relatorios_app), len(pedidas)))
    return falhas


def conferir():
    total = (list(conferir_gitignore()) + list(conferir_url_do_repositorio())
             + list(conferir_protocolo_do_app()))
    for nome in ALVOS:
        try:
            bruto = open(nome, encoding='cp1252', newline='').read()
        except FileNotFoundError:
            print('  -- %s nao existe, pulando' % nome)
            continue
        falhas = checar(nome, bruto)
        if nome == 'SALVAR_TUDO.bat':
            falhas += checar_ordem(bruto)
        if falhas:
            for f in falhas:
                print('  FALHA %s: %s' % (nome, f))
            total += falhas
        else:
            print('  OK    %s' % nome)
    return total


if __name__ == '__main__':
    print('conferindo os .bat')
    ruim = conferir()
    print()
    if ruim:
        print('%d FALHA(S)' % len(ruim))
        sys.exit(1)
    print('tudo passou')
