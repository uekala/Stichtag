#!/usr/bin/env python3
"""Stichtag: Weboberfläche, Datenspeicher und Erinnerungen."""
import json
import os
import threading
import time
import urllib.error
import urllib.request
from datetime import date, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA_DIR = os.environ.get("DATA_DIR", "/data")
WWW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "www")
TOKEN = os.environ.get("SUPERVISOR_TOKEN", "")
DEV = os.environ.get("DEV") == "1"
PORT = int(os.environ.get("PORT", "8099"))
INGRESS_GATEWAY = "172.30.32.2"
MAX_BODY = 5 * 1024 * 1024
STATE_FILE = os.path.join(DATA_DIR, "state.json")
NOTIFIED_FILE = os.path.join(DATA_DIR, "notified.json")
DEFAULT_SITES = [
    "Bauch links", "Bauch rechts", "Oberschenkel links",
    "Oberschenkel rechts", "Flanke links", "Flanke rechts",
]
LISTS = ("protocols", "logs", "vials", "body")

lock = threading.Lock()


def blank():
    return {
        "v": 1, "rev": 0, "demo": False,
        "protocols": [], "logs": [], "vials": [], "body": [],
        "sites": list(DEFAULT_SITES),
        "settings": {"notify": "", "followup": 0},
    }


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def load_state():
    s = read_json(STATE_FILE, None)
    if not isinstance(s, dict):
        return blank()
    base = blank()
    base.update(s)
    return base


def valid_state(s):
    if not isinstance(s, dict):
        return False
    if not all(isinstance(s.get(k), list) for k in LISTS):
        return False
    return isinstance(s.get("sites"), list) and isinstance(s.get("settings"), dict)


# ---------- Fälligkeit (gleiche Regeln wie in der Oberfläche) ----------

def is_due(p, day):
    if not p.get("active") or p.get("demo"):
        return False
    try:
        start = date.fromisoformat(str(p.get("start", "")))
        weeks = int(p.get("weeks") or 0)
        diff = (day - start).days
        if diff < 0 or (weeks > 0 and diff >= weeks * 7):
            return False
        kind = p.get("type")
        if kind == "daily":
            return True
        if kind == "interval":
            return diff % max(1, int(p.get("n") or 1)) == 0
        return (day.weekday() + 1) % 7 in (p.get("days") or [])
    except (TypeError, ValueError):
        return False


def next_site(state):
    last = {}
    for log in state["logs"]:
        site, ts = log.get("site"), str(log.get("ts", ""))
        if site and ts > last.get(site, ""):
            last[site] = ts
    sites = [str(s) for s in state["sites"]]
    return sorted(sites, key=lambda s: last.get(s, ""))[0] if sites else ""


def fmt(n):
    try:
        return ("%.3f" % float(n)).rstrip("0").rstrip(".").replace(".", ",")
    except (TypeError, ValueError):
        return str(n)


# ---------- Home Assistant ----------

def supervisor(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        "http://supervisor" + path, method=method, data=data,
        headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


_panel_url = None


def panel_url():
    global _panel_url
    if _panel_url is None:
        try:
            info = supervisor("GET", "/addons/self/info")
            _panel_url = "/hassio/ingress/" + info["data"]["slug"]
        except Exception:
            _panel_url = ""
    return _panel_url


def notify_services():
    names = []
    for dom in supervisor("GET", "/core/api/services") or []:
        if dom.get("domain") == "notify":
            names = ["notify." + n for n in dom.get("services", {})]
    return sorted(names, key=lambda n: (not n.startswith("notify.mobile_app_"), n))


def send(service, message, tag):
    name = service.split(".", 1)[1] if "." in service else service
    if not name.replace("_", "").isalnum():
        raise ValueError("Ungültiger Dienstname")
    payload = {"title": "Stichtag", "message": message}
    if name.startswith("mobile_app_"):
        data = {"tag": tag}
        url = panel_url()
        if url:
            data["url"] = url
            data["clickAction"] = url
        payload["data"] = data
    supervisor("POST", "/core/api/services/notify/" + name, payload)


def check_reminders(now=None, sender=send):
    now = now or datetime.now()
    day = now.date()
    day_s = day.isoformat()
    with lock:
        state = load_state()
        notified = read_json(NOTIFIED_FILE, {})
    if not isinstance(notified, dict):
        notified = {}
    service = str(state["settings"].get("notify") or "")
    try:
        followup = int(state["settings"].get("followup") or 0)
    except (TypeError, ValueError):
        followup = 0
    changed = False
    for key in [k for k in notified if not k.startswith(day_s)]:
        del notified[key]
        changed = True
    if service:
        done = {l.get("pid") for l in state["logs"] if str(l.get("ts", ""))[:10] == day_s}
        for p in state["protocols"]:
            t = str(p.get("time") or "")
            if not t or not is_due(p, day) or p.get("id") in done:
                continue
            try:
                due_at = datetime.combine(day, datetime.strptime(t, "%H:%M").time())
            except ValueError:
                continue
            if now < due_at:
                continue
            key = day_s + "|" + str(p.get("id"))
            rec = notified.get(key)
            if rec is None:
                text = "%s ist fällig: %s %s" % (p.get("name"), fmt(p.get("dose")), p.get("unit"))
            elif followup > 0 and rec["count"] == 1 and now.timestamp() - rec["last"] >= followup * 60:
                text = "%s ist noch offen: %s %s" % (p.get("name"), fmt(p.get("dose")), p.get("unit"))
            else:
                continue
            site = next_site(state)
            if site:
                text += ". Nächste Stelle: " + site
            try:
                sender(service, text, "peptid-" + str(p.get("id")))
            except Exception as e:  # nächster Durchlauf versucht es erneut
                print("Erinnerung fehlgeschlagen:", e, flush=True)
                continue
            notified[key] = {"count": (rec["count"] + 1) if rec else 1, "last": now.timestamp()}
            changed = True
    if changed:
        with lock:
            write_json(NOTIFIED_FILE, notified)


def reminder_loop():
    while True:
        try:
            check_reminders()
        except Exception as e:
            print("Fehler in der Erinnerungsschleife:", e, flush=True)
        time.sleep(30)


# ---------- HTTP ----------

class Handler(BaseHTTPRequestHandler):
    server_version = "Stichtag"

    def log_message(self, *args):
        pass

    def reply(self, code, body, ctype="application/json", extra=None):
        raw = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)

    def allowed(self):
        if DEV or self.client_address[0] == INGRESS_GATEWAY:
            return True
        self.reply(403, {"error": "Nur über Home Assistant erreichbar"})
        return False

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > MAX_BODY:
            return None
        try:
            return json.loads(self.rfile.read(n))
        except ValueError:
            return None

    def do_GET(self):
        if not self.allowed():
            return
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path in ("/", "/index.html"):
            with open(os.path.join(WWW, "index.html"), "rb") as f:
                self.reply(200, f.read(), "text/html")
        elif path == "/api/state":
            with lock:
                self.reply(200, load_state())
        elif path == "/api/export":
            with lock:
                state = load_state()
            name = "stichtag-%s.json" % date.today().isoformat()
            self.reply(200, json.dumps(state, ensure_ascii=False, indent=1).encode(),
                       extra={"Content-Disposition": 'attachment; filename="%s"' % name})
        elif path == "/api/notify-services":
            try:
                self.reply(200, notify_services())
            except Exception:
                self.reply(200, [])
        else:
            self.reply(404, {"error": "Nicht gefunden"})

    def do_PUT(self):
        if not self.allowed():
            return
        if self.path.split("?", 1)[0].rstrip("/") != "/api/state":
            return self.reply(404, {"error": "Nicht gefunden"})
        new = self.body()
        if not valid_state(new):
            return self.reply(400, {"error": "Ungültige Daten"})
        with lock:
            cur = load_state()
            if int(new.get("rev") or 0) != int(cur.get("rev") or 0):
                return self.reply(409, cur)
            new["rev"] = int(cur.get("rev") or 0) + 1
            write_json(STATE_FILE, new)
        self.reply(200, {"rev": new["rev"]})

    def do_POST(self):
        if not self.allowed():
            return
        if self.path.split("?", 1)[0].rstrip("/") != "/api/test-notify":
            return self.reply(404, {"error": "Nicht gefunden"})
        req = self.body() or {}
        try:
            send(str(req.get("service") or ""), "Testnachricht: Erinnerungen funktionieren.", "peptid-test")
            self.reply(200, {"ok": True})
        except Exception as e:
            self.reply(200, {"ok": False, "error": str(e)})


if __name__ == "__main__":
    os.makedirs(DATA_DIR, exist_ok=True)
    threading.Thread(target=reminder_loop, daemon=True).start()
    print("Stichtag läuft auf Port %d" % PORT, flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
