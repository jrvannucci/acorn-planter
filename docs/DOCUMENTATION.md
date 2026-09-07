# acorn documentation

The map. Everything is split into two tracks — one for people **using**
acorn on their own machine, one for people **deploying** it to others.

New here? The [home page](index.md) covers what acorn is and the everyday
workflow in a couple of minutes.

---

## Using acorn

Start here if acorn is installed on your own machine, or about to be.

| | |
|---|---|
| **[Using acorn](GUIDE.md)** | How installation works, the folder layout, why `acorn` is a shell function, the update model, uninstalling, and troubleshooting. |
| **[Command reference](COMMANDS.md)** | All 59 commands in one filterable list — click any one to open its full documentation — plus the per-family breakdowns. |
| **[Design and safety](DESIGN.md)** | Why deletion is so defensive, what gets logged, how downloads are verified, and how to run acorn unattended. |
| **[Scripting & automation](commands/scripting-and-automation.md)** | The machine-facing surface, in one place: `acorn run`, `acorn which`, `--json` on every read command, never blocking on a prompt, and how concurrent commands are serialized. |

---

## Deploying acorn

Start here if you are setting acorn up **for other people** — a team, a
lab, a restricted network.

| | |
|---|---|
| **[Deployment guide](DEPLOYMENT.md)** | `global.conf`, shared-machine installs, the elevated `admin-*` teardown family, a rollout checklist, and the answers to a security review. |
| **[Deployment profiles](PROFILES.md)** | One file describing the environment your users should end up with — interpreters, named venvs and their packages, repos — applied at install and re-applied with `acorn apply`. |
| **[Profile examples](PROFILE-EXAMPLES.md)** | Complete, working profiles for real situations — a research group, a software team, a classroom, an air-gapped fleet. Copy one and change the names. |
| **[Custom commands](CUSTOM-COMMANDS.md)** | Add your organization's own verbs to `acorn` (`acorn lint`, `acorn bootstrap`) and, optionally, run some of them automatically in every new shell. |
| **[Offline / air-gapped networks](OFFLINE.md)** | Running with no internet at all: mirrors, vendored binaries, wheel directories, corporate CAs, and `GET_STARTED_OFFLINE_BUNDLE/offline-bundler.cmd`. |
| **[Licensing and redistribution](LICENSING.md)** | acorn ships no third-party software. What it downloads, under what terms, and what changes when you stage a bundle for a share. |

---

## Working on acorn itself

**[Contributor guide](CONTRIBUTING.md)** — the edit → `acorn update-commands`
loop (including `--from-branch` for tracking a fork's branch), the source
layout, and running the tests.

---

## Quick answers

| I want to… | Go to |
|---|---|
| Install acorn | [Using acorn → How installation works](GUIDE.md#how-installation-works) |
| Know what a .cmd file actually does | [Entry points](commands/entry-points.md) |
| Deploy it to other people | [Deployment guide → The deployment workflow](DEPLOYMENT.md#the-deployment-workflow) |
| Build a bundle for an air-gapped network | [Offline networks → The workflow](OFFLINE.md#the-workflow) |
| Look up a command | [Command reference](COMMANDS.md) |
| Drive acorn from a script, CI job or AI agent | [Scripting & automation](commands/scripting-and-automation.md) |
| Get a venv's interpreter path | [`acorn which`](commands/venvs-and-packages.md#acorn-which-name---json) |
| Run something in a venv without a shell | [`acorn run`](commands/venvs-and-packages.md#acorn-run--n-venv----command-args) |
| Read acorn's state as JSON | [Scripting & automation](commands/scripting-and-automation.md) |
| Install an editor (VS Code, Spyder) or a Python app | [Command reference](COMMANDS.md) |
| Standardize the editor across a fleet | [Deployment profiles](PROFILES.md) |
| Understand where files go | [Using acorn → The folder layout](GUIDE.md#the-folder-layout) |
| Update or repair an install | [Using acorn → The update model](GUIDE.md#the-update-model) |
| Remove acorn completely | [Using acorn → Uninstalling](GUIDE.md#uninstalling) |
| Fix something that broke | [Using acorn → Troubleshooting](GUIDE.md#troubleshooting) |
| Standardize a team's setup | [Profile examples](PROFILE-EXAMPLES.md) |
| Add my own verbs to `acorn` | [Custom commands](CUSTOM-COMMANDS.md) |
| Give everyone the same venvs and packages | [Profile examples](PROFILE-EXAMPLES.md) |
| Give different teams different environments | [Profiles → Who gets which profile](PROFILES.md#who-gets-which-profile) |
| Point installs at an internal source | [Deployment guide → `global.conf`](DEPLOYMENT.md#deployment-configuration-globalconf) |
| Install with no internet | [Offline networks](OFFLINE.md) |
| Put many users on one machine | [Deployment guide → Shared-machine installs](DEPLOYMENT.md#shared-machine-multi-user-installs) |
| Tear down another user's install | [Deployment guide → Admin commands](DEPLOYMENT.md#admin-commands-shared-root-teardown) |
| Answer a security questionnaire | [Deployment guide → What a security review will ask](DEPLOYMENT.md#what-a-security-review-will-ask) |
| Know what I'm allowed to redistribute | [Licensing and redistribution](LICENSING.md) |
| Know what acorn can't do | [Using acorn → Known limits](GUIDE.md#known-limits) |
