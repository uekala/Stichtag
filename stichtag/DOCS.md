# Stichtag

## Bedienung

Die Oberfläche öffnest du über den Eintrag **Stichtag** in der Seitenleiste.

- **Heute**: fällige Dosen, Eintragen, nächste Injektionsstelle laut Rotation
- **Protokolle**: Peptid, Dosis, Rhythmus, Startdatum, Uhrzeit, Zykluslänge
- **Verlauf**: alle Einträge, filterbar nach Peptid
- **Körper**: Gewicht, Bauchumfang, Körperfett mit Verlaufskurve
- **Vials & Rechner**: Vorrat pro Vial und Misch-Rechner für U-100-Spritzen
- **Daten**: Erinnerungen, Injektionsstellen, Export, Import

## Erinnerungen

1. Unter **Daten → Erinnerungen** einen Benachrichtigungsdienst wählen, zum Beispiel `notify.mobile_app_<dein_handy>`.
2. Mit **Test senden** prüfen, ob die Nachricht ankommt.
3. Jedem Protokoll, das erinnern soll, eine Uhrzeit geben.

Erinnert wird zur Uhrzeit des Protokolls, solange die Dosis an dem Tag noch nicht eingetragen ist. Optional kommt nach einer einstellbaren Zahl von Minuten eine zweite Erinnerung. Protokolle ohne Uhrzeit erinnern nicht.

## Daten

Alle Daten liegen in `/data/state.json` der App und sind Teil der Home-Assistant-Backups. Über **Daten → Export** lässt sich zusätzlich eine JSON-Datei sichern.

## Hinweis

Die App ist ein Protokoll und ein Rechenhilfsmittel. Sie empfiehlt keine Substanzen, Dosen oder Zyklen und ersetzt keine ärztliche Beratung.
