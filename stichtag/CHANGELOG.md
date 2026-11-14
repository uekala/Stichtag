# Changelog

## 1.3.1

- Dosen werden nur noch in mg eingegeben; die Auswahl der Einheit entfällt. Alte Einträge in mcg rechnet das Formular beim Bearbeiten um
- Misch-Rechner und Vials zeigen mg und mg/ml

## 1.3.0

- Dosisstufen je Protokoll: Ab einer Woche gilt eine neue Dosis; Heute, Erinnerungen und „Erledigt“ rechnen damit
- Vials haben eine Haltbarkeit in Tagen, mit Hinweis unter Heute und einer Warnung, wenn die Frist abgelaufen ist
- Drei Sensoren für Home Assistant: offene Dosen, Einhaltung über 7 Tage, nächste Dosis

## 1.2.2

- Das Feld „Peptid“ schlägt eigene und gängige Namen vor

## 1.2.1

- Behoben: Die Handy-App konnte nicht koppeln und nicht speichern, weil der Server in Stücken gesendete Anfragen nicht las

## 1.2.0

- Heute: „Erledigt“ trägt die Dosis mit einem Klick ein, „Rückgängig“ nimmt sie zurück; dazu die nächsten 7 Tage, ein Fortschrittsring und Hinweise auf fast leere Vials
- Neuer Reiter Auswertung: Einhaltung über 8 Wochen, Zahlen je Peptid, Befinden im Verlauf, Verteilung der Stellen
- Einträge im Verlauf lassen sich bearbeiten
- Erinnerungen: „Erledigt“ direkt in der Benachrichtigung der Home-Assistant-App, Warnung bei Vials unter 20 %
- Eigenes Symbol für die App

## 1.1.1

- Das Protokoll nennt die Adresse, wenn die Handy-API eine Anfrage ablehnt. Das hilft beim Einrichten von `trusted_proxies`.

## 1.1.0

- Handy-App: Kopplung per QR-Code unter Daten → Handy-App, Geräteliste mit Entfernen
- Neue Einstellungen `mobile_server_url` und `trusted_proxies`, optionaler Port 8098 für die Handy-API
- Die Oberfläche ist jetzt Administratoren vorbehalten

## 1.0.0

- Erste Version: Heute-Ansicht, Protokolle, Verlauf, Körperwerte, Vials, Misch-Rechner
- Erinnerungen über einen Benachrichtigungsdienst von Home Assistant
