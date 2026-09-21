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
    # The compact reporter prints a progress line before every chunk of test
    # output.  A failing widget test therefore appears twice: first as
    # "<title>" followed by the framework's exception dump, then as
    # "<title> [E]" followed by the (terse) failure summary.  Both parts are
    # kept and merged so the comment shows the real assertion.
    progress = re.compile(r"^\d\d:\d\d \+\d+(?: ~\d+)?(?: -\d+)?: (.*?)( \[E\])?$")
    compile_error = re.compile(r"^\s*((?:test|lib)/\S+?\.dart):(\d+):(\d+): Error: (.*)$")
    frame = re.compile(r"^\s*#\d+\s")
    noise = re.compile(r"^[═╞╡\s]*$")
    seen_compile = set()
    printed = {}  # title -> lines printed by the test before it failed
    failures = []  # (title, summary lines)
    current_title, current_failed = None, False
    for line in lines:
        compiled = compile_error.match(line)
        if compiled:
            path, line_no, _, message = compiled.groups()
            key = (path, line_no, message)
            if key not in seen_compile:
                seen_compile.add(key)
                findings.append((path, line_no, "Compile error", message))
            continue
        match = progress.match(line)
        if match:
            current_title, current_failed = match.group(1), bool(match.group(2))
            if current_failed:
                failures.append((current_title, []))
            continue
        if current_title is None:
            continue
        if current_failed:
            if len(failures[-1][1]) < 40:
                failures[-1][1].append(line)
        else:
            printed.setdefault(current_title, []).append(line)

    def useful(block):
        """Keeps messages and the stack frames that point at our own code."""
        kept = []
        for entry in block:
            text = entry.rstrip()
            if not text.strip() or noise.match(text):
                continue
            if frame.match(text) and not re.search(r"(package:lab_wizard/|[\s(/]test/\S+_test\.dart)", text):
                continue
            if text.startswith("(elided ") or "asynchronous suspension" in text:
                continue
            kept.append(text)
            if len(kept) >= 45:
                kept.append("…")
                break
        return kept

    for title, summary in failures:
        detail_lines = useful(printed.get(title, [])) + useful(summary)
        detail = "\n".join(detail_lines)
        # Point the annotation at the test file when the trace names one.
        location = re.search(r"(?:^|[\s(/])(test/[^\s:]+?_test\.dart)[ :](\d+):\d+", detail, re.M)
        path = location.group(1) if location else None
        line_no = location.group(2) if location else None
        short_title = title.split("/flutter_app/")[-1]
        findings.append((path, line_no, "Test failed", f"{short_title}\n{detail}"))
    headline = f"flutter test: {len(failures)} failing test(s)"
else:
    dart_error = re.compile(r"^\s*((?:lib|test)/\S+?\.dart):(\d+):(\d+): Error: (.*)$")
    other = re.compile(r"(FAILURE:|What went wrong|error:|Error:|Exception)")
    capture_block = False
    block_lines = []
    for line in lines:
        match = dart_error.match(line)
        if match:
            path, line_no, _, message = match.groups()
            findings.append((path, line_no, "Compile error", message))
            continue
        if "FAILURE: Build failed" in line or "* What went wrong:" in line or capture_block:
            capture_block = True
            block_lines.append(line)
            if len(block_lines) >= 35 or "* Try:" in line:
                findings.append((None, None, "Gradle failure", "\n".join(block_lines)))
                block_lines = []
                capture_block = False
        elif other.search(line):
            findings.append((None, None, "Build", line.strip()))
    if block_lines:
        findings.append((None, None, "Gradle failure", "\n".join(block_lines)))
    headline = f"flutter build apk: {len(findings)} error line(s)"

# --- annotations -------------------------------------------------------------
print(f"::error title={KIND}::{headline}; see the commit comment for the full list")
levels = ["error"] * 9 + ["warning"] * 10 + ["notice"] * 10
for level, (path, line_no, title, message) in zip(levels, findings):
    text = message.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    where = f" file=flutter_app/{path},line={line_no}" if path else ""
    print(f"::{level}{where},title={title}::{text}" if where else f"::{level} title={title}::{text}")

# --- commit comment ----------------------------------------------------------
def render(findings, detail_limit):
    """Comment body; details are cut to detail_limit characters each so the
    list of failures always fits GitHub's comment size."""
    parts = [f"### {headline} — run {os.environ.get('GITHUB_RUN_ID', '?')}", ""]
    if not findings:
        parts.append("No structured findings; log tail:")
        parts.append("```")
        parts.extend(lines[-200:])
        parts.append("```")
        return "\n".join(parts)
    for path, line_no, title, message in findings:
        where = f"`{path}:{line_no}` " if path else ""
        if detail_limit == 0:
            parts.append(f"- **{title}** {where}{message.splitlines()[0] if message else ''}")
            continue
        if len(message) > detail_limit:
            message = message[:detail_limit] + "\n  … (cut)"
        parts.append(f"- **{title}** {where}\n  ```\n  " + message.replace("\n", "\n  ") + "\n  ```")
    return "\n".join(parts)


body = render(findings, 4000)
for detail_limit in (2000, 1000, 500, 0):
    if len(body) <= LIMIT:
        break
    body = render(findings, detail_limit)
if len(body) > LIMIT:
    body = body[: LIMIT - 40] + "\n\n…truncated…"
with open("failure-comment.json", "w", encoding="utf-8") as handle:
    json.dump({"body": body}, handle)
