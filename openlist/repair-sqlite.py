#!/usr/bin/env python3
import argparse
from contextlib import closing
import datetime
import json
import pathlib
import sqlite3
import subprocess
import tempfile


def require_stopped(container):
    result = subprocess.run(
        ["docker", "inspect", container, "--format", "{{json .State}}"],
        check=True, capture_output=True, text=True, timeout=15,
    )
    state = json.loads(result.stdout)
    if state.get("Status") != "exited" or state.get("Running") or state.get("Restarting"):
        raise RuntimeError("Stop OpenList in Portainer before running this tool.")


def check_database(connection):
    if connection.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
        raise RuntimeError("SQLite integrity check failed.")


def repair(database, container):
    database = pathlib.Path(database)
    if database.is_symlink() or not database.is_file():
        raise RuntimeError("Provide an existing SQLite database file, not a symlink.")
    database = database.resolve()
    require_stopped(container)
    with closing(sqlite3.connect(database.as_uri() + "?mode=rw", uri=True, timeout=5)) as source:
        check_database(source)
        previous_mode = source.execute("PRAGMA journal_mode").fetchone()[0]
        if previous_mode == "wal":
            return {"changed": False, "journalMode": "wal"}
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup_dir = pathlib.Path(tempfile.mkdtemp(prefix="sqlite-before-wal-" + stamp + "-", dir=database.parent))
        backup_path = backup_dir / "data.db"
        with closing(sqlite3.connect(backup_path)) as backup:
            source.backup(backup)
            check_database(backup)
        backup_path.chmod(0o600)
        require_stopped(container)
        mode = source.execute("PRAGMA journal_mode=WAL").fetchone()[0]
        if mode != "wal":
            raise RuntimeError("SQLite did not enable WAL; verified backup: " + str(backup_path))
        check_database(source)
    return {"changed": True, "journalMode": mode, "backup": str(backup_path)}


def main():
    parser = argparse.ArgumentParser(description="Back up a stopped OpenList SQLite database and enable WAL. Never stops or starts containers.")
    parser.add_argument("database", type=pathlib.Path)
    parser.add_argument("--container", default="openlist")
    arguments = parser.parse_args()
    try:
        print(json.dumps(repair(arguments.database, arguments.container)))
    except (OSError, RuntimeError, ValueError, sqlite3.Error, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
