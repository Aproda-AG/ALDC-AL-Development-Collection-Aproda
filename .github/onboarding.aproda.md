# Aproda ALDC — Developer Onboarding

> **Aproda ALDC** ist Aprodas angepasste Version des quelloffenen [ALDC (AL Development Collection)](https://github.com/javiarmesto/AL-Development-Collection-for-GitHub-Copilot) Frameworks — ein strukturiertes, spec-getriebenes KI-Entwicklungsframework für Microsoft Dynamics 365 Business Central.
>
> Weiterlesen: [Aproda-README](.github/readme.aproda.md) · [ALDC Quickstart](docs/quick-start-en.md)

---

## Was ist Aproda ALDC?

ALDC ersetzt ad-hoc KI-Codegenerierung durch **kontrollierten Engineering-Prozess**: Spec → Architektur → Tests → Code → Review. Aproda erweitert das Framework um Aproda-spezifische Infrastruktur (ASINST-Env-Test-Loop, SRP, ADO).

> [!IMPORTANT]
> - Wichtigster Grundsatz: **Qualitative Spezifikation → Qualitatives Ergebnis**
> - Genauere Beschreibungen im [readme.aproda.md](readme.aproda.md) und [README.md](../README.md)
> - ⚠️ (Noch) nicht kompatibel mit ACT (Aproda Copilot Template) von Antionio. **Nicht getestet und nicht empfohlen, beides gleichzeitig in einem Repo zu verwenden**

| Ohne Aproda ALDC | Mit Aproda ALDC |
|------------------|-----------------|
| Vibe Coding — Ergebnis unvorhersehbar | Spec-getrieben — KI arbeitet gegen einen Vertrag |
| Tests zuletzt (oder nie) | Integriertes Test Driven Development Enforcement |
| Reviews: „sieht gut aus" | BCQuality-zitierte Prüfungen |
| Kein OnPrem-Gate | Aproda Test-Loop: deploy → tests-run → fix → green (Echte Test-Runs) |


---

## Was kann es?

### Kern-Agents (GitHub Copilot `@`-Syntax)

| Agent | Wann | Was |
|-------|------|-----|
| `@AL Architecture & Design Specialist` | Neue Features (MEDIUM/HIGH) | Lösungsdesign, Datenmodell, Integrationsstrategie |
| `@AL Implementation Specialist` | Implementieren, debuggen, fixen | Taktischer Code, direkte Änderungen |
| `@AL Development Conductor` | Vollständiger TDD-Zyklus | Orchestriert Planung → Impl. → Review mit Subagents |
| `@AL Pre-Sales & Project Estimation Specialist` | Aufwandschätzung | PERT, SWOT, Kostenaufstellung |
| `@Dredd` | Unabhängiges Audit | BCQuality-zitierter statischer Review |

### Aproda-Erweiterungen (🟦)

| Feature | Beschreibung |
|---------|--------------|
| **OnPrem-Env Test-Loop** | `skill-aproda-test-loop` — publish → sync → run-tests → review gegen ASINST-Umgebung (später Container); loop bis grün |
| **ADO-Integration** | `skill-ado` — `req_name = {type}-{id}` (z.B. `bug-36370`), ADO-URL in jedem Plan-Dokument |
| **UAT-Loop** | Strukturiertes Issue-Tracking in `{req}-uat-issues.md` über mehrere Feedback-Runden |
| **Modul-Doku** | `al-doc-update`-Workflow — `<Modul>.reference.md` (EN) + `<Modul>.Handbuch.de-CH.md` |

### Workflows (`@workspace use <name>`)

`al-spec.create` · `al-build` · `al-pr-prepare` · `al-memory.create` · `al-context.create` · `al-initialize` · `al-doc-update` (🟦)

---

## Wie verwenden?

### 1 — Repo initialisieren (einmalig pro Projekt)

**Voraussetzung:** Fork lokal geklont, Ziel-Projekt-Repo existiert (`git init` reicht).

```
1. Fork in VS Code öffnen: File → Open Folder
2. tools/aproda-sync/Start-InitNewProject-SRP-Safe.ps1 öffnen
3. Alles markieren (Ctrl+A) → Strg+P-Command: `PowerShell: Run Selection` oder F8 (PowerShell Extension Terminal)
4. Ziel-Repo im Auswahlfenster wählen (oder Pfad eintippen)
→ Layer wird nach .github/ des Zielprojekts geschrieben
```

> - Genauere Anleitung im [readme.aproda.md - Quickstart](readme.aproda.md#Quickstart-—-initialize-Aproda-Aldc-to-a-existing-or-new-project-repo)
> - Repo nicht im Auswahlfenster? → [readme.aproda.md — Fallback](readme.aproda.md#fallback--target-repo-not-in-the-selection-list)

**BCQuality einmalig pro Workstation klonen** (neben das Projekt-Repo, nicht hinein):
```
git clone https://github.com/Aproda-AG/BCQuality-Aproda bcquality
```

> **BCQuality** — kuratierte, zitierbare BC-Wissensbasis von Microsoft; wird von `@Dredd` und dem Review-Subagent für belegte Qualitätsbefunde genutzt.


### 2 — Routing: Komplexität bestimmt den Einstieg

```
LOW   (ein Objekt, keine Integration):
  @workspace use al-spec.create  →  @AL Implementation Specialist

MEDIUM/HIGH (Logik, Events, externe Systeme):
  @AL Architecture & Design Specialist
    → @workspace use al-spec.create
      → @AL Development Conductor
```

Im Zweifel: `@AL Architecture & Design Specialist` fragen — er bewertet die Komplexität und empfiehlt den Weg.

### 3 — ADO-Anforderung starten

```
1. Work Item in ADO prüfen/ergänzen (Beschreibung, Akzeptanzkriterien)
2. URL + Inhalt ins Chat-Prompt kopieren:
   https://dev.azure.com/alphasol/<projekt>/_workitems/edit/<id>
3. Agent bestimmt req_name = {type}-{id}, legt .github/plans/{type}-{id}/ an
```

### 4 — Test-Loop (OnPrem Gate)

Nach jeder Implementierungsphase läuft der Test-Loop automatisch:
- `al-developer` → einmal vor PR (LOW)
- `al-conductor` → nach jeder Phase (MEDIUM/HIGH)

Konfiguration: `Test/testloop.config.jsonc` + `launch.json` im Projekt.

### 5 — PR vorbereiten

```
@workspace use al-pr-prepare
```
Erzeugt Modul-Doku (`al-doc-update`) und PR-Beschreibung. Erst nach grünem Test-Loop und UAT-Sign-off ausführen.

---

## Wo finde ich was?

| Frage | Dokument |
|-------|----------|
| Layer-Struktur und Upgrade-Zyklus | [readme.aproda.md](readme.aproda.md) |
| Warum ist es so strukturiert? | [decisions.aproda.md](decisions.aproda.md) (D-1…D-18) |
| Infra-Details (K:, NST, SRP, Remote-PS) | [site-profile.aproda.md](site-profile.aproda.md) |
| ALDC-Framework-Spec | [docs/framework/ALDC-Core-Spec-v1.2.md](../docs/framework/ALDC-Core-Spec-v1.2.md) |
| Test-Loop Technisches | [skills/skill-aproda-test-loop/SKILL.md](../skills/skill-aproda-test-loop/SKILL.md) |
| Layer selbst erweitern | [readme.aproda.md — TL;DR](readme.aproda.md#tldr--extend-aproda-aldc--the-two-rules) |

---

> **Faustregel:** Spec kommt vor Code. KI generiert gegen einen Vertrag, nicht gegen eine Idee.
