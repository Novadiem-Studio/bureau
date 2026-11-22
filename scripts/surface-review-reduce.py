#!/usr/bin/env python3
"""Reduce one round of parallel surface-review findings (issue #143, contracts C1, C1b, C2).

C1 (findings file) and C1b (closure packet) are stated verbatim in
agents/critic/surface-review.md; C2 (this CLI) is documented in scripts/README.md under
"Surface review reduce (`surface-review-reduce.py`)".

  surface-review-reduce.py lenses <ROUND_DIR> --lenses S1,S4|none --diff-sha <hex>
  surface-review-reduce.py final  <ROUND_DIR> --lenses S1,S4|none --diff-sha <hex> \
      --max-fix-rounds <M> [--overrides <file>]

`lenses` validates the lens findings files and writes ROUND_DIR/merged.json. `final` adds
interaction.json, applies overrides, computes the route and the round cap, writes
ROUND_DIR/final.json and, on route fix, the closure packets for the next round.

Deterministic by contract: it reads only ROUND_DIR, the prior round dir and the overrides
file; it calls no git, reads no log.md or state.json, spawns nothing and writes no
timestamps or absolute paths. Exit 0 written; 2 usage or invalid input; 3 missing input.
Exit 2 and 3 write nothing and print one stderr line naming the file and the rule.
"""
import json
import os
import re
import sys
import tempfile

LENSES = ("S1", "S2", "S3", "S4", "S5")
ORDER = {s: i for i, s in enumerate(LENSES + ("X", "R"))}
HEX64 = re.compile(r"[0-9a-f]{64}")
ROUND_NAME = re.compile(r"r([1-9][0-9]*)")
FINDING_ID = re.compile(r"r([0-9]+)-([A-Z][A-Z0-9]*)-([0-9]+)")
ROUTES = ("escalate", "checkpoint", "fix", "ship")

TOP_KEYS = {"schema", "attempt_id", "lens", "round", "diff_sha", "fired", "gate_miss",
            "closures", "findings"}
FINDING_KEYS = {"id", "surface", "file", "line", "failure_scenario", "severity", "verdict",
                "interacts", "reraises"}
CLOSURE_KEYS = {"id", "file", "line", "evidence"}
PACKET_KEYS = {"schema", "from_round", "lens", "blockers"}
PACKET_BLOCKER_KEYS = {"id", "file", "line", "failure_scenario"}
OPTIONS = ("--lenses", "--diff-sha", "--max-fix-rounds", "--overrides")


class Fail(Exception):
    def __init__(self, code, name, rule):
        super().__init__(name + ": " + rule)
        self.code = code


def reject(name, rule):
    raise Fail(2, name, rule)


def missing(name, rule):
    raise Fail(3, name, rule)


def load_json(path, name):
    def pairs(items):
        obj = {}
        for key, value in items:
            if key in obj:
                reject(name, "duplicate key %r" % key)
            obj[key] = value
        return obj

    def constant(token):
        reject(name, "invalid JSON constant " + token)

    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle, object_pairs_hook=pairs, parse_constant=constant)
    except Fail:
        raise
    except ValueError as exc:
        reject(name, "invalid JSON (%s)" % str(exc).splitlines()[0])


def closed(name, obj, keys, where):
    if not isinstance(obj, dict):
        reject(name, where + " must be an object")
    extra = sorted(set(obj) - keys)
    if extra:
        reject(name, "unknown key %r in %s" % (extra[0], where))
    lack = sorted(keys - set(obj))
    if lack:
        reject(name, "missing key %r in %s" % (lack[0], where))


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def check_file(name, value, where):
    if (not isinstance(value, str) or not value or value.startswith("/")
            or ".." in value.split("/")):
        reject(name, "file %r in %s must be repo-relative (no leading /, no ..)" % (value, where))


def check_line(name, value, where):
    if not is_int(value) or value < 1:
        reject(name, "line must be an integer >= 1 in %s (got %r)" % (where, value))


def s_ids(value):
    """A list of S-id strings. Checked before any set() so a nested list is exit 2, not a crash."""
    return isinstance(value, list) and all(isinstance(v, str) and v in LENSES for v in value)


def two_s_ids(value):
    return s_ids(value) and len(value) == 2 and len(set(value)) == 2


def text(value):
    return isinstance(value, str) and value.strip() != ""


def id_key(fid):
    match = FINDING_ID.fullmatch(fid)
    if not match:
        return (0, 99, 0, fid)
    return (int(match.group(1)), ORDER.get(match.group(2), 99), int(match.group(3)), fid)


def finding_key(finding):
    return (ORDER[finding["surface"]],) + id_key(finding["id"])


def lens_file(lens):
    return "lens-s%s.json" % lens[1:]


def parse_args(argv):
    if len(argv) < 2 or argv[0] not in ("lenses", "final"):
        reject("arguments", "stage must be lenses or final, then ROUND_DIR")
    stage, round_dir = argv[0], argv[1]
    opts = {}
    rest = argv[2:]
    while rest:
        key = rest[0]
        if key not in OPTIONS:
            reject("arguments", "unknown argument %r" % key)
        if len(rest) < 2:
            reject("arguments", key + " needs a value")
        if key in opts:
            reject("arguments", key + " given twice")
        opts[key] = rest[1]
        rest = rest[2:]

    base = os.path.basename(os.path.normpath(round_dir))
    match = ROUND_NAME.fullmatch(base)
    if not match:
        reject(base, "round dir must be named r<N> with N >= 1")
    if not os.path.isdir(round_dir):
        reject(base, "round dir is not a directory")
    n = int(match.group(1))

    if "--lenses" not in opts:
        reject("arguments", "--lenses is required")
    raw = opts["--lenses"]
    if raw == "":
        reject("arguments", "--lenses is empty")
    none = raw == "none"
    lenses = []
    if not none:
        for token in raw.split(","):
            if token not in LENSES:
                reject("arguments", "--lenses has %r; want S1..S5 or none" % token)
            if token in lenses:
                reject("arguments", "--lenses names %s twice" % token)
            lenses.append(token)
    lenses.sort(key=ORDER.get)

    sha = opts.get("--diff-sha")
    if sha is None or not HEX64.fullmatch(sha):
        reject("arguments", "--diff-sha must be 64 lowercase hex")

    max_rounds = None
    if stage == "final":
        if "--max-fix-rounds" not in opts:
            reject("arguments", "--max-fix-rounds is required for final")
        if not re.fullmatch(r"[0-9]+", opts["--max-fix-rounds"]):
            reject("arguments", "--max-fix-rounds must be a non-negative integer")
        max_rounds = int(opts["--max-fix-rounds"])
    else:
        for key in ("--max-fix-rounds", "--overrides"):
            if key in opts:
                reject("arguments", key + " is only valid for final")
    return stage, os.path.normpath(round_dir), n, none, lenses, sha, max_rounds, opts.get("--overrides")


def load_prior(round_dir, n):
    """Prior round final record and closure packets (C2 check order step 2)."""
    prev = "r%d" % (n - 1)
    prev_dir = os.path.join(os.path.dirname(round_dir), prev)
    name = prev + "/final.json"
    path = os.path.join(prev_dir, "final.json")
    if not os.path.isfile(path):
        missing(name, "missing; round %d needs the prior round's final record" % n)
    final = load_json(path, name)
    if not isinstance(final, dict) or final.get("schema") != "surface-final/1":
        reject(name, "schema must be surface-final/1")
    if final.get("round") != n - 1:
        reject(name, "round must be %d" % (n - 1))
    route = final.get("route")
    if route not in ROUTES:
        reject(name, "route must be one of " + ", ".join(ROUTES))
    if route != "fix":
        reject(name, "route is %s, not fix; round %d cannot follow it" % (route, n))
    fired = final.get("fired")
    rerun = final.get("rerun_lenses")
    if not two_s_ids(fired):
        reject(name, "fired must be exactly two distinct S-ids")
    if not isinstance(rerun, list) or not all(isinstance(r, str) and r in fired for r in rerun):
        reject(name, "rerun_lenses must be S-ids from fired")

    # Only lenses in rerun_lenses (and the interaction reviewer) have a packet. Any other
    # lens counts as an empty packet, even if a stale closure file sits in the prior dir.
    owners = [(o, "closure-s%s.json" % o[1:]) for o in sorted(rerun, key=ORDER.get)]
    owners.append(("X", "closure-x.json"))
    for owner, fname in owners:
        if not os.path.isfile(os.path.join(prev_dir, fname)):
            missing(prev + "/" + fname, "missing closure packet for %s" % owner)
    packets = {}
    for owner, fname in owners:
        pname = prev + "/" + fname
        packet = load_json(os.path.join(prev_dir, fname), pname)
        closed(pname, packet, PACKET_KEYS, "the closure packet")
        if packet["schema"] != "surface-closure/1":
            reject(pname, "schema must be surface-closure/1")
        if packet["from_round"] != n - 1 or not is_int(packet["from_round"]):
            reject(pname, "from_round must be %d" % (n - 1))
        if packet["lens"] != owner:
            reject(pname, "lens must be %s (from the filename)" % owner)
        if not isinstance(packet["blockers"], list):
            reject(pname, "blockers must be a list")
        ids = set()
        for entry in packet["blockers"]:
            closed(pname, entry, PACKET_BLOCKER_KEYS, "a packet blocker")
            if not isinstance(entry["id"], str) or entry["id"] in ids:
                reject(pname, "packet blocker id %r is not a unique string" % entry["id"])
            ids.add(entry["id"])
        packets[owner] = ids
    return prev, sorted(fired, key=ORDER.get), sorted(rerun, key=ORDER.get), packets


def validate_reviewer(name, data, lens, n, sha, fired_ref, packet):
    """C1 rules for one findings file. Returns (fired, gate_miss, closures, findings)."""
    closed(name, data, TOP_KEYS, "the top level")
    if data["schema"] != "surface-findings/1":
        reject(name, "schema must be surface-findings/1")
    if not isinstance(data["attempt_id"], str) or not data["attempt_id"].startswith("challenger-"):
        reject(name, "attempt_id must start with challenger-")
    if data["lens"] != lens:
        reject(name, "lens must be %s (from the filename)" % lens)
    if not is_int(data["round"]) or data["round"] != n:
        reject(name, "round must be %d (from the r%d dir)" % (n, n))
    if data["diff_sha"] != sha:
        reject(name, "diff_sha does not match --diff-sha")

    fired = data["fired"]
    if not two_s_ids(fired):
        reject(name, "fired must be exactly two distinct S-ids")
    fired = sorted(fired, key=ORDER.get)
    if fired_ref is not None and fired != fired_ref[1]:
        reject(name, "fired differs from %s" % fired_ref[0])
    if lens != "X" and lens not in fired:
        reject(name, "lens %s not in fired" % lens)

    gate_miss = data["gate_miss"]
    if not s_ids(gate_miss) or len(set(gate_miss)) != len(gate_miss):
        reject(name, "gate_miss must be distinct S-ids")
    for g in gate_miss:
        if g in fired:
            reject(name, "gate_miss %s is in fired; it lists surfaces outside fired" % g)

    closures = data["closures"]
    if not isinstance(closures, list):
        reject(name, "closures must be a list")
    if n == 1 and closures:
        reject(name, "closures must be [] in round 1")
    for i, entry in enumerate(closures):
        where = "closure entry %d" % i
        closed(name, entry, CLOSURE_KEYS, where)
        if not isinstance(entry["id"], str):
            reject(name, "closure id in %s must be a string" % where)
        check_file(name, entry["file"], where)
        check_line(name, entry["line"], where)
        if not text(entry["evidence"]):
            reject(name, "closure evidence is empty in %s" % where)

    findings = data["findings"]
    if not isinstance(findings, list):
        reject(name, "findings must be a list")
    seen = set()
    for i, f in enumerate(findings):
        where = "finding %d" % i
        closed(name, f, FINDING_KEYS, where)
        fid = f["id"]
        match = FINDING_ID.fullmatch(fid) if isinstance(fid, str) else None
        if not match:
            reject(name, "finding id %r must be r<N>-<lens>-<n>" % (fid,))
        rnum, idlens, num = match.groups()
        if rnum != str(int(rnum)) or int(rnum) != n:
            reject(name, "finding id %r has the wrong round prefix (want r%d)" % (fid, n))
        if idlens != lens:
            reject(name, "id lens of %r must be %s" % (fid, lens))
        if num != str(int(num)) or int(num) < 1:
            reject(name, "id number of %r must be >= 1 with no leading zero" % fid)
        if fid in seen:
            reject(name, "duplicate id %r" % fid)
        seen.add(fid)
        where = "finding " + fid
        surface = f["surface"]
        if lens == "X":
            if surface not in ("X", "R"):
                reject(name, "surface %r of %s must be X or R in the interaction file" % (surface, fid))
        elif surface != lens:
            reject(name, "surface %r of %s must equal lens %s" % (surface, fid, lens))
        check_file(name, f["file"], where)
        check_line(name, f["line"], where)
        if not text(f["failure_scenario"]):
            reject(name, "failure_scenario is empty in %s" % where)
        if f["severity"] not in ("blocker", "warning"):
            reject(name, "severity of %s must be blocker or warning" % fid)
        if f["verdict"] not in ("confirmed", "plausible"):
            reject(name, "verdict of %s must be confirmed or plausible" % fid)
        interacts = f["interacts"]
        if surface == "X":
            if (not isinstance(interacts, list)
                    or not all(isinstance(s, str) for s in interacts)
                    or len(interacts) < 2 or len(set(interacts)) != len(interacts)):
                reject(name, "interacts of %s must be two or more distinct S-ids" % fid)
            for s in interacts:
                if s not in fired:
                    reject(name, "interacts id %s of %s not in fired" % (s, fid))
        elif interacts != []:
            reject(name, "interacts must be [] on a %s finding (%s)" % (surface, fid))
        reraises = f["reraises"]
        if reraises is not None:
            if not isinstance(reraises, str):
                reject(name, "reraises of %s must be null or an id" % fid)
            if f["severity"] != "blocker":
                reject(name, "reraises only allowed on a blocker finding (%s)" % fid)
            if n == 1:
                reject(name, "reraises must be null in round 1 (%s)" % fid)

    if n >= 2:
        closed_ids = [c["id"] for c in closures]
        raised = [f["reraises"] for f in findings if f["reraises"] is not None]
        for cid in closed_ids:
            if cid not in packet:
                reject(name, "closure id %r not in closure packet" % cid)
        for rid in raised:
            if rid not in packet:
                reject(name, "reraises %r not in closure packet" % rid)
        for both in sorted(set(closed_ids) & set(raised), key=id_key):
            reject(name, "%s: both closed and re-raised" % both)
        for label, ids in (("closed", closed_ids), ("re-raised", raised)):
            if len(set(ids)) != len(ids):
                twice = sorted({i for i in ids if ids.count(i) > 1}, key=id_key)[0]
                reject(name, "%s: %s twice" % (twice, label))
        for absent in sorted(packet - set(closed_ids) - set(raised), key=id_key):
            reject(name, "%s: neither closed nor re-raised (silently absent is not closed)" % absent)
    return fired, gate_miss, closures, findings


def merge(findings, overridden, final):
    groups = {}
    for f in findings:
        groups.setdefault((f["file"], f["line"]), []).append(f)
    entries = []
    for key in sorted(groups):
        members = sorted(groups[key], key=finding_key)
        surfaces = set()
        for m in members:
            if m["surface"] in LENSES:
                surfaces.add(m["surface"])
            surfaces.update(m["interacts"])
        tags = [t for t in ("X", "R") if any(m["surface"] == t for m in members)]
        entry = {
            "file": key[0],
            "line": key[1],
            "surfaces": sorted(surfaces, key=ORDER.get) + tags,
            "ids": [m["id"] for m in members],
            "scenarios": [{"id": m["id"], "surface": m["surface"],
                           "text": m["failure_scenario"], "reraises": m["reraises"]}
                          for m in members],
            "verdict": "confirmed" if any(m["verdict"] == "confirmed" for m in members)
                       else "plausible",
            "severity": "blocker" if any(m["severity"] == "blocker" and m["id"] not in overridden
                                         for m in members) else "warning",
        }
        if final:
            entry["overridden_ids"] = [m["id"] for m in members if m["id"] in overridden]
        entries.append(entry)
    return entries


def load_overrides(path, blocker_ids):
    name = os.path.basename(path)
    data = load_json(path, name)
    closed(name, data, {"overrides"}, "the top level")
    if not isinstance(data["overrides"], list):
        reject(name, "overrides must be a list")
    ids = set()
    for i, entry in enumerate(data["overrides"]):
        closed(name, entry, {"id", "reason"}, "override %d" % i)
        oid = entry["id"]
        if not isinstance(oid, str) or oid not in blocker_ids:
            reject(name, "override id %r is not a blocker finding in this round" % (oid,))
        if oid in ids:
            reject(name, "override id %r listed twice" % oid)
        if not text(entry["reason"]):
            reject(name, "override reason for %r is empty" % oid)
        ids.add(oid)
    return ids


def dump(obj):
    return json.dumps(obj, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def publish(round_dir, here, outputs, stale=()):
    """Write every output to a temp file first, then os.replace each; the record goes last.
    Then remove each `stale` file (closure packets a previous `final` left behind).

    Every destination and stale path is checked before the first replace, so one that
    cannot be replaced or removed (a directory at final.json) is exit 2 with nothing
    written. shortcut: a rename that fails after that check (a concurrent writer in the
    round dir) is not rolled back; add rollback if the round dir ever gets a second writer.
    Likewise an unlink of a stale closure packet that fails after the replaces exits 2 with
    final.json already written. That is harmless: load_prior reads only the packets the
    prior rerun_lenses asks for (plus closure-x.json), so a leftover packet is ignored.
    """
    for fname in [o[0] for o in outputs] + list(stale):
        dest = os.path.join(round_dir, fname)
        if os.path.lexists(dest) and (os.path.islink(dest) or not os.path.isfile(dest)):
            reject(here + "/" + fname, "destination exists and is not a regular file")
    temps = []
    try:
        for fname, body in outputs:
            fd, tmp = tempfile.mkstemp(prefix=".surface-reduce-", suffix=".tmp", dir=round_dir)
            temps.append(tmp)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(body)
        for tmp, (fname, _) in zip(temps, outputs):
            os.replace(tmp, os.path.join(round_dir, fname))
        for fname in stale:
            os.unlink(os.path.join(round_dir, fname))
    finally:
        for tmp in temps:
            if os.path.exists(tmp):
                os.unlink(tmp)


def run(argv):
    stage, round_dir, n, none, lenses, sha, max_rounds, overrides_path = parse_args(argv)
    here = "r%d" % n

    # Step 2: prior-round inputs.
    prior, prior_fired, prior_rerun, packets = None, [], [], {}
    if n >= 2:
        prev, prior_fired, prior_rerun, packets = load_prior(round_dir, n)
        prior = (prev + "/final.json", prior_fired)

    # Step 3: the --lenses rules.
    if none:
        if n == 1:
            reject("arguments", "--lenses none is only for a readiness-only fix round (round 2 or later)")
        if prior_rerun:
            reject(prior[0], "--lenses none needs rerun_lenses [], got " + ",".join(prior_rerun))
    elif n >= 2:
        for lens in prior_rerun:
            if lens not in lenses:
                reject(prior[0], "--lenses skips %s, which rerun_lenses asks for" % lens)
        for lens in lenses:
            if lens not in prior_fired:
                reject(prior[0], "--lenses %s is not in fired %s" % (lens, ",".join(prior_fired)))
    elif len(lenses) != 2:
        # Round 1 runs both fired lenses. fired is in the files, so only the count is checked
        # here; step 5 (each lens in its file's fired, fired two ids and the same in every
        # file) then makes --lenses equal to fired.
        reject("arguments", "--lenses must name both fired lenses in round 1 (got %s)"
               % ",".join(lenses))
    for fname in sorted(os.listdir(round_dir)):
        if re.fullmatch(r"lens-s.*\.json", fname) and fname not in [lens_file(l) for l in lenses]:
            reject(here + "/" + fname, "lens file for a lens not in --lenses")

    # Step 4: this round's reviewer files, S1..S5 then interaction.json.
    files = [(lens, lens_file(lens)) for lens in lenses]
    if stage == "final":
        files.append(("X", "interaction.json"))
    for lens, fname in files:
        if not os.path.isfile(os.path.join(round_dir, fname)):
            who = "the interaction reviewer" if lens == "X" else "lens " + lens
            missing(here + "/" + fname, "missing reviewer file for " + who)
    if overrides_path is not None and not os.path.isfile(overrides_path):
        missing(os.path.basename(overrides_path), "overrides file missing")

    # Step 5: C1 validation in the same order.
    # fired must match the prior final.json, or in round 1 the first file read.
    ref = prior
    gate_miss, closed_all, findings = set(), [], []
    for lens, fname in files:
        name = here + "/" + fname
        data = load_json(os.path.join(round_dir, fname), name)
        f_fired, f_gate, f_closures, f_findings = validate_reviewer(
            name, data, lens, n, sha, ref, packets.get(lens, set()))
        if ref is None:
            ref = (name, f_fired)
        gate_miss.update(f_gate)
        closed_all.extend(dict(c, lens=lens) for c in f_closures)
        findings.extend(f_findings)
    fired = ref[1]

    overridden = set()
    if overrides_path is not None:
        blockers = {f["id"] for f in findings if f["severity"] == "blocker"}
        overridden = load_overrides(overrides_path, blockers)

    record = {
        "schema": "surface-final/1" if stage == "final" else "surface-merged/1",
        "round": n,
        "diff_sha": sha,
        "fired": fired,
        "lenses": lenses,
        "gate_miss": sorted(gate_miss, key=ORDER.get),
        "closed": sorted(closed_all, key=lambda c: (ORDER[c["lens"]],) + id_key(c["id"])),
        "findings": merge(findings, overridden, stage == "final"),
    }
    blockers = sum(1 for e in record["findings"] if e["severity"] == "blocker")
    record["counts"] = {"blocker": blockers, "warning": len(record["findings"]) - blockers}
    line = "surface-review %s %s: %d findings, %d blockers" % (
        here, stage, len(record["findings"]), blockers)
    if stage == "lenses":
        publish(round_dir, here, [("merged.json", dump(record))])
        return line

    open_blockers = sorted((f for f in findings
                            if f["severity"] == "blocker" and f["id"] not in overridden),
                           key=finding_key)
    if record["gate_miss"]:
        route = "escalate"
    elif open_blockers and n - 1 >= max_rounds:
        route = "checkpoint"
    elif open_blockers:
        route = "fix"
    else:
        route = "ship"
    rerun = set()
    if route == "fix":
        for f in open_blockers:
            if f["surface"] in LENSES:
                rerun.add(f["surface"])
            elif f["surface"] == "X":
                rerun.update(f["interacts"])
    record.update(route=route, rerun_lenses=sorted(rerun, key=ORDER.get),
                  rerun_interaction=route == "fix", max_fix_rounds=max_rounds)

    outputs = []
    if route == "fix":
        def packet(owner, owned):
            return dump({"schema": "surface-closure/1", "from_round": n, "lens": owner,
                         "blockers": [{"id": f["id"], "file": f["file"], "line": f["line"],
                                       "failure_scenario": f["failure_scenario"]}
                                      for f in open_blockers if f["surface"] in owned]})
        for lens in record["rerun_lenses"]:
            outputs.append(("closure-s%s.json" % lens[1:], packet(lens, (lens,))))
        outputs.append(("closure-x.json", packet("X", ("X", "R"))))
    outputs.append(("final.json", dump(record)))
    # Packets from an earlier `final` on this round dir that this run does not rewrite are
    # removed, so the packets on disk always match the latest final.json.
    written = {o[0] for o in outputs}
    stale = [f for f in sorted(os.listdir(round_dir))
             if re.fullmatch(r"closure-.*\.json", f) and f not in written]
    publish(round_dir, here, outputs, stale)
    return line + ", route " + route


def main(argv):
    try:
        line = run(argv)
    except Fail as exc:
        print("surface-review-reduce: " + str(exc), file=sys.stderr)
        return exc.code
    except OSError as exc:
        print("surface-review-reduce: io: %s" % exc, file=sys.stderr)
        return 2
    print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
