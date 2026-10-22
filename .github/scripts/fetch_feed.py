#!/usr/bin/env python3
"""ChadAds dealer feed courier (runs on GitHub Actions, see .github/workflows/fetch-feed.yml).

carsforsale.com pushes its inventory file to an FTP/SFTP drop box (ftpGrid). This script:
  1. logs into the drop box and finds the NEWEST .csv/.txt file,
  2. asks the ChadAds importer "is this file new?" (a stamp = file name | modified time | size),
  3. if it is new, downloads it and sends it to the importer (the same door the admin page's "Upload a feed file" uses),
     repeating while the importer says it ran out of time (a big first import takes a few rounds).
Nothing here is secret: the logins come from GitHub "secrets" (Settings > Secrets and variables > Actions), set in the environment.
The script only READS the drop box. It never deletes or changes files there.
"""
import io
import json
import os
import posixpath
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_IMPORT_URL = "https://xhjybpostmfgwidqipgc.supabase.co/functions/v1/import-feed"
MAX_BYTES = 25 * 1024 * 1024


def env(name, default=None, required=False):
    value = (os.environ.get(name) or "").strip()
    if not value:
        value = default
    if required and not value:
        fail(f"The GitHub secret {name} is not set.")
    return value


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


# ---- the drop box -------------------------------------------------------------------------------------------------------
class DropBox:
    """Lists and downloads files over SFTP (recommended), FTPS or plain FTP."""

    def __init__(self, protocol, host, port, user, password, folder):
        self.protocol, self.folder = protocol, folder
        if protocol == "sftp":
            import paramiko  # installed by the workflow

            self.transport = paramiko.Transport((host, int(port or 22)))
            self.transport.connect(username=user, password=password)
            self.sftp = paramiko.SFTPClient.from_transport(self.transport)
        elif protocol in ("ftps", "ftp"):
            from ftplib import FTP, FTP_TLS

            self.ftp = (FTP_TLS if protocol == "ftps" else FTP)()
            self.ftp.connect(host, int(port or 21), timeout=60)
            self.ftp.login(user, password)
            if protocol == "ftps":
                self.ftp.prot_p()
        else:
            fail(f'FEED_PROTOCOL must be "sftp", "ftps" or "ftp" (it is "{protocol}").')

    def files(self):
        """[(name, size_in_bytes, modified_unix_seconds)] for the plain files in the folder."""
        found = []
        if self.protocol == "sftp":
            for a in self.sftp.listdir_attr(self.folder):
                if not stat.S_ISDIR(a.st_mode):
                    found.append((a.filename, int(a.st_size), int(a.st_mtime)))
        else:
            self.ftp.cwd(self.folder)
            for name, facts in self.ftp.mlsd(facts=["type", "size", "modify"]):
                if facts.get("type") == "file":
                    modify = facts.get("modify", "")[:14]
                    when = int(time.mktime(time.strptime(modify, "%Y%m%d%H%M%S"))) if len(modify) == 14 else 0
                    found.append((name, int(facts.get("size", 0)), when))
        return found

    def read(self, name):
        if self.protocol == "sftp":
            with self.sftp.open(posixpath.join(self.folder, name), "rb") as handle:
                return handle.read()
        buffer = io.BytesIO()
        self.ftp.retrbinary("RETR " + name, buffer.write)
        return buffer.getvalue()

    def close(self):
        try:
            if self.protocol == "sftp":
                self.sftp.close()
                self.transport.close()
            else:
                self.ftp.quit()
        except Exception:
            pass


def newest(files):
    """The newest .csv/.txt file, or None."""
    candidates = [f for f in files if f[0].lower().endswith((".csv", ".txt"))]
    return max(candidates, key=lambda f: f[2]) if candidates else None


# ---- the importer -------------------------------------------------------------------------------------------------------
def call_importer(url, secret, query, body=None):
    request = urllib.request.Request(
        url + "?" + urllib.parse.urlencode(query),
        data=body,
        method="POST",
        headers={"x-import-secret": secret, "content-type": "text/csv"},
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:300]
        fail(f"The importer answered HTTP {e.code}: {detail}")
    except Exception as e:  # network trouble, bad JSON ...
        fail(f"Could not reach the importer: {e}")


def main():
    protocol = env("FEED_PROTOCOL", "sftp").lower()
    host = env("FEED_HOST", required=True)
    port = env("FEED_PORT")
    user = env("FEED_USER", required=True)
    password = env("FEED_PASS", required=True)
    folder = "/" + (env("FEED_FOLDER", "/") or "/").strip("/")
    feed = env("FEED_NAME", "carsforsale.com")
    url = env("IMPORT_URL", DEFAULT_IMPORT_URL)
    secret = env("IMPORT_SECRET", required=True)

    box = DropBox(protocol, host, port, user, password, folder)
    try:
        latest = newest(box.files())
        if not latest:
            print(f"No .csv or .txt file is in {folder} yet. Nothing to do.")
            return
        name, size, modified = latest
        stamp = f"{name}|{modified}|{size}"
        age_days = (time.time() - modified) / 86400
        print(f"Newest file: {name} ({size:,} bytes, {age_days:.1f} days old)")
        if age_days > 3:
            print(f"::warning::The newest file is {age_days:.0f} days old. Has carsforsale.com stopped sending?")
        if size > MAX_BYTES:
            fail(f"{name} is over 25 MB.")

        checked = call_importer(url, secret, {"check": "1", "source": feed, "stamp": stamp})
        if checked.get("error"):
            fail(checked["error"])
        if not checked.get("changed"):
            print("This is the same file as last time. Nothing to do.")
            return

        data = box.read(name)
    finally:
        box.close()

    print(f"Downloaded {len(data):,} bytes. Sending it to the importer ...")
    for round_number in range(1, 11):
        answer = call_importer(url, secret, {"upload": "1", "source": feed, "stamp": stamp, "filename": name}, data)
        if answer.get("error"):
            fail(answer["error"])
        result = (answer.get("results") or [{}])[0]
        for note in result.get("notes", []):
            print(f"::warning::{note}")
        for unknown in result.get("unknown", []):
            print(f"::warning::DealerID {unknown.get('code')} has {unknown.get('cars')} cars in the file but is not set up in ChadAds, so they were ignored.")
        deferred = 0
        for d in result.get("dealers", []):
            if d.get("error"):
                fail(f"{d.get('dealer')}: {d['error']}")
            deferred += d.get("deferred", 0)
            print(
                f"Round {round_number} - {d.get('dealer')}: {d.get('rows')} cars in the file; "
                f"added {d.get('created')}, updated {d.get('updated')}, unchanged {d.get('unchanged')}, "
                f"hid {d.get('sold')}, skipped {d.get('skipped')}, still waiting {d.get('deferred')}"
            )
        if not deferred:
            print("Done. The whole file has been imported.")
            return
        print(f"{deferred} cars are still waiting (the importer ran out of time). Continuing ...")
    print("::warning::Some cars are still waiting after 10 rounds. The next run will continue where this one stopped.")


if __name__ == "__main__":
    main()
