# -*- coding: utf-8 -*-
"""Confere os tropecos de .bat que ja quebraram este projeto antes.

Cada checagem aqui existe porque a falha correspondente aconteceu de
verdade: .bat gravado com LF perdendo os rotulos de goto, parenteses
dentro de bloco abortando o script, "^|" chegando literal dentro de
aspas, e "(S/N)" fechando o if no meio da pergunta.
"""
import re
import sys

ALVOS = ['SALVAR_TUDO.bat', 'RECUPERAR_FARMACIA.bat', 'BACKUP_AGENTE.bat']


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

    # 4. (S/N) fecha o bloco do if no meio da pergunta
    for n, linha in enumerate(linhas, 1):
        if re.search(r'\(\s*[SsNn]\s*/\s*[SsNn]\s*\)', sem_comentario(linha)):
            falhas.append('linha %d: usa (S/N) em vez de [S/N]' % n)

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

    # 7. del/rmdir so na pasta e no zip que o proprio script cria
    for n, linha in enumerate(linhas, 1):
        limpa = sem_comentario(linha)
        if re.search(r'(?i)\b(del|rmdir|rd)\b', limpa):
            if '%DESTINO%' not in limpa and '%ZIP%' not in limpa and '%%A' not in limpa:
                falhas.append('linha %d: del/rmdir fora do destino' % n)

    # 8. curl sempre com -f, senao erro de HTTP passa como sucesso
    for n, linha in enumerate(linhas, 1):
        limpa = sem_comentario(linha)
        if re.search(r'(?i)\bcurl\b', limpa) and not re.search(r'(?i)curl[^\r\n]*\s-[a-zA-Z]*f', limpa):
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


def conferir():
    total = []
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
