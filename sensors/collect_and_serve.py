#!/usr/bin/env python3
"""Сбор температур lm-sensors с PVE-хостов и HTTP-отдача JSON для Homepage customapi."""

import json
import os
import subprocess
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOSTS = [
    {"id": "S1", "host": "192.168.10.10", "port": 22},
    {"id": "S2", "host": "192.168.10.11", "port": 22},
    {"id": "LLM-PC", "host": "192.168.10.70", "port": 22},
    {"id": "S3", "host": "192.168.10.60", "port": 22, "optional": True},
]

SSH_KEY = os.environ.get("SENSORS_SSH_KEY", "/opt/homepage/sensors/ssh/id_ed25519")
SSH_USER = os.environ.get("SENSORS_SSH_USER", "root")
LISTEN_HOST = os.environ.get("SENSORS_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("SENSORS_LISTEN_PORT", "3080"))
INTERVAL_SEC = int(os.environ.get("SENSORS_INTERVAL_SEC", "300"))
OUTPUT_PATH = os.environ.get("SENSORS_OUTPUT_PATH", "/opt/homepage/sensors/data/sensors.json")

_cache = {"updated": None, "nodes": {}}
_cache_lock = threading.Lock()


def run_ssh_sensors(host_cfg):
    cmd = [
        "ssh",
        "-i",
        SSH_KEY,
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=8",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-p",
        str(host_cfg["port"]),
        f"{SSH_USER}@{host_cfg['host']}",
        "sensors",
        "-j",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "ssh failed")
    return json.loads(result.stdout)


def temp_values(chip_data):
    values = []
    if not isinstance(chip_data, dict):
        return values
    for label, metrics in chip_data.items():
        if label == "Adapter" or not isinstance(metrics, dict):
            continue
        for metric_key, metric_value in metrics.items():
            if "temp" in metric_key and metric_key.endswith("_input"):
                if isinstance(metric_value, (int, float)):
                    values.append((label, float(metric_value)))
    return values


def parse_s1(raw):
    cpu = None
    gpu = None
    for chip, data in raw.items():
        if chip.startswith("k10temp"):
            for label, value in temp_values(data):
                if label in ("Tctl", "temp1"):
                    cpu = round(value, 1)
        if chip.startswith("nouveau"):
            for label, value in temp_values(data):
                if label.startswith("temp"):
                    gpu = round(value, 1)
    return {"cpu": cpu, "gpu": gpu}


def parse_s2(raw):
    socket_temps = {}
    chipset = None
    for chip, data in raw.items():
        if chip.startswith("coretemp"):
            core_temps = [
                value for label, value in temp_values(data) if label.startswith("Core")
            ]
            if core_temps:
                socket_temps[chip] = round(max(core_temps), 1)
        if chip.startswith("intel5500"):
            for label, value in temp_values(data):
                if label.startswith("temp"):
                    chipset = round(value, 1)

    result = {}
    for index, chip in enumerate(sorted(socket_temps)):
        result[f"cpu{index}"] = socket_temps[chip]
    if chipset is not None:
        result["chipset"] = chipset
    return result


def parse_llm_pc(raw):
    cpu = None
    for chip, data in raw.items():
        if chip.startswith("k10temp"):
            for label, value in temp_values(data):
                if label in ("Tctl", "temp1"):
                    cpu = round(value, 1)
    return {"cpu": cpu}


def parse_generic(raw):
    temps = []
    for chip, data in raw.items():
        for label, value in temp_values(data):
            if label.startswith("Core") or label in ("Tctl", "temp1", "Package id 0"):
                temps.append(value)
    cpu = round(max(temps), 1) if temps else None
    return {"cpu": cpu}


PARSERS = {
    "S1": parse_s1,
    "S2": parse_s2,
    "LLM-PC": parse_llm_pc,
    "S3": parse_generic,
}


def collect_node(host_cfg):
    node_id = host_cfg["id"]
    try:
        raw = run_ssh_sensors(host_cfg)
        parser = PARSERS.get(node_id, parse_generic)
        metrics = parser(raw)
        metrics["status"] = "ok"
        return metrics
    except Exception as exc:
        if host_cfg.get("optional"):
            return {"cpu": None, "status": "offline", "error": str(exc)}
        return {"cpu": None, "status": "error", "error": str(exc)}


def collect_all():
    nodes = {}
    for host_cfg in HOSTS:
        nodes[host_cfg["id"]] = collect_node(host_cfg)
    payload = {
        "updated": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "nodes": nodes,
    }
    with _cache_lock:
        _cache.clear()
        _cache.update(payload)
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)


def collector_loop():
    while True:
        try:
            collect_all()
        except Exception as exc:
            print(f"collect error: {exc}", flush=True)
        time.sleep(INTERVAL_SEC)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/", "/sensors.json"):
            self.send_error(404)
            return
        with _cache_lock:
            body = json.dumps(_cache, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return


def main():
    collect_all()
    threading.Thread(target=collector_loop, daemon=True).start()
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"sensors API on http://{LISTEN_HOST}:{LISTEN_PORT}/sensors.json", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
