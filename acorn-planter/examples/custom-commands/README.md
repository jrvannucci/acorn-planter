# Custom commands — worked examples

A runnable companion to [docs/CUSTOM-COMMANDS.md](../../docs/CUSTOM-COMMANDS.md).
One file, `custom-commands.toml`, declares every command below (`run` for
the simple ones, `script` for `quote`/`bootstrap`, which need real logic):

```
acorn config set custom_commands ./examples/custom-commands/custom-commands.toml
```

Then:

```
acorn custom              # lists everything in the file
acorn custom data-stack   # run: acorn install into the active venv
acorn hello Jon           # run, toplevel = true -- runs as bare `acorn hello`
acorn custom quote        # script: random line from a companion quotes.txt
acorn bootstrap           # script, toplevel = true -- runs as bare `acorn bootstrap`
```

`bootstrap.py` is illustrative — it shells out to `acorn venv` and
`acorn run` (the pattern for "build a venv, then run something in it"), but
the `myorg_tools.setup` module it references is a stand-in for whatever your
own package actually is; it won't complete successfully as-is.

**Running one at shell startup.** `motd` in `custom-commands.toml` is meant
to demonstrate [`startup_commands`](../../docs/CUSTOM-COMMANDS.md#running-commands-at-startup)
rather than be typed by hand:

```
acorn config set startup_commands motd
```

Open a **new** terminal (the existing one already ran its startup block) and
the message prints automatically, before your prompt — no `acorn custom`, no
`acorn motd`, nothing to remember. `acorn config unset startup_commands` turns
it back off.

**Chaining two commands** so the second only runs if the first succeeds:

```
acorn config set startup_commands "data-stack&&motd"
```

Open a new terminal and `data-stack` (the `acorn install` example above)
runs first; `motd` only follows it if that install actually succeeded. `,`
still separates independent entries — `"data-stack&&motd, quote"` runs
`quote` regardless of how the chain went.

Unset the rest with `acorn config unset custom_commands` /
`acorn config unset startup_commands` when you're done trying it out.
