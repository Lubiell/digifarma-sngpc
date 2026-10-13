"""Gera laboratorios.json: o laboratório de cada registro M.S., pela ANVISA.

O Digifarma desta farmácia não entrega o laboratório em coluna que o agente
ache. O próprio registro M.S. entrega: os dígitos 2 a 5 são o número da
empresa detentora na ANVISA (1.0235 é a EMS, 1.0573 o Aché). A tabela sai
dos dados abertos da ANVISA, a mesma fonte da consulta pública de registro.

Uso (da pasta do app):
    python ferramentas/gerar_laboratorios.py DADOS_ABERTOS_MEDICAMENTOS.csv

O CSV se baixa em
https://dados.anvisa.gov.br/dados/DADOS_ABERTOS_MEDICAMENTOS.csv

Saída: {"empresas": {"0235": "EMS S/A", ...}, "registros": {"1234567890": ...}}
"registros" só traz os registros de números de empresa que a ANVISA já deu a
mais de um nome (incorporação, troca de razão social): ali o número da
empresa sozinho não decide, e o registro inteiro decide.
"""
import collections
import csv
import json
import os
import sys


def nome_da_empresa(campo):
    # "57507378000365 - EMS S/A" -> "EMS S/A"
    return campo.split(' - ', 1)[-1].strip()


def gerar(caminho_csv):
    por_empresa = collections.defaultdict(collections.Counter)
    por_registro = {}
    with open(caminho_csv, encoding='latin-1', newline='') as f:
        for linha in csv.DictReader(f, delimiter=';'):
            registro = (linha.get('NUMERO_REGISTRO_PRODUTO') or '').strip()
            nome = nome_da_empresa(linha.get('EMPRESA_DETENTORA_REGISTRO') or '')
            if not registro.isdigit() or not nome:
                continue
            registro = registro.zfill(9)
            por_empresa[registro[1:5]][nome] += 1
            por_registro[registro] = nome
    empresas = {c: n.most_common(1)[0][0] for c, n in sorted(por_empresa.items())}
    ambiguas = {c for c, n in por_empresa.items() if len(n) > 1}
    registros = {r: n for r, n in sorted(por_registro.items())
                 if r[1:5] in ambiguas and n != empresas[r[1:5]]}
    return {'fonte': 'ANVISA, dados abertos de medicamentos',
            'empresas': empresas, 'registros': registros}


def principal():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    dados = gerar(sys.argv[1])
    destino = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           'laboratorios.json')
    with open(destino, 'w', encoding='utf-8') as f:
        json.dump(dados, f, ensure_ascii=False, separators=(',', ':'))
    print('%s: %d empresas, %d registros com nome próprio'
          % (destino, len(dados['empresas']), len(dados['registros'])))
    return 0


if __name__ == '__main__':
    sys.exit(principal())
