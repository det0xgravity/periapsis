#!/usr/bin/env python3
"""pa_event — CTF events, challenges, flags and writeups for Periapsis.

Layout (all private, mode 700):

  ~/Periapsis/Events/<event>/
    event.json                       name, platform, URL, flag format, state
    audit.log                        hash-chained log (same format as lib/ui.sh)
    Writeup.md                       built by `writeup`
    <category>/<challenge>/
      challenge.json                 name, category, points, status, flag
      notes.md                       your working notes / writeup section
      files/                         the challenge's handout files
      solve/                         your scripts and exploits

Standard library only. Usage: pa_event <command> --help
"""

import argparse
import datetime as dt
import getpass
import hashlib
import json
import os
import re
import sys

CATEGORIES = ["web", "crypto", "pwn", "rev", "forensics", "stego", "osint",
              "misc", "network", "hardware", "blockchain", "boot2root"]
STATUSES = ["todo", "working", "solved", "skipped"]


def data_root():
    return os.environ.get("PA_DATA") or os.path.expanduser("~/Periapsis")


def events_root():
    return os.path.join(data_root(), "Events")


def now():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def slug(text):
    s = re.sub(r"[^a-z0-9._-]+", "-", text.lower()).strip("-")
    return re.sub(r"-+", "-", s)[:60] or "untitled"


def private_dirs(path):
    old = os.umask(0o077)
    try:
        os.makedirs(path, exist_ok=True)
    finally:
        os.umask(old)


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def die(msg, code=1):
    print(f"pa_event: {msg}", file=sys.stderr)
    sys.exit(code)


# --- audit log --------------------------------------------------------------
# Same format as pa_audit in lib/ui.sh: six tab-separated fields, then
# SHA-256(previous line + those fields joined by tabs).

def _field(s):
    return re.sub(r"[\t\r\n]", " ", str(s))


def audit(event_dir, tool, target, detail):
    log = os.path.join(event_dir, "audit.log")
    body = "\t".join([now(), os.path.basename(event_dir), _field(tool),
                      _field(target), _field(detail), getpass.getuser()])
    prev = ""
    if os.path.exists(log) and os.path.getsize(log):
        with open(log, encoding="utf-8") as f:
            lines = f.read().splitlines()
            prev = lines[-1] if lines else ""
    h = hashlib.sha256((prev + body).encode("utf-8")).hexdigest()
    with open(log, "a", encoding="utf-8") as f:
        f.write(f"{body}\t{h}\n")


def audit_verify(log):
    """Returns (ok, message)."""
    if not os.path.exists(log):
        return True, "no audit log yet"
    prev = ""
    with open(log, encoding="utf-8") as f:
        for n, line in enumerate(f.read().splitlines(), 1):
            body, sep, h = line.rpartition("\t")
            if not sep or body.count("\t") != 5:
                return False, f"line {n}: malformed"
            if hashlib.sha256((prev + body).encode("utf-8")).hexdigest() != h:
                return False, f"line {n}: hash mismatch (edited, inserted or deleted lines)"
            prev = line
    return True, f"{n if prev else 0} lines, chain intact"


# --- events -----------------------------------------------------------------

def event_dir(name):
    d = os.path.join(events_root(), slug(name))
    if not os.path.isfile(os.path.join(d, "event.json")):
        die(f"no such event: {name} (pa-event list)")
    return d


def cmd_new(a):
    s = slug(a.name)
    d = os.path.join(events_root(), s)
    meta_path = os.path.join(d, "event.json")
    if os.path.exists(meta_path):
        die(f"event already exists: {s}")
    if a.flag_format:
        try:
            re.compile(a.flag_format)
        except re.error as e:
            die(f"flag format is not a valid regex: {e}")
    private_dirs(d)
    for p in (data_root(), events_root(), d):
        os.chmod(p, 0o700)
    write_json(meta_path, {
        "name": a.name, "slug": s, "platform": a.platform or "", "url": a.url or "",
        "flag_format": a.flag_format or "", "state": "live", "created": now(),
        "finished": "",
    })
    audit(d, "pa_event", s, f"new event: {a.name}")
    print(s)


def list_events():
    root = events_root()
    if not os.path.isdir(root):
        return []
    out = []
    for s in sorted(os.listdir(root)):
        p = os.path.join(root, s, "event.json")
        if os.path.isfile(p):
            out.append(read_json(p))
    return out


def cmd_list(a):
    evs = list_events()
    if a.tsv:
        for e in evs:
            print(f"{e['slug']}\t{e['name']}\t{e['state']}")
        return
    if not evs:
        print("No events yet. Create one: pa-event new \"<name>\"")
    for e in evs:
        print(f"{e['slug']:<30} {e['state']:<9} {e['name']}")


def cmd_finish(a):
    d = event_dir(a.event)
    p = os.path.join(d, "event.json")
    meta = read_json(p)
    meta["state"] = "finished"
    meta["finished"] = now()
    write_json(p, meta)
    audit(d, "pa_event", meta["slug"], "event finished")
    print(f"{meta['name']}: finished")


def cmd_set(a):
    d = event_dir(a.event)
    p = os.path.join(d, "event.json")
    meta = read_json(p)
    if a.key not in ("platform", "url", "flag_format", "state"):
        die("can set: platform, url, flag_format, state")
    if a.key == "flag_format" and a.value:
        try:
            re.compile(a.value)
        except re.error as e:
            die(f"flag format is not a valid regex: {e}")
    if a.key == "state" and a.value not in ("live", "finished"):
        die("state is live or finished")
    meta[a.key] = a.value
    write_json(p, meta)
    audit(d, "pa_event", meta["slug"], f"set {a.key}={a.value}")


# --- challenges -------------------------------------------------------------

def challenges(d):
    out = []
    for cat in sorted(os.listdir(d)):
        cd = os.path.join(d, cat)
        if not os.path.isdir(cd) or cat.startswith("."):
            continue
        for ch in sorted(os.listdir(cd)):
            p = os.path.join(cd, ch, "challenge.json")
            if os.path.isfile(p):
                c = read_json(p)
                c["_dir"] = os.path.join(cd, ch)
                c["_id"] = f"{cat}/{ch}"
                out.append(c)
    return out


def find_challenge(d, ref):
    """ref is category/slug, or a slug or name that matches exactly one challenge."""
    chs = challenges(d)
    hits = [c for c in chs if c["_id"] == ref]
    if not hits:
        hits = [c for c in chs if c["_id"].split("/", 1)[1] == slug(ref)
                or c["name"].lower() == ref.lower()]
    if not hits:
        die(f"no such challenge: {ref}")
    if len(hits) > 1:
        die(f"'{ref}' matches several challenges: " + ", ".join(c["_id"] for c in hits))
    return hits[0]


def save_challenge(c):
    write_json(os.path.join(c["_dir"], "challenge.json"),
               {k: v for k, v in c.items() if not k.startswith("_")})


def cmd_add(a):
    d = event_dir(a.event)
    cat = slug(a.category)
    s = slug(a.name)
    cdir = os.path.join(d, cat, s)
    if os.path.exists(os.path.join(cdir, "challenge.json")):
        print(cdir)
        return
    for sub in ("files", "solve"):
        private_dirs(os.path.join(cdir, sub))
    write_json(os.path.join(cdir, "challenge.json"), {
        "name": a.name, "category": cat, "points": a.points, "status": "todo",
        "url": a.url or "", "flag": "", "added": now(), "solved": "",
    })
    notes = os.path.join(cdir, "notes.md")
    if not os.path.exists(notes):
        with open(notes, "w", encoding="utf-8") as f:
            f.write(f"## {a.name}\n\n"
                    f"**Category:** {cat}" + (f" · **Points:** {a.points}" if a.points else "") + "\n\n"
                    "### Description\n\n\n"
                    "### Recon\n\n\n"
                    "### Solution\n\n\n"
                    "### Takeaways\n\n")
    audit(d, "pa_event", f"{cat}/{s}", f"challenge added: {a.name}")
    print(cdir)


def cmd_chals(a):
    d = event_dir(a.event)
    for c in challenges(d):
        if a.tsv:
            print(f"{c['_id']}\t{c['name']}\t{c['status']}\t{c.get('points') or ''}\t{c['_dir']}")
        else:
            pts = str(c.get("points") or "")
            print(f"{c['status']:<8} {pts:>5}  {c['_id']:<36} {c['name']}")


def cmd_path(a):
    print(find_challenge(event_dir(a.event), a.challenge)["_dir"])


def cmd_status(a):
    d = event_dir(a.event)
    c = find_challenge(d, a.challenge)
    if a.status not in STATUSES:
        die("status is one of: " + ", ".join(STATUSES))
    c["status"] = a.status
    if a.status != "solved":
        c["solved"] = ""
    save_challenge(c)
    audit(d, "pa_event", c["_id"], f"status: {a.status}")


def cmd_flag(a):
    """Exit 0 = recorded; 2 = doesn't match the event's flag format (not
    recorded unless --force)."""
    d = event_dir(a.event)
    meta = read_json(os.path.join(d, "event.json"))
    c = find_challenge(d, a.challenge)
    flag = a.flag.strip()
    fmt = meta.get("flag_format") or ""
    if fmt and not re.fullmatch(fmt, flag) and not a.force:
        print(f"'{flag}' doesn't match this event's flag format: {fmt}", file=sys.stderr)
        sys.exit(2)
    c["flag"] = flag
    c["status"] = "solved"
    c["solved"] = now()
    save_challenge(c)
    # The flag goes in challenge.json, not the audit log, so the log can be shared
    audit(d, "pa_event", c["_id"], "flag recorded, sha256:" + hashlib.sha256(flag.encode()).hexdigest()[:16])
    print(f"{c['_id']}: solved")


def cmd_board(a):
    d = event_dir(a.event)
    meta = read_json(os.path.join(d, "event.json"))
    chs = challenges(d)
    solved = [c for c in chs if c["status"] == "solved"]
    pts = sum(int(c.get("points") or 0) for c in solved)
    print(f"{meta['name']}  [{meta['state']}]" + (f"  {meta['platform']}" if meta.get("platform") else ""))
    print(f"Solved {len(solved)}/{len(chs)}" + (f" · {pts} points" if pts else ""))
    cats = sorted({c["category"] for c in chs})
    for cat in cats:
        cc = [c for c in chs if c["category"] == cat]
        done = sum(1 for c in cc if c["status"] == "solved")
        print(f"\n{cat}  ({done}/{len(cc)})")
        for c in cc:
            mark = {"solved": "✔", "working": "…", "skipped": "–"}.get(c["status"], " ")
            p = str(c.get("points") or "")
            print(f"  [{mark}] {c['name']:<40} {p:>5}")


def cmd_writeup(a):
    """Writeup.md from every challenge's notes.md. Flags are left out unless
    --flags, and a live event gets a warning banner: most CTFs forbid
    publishing solutions before the event ends."""
    d = event_dir(a.event)
    meta = read_json(os.path.join(d, "event.json"))
    chs = challenges(d)
    if a.solved_only:
        chs = [c for c in chs if c["status"] == "solved"]
    out = [f"# {meta['name']} — writeups", ""]
    if meta.get("platform") or meta.get("url"):
        out += [" · ".join(x for x in (meta.get("platform"), meta.get("url")) if x), ""]
    out += [f"Author: {a.author}", ""] if a.author else []
    if meta["state"] == "live":
        out += ["> **Event still live.** Don't publish this until the event ends and the "
                "organisers allow writeups.", ""]
    for cat in sorted({c["category"] for c in chs}):
        out += [f"# {cat}", ""]
        for c in [c for c in chs if c["category"] == cat]:
            notes = os.path.join(c["_dir"], "notes.md")
            body = open(notes, encoding="utf-8").read().strip() if os.path.exists(notes) else f"## {c['name']}"
            out += [body, ""]
            if a.flags and c.get("flag"):
                out += [f"**Flag:** `{c['flag']}`", ""]
    path = os.path.join(d, "Writeup.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out).rstrip() + "\n")
    audit(d, "pa_event", meta["slug"], "writeup built" + (" with flags" if a.flags else ""))
    print(path)


def cmd_audit(a):
    audit(event_dir(a.event), a.tool, a.target, a.detail)


def cmd_audit_verify(a):
    ok, msg = audit_verify(a.log)
    print(msg)
    sys.exit(0 if ok else 1)


def main():
    p = argparse.ArgumentParser(prog="pa_event", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("new", help="create an event")
    s.add_argument("name")
    s.add_argument("--platform", help="e.g. CTFd, picoCTF, HTB")
    s.add_argument("--url")
    s.add_argument("--flag-format", help=r"regex a flag must match, e.g. 'flag\{.+\}'")
    s.set_defaults(fn=cmd_new)

    s = sub.add_parser("list", help="list events")
    s.add_argument("--tsv", action="store_true")
    s.set_defaults(fn=cmd_list)

    s = sub.add_parser("finish", help="mark an event finished")
    s.add_argument("event")
    s.set_defaults(fn=cmd_finish)

    s = sub.add_parser("set", help="change an event setting")
    s.add_argument("event")
    s.add_argument("key")
    s.add_argument("value")
    s.set_defaults(fn=cmd_set)

    s = sub.add_parser("add", help="add a challenge; prints its folder")
    s.add_argument("event")
    s.add_argument("category")
    s.add_argument("name")
    s.add_argument("--points", type=int, default=0)
    s.add_argument("--url")
    s.set_defaults(fn=cmd_add)

    s = sub.add_parser("chals", help="list challenges")
    s.add_argument("event")
    s.add_argument("--tsv", action="store_true")
    s.set_defaults(fn=cmd_chals)

    s = sub.add_parser("path", help="print a challenge's folder")
    s.add_argument("event")
    s.add_argument("challenge")
    s.set_defaults(fn=cmd_path)

    s = sub.add_parser("status", help="set a challenge's status")
    s.add_argument("event")
    s.add_argument("challenge")
    s.add_argument("status", choices=STATUSES)
    s.set_defaults(fn=cmd_status)

    s = sub.add_parser("flag", help="record a flag (checked against the flag format)")
    s.add_argument("event")
    s.add_argument("challenge")
    s.add_argument("flag")
    s.add_argument("--force", action="store_true", help="record even if the format doesn't match")
    s.set_defaults(fn=cmd_flag)

    s = sub.add_parser("board", help="progress by category")
    s.add_argument("event")
    s.set_defaults(fn=cmd_board)

    s = sub.add_parser("writeup", help="build Writeup.md from the challenge notes")
    s.add_argument("event")
    s.add_argument("--flags", action="store_true", help="include the flags")
    s.add_argument("--solved-only", action="store_true")
    s.add_argument("--author", default=os.environ.get("PA_AUTHOR", ""))
    s.set_defaults(fn=cmd_writeup)

    s = sub.add_parser("audit", help="append to an event's audit log")
    s.add_argument("event")
    s.add_argument("tool")
    s.add_argument("target")
    s.add_argument("detail")
    s.set_defaults(fn=cmd_audit)

    s = sub.add_parser("audit-verify", help="check an audit log's hash chain")
    s.add_argument("log")
    s.set_defaults(fn=cmd_audit_verify)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
