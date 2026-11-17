#!/usr/bin/env python3
"""Ordinary synthetic XML, spreadsheet and PDF checks for the rebuilt wheel."""
import io
import json
from pathlib import Path
import subprocess
import tempfile

from lxml import etree
import openpyxl
from pypdf import PdfReader, PdfWriter


def main():
    assert etree.LXML_VERSION[:3] == (6, 1, 3), etree.LXML_VERSION
    assert etree.LIBXML_VERSION == etree.LIBXML_COMPILED_VERSION == (2, 15, 4)
    assert etree.LIBXSLT_VERSION == etree.LIBXSLT_COMPILED_VERSION == (1, 1, 45)
    xml = etree.fromstring('<order><quantity>12</quantity><name>தமிழ்</name></order>'.encode())
    assert xml.xpath('sum(quantity)') == 12
    assert etree.fromstring(etree.tostring(xml)).findtext('name') == 'தமிழ்'
    style = etree.XML(b'''<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
      <xsl:template match="/"><summary><xsl:value-of select="order/quantity"/></summary></xsl:template>
    </xsl:stylesheet>''')
    transformed = etree.XSLT(style)(xml)
    assert transformed.getroot().text == '12'
    schema = etree.XMLSchema(etree.XML(b'''<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="summary" type="xs:integer"/>
    </xs:schema>'''))
    schema.assertValid(transformed)
    with tempfile.TemporaryDirectory(prefix='erp-lxml-ordinary-') as temporary:
        path = Path(temporary)/'synthetic.xlsx'
        workbook = openpyxl.Workbook()
        workbook.active.append(['Synthetic order', 12, 'தமிழ்'])
        workbook.save(path)
        restored = openpyxl.load_workbook(path)
        assert list(restored.active.values) == [('Synthetic order', 12, 'தமிழ்')]
        restored.close()
    pdf = io.BytesIO()
    writer = PdfWriter(); writer.add_blank_page(width=144, height=144)
    writer.add_metadata({'/Title': transformed.getroot().text}); writer.write(pdf)
    pdf.seek(0); reader = PdfReader(pdf)
    assert len(reader.pages) == 1 and reader.metadata.title == '12'
    linked = subprocess.check_output(['ldd', etree.__file__], text=True)
    assert 'not found' not in linked
    # Private static dependencies must not accidentally bind to the older OS XML library.
    assert not any(name in linked for name in ('libxml2.so', 'libxslt.so', 'libexslt.so', 'libz.so', 'libiconv.so')), linked
    print(json.dumps({'status': 'passed', 'lxml': etree.LXML_VERSION,
        'libxml2': etree.LIBXML_VERSION, 'libxslt': etree.LIBXSLT_VERSION,
        'features': sorted(getattr(etree, 'LIBXML_FEATURES', [])), 'extension': etree.__file__,
        'linked_libraries': linked,
        'checks': ['UTF-8 XML', 'XPath', 'XSLT', 'XML Schema', 'XLSX round trip', 'PDF metadata round trip']}, indent=2))


if __name__ == '__main__':
    main()
