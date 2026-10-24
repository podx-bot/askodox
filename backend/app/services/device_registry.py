"""Universal Connectivity & Pairing: the user's device registry and the
device compatibility catalog.

What is actually supported is said exactly (master command 13-15):
- Bluetooth Low Energy devices that implement a Bluetooth SIG standard GATT
  profile (weight scale, environmental sensing, health thermometer, heart
  rate, battery) are read by the phone app directly. Status:
  ``standard_profile_untested`` until a real device of that kind is tested.
- Everything else (Matter, Zigbee, Z-Wave, IR, UHF RFID, LoRa, UWB, OBD-II,
  RTSP / ONVIF cameras, MQTT, USB serial, HDMI-CEC, vendor clouds) is listed
  with the reason it is NOT supported yet -- never shown as working.

Privacy: the phone keeps the raw Bluetooth address; the server stores only a
keyed hash of it (so a registry leak does not reveal device addresses),
plus what the user named the device. Every registry call is token-proven.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

SIG_SOURCE = "https://www.bluetooth.com/specifications/assigned-numbers/"

# id -> catalog row. ``status`` values:
#   standard_profile_untested  built against the published standard, no real device tested yet
#   tested                     a real device of this kind was tested (set only with evidence)
#   needs_hub                  works only through a hub / gateway ASKODOX does not integrate yet
#   needs_vendor_sdk           needs a vendor SDK / cloud account and agreement
#   unsupported_on_phone       typical phones lack the radio / hardware
#   not_built                  feasible on Android, not built yet
COMPATIBILITY: List[Dict[str, Any]] = [
    {"id": "ble_weight_scale", "category": "weighing_scale", "protocol": "BLE", "standard": "Weight Scale Service 0x181D",
     "service_uuid": "181d", "commands": ["read_weight"], "required_hub": None, "auth": "BLE pairing (if the scale asks)",
     "sdk": "Bluetooth SIG GATT", "status": "standard_profile_untested",
     "limitations": "Many cheap scales use a private protocol instead of the standard service; those will not show a weight."},
    {"id": "ble_body_composition", "category": "weighing_scale", "protocol": "BLE",
     "standard": "Body Composition Service 0x181B", "service_uuid": "181b", "commands": ["detect_only"],
     "required_hub": None, "auth": "BLE pairing", "sdk": "Bluetooth SIG GATT", "status": "not_built",
     "limitations": "Detected, but body-composition values are not decoded yet."},
    {"id": "ble_environment", "category": "temperature_humidity_sensor", "protocol": "BLE",
     "standard": "Environmental Sensing Service 0x181A", "service_uuid": "181a",
     "commands": ["read_temperature", "read_humidity"], "required_hub": None, "auth": "none / BLE pairing",
     "sdk": "Bluetooth SIG GATT", "status": "standard_profile_untested",
     "limitations": "Soil moisture has no single standard characteristic; moisture probes need their vendor protocol."},
    {"id": "ble_thermometer", "category": "thermometer", "protocol": "BLE", "standard": "Health Thermometer Service 0x1809",
     "service_uuid": "1809", "commands": ["read_temperature"], "required_hub": None, "auth": "BLE pairing",
     "sdk": "Bluetooth SIG GATT", "status": "standard_profile_untested",
     "limitations": "Not a medical device certification; follow the thermometer maker's instructions."},
    {"id": "ble_heart_rate", "category": "heart_rate_monitor", "protocol": "BLE", "standard": "Heart Rate Service 0x180D",
     "service_uuid": "180d", "commands": ["read_heart_rate"], "required_hub": None, "auth": "none / BLE pairing",
     "sdk": "Bluetooth SIG GATT", "status": "standard_profile_untested",
     "limitations": "Fitness reading only, not for medical decisions."},
    {"id": "ble_battery", "category": "any_ble", "protocol": "BLE", "standard": "Battery Service 0x180F",
     "service_uuid": "180f", "commands": ["read_battery"], "required_hub": None, "auth": "none",
     "sdk": "Bluetooth SIG GATT", "status": "standard_profile_untested", "limitations": ""},
    {"id": "matter", "category": "smart_home", "protocol": "Matter / Thread", "standard": "Matter",
     "service_uuid": None, "commands": [], "required_hub": "Thread border router for Thread devices",
     "auth": "Matter commissioning (setup code)", "sdk": "Google Home Mobile SDK (not integrated)",
     "status": "not_built", "limitations": "Use the device maker's app or Google Home until ASKODOX integrates Matter commissioning."},
    {"id": "zigbee", "category": "smart_home", "protocol": "Zigbee", "standard": "Zigbee", "service_uuid": None,
     "commands": [], "required_hub": "Zigbee hub / bridge", "auth": "hub pairing", "sdk": "hub vendor API",
     "status": "needs_hub", "limitations": "Phones have no Zigbee radio."},
    {"id": "zwave", "category": "smart_home", "protocol": "Z-Wave", "standard": "Z-Wave", "service_uuid": None,
     "commands": [], "required_hub": "Z-Wave hub", "auth": "hub pairing", "sdk": "hub vendor API",
     "status": "needs_hub", "limitations": "Phones have no Z-Wave radio."},
    {"id": "wifi_vendor_cloud", "category": "smart_home", "protocol": "Wi-Fi (vendor cloud)",
     "standard": "vendor specific (e.g. smart plugs, ACs, TVs)", "service_uuid": None, "commands": [],
     "required_hub": None, "auth": "vendor account OAuth", "sdk": "vendor cloud API + partner agreement",
     "status": "needs_vendor_sdk",
     "limitations": "Remote control needs each brand's official API; ASKODOX never simulates controls."},
    {"id": "ir_remote", "category": "tv_ac_remote", "protocol": "Infrared", "standard": "consumer IR",
     "service_uuid": None, "commands": [], "required_hub": None, "auth": "none",
     "sdk": "Android ConsumerIrManager (phones with an IR blaster only)", "status": "not_built",
     "limitations": "Most phones have no IR transmitter."},
    {"id": "nfc_tag", "category": "tag", "protocol": "NFC", "standard": "NFC Forum NDEF", "service_uuid": None,
     "commands": [], "required_hub": None, "auth": "none", "sdk": "Android NFC", "status": "not_built",
     "limitations": "Phones read NFC (13.56 MHz) tags only, not UHF RFID tags."},
    {"id": "uhf_rfid", "category": "tag", "protocol": "UHF RFID", "standard": "EPC Gen2", "service_uuid": None,
     "commands": [], "required_hub": "external RFID reader", "auth": "reader specific", "sdk": "reader vendor SDK",
     "status": "unsupported_on_phone", "limitations": "Needs a handheld / Bluetooth RFID reader."},
    {"id": "obd2", "category": "vehicle", "protocol": "CAN / OBD-II", "standard": "SAE J1979 via ELM327-type adapter",
     "service_uuid": None, "commands": [], "required_hub": "OBD-II Bluetooth adapter", "auth": "adapter pairing",
     "sdk": "adapter-specific serial over BLE / Classic", "status": "not_built",
     "limitations": "Adapters differ (BLE vs Classic, clones); needs a tested adapter list."},
    {"id": "ip_camera", "category": "cctv", "protocol": "RTSP / ONVIF", "standard": "ONVIF", "service_uuid": None,
     "commands": [], "required_hub": None, "auth": "camera username / password", "sdk": "ONVIF client",
     "status": "not_built", "limitations": "Camera credentials and local network access are required."},
    {"id": "lora", "category": "farm_sensor", "protocol": "LoRa / LoRaWAN", "standard": "LoRaWAN", "service_uuid": None,
     "commands": [], "required_hub": "LoRaWAN gateway + network server", "auth": "network server keys",
     "sdk": "network server API", "status": "needs_hub", "limitations": "Phones have no LoRa radio."},
    {"id": "uwb", "category": "tracker", "protocol": "UWB", "standard": "FiRa", "service_uuid": None, "commands": [],
     "required_hub": None, "auth": "vendor", "sdk": "Android UWB API (few phones)", "status": "unsupported_on_phone",
     "limitations": "Only a few phones have UWB hardware."},
    {"id": "walkie_offline", "category": "communication", "protocol": "offline radio", "standard": "PMR / ham radio",
     "service_uuid": None, "commands": [], "required_hub": "radio hardware", "auth": "licence where required",
     "sdk": "none", "status": "unsupported_on_phone",
     "limitations": "Phones cannot act as long-range radios; ASKODOX push-to-talk works over the internet."},
]

_BY_ID = {row["id"]: row for row in COMPATIBILITY}
_BY_SERVICE = {row["service_uuid"]: row for row in COMPATIBILITY if row.get("service_uuid")}

VALID_STATUS = {"connected", "disconnected", "paired", "error"}


def compatibility(language: str = "en") -> List[Dict[str, Any]]:
    return [{**row, "source": SIG_SOURCE if row["protocol"] == "BLE" else None} for row in COMPATIBILITY]


def match_services(service_uuids: List[str]) -> List[Dict[str, Any]]:
    """Which catalog rows a BLE device's advertised / discovered services match.
    Accepts 16-bit ('181d') or 128-bit base UUIDs ('0000181d-0000-1000-8000-00805f9b34fb')."""
    found = []
    for raw in service_uuids or []:
        key = str(raw or "").strip().lower()
        if len(key) == 36 and key.startswith("0000") and key.endswith("-0000-1000-8000-00805f9b34fb"):
            key = key[4:8]
        elif key.startswith("0x"):
            key = key[2:]
        row = _BY_SERVICE.get(key)
        if row and row not in found:
            found.append(row)
    return found


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class DeviceRegistry:
    def __init__(self, db_path: str, secret: str) -> None:
        self.db_path = db_path
        self.secret = (secret or "askodox-device-registry").encode("utf-8")
        with self._connect() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS user_devices ("
                " id TEXT PRIMARY KEY, app_user_id TEXT NOT NULL, name TEXT NOT NULL, category TEXT NOT NULL,"
                " protocol TEXT NOT NULL, identifier_hash TEXT NOT NULL, manufacturer TEXT, model TEXT,"
                " compatibility_ids TEXT NOT NULL DEFAULT '[]', capabilities TEXT NOT NULL DEFAULT '[]',"
                " status TEXT NOT NULL DEFAULT 'paired', last_seen TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,"
                " UNIQUE(app_user_id, identifier_hash))")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_user_devices_user ON user_devices(app_user_id)")

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    def identifier_hash(self, app_user_id: str, identifier: str) -> str:
        message = f"{app_user_id}|{str(identifier or '').strip().upper()}".encode("utf-8")
        return hmac.new(self.secret, message, hashlib.sha256).hexdigest()

    @staticmethod
    def _row(row: sqlite3.Row) -> Dict[str, Any]:
        out = dict(row)
        out["compatibility_ids"] = json.loads(out.get("compatibility_ids") or "[]")
        out["capabilities"] = json.loads(out.get("capabilities") or "[]")
        out.pop("app_user_id", None)
        return out

    def list(self, app_user_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM user_devices WHERE app_user_id = ? ORDER BY created_at DESC",
                                (app_user_id,)).fetchall()
        return [self._row(r) for r in rows]

    def add(self, app_user_id: str, *, name: str, protocol: str, identifier: str, service_uuids: List[str],
            manufacturer: str = "", model: str = "") -> Dict[str, Any]:
        matched = match_services(service_uuids)
        category = matched[0]["category"] if matched else "unknown"
        capabilities = sorted({c for row in matched for c in row["commands"]})
        ident = self.identifier_hash(app_user_id, identifier)
        now = _now()
        device_id = "dev_" + uuid.uuid4().hex[:20]
        with self._connect() as conn:
            existing = conn.execute("SELECT id FROM user_devices WHERE app_user_id = ? AND identifier_hash = ?",
                                    (app_user_id, ident)).fetchone()
            if existing:
                device_id = existing["id"]
                conn.execute(
                    "UPDATE user_devices SET name=?, category=?, protocol=?, manufacturer=?, model=?, compatibility_ids=?,"
                    " capabilities=?, status='paired', updated_at=? WHERE id=?",
                    (name, category, protocol, manufacturer, model, json.dumps([r["id"] for r in matched]),
                     json.dumps(capabilities), now, device_id))
            else:
                conn.execute(
                    "INSERT INTO user_devices (id, app_user_id, name, category, protocol, identifier_hash, manufacturer,"
                    " model, compatibility_ids, capabilities, status, created_at, updated_at)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'paired', ?, ?)",
                    (device_id, app_user_id, name, category, protocol, ident, manufacturer, model,
                     json.dumps([r["id"] for r in matched]), json.dumps(capabilities), now, now))
            row = conn.execute("SELECT * FROM user_devices WHERE id = ?", (device_id,)).fetchone()
        return self._row(row)

    def update_status(self, app_user_id: str, device_id: str, status: str) -> Optional[Dict[str, Any]]:
        if status not in VALID_STATUS:
            raise ValueError("invalid status")
        now = _now()
        with self._connect() as conn:
            cur = conn.execute(
                "UPDATE user_devices SET status = ?, updated_at = ?, last_seen = CASE WHEN ? = 'connected' THEN ? ELSE last_seen END"
                " WHERE id = ? AND app_user_id = ?", (status, now, status, now, device_id, app_user_id))
            if cur.rowcount == 0:
                return None
            row = conn.execute("SELECT * FROM user_devices WHERE id = ?", (device_id,)).fetchone()
        return self._row(row)

    def remove(self, app_user_id: str, device_id: str) -> bool:
        with self._connect() as conn:
            cur = conn.execute("DELETE FROM user_devices WHERE id = ? AND app_user_id = ?", (device_id, app_user_id))
        return cur.rowcount > 0

    def remove_all(self, app_user_id: str) -> int:
        with self._connect() as conn:
            cur = conn.execute("DELETE FROM user_devices WHERE app_user_id = ?", (app_user_id,))
        return cur.rowcount
