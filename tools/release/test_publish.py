"""Same-run publication and retry tests; GitHub CLI is entirely simulated."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

if __package__:
    from . import manifest, publish
else:
    import manifest
    import publish

TAG = "v1.2.3-rc.2"
REPO = "owner/project"
REAL_RUN = publish.run
REAL_MKDTEMP = tempfile.mkdtemp


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc publish ")
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.root = base / "source"
        self.root.mkdir()
        self.directory = base / "transfer"
        self.directory.mkdir()
        self.remote_assets = base / "remote-assets"
        self.remote_assets.mkdir()
        self.git("init", "--quiet")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Release fixture")
        self.git("config", "core.autocrlf", "false")
        self.notes = self.root / "docs/releases" / f"{TAG}.md"
        self.notes.parent.mkdir(parents=True)
        self.notes.write_bytes(b"Release notes\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "fixture")
        self.git("tag", "-a", TAG, "-m", "annotated fixture")
        self.commit = self.git("rev-parse", "HEAD")
        subprocess.run(["git", "clone", "--quiet", "--bare", str(self.root), str(base / "origin.git")],
                       check=True, capture_output=True)
        self.git("remote", "add", "origin", str(base / "origin.git"))
        self.names = manifest.artifact_names(TAG) + [manifest.MANIFEST, manifest.ABI_REPORT, manifest.CHECKSUMS]
        self.make_transfer()
        for name in self.names:
            shutil.copyfile(self.directory / name, self.remote_assets / name)
        self.release = self.make_release()
        self.commands = []
        self.api_calls = 0
        self.return_no_release = False
        self.change_download = False
        self.origin_url = f"https://github.com/{REPO}.git"
        self.api_error = False
        self.env = mock.patch.dict(os.environ, {"GH_TOKEN": "fixture-token", "GIT_CONFIG_NOSYSTEM": "1",
                                                "GIT_CONFIG_GLOBAL": os.devnull})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.abi = mock.patch.object(manifest, "validate_abi", side_effect=self.validate_abi)
        self.abi.start()
        self.addCleanup(self.abi.stop)
        self.cli = mock.patch.object(publish, "run", side_effect=self.run_command)
        self.cli.start()
        self.addCleanup(self.cli.stop)
        self.staging = mock.patch.object(publish.tempfile, "mkdtemp",
                                         side_effect=lambda **kwargs: REAL_MKDTEMP(dir=base, **kwargs))
        self.staging.start()
        self.addCleanup(self.staging.stop)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.PIPE).decode().strip()

    @staticmethod
    def validate_abi(report, linux):
        manifest.require(report["archive"] == {"path": linux["filename"], "sha256": linux["sha256"],
                                               "bytes": linux["bytes"]}, "ABI binding differs")

    def make_transfer(self):
        artifacts = []
        for name, (system, arch) in zip(self.names, manifest.TARGETS):
            (self.directory / name).write_bytes(("archive " + name).encode())
            artifacts.append({"filename": name, "platform": system, "architecture": arch,
                              "format": "zip", **manifest.file_info(self.directory / name)})
        report = {"archive": {"path": artifacts[0]["filename"], "sha256": artifacts[0]["sha256"],
                              "bytes": artifacts[0]["bytes"]}}
        (self.directory / manifest.ABI_REPORT).write_text(manifest.json_text(report), encoding="utf-8")
        reports = [{"filename": manifest.ABI_REPORT, **manifest.file_info(self.directory / manifest.ABI_REPORT)}]
        input_names = set(manifest.SOURCE_INPUTS) | {"template/" + name for name in manifest.TEMPLATES} | {
            "template/macos-derived.zip", "template/macos-derived.receipt.json", "editor", "tool/zip", "tool/readelf"}
        ci = {key: None for key in manifest.CI_KEYS}
        ci.update(GITHUB_RUN_ID="123", GITHUB_REPOSITORY=REPO)
        data = {"format": manifest.FORMAT,
                "source": {"version": TAG, "commit": self.commit, "tree": self.git("rev-parse", "HEAD^{tree}"),
                           "commit_date": "2026-10-31T12:00:00Z", "application_version": "1.2.3", "dirty": False,
                           "tag": TAG, "channel": "preview", "worktree_sha256": "0" * 64},
                "build": {"host": "fixture", "python": "fixture", "ci": ci}, "engine_version": "fixture",
                "inputs": {name: {"sha256": "0" * 64, "bytes": 1} for name in input_names},
                "artifacts": artifacts, "reports": reports,
                "qualification": {"status": "not_platform_qualified", "pending": manifest.PENDING}}
        (self.directory / manifest.MANIFEST).write_text(manifest.json_text(data), encoding="utf-8", newline="\n")
        records = artifacts + reports + [{"filename": manifest.MANIFEST,
                                         **manifest.file_info(self.directory / manifest.MANIFEST)}]
        (self.directory / manifest.CHECKSUMS).write_text(
            "".join(f'{row["sha256"]}  {row["filename"]}\n' for row in records), encoding="ascii", newline="\n")

    def make_release(self):
        return {"id": 42, "tag_name": TAG, "name": f"OpenRC Simulator {TAG}", "body": "Release notes\n",
                "draft": False, "prerelease": True, "published_at": "2026-10-31T12:00:00Z",
                "assets": [{"name": name, "state": "uploaded"} for name in self.names]}

    def run_command(self, command, *, root, timeout=1800):
        self.commands.append(command)
        if command[0] == "git":
            if command[1:] == ["remote", "get-url", "origin"]:
                return (self.origin_url + "\n").encode()
            # The only fetch is from the fixture's local bare repository; a new
            # command or remote must never escape this test onto the network.
            allowed = (["rev-parse", "HEAD^{commit}"], ["rev-parse", "FETCH_HEAD^{commit}"],
                       ["fetch", "--no-tags", "origin", f"refs/tags/{TAG}"],
                       ["show", f"{self.commit}:docs/releases/{TAG}.md"])
            if command[1:] not in allowed:
                raise AssertionError(f"unexpected git command: {command}")
            return REAL_RUN(command, root=root, timeout=timeout)
        if command[1] == "api":
            self.api_calls += 1
            if self.api_error:
                raise ValueError("simulated GitHub listing failure")
            item = None if self.return_no_release and self.api_calls == 1 else self.release
            # Exercise the page traversal rather than assuming a single page.
            return json.dumps([[], [item] if item is not None else []]).encode()
        if command[1:3] == ["release", "download"]:
            target = Path(command[command.index("--dir") + 1])
            for name in self.names:
                source = self.remote_assets / name
                if source.exists():
                    shutil.copyfile(source, target / name)
            if self.change_download:
                (target / self.names[0]).write_bytes(b"tampered")
            return b""
        if command[1:3] == ["release", "create"]:
            return b"created by mocked CLI"
        raise AssertionError(f"unexpected mocked command: {command}")

    def invoke(self, **changes):
        args = dict(root=self.root, directory=self.directory, notes=self.notes, commit=self.commit,
                    tag=TAG, run_id="123", repository=REPO)
        args.update(changes)
        return publish.publish(**args)

    def test_identical_retry_downloads_and_verifies_without_mutation(self):
        self.assertIn("no mutation", self.invoke())
        gh_commands = [command[1:3] for command in self.commands if command[0] == "gh"]
        self.assertEqual(gh_commands, [["api", "--paginate"], ["release", "download"], ["api", "--paginate"]])
        self.assertEqual(self.api_calls, 2)

    def test_create_uses_verified_tag_and_downloads_the_published_set(self):
        self.return_no_release = True
        self.assertEqual(self.invoke(), "created and verified")
        creates = [command for command in self.commands if command[1:3] == ["release", "create"]]
        self.assertEqual(len(creates), 1)
        self.assertIn("--verify-tag", creates[0])
        self.assertIn("--prerelease", creates[0])
        self.assertNotIn("--clobber", creates[0])
        self.assertNotIn("fixture-token", " ".join(creates[0]))
        self.assertTrue(any(command[1:3] == ["release", "download"] for command in self.commands))

    def test_partial_draft_and_wrong_metadata_stop_without_create(self):
        mutations = [lambda r: r.update(draft=True, published_at=None), lambda r: r.update(body="changed"),
                     lambda r: r.update(prerelease=False), lambda r: r.update(name="wrong title"),
                     lambda r: r["assets"].pop(), lambda r: r["assets"].append({"name": "extra", "state": "uploaded"}),
                     lambda r: r["assets"][0].update(state="new")]
        for mutation in mutations:
            self.release = self.make_release()
            mutation(self.release)
            with self.subTest(release=self.release), self.assertRaises(ValueError):
                self.invoke()
            self.assertFalse(any(command[1:3] == ["release", "create"] for command in self.commands))

    def test_changed_published_bytes_or_missing_download_fail(self):
        for missing in (False, True):
            if missing:
                (self.remote_assets / self.names[0]).unlink()
            else:
                (self.remote_assets / self.names[0]).write_bytes(b"different")
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, "download verification failed"):
                self.invoke()
            self.assertFalse(any(command[1:3] == ["release", "create"] for command in self.commands))

    def test_independent_identity_and_local_inventory_rejections(self):
        for changes in ({"commit": "0" * 40}, {"tag": "v1.2.4-rc.2"},
                        {"run_id": "456"}, {"repository": "other/project"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.invoke(**changes)
        (self.directory / "extra").write_text("unexpected")
        with self.assertRaisesRegex(ValueError, "inventory"):
            self.invoke()
        self.assertFalse(any(command[1:3] == ["release", "create"] for command in self.commands))

    def test_notes_and_remote_peeled_tag_movement_rejected(self):
        self.notes.write_bytes(b"local changed notes\n")
        with self.assertRaisesRegex(ValueError, "notes differ"):
            self.invoke()
        self.notes.write_bytes(b"Release notes\n")
        (self.root / "other").write_text("new commit")
        self.git("add", "other")
        self.git("commit", "--quiet", "-m", "moved")
        self.git("tag", "-f", TAG)
        self.git("push", "--force", "origin", f"refs/tags/{TAG}")
        self.git("checkout", "--quiet", "--detach", self.commit)
        with self.assertRaisesRegex(ValueError, "remote release tag moved"):
            self.invoke()
        self.assertFalse(any(command[1:3] == ["release", "create"] for command in self.commands))

    def test_other_origin_rejected_before_publication(self):
        self.origin_url = "https://github.com/other/project.git"
        with self.assertRaisesRegex(ValueError, "origin does not identify"):
            self.invoke()
        self.assertFalse(any(command[1:3] == ["release", "create"] for command in self.commands))

    def test_listing_failure_stops_without_further_github_action(self):
        self.api_error = True
        with self.assertRaisesRegex(ValueError, "listing failure"):
            self.invoke()
        gh_commands = [command[1:3] for command in self.commands if command[0] == "gh"]
        self.assertEqual(gh_commands, [["api", "--paginate"]])

    def test_bad_local_files_fail_before_network_access(self):
        (self.directory / self.names[0]).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "mismatch"):
            self.invoke()
        self.assertFalse(any(command[0] == "gh" or command[1:2] == ["fetch"] for command in self.commands))

    def test_stable_channel_requires_published_non_prerelease(self):
        stable = self.make_release()
        stable_tag = "v1.2.3"
        stable.update(tag_name=stable_tag, name=f"OpenRC Simulator {stable_tag}", prerelease=False)
        publish.check_metadata(stable, stable_tag, "Release notes\n", self.names)
        stable["prerelease"] = True
        with self.assertRaisesRegex(ValueError, "channel differs"):
            publish.check_metadata(stable, stable_tag, "Release notes\n", self.names)


if __name__ == "__main__":
    unittest.main()
