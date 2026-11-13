#!/usr/bin/env python3
"""Stichtag: Weboberfläche, Datenspeicher und Erinnerungen."""
import base64
import hashlib
import hmac
import ipaddress
import json
import os
import secrets
import socket
import struct
import threading
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

DATA_DIR = os.environ.get("DATA_DIR", "/data")
WWW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "www")
TOKEN = os.environ.get("SUPERVISOR_TOKEN", "")
DEV = os.environ.get("DEV") == "1"
DEV_MOBILE = os.environ.get("DEV_MOBILE") == "1"
VERSION = "1.2.0"
PORT = int(os.environ.get("PORT", "8099"))
MOBILE_PORT = int(os.environ.get("MOBILE_PORT", "8098"))
PAIRING_TTL = 600
ACTION_DONE = "STICHTAG_DONE_"
LOW_VIAL = 0.2
INGRESS_GATEWAY = "172.30.32.2"
MAX_BODY = 5 * 1024 * 1024
STATE_FILE = os.path.join(DATA_DIR, "state.json")
NOTIFIED_FILE = os.path.join(DATA_DIR, "notified.json")
DEVICES_FILE = os.path.join(DATA_DIR, "devices.json")
OPTIONS_FILE = os.path.join(DATA_DIR, "options.json")
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


def put_state(new):
    """Speichert den Stand, wenn er auf der aktuellen Revision aufbaut."""
    if not valid_state(new):
        return 400, {"error": "Ungültige Daten"}
    with lock:
        cur = load_state()
        if int(new.get("rev") or 0) != int(cur.get("rev") or 0):
            return 409, cur
        new["rev"] = int(cur.get("rev") or 0) + 1
        write_json(STATE_FILE, new)
    return 200, {"rev": new["rev"]}


# ---------- Handy-App: Einstellungen, Kopplung, Geräte ----------

def options():
    opts = read_json(OPTIONS_FILE, {})
    return opts if isinstance(opts, dict) else {}


def mobile_server_url():
    """HTTPS-Adresse für die Handy-App aus den App-Einstellungen, sonst leer."""
    raw = str(options().get("mobile_server_url") or "").strip()
    try:
        url = urlsplit(raw)
        if url.scheme != "https" or not url.hostname or url.username or url.query or url.fragment:
            return ""
        if url.path not in ("", "/"):
            return ""
        return "https://" + url.netloc
    except ValueError:
        return ""


def trusted_networks():
    nets = []
    for part in str(options().get("trusted_proxies") or "").split(","):
        part = part.strip()
        if not part:
            continue
        try:
            nets.append(ipaddress.ip_network(part, strict=False))
        except ValueError:
            print("Ungültiger Eintrag in trusted_proxies:", part, flush=True)
    return nets


def sha256(text):
    return hashlib.sha256(text.encode()).hexdigest()


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


pair_lock = threading.Lock()
pairings = {}   # Hash des Kopplungscodes -> Ablaufzeit
attempts = {}   # Gegenstelle -> Zeitpunkte fehlgeschlagener Versuche


def create_pairing():
    secret = secrets.token_urlsafe(32)
    now = time.time()
    with pair_lock:
        for key in [k for k, exp in pairings.items() if exp < now]:
            del pairings[key]
        pairings[sha256(secret)] = now + PAIRING_TTL
    return secret


def redeem_pairing(secret):
    with pair_lock:
        exp = pairings.pop(sha256(str(secret)), None)
    return exp is not None and exp >= time.time()


def too_many_attempts(peer, limit=10, window=60):
    now = time.time()
    with pair_lock:
        recent = [t for t in attempts.get(peer, []) if now - t < window]
        attempts[peer] = recent
        return len(recent) >= limit


def note_failure(peer):
    with pair_lock:
        attempts.setdefault(peer, []).append(time.time())


def load_devices():
    devices = read_json(DEVICES_FILE, [])
    return devices if isinstance(devices, list) else []


def add_device(name):
    token = secrets.token_urlsafe(32)
    name = " ".join(str(name or "").split())[:60] or "Handy"
    device = {"id": secrets.token_hex(8), "name": name, "token_hash": sha256(token),
              "created": now_iso(), "last_used": now_iso()}
    with lock:
        devices = load_devices()
        devices.append(device)
        write_json(DEVICES_FILE, devices)
    return device, token


def find_device(token):
    if not token:
        return None
    wanted = sha256(token)
    with lock:
        devices = load_devices()
        for device in devices:
            if hmac.compare_digest(str(device.get("token_hash")), wanted):
                if str(device.get("last_used"))[:13] != now_iso()[:13]:
                    device["last_used"] = now_iso()
                    write_json(DEVICES_FILE, devices)
                return device
    return None


def remove_device(device_id):
    with lock:
        devices = load_devices()
        kept = [d for d in devices if d.get("id") != device_id]
        if len(kept) != len(devices):
            write_json(DEVICES_FILE, kept)
            return True
    return False


def public_device(device):
    return {k: device.get(k) for k in ("id", "name", "created", "last_used")}


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


def vial_left(state, vial):
    """Rest im Vial als (mcg, Anteil); None, wenn kein Inhalt eingetragen ist."""
    try:
        total = float(vial.get("mg") or 0) * 1000
        used = 0.0
        for log in state["logs"]:
            if log.get("vialId") != vial.get("id"):
                continue
            if log.get("unit") == "mcg":
                used += float(log.get("dose") or 0)
            elif log.get("unit") == "mg":
                used += float(log.get("dose") or 0) * 1000
    except (TypeError, ValueError):
        return None
    if total <= 0:
        return None
    left = max(0.0, total - used)
    return left, left / total


def mark_done(pid, now=None):
    """Trägt die heutige Dosis eines Protokolls ein, wie ein Tipp auf „Erledigt“."""
    now = now or datetime.now()
    day_s = now.date().isoformat()
    with lock:
        state = load_state()
        protocol = next((p for p in state["protocols"] if str(p.get("id")) == pid), None)
        if protocol is None:
            return False
        if any(l.get("pid") == pid and str(l.get("ts", ""))[:10] == day_s for l in state["logs"]):
            return False
        state["logs"].append({
            "id": secrets.token_hex(6), "ts": now.strftime("%Y-%m-%dT%H:%M"), "pid": pid,
            "name": protocol.get("name"), "dose": protocol.get("dose"), "unit": protocol.get("unit"),
            "site": next_site(state), "feel": 0, "note": "", "vialId": protocol.get("vialId") or "",
        })
        state["rev"] = int(state.get("rev") or 0) + 1
        write_json(STATE_FILE, state)
        service = str(state["settings"].get("notify") or "")
    if service.startswith("notify.mobile_app_"):
        try:
            supervisor("POST", "/core/api/services/notify/" + service.split(".", 1)[1],
                       {"message": "clear_notification", "data": {"tag": "peptid-" + pid}})
        except Exception:
            pass
    return True


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


def send(service, message, tag, actions=None):
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
        if actions:
            data["actions"] = actions
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
    for key in [k for k in notified if not k.startswith(day_s) and not k.startswith("vial|")]:
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
            pid = str(p.get("id"))
            actions = [{"action": ACTION_DONE + pid, "title": "Erledigt"}] if pid.isalnum() else None
            try:
                sender(service, text, "peptid-" + pid, actions)
            except Exception as e:  # nächster Durchlauf versucht es erneut
                print("Erinnerung fehlgeschlagen:", e, flush=True)
                continue
            notified[key] = {"count": (rec["count"] + 1) if rec else 1, "last": now.timestamp()}
            changed = True
        # Vorrat: einmal warnen, sobald ein Vial unter 20 % fällt; nach dem Auffüllen wieder scharf.
        warn = state["settings"].get("lowvial") is not False
        for vial in state["vials"]:
            key = "vial|" + str(vial.get("id"))
            level = None if vial.get("demo") else vial_left(state, vial)
            if not warn or level is None or level[1] >= LOW_VIAL:
                if key in notified:
                    del notified[key]
                    changed = True
                continue
            if key in notified:
                continue
            if level[0] <= 0:
                text = "Vial %s ist leer." % vial.get("name")
            else:
                text = "Vial %s ist fast leer: noch %s mg." % (vial.get("name"), fmt(level[0] / 1000))
            try:
                sender(service, text, "peptid-vial-" + str(vial.get("id")), None)
            except Exception as e:
                print("Vorratswarnung fehlgeschlagen:", e, flush=True)
                continue
            notified[key] = {"count": 1, "last": now.timestamp()}
            changed = True
    if changed:
        with lock:
            write_json(NOTIFIED_FILE, notified)


# ---------- „Erledigt“ aus der Benachrichtigung (WebSocket zu Home Assistant) ----------

def _recv_exact(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise ConnectionError("Verbindung geschlossen")
        data += chunk
    return data


def ws_connect(host, port, path):
    sock = socket.create_connection((host, port), timeout=30)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall((
        "GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (path, host, key)
    ).encode())
    head = b""
    while b"\r\n\r\n" not in head:
        head += _recv_exact(sock, 1)
        if len(head) > 8192:
            raise ConnectionError("Antwort zu lang")
    if b" 101 " not in head.split(b"\r\n", 1)[0]:
        sock.close()
        raise ConnectionError("Kein WebSocket: %r" % head.split(b"\r\n", 1)[0])
    sock.settimeout(60)
    return sock


def ws_send(sock, payload, opcode=1):
    data = payload.encode() if isinstance(payload, str) else payload
    mask = os.urandom(4)
    size = len(data)
    if size < 126:
        head = bytes([0x80 | opcode, 0x80 | size])
    elif size < 65536:
        head = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack(">H", size)
    else:
        head = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack(">Q", size)
    sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


def ws_recv(sock):
    """Nächste Textnachricht; "" wenn eine Minute nichts kam, None wenn die Gegenseite schließt."""
    message = b""
    while True:
        try:
            first, second = _recv_exact(sock, 2)
        except socket.timeout:
            if message:
                raise
            return ""
        size = second & 0x7F
        if size == 126:
            size = struct.unpack(">H", _recv_exact(sock, 2))[0]
        elif size == 127:
            size = struct.unpack(">Q", _recv_exact(sock, 8))[0]
        if size > 16 * 1024 * 1024:
            raise ConnectionError("Nachricht zu groß")
        mask = _recv_exact(sock, 4) if second & 0x80 else None
        payload = _recv_exact(sock, size)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        opcode = first & 0x0F
        if opcode == 8:
            return None
        if opcode == 9:
            ws_send(sock, payload, opcode=10)
            continue
        if opcode == 10:
            continue
        message += payload
        if first & 0x80:
            return message.decode("utf-8", "replace")


def listen_actions(sock, token):
    """Meldet sich bei Home Assistant an und wartet auf Tipps auf „Erledigt“."""
    if json.loads(ws_recv(sock) or "{}").get("type") != "auth_required":
        raise ConnectionError("Unerwartete Begrüßung")
    ws_send(sock, json.dumps({"type": "auth", "access_token": token}))
    if json.loads(ws_recv(sock) or "{}").get("type") != "auth_ok":
        raise ConnectionError("Anmeldung abgelehnt")
    ws_send(sock, json.dumps({"id": 1, "type": "subscribe_events",
                              "event_type": "mobile_app_notification_action"}))
    counter = 1
    while True:
        raw = ws_recv(sock)
        if raw is None:
            return
        if raw == "":
            counter += 1
            ws_send(sock, json.dumps({"id": counter, "type": "ping"}))
            continue
        try:
            msg = json.loads(raw)
        except ValueError:
            continue
        if msg.get("type") != "event":
            continue
        action = str(((msg.get("event") or {}).get("data") or {}).get("action") or "")
        if action.startswith(ACTION_DONE):
            if mark_done(action[len(ACTION_DONE):]):
                print("Dosis über die Benachrichtigung eingetragen", flush=True)


def action_loop():
    while True:
        try:
            sock = ws_connect("supervisor", 80, "/core/websocket")
            try:
                listen_actions(sock, TOKEN)
            finally:
                sock.close()
        except Exception as e:
            print("Verbindung zu Home Assistant für „Erledigt“ unterbrochen:", e, flush=True)
        time.sleep(30)


def reminder_loop():
    while True:
        try:
            check_reminders()
        except Exception as e:
            print("Fehler in der Erinnerungsschleife:", e, flush=True)
        time.sleep(30)


# ---------- HTTP ----------

class BaseHandler(BaseHTTPRequestHandler):
    server_version = "Stichtag"

    def log_message(self, *args):
        pass

    def route(self):
        return self.path.split("?", 1)[0].rstrip("/") or "/"

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

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > MAX_BODY:
            return None
        try:
            return json.loads(self.rfile.read(n))
        except ValueError:
            return None


class Handler(BaseHandler):
    """Weboberfläche; nur über Home Assistant (Ingress) erreichbar."""

    def allowed(self):
        if DEV or self.client_address[0] == INGRESS_GATEWAY:
            return True
        self.reply(403, {"error": "Nur über Home Assistant erreichbar"})
        return False

    def admin(self):
        """Kopplung und Geräteverwaltung nur für angemeldete HA-Benutzer."""
        if DEV or self.headers.get("X-Remote-User-Id"):
            return True
        self.reply(403, {"error": "Nur für angemeldete Home-Assistant-Benutzer"})
        return False

    def do_GET(self):
        if not self.allowed():
            return
        path = self.route()
        if path in ("/", "/index.html"):
            with open(os.path.join(WWW, "index.html"), "rb") as f:
                self.reply(200, f.read(), "text/html")
        elif path == "/qrcode.js":
            with open(os.path.join(WWW, "qrcode.js"), "rb") as f:
                self.reply(200, f.read(), "text/javascript")
        elif path == "/api/state":
            with lock:
                self.reply(200, load_state())
        elif path == "/api/mobile":
            if not self.admin():
                return
            with lock:
                devices = [public_device(d) for d in load_devices()]
            self.reply(200, {"server_url": mobile_server_url(), "devices": devices})
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
        if self.route() != "/api/state":
            return self.reply(404, {"error": "Nicht gefunden"})
        self.reply(*put_state(self.body()))

    def do_DELETE(self):
        if not self.allowed():
            return
        path = self.route()
        if not path.startswith("/api/devices/"):
            return self.reply(404, {"error": "Nicht gefunden"})
        if self.admin():
            self.reply(200, {"ok": remove_device(path.rsplit("/", 1)[1])})

    def do_POST(self):
        if not self.allowed():
            return
        path = self.route()
        if path == "/api/pairing":
            if not self.admin():
                return
            url = mobile_server_url()
            if not url:
                return self.reply(400, {"error": "In den App-Einstellungen fehlt mobile_server_url."})
            payload = {"type": "stichtag-pairing", "version": 1,
                       "server_url": url, "pairing_secret": create_pairing()}
            return self.reply(200, {"payload": payload, "expires_in": PAIRING_TTL})
        if path != "/api/test-notify":
            return self.reply(404, {"error": "Nicht gefunden"})
        req = self.body() or {}
        try:
            send(str(req.get("service") or ""), "Testnachricht: Erinnerungen funktionieren.", "peptid-test")
            self.reply(200, {"ok": True})
        except Exception as e:
            self.reply(200, {"ok": False, "error": str(e)})


_refusals = {}


def log_refusal(peer, reason):
    """Schreibt abgelehnte Gegenstellen ins Protokoll, je Adresse höchstens einmal pro Minute."""
    now = time.time()
    with pair_lock:
        if now - _refusals.get((peer, reason), 0) < 60:
            return
        if len(_refusals) > 200:
            _refusals.clear()
        _refusals[(peer, reason)] = now
    print("Handy-API: Anfrage von %s abgelehnt (%s)" % (peer, reason), flush=True)


class MobileHandler(BaseHandler):
    """API der Handy-App: nur per HTTPS über einen vertrauenswürdigen Proxy."""

    def peer(self):
        forwarded = self.headers.get("X-Forwarded-For", "").split(",")[0].strip()
        return forwarded or self.client_address[0]

    def allowed(self):
        if DEV_MOBILE:
            return True
        try:
            address = ipaddress.ip_address(self.client_address[0])
        except ValueError:
            address = None
        if address is None or not any(address in net for net in trusted_networks()):
            log_refusal(self.client_address[0], "nicht in trusted_proxies")
            self.reply(403, {"error": "Diese Gegenstelle ist nicht freigegeben"})
            return False
        if self.headers.get("X-Forwarded-Proto", "").lower() != "https":
            log_refusal(self.client_address[0], "X-Forwarded-Proto ist nicht https")
            self.reply(403, {"error": "HTTPS erforderlich"})
            return False
        return True

    def device(self):
        peer = self.peer()
        if too_many_attempts(peer):
            self.reply(429, {"error": "Zu viele Versuche. Bitte eine Minute warten."})
            return None
        auth = self.headers.get("Authorization", "")
        found = find_device(auth[7:].strip()) if auth.startswith("Bearer ") else None
        if not found:
            note_failure(peer)
            self.reply(401, {"error": "Dieses Gerät ist nicht gekoppelt"})
        return found

    def do_GET(self):
        if not self.allowed():
            return
        path = self.route()
        if path == "/api/v1/health":
            self.reply(200, {"app": "stichtag", "version": VERSION, "api": 1})
        elif path == "/api/v1/state":
            if self.device():
                with lock:
                    self.reply(200, load_state())
        else:
            self.reply(404, {"error": "Nicht gefunden"})

    def do_PUT(self):
        if not self.allowed():
            return
        if self.route() != "/api/v1/state":
            return self.reply(404, {"error": "Nicht gefunden"})
        if self.device():
            self.reply(*put_state(self.body()))

    def do_POST(self):
        if not self.allowed():
            return
        if self.route() != "/api/v1/pair":
            return self.reply(404, {"error": "Nicht gefunden"})
        peer = self.peer()
        if too_many_attempts(peer):
            return self.reply(429, {"error": "Zu viele Versuche. Bitte eine Minute warten."})
        req = self.body()
        req = req if isinstance(req, dict) else {}
        if not redeem_pairing(req.get("pairing_secret") or ""):
            note_failure(peer)
            return self.reply(400, {"error": "Der Kopplungscode ist ungültig oder abgelaufen."})
        device, token = add_device(req.get("device_name"))
        self.reply(200, {"device": public_device(device), "token": token})

    def do_DELETE(self):
        if not self.allowed():
            return
        if self.route() != "/api/v1/session":
            return self.reply(404, {"error": "Nicht gefunden"})
        device = self.device()
        if device:
            remove_device(device["id"])
            self.reply(200, {"ok": True})


if __name__ == "__main__":
    os.makedirs(DATA_DIR, exist_ok=True)
    threading.Thread(target=reminder_loop, daemon=True).start()
    if TOKEN:
        threading.Thread(target=action_loop, daemon=True).start()
    mobile = ThreadingHTTPServer(("0.0.0.0", MOBILE_PORT), MobileHandler)
    threading.Thread(target=mobile.serve_forever, daemon=True).start()
    print("Handy-API auf Port %d" % MOBILE_PORT, flush=True)
    print("Stichtag läuft auf Port %d" % PORT, flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
