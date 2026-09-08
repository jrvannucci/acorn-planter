# Deploying acorn in an organization

acorn was built so that one person can prepare a Python environment and
hand it to everyone else as a single command — including on networks with no
internet, no admin rights for users, and an auditor who wants to know exactly
what landed on each machine.

This page is the deployment track. It assumes you are setting acorn up
**for other people**. If you just want to use acorn yourself, read
[Using acorn](GUIDE.md) instead.

---

## Contents

- [The deployment workflow](#the-deployment-workflow)
- [Deployment configuration: `global.conf`](#deployment-configuration-globalconf)
- [Shared-machine (multi-user) installs](#shared-machine-multi-user-installs)
- [Choosing an editor](#choosing-an-editor)
- Defining the environment itself → **[PROFILES.md](PROFILES.md)**
- [Rolling out](#rolling-out)
- [Admin commands (shared-root teardown)](#admin-commands-shared-root-teardown)
- [What a security review will ask](#what-a-security-review-will-ask)
- Fully offline / air-gapped networks → **[OFFLINE.md](OFFLINE.md)**
- What you may redistribute → **[LICENSING.md](LICENSING.md)**

---

## The deployment workflow

You edit one copy of acorn and hand it out. Everyone who installs from it
inherits your settings — no flags, no environment variables, no instructions
to get wrong.

1. **Edit [`global.conf`](https://github.com/jrvannucci/acorn-planter/blob/main/acorn-planter/global.conf)**
   in the copy you distribute: where installs come from, where packages come
   from, which editor, which profiles.
2. **Put your profiles in `acorn-planter/installation-profile/`** — one marked
   `default = true` for everyone, others opt-in by name. See
   [deployment profiles](PROFILES.md).
3. **Distribute the copy** — a network share, an internal git host, or (for a
   disconnected network) an [offline bundle](OFFLINE.md) built with
   `GET_STARTED_OFFLINE_BUNDLE/offline-bundler.cmd`.
4. **Users run `GET_STARTED/install.cmd`** from it. One command, no follow-up steps.

Afterwards, changing the standard means editing the copy on the share; users
pick it up with `acorn update-commands` and `acorn apply`.

**Why the deployment features exist:** networks where the ordinary "install
Python from python.org, then pip install what you need" path is blocked or
unauditable — disconnected or mirror-only networks, managed desktops with no
admin rights, shared lab machines (one root, a private folder per user), and
teams that need everyone on an identical setup.

## Deployment configuration: `global.conf`

`global.conf` at the repo root is the single place a deployment's paths
and install-time settings live. Every setting is listed in the file with
its default value written out, so there's no guessing what can be changed
or what the current behavior is — values left at their defaults change
nothing. Standard users installing from the internet never touch it.
Organizations replace whichever values they need in the copy of the repo
they distribute (self-hosted git host, or a folder on a network drive),
and everyone installing from that copy picks the values up with no flags
or environment variables:

- `ACORN_REPO_URL` (default: the public GitHub repo) — the source used
  when the installer isn't run from inside a checkout, and where
  `acorn update-commands` fetches updates. A git URL or a plain directory path.
- `ACORN_HOME_DIR` (default: `~/acorn`) — the folder everything
  acorn manages lives in. A leading `~` means the installing user's
  home directory. A `{user}` token expands to the installing user's login
  name, so a **shared** install root gives each user a private,
  conflict-free folder: `ACORN_HOME_DIR="C:\acorn\{user}"` puts
  alice in `C:\acorn\alice`, bob in `C:\acorn\bob`. (The installer
  resolves the token before writing anything, and the shell integration
  exports the resolved `ACORN_HOME` so acorn-cli finds it at runtime.)
- `ACORN_VENV_DEFAULT_PACKAGES` (default: `ipython,ruff,ipykernel`) —
  comma-separated packages installed into every new venv (seeds the
  `venv_default_packages` setting).
- `ACORN_AUTO_SETUP` (default: `true`) — after installing acorn
  itself, install the newest stable Python and create a `dev` venv (with
  the default packages) that every new shell auto-activates. Set to `false`
  for a bare install; the `ACORN_AUTO_SETUP` environment variable
  overrides for one run. Never fatal: if this step fails (e.g. offline),
  acorn itself is still installed and working.
- `ACORN_AUTO_VSCODE` (default: `true`) — also download and set up the
  portable VS Code during install, so `acorn vscode` opens instantly
  instead of downloading ~300 MB on first use. Only applies when
  `ACORN_AUTO_SETUP` is `true`.
- `ACORN_PYTHON_MIRROR` (default: empty = internet) — where `acorn
  python` downloads interpreter builds: a URL of an internal mirror, or a
  plain directory of python-build-standalone archives on a share. Seeds
  the `python_mirror` setting.
- `ACORN_PACKAGE_INDEX` (default: empty = pypi.org) — where packages
  install from: an index URL, or a plain directory of wheels on a share
  (the internet index is then disabled entirely). Seeds the
  `package_index` setting. See [OFFLINE.md](OFFLINE.md) for the full
  offline deployment guide.
- `ACORN_PACKAGE_UPLOAD_URL` (default: empty) — the **upload** endpoint
  `acorn upload-whls` publishes to, which on servers that do both is a
  different path from `ACORN_PACKAGE_INDEX` (`.../api/pypi/<repo>/` vs
  `.../simple`). Seeds the `package_upload_url` setting.
- `ACORN_PACKAGE_UPLOAD_TOKEN` (default: empty) — the API token for it.
  **A write credential**: every value in this file is seeded into every
  user's settings at install time, so leave it empty in the copy you
  distribute and set it only on the machine that publishes (`acorn config set
  package_upload_token`). acorn masks it wherever it prints settings
  (`acorn config`, `acorn summary`, both `--json` forms), redacts it from the
  daily log — including the `config set` line that carries it — and passes it
  to twine through the environment, never on a command line.
- `ACORN_CONDA_CHANNEL` (default: `conda-forge`) — where `acorn
  forge-install` fetches conda-forge command-line tools from: a URL or a
  local directory for an internal mirror or an offline network. Seeds the
  `conda_channel` setting.
- `ACORN_NATIVE_TLS` (default: `false` = bundled trust store) — set to
  `true` to trust the operating system's certificate store, for internal
  HTTPS hosts signed by a machine-installed corporate CA (seeds the
  `native_tls` setting). Alternatively, ship the CA itself in
  `vendor/certs/` — see [OFFLINE.md](OFFLINE.md).
- `ACORN_VSCODE_FLAVOR` (default: `microsoft`) — which editor build
  `acorn vscode` installs: the official Visual Studio Code, or `vscodium`,
  the MIT-licensed community build. Seeds the `vscode_flavor` setting. See
  [Choosing a VS Code build](#which-vs-code-build)
  — this is a licensing choice as much as a technical one.
- `ACORN_EXTENSION_GALLERY` (default: empty = the flavor's own registry)
  — base URL of the extension registry, for an internal Open VSX mirror.
  Seeds the `extension_gallery` setting.
- `ACORN_VSCODE_EXTENSIONS` (default: empty = the flavor's starter kit)
  — comma-separated extensions installed into a fresh editor, or `none` for
  no extensions at all. Seeds the `vscode_extensions` setting.
- `ACORN_VSCODE_CONFIG_DIR` (default: empty) — path (relative to this
  repo copy, or absolute) of a folder holding your own `settings.json`
  and/or `keybindings.json` to acorn into a fresh editor. `settings.json` is
  merged over acorn's built-in defaults (your values win);
  `keybindings.json` is copied in as-is. Both only apply the first time an
  editor is installed. Seeds the `vscode_config_dir` setting.
- `ACORN_PROFILE` (default: empty) — path (relative to this repo copy, or
  absolute) of a [deployment profile](PROFILES.md): the interpreters, named
  venvs, packages and repos your users should end up with. When set, the
  installer applies it instead of creating the built-in single `dev` venv.
- `ACORN_CUSTOM_COMMANDS` (default: empty) — path (relative to this repo
  copy, or absolute) of a [custom commands](CUSTOM-COMMANDS.md) TOML file:
  your organization's own `acorn <name>` verbs. Seeds the `custom_commands`
  setting.
- `ACORN_STARTUP_COMMANDS` (default: empty) — comma-separated custom
  command names to run automatically, in order, in every new shell. Seeds
  the `startup_commands` setting; see
  [Running commands at startup](CUSTOM-COMMANDS.md#running-commands-at-startup).

How it's applied: both installers read `global.conf` at the repo root
(a piped install reads the copy inside the repo it just cloned). The
install source is always recorded as `update_source`, and other values
that differ from the public defaults are written alongside it, into
`~/acorn/system/config/settings.json` on **first install only** — an
existing settings file is never overwritten, so later `acorn config set`
choices survive reinstalls. Changing `global.conf` later doesn't reach
already-installed machines on its own; `acorn update-commands` will *report*
any drift it finds (see [its reference entry](commands/lifecycle.md#acorn-update-commands))
but never overwrite a setting for you. Resolution order for the install source:

1. `ACORN_REPO` environment variable (one-run override)
2. `ACORN_REPO_URL` from `global.conf`
3. the baked-in public default (what the piped one-liner uses)

## Shared-machine (multi-user) installs

By default acorn lives under each user's home (`~/acorn`), so
multiple users on one machine never interfere. If you'd rather put it on a
shared drive or a common folder — a lab computer, a multi-user server, or
just to keep it off roaming profiles — point `ACORN_HOME_DIR` at that
location with a `{user}` token so each person still gets a private,
conflict-free copy.

For example, to install every user under `C:\acorn\<their-name>`, set in
the distributed `global.conf`:

```
ACORN_HOME_DIR="C:\acorn\{user}"
```

Then when each user runs `GET_STARTED/install.cmd` from the share:

```
alice  ->  C:\acorn\alice\   (her interpreters, venvs, config, logs)
bob    ->  C:\acorn\bob\
carol  ->  C:\acorn\carol\
```

The installer resolves `{user}` to the login name before writing anything,
and bakes the resolved path into that user's shell hook — so `acorn` always
targets their own folder, and `acorn purge` only ever touches theirs.
Without the token, everyone would share one `C:\acorn` and collide;
with it, the shared root just holds one subfolder per user. (The default
`~/acorn` needs no token — a home directory is already per-user.)

---

## Choosing an editor

Two separate decisions: **which editor**, and — if it's VS Code — **which
build of it**.

### Which editor

A [deployment profile](PROFILES.md) can name the one everyone gets:

```toml
editor = "spyder"                  # or "vscode", or both in a list
```

`acorn apply` installs them last, since they're the largest step. **Spyder** suits
teams doing analysis rather than software engineering — a variable explorer,
an IPython console and a plots pane, wired automatically to the venv the user
has activated. **VS Code** is the general-purpose default. Omit the key and
`acorn apply` installs no editor at all.

**A profile's `editor` outranks `ACORN_AUTO_VSCODE`.** That setting
defaults to `true` and installs VS Code during setup, but a profile that
names editors *without* VS Code among them turns it off for you —
`editor = "spyder"` deploys Spyder and *only* Spyder, with no conf change
needed. List VS Code among them and it's installed as usual (and still
downloaded in parallel with the Python setup). Leave the key out entirely
and `ACORN_AUTO_VSCODE` decides exactly as before.

> **Spyder is x86_64 only.** Its Qt dependency publishes no arm64 wheels, so
> on Apple Silicon or ARM Linux use `tools = ["spyder"]` (the conda-forge
> build) instead of `editor = "spyder"`.

For whole profiles built around each of these choices, see
[profile examples](PROFILE-EXAMPLES.md).

### Which VS Code build

`acorn vscode` installs the official Microsoft build by default, with
extensions from the Marketplace. For most teams that needs no configuration.

It deserves a second look if you're **staging an offline bundle onto a
share**, because that is redistribution: the official binaries are under
Microsoft's proprietary licence (the MIT licence on `microsoft/vscode` covers
the source, not the branded builds), and Marketplace extensions carry their
own Terms of Use. Both restrict redistribution in ways an internal share may
not satisfy. If that matters:

```
ACORN_VSCODE_FLAVOR="vscodium"
```

VSCodium is the same source without Microsoft's branding and telemetry, MIT
licensed, already pointed at [Open VSX](https://open-vsx.org). acorn picks
the matching extension set automatically.

**The tradeoff is Pylance** — proprietary, licensed to run only in official
Microsoft products, so absent from Open VSX by design. Without it the Python
extension falls back to its bundled Jedi server, and completions and type
checking are noticeably weaker. For many teams that's the deciding factor in
the other direction.

### Pointing at an internal registry

On an isolated network, mirror Open VSX internally and give acorn the
base URL — the gallery and item endpoints are derived from it:

```
ACORN_EXTENSION_GALLERY="https://openvsx.mycompany.com/vscode"
```

Setting this on the **`microsoft` flavor** rewrites `product.json` inside
the official build — that is, it modifies a proprietary binary, which is a
licensing question of its own. Prefer `vscodium`, which needs no patching.

### Standardizing the extension set

```
ACORN_VSCODE_EXTENSIONS="ms-python.python,charliermarsh.ruff"
```

Empty means the starter kit for the chosen flavor. `"none"` installs
nothing at all — useful when your users get their editor from somewhere else
and only want acorn's Python management.

### Seeding your own settings and keybindings

For anything the extension set and `DEFAULT_SETTINGS` don't cover — a font
size, `editor.rulers`, a team keybinding — point at a folder in the repo
copy you distribute:

```
ACORN_VSCODE_CONFIG_DIR="vscode-config"
```

holding whichever of these you want to ship:

```
vscode-config/
├── settings.json       merged over acorn's own defaults -- your values win
└── keybindings.json    copied in as-is (there's no built-in default to merge with)
```

Both only apply the first time the editor is installed — like everything
else here, a user's own edits are never overwritten by a later
`acorn update-commands` or reinstall.

All four are ordinary settings, so a user can override them locally with
`acorn config set` unless you have reason to re-deploy instead.

---

## Rolling out

A workable order for a first deployment:

1. **Pick the install source.** A git URL if you have a self-hosted git
   server; a folder on a share if you don't. This becomes
   `ACORN_REPO_URL`, and it is also where `acorn update-commands` will
   fetch from later — so put it somewhere durable.
2. **Decide where installs live.** `ACORN_HOME_DIR`. Use the `{user}`
   token if several people share one root.
3. **Point package and interpreter downloads at your mirrors** if the
   internet is blocked — `ACORN_PACKAGE_INDEX` and
   `ACORN_PYTHON_MIRROR`. On a fully disconnected network, run
   `GET_STARTED_OFFLINE_BUNDLE/offline-bundler.cmd` to assemble the whole bundle in one step; see
   [OFFLINE.md](OFFLINE.md).
4. **Define the environment.** For a single venv, `ACORN_VENV_DEFAULT_PACKAGES`
   decides what every new venv starts with, and `ACORN_AUTO_VSCODE` whether
   the portable editor is staged during install. For anything richer — several
   named venvs, per-venv packages, repos to clone — write a
   [deployment profile](PROFILES.md) and point `ACORN_PROFILE` at it. The
   profile is also how you keep a fleet converged later: publish an updated
   one and users run `acorn apply`.
5. **Prove it on a clean machine** that matches your users' — same OS, same
   lack of admin rights, same network restrictions. The offline guide has a
   [verification procedure](OFFLINE.md#proving-the-bundle-works-before-it-leaves)
   for this.
6. **Distribute.** Users run the one-liner, or double-click `GET_STARTED/install.cmd` from
   the share on Windows. Nothing else is required of them.
7. **Verify after the fact.** `acorn health-check` confirms an install is
   sound; `acorn summary` prints everything installed, and `--json` makes that
   machine-readable if you want to collect it across a fleet.

---

## Admin commands (shared-root teardown)

The ordinary `acorn purge` / `remove-user` are strictly per-user -- they can
only touch the caller's own folder, by design. For a **shared-root install**
(`ACORN_HOME_DIR="<root>/{user}"`), tearing down *other* users needs an
elevated, ownership-seizing operation. That's the `admin-*` family.

These commands are **hidden from normal help** -- `acorn help` won't list
them. Reveal them with:

```
acorn help --admin
```

Every one of them:

- **Requires elevation** (Administrator on Windows, root on POSIX) and
  refuses with instructions otherwise -- a normal user cannot delete
  another user's files, and shouldn't be able to.
- **Only works on a shared-root install** -- it reads the `shared_root`
  setting recorded at install time when the `{user}` token was used. On a
  plain `~/acorn` it refuses (there are no sibling users to manage). acorn knows its own
  install type from this setting: `acorn summary` shows "install type:
  multi-user (shared root: ...)" vs "single-user", and the admin pointer in
  `acorn help` only appears on a multi-user install.
- **Takes ownership before deleting** (`takeown` + `icacls` on Windows; root
  already bypasses ownership on POSIX), so user-owned, read-only, and
  runtime-generated files (`__pycache__`, a user's own `pip` installs) don't
  block the teardown -- the gap that install-time permissions can never
  fully close.
- Supports `--preview`, `-y`, and `--non-interactive` like the ordinary
  destructive commands.

| Command | Removes |
|---|---|
| `admin-purge-all-users` | every user's install under the shared root, plus every user's shell hook |
| `admin-remove-user <user>` | one user's entire acorn home |
| `admin-remove-venv <user> <name>` | one user's single venv |
| `admin-remove-venv-all <user>` | all of one user's venvs |
| `admin-remove-python <user> <tag>` | one user's base Python and the venvs built on it |
| `admin-remove-repo <user> <name>` | one user's cloned repo |

Example -- an administrator decommissioning a shared lab machine whose users
live under `C:\acorn\<name>`:

```
# In an Administrator PowerShell:
acorn help --admin                     # see the family
acorn admin-purge-all-users --preview  # list exactly what would go
acorn admin-purge-all-users            # take ownership + remove everyone, confirm first
```

Or cleaning up after one departed user:

```
acorn admin-remove-user alice          # removes C:\acorn\alice entirely
```

---
## What a security review will ask

The questions that come up in a review, and where the answer is documented:

| Question | Answer |
|---|---|
| What does it write outside its own folder? | The shell hook line in the user's profile. Nothing else — no registry, no `%APPDATA%`, no system paths. See [the folder layout](GUIDE.md#the-folder-layout). |
| Does it need administrator rights? | No. Only the [`admin-*` family](#admin-commands-shared-root-teardown) does, and only for cross-user teardown. |
| Where does code come from? | Whatever you set in `global.conf`. Pointed at internal mirrors, it never contacts github.com or pypi.org — see [OFFLINE.md](OFFLINE.md). |
| Are downloads verified? | Yes — SHA-256 against the publisher's checksum, with an explicit warning when no checksum can be obtained. See [Download verification](DESIGN.md#download-verification). |
| Is there an audit trail? | Every command is logged, one plain-text file per day, under `system/logs/`. See [Command logging](DESIGN.md#command-logging). |
| Can it be removed completely? | `acorn purge` deletes the install directory and the shell hook. `admin-purge-all-users` does it for every user under a shared root. Both support `--preview` to show exactly what would go, first. |
| What happens to user data on removal? | Destructive commands check cloned repos for work that exists nowhere else and name it before prompting. See [Unsaved work in cloned repos](DESIGN.md#unsaved-work-in-cloned-repos). |
| Can it run unattended in CI or a deployment script? | Yes — `--non-interactive` and `-y`. See [Non-interactive mode](DESIGN.md#non-interactive-mode--previews). |
| What third-party code does it bring in, under what licence? | acorn vendors nothing; it downloads from each publisher at your direction. Every offline bundle carries a `MANIFEST.json` listing component, source, and licence — **including every wheel**, resolved from its own metadata and grouped by obligation. Run it yourself any time: `acorn whl-licenses <dir>`, `acorn venv-licenses`, `acorn forge-licenses`. See [LICENSING.md](LICENSING.md). |

The reasoning behind these behaviors is in **[Design and safety](DESIGN.md)**.
