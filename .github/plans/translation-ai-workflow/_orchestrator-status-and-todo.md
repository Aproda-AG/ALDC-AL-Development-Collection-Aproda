# Wir beginnen mit implementierungsphase.

**du bist der orchestrator** - ich bin ab jetzt abwesend / schlafe, die nächsten stunden.

du bist der orchestrator, nutz subagents für die aufgaben.


1) Starte Subagent für implementierung -> GPT 5.6 Terra.
Gib ihm die "stage-0.spec.md" mit und sinnvolle anweisungen. Er soll präzise und strukturiert arbeiten.

2) **als separater Schritt danach** starte 2. subagent für review - auch GPT 5.6 Terra.
er soll implementierung prüfen -> stimmt impl mit spec überein? Ist es plausibel? -> und dir dann ein review result geben.

3) **als separater Schritt danach** Gibt es etwas zu fixen nach review? oder kannst du was testen? Wenn Ja, beauftrage GPT 5.6 Terra oder Luna als subagent, um das auszuführen.




---


## Status / was habe ich gemacht / wo bin ich dran

### Orchestrator-Entscheidungen (getroffen ohne Rückfrage, da abwesend — bitte gegenlesen)

- **Offener Punkt 1 (Modell-Fallback):** hart scheitern mit klarer Meldung, **kein** stiller Fallback auf das Modell des Aufrufers. Begründung: ein Fallback verzehnfacht die Kosten und verfälscht die Korrekturquote — die Kennzahl, an der die Priorisierung von Stufe 2 hängt.
- **Offener Punkt 2 (Stufengrenze §2):** als bestätigt behandelt — deine drei Antworten (Vendor-Enum, MaxItems, Approval-Gate nachziehen) decken genau diese drei Punkte ab.
- **Offener Punkt 3 (D-Nummer):** `D-32` wiederverwendet; die Nummer wurde beim Fundament-Commit bewusst freigehalten.
- **Scope-Split:** Zyklus 1 = D1–D6 (Code, Vendor-Patch, Fixtures, Tests). Zyklus 2 = D7–D12 (Skill, Agents, Prompt, Governance). Zwölf Deliverables in einem Durchgang gefährden die Qualität; die Framework-Dokumente hängen ohnehin davon ab, dass der Kern stimmt.

### Verlauf

- Ausgangslage: Fundament committet (`be768ef`); im Working Tree liegen die vier überholten Framework-Dateien aus der ersten Runde plus die vier Planungsdokumente.
- Modellbezeichner `GPT-5.6 Luna (copilot)` vorab verifiziert — Vertragstreue und de-CH-Orthografie im Vier-Punkte-Smoke-Test bestanden.
- **Zyklus 1 / Implementierung (Terra):** D1–D6 umgesetzt. Neu: Subagent-Definition, Fixture-Paar, Testharness. Geändert: Wrapper, Vendor-Enum (additiv, 2 Zustände), `UPSTREAM.md`.
- **Verifikation durch Orchestrator (nicht dem Bericht vertraut):** Dateiumfang stimmt (D7–D12 unberührt), Parser 0 Fehler in allen drei PS-Dateien, Testsuite selbst ausgeführt → **T1–T18 alle PASS, Exit-Code 0**. Statistik meldet korrekt „4 missing, 1 need review" — C-11-Fix im Betrieb bestätigt.
- **Offener Doku-Widerspruch gefunden:** Architektur §4.6 nennt `-MaxItems` Default 40, Spec und Entscheidung 22 nennen 30. Implementierung folgt 30. Muss in der Architektur korrigiert werden → Fix-Zyklus.
- **Zyklus 1 / Review (Terra, read-only):** Verdikt **NEEDS_REVISION**. 1 Blocker, 2 major, 4 minor. Positiv bestätigt: AI-Batch leakt keine Tool-Felder, Kurzschlüssel korrekt aus Source-Hash abgeleitet, Vendor-Patch additiv und ohne `final`/`signed-off`, SRP eingehalten, T2–T11 prüfen tatsächlich SHA-256-Byteidentität.
- **Blocker verifiziert (nicht übernommen, selbst geprüft):** `Apply` validiert korrekt vor dem ersten Schreiben, speichert die Dokumente danach aber sequenziell auf die Live-Pfade. Fällt Datei 2 aus, bleibt Datei 1 geändert. In diesem Workflow realistisch, weil PoEdit Dateien offen hält. Spec fordert „any failure leaves every target file byte-identical" → in Scope.
- **Doku-Fixes durch Orchestrator erledigt:** §4.6 MaxItems 40→30; „read-only" für `Report` präzisiert (keine XLIFF-Schreibvorgänge, Cache wird sehr wohl geschrieben); Spec §5.5 um Zwei-Phasen-Commit mit Rollback ergänzt.
- **Zyklus 1 / Fix (Terra):** F1–F6 behoben, Coverage T19–T25 ergänzt. F1 als echter Zwei-Phasen-Commit umgesetzt — Staging auf gleiche Verzeichnisebene, Backups, `File::Replace`, Rollback rückwärts, Cleanup im `finally`.
- **Verifikation durch Orchestrator:** Testsuite selbst ausgeführt → **T1–T25 alle PASS**, Exit 0. Parser 0 Fehler. `npm test` 52/0. `git diff --check` sauber. Foundation und die sechs Out-of-Scope-Dateien unberührt.
- **Design-Entscheidung akzeptiert (bitte gegenlesen):** Der Rollback wird über `APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT` fehlerinjiziert — Testhaken im Produktionspfad. Akzeptiert, weil der Pfad sonst nicht testbar wäre und versehentliche Aktivierung nur einen lauten Abbruch mit Rollback auslöst, keinen Datenverlust. Ich habe eine Begründungszeile im Code ergänzt.
- **Zyklus 1 Status: GRÜN.** D1–D6 fertig.
- **Zyklus 2 / Implementierung (Terra):** D7–D12 umgesetzt — Skill, beide Agents, PR-Prompt, D-32 samt Register-Zeile, Sync-Manifest.
- **Verifikation durch Orchestrator:** Stale-Scan fand **drei überlebende Passagen im Skill**, die der Subagent als entfernt gemeldet hatte (`signed-off`-Zeile in der Zustandstabelle, „Check translation memory", „Promote all final texts to signed-off"). Alle drei im *generischen* Teil, nicht im Aproda-Abschnitt. Selbst korrigiert: Zustandstabelle und Workflow-Abschnitt auf den tatsächlichen Ablauf umgeschrieben.
- **Zyklus 2 / Review (Terra, read-only):** Verdikt NEEDS_REVISION. Berechtigt: falscher Tool-Pfad im Skill, `targetState: "translated"` in Pattern 3, Memory-Schritt in Pattern 5, fehlende Dokumentation von `-Offset`/`Report`/`-ReportPath`. Dazu zwei Widersprüche in **meinem** Architekturtext und ein Formatierungsfehler aus **meiner** Bearbeitung.
- **Selbst korrigiert:** Entscheidung 4·10 sagte „no vendor patch" (widersprach 21); Entscheidung 13 legte das Gate fälschlich in `al-pr-prepare` statt in `Validate`; verwaister Code-Fence im Skill; `needs-adaptation`-Schreiber auf `Sync`/`Validate` präzisiert — hier lag der Reviewer teilweise falsch, `Test-XliffTranslations` schreibt den Zustand sehr wohl.
- **Zyklus 2 / Fix (Terra):** F1–F4 behoben — Tool-Pfad layout-bewusst, Pattern 3 als Nicht-Aproda-Referenz markiert, Pattern 5 entschärft, vollständige Betriebsschleife (`Sync` → `ExportOpen`/Subagent/`Apply` bis `Remaining` 0 → PoEdit → strikte `Validate` → `Report`) in Skill und beiden Agents dokumentiert.
- **Abschlussvalidierung:** **T1–T25 alle PASS**, `npm test` 52 Erfolge / 0 Fehler, `git diff --check` sauber, Foundation unberührt.

## Offen für dich

- **Nichts committet.** Alles liegt im Working Tree, damit du gegenlesen kannst.
- **`aprodaag.aproda-aldc`** in der `tools:`-Zeile von `al-conductor.agent.md` stammt aus deiner früheren Sitzung, nicht aus dieser Arbeit. Sieht wie ein Dublett zu `aproda.aproda-aldc/aprodaAldc_readConfiguration` aus (anderer Publisher-Präfix). Ich habe es bewusst nicht angefasst — bitte prüfen.
- **Testhaken im Produktionspfad** (`APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT`) — Begründung siehe oben, bitte bestätigen.
- **`.altestrunner/`** taucht wiederholt auf; ein `.gitignore`-Eintrag wäre die dauerhafte Lösung.
- **Noch nicht erledigt:** die einmalige PoEdit-Round-Trip-Prüfung an einer echten BC-XLF (Abnahmekriterium 5) — braucht dich, weil PoEdit interaktiv ist.

