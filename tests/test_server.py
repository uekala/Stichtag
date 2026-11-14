"""Tests für den Stichtag-Server. Aufruf: python3 -m unittest discover -s tests"""
import json
import os
import socket
import struct
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from datetime import date, datetime
from http.server import ThreadingHTTPServer

DATA = tempfile.mkdtemp(prefix="stichtag-test-")
os.environ["DATA_DIR"] = DATA
os.environ["DEV"] = "1"
os.environ.pop("DEV_MOBILE", None)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "stichtag", "app"))

import server  # noqa: E402

HTTPS = {"X-Forwarded-Proto": "https"}


def call(url, method="GET", body=None, headers=None, chunked=False):
    """Schickt eine Anfrage und gibt (Status, JSON) zurück."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, method=method, headers=dict(headers or {}))
    if data is not None and chunked:
        req.add_header("Transfer-Encoding", "chunked")
        req.data = iter([data[: len(data) // 2], data[len(data) // 2:]])
    elif data is not None:
        req.data = data
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            return res.status, json.loads(res.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


def protocol(**extra):
    base = {"id": "p1", "name": "Test", "dose": 2, "unit": "mg", "type": "daily",
            "start": "2026-11-01", "weeks": 0, "time": "08:00", "active": True}
    base.update(extra)
    return base


def save(**parts):
    state = server.blank()
    state["settings"] = {"notify": "notify.mobile_app_x", "followup": 0}
    state.update(parts)
    server.write_json(server.STATE_FILE, state)
    return state


def at(stamp):
    return datetime.fromisoformat(stamp)


class Base(unittest.TestCase):
    def setUp(self):
        for name in os.listdir(DATA):
            os.remove(os.path.join(DATA, name))
        server.pairings.clear()
        server.attempts.clear()
        server._published.clear()
        server._refusals.clear()
        self.sent = []

    def sender(self, service, message, tag, actions=None):
        self.sent.append((message, tag, actions))


class Rules(Base):
    def test_is_due(self):
        day = date(2026, 11, 13)  # Freitag
        self.assertTrue(server.is_due(protocol(), day))
        self.assertFalse(server.is_due(protocol(active=False), day))
        self.assertFalse(server.is_due(protocol(demo=True), day))
        self.assertFalse(server.is_due(protocol(start="2026-11-14"), day))
        self.assertFalse(server.is_due(protocol(weeks=1), day))
        self.assertTrue(server.is_due(protocol(type="interval", n=3), date(2026, 11, 4)))
        self.assertFalse(server.is_due(protocol(type="interval", n=3), date(2026, 11, 5)))
        self.assertTrue(server.is_due(protocol(type="weekdays", days=[5]), day))
        self.assertFalse(server.is_due(protocol(type="weekdays", days=[0]), day))
        self.assertTrue(server.is_due(protocol(type="weekdays", days=[0]), date(2026, 11, 15)))
        self.assertFalse(server.is_due(protocol(start="kaputt"), day))

    def test_dose_steps(self):
        p = protocol(start="2026-10-02", steps=[{"week": 9, "dose": 6}, {"week": 5, "dose": 4}])
        self.assertEqual(server.dose_on(p, date(2026, 10, 29)), 2)
        self.assertEqual(server.dose_on(p, date(2026, 10, 30)), 4)
        self.assertEqual(server.dose_on(p, date(2026, 11, 27)), 6)

    def test_next_site_is_least_recently_used(self):
        state = save(sites=["A", "B", "C"], logs=[
            {"ts": "2026-11-10T08:00", "site": "A"}, {"ts": "2026-11-12T08:00", "site": "B"}])
        self.assertEqual(server.next_site(state), "C")


class Reminders(Base):
    def test_dose_reminder_once_then_followup(self):
        state = save(protocols=[protocol(time="08:00")])
        state["settings"]["followup"] = 30
        server.write_json(server.STATE_FILE, state)
        for stamp in ("2026-11-13T07:59", "2026-11-13T08:01", "2026-11-13T08:10",
                      "2026-11-13T08:32", "2026-11-13T09:30"):
            server.check_reminders(at(stamp), self.sender)
        self.assertEqual([m for m, _, _ in self.sent], [
            "Test ist fällig: 2 mg. Nächste Stelle: Bauch links",
            "Test ist noch offen: 2 mg. Nächste Stelle: Bauch links"])
        self.assertEqual(self.sent[0][2], [{"action": "STICHTAG_DONE_p1", "title": "Erledigt"}])

    def test_no_reminder_when_logged_or_without_service(self):
        save(protocols=[protocol()], logs=[{"ts": "2026-11-13T07:00", "pid": "p1"}])
        server.check_reminders(at("2026-11-13T08:01"), self.sender)
        state = save(protocols=[protocol()])
        state["settings"]["notify"] = ""
        server.write_json(server.STATE_FILE, state)
        server.check_reminders(at("2026-11-13T08:01"), self.sender)
        self.assertEqual(self.sent, [])

    def test_low_vial_and_shelf_life_warn_once(self):
        save(vials=[{"id": "v1", "name": "A", "mg": 1, "mixed": "2026-10-10", "days": 28}],
             logs=[{"ts": "2026-11-01T08:00", "vialId": "v1", "dose": 0.85, "unit": "mg"}])
        for stamp in ("2026-11-07T09:00", "2026-11-08T09:00", "2026-11-08T09:01", "2026-11-09T09:00"):
            server.check_reminders(at(stamp), self.sender)
        self.assertEqual([m for m, _, _ in self.sent], [
            "Vial A ist fast leer: noch 0,15 mg.", "Vial A ist seit dem 07.11. nicht mehr haltbar."])

    def test_warnings_can_be_switched_off(self):
        state = save(vials=[{"id": "v1", "name": "A", "mg": 1, "mixed": "2026-10-10", "days": 1}],
                     logs=[{"ts": "2026-11-01T08:00", "vialId": "v1", "dose": 1, "unit": "mg"}])
        state["settings"]["lowvial"] = False
        server.write_json(server.STATE_FILE, state)
        server.check_reminders(at("2026-11-13T09:00"), self.sender)
        self.assertEqual(self.sent, [])

    def test_mark_done_logs_todays_dose_once(self):
        save(protocols=[protocol(start="2026-10-02", vialId="v1", steps=[{"week": 5, "dose": 4}])])
        server.supervisor = lambda *a, **k: None
        self.assertTrue(server.mark_done("p1", at("2026-11-13T20:05")))
        self.assertFalse(server.mark_done("p1", at("2026-11-13T20:06")))
        self.assertFalse(server.mark_done("gibtsnicht", at("2026-11-13T20:06")))
        state = server.load_state()
        self.assertEqual(state["rev"], 1)
        log = state["logs"][0]
        self.assertEqual((log["dose"], log["unit"], log["site"], log["vialId"], log["ts"]),
                         (4, "mg", "Bauch links", "v1", "2026-11-13T20:05"))


class Sensors(Base):
    def test_values_and_republish_only_on_change(self):
        save(protocols=[protocol(time="20:00"), protocol(id="p2", name="B", time="08:00")],
             logs=[{"ts": "2026-11-13T08:05", "pid": "p2"}])
        posts = []
        post = lambda entity, body: posts.append((entity, body["state"]))  # noqa: E731
        server.publish_sensors(at("2026-11-13T19:00"), post)
        server.publish_sensors(at("2026-11-13T19:01"), post)
        self.assertEqual(posts, [("sensor.stichtag_offene_dosen", 1),
                                 ("sensor.stichtag_einhaltung_7_tage", 7),
                                 ("sensor.stichtag_naechste_dosis", "Heute 20:00 Test")])
        server.mark_done("p1", at("2026-11-13T20:05"))
        posts.clear()
        server.publish_sensors(at("2026-11-13T20:06"), post)
        self.assertEqual(dict(posts)["sensor.stichtag_offene_dosen"], 0)
        self.assertEqual(dict(posts)["sensor.stichtag_naechste_dosis"], "Morgen 08:00 B")


class Http(Base):
    @classmethod
    def setUpClass(cls):
        cls.web = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        cls.mobile = ThreadingHTTPServer(("127.0.0.1", 0), server.MobileHandler)
        for srv in (cls.web, cls.mobile):
            threading.Thread(target=srv.serve_forever, daemon=True).start()
        cls.A = "http://127.0.0.1:%d" % cls.web.server_address[1]
        cls.M = "http://127.0.0.1:%d" % cls.mobile.server_address[1]

    @classmethod
    def tearDownClass(cls):
        for srv in (cls.web, cls.mobile):
            srv.shutdown()
            srv.server_close()

    def setUp(self):
        super().setUp()
        server.write_json(server.OPTIONS_FILE, {
            "mobile_server_url": "https://stichtag.example.ts.net/", "trusted_proxies": "127.0.0.1/32"})

    def pair(self, chunked=False):
        _, res = call(self.A + "/api/pairing", "POST")
        secret = res["payload"]["pairing_secret"]
        return secret, call(self.M + "/api/v1/pair", "POST",
                            {"pairing_secret": secret, "device_name": "Testhandy"}, HTTPS, chunked)

    def test_web_state_roundtrip_and_conflict(self):
        status, state = call(self.A + "/api/state")
        self.assertEqual((status, state["rev"]), (200, 0))
        self.assertEqual(call(self.A + "/api/state", "PUT", state), (200, {"rev": 1}))
        status, current = call(self.A + "/api/state", "PUT", state)
        self.assertEqual((status, current["rev"]), (409, 1))
        self.assertEqual(call(self.A + "/api/state", "PUT", {"x": 1})[0], 400)

    def test_index_and_qr_library_are_served(self):
        for path in ("/", "/qrcode.js"):
            with urllib.request.urlopen(self.A + path, timeout=10) as res:
                self.assertEqual(res.status, 200)

    def test_pairing_payload(self):
        _, res = call(self.A + "/api/pairing", "POST")
        payload = res["payload"]
        self.assertEqual((payload["type"], payload["version"], payload["server_url"]),
                         ("stichtag-pairing", 1, "https://stichtag.example.ts.net"))
        self.assertGreaterEqual(len(payload["pairing_secret"]), 43)

    def test_pairing_needs_configured_address(self):
        server.write_json(server.OPTIONS_FILE, {"mobile_server_url": "http://unsicher.example"})
        self.assertEqual(call(self.A + "/api/pairing", "POST")[0], 400)

    def test_mobile_api_requires_trusted_https_proxy(self):
        self.assertEqual(call(self.M + "/api/v1/health")[0], 403)
        self.assertEqual(call(self.M + "/api/v1/health", headers=HTTPS)[1]["app"], "stichtag")
        server.write_json(server.OPTIONS_FILE, {"trusted_proxies": "10.0.0.1"})
        self.assertEqual(call(self.M + "/api/v1/health", headers=HTTPS)[0], 403)

    def test_pair_use_and_revoke_device(self):
        secret, (status, res) = self.pair()
        self.assertEqual(status, 200)
        auth = dict(HTTPS, Authorization="Bearer " + res["token"])
        with open(server.DEVICES_FILE, encoding="utf-8") as stored:
            self.assertNotIn(res["token"], stored.read())
        # Der Code gilt nur einmal.
        self.assertEqual(call(self.M + "/api/v1/pair", "POST", {"pairing_secret": secret}, HTTPS)[0], 400)
        status, state = call(self.M + "/api/v1/state", headers=auth)
        self.assertEqual(status, 200)
        self.assertEqual(call(self.M + "/api/v1/state", "PUT", state, auth), (200, {"rev": 1}))
        self.assertEqual(call(self.M + "/api/v1/state", "PUT", state, auth)[0], 409)
        self.assertEqual(call(self.M + "/api/v1/state", headers=HTTPS)[0], 401)
        devices = call(self.A + "/api/mobile")[1]["devices"]
        self.assertEqual([d["name"] for d in devices], ["Testhandy"])
        self.assertEqual(call(self.A + "/api/devices/" + devices[0]["id"], "DELETE")[1], {"ok": True})
        self.assertEqual(call(self.M + "/api/v1/state", headers=auth)[0], 401)

    def test_chunked_requests_like_the_phone_app_sends_them(self):
        _, (status, res) = self.pair(chunked=True)
        self.assertEqual(status, 200)
        auth = dict(HTTPS, Authorization="Bearer " + res["token"])
        _, state = call(self.M + "/api/v1/state", headers=auth)
        self.assertEqual(call(self.M + "/api/v1/state", "PUT", state, auth, chunked=True), (200, {"rev": 1}))

    def test_expired_pairing_code_is_refused(self):
        _, res = call(self.A + "/api/pairing", "POST")
        for key in server.pairings:
            server.pairings[key] = time.time() - 1
        body = {"pairing_secret": res["payload"]["pairing_secret"]}
        self.assertEqual(call(self.M + "/api/v1/pair", "POST", body, HTTPS)[0], 400)

    def test_wrong_tokens_are_rate_limited(self):
        bad = dict(HTTPS, Authorization="Bearer falsch")
        codes = [call(self.M + "/api/v1/state", headers=bad)[0] for _ in range(11)]
        self.assertEqual((codes[0], codes[-1]), (401, 429))

    def test_logout_removes_the_device(self):
        _, (_, res) = self.pair()
        auth = dict(HTTPS, Authorization="Bearer " + res["token"])
        self.assertEqual(call(self.M + "/api/v1/session", "DELETE", headers=auth)[1], {"ok": True})
        self.assertEqual(call(self.M + "/api/v1/state", headers=auth)[0], 401)


class DoneAction(Base):
    """„Erledigt“ in der Benachrichtigung, gegen ein nachgebautes Home Assistant."""

    @staticmethod
    def frame(text):
        data = text.encode()
        head = bytes([0x81, len(data)]) if len(data) < 126 else bytes([0x81, 126]) + struct.pack(">H", len(data))
        return head + data

    @staticmethod
    def read(conn):
        head = server._recv_exact(conn, 2)
        size = head[1] & 0x7F
        if size == 126:
            size = struct.unpack(">H", server._recv_exact(conn, 2))[0]
        mask = server._recv_exact(conn, 4)
        return json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(server._recv_exact(conn, size))))

    def test_tap_on_done_logs_the_dose(self):
        save(protocols=[protocol()])
        server.supervisor = lambda *a, **k: None
        got = []
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)

        def home_assistant():
            conn, _ = listener.accept()
            head = b""
            while b"\r\n\r\n" not in head:
                head += conn.recv(1)
            conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
            conn.sendall(self.frame(json.dumps({"type": "auth_required"})))
            got.append(self.read(conn))
            conn.sendall(self.frame(json.dumps({"type": "auth_ok"})))
            got.append(self.read(conn))
            conn.sendall(bytes([0x89, 0]))  # Ping zwischendurch
            conn.sendall(self.frame(json.dumps({"type": "event", "event": {"data": {
                "action": "STICHTAG_DONE_p1", "fuellung": "x" * 300}}})))
            time.sleep(0.3)
            conn.sendall(bytes([0x88, 0]))
            conn.close()

        threading.Thread(target=home_assistant, daemon=True).start()
        sock = server.ws_connect("127.0.0.1", listener.getsockname()[1], "/core/websocket")
        try:
            server.listen_actions(sock, "token")
        finally:
            sock.close()
            listener.close()
        self.assertEqual([m["type"] for m in got], ["auth", "subscribe_events"])
        self.assertEqual(got[0]["access_token"], "token")
        logs = server.load_state()["logs"]
        self.assertEqual([(log["pid"], log["dose"]) for log in logs], [("p1", 2)])


if __name__ == "__main__":
    unittest.main()
