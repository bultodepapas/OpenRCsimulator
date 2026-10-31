#!/usr/bin/env python3
"""Publish a verified same-run release, or verify an identical completed retry."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

if __package__:
    from . import manifest
else:
    import manifest


def run(command, *, root, timeout=1800):
    # Credentials remain in the environment. Suppress GH_DEBUG to avoid logging them.
    env = os.environ.copy()
    env.pop("GH_DEBUG", None)
    result = subprocess.run(command, cwd=root, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout, check=False)
    if result.returncode:
        raise ValueError(f"{' '.join(command[:2])} command failed (exit {result.returncode})")
    return result.stdout


def check_tag(root, tag, commit, repository):
    origin = run(["git", "remote", "get-url", "origin"], root=root).decode("utf-8").strip()
    accepted = (f"https://github.com/{repository}", f"https://github.com/{repository}.git",
                f"git@github.com:{repository}", f"git@github.com:{repository}.git",
                f"ssh://git@github.com/{repository}", f"ssh://git@github.com/{repository}.git")
    manifest.require(origin.casefold() in {value.casefold() for value in accepted},
                     "origin does not identify the expected repository")
    run(["git", "fetch", "--no-tags", "origin", f"refs/tags/{tag}"], root=root)
    actual = run(["git", "rev-parse", "FETCH_HEAD^{commit}"], root=root).decode("ascii").strip()
    manifest.require(actual == commit, "remote release tag moved or does not identify the commit")


def check_notes(root, notes, tag, commit):
    manifest.require(notes.is_file() and not notes.is_symlink() and notes.stat().st_size > 0,
                     "missing or invalid release notes")
    expected = run(["git", "show", f"{commit}:docs/releases/{tag}.md"], root=root)
    actual = notes.read_bytes()
    manifest.require(actual == expected and bool(actual), "release notes differ from the tagged source")
    return actual.decode("utf-8")


def list_matching(root, repository, tag):
    # The by-tag endpoint returns published releases only. Listing every page with
    # contents:write also detects an incomplete draft left by a failed upload.
    raw = run(["gh", "api", "--paginate", "--slurp", f"repos/{repository}/releases?per_page=100"], root=root)
    pages = json.loads(raw, object_pairs_hook=manifest.unique_object)
    manifest.require(isinstance(pages, list) and pages and all(isinstance(page, list) for page in pages),
                     "invalid release listing")
    matches = []
    for page in pages:
        for release in page:
            manifest.require(isinstance(release, dict) and isinstance(release.get("tag_name"), str),
                             "invalid release listing entry")
            if release["tag_name"] == tag:
                matches.append(release)
    manifest.require(len(matches) <= 1, "multiple releases match this tag")
    return matches[0] if matches else None


def check_metadata(release, tag, notes, names):
    manifest.require(isinstance(release, dict), "release is missing")
    manifest.require(release.get("tag_name") == tag and release.get("name") == f"OpenRC Simulator {tag}",
                     "release tag/title differs")
    manifest.require(release.get("body") == notes, "release notes differ")
    manifest.require(release.get("draft") is False and isinstance(release.get("published_at"), str)
                     and bool(release["published_at"]), "release is not published")
    manifest.require(release.get("prerelease") is ("-" in tag), "release prerelease/channel differs")
    assets = release.get("assets")
    manifest.require(isinstance(assets, list) and len(assets) == len(names), "release asset count differs")
    manifest.require(all(isinstance(asset, dict) and asset.get("state") == "uploaded"
                         and isinstance(asset.get("name"), str) for asset in assets),
                     "release has invalid or incomplete assets")
    asset_names = [asset["name"] for asset in assets]
    manifest.require(len(set(asset_names)) == len(names) and set(asset_names) == set(names),
                     "release asset names differ")


def verify_download(root, directory, tag, commit, run_id, repository, names):
    staged = Path(tempfile.mkdtemp(prefix="openrc-published-check-"))
    try:
        run(["gh", "release", "download", tag, "--repo", repository, "--dir", str(staged)], root=root)
        manifest.verify(staged, expected_commit=commit, expected_tag=tag,
                        expected_run_id=run_id, expected_repository=repository)
        for name in names:
            manifest.require(manifest.file_info(staged / name) == manifest.file_info(directory / name),
                             f"published asset differs from this run: {name}")
    except Exception as error:
        raise ValueError(f"published download verification failed; retained at {staged}: {error}") from error
    for name in names:
        (staged / name).unlink()
    staged.rmdir()


def publish(root, directory, notes, commit, tag, run_id, repository):
    root, directory, notes = Path(root).resolve(), Path(directory).resolve(), Path(notes)
    manifest.require(not any(char in str(directory) for char in "#*?["),
                     "release directory contains GitHub CLI asset-pattern characters")
    if not notes.is_absolute():
        notes = root / notes
    manifest.require(re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", commit) is not None,
                     "invalid expected commit")
    manifest.require(manifest.TAG.fullmatch(tag) is not None, "invalid expected tag")
    manifest.require(re.fullmatch(r"[1-9][0-9]*", run_id) is not None, "invalid expected run ID")
    manifest.require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) is not None,
                     "invalid expected repository")
    manifest.require(bool(os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")),
                     "GitHub token must be supplied through the environment")
    head = run(["git", "rev-parse", "HEAD^{commit}"], root=root).decode("ascii").strip()
    manifest.require(head == commit, "publication checkout differs from expected commit")
    manifest.verify(directory, expected_commit=commit, expected_tag=tag,
                    expected_run_id=run_id, expected_repository=repository)
    names = manifest.artifact_names(tag) + [manifest.MANIFEST, manifest.ABI_REPORT, manifest.CHECKSUMS]
    body = check_notes(root, notes, tag, commit)
    check_tag(root, tag, commit, repository)
    release = list_matching(root, repository, tag)
    created = False
    if release is None:
        # Recheck all local/remote inputs immediately before the only mutation.
        check_tag(root, tag, commit, repository)
        manifest.verify(directory, expected_commit=commit, expected_tag=tag,
                        expected_run_id=run_id, expected_repository=repository)
        manifest.require(check_notes(root, notes, tag, commit) == body, "release notes changed")
        command = ["gh", "release", "create", tag, *[str(directory / name) for name in names],
                   "--repo", repository, "--verify-tag", "--title", f"OpenRC Simulator {tag}",
                   "--notes-file", str(notes), "--prerelease" if "-" in tag else "--latest"]
        run(command, root=root)
        created = True
        release = list_matching(root, repository, tag)
    check_metadata(release, tag, body, names)
    verify_download(root, directory, tag, commit, run_id, repository, names)
    # Detect metadata or tag movement during the download as well.
    again = list_matching(root, repository, tag)
    check_metadata(again, tag, body, names)
    manifest.require(again.get("id") == release.get("id") and again.get("id") is not None,
                     "release identity changed during verification")
    check_tag(root, tag, commit, repository)
    return "created and verified" if created else "identical completed release verified; no mutation"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--expected-tag", required=True)
    parser.add_argument("--expected-run-id", required=True)
    parser.add_argument("--expected-repository", required=True)
    args = parser.parse_args()
    try:
        result = publish(args.root, args.directory, args.notes, args.expected_commit,
                         args.expected_tag, args.expected_run_id, args.expected_repository)
        print("Release publication: " + result)
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Release publication failed: {error}\n")


if __name__ == "__main__":
    main()
