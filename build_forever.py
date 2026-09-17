"""Build the WoW: Forever packages of the WordHunter addons, and install them.

    python build_forever.py                  # zips into packages/
    python build_forever.py --out .          # and the six addon folders, here
    python build_forever.py --install        # and copy into the beta client
    python build_forever.py --only WordHunterWoW,WordHunterWoW-ENPanel

This file lives in the WordHunter-Learning-Forever repository, which must sit
beside the six addon repositories it builds from: the workspace is taken to be
this file's parent directory, the same rule the release tools follow.

World of Warcraft: Forever (product wow_classic_beta, client 1.60.x, Blizzard's
codename Camelot) is a third game beside Retail and Classic Era. Its addon loader
looks for <Addon>_Camelot.toc and expects "## Interface: 16001" -- the number is
1.60.1 written the way every manifest writes it, and it is what DBM ships in its
own _Camelot manifests. The API is the Classic Era surface, so every package here
is the Classic Era variant of the addon with a different manifest.

Nothing in the repositories is changed. Each package is what CurseForge would
build from the tagged commit -- the tracked files minus what .pkgmeta ignores --
with the Retail and Era manifests taken out, any Lua the Era manifest never loads
taken out (ENPanel's Retail quest data), and two manifests put in: the Camelot
one, and a plain <Addon>.toc with the same content, which is the loader's
fallback should it not know the suffix.
"""

import argparse
import hashlib
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORKSPACE = HERE.parent
PACKAGES = HERE / "packages"

INTERFACE = "16001"
SUFFIX = "Camelot"
FLAVOR = "Forever"
CLIENT = Path(r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns")

ADDONS = [
    "WordHunterWoW",
    "WordHunterWoW-ENPanel",
    "WordHunterWoW-Dictionary-DE",
    "WordHunterWoW-Voice-DE",
    "WordHunterWoW-Voice-DE-Classic",
    "WordHunterWoW-Voice-DE-Words",
]

# Repository bookkeeping the client cannot read.
ALWAYS_DROP = {".gitignore", ".pkgmeta", ".gitattributes"}


def git(repo, *args):
    out = subprocess.run(["git", "-C", str(repo), *args], check=True,
                         capture_output=True)
    return out.stdout


def tracked_files(repo):
    raw = git(repo, "ls-files", "-z").decode("utf-8")
    return [p for p in raw.split("\0") if p]


def pkgmeta_ignores(repo):
    path = repo / ".pkgmeta"
    if not path.exists():
        return []
    ignores, in_list = [], False
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("ignore:"):
            in_list = True
            continue
        if in_list and stripped.startswith("-"):
            ignores.append(stripped[1:].strip().strip('"').rstrip("/"))
            continue
        in_list = False
    return ignores


def ignored(path, ignores):
    return any(path == ig or path.startswith(ig + "/") for ig in ignores)


def read_manifest(repo, addon):
    """The Classic Era manifest, as raw lines, plus the files it loads."""
    path = repo / ("%s_Vanilla.toc" % addon)
    raw = path.read_bytes()
    newline = b"\r\n" if b"\r\n" in raw else b"\n"
    lines = raw.split(newline)
    loads, version = [], None
    for line in lines:
        text = line.decode("utf-8-sig").strip()
        if not text:
            continue
        if text.startswith("#"):
            if text.startswith("## Version:"):
                version = text.split(":", 1)[1].strip()
            continue
        loads.append(text.replace("\\", "/"))
    if not version:
        raise SystemExit("%s: manifest has no ## Version" % addon)
    return lines, newline, loads, version


def camelot_manifest(lines, newline):
    out, replaced = [], False
    for line in lines:
        bare = line[3:] if line.startswith(b"\xef\xbb\xbf") else line
        if bare.strip().startswith(b"## Interface:"):
            prefix = line[:len(line) - len(bare)]
            out.append(prefix + b"## Interface: " + INTERFACE.encode())
            replaced = True
        else:
            out.append(line)
    if not replaced:
        raise SystemExit("manifest has no ## Interface line")
    return newline.join(out)


def stage(addon):
    repo = WORKSPACE / addon
    if not (repo / ".git").exists():
        raise SystemExit("%s is not a repository checkout" % repo)
    lines, newline, loads, version = read_manifest(repo, addon)
    ignores = pkgmeta_ignores(repo)
    loaded = set(loads)
    files = []
    for path in tracked_files(repo):
        name = path.rsplit("/", 1)[-1]
        if name in ALWAYS_DROP or ignored(path, ignores):
            continue
        if path.startswith(".") or "/." in path:
            # .github and its like: the repository's own machinery.
            continue
        if path.endswith(".toc"):
            continue
        if path.endswith(".lua") and path not in loaded:
            # A Lua file the manifest never loads is another game's data --
            # ENPanel's Retail quest text -- and shipping it only makes the
            # download bigger.
            continue
        files.append(path)
    present = set(files)
    missing = [p for p in loads if p not in present]
    if missing:
        raise SystemExit("%s: the manifest loads files that are not tracked: %s"
                         % (addon, ", ".join(missing)))
    manifest = camelot_manifest(lines, newline)
    return repo, files, manifest, version


def provenance(repo):
    describe = git(repo, "describe", "--tags", "--always", "--dirty").decode().strip()
    commit = git(repo, "rev-parse", "HEAD").decode().strip()
    return describe, commit


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_zip(addon, version, repo, files, manifest):
    PACKAGES.mkdir(parents=True, exist_ok=True)
    archive = PACKAGES / ("%s-%s-%s.zip" % (addon, version, FLAVOR))
    partial = archive.with_suffix(".zip.partial")
    if archive.exists():
        archive.unlink()
    expected = {}
    with zipfile.ZipFile(partial, "w", allowZip64=True) as z:
        for rel in files:
            src = repo / rel
            # Ogg does not compress; deflating 1.5 GB of it would cost minutes
            # and save nothing.
            method = zipfile.ZIP_STORED if rel.endswith(".ogg") else zipfile.ZIP_DEFLATED
            arc = "%s/%s" % (addon, rel)
            z.write(src, arc, compress_type=method)
            expected[arc] = src.stat().st_size
        for name in ("%s_%s.toc" % (addon, SUFFIX), "%s.toc" % addon):
            arc = "%s/%s" % (addon, name)
            z.writestr(arc, manifest, compress_type=zipfile.ZIP_DEFLATED)
            expected[arc] = len(manifest)
    # A listing cannot tell a truncated archive from a good one; reopening it
    # and reading every member can.
    with zipfile.ZipFile(partial) as z:
        bad = z.testzip()
        if bad is not None:
            raise SystemExit("%s: corrupt member %s" % (partial, bad))
        got = {i.filename: i.file_size for i in z.infolist()}
    if got != expected:
        raise SystemExit("%s: archive content differs from what went in" % partial)
    partial.rename(archive)
    return archive


def write_tree(addon, repo, files, manifest, root):
    """The addon as the client loads it, under root/<addon>. Used both for the
    client's own AddOns folder and for this repository's checkout, which is
    installable as it stands for the same reason the sound packs are."""
    target = root / addon
    if target.exists():
        shutil.rmtree(target)
    for rel in files:
        dst = target / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(repo / rel, dst)
    for name in ("%s_%s.toc" % (addon, SUFFIX), "%s.toc" % addon):
        (target / name).write_bytes(manifest)
    # Every staged file, and nothing else, at the same size.
    on_disk = {p.relative_to(target).as_posix(): p.stat().st_size
               for p in target.rglob("*") if p.is_file()}
    wanted = {rel: (repo / rel).stat().st_size for rel in files}
    wanted["%s_%s.toc" % (addon, SUFFIX)] = len(manifest)
    wanted["%s.toc" % addon] = len(manifest)
    if on_disk != wanted:
        extra = sorted(set(on_disk) - set(wanted))[:5]
        gone = sorted(set(wanted) - set(on_disk))[:5]
        raise SystemExit("%s: installed tree differs (extra %s, missing %s)"
                         % (addon, extra, gone))
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--install", action="store_true",
                        help="copy each package into the beta client's AddOns folder")
    parser.add_argument("--client", type=Path, default=CLIENT,
                        help="the AddOns folder to install into")
    parser.add_argument("--out", type=Path,
                        help="also write the six addon folders under this directory")
    parser.add_argument("--only", help="comma-separated addon folder names")
    parser.add_argument("--no-zip", action="store_true", help="no archives")
    args = parser.parse_args()

    chosen = ADDONS if not args.only else [a.strip() for a in args.only.split(",")]
    unknown = [a for a in chosen if a not in ADDONS]
    if unknown:
        raise SystemExit("not a WordHunter addon: %s" % ", ".join(unknown))
    if args.install:
        args.client.mkdir(parents=True, exist_ok=True)
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)

    report = ["WordHunter Learning for World of Warcraft: Forever (wow_classic_beta)",
              "manifest suffix _%s, ## Interface: %s" % (SUFFIX, INTERFACE),
              "built %s" % time.strftime("%Y-%m-%d %H:%M"), ""]
    for addon in chosen:
        started = time.time()
        repo, files, manifest, version = stage(addon)
        describe, commit = provenance(repo)
        total = sum((repo / f).stat().st_size for f in files)
        line = "%s %s  (%s, %s)  %d files, %.1f MB" % (
            addon, version, describe, commit[:10], len(files) + 2, total / 1048576)
        print(line)
        if not args.no_zip:
            archive = write_zip(addon, version, repo, files, manifest)
            line += "\n    %s  %.1f MB  sha256 %s" % (
                archive.name, archive.stat().st_size / 1048576, sha256(archive))
            print("    zip ok: %s" % archive.name)
        if args.out:
            print("    written: %s" % write_tree(addon, repo, files, manifest, args.out))
        if args.install:
            print("    installed: %s" % write_tree(addon, repo, files, manifest, args.client))
        print("    %.0f s" % (time.time() - started))
        report.append(line)
    if not args.no_zip and not args.only:
        # The record of what the archives were made from. Only a full build
        # writes it, so a partial rebuild cannot leave it describing one addon.
        (HERE / "BUILD-INFO.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
