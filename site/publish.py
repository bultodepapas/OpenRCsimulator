"""Publish only website assets to the isolated gh-pages branch. Requires Git and gh."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys
import tempfile

SITE = Path(__file__).resolve().parent
REPOSITORY = "bultodepapas/OpenRCsimulator"
REMOTE = f"https://github.com/{REPOSITORY}.git"
FILES = ("index.html", "en.html", "pt.html", "zh-Hans.html", "de.html", "ru.html", "sitemap.xml", "style.css", "details.css", "cinema.css", "content.js", "main.js", "details.js", "viewer.js", "cinema.js", "inspector.js", "favicon.svg", ".nojekyll")


def run(*args, cwd=None):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def publish(message):
    # Fail before touching GitHub if a translation or sitemap update was missed.
    run(sys.executable, str(SITE / "build_locales.py"), "--check")
    # Check authority and existing Pages configuration before writing to GitHub.
    info = json.loads(run("gh", "api", f"repos/{REPOSITORY}"))
    if not info["permissions"].get("admin"):
        raise RuntimeError("Repository admin permission is required to configure Pages.")
    existing = subprocess.run(["gh", "api", f"repos/{REPOSITORY}/pages"], text=True, capture_output=True)
    if existing.returncode and '"status":"404"' not in existing.stdout.replace(" ", ""):
        raise RuntimeError(existing.stderr)
    if not existing.returncode:
        configuration = json.loads(existing.stdout)
        if configuration.get("source") != {"branch": "gh-pages", "path": "/"}:
            raise RuntimeError("Pages already has a different publishing source; review it first.")
    branch_exists = bool(run("git", "ls-remote", "--heads", REMOTE, "gh-pages"))
    with tempfile.TemporaryDirectory(prefix="openrc-pages-") as directory:
        stage = Path(directory)
        if branch_exists:
            run("git", "clone", "--quiet", "--depth=1", "--branch=gh-pages", REMOTE, directory)
        else:
            run("git", "init", "--quiet", "--initial-branch=gh-pages", directory)
            run("git", "remote", "add", "origin", REMOTE, cwd=stage)
        for key in ("user.name", "user.email"):
            run("git", "config", key, run("git", "config", key, cwd=SITE), cwd=stage)
        for name in FILES:
            shutil.copy2(SITE / name, stage / name)
        assets_target = stage / "assets"
        expected_assets_target = stage.resolve() / "assets"
        if assets_target.resolve() != expected_assets_target or assets_target.is_symlink():
            raise RuntimeError("Refusing to replace gh-pages assets outside the staging checkout.")
        if assets_target.exists():
            if not assets_target.is_dir():
                raise RuntimeError("The gh-pages assets path is not a directory.")
            shutil.rmtree(assets_target)
        shutil.copytree(SITE / "assets", assets_target)
        run("git", "add", "--", *FILES, "assets", cwd=stage)
        if run("git", "status", "--porcelain", cwd=stage):
            run("git", "commit", "-m", message, cwd=stage)
            run("git", "push", "origin", "gh-pages", cwd=stage)
        commit = run("git", "rev-parse", "HEAD", cwd=stage)
    if existing.returncode:
        # Pushing a first gh-pages branch can enable Pages automatically.
        current = subprocess.run(["gh", "api", f"repos/{REPOSITORY}/pages"], text=True, capture_output=True)
        if current.returncode:
            run("gh", "api", "--method", "POST", f"repos/{REPOSITORY}/pages", "-f", "build_type=legacy", "-f", "source[branch]=gh-pages", "-f", "source[path]=/")
        elif json.loads(current.stdout).get("source") != {"branch": "gh-pages", "path": "/"}:
            raise RuntimeError("Pages was enabled with a different source; review it first.")
    print(json.dumps({"commit": commit, "url": f"https://bultodepapas.github.io/OpenRCsimulator/"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--message", required=True, help="Track step, change summary and completed verification.")
    publish(parser.parse_args().message)
