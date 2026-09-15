

# pptx Anpassungen Plan


* drv Folie besser ausrichten; und am anfang fehlt "anpassung/fix" als kästchen.
* "->" in echten pfeil-symbol ändern
* drv in entwicklungsprozess folie mit den 3 pfeilen und oben drüber oder als fast voller kreis mit pfeil (als loop)
* entwicklungsprozess (oder neu folie?) mit 2 einstiegspunkte oder möglichkeiten: Aus Supportticket/debug/fehlerfall -> AL Triage agent -> ... ; und Neuanforderung/Change Request -> komplexitäts entscheid (selbst oder durch triage, oder conductor oder architect) -> LOW direkt; medium zu conductor oder architect; high zu architect. 
* den entwicklungsprozess insgesamt in die richtung: zuerst gesamt prozess (eventuell eher grob), dann prozesse-teile von vorne-nach hinten im prozess durchgehen und einzeln beleuchten.
* am ende diagram mit des gesamt prozesses ein komplexes diagramm/visualisierung mit allen teilprozessen.


Teilprozesse

* Start via ADO Work Item (und ggf. Spez dokument)
* Komplexity beurteilung
* HITL Verifikation
* AL translation prozess, optimiert, günstiger agent, translations in review state poedit gate
* PR Prepare und die: Gates, Teilprozesse, al-doc-update (ref +handbuch), BCQuality-Review (Dredd)
* Modul-Dokumentation (oder nur bei PR.. hmm?)

Sonstiges muss auch noch rein:
* Gates, was gibt es für welche?, warum? usw.
* Eventuell die Agents noch genauer vorstellen.



---

Trennfolie / teil 2

anwendungsszenarien
* Support zu prüfen -> Triage -> AL Tests erstellen: um fehler nachzuvollziehen + Ist zustand zu messen. -> Fix implementieren -> Erneut Tests ausführen (eventuell DRV-Cycle) -> Review / Abschluss
* BCQuality + Dredd Agent -> Z.B.: Bestehendes Projekt analysieren, Schwachstellen identifizieren, Guildelines bereinigen, Verbesserungen implementieren.
* Beispiel ASCDC Extensibility (ref unten: ASCDC Extensibility)


---

Trennfolie / teil 3

Ausblick (am schluss):

* Fkh Freddy Kubernetes Helper ->  https://github.com/Freddy-DK/Fkh/blob/main/README.md -> inkl dem Bild.
* FreddyK - Blog: pormpt e., Loop enginieering, .. steigerungen. -> https://freddysblog.com/2026/08/15/the-engineering-stairway-to-heaven/



---

## References:

### ASCDC Extensibility

ASCDC Extensibility mit A-ALDC (für Azure Storage Proxy Function)

Storage-Extensibility
Provider-neutrale Integration Events für List, Copy und Get mit IsHandled-Pattern. Proxy-Apps können Storage-Zugriffe ersetzen, ohne Azure-Zugangsdaten oder direkte Blob-Clients zu verwenden.

Erweiterbare Container-Verwaltung
Neue temporäre WORM-Container-Entry-Tabelle als neutrales Datenformat für externe Storage-Provider.

Real-Verifikation
Storage-Setup wird mit einer echten Datei geprüft; die schreibende Aktion ist standardmässig verborgen.

Qualität und Tests
29 relevante WORM-Tests erfolgreich.

Zeithorizont
~16 Stunden vom 11.–13. September 2026: Konzeption, Implementierung, Testausbau, Runtime-Verifikation und Abschluss.