# -*- coding: utf-8 -*-
"""Instala uma chave de conta de servico recem-baixada.

O TROCAR_CHAVE_FIREBASE.bat exige a chave ATUAL para descobrir qual
conta trocar. Quando a chave atual ja foi apagada no console - que e
exatamente o momento em que mais se precisa instalar a nova - ele para
dizendo que nao achou. Mas a conta e o projeto estao dentro do proprio
JSON novo: a chave velha nunca foi necessaria para isso.

    python instalar_chave.py                 procura em Downloads
    python instalar_chave.py CAMINHO.json    usa este arquivo
"""

import datetime
import glob
import json
import os
import shutil
import sys

PROJETO = 'estoque-remedios-7b785'


def ler_config(pasta):
    caminho = os.path.join(pasta, 'agente_config.json')
    if not os.path.exists(caminho):
        return {}, caminho
    try:
        with open(caminho, encoding='utf-8') as f:
            return json.load(f), caminho
    except Exception as e:
        print('  Nao consegui ler o agente_config.json: %s' % e)
        return {}, caminho


def conferir(caminho):
    """E uma chave de conta de servico deste projeto? Devolve (ok, dados)."""
    try:
        with open(caminho, encoding='utf-8') as f:
            d = json.load(f)
    except Exception:
        return False, None
    if d.get('type') != 'service_account':
        return False, None
    if not d.get('private_key') or 'PRIVATE KEY' not in d.get('private_key', ''):
        return False, None
    if d.get('project_id') != PROJETO:
        return False, d
    return True, d


def achar_baixada():
    """A chave de conta de servico mais recente na pasta de downloads."""
    pastas = [os.path.join(os.path.expanduser('~'), 'Downloads'),
              os.path.join(os.path.expanduser('~'), 'Desktop'),
              os.getcwd()]
    achadas = []
    for pasta in pastas:
        for caminho in glob.glob(os.path.join(pasta, '*.json')):
            ok, dados = conferir(caminho)
            if ok:
                achadas.append((os.path.getmtime(caminho), caminho, dados))
    achadas.sort(reverse=True)
    return achadas


def principal(argumentos):
    pasta = os.path.dirname(os.path.abspath(__file__))
    if not os.path.exists(os.path.join(pasta, 'agente_auto.py')):
        pasta = os.getcwd()

    config, caminho_cfg = ler_config(pasta)
    destino = config.get('chave_firebase') or os.path.join(pasta, 'chave-firebase.json')
    print('Pasta do agente: %s' % pasta)
    print('A chave vai para: %s' % destino)
    if not config:
        print('  (sem agente_config.json; usando o nome padrao)')
    print()

    if argumentos:
        candidatos = []
        for a in argumentos:
            ok, dados = conferir(a)
            if ok:
                candidatos.append((0, a, dados))
            else:
                print('RECUSADO: %s nao e chave de conta de servico do projeto %s'
                      % (a, PROJETO))
    else:
        candidatos = achar_baixada()

    if not candidatos:
        print('Nao achei nenhuma chave nova em Downloads, na Area de Trabalho')
        print('nem nesta pasta.')
        print()
        print('A chave so pode ser baixada no momento em que e criada. Se a')
        print('janela foi fechada sem salvar, crie outra no console e apague')
        print('a que ficou sem uso.')
        return 1

    _, origem, dados = candidatos[0]
    print('Chave encontrada: %s' % origem)
    print('  conta:   %s' % dados.get('client_email'))
    print('  projeto: %s' % dados.get('project_id'))
    print('  codigo:  %s' % dados.get('private_key_id'))
    print()

    pasta_destino = os.path.dirname(destino)
    if pasta_destino and not os.path.isdir(pasta_destino):
        print('A pasta de destino nao existe: %s' % pasta_destino)
        return 1

    if os.path.exists(destino):
        carimbo = datetime.datetime.now().strftime('%Y-%m-%d_%H%M')
        backup = os.path.join(pasta_destino or '.',
                              'chave-firebase_antes_de_%s.json' % carimbo)
        shutil.copy2(destino, backup)
        print('A chave que estava ali foi guardada em:')
        print('  %s' % backup)

    shutil.copy2(origem, destino)
    ok, conferida = conferir(destino)
    if not ok or conferida.get('private_key_id') != dados.get('private_key_id'):
        print('FALHOU: o arquivo copiado nao confere com o de origem.')
        return 1

    print()
    print('INSTALADA.')
    print()
    print('Confira no app, aba Servidor: "Chave em uso" tem de virar')
    print('  %s' % dados.get('private_key_id'))
    print()
    print('Se o agente_config.json nao apontava para este caminho, o agente')
    print('continua lendo o antigo. O caminho que ele usa esta em:')
    print('  %s' % caminho_cfg)
    return 0


if __name__ == '__main__':
    raise SystemExit(principal(sys.argv[1:]))
