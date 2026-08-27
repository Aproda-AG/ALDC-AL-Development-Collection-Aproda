# Aproda ALDC — Developer Onboarding

> **Aproda ALDC** ist Aprodas angepasste Version des quelloffenen [ALDC (AL Development Collection)](https://github.com/javiarmesto/AL-Development-Collection-for-GitHub-Copilot) Frameworks — ein strukturiertes, spec-getriebenes KI-Entwicklungsframework für Microsoft Dynamics 365 Business Central.
>
> Weiterlesen: [Aproda-README](readme.aproda.md) · [VS Code Einstieg](readme.aproda.md#recommended-vs-code-extension)

---

## Was ist Aproda ALDC?

ALDC ersetzt ad-hoc KI-Codegenerierung durch kontrollierten Engineering-Prozess in Form von **Spec-Driven Development** und nutzt Test-Driven-Development-Prinzipien: Spec → Architektur → Tests → Code → Review. Aproda ergänzt das Framework um echte AL-Test-Ausführung (Deploy-Run-Verify Cycle gegen ASINST-Umgebung), strukturiertes HITL-Validation-Issue-Tracking, automatische Modul-Dokumentation und ADO-Integration.

Das Framework arbeitet mit **spezialisierten Agent-Persönlichkeiten** je nach Aufgabe und Komplexität: der **Architekt** für komplexe Anforderungen (Lösungsdesign, Datenmodell), der **Conductor** als Umsetzungs-Orchestrator (orchestriert Planung → Implementierung → Review, bei mittlerer/hoher Komplexität oder arbeitet Issues aus der HITL Validation ab.), der **Implementation Specialist** für direktes Codieren (eigenständig bei einfachen Aufgaben, oder angewiesen vom Conductor). Ergänzend: der **Triage-Agent** für Problemanalyse und Diagnose, der **Pre-Sales-Agent** für Aufwandschätzungen, und **Dredd** — der unabhängige Auditor, der bestehende Lösungen via BCQuality auf Security, Performance, Guidelines und Patterns prüft und bewertet.

**Beispielprozess (Komplexity MEDIUM/HIGH):**

```
ADO Work Item/Spez      → Anforderung, Akzeptanzkriterien
→ Architekt             → Lösungsdesign (optional, bei komplexen Features)
→ al-spec.create        → Spec-Dokument als Vertrag für die KI
→ Conductor             → Implementierung + Deploy-Run-Verify Cycle (deploy → run → fix → grün, je Phase)
→ HITL Validation       → Entwickler prüft in ASINST; ggf. Kunden-Sandbox; ggf. Berater/Kunde
                          Befunde werden in hitl-validation-issues.md getrackt → KI arbeitet nach, Deploy-Run-Verify Cycle läuft erneut
→ al-pr-prepare         → PR + Technische Modul-Doku & Handbuch.de-CH aktualisiert (repo-weit)
```
> Pro Work Item/Anforderung entsteht ein eigener `plans/{req}/`-Ordner (Spec, Architektur, Test-Plan, HITL-Validation-Issues). Doku und Handbuch gelten **repo-weit** — immer Vollstand, nicht nur Delta des letzten Work Items.

**LOW** (einfache Änderung, ein Objekt): Direkt `@AL Implementation Specialist` — kein Architekt, kein Conductor. Details: [Routing](#2--routing-komplexität-bestimmt-den-einstieg)


> [!IMPORTANT]
> - Wichtigster Grundsatz: **Qualitative Spezifikation → Qualitatives Ergebnis**
> - Genauere Beschreibungen im [readme.aproda.md](readme.aproda.md) und [README.md](../README.md)
> - ⚠️ Nicht kompatibel mit ACT (Aproda Copilot Template) von Antionio. **Nicht getestet und nicht empfohlen, beides gleichzeitig in einem Repo zu verwenden**

| Ohne Aproda ALDC | Mit Aproda ALDC |
|------------------|-----------------|
| Vibe Coding — Ergebnis unvorhersehbar | Spec-getrieben — KI arbeitet gegen einen Vertrag |
| Tests zuletzt (oder nie) | Integriertes Test Driven Development Enforcement |
| Reviews: „sieht gut aus" | BCQuality-zitierte Prüfungen |
| Kein OnPrem-Gate | Deploy-Run-Verify Cycle: deploy → run → fix → grün (echte Test-Runs gegen ASINST) |


---

## Was kann es?

### Kern-Agents (GitHub Copilot `@`-Syntax)

| Agent | Wann | Was |
|-------|------|-----|
| `@AL Architecture & Design Specialist` | Neue Features (MEDIUM/HIGH) | Lösungsdesign, Datenmodell, Integrationsstrategie |
| `@AL Development Conductor` | Vollständiger TDD-Zyklus | Orchestriert Planung → Impl. → Review mit Subagents |
| `@AL Implementation Specialist` | Implementieren, debuggen, fixen | Taktischer Code, direkte Änderungen |
| `@AL Triage — Reactive Diagnosis Specialist` | Bug, Fehler, Regression | Reproduzieren, Ursache lokalisieren, Fix-Empfehlung |
| `@AL Pre-Sales & Project Estimation Specialist` | Aufwandschätzung | PERT, SWOT, Kostenaufstellung |
| `@Dredd` | Unabhängiges Audit | BCQuality-zitierter statischer Review |

### Aproda-Erweiterungen

| Feature | Beschreibung |
|---------|--------------|
| **Deploy-Run-Verify Cycle** | `skill-aproda-deploy-run-verify` — publish → sync → run-tests → review gegen ASINST-Umgebung (später Container); loop bis grün |
| **ADO-Integration** | `skill-aproda-ado` — `req_name = {type}-{id}-{short-name}` (z.B. `bug-36370-posting-error`), ADO-URL in jedem Plan-Dokument |
| **HITL Validation** | Strukturiertes Issue-Tracking in `{req}-hitl-validation-issues.md` über mehrere Pre-PR Feedback-Runden ([Bitte Lesen](readme.aproda.md#hitl-validation)) |
| **Modul-Doku** | `al-doc-update`-Workflow — `<Modul>.reference.md` (EN) + `<Modul>.Handbuch.de-CH.md` |

### Workflows / Prompts

| Workflow | Wann aufrufen | Was es tut |
|----------|---------------|------------|
| `al-spec.create` | Vor jeder Implementierung | Erstellt `{req}.spec.md` aus Anforderung + Architektur |
| `al-build` | Nach Implementierung | Baut, paketiert und deployed die Extension |
| `al-pr-prepare` | Vor dem PR | Erzeugt Modul-Doku + PR-Beschreibung |
| `al-memory.create` | Nach langer Session | Aktualisiert `memory.md` für Session-Kontinuität |
| `al-context.create` | Projektstart / neuer Kollege | Generiert `context.md` als KI-Kontext-Einführung |
| `al-initialize` | Einmaliges Setup | Vollständiges Workspace- und Umgebungs-Setup |
| `al-doc-update` | Vor PR (Aproda) | Erstellt/aktualisiert `reference.md` + `Handbuch.de-CH.md` |

---

## Wie verwenden?

> [!TIP]
> Die interne VS Code Extension **Aproda ALDC** ist der empfohlene Einstieg. Sie verwaltet den Toolkit-Cache und die BCQuality-Einrichtung; ein lokaler Fork ist nur für Toolkit-Maintainer oder den nachfolgenden PowerShell-Fallback nötig.

### 1 — Installation und Projekt einrichten

1. Die interne `aproda-aldc.vsix` aus dem GitHub Release installieren: VS Code Command Palette → **Extensions: Install from VSIX...**.
2. VS Code bei Aufforderung neu laden und das Ziel-Git-Repository öffnen.
3. Beim ersten Hinweis **Getting Started** wählen. Dadurch öffnet sich der native VS Code Walkthrough.
4. Im Walkthrough **Configure Settings** ausführen. Der Wizard konfiguriert Developer Root, Toolkit-Quelle, Channel, BCQuality-Standort und Toolkit-Update-Checks.
5. **Apply Toolkit to Project** auswählen.
6. **Install / Update BCQuality** ausführen und danach bei Bedarf **Validate Installation**.

Für spätere Toolkit-Versionen stehen **Check for Updates** und optional **Preview Update Changes** bereit. Die Extension selbst prüft interne VSIX-Releases und bietet nach expliziter Bestätigung die Installation an.

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
3. Agent bestimmt `req_name = {type}-{id}-{short-name}` und legt `.github/plans/{type}-{id}-{short-name}/` an
```

### 4 — Deploy-Run-Verify Cycle (OnPrem Gate)

Nach jeder Implementierungsphase läuft der Deploy-Run-Verify Cycle automatisch:
- `al-developer` → einmal vor PR (LOW)
- `al-conductor` → nach jeder Phase (MEDIUM/HIGH)

Konfiguration: `Test/deploy-run-verify.config.jsonc` + `launch.json` im Projekt.

### 5 — PR vorbereiten

```
@workspace use al-pr-prepare
```
Erzeugt Modul-Doku (`al-doc-update`) und PR-Beschreibung. Erst nach grünem Deploy-Run-Verify Cycle und HITL Validation Sign-off ausführen.

---

## Wo finde ich was?

| Frage | Dokument |
|-------|----------|
| Toolkit-Struktur und Upgrade-Zyklus | [readme.aproda.md](readme.aproda.md) |
| Warum ist es so strukturiert? | [decisions.aproda.md](decisions.aproda.md) (D-1…D-22) |
| Infra-Details (K:, NST, SRP, Remote-PS) | [site-profile.aproda.md](site-profile.aproda.md) |
| ALDC-Framework-Spec | [docs/framework/ALDC-Core-Spec-v1.2.md](../docs/framework/ALDC-Core-Spec-v1.2.md) |
| Deploy-Run-Verify Cycle – Technisches | [skills/skill-aproda-deploy-run-verify/SKILL.md](../skills/skill-aproda-deploy-run-verify/SKILL.md) |
| Toolkit selbst erweitern | [readme.aproda.md — TL;DR](readme.aproda.md#tldr--extend-aproda-aldc--the-two-rules) |

---

> **Faustregel:** Spec kommt vor Code. KI generiert gegen einen Vertrag, nicht gegen eine Idee.
