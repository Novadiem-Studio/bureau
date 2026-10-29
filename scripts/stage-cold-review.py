#!/usr/bin/env python3
"""Rebuild a routine/integration packet from live sources, then archive its read-set.

The recipe lives outside the reviewer's read root at checkpoints/NN-review-sources.json.
Its files object maps packet-relative names to ordered lists of absolute source files.
Multiple sources are concatenated with one newline between them. Framework instructions
are derived here, never copied from a previous review. Cursor resume validates the frozen
packet instead of rebuilding it from sources that may have changed during the Task.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile


def reject(message):
    raise ValueError(message)


def read_file(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        reject("source is not a regular, non-symlink file: " + str(path))
    return path.read_bytes()


def inventory(root):
    result = {}
    for path in root.rglob("*"):
        if path.is_symlink():
            reject("packet contains a symlink: " + str(path))
        if path.is_dir():
            continue
        result[path.relative_to(root).as_posix()] = read_file(path)
    return result


def main():
    root, run, ctx = map(lambda p: Path(p).absolute(), sys.argv[1:4])
    checkpoint, spawn, primary, mode, action = sys.argv[4:]
    checkpoints = run / "checkpoints"
    if ctx != checkpoints / (checkpoint + "-context") or ctx.is_symlink():
        reject("CTX must be the non-symlink checkpoints/NN-context directory")
    archive = checkpoints / (spawn + "-reviewer-context")
    slice_archive = checkpoints / (spawn + "-log-slice.md")
    if action == "resume":
        if not archive.is_dir() or archive.is_symlink():
            reject("no Cursor reviewer Task plan archive for this spawn")
        if inventory(ctx) != inventory(archive):
            reject("archived packet mismatch (artifactSha256 mismatch or changed read-set)")
        return
    if archive.exists() or slice_archive.exists():
        reject("review packet already exists for spawn " + spawn + "; use a new spawn id")
    recipe = checkpoints / (checkpoint + "-review-sources.json")
    sources = json.loads(read_file(recipe))
    if not isinstance(sources, dict) or set(sources) != {"files"} or not isinstance(sources["files"], dict):
        reject("source recipe must contain exactly a files object")
    files = {}
    bindings = {}
    reserved = {"bureau-agents.md", "delegate-reviewer.md", "conventions.md",
                "artifact.sha256", "artifacts.sha256"}
    for name, paths in sources["files"].items():
        parts = name.split("/")
        if (not name or any(p in {"", ".", ".."} for p in parts) or
                any(ord(c) < 32 or ord(c) == 127 or c == "\\" for c in name)):
            reject("unsafe packet path: " + repr(name))
        basename = parts[-1].lower()
        if (basename == "log.md" or "transcript" in basename or
                ("log-slice" in basename and name != "log-slice.md") or
                "verdict" in basename or name in reserved or parts[0] == "conventions"):
            reject("forbidden packet file: " + name)
        if not isinstance(paths, list) or not paths or not all(isinstance(p, str) for p in paths):
            reject("each packet file needs a nonempty list of source paths")
        chunks = []
        for source in paths:
            path = Path(source)
            if not path.is_absolute():
                reject("source paths must be absolute")
            resolved = path.resolve()
            if resolved == ctx.resolve() or ctx.resolve() in resolved.parents:
                reject("source cannot be a staged copy: " + source)
            if any(re.fullmatch(r".+-reviewer-context", p) for p in resolved.parts):
                reject("source cannot be a prior review archive: " + source)
            raw = read_file(path)
            if path in bindings and bindings[path] != raw:
                reject("source changed while building packet: " + source)
            bindings[path] = raw
            chunks.append(raw)
        files[name] = b"\n".join(chunks)
    for required in (primary, "state.json", "log-slice.md"):
        if required not in files:
            reject("source recipe missing " + required)
    if mode == "integration" and "integration-results.json" not in files:
        reject("integration review requires current integration-results.json source")
    if mode == "routine" and any(p == "integration-results.json" or p.startswith("gate-output/") for p in files):
        reject("routine packet must not inherit integration evidence")
    files["bureau-agents.md"] = read_file(root / "AGENTS.md")
    files["conventions.md"] = read_file(root / "docs/conventions.md")
    persona = read_file(root / "agents/delegate.md")
    match = re.search(rb"(?ms)^# COLD-REVIEWER-MODE:BEGIN\n.*?^# COLD-REVIEWER-MODE:END[^\n]*\n?", persona)
    if not match:
        reject("cold reviewer persona markers missing")
    files["delegate-reviewer.md"] = match.group()
    for path in (root / "docs/conventions").glob("*.md"):
        files["conventions/" + path.name] = read_file(path)
    infra = reserved | {"state.json", "log-slice.md", "integration-results.json"}
    artifacts = sorted(p for p in files if p not in infra and not p.startswith(("conventions/", "gate-output/")))
    if primary not in artifacts:
        reject("primary must be an artifact, not infrastructure")
    artifacts.remove(primary)
    artifacts.insert(0, primary)
    # Hash the exact bytes derived from sources, not yesterday's staged copies.
    lines = [hashlib.sha256(files[p]).hexdigest() + "  " + p + "\n" for p in artifacts]
    files["artifact.sha256"] = lines[0].encode()
    files["artifacts.sha256"] = "".join(lines).encode()
    for path, raw in bindings.items():
        if read_file(path) != raw:
            reject("source changed while building packet: " + str(path))
    temporary = Path(tempfile.mkdtemp(prefix=".review-stage-", dir=checkpoints))
    try:
        for name, raw in files.items():
            destination = temporary / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(raw)
        # Exclusive publication keeps a prior spawn's evidence intact. Archives are
        # siblings, never descendants of the reviewer's only allowed read root.
        archive.mkdir()
        shutil.copytree(temporary, archive, dirs_exist_ok=True)
        with slice_archive.open("xb") as output:
            output.write(files["log-slice.md"])
        if ctx.exists():
            shutil.rmtree(ctx)
        os.rename(temporary, ctx)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError) as exc:
        print("stage-cold-review: " + str(exc), file=sys.stderr)
        sys.exit(1)
