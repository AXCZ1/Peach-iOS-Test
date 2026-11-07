"""Fixed-count Peach timeline cache. Run inside the existing official container.
Only derived files are written; the ledger and media are opened read-only.
"""
import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile
import time

GENERATOR = "peach-ios-fixed30-v1"

def timestamps(duration):
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("video has no finite positive duration")
    return [duration * (0.01 + i / 30) for i in range(30)]

def fingerprint(source):
    stat = source.stat()
    return {"size": stat.st_size, "mtime_ns": stat.st_mtime_ns}

def make_one(ffmpeg, source, duration, root, asset_id):
    from peach.frame_capture import capture_with_retry, tile_frames
    from peach.timeline_sheets import sheet_dir, read_meta
    samples = timestamps(duration)
    before = fingerprint(source)
    destination = sheet_dir(root, asset_id)
    old = read_meta(root, asset_id)
    if old and old.get("generator") != GENERATOR:
        return "existing_external"
    if old and old.get("fingerprint") == before and old.get("frames") == 30 and (destination / "000.jpg").is_file():
        return "current"
    if shutil.disk_usage(root).free < 40 * 1024**3:
        raise RuntimeError("preview cache volume has less than 40 GiB free")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="fixed30-", dir=destination.parent) as temporary:
        temp = Path(temporary)
        for index, timestamp in enumerate(samples):
            if not capture_with_retry(ffmpeg, str(source), timestamp, temp / f"s{index:03}.jpg", width=320, timeout=30):
                raise RuntimeError(f"frame {index+1}/30 failed at {timestamp:.2f}s")
        if not tile_frames(ffmpeg, str(temp / "s%03d.jpg"), 10, 3, temp / "000.jpg"):
            raise RuntimeError("contact sheet creation failed")
        if fingerprint(source) != before:
            raise RuntimeError("source changed during capture; cache not published")
        meta = {"interval": duration / 30, "frames": 30, "sheets": 1,
                "columns": 10, "rows": 10, "frame_width": 320,
                "made_at": time.time(), "timestamps": samples,
                "generator": GENERATOR, "fingerprint": before}
        (temp / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
        destination.mkdir(parents=True, exist_ok=True)
        os.replace(temp / "000.jpg", destination / "000.jpg")
        os.replace(temp / "meta.json", destination / "meta.json")
    return "made"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--id", type=int)
    parser.add_argument("--output-root", type=Path)
    args = parser.parse_args()
    from peach.config import PeachSettings, FFMPEG_DIR
    from peach.ffmpeg import FFmpegResolver
    from peach.media import resolve_case_insensitive
    settings = PeachSettings()
    root = args.output_root or settings.timeline_root
    with sqlite3.connect(f"file:{settings.db_path}?mode=ro", uri=True) as connection:
        rows = connection.execute("SELECT id,path,duration FROM asset WHERE medium='video' AND location='local' AND disposal IS NULL ORDER BY (last_played IS NULL),last_played DESC,id").fetchall()
    if args.id is not None:
        rows = [row for row in rows if row[0] == args.id]
    allowed = [path.resolve() for path in settings.allowed_media_roots]
    tasks = []
    for asset_id, path, duration in rows:
        source = Path(resolve_case_insensitive(path)).resolve()
        if not source.is_file() or not any(source.is_relative_to(base) for base in allowed):
            raise RuntimeError(f"asset {asset_id} is outside available configured media roots")
        timestamps(float(duration or 0))
        tasks.append((asset_id, source, float(duration)))
    if not args.run:
        print(json.dumps({"mode":"dry-run","count":len(tasks),"frames_each":30,"output":str(root),"sources":[{"id":i,**fingerprint(s)} for i,s,d in tasks]}))
        return
    root.mkdir(parents=True, exist_ok=True)
    with (root / ".fixed30.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("generation already running")
            return
        os.nice(10)
        choice = FFmpegResolver(FFMPEG_DIR).ffmpeg()
        if choice is None:
            raise RuntimeError("ffmpeg unavailable")
        state = {"total":len(tasks),"done":0,"made":0,"current":0,"existing_external":0,"failed":[],"started_at":time.time()}
        for asset_id, source, duration in tasks:
            try:
                result = make_one(str(choice.path), source, duration, root, asset_id)
                state[result] += 1
                print(json.dumps({"id":asset_id,"status":result}), flush=True)
            except Exception as error:
                state["failed"].append({"id":asset_id,"error":str(error)})
                print(json.dumps({"id":asset_id,"error":str(error)}), flush=True)
            state["done"] += 1
            status = root / ".fixed30-status.tmp"
            status.write_text(json.dumps(state), encoding="utf-8")
            os.replace(status, root / ".fixed30-status.json")
        print(json.dumps(state), flush=True)
        if state["failed"]:
            raise SystemExit(1)

if __name__ == "__main__":
    main()
