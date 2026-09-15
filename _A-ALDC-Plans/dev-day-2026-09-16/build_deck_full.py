"""Volle Dev-Day-Präsentation: A-ALDC & BCQuality (~16 Folien, ~20 Min).
Baut auf der echten Aproda-Vorlage auf (Layouts/Master/Branding), inkl. A-ALDC-Logo
und präsentationstauglichen Architektur-/Prozess-Diagrammen (native PowerPoint-Shapes,
damit alles im Ziel-Theme bleibt und in PowerPoint frei nachbearbeitbar ist).

Run: C:/Python314/python.exe build_deck_full.py
Output: A-ALDC-DevDay.pptx
"""
import math

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml.ns import qn

SOURCE_TEMPLATE = "aproda-vorlage.pptx"
LOGO = "a-aldc-logo.png"
OUTPUT = "A-ALDC-DevDay.pptx"

# Aproda-Theme-Palette (aus theme1.xml der Vorlage)
PRIMARY = "3C6CE8"    # dk2
DARK = "003399"       # accent5
DEEPEST = "000066"    # accent6
MID = "6699FF"        # accent3
DEEP = "0000CC"       # accent4
LIGHT = "CCECFF"      # accent1
WHITE = "FFFFFF"
INK = "1C2833"

prs = Presentation(SOURCE_TEMPLATE)


def delete_slide(prs, index):
    """Remove slide + drop its relationship so the part is excluded on save."""
    sld_id = prs.slides._sldIdLst[index]
    prs.part.drop_rel(sld_id.rId)
    prs.slides._sldIdLst.remove(sld_id)


for _ in range(len(prs.slides._sldIdLst)):
    delete_slide(prs, 0)

layouts = {layout.name: layout for layout in prs.slide_layouts}


# ---------- generic helpers ----------

def add_slide(layout_name, title=None, notes=None):
    slide = prs.slides.add_slide(layouts[layout_name])
    if title is not None and slide.shapes.title is not None:
        slide.shapes.title.text = title
    if notes:
        slide.notes_slide.notes_text_frame.text = notes
    return slide


def set_placeholder_text(slide, idx, lines):
    ph = slide.placeholders[idx]
    tf = ph.text_frame
    tf.clear()
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = line


def add_box(slide, l, t, w, h, text, fill_hex=PRIMARY, font_hex=WHITE, size=13,
            bold=True, shape_type=MSO_SHAPE.ROUNDED_RECTANGLE, subtitle=None, subtitle_size=10):
    shape = slide.shapes.add_shape(shape_type, Inches(l), Inches(t), Inches(w), Inches(h))
    shape.fill.solid()
    shape.fill.fore_color.rgb = RGBColor.from_string(fill_hex)
    shape.line.fill.background()
    shape.shadow.inherit = False
    tf = shape.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    tf.margin_left = Inches(0.06)
    tf.margin_right = Inches(0.06)
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(size)
    p.font.bold = bold
    p.font.color.rgb = RGBColor.from_string(font_hex)
    p.alignment = PP_ALIGN.CENTER
    if subtitle:
        p2 = tf.add_paragraph()
        p2.text = subtitle
        p2.font.size = Pt(subtitle_size)
        p2.font.bold = False
        p2.font.color.rgb = RGBColor.from_string(font_hex)
        p2.alignment = PP_ALIGN.CENTER
    return shape


def add_label(slide, l, t, w, h, text, size=11, color_hex=INK, bold=False, align=PP_ALIGN.CENTER):
    box = slide.shapes.add_textbox(Inches(l), Inches(t), Inches(w), Inches(h))
    tf = box.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(size)
    p.font.bold = bold
    p.font.color.rgb = RGBColor.from_string(color_hex)
    p.alignment = align
    return box


def _set_arrow_end(ln, tag, arrow_type="triangle"):
    el = ln.makeelement(qn(f"a:{tag}"), {"type": arrow_type, "w": "med", "len": "med"})
    ln.append(el)


def add_arrow(slide, x1, y1, x2, y2, color_hex=PRIMARY, width_pt=2.25, both=False):
    conn = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    conn.line.color.rgb = RGBColor.from_string(color_hex)
    conn.line.width = Pt(width_pt)
    ln = conn.line._get_or_add_ln()
    _set_arrow_end(ln, "tailEnd")
    if both:
        _set_arrow_end(ln, "headEnd")
    return conn


def add_line(slide, x1, y1, x2, y2, color_hex=INK, width_pt=1.5, dashed=False):
    """Plain connector without an arrowhead, used for bypass/elbow segments."""
    conn = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    conn.line.color.rgb = RGBColor.from_string(color_hex)
    conn.line.width = Pt(width_pt)
    if dashed:
        conn.line.dash_style = 3  # MSO_LINE_DASH_STYLE.DASH
    return conn


def add_diamond(slide, l, t, w, h, text, fill_hex=DARK, size=12):
    return add_box(slide, l, t, w, h, text, fill_hex=fill_hex, size=size, shape_type=MSO_SHAPE.DIAMOND)


# ========== 1) Titelfolie ==========
s1 = add_slide(
    "Titelfolie",
    title="A-ALDC",
    notes=(
        "Übergang: 'Das war die Theorie - grosse Teile dieser Prinzipien "
        "finden wir in A-ALDC, einem Agentic Engineering Toolkit für BC AL.'"
    ),
)
set_placeholder_text(s1, 10, ["Agentic Engineering Toolkit für Business Central AL"])
s1.shapes.add_picture(LOGO, Inches(11.0), Inches(0.35), height=Inches(1.6))

# ========== 2) Agenda ==========
s2 = add_slide("Nur Titel", title="Agenda", notes="Überblick über die Blöcke des Teils.")
s2.shapes.add_picture(LOGO, Inches(0.7), Inches(1.7), height=Inches(5.2))
box = s2.shapes.add_textbox(Inches(6.8), Inches(1.9), Inches(6.0), Inches(4.8))
tf = box.text_frame
tf.word_wrap = True
for i, text in enumerate(
    [
        "Von der Theorie zur Praxis: A-ALDC im Überblick",
        "Architektur & Prozess von A-ALDC",
        "Agents im Überblick",
        "BCQuality: was & warum",
        "Ausblick",
    ]
):
    p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
    p.text = f"{i + 1}.  {text}"
    p.font.size = Pt(22)
    p.font.color.rgb = RGBColor.from_string(PRIMARY) if i == 0 else RGBColor.from_string(INK)
    p.space_after = Pt(16)

# ========== 3) Abschnitt: Von der Theorie zur Praxis ==========
s3 = add_slide("Abschnitt 1", title="Von der Theorie zur Praxis", notes="Bezug zum Harnisch/Skills-Vortrag herstellen.")
set_placeholder_text(
    s3, 1, ["Wo A-ALDC die vorgestellten Prinzipien (Harnisch, Skills, Agents) konkret umsetzt"]
)

# ========== 4) Was ist A-ALDC? ==========
s4 = add_slide("Titel und Inhalt", title="Was ist A-ALDC?", notes="Positionierung: Spec-Driven Development + TDD.")
set_placeholder_text(
    s4,
    1,
    [
        "Ersetzt Ad-hoc-KI-Codegenerierung durch kontrollierten Engineering-Prozess",
        "Spec-Driven Development: Spec → Architektur → Tests → Code → Review",
        "TDD-Prinzipien fest im Ablauf verankert",
        "Aproda-Fork erweitert um echte AL-Testausführung, HITL-Tracking, ADO-Integration, Modul-Doku, KI-Übersetzung",
        "Spezialisierte Agent-Rollen je Aufgabe und Komplexität",
    ],
)

# ========== 5) Ohne vs. mit A-ALDC ==========
s5 = add_slide("Zwei Inhalte", title="Ohne vs. mit A-ALDC", notes="Kontrast pointiert vortragen.")
set_placeholder_text(
    s5,
    1,
    [
        "Ohne A-ALDC",
        "Vibe Coding - Ergebnis unvorhersehbar",
        "Tests zuletzt (oder nie)",
        "Reviews: \u201esieht gut aus\u201c",
        "Kein OnPrem-Gate",
    ],
)
set_placeholder_text(
    s5,
    2,
    [
        "Mit A-ALDC",
        "Spec-getrieben - KI arbeitet gegen einen Vertrag",
        "Integriertes Test-Driven-Development-Enforcement",
        "BCQuality-zitierte Prüfungen",
        "Deploy-Run-Verify Cycle: deploy → run → fix → grün",
    ],
)

# ========== 6) Architektur im Überblick (Diagramm A) ==========
s6 = add_slide("Nur Titel", title="Architektur im Überblick", notes="Hub-and-Spoke: A-ALDC verbindet 5 Bausteine.")
cx, cy = 6.65, 4.1
r = 2.5
hub_w, hub_h = 2.2, 1.0
sat_w, sat_h = 2.5, 1.05
labels = ["Agents", "Skills", "Workflows", "Instructions", "Plans"]
colors = [PRIMARY, DARK, MID, DEEP, DEEPEST]
angles = [-90 + i * 72 for i in range(5)]
sat_centers = []
for angle, label, color in zip(angles, labels, colors):
    rad = math.radians(angle)
    scx = cx + r * math.cos(rad)
    scy = cy + r * math.sin(rad) * 0.78  # etwas flacher wegen 16:9
    sat_centers.append((scx, scy))
for (scx, scy), label, color in zip(sat_centers, labels, colors):
    add_arrow(s6, cx, cy, scx, scy, color_hex=color, width_pt=2)
add_box(s6, cx - hub_w / 2, cy - hub_h / 2, hub_w, hub_h, "A-ALDC", fill_hex=INK, size=16)
for (scx, scy), label, color in zip(sat_centers, labels, colors):
    add_box(s6, scx - sat_w / 2, scy - sat_h / 2, sat_w, sat_h, label, fill_hex=color, size=14)

# ========== 7) Kern-Agents im Überblick ==========
s7 = add_slide("Titel und Inhalt", title="Kern-Agents im Überblick", notes="Je Agent kurz Rolle nennen.")
set_placeholder_text(
    s7,
    1,
    [
        "Architect - Lösungsdesign, Datenmodell, Integrationsstrategie (MEDIUM/HIGH)",
        "Conductor - orchestriert Planung → Implementierung → Review (voller TDD-Zyklus)",
        "Implementation Specialist - taktischer Code, direkte Änderungen, Debugging",
        "Triage - Reproduktion, Ursachenanalyse, Fix-Empfehlung bei Bugs",
        "Pre-Sales - PERT-Schätzung, SWOT, Kostenaufstellung",
        "Dredd - unabhängiger, BCQuality-zitierter Audit-Agent",
    ],
)

def add_breadcrumb(slide, text):
    add_label(slide, 0.55, 1.32, 8.0, 0.35, text, size=12, color_hex=DARK, bold=True)


# ========== 8) Der Entwicklungsprozess - Grobüberblick (Diagramm B) ==========
s8 = add_slide("Nur Titel", title="Der Entwicklungsprozess", notes="Grobüberblick. Jeder Schritt wird auf den folgenden Folien vertieft.")
add_breadcrumb(s8, "Teilprozess 1/6 \u2013 Überblick")
proc_labels = ["ADO / Spec", "Architektur", "Implementierung", "HITL Validation", "PR vorbereiten"]
proc_roles = ["", "Architect", "Conductor", "Entwickler / Kunde", "al-pr-prepare"]
proc_colors = [DEEPEST, DARK, PRIMARY, MID, DEEP]
n = len(proc_labels)
pw, ph = 2.15, 1.3
margin = 0.55
gap = (13.333 - 2 * margin - n * pw) / (n - 1)
py = 3.3
px_list = [margin + i * (pw + gap) for i in range(n)]
for x, label, color, role in zip(px_list, proc_labels, proc_colors, proc_roles):
    if role:
        add_label(s8, x, py - 0.4, pw, 0.35, role, size=11, color_hex=INK, bold=True)
    add_box(s8, x, py, pw, ph, label, fill_hex=color, size=14)
for i in range(n - 1):
    x1 = px_list[i] + pw
    x2 = px_list[i + 1]
    y = py + ph / 2
    add_arrow(s8, x1, y, x2, y, color_hex=INK, width_pt=2)

# kleines Loop-Badge auf "Implementierung" - Details: eigene DRV-Folie
badge_x, badge_y = px_list[2] + pw - 0.28, py - 0.28
badge = s8.shapes.add_shape(MSO_SHAPE.OVAL, Inches(badge_x), Inches(badge_y), Inches(0.56), Inches(0.56))
badge.fill.solid()
badge.fill.fore_color.rgb = RGBColor.from_string(WHITE)
badge.line.color.rgb = RGBColor.from_string(PRIMARY)
badge.line.width = Pt(1.5)
badge.shadow.inherit = False
btf = badge.text_frame
btf.vertical_anchor = MSO_ANCHOR.MIDDLE
bp = btf.paragraphs[0]
bp.text = "\u21bb"
bp.font.size = Pt(20)
bp.font.bold = True
bp.font.color.rgb = RGBColor.from_string(PRIMARY)
bp.alignment = PP_ALIGN.CENTER

add_label(
    s8, 0.55, py + ph + 0.5, 12.2, 0.5,
    "Die nächsten Folien vertiefen jeden Schritt einzeln.",
    size=13, color_hex=INK,
)

# ========== 8a) Wie beginnt der Vorgang? (Einstiegspunkte + Komplexität, Diagramm C) ==========
s8a = add_slide(
    "Nur Titel",
    title="Wie beginnt der Vorgang?",
    notes="Zwei Einstiegspunkte: Supportfall via Triage, Neuanforderung via Komplexitätsentscheid.",
)
add_breadcrumb(s8a, "Teilprozess 2/6 \u2013 Einstieg & Komplexität")

# linke Spur: Supportticket/Debug -> Triage -> Fix
lx, lw = 0.5, 3.5
add_box(s8a, lx, 1.85, lw, 0.9, "Supportticket / Debug-Fall", fill_hex=INK, size=12)
add_arrow(s8a, lx + lw / 2, 2.75, lx + lw / 2, 3.05, color_hex=INK)
add_box(s8a, lx, 3.05, lw, 0.9, "Triage", fill_hex=DEEPEST, size=13,
        subtitle="Reproduzieren, Ursache lokalisieren", subtitle_size=10)
add_arrow(s8a, lx + lw / 2, 3.95, lx + lw / 2, 4.25, color_hex=INK)
add_box(s8a, lx, 4.25, lw, 0.9, "Implementierung (Fix)", fill_hex=PRIMARY, size=12,
        subtitle="Deploy-Run-Verify Cycle erneut", subtitle_size=10)

# rechte Spur: Neuanforderung -> Komplexität? -> LOW / MEDIUM/HIGH
add_box(s8a, 7.1, 1.5, 2.1, 0.8, "Neuanforderung /\nChange Request", fill_hex=INK, size=12)
add_arrow(s8a, 8.15, 2.3, 8.15, 2.55, color_hex=INK)
add_diamond(s8a, 6.85, 2.55, 2.6, 1.05, "Komplexität?", fill_hex=DARK, size=12)
# LOW branch
add_arrow(s8a, 6.85, 3.0, 6.6, 3.0, color_hex=PRIMARY)
add_label(s8a, 4.7, 2.6, 1.9, 0.35, "LOW", size=12, color_hex=PRIMARY, bold=True)
add_box(s8a, 4.55, 2.55, 2.05, 0.9, "Implementation\nSpecialist (direkt)", fill_hex=PRIMARY, size=11,
        subtitle="Architektur & spec.create übersprungen", subtitle_size=8)
# MEDIUM/HIGH branch
add_arrow(s8a, 9.45, 3.0, 9.9, 3.0, color_hex=MID)
add_label(s8a, 9.5, 2.6, 2.6, 0.35, "MEDIUM / HIGH", size=12, color_hex=MID, bold=True)
mh_labels = ["Architect", "spec.create", "Conductor"]
mh_y = [2.55, 3.5, 4.45]
for y, label in zip(mh_y, mh_labels):
    add_box(s8a, 9.9, y, 2.6, 0.8, label, fill_hex=MID, size=13)
add_arrow(s8a, 11.2, 3.35, 11.2, 3.5, color_hex=MID, width_pt=1.5)
add_arrow(s8a, 11.2, 4.3, 11.2, 4.45, color_hex=MID, width_pt=1.5)
# Bypass: MEDIUM auch direkt über Conductor
add_line(s8a, 9.45, 3.2, 8.9, 3.2, color_hex=DARK, width_pt=1.5, dashed=True)
add_line(s8a, 8.9, 3.2, 8.9, 4.85, color_hex=DARK, width_pt=1.5, dashed=True)
add_arrow(s8a, 8.9, 4.85, 9.9, 4.85, color_hex=DARK, width_pt=1.5)
add_label(s8a, 5.9, 5.2, 3.0, 0.9, "MEDIUM: auch direkt\nüber Conductor möglich\n(voller TDD-Zyklus)",
          size=10, color_hex=DARK, bold=True)

# ========== 8b) Start: ADO Work Item & Spec ==========
s8s = add_slide("Titel und Inhalt", title="Start: ADO Work Item & Spec", notes="req_name-Muster, ADO-Header, Azure-CLI-Abruf.")
add_breadcrumb(s8s, "Teilprozess 3/6 \u2013 Start")
set_placeholder_text(
    s8s,
    1,
    [
        "req_name = {type}-{id}-{short-name} (Beispiel: bug-36370-posting-error)",
        "ADO-Header (Link zum Work Item) in jedem Plan-Dokument",
        "Azure CLI lädt Titel, Beschreibung, Repro-Steps bzw. Akzeptanzkriterien automatisch (Bug/User Story)",
        "Bei Task/Feature: zusätzlicher Kontext bleibt manueller Copy-Schritt",
        "Ergebnis: spec.md als Vertrag, gegen den die KI arbeitet",
    ],
)

# ========== 8c) Deploy-Run-Verify Cycle (eigene Folie) ==========
s8b = add_slide(
    "Nur Titel",
    title="Deploy-Run-Verify Cycle",
    notes="OnPrem-Gate: publish → sync/install → run tests → review, Loop bis grün.",
)
add_breadcrumb(s8b, "Teilprozess 4/6 \u2013 Implementierung")
drv_labels = ["Publish", "Sync & Install", "Run Tests", "Review"]
drv_colors = [DEEPEST, DARK, PRIMARY, MID]
dn = len(drv_labels)
dw, dh = 2.4, 1.2
dmargin = 0.9
dgap = (13.333 - 2 * dmargin - dn * dw) / (dn - 1)
dpy = 3.15
dpx_list = [dmargin + i * (dw + dgap) for i in range(dn)]
for x, label, color in zip(dpx_list, drv_labels, drv_colors):
    add_box(s8b, x, dpy, dw, dh, label, fill_hex=color, size=14)
for i in range(dn - 1):
    x1 = dpx_list[i] + dw
    x2 = dpx_list[i + 1]
    y = dpy + dh / 2
    add_arrow(s8b, x1, y, x2, y, color_hex=INK, width_pt=2)
# Fehler-Loop: Review -> Anpassung/Fix -> zurück zu Publish
x_review = dpx_list[3] + dw / 2
x_publish = dpx_list[0] + dw / 2
fix_w, fix_h = 2.8, 0.85
fix_y = 2.0
fix_cx = (x_publish + x_review) / 2
add_box(s8b, fix_cx - fix_w / 2, fix_y, fix_w, fix_h, "Anpassung / Fix", fill_hex=DEEP, size=13,
        subtitle="bei Fehler - Loop bis grün", subtitle_size=10)
add_line(s8b, x_review, dpy, x_review, fix_y + fix_h / 2, color_hex=DEEP, width_pt=1.5)
add_arrow(s8b, x_review, fix_y + fix_h / 2, fix_cx + fix_w / 2, fix_y + fix_h / 2, color_hex=DEEP, width_pt=2)
add_arrow(s8b, fix_cx - fix_w / 2, fix_y + fix_h / 2, x_publish, fix_y + fix_h / 2, color_hex=DEEP, width_pt=2)
add_line(s8b, x_publish, fix_y + fix_h / 2, x_publish, dpy, color_hex=DEEP, width_pt=1.5)
# Erfolgspfad: Review -> ASINST
add_arrow(s8b, x_review, dpy + dh, x_review, dpy + dh + 0.7, color_hex=PRIMARY, width_pt=2)
add_box(
    s8b, x_review - 2.6, dpy + dh + 0.75, 5.2, 1.1,
    "Erfolg: bleibt deployed in ASINST",
    fill_hex=PRIMARY, size=13, subtitle="bereit für manuelles Testen", subtitle_size=11,
)
add_label(
    s8b, 0.6, dpy + dh + 1.95, 12.1, 0.6,
    "OnPrem + HTTPS-Launch-Config: nutzt zusätzlich den Fkh-Transport-Adapter (Invoke-DeployRunVerifyDeployFkh)",
    size=10, color_hex=INK,
)

# ========== 8d) HITL Validation ==========
s8h = add_slide("Titel und Inhalt", title="HITL Validation", notes="Issue-Tracking-Datei, Loop-Sektionen, Sign-off.")
add_breadcrumb(s8h, "Teilprozess 5/6 \u2013 Verifikation")
set_placeholder_text(
    s8h,
    1,
    [
        "Nach grünem Deploy-Run-Verify Cycle: manuelle Prüfung in ASINST oder Kunden-Sandbox",
        "Befunde in {req}-hitl-validation-issues.md, IDs I-1, I-2, ... mit Status TODO/DONE",
        "KI arbeitet offene Issues ab, Deploy-Run-Verify Cycle läuft je Fix erneut",
        "Mehrere Feedback-Runden ergänzen \u201e## Loop N\u201c - die Datei wird nie gesplittet",
        "Erfolgreich abgeschlossen \u2192 weiter zu PR vorbereiten",
    ],
)

# ========== 8e) Übersetzungsprozess (XLIFF) ==========
s8t = add_slide("Nur Titel", title="Übersetzungsprozess (XLIFF)", notes="Adaptive Waterfall: Sync -> Resolve -> Export/Apply -> PoEdit -> Validate.")
add_breadcrumb(s8t, "Teilprozess 6/6 \u2013 Übersetzung (bedingt)")
tr_labels = ["Sync", "Resolve\n(Stage 1)", "Export/Apply\n(Stage 0, KI)", "PoEdit\nReview", "Validate"]
tr_colors = [DEEPEST, DARK, PRIMARY, MID, DEEP]
tn = len(tr_labels)
tw, th = 2.15, 1.3
tmargin = 0.55
tgap = (13.333 - 2 * tmargin - tn * tw) / (tn - 1)
tpy = 2.9
tpx_list = [tmargin + i * (tw + tgap) for i in range(tn)]
for x, label, color in zip(tpx_list, tr_labels, tr_colors):
    add_box(s8t, x, tpy, tw, th, label, fill_hex=color, size=13)
for i in range(tn - 1):
    x1 = tpx_list[i] + tw
    x2 = tpx_list[i + 1]
    y = tpy + th / 2
    add_arrow(s8t, x1, y, x2, y, color_hex=INK, width_pt=2)
add_label(
    s8t, 0.55, tpy + th + 0.5, 12.2, 0.9,
    "Gestufte Adaptive Waterfall: günstiger, deterministischer Kern (Stage 1) + gezielter "
    "KI-Batch nur für offene Units (Stage 0)\nGate: Validate -FailOnIssues -FailOnUnapproved "
    "blockiert die Auslieferung bis alles freigegeben ist",
    size=12, color_hex=INK,
)

# ========== 8f) PR vorbereiten ==========
s8p = add_slide("Titel und Inhalt", title="PR vorbereiten", notes="Gates + Modul-Doku + BCQuality-Review konsolidiert.")
add_breadcrumb(s8p, "Teilprozess 6/6 \u2013 Abschluss")
set_placeholder_text(
    s8p,
    1,
    [
        "Gate: erst nach grünem Deploy-Run-Verify Cycle + HITL-Sign-off",
        "al-pr-prepare erzeugt: Modul-Referenz (reference.md, EN) + Handbuch.de-CH.md - repo-weit, immer Vollstand",
        "BCQuality-Review: Review-Subagent konsultiert BCQuality vor der A-G-Checkliste",
        "@Dredd optional: unabhängiges, zusätzliches Audit",
        "Bei neuen/geänderten Labels vorher: Übersetzungsworkflow (vorherige Folie)",
        "Ergebnis: PR + aktualisierte Doku - Plan-Ordner für diese Anforderung wird geschlossen",
    ],
)

# ========== 8g) Recap: alle Diagramme im Überblick ==========
s8r1 = add_slide("Nur Titel", title="Der Gesamtprozess \u2013 alle Diagramme im Überblick", notes="Recap: fasst die gezeigten Diagramme zusammen, keine neuen Infos.")
panel_w, panel_h = 5.7, 2.5
gx = [0.6, 6.9]
gy = [1.55, 4.35]
panel_titles = ["Architektur", "Entwicklungsprozess", "Einstieg & Komplexität", "Deploy-Run-Verify Cycle"]
for (px0, py0), ptitle in zip([(gx[0], gy[0]), (gx[1], gy[0]), (gx[0], gy[1]), (gx[1], gy[1])], panel_titles):
    add_label(s8r1, px0, py0 - 0.05, panel_w, 0.3, ptitle, size=12, color_hex=DARK, bold=True)
# Panel 1: Architektur (Mini-Hub)
p0x, p0y = gx[0], gy[0] + 0.35
add_box(s8r1, p0x + 2.2, p0y + 0.7, 1.3, 0.5, "A-ALDC", fill_hex=INK, size=9)
mini_sat = [("Agents", 0.0, 0.0), ("Skills", 3.4, 0.0), ("Workflows", 0.0, 1.5), ("Instructions", 1.7, 1.7), ("Plans", 3.4, 1.5)]
for label, dx, dy in mini_sat:
    add_box(s8r1, p0x + dx, p0y + dy, 1.3, 0.45, label, fill_hex=PRIMARY, size=8)
# Panel 2: Entwicklungsprozess (Mini-Kette)
p1x, p1y = gx[1], gy[0] + 1.0
mini_chain = ["Spec", "Archi-\ntektur", "Impl.", "HITL", "PR"]
mcw = 1.05
for i, label in enumerate(mini_chain):
    x = p1x + i * (mcw + 0.1)
    add_box(s8r1, x, p1y, mcw, 0.7, label, fill_hex=[DEEPEST, DARK, PRIMARY, MID, DEEP][i], size=8)
    if i > 0:
        add_arrow(s8r1, x - 0.1, p1y + 0.35, x, p1y + 0.35, color_hex=INK, width_pt=1)
# Panel 3: Einstieg & Komplexität (Mini)
p2x, p2y = gx[0], gy[1] + 0.4
add_diamond(s8r1, p2x + 1.9, p2y, 1.6, 0.8, "Komplexität?", fill_hex=DARK, size=8)
add_box(s8r1, p2x, p2y + 1.1, 1.9, 0.6, "LOW \u2192 Specialist", fill_hex=PRIMARY, size=8)
add_box(s8r1, p2x + 3.7, p2y + 1.1, 2.0, 0.6, "MEDIUM/HIGH \u2192 Conductor", fill_hex=MID, size=8)
# Panel 4: DRV (Mini-Loop)
p3x, p3y = gx[1], gy[1] + 0.4
drv_mini = ["Publish", "Sync", "Tests", "Review"]
dmw = 1.3
for i, label in enumerate(drv_mini):
    x = p3x + i * (dmw + 0.1)
    add_box(s8r1, x, p3y, dmw, 0.6, label, fill_hex=[DEEPEST, DARK, PRIMARY, MID][i], size=8)
    if i > 0:
        add_arrow(s8r1, x - 0.1, p3y + 0.3, x, p3y + 0.3, color_hex=INK, width_pt=1)
add_label(s8r1, p3x, p3y + 0.75, 4 * dmw + 0.3, 0.4, "\u21bb Loop bis grün", size=9, color_hex=DEEP, bold=True)

# ========== 8h) Recap: Gesamtprozess im Detail ==========
s8r2 = add_slide("Nur Titel", title="Gesamtprozess im Detail", notes="Ein Diagramm, das alle Teilprozesse zu einem Fluss verbindet.")
add_box(s8r2, 0.8, 1.4, 2.6, 0.7, "Supportticket / Debug", fill_hex=INK, size=10)
add_box(s8r2, 9.9, 1.4, 2.6, 0.7, "Neuanforderung", fill_hex=INK, size=10)
add_arrow(s8r2, 2.1, 2.1, 5.9, 2.85, color_hex=INK, width_pt=1.5)
add_arrow(s8r2, 11.2, 2.1, 7.6, 2.85, color_hex=INK, width_pt=1.5)
add_diamond(s8r2, 5.4, 2.85, 2.6, 0.85, "Komplexität?", fill_hex=DARK, size=11)
add_arrow(s8r2, 6.65, 3.7, 6.65, 4.0, color_hex=INK, width_pt=1.5)
final_labels = ["Spec", "Architektur", "Implementierung", "HITL", "Übersetzung", "PR vorbereiten"]
final_colors = [DEEPEST, DARK, PRIMARY, MID, DARK, DEEP]
fn = len(final_labels)
fw = 1.95
fmargin = 0.4
fgap = (13.333 - 2 * fmargin - fn * fw) / (fn - 1)
fpy = 4.0
fpx = [fmargin + i * (fw + fgap) for i in range(fn)]
for x, label, color in zip(fpx, final_labels, final_colors):
    add_box(s8r2, x, fpy, fw, 1.0, label, fill_hex=color, size=11)
for i in range(fn - 1):
    add_arrow(s8r2, fpx[i] + fw, fpy + 0.5, fpx[i + 1], fpy + 0.5, color_hex=INK, width_pt=1.5)
# Loop-Badge auf Implementierung
b2x, b2y = fpx[2] + fw - 0.25, fpy - 0.25
badge2 = s8r2.shapes.add_shape(MSO_SHAPE.OVAL, Inches(b2x), Inches(b2y), Inches(0.5), Inches(0.5))
badge2.fill.solid()
badge2.fill.fore_color.rgb = RGBColor.from_string(WHITE)
badge2.line.color.rgb = RGBColor.from_string(PRIMARY)
badge2.line.width = Pt(1.5)
badge2.shadow.inherit = False
btf2 = badge2.text_frame
btf2.vertical_anchor = MSO_ANCHOR.MIDDLE
bp2 = btf2.paragraphs[0]
bp2.text = "\u21bb"
bp2.font.size = Pt(16)
bp2.font.bold = True
bp2.font.color.rgb = RGBColor.from_string(PRIMARY)
bp2.alignment = PP_ALIGN.CENTER
add_arrow(s8r2, fpx[-1] + fw / 2, fpy + 1.0, fpx[-1] + fw / 2, fpy + 1.45, color_hex=PRIMARY, width_pt=1.5)
add_box(s8r2, fpx[-1] + fw / 2 - 1.6, fpy + 1.5, 3.2, 0.8, "PR + aktualisierte Doku", fill_hex=PRIMARY, size=11)

# ========== 9a) Trennfolie: Anwendungsszenarien ==========
s9a = add_slide("1_Abschnitt 2", title="Anwendungsszenarien", notes="Überleitung: wie A-ALDC in der Praxis eingesetzt wird.")
set_placeholder_text(s9a, 1, ["Drei Beispiele, wie sich A-ALDC in der Praxis einsetzen lässt"])

# ========== 9b) Szenario: Support-Ticket via Triage ==========
s9b = add_slide("Nur Titel", title="Szenario: Support-Ticket über Triage", notes="Konkreter Ablauf fuer den Support/Debug-Einstiegspunkt.")
sc_labels = ["Support\nprüfen", "Triage", "AL-Tests\nerstellen", "Fix\nimplementieren", "Tests erneut\nausführen", "Review /\nAbschluss"]
sc_subtitles = [None, None, "Fehler nachvollziehen,\nIst-Zustand messen", None, "eventuell Deploy-\nRun-Verify Cycle", None]
sc_colors = [INK, DEEPEST, DARK, PRIMARY, MID, DEEP]
scn = len(sc_labels)
scw, sch = 1.95, 1.5
scmargin = 0.4
scgap = (13.333 - 2 * scmargin - scn * scw) / (scn - 1)
scpy = 2.9
scpx = [scmargin + i * (scw + scgap) for i in range(scn)]
for x, label, sub, color in zip(scpx, sc_labels, sc_subtitles, sc_colors):
    add_box(s9b, x, scpy, scw, sch, label, fill_hex=color, size=12, subtitle=sub, subtitle_size=9)
for i in range(scn - 1):
    add_arrow(s9b, scpx[i] + scw, scpy + sch / 2, scpx[i + 1], scpy + sch / 2, color_hex=INK, width_pt=1.5)

# ========== 9c) Szenario: BCQuality + Dredd ==========
s9c = add_slide("Titel und Inhalt", title="Szenario: BCQuality + Dredd", notes="Anwendungsbeispiel: bestehendes Projekt auditieren und verbessern.")
set_placeholder_text(
    s9c,
    1,
    [
        "Bestehendes Projekt analysieren \u2192 @Dredd prüft read-only gegen BCQuality",
        "Schwachstellen identifizieren \u2192 Findings mit Zitat aus BCQuality-Wissensbasis",
        "Guidelines bereinigen \u2192 Verstösse gegen Security-/Performance-/Style-Regeln beheben",
        "Verbesserungen implementieren \u2192 al-developer setzt priorisierte Findings um",
        "Ergebnis: unabhängiges, nachvollziehbares Qualitäts-Audit ohne Schreibzugriff von Dredd selbst",
    ],
)

# ========== 9d) Case Study: ASCDC Extensibility ==========
s9d = add_slide("Titel und Inhalt", title="Case Study: ASCDC Extensibility", notes="Reales Beispiel mit konkreten Zahlen (Azure Storage Proxy Function).")
set_placeholder_text(
    s9d,
    1,
    [
        "Storage-Extensibility: providerneutrale Integration Events für List, Copy, Get mit IsHandled-Pattern",
        "Proxy-Apps ersetzen Storage-Zugriffe ohne Azure-Zugangsdaten oder direkte Blob-Clients",
        "Erweiterbare Container-Verwaltung: neue temporäre WORM-Container-Entry-Tabelle als neutrales Datenformat",
        "Real-Verifikation: Storage-Setup mit echter Datei geprüft, schreibende Aktion standardmässig verborgen",
        "Qualität: 29 relevante WORM-Tests erfolgreich",
        "Zeithorizont: ~16 Stunden (11.\u201313. September 2026) - Konzeption, Implementierung, Testausbau, Runtime-Verifikation, Abschluss",
    ],
)

# ========== 10) Abschnitt: BCQuality ==========
s10 = add_slide("Abschnitt 2", title="BCQuality", notes="Überleitung zum zweiten Themenblock.")
set_placeholder_text(s10, 1, ["Eine kuratierte, zitierfähige Wissensbasis für Business Central"])

# ========== 11) Was ist BCQuality? ==========
s11 = add_slide("Titel und Inhalt", title="Was ist BCQuality?", notes="Drei Layer erklären.")
set_placeholder_text(
    s11,
    1,
    [
        "Offizielle, agentenlesbare BC-Wissensbasis (github.com/microsoft/BCQuality)",
        "3 Layer: MS (offizielle Guidelines), Community (ergänzende Patterns), Custom (firmenspezifisch)",
        "Aproda-Fork BCQuality-Aproda befüllt den Custom-Layer",
        "Wird von @Dredd und dem Review-Subagent konsultiert",
        "Citation-/Audit-Layer - kein Ersatz für Instructions & Skills",
    ],
)

# ========== 12) BCQuality im Zusammenspiel (Diagramm D) ==========
s12 = add_slide("Nur Titel", title="BCQuality im Zusammenspiel", notes="Zweite Workspace-Root, read-only, Review-Konsultation.")
add_box(s12, 0.8, 2.0, 4.6, 3.6, "Projekt-Repo\n(AL, wird kompiliert)", fill_hex=PRIMARY, size=15)
add_arrow(s12, 5.4, 3.8, 7.7, 3.8, color_hex=INK, width_pt=2.25, both=True)
add_label(s12, 5.3, 3.05, 2.5, 0.6, "Review-Subagent\nkonsultiert", size=11, color_hex=INK, bold=True)
add_box(s12, 7.7, 2.0, 4.8, 1.0, "BCQuality (2. Workspace-Root, read-only)", fill_hex=INK, size=13)
layer_labels = ["MS - offizielle Guidelines", "Community - ergänzende Patterns", "Custom - Aproda-spezifisch"]
layer_colors = [DEEPEST, DARK, MID]
ly = 3.2
for label, color in zip(layer_labels, layer_colors):
    add_box(s12, 7.7, ly, 4.8, 0.85, label, fill_hex=color, size=12)
    ly += 1.0

# ========== 13) Aproda-Erweiterungen im Überblick ==========
s13 = add_slide("Titel und Inhalt", title="Aproda-Erweiterungen im Überblick", notes="Was der Fork zusätzlich bringt.")
set_placeholder_text(
    s13,
    1,
    [
        "Deploy-Run-Verify Cycle - publish → sync → run-tests → review gegen ASINST, Loop bis grün",
        "ADO-Integration - req_name = {type}-{id}-{short-name}, ADO-Link in jedem Plan-Dokument",
        "HITL Validation - strukturiertes Issue-Tracking über mehrere Feedback-Runden",
        "Modul-Dokumentation - reference.md (EN) + Handbuch.de-CH.md, repo-weit aktuell",
        "KI-Übersetzungsworkflow (XLIFF) - Sync → Resolve → Review → Validate",
    ],
)

# ========== 14) Abschnitt: Ausblick ==========
s14 = add_slide("Abschnitt 1", title="Ausblick", notes="Überleitung zum Backlog.")
set_placeholder_text(s14, 1, ["Was als Nächstes am Toolkit selbst geplant ist"])

# ========== 15) Ausblick - Nächste Schritte ==========
s15 = add_slide("Titel und Inhalt", title="Ausblick \u2013 Nächste Schritte", notes="Aus extension-ideas-and-todos.md.")
set_placeholder_text(
    s15,
    1,
    [
        "E-001 - Read-only Upstream-Drift-Report für Aproda Sync (High, Proposed)",
        "E-002 - Offizieller Microsoft-Learn-MCP-Endpoint als Pilot (Medium, Proposed)",
        "E-003 - Auto-Cleanup-Befehl nach Implementierungsende (Medium, Proposed)",
        "E-004 - Regelbasierte AL-Objekt-ID-Vorschläge, global pro Repo (Medium, Proposed)",
        "E-005 - Gestufter KI-Übersetzungsworkflow XLIFF (High, In Progress)",
    ],
)

# ========== 15a) Ökosystem: Fkh ==========
s15a = add_slide("Nur Titel", title="Ökosystem: Fkh (Freddy's Kubernetes Helper)", notes="On-Demand BC-Container ueber GitHub-authentifizierte Azure Function + Terraform/AKS.")
fkh_labels = ["VS Code / CLI /\nGitHub Actions", "Azure Function\n(Gate)", "Terraform \u2192\nAKS", "BC-Container\n(1\u20132 Min.)"]
fkh_colors = [INK, DEEPEST, DARK, PRIMARY]
fn2 = len(fkh_labels)
fw2 = 2.5
fmargin2 = 0.9
fgap2 = (13.333 - 2 * fmargin2 - fn2 * fw2) / (fn2 - 1)
fpy2 = 1.7
fpx2 = [fmargin2 + i * (fw2 + fgap2) for i in range(fn2)]
for x, label, color in zip(fpx2, fkh_labels, fkh_colors):
    add_box(s15a, x, fpy2, fw2, 1.1, label, fill_hex=color, size=12)
for i in range(fn2 - 1):
    add_arrow(s15a, fpx2[i] + fw2, fpy2 + 0.55, fpx2[i + 1], fpy2 + 0.55, color_hex=INK, width_pt=2)
box = s15a.shapes.add_textbox(Inches(0.9), Inches(3.3), Inches(11.5), Inches(3.4))
tf = box.text_frame
tf.word_wrap = True
for i, text in enumerate(
    [
        "GitHub-authentifizierte Azure Function als Provisioning-Gate, Terraform verwaltet Azure & Kubernetes",
        "Container starten in 1\u20132 Minuten, Autoscaling, keine von Menschen verwalteten Secrets",
        "VS Code Extension + CLI: Container, Images und VMs direkt aus dem Editor verwalten",
        "Open Source, kostenlos für den Eigenbedarf (MIT-Lizenz mit Commons Clause)",
        "Repo: github.com/Freddy-DK/Fkh",
    ]
):
    p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
    p.text = text
    p.font.size = Pt(16)
    p.font.color.rgb = RGBColor.from_string(INK)
    p.space_after = Pt(10)

# ========== 15b) Weiterführend: The Engineering Stairway to Heaven ==========
s15b = add_slide("Nur Titel", title="Weiterführend: The Engineering Stairway to Heaven", notes="Freddy Kristiansen, freddysblog.com, 15.08.2026.")
s15b.shapes.add_picture("stairway-hero.png", Inches(0.7), Inches(1.7), height=Inches(4.6))
box2 = s15b.shapes.add_textbox(Inches(6.4), Inches(1.9), Inches(6.3), Inches(4.8))
tf2 = box2.text_frame
tf2.word_wrap = True
for i, text in enumerate(
    [
        "6 Stufen: Old-School Engineering \u2192 Prompt \u2192 Context \u2192 Harness \u2192 Loop \u2192 Graph Engineering",
        "A-ALDC deckt bereits mehrere Stufen ab: Context (Skills/Instructions), Harness (Agents/Tools), Loop (Deploy-Run-Verify Cycle), Graph (Conductor + Subagents)",
        "Freddy Kristiansen, freddysblog.com, 15.08.2026",
    ]
):
    p = tf2.paragraphs[0] if i == 0 else tf2.add_paragraph()
    p.text = text
    p.font.size = Pt(15)
    p.font.color.rgb = RGBColor.from_string(PRIMARY) if i == 0 else RGBColor.from_string(INK)
    p.space_after = Pt(14)

# ========== 16) Kontaktdaten / Fragen ==========
s16 = add_slide("Kontaktdaten", notes="Fragen & Feedback.")

prs.save(OUTPUT)
print(f"Saved {OUTPUT} ({len(prs.slides)} Folien)")
