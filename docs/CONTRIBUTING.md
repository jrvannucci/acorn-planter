---
orphan: true
---

# Contributing to acorn

This guide is for people working on acorn **itself** — changing the `acorn`
commands, the installers, or the shell integration. For using acorn, see
[Using acorn](GUIDE.md) and the [command reference](COMMANDS.md); for
deploying it to other people, see the [deployment guide](DEPLOYMENT.md) and
[OFFLINE.md](OFFLINE.md).

---

## The edit → update loop

acorn installs from a private copy of its source at `~/acorn/system/src`
and never touches that copy except through `acorn update-commands` (see
[The update model](GUIDE.md#the-update-model)). That would normally make
iterating awkward — but installing from a **local checkout** wires the loop up
for you.

When you run the installer from inside a checkout of this repo, acorn records
that checkout directory as the `update_source` setting. `acorn update-commands`
then re-copies from your working tree, so the loop is:

1. Install once from your checkout:
   - **macOS/Linux:** `sh ./GET_STARTED/install.cmd`
   - **Windows:** `GET_STARTED\install.cmd`
2. Edit the source in your checkout (or `git pull`).
3. Run `acorn update-commands`. Your changes are copied into the install and
   `acorn-cli` is reinstalled from them — no re-running the installer.
4. Open a new terminal (or re-source the printed `acorn.sh`/`acorn.ps1`) to pick
   up any change to the `acorn` shell function itself.

`acorn update-commands` re-copies the whole tree **minus `.git` and `vendor/`**,
and overwrites `~/acorn/system/src` wholesale — so edit in your checkout, not
in the installed copy (edits there don't survive an update).

> An explicit `ACORN_REPO` (env, one run) or `ACORN_REPO_URL`
> (`global.conf`) still wins over the checkout directory if you'd rather
> updates come from a URL — see below.

---

## Tracking a branch: `--from-branch`

When `update_source` is a **git URL** (your fork, or a self-hosted host), update
from a specific branch or tag instead of the remote's default branch:

```
acorn update-commands --from-branch dev
```

This adds `--branch <name>` to the shallow clone, so it works for either a
branch or a tag — handy for tracking a `dev`/`staging` line or pinning a release.
It only applies to git-URL sources; with a directory/share `update_source` (or
none) it's ignored with a note, since a directory has no branches.

To point an install at a fork's URL in the first place, set it at install time
(`ACORN_REPO=https://github.com/you/acorn.git`) or afterward with
`acorn config set update_source <git-url>`.

---

## Source layout

```
README.md
GET_STARTED/                  user install/uninstall launchers
GET_STARTED_OFFLINE_BUNDLE/    administrator build launchers
acorn-planter/
  global.conf                 shared install settings
  offline-bundle.toml          superset and build settings
  installation-profile/       default and opt-in profiles
  installers/                 install, uninstall and bundle engines
  examples/                   editor and custom-command examples
  src/
    pyproject.toml            Python package definition
    acorn/
      __init__.py             version and public repository constants
      cli.py                  command dispatcher
      paths.py                user directory layout
      config.py               installed configuration
      profile.py              profile parsing
      bundle.py               bundle parsing and validation
      commands/               CLI implementations
      shell/                  PowerShell and POSIX templates
  vendor/                     staged native tools (generated)
  wheels/                     shared package downloads (generated)
  python-builds/              interpreter archives (generated)
  conda-channel/              conda artifacts (generated)
  MANIFEST.json               inventory and licensing (generated)
docs/                         Sphinx sources and diagram generators
tests/                        unit and integration tests
```

---

## Running the tests

`uvx pytest` from the repo root runs the whole suite — uv supplies pytest, and
`tests/conftest.py` puts `acorn-planter/src/` on the import path, so nothing needs installing
first. The suite is dominated by I/O-bound installer tests (real subprocess
installs, real file copies) rather than CPU work, so it parallelizes well:
`uvx --with pytest-xdist pytest -n auto` runs the same suite in a fraction of
the time (measured ~20x on a 6-core machine) — CI runs the equivalent
(`uvx --python <version> --with pytest-xdist pytest -q -n auto`, see
`.github/workflows/ci.yml`). Design guarantees the suite enforces:

- **Never touches your real `~/acorn`** — every test rebinds acorn's
  paths to a throwaway directory, and the machine-wide process killer is
  disabled for the whole run.
- **Fully offline** — installer runs use a stub `uv` that logs its
  invocations; the offline-index tests hand-craft a local wheel and prove
  both directions (a package in the wheels folder installs; one that
  isn't fails fast with the internet index disabled); downloads are
  exercised over `file://` URLs.
- Real `git`, `bash`, and `powershell` are used where present (git file
  protocol, installer end-to-end, shell-function behavior) and those
  tests skip cleanly on machines without them.

`uvx ruff check .` must also pass — it runs in CI, config is in `ruff.toml` at
the repo root (deliberately there, not in `acorn-planter/src/pyproject.toml`, so it covers
`tests/` and `acorn-planter/installers/` too).

---

## Releasing

The version lives in **one** place: `__version__` in
`acorn-planter/src/acorn/__init__.py`. `acorn-planter/src/pyproject.toml` reads it from there
(`dynamic = ["version"]`), so the built distribution, `acorn --version`, and the
`acorn help` footer can never disagree. A test enforces that pyproject stays
dynamic — don't add a literal `version =` back.

Keep [`CHANGELOG.md`](https://github.com/jrvannucci/acorn-planter/blob/main/CHANGELOG.md)
current as you go: add a line under
`## [Unreleased]` in the same commit as the change, while you still remember
why it mattered. Write for someone deploying acorn, not for someone reading
the diff.

To cut a release:

1. Bump `__version__` in `acorn-planter/src/acorn/__init__.py`.
2. Rename `## [Unreleased]` to the new version with today's date, and open a
   fresh empty `## [Unreleased]` above it.
3. Commit, then tag: `git tag -a v0.2.0 -m "v0.2.0"`.

This matters more than it looks. `acorn update-commands` pulls from a share or a
git URL, so an install can sit at a different version than the source it was
built from — the changelog is how a user finds out what an update changed.

---

## License

acorn is [Apache-2.0](https://github.com/jrvannucci/acorn-planter/blob/main/LICENSE).
Contributions are accepted under the same license (inbound = outbound, per
Apache-2.0 section 5) — by opening a pull request you agree your contribution
is licensed under Apache-2.0. Please don't add third-party runtime
dependencies: acorn deliberately ships on the standard library alone, which
is what keeps its licensing and its "nothing pre-installed" promise simple
(see [THIRD-PARTY-NOTICES](https://github.com/jrvannucci/acorn-planter/blob/main/THIRD-PARTY-NOTICES.md)).
