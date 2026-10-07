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
            if prof_sn > 0 or not protegida:
                falhas.append('linha %d: (S/N) em lugar que quebra o CMD' % n)
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


def conferir():
    total = list(conferir_gitignore()) + list(conferir_url_do_repositorio())
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
