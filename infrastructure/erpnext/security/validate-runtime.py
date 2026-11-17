#!/usr/bin/env python3
"""Offline smoke/regression tests inside a disposable candidate-image container.

No site, customer data, database, network, or application-volume access needed.
Run with the candidate image's bench Python after installing its overlays.
"""
import ctypes
import ctypes.util
import importlib.metadata
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import pyexpat

import git
from lxml import etree
import openpyxl
from pypdf import PdfReader, PdfWriter


def run(*command):
    return subprocess.run(command, check=True, text=True, capture_output=True, timeout=60).stdout.strip()


def validate_system_expat():
    soname = ctypes.util.find_library('expat')
    assert soname == 'libexpat.so.1', soname
    library = ctypes.CDLL(soname)
    library.XML_ExpatVersion.restype = ctypes.c_char_p
    version = library.XML_ExpatVersion().decode('ascii')
    assert version == 'expat_2.10.0', version
    library.XML_ParserCreate.argtypes = [ctypes.c_char_p]
    library.XML_ParserCreate.restype = ctypes.c_void_p
    library.XML_Parse.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
    library.XML_Parse.restype = ctypes.c_int
    library.XML_GetErrorCode.argtypes = [ctypes.c_void_p]
    library.XML_GetErrorCode.restype = ctypes.c_int
    library.XML_ParserFree.argtypes = [ctypes.c_void_p]
    library.XML_ParserFree.restype = None
    samples = [('<invoice>தமிழ் 125</invoice>'.encode('utf-8'), True),
               ('<?xml version="1.0" encoding="UTF-16"?><invoice>125</invoice>'.encode('utf-16'), True),
               (b'<invoice><amount></invoice>', False)]
    for data, valid in samples:
        parser = library.XML_ParserCreate(None)
        assert parser
        try:
            assert (library.XML_Parse(parser, data, len(data), 1) == 1) == valid
            assert (library.XML_GetErrorCode(parser) == 0) == valid
        finally:
            library.XML_ParserFree(parser)
    loaded = sorted({line.split(maxsplit=5)[5].strip()
                     for line in Path('/proc/self/maps').read_text().splitlines()
                     if '/libexpat.so.1' in line})
    system_path = Path('/usr/lib/aarch64-linux-gnu/libexpat.so.1').resolve(strict=True)
    assert str(system_path) in loaded, (system_path, loaded)
    python_links = run('ldd', pyexpat.__file__)
    assert pyexpat.version_info == (2, 10, 0), pyexpat.EXPAT_VERSION
    assert 'libexpat.so.1 =>' in python_links, python_links
    return {'status': 'passed', 'soname': soname, 'system_version': version,
            'system_library': str(system_path), 'loaded_system_libraries': loaded,
            'ordinary_xml_checks': ['UTF-8', 'UTF-16', 'malformed XML rejected'],
            'pyexpat_version': pyexpat.EXPAT_VERSION, 'pyexpat_module': pyexpat.__file__,
            'pyexpat_ldd': python_links,
            'scope': 'System Expat API and rebuilt Python parser both report 2.10.0; Python links system libexpat.so.1. Paired upstream-tested module receipt is retained separately.'}


def validate_postgresql_client():
    library = ctypes.CDLL('libpq.so.5')
    library.PQlibVersion.restype = ctypes.c_int
    assert library.PQlibVersion() == 170012
    library.PQconninfoParse.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]
    library.PQconninfoParse.restype = ctypes.c_void_p
    library.PQconninfoFree.argtypes = [ctypes.c_void_p]
    library.PQconninfoFree.restype = None
    error = ctypes.c_char_p()
    options = library.PQconninfoParse(b'host=localhost port=5432 dbname=synthetic sslmode=verify-full', ctypes.byref(error))
    assert options and not error.value
    library.PQconninfoFree(options)
    version = run('/usr/lib/postgresql/17/bin/psql', '--version')
    assert '17.12' in version, version
    links = run('ldd', '/usr/lib/aarch64-linux-gnu/libpq.so.5')
    assert 'not found' not in links
    return {'version': version, 'library_version': 170012, 'linked_libraries': links,
            'checks': ['libpq connection-options parser', 'psql version'], 'database_connections': 0}


def main():
    assert importlib.metadata.version('GitPython') == '3.2.1'
    assert importlib.metadata.version('pypdf') == '6.21.4'
    assert importlib.metadata.version('lxml') == '6.1.3'
    assert etree.LIBXML_VERSION == etree.LIBXML_COMPILED_VERSION == (2, 15, 4)
    assert etree.LIBXSLT_VERSION == etree.LIBXSLT_COMPILED_VERSION == (1, 1, 45)
    assert run('/home/frappe/frappe-bench/apps/frappe/node_modules/esbuild/bin/esbuild', '--version') == '0.14.54'
    esbuild_result = json.loads(run('node', '-e', '''
const assert = require('node:assert/strict');
const esbuild = require('/home/frappe/frappe-bench/apps/frappe/node_modules/esbuild');
assert.equal(esbuild.version, '0.14.54');
const result = esbuild.transformSync('export const quantity = 6 * 7;', {format:'cjs',minify:true});
const module = {exports:{}};
new Function('module','exports',result.code)(module,module.exports);
assert.equal(module.exports.quantity,42);
const css = esbuild.transformSync('.order { color: red; }',{loader:'css',minify:true});
assert.equal(css.code.trim(),'.order{color:red}');
console.log(JSON.stringify({version:esbuild.version,javascript:42,css:css.code.trim()}));
'''))
    browser = '/home/frappe/frappe-bench/chromium/chrome-linux/headless_shell'
    browser_version = run(browser, '--version')
    assert '157.0.8103.78' in browser_version
    # Actual dependents of system libxml2 must remain loadable after the
    # backport. Symbol retention by itself is not a complete ABI check.
    ctypes.CDLL('libLLVM.so.19.1')
    ctypes.CDLL('libgbm.so.1')
    assert etree.fromstring(b'<invoice><amount currency="INR">125</amount></invoice>')[0].text == '125'
    result = {'status': 'passed', 'browser': browser_version, 'lxml_libxml': etree.LIBXML_VERSION,
              'expat': validate_system_expat(), 'postgresql': validate_postgresql_client(), 'esbuild': esbuild_result}
    with tempfile.TemporaryDirectory(prefix='erp-runtime-regression-') as temporary:
        temporary = Path(temporary)
        repo = git.Repo.init(temporary / 'git')
        (temporary / 'git/fixture.txt').write_text('synthetic security validation\n')
        repo.index.add(['fixture.txt'])
        actor = git.Actor('Synthetic test', 'test@localhost')
        commit = repo.index.commit('Synthetic commit', author=actor, committer=actor)
        assert repo.commit(commit.hexsha).message == 'Synthetic commit'
        book = openpyxl.Workbook()
        book.active.append(['Invoice', 125.5])
        book.save(temporary / 'invoice.xlsx')
        assert openpyxl.load_workbook(temporary / 'invoice.xlsx').active['B1'].value == 125.5
        writer = PdfWriter()
        writer.add_blank_page(width=100, height=200)
        buffer = io.BytesIO()
        writer.write(buffer)
        assert len(PdfReader(buffer).pages) == 1
        html = temporary / 'fixture.html'
        html.write_text('''<!doctype html><meta charset="utf-8"><title>Security regression</title>
<style>body { font-family: sans-serif } svg { width: 180px; height: 80px }</style>
<h1>ERP synthetic invoice</h1><p>Invoice total INR 125.50</p>
<p>தமிழ் — العربية</p><svg xmlns="http://www.w3.org/2000/svg"><rect width="100" height="60" fill="#24705a"/><text x="4" y="30">SVG fixture</text></svg>''')
        pdf = temporary / 'chrome.pdf'
        run(browser, '--headless', '--no-sandbox', '--disable-dev-shm-usage', '--no-pdf-header-footer', '--print-to-pdf=' + str(pdf), html.as_uri())
        chrome_text = '\n'.join(page.extract_text() for page in PdfReader(pdf).pages)
        assert 'ERP synthetic invoice' in chrome_text and '125.50' in chrome_text and 'SVG fixture' in chrome_text
        # Frappe's PDFKit subclass must ignore attacker-supplied meta options.
        from frappe.utils.pdf import FrappePDFKit
        import pdfkit
        executable = shutil.which('wkhtmltopdf')
        assert executable
        sentinel = temporary / 'private-synthetic.txt'
        sentinel.write_text('SYNTHETIC_PRIVATE_SENTINEL_9277')
        payload = '<meta name="pdfkit-enable-local-file-access" content=""><h1>Safe PDF</h1><iframe src="' + sentinel.as_uri() + '"></iframe>'
        kit = FrappePDFKit(payload, 'string', options={'disable-local-file-access': '', 'disable-javascript': '', 'quiet': ''}, configuration=pdfkit.configuration(wkhtmltopdf=executable))
        assert 'enable-local-file-access' not in kit.options
        command = kit.command()
        assert '--disable-local-file-access' in command and '--disable-javascript' in command
        # wkhtmltopdf may report blocked local access as nonzero; inspect its
        # PDF only when the expected output exists and has a valid header.
        completed = subprocess.run(command, input=payload.encode(), capture_output=True, timeout=60)
        assert completed.stdout.startswith(b'%PDF-')
        rendered = '\n'.join(page.extract_text() for page in PdfReader(io.BytesIO(completed.stdout)).pages)
        assert 'Safe PDF' in rendered and 'SYNTHETIC_PRIVATE_SENTINEL_9277' not in rendered
        result['checks'] = ['GitPython commit', 'XLSX roundtrip', 'XML parse', 'PDF writer/reader', 'LLVM/Mesa load', 'Chrome HTML/SVG PDF', 'Frappe PDF meta-option guard', 'wkhtmltopdf local-file isolation']
    print(json.dumps(result))


if __name__ == '__main__':
    main()
