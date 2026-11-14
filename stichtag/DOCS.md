# Stichtag

## Bedienung

Die Oberfläche öffnest du über den Eintrag **Stichtag** in der Seitenleiste.

- **Heute**: fällige Dosen, Eintragen, nächste Injektionsstelle laut Rotation
- **Protokolle**: Peptid, Dosis, Rhythmus, Startdatum, Uhrzeit, Zykluslänge, optional Dosisstufen ab einer Woche
- **Verlauf**: alle Einträge, filterbar nach Peptid, mit Bearbeiten
- **Auswertung**: Einhaltung über 8 Wochen, Zahlen je Peptid, Befinden, Stellen
- **Körper**: Gewicht, Bauchumfang, Körperfett mit Verlaufskurve; auf Wunsch mit Markierungen, ab wann eine andere Dosis eingetragen wurde
- **Vials & Rechner**: Vorrat und Haltbarkeit pro Vial, Misch-Rechner für U-100-Spritzen
- **Daten**: Erinnerungen, Handy-App, Injektionsstellen, Liste der Nebenwirkungen, Export, Import

## Erinnerungen

1. Unter **Daten → Erinnerungen** einen Benachrichtigungsdienst wählen, zum Beispiel `notify.mobile_app_<dein_handy>`.
2. Mit **Test senden** prüfen, ob die Nachricht ankommt.
3. Jedem Protokoll, das erinnern soll, eine Uhrzeit geben.

Erinnert wird zur Uhrzeit des Protokolls, solange die Dosis an dem Tag noch nicht eingetragen ist. Optional kommt nach einer einstellbaren Zahl von Minuten eine zweite Erinnerung. Protokolle ohne Uhrzeit erinnern nicht.

Läuft die Erinnerung über die Home-Assistant-App (`notify.mobile_app_…`), hat sie den Knopf **Erledigt**. Ein Tipp
darauf trägt die Dosis mit den Vorgaben des Protokolls und der nächsten Stelle der Rotation ein.

Fällt ein Vial unter 20 % Rest oder läuft seine eingetragene Haltbarkeit ab, kommt jeweils einmal eine Warnung. Das lässt sich unter **Daten → Erinnerungen** abschalten.

## Sensoren

Stichtag legt drei Sensoren in Home Assistant an und hält sie aktuell:

| Sensor | Zustand | Attribute |
|---|---|---|
| `sensor.stichtag_offene_dosen` | Zahl der heute noch offenen Dosen | `faellig`, `erledigt`, `offen` (Namen) |
| `sensor.stichtag_einhaltung_7_tage` | Einhaltung der letzten 7 Tage in Prozent | `faellig`, `erledigt` |
| `sensor.stichtag_naechste_dosis` | zum Beispiel „Heute 20:00 Name“ | `peptid`, `dosis`, `datum`, `uhrzeit` |

### Karten fürs Dashboard

Im Dashboard **Karte hinzufügen → Manuell** wählen und einfügen:

```yaml
type: entities
title: Stichtag
entities:
  - entity: sensor.stichtag_naechste_dosis
    name: Nächste Dosis
  - entity: sensor.stichtag_offene_dosen
    name: Heute offen
  - entity: sensor.stichtag_einhaltung_7_tage
    name: Einhaltung 7 Tage
```

Die Einhaltung als Anzeige:

```yaml
type: gauge
entity: sensor.stichtag_einhaltung_7_tage
name: Einhaltung 7 Tage
min: 0
max: 100
severity:
  green: 90
  yellow: 70
  red: 0
```

Die Sensoren eignen sich für Dashboards und Automationen. Sie haben keine eindeutige ID und lassen sich deshalb
nicht in der Oberfläche umbenennen. Nach einem Neustart von Home Assistant erscheinen sie innerhalb einer Minute
wieder.

## Handy-App

Die Stichtag-App für Android und iOS arbeitet mit demselben Datenstand wie diese Oberfläche. Sie spricht nur per
HTTPS mit Stichtag, und zwar über einen Proxy, der das Zertifikat bereitstellt, zum Beispiel einen Tailscale-Service.
Eine Portfreigabe am Router ist nicht nötig und nicht vorgesehen.

1. Unter **Netzwerk** dem Port `8098/tcp` einen Host-Port geben, zum Beispiel `18098`.
2. Den HTTPS-Proxy auf `http://127.0.0.1:18098` zeigen lassen. Im Tailscale-Add-on ist das ein Eintrag unter
   `services` mit `protocol: https` und `port: 443`.
3. In der Konfiguration dieser App eintragen:
   - `mobile_server_url`: die HTTPS-Adresse des Proxys, zum Beispiel `https://stichtag.<tailnet>.ts.net`
   - `trusted_proxies`: die Adresse, von der der Proxy bei Stichtag ankommt. Läuft er auf dem Home-Assistant-Host,
     ist das in der Regel `172.30.32.1/32`.
4. Die App neu starten, **Daten → Handy-App → Handy koppeln** wählen und den QR-Code mit der Handy-App scannen.

Der Kopplungscode gilt 10 Minuten und nur einmal. Jedes Handy bekommt ein eigenes Token, von dem Stichtag nur einen
Hash speichert. Unter **Daten → Handy-App** lässt sich jedes Handy einzeln entfernen.

Anfragen, die nicht von einem Eintrag aus `trusted_proxies` kommen oder nicht per HTTPS beim Proxy ankamen, lehnt
die Handy-API ab. Die abgelehnte Adresse steht dann im Protokoll der App; trage sie bei Bedarf in
`trusted_proxies` ein.

## Daten

Alle Daten liegen in `/data/state.json` der App, gekoppelte Handys in `/data/devices.json`. Beides ist Teil der Home-Assistant-Backups. Über **Daten → Export** lässt sich zusätzlich eine JSON-Datei sichern.

## Hinweis

Die App ist ein Protokoll und ein Rechenhilfsmittel. Sie empfiehlt keine Substanzen, Dosen oder Zyklen und ersetzt keine ärztliche Beratung.
