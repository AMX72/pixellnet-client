"""Upload release artifacts to Google Drive PNET folder.

Usage:
    python scripts/upload_to_gdrive.py [--version 0.1.80] [--android <apk>] [--windows <exe>]

If --version is omitted, reads from pubspec.yaml.
If --android/--windows paths are omitted, looks under build/ by naming convention.

Auth: service account JSON path from env GDRIVE_SA_JSON,
      fallback to C:\\File Visual Studio Code\\_secrets\\rosbotanic_google_service_account.json

Layout on Drive:
    PNET/
      Android/pixellnet-<version>.apk
      Windows/pixellnet-setup-<version>.exe
      pixellnet-latest.apk            (aliases, overwritten each release)
      pixellnet-setup-latest.exe
"""
from __future__ import annotations
import argparse
import os
import re
import sys
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError

ROOT_FOLDER_ID = "1Q2o9ZoKASQ87O7R3gX5APPEyBvf7Svtp"  # PNET
SCOPES = ["https://www.googleapis.com/auth/drive"]
DEFAULT_SA = r"C:\File Visual Studio Code\_secrets\rosbotanic_google_service_account.json"


def get_drive():
    sa_path = os.environ.get("GDRIVE_SA_JSON", DEFAULT_SA)
    if not Path(sa_path).exists():
        sys.exit(f"service account json not found: {sa_path}")
    creds = service_account.Credentials.from_service_account_file(sa_path, scopes=SCOPES)
    return build("drive", "v3", credentials=creds, cache_discovery=False)


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


def upload_file(drive, local_path: Path, drive_name: str, parent: str, mime: str) -> dict:
    existing = find_by_name(drive, drive_name, parent)
    media = MediaFileUpload(str(local_path), mimetype=mime, resumable=True, chunksize=8 * 1024 * 1024)
    if existing:
        file_id = existing[0]["id"]
        request = drive.files().update(fileId=file_id, media_body=media, supportsAllDrives=True,
                                       fields="id,name,size,webViewLink")
        action = "replaced"
    else:
        request = drive.files().create(
            body={"name": drive_name, "parents": [parent]},
            media_body=media, supportsAllDrives=True,
            fields="id,name,size,webViewLink",
        )
        action = "uploaded"
    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            pct = int(status.progress() * 100)
            print(f"  {drive_name}: {pct}%", end="\r", flush=True)
    print(f"  {drive_name}: 100% — {action}")
    return response


def read_version_from_pubspec() -> str:
    pubspec = Path(__file__).parent.parent / "pubspec.yaml"
    for line in pubspec.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^version:\s*(\d+\.\d+\.\d+)", line)
        if m:
            return m.group(1)
    sys.exit("could not parse version from pubspec.yaml")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version")
    ap.add_argument("--android", help="path to APK")
    ap.add_argument("--windows", help="path to .exe installer")
    args = ap.parse_args()

    version = args.version or read_version_from_pubspec()
    print(f"==> uploading v{version} to Google Drive PNET folder")

    drive = get_drive()
    android_folder = ensure_folder(drive, "Android", ROOT_FOLDER_ID)
    windows_folder = ensure_folder(drive, "Windows", ROOT_FOLDER_ID)

    repo_root = Path(__file__).parent.parent

    if args.android:
        apk_path = Path(args.android)
    else:
        candidates = list(repo_root.glob(f"build/app/outputs/flutter-apk/*{version}*arm64*release.apk"))
        candidates += list(repo_root.glob(f"build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"))
        candidates += list(repo_root.glob(f"**/pixellnet*{version}*arm64*.apk"))
        apk_path = candidates[0] if candidates else None

    if args.windows:
        exe_path = Path(args.windows)
    else:
        candidates = list(repo_root.glob(f"**/pixellnet-setup-{version}.exe"))
        exe_path = candidates[0] if candidates else None

    if apk_path and apk_path.exists():
        print(f"APK source: {apk_path} ({apk_path.stat().st_size // 1024} KB)")
        upload_file(drive, apk_path, f"pixellnet-{version}.apk", android_folder,
                    "application/vnd.android.package-archive")
        upload_file(drive, apk_path, "pixellnet-latest.apk", ROOT_FOLDER_ID,
                    "application/vnd.android.package-archive")
    else:
        print("WARN: no APK found, skipping Android upload")

    if exe_path and exe_path.exists():
        print(f"EXE source: {exe_path} ({exe_path.stat().st_size // 1024} KB)")
        upload_file(drive, exe_path, f"pixellnet-setup-{version}.exe", windows_folder,
                    "application/x-msdownload")
        upload_file(drive, exe_path, "pixellnet-setup-latest.exe", ROOT_FOLDER_ID,
                    "application/x-msdownload")
    else:
        print("WARN: no Windows installer found, skipping Windows upload")

    print("==> done")


if __name__ == "__main__":
    try:
        main()
    except HttpError as e:
        sys.exit(f"Google API error: {e}")
