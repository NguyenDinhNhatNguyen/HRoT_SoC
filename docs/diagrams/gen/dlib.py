"""Small draw.io page builder for the HRoT_SoC diagrams (blocks, groups, wires, flowchart shapes)."""
from xml.sax.saxutils import quoteattr

BG = "#DCE6F2"
FONT = "fontFamily=Helvetica;"
# role -> (fill, stroke)
KIND = {
    "core": ("#D5E8D4", "#82B366"),
    "mem": ("#E1D5E7", "#9673A6"),
    "sha": ("#FFE6CC", "#D79B00"),
    "sec": ("#F8CECC", "#B85450"),
    "sys": ("#FFF2CC", "#D6B656"),
    "bus": ("#DAE8FC", "#6C8EBF"),
    "per": ("#DAE8FC", "#6C8EBF"),
    "neutral": ("#EEEEEE", "#999999"),
    "white": ("#FFFFFF", "#999999"),
    "ok": ("#D5E8D4", "#82B366"),
    "bad": ("#F8CECC", "#B85450"),
}
GROUP = {  # fill, stroke for containers
    "sec": ("#FDECEA", "#B85450"), "sys": ("#FFF8E1", "#D6B656"), "core": ("#EEF7EC", "#82B366"),
    "sha": ("#FFF3E6", "#D79B00"), "bus": ("#EEF3FB", "#6C8EBF"), "zone": ("#F4F7FB", "#5B6B7F"),
    "app": ("#FFF4D6", "#D6B656"), "root": ("#EAF1FA", "#1E3A8A"), "mem": ("#F3ECF7", "#9673A6"),
}
WIRE = {
    "n": ("#333333", False), "bus": ("#6C8EBF", False), "sec": ("#B85450", False), "sys": ("#B58B00", False),
    "sha": ("#D79B00", False), "mem": ("#9673A6", True), "irq": ("#2F6DB5", True), "dash": ("#555555", True),
    "core": ("#4C8B3B", False), "ok": ("#2E7D32", False), "bad": ("#C62828", False),
}


class Page:
    def __init__(self, name, w=1600, h=900, bg=BG):
        self.name, self.w, self.h, self.bg = name, w, h, bg
        self.cells = []
        self.n = 2

    def _id(self, k=None):
        if k:
            return k
        self.n += 1
        return "n%d" % self.n

    def group(self, title, x, y, w, h, kind="zone", key=None, dashed=True, size=14):
        f, s = GROUP[kind]
        st = (f"rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor={f};strokeColor={s};strokeWidth=2;"
              f"verticalAlign=top;fontSize={size};fontColor=#1F2937;{'dashed=1;' if dashed else ''}{FONT}")
        i = self._id(key)
        self.cells.append(f'<mxCell id="{i}" value={quoteattr("<b>%s</b>" % title)} style={quoteattr(st)} vertex="1" parent="1">'
                          f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    def block(self, name, desc, x, y, w=150, h=56, kind="bus", key=None, size=12, extra=""):
        f, s = KIND[kind]
        label = "<b>%s</b>" % name + ("<br>%s" % desc if desc else "")
        st = (f"rounded=1;whiteSpace=wrap;html=1;fillColor={f};strokeColor={s};strokeWidth=2;fontSize={size};"
              f"fontColor=#1F2937;{FONT}{extra}")
        i = self._id(key)
        self.cells.append(f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(st)} vertex="1" parent="1">'
                          f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    def text(self, label, x, y, w=200, h=24, size=12, bold=False, color="#1F2937", align="left", key=None):
        st = (f"text;html=1;whiteSpace=wrap;strokeColor=none;fillColor=none;align={align};verticalAlign=middle;"
              f"fontSize={size};fontColor={color};{'fontStyle=1;' if bold else ''}{FONT}")
        i = self._id(key)
        self.cells.append(f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(st)} vertex="1" parent="1">'
                          f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    # ---- flowchart shapes
    def term(self, label, x, y, w=170, h=44, kind="neutral", key=None):
        f, s = KIND[kind]
        st = (f"rounded=1;arcSize=50;whiteSpace=wrap;html=1;fillColor={f};strokeColor={s};strokeWidth=2;fontSize=12;"
              f"fontColor=#1F2937;fontStyle=1;{FONT}")
        i = self._id(key)
        self.cells.append(f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(st)} vertex="1" parent="1">'
                          f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    def step(self, label, x, y, w=210, h=48, kind="bus", key=None):
        f, s = KIND[kind]
        st = (f"rounded=0;whiteSpace=wrap;html=1;fillColor={f};strokeColor={s};strokeWidth=2;fontSize=12;"
              f"fontColor=#1F2937;{FONT}")
        i = self._id(key)
        self.cells.append(f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(st)} vertex="1" parent="1">'
                          f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    def decision(self, label, x, y, w=210, h=84, key=None):
        st = (f"rhombus;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#333333;strokeWidth=2;fontSize=12;"
              f"fontColor=#1F2937;{FONT}")
        i = self._id(key)
        self.cells.append(f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(st)} vertex="1" parent="1">'
                          f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    def io(self, label, x, y, w=210, h=48, kind="white", key=None):
        f, s = KIND[kind]
        st = (f"shape=parallelogram;perimeter=parallelogramPerimeter;whiteSpace=wrap;html=1;fillColor={f};strokeColor={s};"
              f"strokeWidth=2;fontSize=12;fontColor=#1F2937;{FONT}")
        i = self._id(key)
        self.cells.append(f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(st)} vertex="1" parent="1">'
                          f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    def wire(self, a, b, label="", kind="n", pts=None, exit=None, entry=None, dashed=None, key=None, width=2):
        color, dflt = WIRE[kind]
        dash = dflt if dashed is None else dashed
        st = (f"edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=classic;strokeColor={color};strokeWidth={width};"
              f"fontSize=11;fontStyle=1;fontColor=#1F2937;labelBackgroundColor=#FFFFFF;{FONT}{'dashed=1;' if dash else ''}")
        if exit:
            st += "exitX=%s;exitY=%s;exitDx=0;exitDy=0;" % exit
        if entry:
            st += "entryX=%s;entryY=%s;entryDx=0;entryDy=0;" % entry
        i = self._id(key)
        g = '<mxGeometry relative="1" as="geometry">'
        if pts:
            g += '<Array as="points">' + "".join('<mxPoint x="%s" y="%s"/>' % p for p in pts) + "</Array>"
        g += "</mxGeometry>"
        self.cells.append(f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(st)} edge="1" parent="1" '
                          f'source="{a}" target="{b}">{g}</mxCell>')
        return i

    def xml(self, idx):
        head = (f'<diagram id="p{idx}" name={quoteattr(self.name)}><mxGraphModel dx="1400" dy="800" grid="0" gridSize="10" '
                f'guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="{self.w}" '
                f'pageHeight="{self.h}" background="{self.bg}" math="0" shadow="0"><root><mxCell id="0"/>'
                f'<mxCell id="1" parent="0"/>')
        return head + "".join(self.cells) + "</root></mxGraphModel></diagram>"


def write(pages, path):
    out = '<mxfile host="app.diagrams.net" version="29.6.6">' + "".join(p.xml(i) for i, p in enumerate(pages)) + "</mxfile>\n"
    open(path, "w", encoding="utf-8", newline="").write(out)
