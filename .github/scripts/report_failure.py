#!/usr/bin/env python3
"""Turns a failed analyze / test / build log into GitHub check annotations and
a commit comment.

Raw job logs live on a blob store that is not always reachable from the
tooling used to work on this repository, so the useful part of the log is
re-published where the REST API can serve it:

* check annotations (GitHub keeps at most 10 per level and step, so the
  first 30 findings are spread over error / warning / notice), and
* a commit comment on the pushed commit with the full findings (capped at
  60 000 characters).

Usage: report_failure.py <analyze|test|build> <logfile>
"""

import json
import os
import re
import sys

KIND, LOG = sys.argv[1], sys.argv[2]
LIMIT = 60_000

with open(LOG, encoding="utf-8", errors="replace") as handle:
    lines = [line.rstrip("\n") for line in handle]

findings = []  # (path or None, line or None, title, message)

if KIND == "analyze":
    pattern = re.compile(
        r"^\s*(error|warning|info) • (.*) • (.*?):(\d+):(\d+) • (\S+)\s*$"
    )
    for line in lines:
        match = pattern.match(line)
        if match:
            level, message, path, line_no, _, rule = match.groups()
            findings.append((path, line_no, f"{level} {rule}", message))
    headline = f"flutter analyze: {len(findings)} issue(s)"
elif KIND == "test":
    progress = re.compile(r"^\d\d:\d\d \+\d+(?: ~\d+)?(?: -\d+)?: (.*?)(?: \[E\])?$")
    compile_error = re.compile(r"^\s*((?:test|lib)/\S+?\.dart):(\d+):(\d+): Error: (.*)$")
    blocks = []
    current = None
    for line in lines:
        compiled = compile_error.match(line)
        if compiled:
            path, line_no, _, message = compiled.groups()
            findings.append((path, line_no, "Compile error", message))
            continue
        match = progress.match(line)
        if match:
            current = [line] if line.endswith("[E]") else None
            if current:
                blocks.append(current)
            continue
        if current is not None and len(current) < 60:
            current.append(line)
    for block in blocks:
        title = block[0].split(": ", 1)[1].removesuffix(" [E]")
        detail = "\n".join(entry.rstrip() for entry in block[1:] if entry.strip())
        # Point the annotation at the test file when the trace names one.
        location = re.search(r"(test/[^\s:]+?\.dart)[ :](\d+):\d+", detail)
        path = location.group(1) if location else None
        line_no = location.group(2) if location else None
        findings.append((path, line_no, "Test failed", f"{title}\n{detail}"))
    headline = f"flutter test: {len(blocks)} failing test(s)"
else:
    dart_error = re.compile(r"^\s*((?:lib|test)/\S+?\.dart):(\d+):(\d+): Error: (.*)$")
    other = re.compile(r"(FAILURE:|What went wrong|error:|Error:|Exception)")
    for line in lines:
        match = dart_error.match(line)
        if match:
            path, line_no, _, message = match.groups()
            findings.append((path, line_no, "Compile error", message))
        elif other.search(line):
            findings.append((None, None, "Build", line.strip()))
    headline = f"flutter build apk: {len(findings)} error line(s)"

# --- annotations -------------------------------------------------------------
print(f"::error title={KIND}::{headline}; see the commit comment for the full list")
levels = ["error"] * 9 + ["warning"] * 10 + ["notice"] * 10
for level, (path, line_no, title, message) in zip(levels, findings):
    text = message.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    where = f" file=flutter_app/{path},line={line_no}" if path else ""
    print(f"::{level}{where},title={title}::{text}" if where else f"::{level} title={title}::{text}")

# --- commit comment ----------------------------------------------------------
parts = [f"### {headline} — run {os.environ.get('GITHUB_RUN_ID', '?')}", ""]
if findings:
    for path, line_no, title, message in findings:
        where = f"`{path}:{line_no}` " if path else ""
        parts.append(f"- **{title}** {where}\n  ```\n  " + message.replace("\n", "\n  ") + "\n  ```")
else:
    parts.append("No structured findings; log tail:")
    parts.append("```")
    parts.extend(lines[-200:])
    parts.append("```")
body = "\n".join(parts)
if len(body) > LIMIT:
    body = body[: LIMIT - 40] + "\n\n…truncated…"
with open("failure-comment.json", "w", encoding="utf-8") as handle:
    json.dump({"body": body}, handle)
