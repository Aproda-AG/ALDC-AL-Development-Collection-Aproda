Arbeiten wir am besten **abschnittsweise entlang der Trennfolien** – das gibt dir nach jedem Block eine sinnvolle Review-Chance, und ich kann pro Block bauen → strukturell prüfen → dir zeigen, statt am Ende eine riesige Diff-Wand zu liefern. Innerhalb eines Blocks gehe ich dann in kleinen Einzelschritten vor (erst Struktur/Text, dann Diagramm-Feinschliff).

Vorschlag für die Reihenfolge:

**Paket 0 – globale Quick-Fixes (zuerst, für die ganze Datei)**
- `->` → echtes `→`-Symbol überall
- DRV-Folie: Ausrichtung + fehlende „Anpassung/Fix"-Box im Loop
- Entwicklungsprozess-Übersicht: kleines Loop-Badge statt Duplikat-Diagramm bei „Implementierung"

**Paket 1 – Teil 1 „Der Entwicklungsprozess" (Kernstück, wird am grössten)**
1. Grob-Überblick-Folie (Gesamtprozess, wenig Detail)
2. Zwei-Einstiegspunkte-Diagramm (Support/Debug → Triage **vs.** Neuanforderung → Komplexität), direkt vor/mit der bestehenden Komplexitäts-Folie verschmolzen
3. Teilprozess-Detailfolien einzeln: Start (ADO/Spec) → Komplexität-Entscheid (schon vorhanden, ggf. anpassen) → HITL Verifikation → Übersetzungsprozess → PR vorbereiten (Gates + Sub-Prozesse + al-doc-update + BCQuality-Review kompakt zusammen)
4. Recap-Diagramm am Ende des Blocks (fasst die Teile visuell zusammen, keine neuen Infos)

**Paket 2 – Trennfolie + Teil 2 „Anwendungsszenarien"**
- Support/Triage-Walkthrough
- ASCDC-Extensibility-Case-Study
- (offene Frage unten: BCQuality/Dredd als drittes Szenario oder in Teil 1 belassen?)

**Paket 3 – Trennfolie + Teil 3 „Ausblick"**
- Fkh (inkl. Bild aus dem Repo) + Freddy's-Blog-Verweis, kompakt

Ich würde nach jedem Paket kurz zeigen, bevor ich das nächste angehe.

**Zwei offene Mini-Entscheidungen, bevor ich mit Paket 0 starte** (bei 45–50 Min. jetzt flexibler als vorher, aber will nicht an dir vorbei entscheiden):

1. BCQuality/Dredd-Beispiel: als drittes Anwendungsszenario in Teil 2, oder wie vorgeschlagen in den 
bestehenden BCQuality-Block (Teil 1) integrieren?
 ->  beides. teil 2 ist als anwendungsbeispiel-idee - so könnte man es nutzen.
2. Recap-Diagramm am Ende von Teil 1: ein neu gezeichnetes Gesamtdiagramm, oder eine Folie mit den 4–5 bestehenden Diagrammen verkleinert nebeneinander (schneller zu bauen, wirkt aufgeräumter)?
 -> mach beides. ich entscheide dann.
