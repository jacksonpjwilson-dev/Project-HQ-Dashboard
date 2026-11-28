#!/usr/bin/env python3
"""Build, install, and launch a signed Debug app on a connected physical iPhone."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
RESULTS = Path(os.environ.get("HQ_DEPLOY_RESULTS", ROOT / "ios/HeadQuarter/DerivedData/physical-deployment"))
DERIVED = Path(os.environ.get("HQ_DEVICE_DERIVED_DATA", ROOT / "ios/HeadQuarter/DerivedData/PhysicalDevice"))
TEAM = os.environ.get("HQ_DEVELOPMENT_TEAM", "7HL7Y5SP24")
RESULTS.mkdir(parents=True, exist_ok=True)


def device_command(arguments, result_name):
    result = RESULTS / (result_name + ".json")
    subprocess.run(
        ["xcrun", "devicectl", *arguments, "--timeout", "120", "--json-output", str(result)],
        check=True,
    )
    return json.loads(result.read_text())["result"]


def deploy():
    inventory = device_command(["list", "devices"], "devices")
    requested = os.environ.get("HQ_DEVICE_UDID")
    phones = []
    for device in inventory["devices"]:
        properties = device.get("properties", {})
        hardware = properties.get("hardware", device.get("hardwareProperties", {}))
        connection = properties.get("connection", {})
        if hardware.get("deviceType") != "iPhone" or hardware.get("reality") == "simulated":
            continue
        udid = hardware.get("udid", device["identifier"])
        if requested and requested not in (udid, device["identifier"]):
            continue
        if connection.get("state") == "unavailable":
            continue
        phones.append((device["identifier"], udid))
    if len(phones) != 1:
        sys.exit("Connect and unlock one physical iPhone, or set HQ_DEVICE_UDID to select it.")
    identifier, udid = phones[0]
    print(f"Deploying Debug to iPhone {udid} with team {TEAM}", flush=True)
    device_command(["manage", "pair", "--device", identifier], "pair")
    command = [
        "xcodebuild", "-project", str(ROOT / "ios/HeadQuarter/HeadQuarter.xcodeproj"),
        "-scheme", "HeadQuarter", "-configuration", "Debug",
        "-destination", "generic/platform=iOS", "-derivedDataPath", str(DERIVED),
        "-allowProvisioningUpdates", f"DEVELOPMENT_TEAM={TEAM}", "CODE_SIGN_STYLE=Automatic",
        "build",
    ]
    print(f"Build log: {RESULTS / 'build.log'}", flush=True)
    with (RESULTS / "build.log").open("w") as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    app = DERIVED / "Build/Products/Debug-iphoneos/HeadQuarter.app"
    with (app / "Info.plist").open("rb") as info:
        bundle = plistlib.load(info)["CFBundleIdentifier"]
    device_command(["device", "install", "app", "--device", identifier, str(app)], "install")
    launch = device_command(["device", "process", "launch", "--device", identifier, bundle], "launch")
    pid = launch["process"]["processIdentifier"]
    time.sleep(15)
    processes = device_command(["device", "info", "processes", "--device", identifier], "processes")
    if not any(process.get("processIdentifier") == pid for process in processes["runningProcesses"]):
        sys.exit(f"Head Quarter launched as PID {pid}, but was absent after 15 seconds. Inspect device crash logs.")
    print(f"Head Quarter installed and launched. PID {pid} was still running after 15 seconds.")
    print(f"Deployment evidence: {RESULTS}")


if __name__ == "__main__":
    try:
        deploy()
    except (subprocess.CalledProcessError, KeyError) as error:
        sys.exit(f"Deployment stopped: {error}. Review logs in {RESULTS}.")
