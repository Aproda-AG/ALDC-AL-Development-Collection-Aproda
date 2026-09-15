# Wir beginnen mit implementierungsphase


du bist der orchestrator, nutz subagents gezielt für die aufgaben.

**Ausbaustufe 1**

1) Starte Subagent für implementierung - Claude Sonnet 5
Gib ihm die "stage-1.spec.md" mit und sinnvolle anweisungen. Er soll präzise und strukturiert arbeiten.

2) **als separater Schritt danach** starte 2. subagent für review - auch Claude Sonnet 5
er soll implementierung prüfen -> stimmt impl mit spec überein? Ist es plausibel? -> und dir dann ein review result geben.

3) als folge von `2)` Gibt es etwas zu fixen nach review? oder kannst du was testen? Wenn Ja, beauftrage GPT 5.6 Luna als subagent, um das auszuführen.

4) Führe abschließende Tests - beauftrage GPT 5.6 Luna als subagent - durch, um sicherzustellen, dass alle Änderungen korrekt implementiert wurden und die Spezifikationen erfüllen. Dann gibt zusammenfassend ein finales Review-Ergebnis.

---


## Status / was habe ich gemacht / wo bin ich dran

### Orchestrator-Entscheidungen (getroffen ohne Rückfrage, da abwesend — bitte gegenlesen)

### Verlauf

## Offen für dich


