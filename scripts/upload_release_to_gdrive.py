"""Download a GitHub release's assets and upload them to Google Drive PNET folder.

Usage locally:
    GITHUB_TOKEN=... python scripts/upload_release_to_gdrive.py --tag v0.1.80

In CI the GITHUB_TOKEN env var is set automatically.
Service account JSON path: env GDRIVE_SA_JSON (literal JSON string) OR
GDRIVE_SA_FILE (filesystem path), fallback local _secrets.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sys
import tempfile
import urllib.request
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError

ROOT_FOLDER_ID = os.environ.get("GDRIVE_FOLDER_ID", "1Q2o9ZoKASQ87O7R3gX5APPEyBvf7Svtp")
SCOPES = ["https://www.googleapis.com/auth/drive"]
REPO = "AMX72/pixellnet-client"
KEEP_LAST = int(os.environ.get("GDRIVE_KEEP_LAST", "3"))

VERSION_RE = re.compile(r"(\d+)\.(\d+)\.(\d+)")


def load_sa_credentials():
    sa_json_str = os.environ.get("GDRIVE_SA_JSON")
    if sa_json_str and sa_json_str.strip().startswith("{"):
        info = json.loads(sa_json_str)
        return service_account.Credentials.from_service_account_info(info, scopes=SCOPES)
    sa_file = os.environ.get("GDRIVE_SA_FILE") or r"C:\File Visual Studio Code\_secrets\rosbotanic_google_service_account.json"
    if not Path(sa_file).exists():
        sys.exit(f"service account not found: GDRIVE_SA_JSON env unset and file {sa_file} missing")
    return service_account.Credentials.from_service_account_file(sa_file, scopes=SCOPES)


def get_drive():
    return build("drive", "v3", credentials=load_sa_credentials(), cache_discovery=False)


def ensure_folder(drive, name: str, parent: str) -> str:
    q = (
        f"name='{name}' and '{parent}' in parents "
        f"and mimeType='application/vnd.google-apps.folder' and trashed=false"
    )
    res = drive.files().list(q=q, fields="files(id)", supportsAllDrives=True,
                             includeItemsFromAllDrives=True).execute()
    if res.get("files"):
        return res["files"][0]["id"]
    folder = drive.files().create(
        body={"name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [parent]},
        fields="id", supportsAllDrives=True,
    ).execute()
    print(f"  created subfolder '{name}' ({folder['id']})")
    return folder["id"]


def find_by_name(drive, name: str, parent: str):
    q = f"name='{name}' and '{parent}' in parents and trashed=false"
    res = drive.files().list(q=q, fields="files(id,size)", supportsAllDrives=True,
                             includeItemsFromAllDrives=True).execute()
    return res.get("files", [])


def parse_version(name: str):
    """Extract (major, minor, patch) from a filename; None if no match."""
    m = VERSION_RE.search(name)
    if not m:
        return None
    return tuple(int(x) for x in m.groups())


def rotate_folder(drive, folder_id: str, keep_last: int = KEEP_LAST):
    """Keep only the last `keep_last` versioned files per base-name family.

    Example: Android/ has pixellnet-0.1.78-arm64.apk, …-x86_64.apk, …
    Groups by (base-name-without-version, extension), sorts by version desc,
    trashes everything beyond keep_last per group.
    """
    res = drive.files().list(
        q=f"'{folder_id}' in parents and trashed=false",
        fields="files(id,name,createdTime)",
        pageSize=200, supportsAllDrives=True, includeItemsFromAllDrives=True,
    ).execute()
    files = res.get("files", [])

    groups: dict[str, list] = {}
    for f in files:
        ver = parse_version(f["name"])
        if ver is None:
            continue  # leave non-versioned files alone
        # group by filename with version stripped out
        key = VERSION_RE.sub("VER", f["name"])
        groups.setdefault(key, []).append((ver, f))

    for key, entries in groups.items():
        entries.sort(key=lambda x: x[0], reverse=True)  # newest first
        to_delete = entries[keep_last:]
        for _, f in to_delete:
            try:
                drive.files().delete(fileId=f["id"], supportsAllDrives=True).execute()
                print(f"  rotated out: {f['name']}")
            except HttpError as e:
                print(f"  WARN: could not delete {f['name']}: {e}")


def upload_to_drive(drive, local_path: Path, drive_name: str, parent: str, mime: str):
    existing = find_by_name(drive, drive_name, parent)
    media = MediaFileUpload(str(local_path), mimetype=mime, resumable=True, chunksize=8 * 1024 * 1024)
    if existing:
        request = drive.files().update(fileId=existing[0]["id"], media_body=media,
                                       supportsAllDrives=True, fields="id,name,size")
        action = "replaced"
    else:
        request = drive.files().create(
            body={"name": drive_name, "parents": [parent]},
            media_body=media, supportsAllDrives=True,
            fields="id,name,size",
        )
        action = "uploaded"
    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            print(f"  {drive_name}: {int(status.progress()*100)}%", end="\r", flush=True)
    print(f"  {drive_name}: 100% — {action}")


def gh_api(url: str) -> dict:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GITHUB_TOKEN_PIXELLNET")
    if not token:
        env_path = Path(r"C:\File Visual Studio Code\_secrets\.env")
        if env_path.exists():
            for line in env_path.read_text(encoding="utf-8").splitlines():
                if line.startswith("GITHUB_TOKEN_PIXELLNET="):
                    token = line.split("=", 1)[1].strip()
                    break
    if not token:
        sys.exit("GITHUB_TOKEN env var required")
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "pixellnet-release-uploader",
    })
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def download_asset(url: str, dst: Path, token: str):
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/octet-stream",
        "User-Agent": "pixellnet-release-uploader",
    })
    with urllib.request.urlopen(req) as r, dst.open("wb") as f:
        while True:
            chunk = r.read(1024 * 1024)
            if not chunk:
                break
            f.write(chunk)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True, help="e.g. v0.1.80")
    args = ap.parse_args()
    version = args.tag.lstrip("v")

    print(f"==> fetching release {args.tag} from GitHub…")
    release = gh_api(f"https://api.github.com/repos/{REPO}/releases/tags/{args.tag}")
    assets = release.get("assets", [])
    if not assets:
        sys.exit(f"no assets on release {args.tag}")
    print(f"  {len(assets)} assets found")

    token = (os.environ.get("GITHUB_TOKEN") or os.environ.get("GITHUB_TOKEN_PIXELLNET") or "")
    if not token:
        env_path = Path(r"C:\File Visual Studio Code\_secrets\.env")
        if env_path.exists():
            for line in env_path.read_text(encoding="utf-8").splitlines():
                if line.startswith("GITHUB_TOKEN_PIXELLNET="):
                    token = line.split("=", 1)[1].strip()

    drive = get_drive()
    android_folder = ensure_folder(drive, "Android", ROOT_FOLDER_ID)
    windows_folder = ensure_folder(drive, "Windows", ROOT_FOLDER_ID)

    arm64_apk = None
    exe_installer = None
    universal_apk = None

    with tempfile.TemporaryDirectory() as tmpd:
        tmp = Path(tmpd)
        for a in assets:
            name = a["name"]
            url = a["url"]
            local = tmp / name
            print(f"  downloading {name} ({a['size']//1024} KB)…")
            download_asset(url, local, token)

            if re.search(r"arm64", name, re.I) and name.endswith(".apk"):
                arm64_apk = local
            elif name.endswith(".exe") and "setup" in name.lower():
                exe_installer = local
            elif name.endswith(".apk") and arm64_apk is None:
                universal_apk = local

            # Also upload versioned subfolder copies for ALL android/windows binaries
            if name.endswith(".apk"):
                upload_to_drive(drive, local, name, android_folder,
                                "application/vnd.android.package-archive")
            elif name.endswith(".exe"):
                upload_to_drive(drive, local, name, windows_folder,
                                "application/x-msdownload")
            elif name.endswith(".zip"):
                upload_to_drive(drive, local, name, windows_folder, "application/zip")

        # Latest aliases — use arm64 APK (modern phones) and setup .exe
        primary_apk = arm64_apk or universal_apk
        if primary_apk:
            upload_to_drive(drive, primary_apk, "pixellnet-latest.apk", ROOT_FOLDER_ID,
                            "application/vnd.android.package-archive")
        if exe_installer:
            upload_to_drive(drive, exe_installer, "pixellnet-setup-latest.exe", ROOT_FOLDER_ID,
                            "application/x-msdownload")

    print(f"==> rotating old versions (keeping last {KEEP_LAST})")
    rotate_folder(drive, android_folder, KEEP_LAST)
    rotate_folder(drive, windows_folder, KEEP_LAST)

    print(f"==> done, v{version} published to Google Drive")


if __name__ == "__main__":
    try:
        main()
    except HttpError as e:
        sys.exit(f"Google API error: {e}")
