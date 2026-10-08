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
import struct
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
LIMITE_CABECALHO = 1024

# Quanto descomprimir so para sondar se vale descomprimir o resto.
SONDA = 64 * 1024

# Blob menor que isto nao cabe um app.js, nem comprimido.
PISO = 2048

# Cabecalho do Simple Cache do Chrome: uint64 magico, uint32 versao,
# uint32 tamanho da chave, uint32 hash. A chave e a URL, e logo depois
# dela comeca o corpo. Com isso o inicio do corpo e uma conta, nao uma
# adivinhacao - foi tentar adivinhar que travou a maquina da loja.
MAGICO_CHROME = 0xfcfb6d1ba7725c30
LIMITE_CEGO = 256


def tem_marca(dados):
    return any(m in dados for m in MARCAS)


def descomprimir(vista, pos, janela, teto=None):
    """Descomprime a partir de pos, tolerando lixo antes e depois.

    Recebe memoryview, nao bytes: fatiar bytes copia o buffer inteiro a
    cada chamada, e com milhares de posicoes por arquivo isso nunca
    termina. Foi o que travou a primeira versao na maquina da loja.

    O flush() no fim e obrigatorio: sem ele o objeto segura o ultimo
    bloco e o arquivo sai truncado, o que e pior que nao achar nada.
    Com teto, so descomprime o inicio, para sondar barato.
    """
    obj = zlib.decompressobj(janela)
    try:
        if teto:
            return obj.decompress(vista[pos:], teto)
        return obj.decompress(vista[pos:]) + obj.flush()
    except zlib.error:
        try:
            return obj.flush()
        except zlib.error:
            return b''


def posicoes_com_magico(vista):
    """Onde comeca um fluxo gzip ou zlib. Barato e confiavel."""
    bruto = bytes(vista[:LIMITE_CABECALHO + 64])
    for m in re.finditer(b'\x1f\x8b\x08', bruto):
        yield m.start(), 16 + zlib.MAX_WBITS
    for pos in range(len(bruto) - 1):
        if bruto[pos] == 0x78 and (bruto[pos] * 256 + bruto[pos + 1]) % 31 == 0:
            yield pos, zlib.MAX_WBITS


def corpo_pelo_cabecalho(bruto):
    """Onde o corpo comeca, segundo o cabecalho do Simple Cache."""
    if len(bruto) < 24:
        return []
    magico, versao, tam_chave, _ = struct.unpack_from('<QIII', bruto, 0)
    if magico != MAGICO_CHROME or not 0 < tam_chave < 8192:
        return []
    # o cabecalho tem 20 bytes de campos; o compilador costuma alinhar
    # em 24. Devolvo os dois, que custam uma tentativa cada.
    return [p for p in (20 + tam_chave, 24 + tam_chave) if p < len(bruto)]


def url_do_cache(bruto):
    """A chave guardada e a URL. Util para dizer de onde veio."""
    if len(bruto) < 24:
        return ''
    magico, _, tam_chave, _ = struct.unpack_from('<QIII', bruto, 0)
    if magico != MAGICO_CHROME or not 0 < tam_chave < 8192:
        return ''
    for inicio in (20, 24):
        try:
            chave = bruto[inicio:inicio + tam_chave].decode('utf-8')
        except UnicodeDecodeError:
            continue
        if chave.startswith('http') or '://' in chave:
            return chave
    return ''


def tentativas(bruto, vista, fundo):
    """Leituras possiveis do blob.

    Sem fundo: o blob cru, os fluxos com magico, e o inicio do corpo que
    o cabecalho do Chrome aponta. Com fundo: tambem tentativa cega, em
    alcance curto, para o caso de o arquivo nao ter cabecalho conhecido.
    """
    # o blob cru vai como bytes: memoryview nao faz busca de
    # subsequencia, entao 'marca in vista' nao procura nada. Quando o
    # cabecalho diz onde o corpo comeca, corto antes: senao a chave,
    # que e a URL, entra colada no inicio do arquivo recuperado.
    inicio = corpo_pelo_cabecalho(bruto)
    yield bruto[inicio[0]:] if inicio else bruto

    for pos, janela in posicoes_com_magico(vista):
        saida = descomprimir(vista, pos, janela)
        if len(saida) > 1024:
            yield saida

    for pos in corpo_pelo_cabecalho(bruto):
        for janela in (-zlib.MAX_WBITS, zlib.MAX_WBITS, 16 + zlib.MAX_WBITS):
            saida = descomprimir(vista, pos, janela)
            if len(saida) > 1024:
                yield saida

    if not fundo:
        return

    for pos in range(min(LIMITE_CEGO, len(vista))):
        sonda = descomprimir(vista, pos, -zlib.MAX_WBITS, teto=SONDA)
        if len(sonda) < 512 or not tem_marca(sonda):
            continue
        saida = descomprimir(vista, pos, -zlib.MAX_WBITS)
        if len(saida) > 1024:
            yield saida

    try:
        import brotli
    except ImportError:
        return
    for pos in list(corpo_pelo_cabecalho(bruto)) + list(range(32)):
        try:
            saida = brotli.decompress(vista[pos:])
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


def listar(pastas):
    todos = []
    for pasta in pastas:
        for raiz, _, arquivos in os.walk(pasta):
            for nome in arquivos:
                caminho = os.path.join(raiz, nome)
                try:
                    tamanho = os.path.getsize(caminho)
                except OSError:
                    continue
                if PISO <= tamanho <= TETO:
                    todos.append(caminho)
    return todos


def procurar(arquivos, fundo, rotulo):
    """Varre os arquivos. fundo=False e a passada barata."""
    achados = []
    total = len(arquivos)
    marco = max(total // 20, 1)
    print('  %s: %d arquivo(s)' % (rotulo, total))
    for i, caminho in enumerate(arquivos, 1):
        if i % marco == 0 or i == total:
            print('    %d%%  (%d de %d)' % (i * 100 // total, i, total))
            sys.stdout.flush()
        try:
            bruto = open(caminho, 'rb').read()
        except OSError:
            continue
        vista = memoryview(bruto)
        for leitura in tentativas(bruto, vista, fundo):
            if tem_marca(leitura):
                achados.append((caminho, recortar_js(leitura)))
                break
    return achados


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

    arquivos = listar(pastas)
    if not arquivos:
        print('Nenhum arquivo de cache nessas pastas.')
        return 1

    print('Passada 1 de 2 - a rapida, que resolve quase sempre.')
    achados = procurar(arquivos, False, 'lendo cru e os fluxos com magico')

    if not achados:
        print()
        print('Passada 2 de 2 - a lenta, tentando deflate sem magico.')
        achados = procurar(arquivos, True, 'tentativa posicao por posicao')

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
