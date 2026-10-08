# -*- coding: utf-8 -*-
"""Tira o app.js de dentro do cache do navegador.

O repositorio antigo foi bloqueado e o app.js do projeto nao sobreviveu
a copia: o app.js do proprio Windows, de mesmo nome, sobrescreveu o
nosso. Mas o app e um PWA, entao o navegador guardou uma copia dele.

O Chrome guarda o corpo da resposta num arquivo de cache com cabecalho
binario em volta, e do jeito que o servidor mandou: pode estar cru,
em gzip, em deflate ou em brotli. Este programa varre os arquivos de
cache, tenta descomprimir de todas essas formas em cada posicao
plausivel, e grava o que contiver as marcas do nosso app.

    python ACHAR_APPJS.py                 procura sozinho no Chrome/Edge
    python ACHAR_APPJS.py PASTA [PASTA2]  procura nas pastas indicadas
"""

import gzip
import io
import os
import re
import sys
import zlib

# Marcas que so existem no nosso app.js. Qualquer uma serve.
MARCAS = [b'MOTIVO_SALDO', b'farmacia/inventario', b'ladoComparado',
          b'pintarServidor', b'tela-login', b'ponteiroSugerido']

# Nao vale a pena abrir arquivo gigante: o app.js tem dezenas de KB.
TETO = 12 * 1024 * 1024

# O corpo da resposta vem depois do cabecalho e da chave do cache, que
# cabem nos primeiros kilobytes. Procurar mais longe so custa tempo.
LIMITE_CABECALHO = 2048


def tem_marca(dados):
    return any(m in dados for m in MARCAS)


def descomprimir(bruto, pos, janela):
    """Descomprime tolerando lixo antes e depois do fluxo.

    O flush() no fim e obrigatorio: sem ele o objeto guarda o ultimo
    bloco e o arquivo sai truncado, o que e pior que nao achar nada.
    """
    obj = zlib.decompressobj(janela)
    try:
        saida = obj.decompress(bruto[pos:]) + obj.flush()
    except zlib.error:
        saida = obj.unconsumed_tail and b'' or b''
        try:
            saida = obj.flush()
        except zlib.error:
            return b''
    return saida


def tentativas(bruto):
    """Cada leitura possivel do blob: crua, gzip, zlib e deflate cru."""
    yield bruto

    # gzip: o magico 1f 8b 08 acha o inicio sem adivinhacao. Janela 31
    # para o cabecalho gzip, e nao GzipFile, que estoura no lixo do fim.
    for m in re.finditer(b'\x1f\x8b\x08', bruto):
        saida = descomprimir(bruto, m.start(), 16 + zlib.MAX_WBITS)
        if len(saida) > 1024:
            yield saida

    # zlib: o magico e um 78 seguido de byte que fecha o resto 31
    for pos, b in enumerate(bruto[:LIMITE_CABECALHO]):
        if b == 0x78 and pos + 1 < len(bruto) and (b * 256 + bruto[pos + 1]) % 31 == 0:
            saida = descomprimir(bruto, pos, zlib.MAX_WBITS)
            if len(saida) > 1024:
                yield saida

    # deflate cru nao tem magico nenhum: nao da para detectar, so tentar.
    # O corpo do cache do Chrome vem depois do cabecalho e da chave, que
    # cabem nos primeiros kilobytes, entao o alcance e limitado.
    for pos in range(LIMITE_CABECALHO):
        saida = descomprimir(bruto, pos, -zlib.MAX_WBITS)
        if len(saida) > 1024:
            yield saida

    try:
        import brotli
    except ImportError:
        return
    for pos in range(LIMITE_CABECALHO):
        try:
            saida = brotli.decompress(bruto[pos:])
        except Exception:
            continue
        if len(saida) > 1024:
            yield saida


def recortar_js(dados):
    """Corta o lixo binario em volta, mantendo o texto do script.

    O blob guardado sem compressao vem com o cabecalho e o rodape do
    cache em volta do corpo. Recorto pelo maior trecho continuo de
    texto que contenha uma das marcas: um .js nao tem caractere de
    controle no meio, entao o proprio script e esse trecho inteiro.
    """
    texto = dados.decode('utf-8', 'replace')
    pedacos = re.split(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\ufffd]+', texto)
    com_marca = [p for p in pedacos
                 if any(m.decode() in p for m in MARCAS)]
    if not com_marca:
        return texto
    return max(com_marca, key=len)


def pastas_padrao():
    local = os.environ.get('LOCALAPPDATA', '')
    achadas = []
    for navegador in [r'Google\Chrome', r'Microsoft\Edge',
                      r'BraveSoftware\Brave-Browser']:
        base = os.path.join(local, navegador, 'User Data')
        if not os.path.isdir(base):
            continue
        for perfil in os.listdir(base):
            for sub in [os.path.join('Service Worker', 'CacheStorage'),
                        os.path.join('Cache', 'Cache_Data'),
                        os.path.join('Code Cache', 'js')]:
                caminho = os.path.join(base, perfil, sub)
                if os.path.isdir(caminho):
                    achadas.append(caminho)
    return achadas


def procurar(pastas):
    achados = []
    vistos = 0
    for pasta in pastas:
        for raiz, _, arquivos in os.walk(pasta):
            for nome in arquivos:
                caminho = os.path.join(raiz, nome)
                try:
                    if os.path.getsize(caminho) > TETO:
                        continue
                    bruto = open(caminho, 'rb').read()
                except OSError:
                    continue
                vistos += 1
                for leitura in tentativas(bruto):
                    if tem_marca(leitura):
                        achados.append((caminho, recortar_js(leitura)))
                        break
    return achados, vistos


def principal(argumentos):
    pastas = argumentos or pastas_padrao()
    if not pastas:
        print('Nao achei pasta de cache de navegador nesta maquina.')
        print('Passe a pasta como argumento, se souber onde esta.')
        return 1

    print('Procurando em %d pasta(s) de cache:' % len(pastas))
    for p in pastas:
        print('  %s' % p)
    print()
    print('Isto le arquivo por arquivo e pode levar alguns minutos.')
    print()

    achados, vistos = procurar(pastas)
    print('%d arquivo(s) de cache lidos.' % vistos)

    if not achados:
        print()
        print('NAO achei o app.js em nenhum deles.')
        print()
        print('O que costuma resolver: abrir o app uma vez no navegador')
        print('deste computador, mesmo que de erro, e rodar de novo.')
        return 1

    destino = os.path.join(os.path.expanduser('~'), 'Desktop')
    if not os.path.isdir(destino):
        destino = os.getcwd()

    print()
    print('ACHEI %d copia(s):' % len(achados))
    maior = None
    for i, (origem, texto) in enumerate(sorted(
            achados, key=lambda a: -len(a[1])), 1):
        saida = os.path.join(destino, 'app-recuperado-%d.js' % i)
        with open(saida, 'w', encoding='utf-8', newline='\n') as f:
            f.write(texto)
        print('  %d) %d caracteres' % (i, len(texto)))
        print('     de:    %s' % origem)
        print('     salvo: %s' % saida)
        if maior is None:
            maior = saida

    print()
    if len(achados) > 1:
        print('Mais de uma copia: podem ser versoes diferentes. Mande todas.')
    print('Anexe no chat os arquivos app-recuperado-*.js da area de trabalho.')
    return 0


if __name__ == '__main__':
    raise SystemExit(principal(sys.argv[1:]))
