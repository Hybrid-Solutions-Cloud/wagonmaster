import sys
from docx import Document
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
for path in sys.argv[1:]:
    d = Document(path)
    for t in d.tables:
        try: t.style = 'Table Grid'
        except Exception: pass
        pr = t._tbl.tblPr
        for tag in ('w:tblW', 'w:tblLayout'):
            for e in pr.findall(qn(tag)): pr.remove(e)
        w = OxmlElement('w:tblW'); w.set(qn('w:w'), '5000'); w.set(qn('w:type'), 'pct'); pr.append(w)
        grid = t._tbl.find(qn('w:tblGrid'))
        if grid is not None:
            for gc in grid.findall(qn('w:gridCol')): gc.attrib.pop(qn('w:w'), None)
        for row in t.rows:
            for c in row.cells:
                tcPr = c._tc.get_or_add_tcPr()
                for e in tcPr.findall(qn('w:tcW')): tcPr.remove(e)
        for c in t.rows[0].cells:
            for p in c.paragraphs:
                for r in p.runs: r.bold = True
    d.save(path)
