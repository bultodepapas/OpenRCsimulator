"""Check new and newly broken local links in the audited CI documentation paths.

The comparison and targets come from Git objects, not the working tree. The
selection receipt is independently checked against the GitHub event and Git.
"""
from __future__ import annotations

import argparse
from collections import Counter
from functools import lru_cache
from html import unescape
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import posixpath
import re
import subprocess
import sys
import unicodedata
from urllib.parse import unquote, urlsplit

import policy


def _blank(value: str) -> str:
    return "".join("\n" if c == "\n" else " " for c in value)


def _without_blocks(text: str, *, inline_html_code: bool = False) -> str:
    """Mask comments, fenced/indented blocks and HTML blocks, preserving lines."""
    text = re.sub(r"<!--(?:.*?-->|.*\Z)", lambda m: _blank(m.group()), text, flags=re.S)
    elements = "pre|script|style|code" if inline_html_code else "pre|script|style"
    text = re.sub(r"<(" + elements + r")\b[^>]*>.*?</\1\s*>",
                  lambda m: _blank(m.group()), text, flags=re.I | re.S)
    lines, fence, indented, list_active, blank = [], None, False, False, True
    for line in text.splitlines(keepends=True):
        quote = re.match(r"^ {0,3}(?:> ?)+", line)
        content = line[quote.end():] if quote else line
        if fence:
            if fence[3] and not quote and line.strip():
                fence = None
            else:
                lines.append(_blank(line))
                if re.match(r"^ {0," + str(fence[2]) + "}" + re.escape(fence[0]) +
                            "{" + str(fence[1]) + r",}[ \t]*\r?\n?$", content):
                    fence = None
                blank = not line.strip()
                continue
        if indented:
            if not line.strip() or re.match(r"^(?: {4}|\t)", content):
                lines.append(_blank(line))
                blank = not line.strip()
                continue
            indented = False
        item = re.match(r"^ {0,3}(?:[-+*]|[0-9]{1,9}[.)])[ \t]+", content)
        if item:
            list_active = True
        elif line.strip() and not re.match(r"^\s", content):
            list_active = False
        candidate = content[item.end():] if item else content
        max_indent = 8 if list_active else 3
        opening = re.match(r"^ {0," + str(max_indent) + r"}(`{3,}|~{3,})", candidate)
        if opening:
            fence = (opening[1][0], len(opening[1]), max_indent, bool(quote))
            lines.append(_blank(line))
        elif not list_active and blank and re.match(r"^(?: {4}|\t)", content):
            indented = True
            lines.append(_blank(line))
        else:
            lines.append(line)
        blank = not line.strip()
    return "".join(lines)


def _without_code(text: str) -> str:
    """Also mask inline backtick spans, leaving non-code Markdown intact."""
    text = _without_blocks(text, inline_html_code=True)
    # Inline backtick runs close only with a run of exactly the same length.
    chars = list(text)
    i = 0
    while i < len(text):
        if text[i] != "`" or _escaped(text, i):
            i += 1
            continue
        end = i
        while end < len(text) and text[end] == "`":
            end += 1
        ticks = end - i
        close = re.search(r"(?<!`)`{" + str(ticks) + r"}(?!`)", text[end:])
        if close:
            stop = end + close.end()
            chars[i:stop] = _blank(text[i:stop])
            i = stop
        else:
            i = end
    return "".join(chars)


def _escaped(text: str, index: int) -> bool:
    start = index
    while start and text[start - 1] == "\\":
        start -= 1
    return (index - start) % 2 == 1


def _unescape_markdown(value: str) -> str:
    return unescape(re.sub(r"\\([!\"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~])", r"\1", value))


def _label(value: str) -> str:
    return " ".join(_unescape_markdown(value).split()).casefold()


def _bracket_end(text: str, start: int) -> int | None:
    depth = 1
    for i in range(start + 1, len(text)):
        if _escaped(text, i):
            continue
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if not depth:
                return i
    return None


def _inline_destination(text: str, start: int) -> tuple[str, int] | None:
    """Parse the destination and optional title after an opening parenthesis."""
    i = start + 1
    while i < len(text) and text[i].isspace():
        i += 1
    if i < len(text) and text[i] == "<":
        begin = i + 1
        i = begin
        while i < len(text) and (text[i] != ">" or _escaped(text, i)) and text[i] != "\n":
            i += 1
        if i == len(text) or text[i] != ">":
            return None
        destination = text[begin:i]
        i += 1
    else:
        begin, depth = i, 0
        while i < len(text):
            if text[i] == "\\" and i + 1 < len(text):
                i += 2
                continue
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                if not depth:
                    return text[begin:i], i + 1
                depth -= 1
            elif text[i].isspace():
                break
            i += 1
        destination = text[begin:i]
    while i < len(text) and text[i].isspace():
        i += 1
    if i < len(text) and text[i] in "\"'":
        quote = text[i]
        i += 1
        while i < len(text) and (text[i] != quote or _escaped(text, i)):
            i += 1
        i += 1
        while i < len(text) and text[i].isspace():
            i += 1
    if i < len(text) and text[i] == ")":
        return destination, i + 1
    return None


class _HtmlLinks(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links: list[tuple[str, int]] = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in {"href", "src"} and value is not None:
                self.links.append((value, self.getpos()[0]))

    handle_startendtag = handle_starttag


def links(text: str) -> list[tuple[str, int]]:
    """Extract Markdown inline/reference/image and HTML href/src destinations."""
    text = _without_code(text)
    definitions: dict[str, str] = {}
    definition = re.compile(r"(?m)^ {0,3}\[((?:\\.|[^]\\\n])+)\]:[ \t]*(?:\r?\n[ \t]+)?"
                            r"(?:<((?:\\.|[^>\\\n])*)>|((?:\\.|[^\s])+))")

    def remember(match):
        definitions.setdefault(_label(match[1]), _unescape_markdown(match[2] if match[2] is not None else match[3]))
        return _blank(match.group())

    text = definition.sub(remember, text)
    found: list[tuple[str, int]] = []

    def scan(segment: str, line_offset: int = 0) -> None:
        i = 0
        while i < len(segment):
            if segment[i] != "[" or _escaped(segment, i):
                i += 1
                continue
            end = _bracket_end(segment, i)
            if end is None:
                i += 1
                continue
            label, after, dest = segment[i + 1:end], end + 1, None
            if after < len(segment) and segment[after] == "(":
                parsed = _inline_destination(segment, after)
                if parsed:
                    dest, after = parsed
                    dest = _unescape_markdown(dest)
            elif after < len(segment) and segment[after] == "[":
                ref_end = _bracket_end(segment, after)
                if ref_end is not None:
                    ref = segment[after + 1:ref_end] or label
                    dest = definitions.get(_label(ref))
                    after = ref_end + 1
            else:
                dest = definitions.get(_label(label))
            if dest is None:
                i += 1
                continue
            line = line_offset + segment.count("\n", 0, i) + 1
            found.append((dest, line))
            scan(label, line - 1)
            i = after

    scan(text)
    parser = _HtmlLinks()
    parser.feed(text)
    found.extend(parser.links)
    return found


def _slug(value: str) -> str:
    value = re.sub(r"!?\[([^]]*)\]\([^)]*\)", r"\1", value)
    value = re.sub(r"!?\[([^]]*)\]\[[^]]*\]", r"\1", value)
    value = re.sub(r"<[^>]*>", "", value)
    value = _unescape_markdown(value).strip().lower()
    return "".join("-" if c == " " else c for c in value
                   if c in "_- " or unicodedata.category(c)[0] not in {"P", "S", "C"})


class _HtmlAnchors(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.anchors: set[str] = set()

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if value and (name == "id" or (tag == "a" and name == "name")):
                self.anchors.add(value)

    handle_startendtag = handle_starttag


def anchors(text: str) -> set[str]:
    """Collect GitHub-style Markdown headings, duplicates and explicit HTML IDs."""
    # Keep inline code contents in headings; mask fenced blocks separately.
    text = _without_blocks(text)
    parser = _HtmlAnchors()
    parser.feed(_without_code(text))
    found = parser.anchors
    seen: dict[str, int] = {}
    lines = text.splitlines()
    for i, line in enumerate(lines):
        heading = re.match(r"^ {0,3}#{1,6}(?:[ \t]+|$)(.*)$", line)
        if heading:
            value = re.sub(r"[ \t]+#+[ \t]*$", "", heading[1])
        elif (line.strip() and i + 1 < len(lines) and
              re.fullmatch(r" {0,3}(?:=+|-+)[ \t]*", lines[i + 1])):
            value = line.strip()
        else:
            continue
        original = slug = _slug(value)
        while slug in seen:
            seen[original] += 1
            slug = f"{original}-{seen[original]}"
        seen[slug] = 0
        found.add(slug)
    return found


class GitObjects:
    def __init__(self, root: Path):
        self.root = root

    @lru_cache(maxsize=512)
    def kind(self, revision: str, path: str) -> str | None:
        obj = f"{revision}:{path}" if path != "." else f"{revision}^{{tree}}"
        result = subprocess.run(["git", "-C", str(self.root), "cat-file", "-t", obj],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            return None
        return result.stdout.decode("ascii").strip()

    @lru_cache(maxsize=256)
    def text(self, revision: str, path: str) -> str:
        data = subprocess.run(["git", "-C", str(self.root), "show", f"{revision}:{path}"],
                              check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
        return data.decode("utf-8")


def _local_target(source: str, destination: str) -> tuple[str, str] | None:
    try:
        url = urlsplit(destination)
        if url.scheme or url.netloc or destination.startswith("//"):
            return None
        if re.search(r"%(?![0-9a-fA-F]{2})", url.path + url.fragment):
            raise ValueError("invalid percent escape")
        path = unquote(url.path, encoding="utf-8", errors="strict")
        fragment = unquote(url.fragment, encoding="utf-8", errors="strict")
    except (UnicodeDecodeError, ValueError) as error:
        raise ValueError(f"invalid URL: {error}") from error
    if path.startswith("/") or "\\" in path or "\0" in path or "\0" in fragment:
        raise ValueError("absolute or invalid local path")
    target = posixpath.normpath(posixpath.join(posixpath.dirname(source), path)) if path else source
    if target == ".." or target.startswith("../"):
        raise ValueError("local path escapes the repository")
    return target, fragment


def check_target(objects: GitObjects, revision: str, source: str, destination: str) -> str | None:
    try:
        parsed = _local_target(source, destination)
    except ValueError as error:
        return str(error)
    if parsed is None:
        return None
    target, fragment = parsed
    kind = objects.kind(revision, target)
    if kind is None:
        return f"missing target {target}"
    if not fragment:
        return None
    if kind == "tree":
        target = posixpath.join(target, "README.md")
        if objects.kind(revision, target) != "blob":
            return f"cannot check anchor in directory without {target}"
    elif kind != "blob":
        return f"cannot check anchor in {target}"
    line = re.fullmatch(r"L([1-9][0-9]*)(?:-L([1-9][0-9]*))?", fragment)
    if line:
        contents = objects.text(revision, target)
        first, last = int(line[1]), int(line[2] or line[1])
        if first <= last <= len(contents.splitlines()):
            return None
        return f"missing line anchor #{fragment} in {target}"
    if Path(target).suffix.lower() not in {".md", ".markdown", ".html", ".htm"}:
        return f"cannot check anchor #{fragment} in {target}"
    if fragment not in anchors(objects.text(revision, target)):
        return f"missing anchor #{fragment} in {target}"
    return None


def check(root: Path, receipt: dict, sha: str, event: str, ref: str, payload: dict,
          fetch: bool = False) -> int:
    policy.validate(receipt, root, sha, event, ref, payload, fetch=fetch)
    if not receipt["base"] or not receipt["paths"]:
        print(f"Document link comparison unavailable ({receipt['reason']}); full scope retained.")
        return 0
    objects = GitObjects(root)
    errors, checked = [], 0
    changed = set(receipt["paths"])
    # Include inbound links from the other audited guides when their targets
    # changed. This is deliberately not a whole-repository inbound-link scan.
    for source in sorted(policy.SAFE_DOCS):
        if objects.kind(sha, source) != "blob":
            continue  # A deletion or non-regular change already forces full scope.
        previous = (objects.text(receipt["base"], source)
                    if objects.kind(receipt["base"], source) == "blob" else "")
        old = Counter(dest for dest, _ in links(previous))
        for destination, line in links(objects.text(sha, source)):
            inherited = old[destination] > 0
            if inherited:
                old[destination] -= 1
            try:
                parsed = _local_target(source, destination)
            except ValueError:
                if inherited:
                    continue
                parsed = ()  # The normal target check reports the malformed URL.
            if parsed is None:
                continue  # External destinations are outside this check.
            if inherited:
                target = parsed[0]
                affected = any(p == target or target == "." or p.startswith(target + "/") for p in changed)
                if not affected or check_target(objects, receipt["base"], source, destination):
                    continue
            checked += 1
            error = check_target(objects, sha, source, destination)
            if error:
                errors.append(f"{source}:{line}: {destination!r}: {error}")
    if errors:
        raise ValueError("\n" + "\n".join(errors))
    print(f"Checked {checked} new or potentially affected local document link(s).")
    return checked


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    sha, event, ref = (os.environ[k] for k in ("GITHUB_SHA", "GITHUB_EVENT_NAME", "GITHUB_REF"))
    payload = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
    check(args.root, json.loads(args.receipt.read_text(encoding="utf-8")),
          sha, event, ref, payload, fetch=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Document check refused: {error}", file=sys.stderr)
        sys.exit(1)
