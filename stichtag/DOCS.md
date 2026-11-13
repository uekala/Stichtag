# Stichtag

## Bedienung

Die Oberfläche öffnest du über den Eintrag **Stichtag** in der Seitenleiste.

- **Heute**: fällige Dosen, Eintragen, nächste Injektionsstelle laut Rotation
- **Protokolle**: Peptid, Dosis, Rhythmus, Startdatum, Uhrzeit, Zykluslänge
- **Verlauf**: alle Einträge, filterbar nach Peptid
- **Körper**: Gewicht, Bauchumfang, Körperfett mit Verlaufskurve
- **Vials & Rechner**: Vorrat pro Vial und Misch-Rechner für U-100-Spritzen
- **Daten**: Erinnerungen, Handy-App, Injektionsstellen, Export, Import

## Erinnerungen

1. Unter **Daten → Erinnerungen** einen Benachrichtigungsdienst wählen, zum Beispiel `notify.mobile_app_<dein_handy>`.
2. Mit **Test senden** prüfen, ob die Nachricht ankommt.
3. Jedem Protokoll, das erinnern soll, eine Uhrzeit geben.

Erinnert wird zur Uhrzeit des Protokolls, solange die Dosis an dem Tag noch nicht eingetragen ist. Optional kommt nach einer einstellbaren Zahl von Minuten eine zweite Erinnerung. Protokolle ohne Uhrzeit erinnern nicht.

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
