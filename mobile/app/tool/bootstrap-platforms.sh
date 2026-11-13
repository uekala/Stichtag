#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK nicht gefunden. Installiere zuerst den Flutter Stable Channel." >&2
  exit 1
fi

if [[ -d android || -d ios ]]; then
  echo "Android- oder iOS-Projektdateien existieren bereits. Bootstrap wird aus Sicherheitsgründen abgebrochen." >&2
  echo "Prüfe die vorhandenen Plattformdateien und führe flutter create nicht erneut darüber aus." >&2
  exit 1
fi

flutter create \
  --project-name stichtag_mobile \
  --org de.uekala.stichtag \
  --platforms android,ios \
  .

python3 - <<'PY'
from pathlib import Path
import plistlib
import re

info_path = Path("ios/Runner/Info.plist")
with info_path.open("rb") as source:
    info = plistlib.load(source)
info["CFBundleDisplayName"] = "Stichtag"
info["NSCameraUsageDescription"] = (
    "Stichtag verwendet die Kamera, um den einmaligen Kopplungscode zu scannen."
)
with info_path.open("wb") as target:
    plistlib.dump(info, target, fmt=plistlib.FMT_XML, sort_keys=False)

android = Path("android/app/src/main")
manifest_path = android / "AndroidManifest.xml"
manifest = manifest_path.read_text(encoding="utf-8")
manifest, replacements = re.subn(
    r'android:icon="[^"]+"',
    'android:icon="@mipmap/ic_launcher"',
    manifest,
    count=1,
)
if replacements != 1:
    raise SystemExit("Das Standard-App-Icon in AndroidManifest.xml wurde nicht gefunden.")
manifest, replacements = re.subn(
    r'android:label="[^"]+"',
    'android:label="Stichtag"',
    manifest,
    count=1,
)
if replacements != 1:
    raise SystemExit("Der App-Name in AndroidManifest.xml wurde nicht gefunden.")
manifest_path.write_text(manifest, encoding="utf-8")

# App-Zeichen: ein Kalenderblatt mit einem markierten Tag auf dem Grün der App.
MARK = """    <!-- Kalenderblatt -->
    <path
        android:fillColor="{main}"
        android:pathData="M34,38 a6,6 0 0 1 6,-6 h28 a6,6 0 0 1 6,6 v32 a6,6 0 0 1 -6,6 h-28 a6,6 0 0 1 -6,-6 Z" />
    <!-- Ringe -->
    <path
        android:strokeColor="{main}"
        android:strokeWidth="5"
        android:strokeLineCap="round"
        android:pathData="M44,28 V36 M64,28 V36" />
    <!-- Markierter Tag -->
    <path
        android:fillColor="{dot}"
        android:pathData="M54,49 m-8,0 a8,8 0 1 0 16,0 a8,8 0 1 0 -16,0" />
"""
VECTOR = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
{mark}</vector>
"""

drawable = android / "res/drawable"
drawable.mkdir(parents=True, exist_ok=True)
(drawable / "ic_launcher_foreground.xml").write_text(
    VECTOR.format(mark=MARK.format(main="#FFFFFF", dot="#0B6E60")), encoding="utf-8")
# Einfarbige Fassung für die thematischen Symbole ab Android 13.
(drawable / "ic_launcher_monochrome.xml").write_text(
    VECTOR.format(mark=MARK.format(main="#FFFFFF", dot="#66FFFFFF")), encoding="utf-8")
(drawable / "ic_launcher_background.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="#12907E"
        android:endColor="#07453C" />
</shape>
""", encoding="utf-8")

adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""
resource_dir = android / "res" / "mipmap-anydpi-v26"
resource_dir.mkdir(parents=True, exist_ok=True)
(resource_dir / "ic_launcher.xml").write_text(adaptive, encoding="utf-8")
(resource_dir / "ic_launcher_round.xml").write_text(adaptive, encoding="utf-8")
PY

python3 "$(dirname "${BASH_SOURCE[0]}")/configure-android-manifest.py"

echo "Android- und iOS-Projektdateien wurden erstellt."
echo "Nächster Schritt: flutter pub get && flutter test"
