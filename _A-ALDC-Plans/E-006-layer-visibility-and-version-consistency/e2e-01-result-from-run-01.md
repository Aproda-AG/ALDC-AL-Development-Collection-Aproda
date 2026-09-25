# Run 1 — Ergebnis: die falsche Reihenfolge (Layer ohne neue Extension)

> Bericht zu [`e2e-01-run-wrong-order.md`](e2e-01-run-wrong-order.md), Kontext in [`e2e-00-briefing.md`](e2e-00-briefing.md).
> **Lauf 2 wurde NICHT gestartet** — wie im Briefing gefordert, hier angehalten und zum Review vorgelegt.

---

## Result

| ID | Verdict | Evidence (kurz) |
|---|---|---|
| A1 | PASS | `git branch --show-current` → `temp/temp-testing-for-aldc`; `git status --short` clean |
| A2 | PASS | root `aldc.yaml`=True, `.github/aldc.yaml`=False, `.external`=False |
| A3 | PASS | `aprodaag.aproda-aldc-0.1.7` installiert |
| A4 | **FAIL** | Pull warf eine unbehandelte Exception: `ReadAllText` auf fehlende `templates\external-readme.seed.md` |
| A5 | **FAIL** | `.github/aldc.yaml` existierte nach Lauf 1 nicht |
| A6 | **FAIL** | Root-`aldc.yaml` war nach Lauf 1 weiterhin vorhanden (Inhalt in-place überschrieben: `toolkitRoot: ".github"`, aber nie verschoben) |
| A7 | **FAIL** | `.external/` wurde angelegt (leer), `.external/README.md` aber nicht (Crash genau an dieser Stelle) |
| A8 | **FAIL** | Workspace bekam den neuen `.external`-Ordnereintrag, der alte `../../BCQuality-Aproda`-Eintrag blieb zusätzlich bestehen (beide gleichzeitig vorhanden) |
| A9 | **FAIL** | Keine `*.code-workspace.bak` während Lauf 1 erzeugt (das Backup schreibt das Migrationsskript, das nie lief) |
| A10 | **FAIL** | `BCQUALITY_HOME` unter `terminal.integrated.env.windows` nach Lauf 1 weiterhin vorhanden |
| A11 | PASS (mit Vorbehalt) | `bcquality/**` zu `search.exclude`/`files.watcherExclude` hinzugefügt; kein `files.exclude`-Eintrag erzeugt — aber die alten `../../BCQuality-Aproda`-Glob-Einträge blieben zusätzlich bestehen |
| A12 | PASS | `.gitignore`-Block korrekt aktualisiert, enthält alle vier neuen Einträge — trotz späterem Absturz |
| A13 | PASS | `.external/bcquality` existiert nicht — sowohl by design (alte Extension) als auch faktisch wegen des Absturzes |
| A14 | **FAIL** | Keine der Dateien `agents/index.md`, `docs/copilot-reference.md`, `docs/bcquality.md` kam an; keiner der drei Pfade taucht im Sync-Manifest (`aproda-sync.json`) auf — geprüft: `includeFiles`, `includeGlobs`, `dualVariant`, `dotGithub` |
| A15 | PASS | Rung 1: kein `#bcquality`-Tool über `tool_search` auffindbar. Rung 2: `aprodaAldc_readConfiguration` liefert nur den deklarierten `home`-Wert (kein `resolvedHome`/`verified`). Rung 3: `read_file` auf `.github/aldc.yaml` → „nonexistent file"; `read_file` auf `.external/bcquality/skills/entry.md` → „nonexistent file" |
| A16 | PASS | Dredd-Review lief sauber durch — kein Block/Error/Loop (per Subagent-Lauf verifiziert) |
| A17 | PASS | Dredd protokollierte `"outcome": "not-applicable"` und wich auf die volle native A–G-Checkliste aus |
| A18 | **Judgement Call — siehe unten** | Sichtbar nur, wenn man in `audit.bcquality`/`notes` liest; das Top-Level-Verdikt (`PASS_WITH_FINDINGS`) und die Findings-Liste enthalten keinerlei Hinweis |
| A19 | NOT-REACHED (wie ursprünglich gescoped) / **PASS bei konvergiertem 3. Lauf** | Lauf 2 hat die unterbrochene Migration selbst nachgeholt; ein sauberer Lauf 3 meldete danach `Init 5: project layout already current -- nothing to migrate.` |
| A20 | PASS (bei Lauf 3) | Workspace-Hash vor/nach Lauf 3 identisch (`4DB128DF…`), kein neues `.bak` |
| A21 | PASS (bei Lauf 3) | `git status --short` vor/nach Lauf 3 identisch (2 modified + 1 untracked) |

## Was tatsächlich passiert ist

Die Baseline entsprach exakt dem erwarteten Pre-Block-4-Layout. Das Ausführen des echten `Start-Pull.ps1` erforderte einen Workaround: Das Launcher-Skript setzt `$env:APRODA_SYNC_SCRIPTDIR` bedingungslos auf `''` zurück und verlässt sich danach auf `$PSScriptRoot` (Datei-Ausführung, durch SRP blockiert) oder `$psEditor` (VS Code „Run Selection", nur interaktiv) zur Selbstlokalisierung — beides funktioniert nicht bei einer terminalbasierten Ausführung geladenen Inhalts. Ich habe deshalb nur diese eine Zuweisungszeile in einer In-Memory-Kopie des Skriptinhalts gepatcht (nie die Datei auf der Platte angefasst) — ein reiner Headless-Invocation-Workaround, keine Änderung an der geprüften Implementierung.

**Lauf 1 stürzte ab.** `Sync-AprodaLayer.ps1` löste nur 130 der im Manifest deklarierten `includeFiles`/Globs auf und liess dabei `tools/aproda-sync/Migrate-AprodaProjectLayout.ps1`, `templates/external-readme.seed.md` und `templates/workspace.seed.jsonc` stillschweigend aus — alle drei existieren nachweislich im Fork und stehen nachweislich in `aproda-sync.json`. `Initialize-AprodaProject.ps1` durchlief Init 1–3 (Memory-Seed, `.gitignore`, Workspace-Roots) erfolgreich, warf dann in Init 4 eine unbehandelte `ReadAllText`-Exception beim Versuch, das fehlende Template zu lesen, und erreichte Init 5 (die eigentliche T-35-Migration) nie. Das Projekt blieb in einem inkonsistenten Zustand zurück: `.external/` angelegt aber leer, Workspace-Datei halb aktualisiert (neuer Root hinzugefügt, alter Root und `BCQUALITY_HOME` nicht entfernt), Root-`aldc.yaml`-Inhalt überschrieben aber nie nach `.github/` verschoben, kein `.bak`-Backup je geschrieben.

Ein zweiter, unveränderter Lauf des identischen Pull-Befehls löste alle 135 Dateien korrekt auf, schloss Init 4 sowie die vollständige Init-5-Migration sauber ab (entfernte die verwaiste Root-`aldc.yaml`, ersetzte den alten Workspace-Root, entfernte `BCQUALITY_HOME`, schrieb das `.bak`). Ein dritter Lauf bestätigte danach echte Idempotenz. Das Arbeitsverzeichnis des Forks war zum Zeitpunkt des fehlgeschlagenen Pulls sauber (read-only geprüft, keine Schreibzugriffe) — die Ursache lag also nicht an einer parallelen Bearbeitung auf der Quellseite.

Die BCQuality-Erreichbarkeitsprüfung in Phase 2 bestätigte echte Unerreichbarkeit über alle drei dokumentierten Rungs. Ein echter `@Dredd`-Lauf auf `Base/SRC/General Setup/CompanyInformation.TableExt.al` lief ohne Blockade durch, protokollierte `outcome: not-applicable` und wich auf die volle native Checkliste aus — genau wie vertraglich vorgesehen. Dredd merkte dabei allerdings unaufgefordert selbst an, dass seine eigene Top-Level-Antwort keinen expliziten „BCQuality nicht konsultiert"-Hinweis enthält; das Faktum wird erst sichtbar, wenn man tief in die `bcquality`/`notes`-Felder des persistierten JSON liest.

## Findings

- **Blocker** — Der allererste Pull in dieser Session liess non-deterministisch 3 deklarierte `includeFiles` bei der Auflösung aus, was zu einem unbehandelten Absturz führte und das Projekt in einem inkonsistenten Halb-Migrations-Zustand zurückliess (doppelte Workspace-Roots, verwaistes `BCQUALITY_HOME`, Root-`aldc.yaml` überschrieben aber nicht verschoben, kein Backup). Ein zweiter identischer Lauf heilte sich selbst. Das ist unabhängig von der Extension-Installationsreihenfolge und würde **jedes** Projekt beim ersten Block-4-Pull treffen, nicht nur das hier getestete „falsche Reihenfolge"-Szenario. Muss vor Release in `Sync-AprodaLayer.ps1`s Dateiauflösung root-caused werden.
- **Blocker/Major** — A14 scheitert vollständig: `agents/index.md`, `docs/copilot-reference.md`, `docs/bcquality.md` sind in keinem auffindbaren Teil des Sync-Manifests referenziert, in keinem der Läufe. Falls „T-36" (Ein-Pull-Auslieferung dieser Dateien) implementiert sein sollte, ist das entweder nicht der Fall, oder es läuft über einen Mechanismus, den ich nicht finden konnte.
- **Major** — A18 bestätigt das vom Implementierer vorhergesagte Risiko: Die BCQuality-Degradation ist auf der Ebene, die ein Entwickler tatsächlich liest (Top-Level-Verdikt + Findings), unsichtbar. Sie ist nur durch Lesen verschachtelter `audit.bcquality`/`notes`-Felder auffindbar. Dredd selbst hat dies unaufgefordert während des Laufs als eigene Reporting-Lücke geflaggt.
- **Minor** — Nach der Migration behalten sowohl `search.exclude` als auch `files.watcherExclude` die alten `../../BCQuality-Aproda`-Glob-Einträge zusätzlich zum neuen `bcquality/**`-Eintrag; `Migrate-AprodaProjectLayout.ps1` räumt diese nicht auf. Rein kosmetisch.
- **Nit** — Der Selbstlokalisierungs-Guard in `Start-Pull.ps1` kann trotz gegenteiligem Kommentar nicht per vorab gesetzter Umgebungsvariable überschrieben werden (er setzt sie bedingungslos zurück, bevor er sie prüft). Er funktioniert nur über SRP-blockierte Datei-Ausführung oder interaktives VS-Code-„Run Selection" — für Headless-/Automatisierungs-Aufrufe wäre ein echter Override-Rung sinnvoll.

## Open questions

- Ist der Datei-Auflösungsfehler in Lauf 1 reproduzierbar oder ein Einzelfall? Ich konnte ihn bei Läufen 2/3 nicht erneut auslösen, und das Fork-Arbeitsverzeichnis war durchgehend sauber. Braucht einen eigenen Reproduktionsversuch durch den Implementierer (z. B. kalter Cache, frischer Fork-Klon).
- Ist ein leerer `.external`-Ordner im Explorer (ohne Fehler/Warnung) ein akzeptabler degradierter Zustand für ein Projekt mit alter Extension, oder sollte etwas eine Warnung anzeigen?

## Wenn der Block-4-Layer vor der neuen Extension released würde — was würde tatsächlich passieren, und würde es jemand merken?

**Schlimmer als die Vorhersage des Implementierers.** Die Vorhersage war, dass BCQuality still und leise ausfällt, während alles andere funktioniert. Tatsächlich gemessen habe ich, dass **der allererste Pull abstürzen kann und das Projekt in einem kaputten Zwischenzustand zurücklässt** (doppelte Workspace-Roots, verwaistes `BCQUALITY_HOME`, verwaiste Root-`aldc.yaml`) — unabhängig von der Extension-Version. Ein Entwickler würde beim allerersten Pull eine PowerShell-Exception sehen, was weitaus sichtbarer ist als eine stille BCQuality-Degradation, aber das Projekt bliebe inkonsistent, bis er auf die Idee kommt, den Pull ein zweites Mal auszuführen (was zufällig alles repariert). Ist diese Hürde einmal genommen, entspricht die BCQuality-spezifische Degradation eng der Vorhersage und ist real, aber ihre Sichtbarkeit im Review-Output ist derzeit grenzwertig — ein Entwickler, der nur das Verdikt überfliegt, würde nicht merken, dass BCQuality nie konsultiert wurde.
