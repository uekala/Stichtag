# Stichtag fürs Handy

Flutter-App für Android und iOS. Sie zeigt und ändert denselben Datenstand wie die Stichtag-Oberfläche in Home
Assistant und braucht einen eigenen Stichtag-Server (ab Version 1.1.0).

## Entwickeln

```bash
cd mobile/app
bash tool/bootstrap-platforms.sh   # erzeugt android/ und ios/, nur einmal
flutter pub get
flutter analyze
flutter test
flutter run
```

Die Ordner `android/` und `ios/` liegen nicht im Repository. `tool/bootstrap-platforms.sh` erzeugt sie mit
`flutter create` und richtet App-Namen, App-Zeichen, Kamera-Hinweis und Backup-Ausschlüsse ein.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `lib/core` | Fälligkeitsregeln, Kopplungscode, HTTPS-Client, Sitzungsspeicher, Datenhaltung |
| `lib/features` | Bildschirme: Kopplung, Heute, Protokolle, Verlauf, Körper, Vials & Rechner, Mehr |
| `test` | Tests für Regeln, Kopplungscode und die wichtigsten Abläufe |

Die App speichert nur Serveradresse und Gerätetoken, und zwar im Schlüsselspeicher des Handys. Die Daten selbst
bleiben auf dem Server.

## Veröffentlichen

Ein Tag `mobile-v<Version>` (passend zur Version in `pubspec.yaml`) baut eine signierte Android-APK und hängt sie
an ein GitHub-Release. Dafür müssen im Repository die Secrets `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` und `ANDROID_KEY_PASSWORD` hinterlegt sein. Ohne Tag entsteht bei
jedem Push eine Debug-APK als Artefakt des Workflows; sie eignet sich zum Testen, lässt sich aber nicht über eine
installierte Version installieren.
