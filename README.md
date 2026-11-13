# Stichtag

Peptid-Tracker als App (Add-on) für Home Assistant: Dosen, Protokolle, Vials und Körperwerte protokollieren und sich über Home Assistant an fällige Dosen erinnern lassen.

## Installation

### Über dieses Repository

1. In Home Assistant **Einstellungen → Apps → App-Store** öffnen.
2. Über das Menü oben rechts **Repositories** wählen und `https://github.com/uekala/stichtag` eintragen.
3. **Stichtag** installieren und starten.

### Lokal, ohne GitHub

1. Den Ordner `stichtag` nach `/addons/stichtag` auf dem Home-Assistant-Gerät kopieren (Samba oder SSH).
2. Im App-Store über das Menü **Nach Updates suchen** wählen.
3. **Stichtag** unter den lokalen Apps installieren und starten.

## Handy-App für Android und iOS

Unter `mobile/app` liegt eine Flutter-App, die mit demselben Datenstand arbeitet wie die Oberfläche in Home
Assistant: Heute, Protokolle, Verlauf, Körperwerte, Vials und Misch-Rechner. Gekoppelt wird sie per QR-Code unter
**Daten → Handy-App**. Die App spricht nur per HTTPS mit dem eigenen Stichtag-Server; wie das eingerichtet wird,
steht in der [Dokumentation](stichtag/DOCS.md#handy-app).

Signierte Android-Versionen hängen an den [Releases](https://github.com/uekala/stichtag/releases) (Einträge
„Stichtag Mobile“), sobald eine Version veröffentlicht ist. Details zum Bauen stehen in [mobile/app/README.md](mobile/app/README.md).

## Hinweis

Stichtag ist ein Protokoll und ein Rechenhilfsmittel. Es empfiehlt keine Substanzen, Dosen oder Zyklen und ersetzt
keine ärztliche Beratung.

Die QR-Codes erzeugt [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) von Kazuhiko Arase
(MIT-Lizenz).

Die Bedienung steht in [stichtag/DOCS.md](stichtag/DOCS.md).
