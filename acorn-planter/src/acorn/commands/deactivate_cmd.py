from __future__ import annotations


def run(args) -> int:
    # The real work happens in the `acorn` shell function, which intercepts
    # `deactivate` before it ever gets here and calls the shell's own
    # `deactivate` function/command (the one venv's activate script defines).
    # A subprocess has no way to affect the parent shell's environment, so if
    # we're running here it means acorn-cli was invoked directly rather than
    # through the shell function.
    print(
        "This only works when 'acorn' is the shell function installed by the "
        "acorn installer (it's what lets deactivation affect your current "
        "shell). If you're seeing this, re-run the installer or open a new "
        "terminal, then run:  acorn deactivate"
    )
    return 0
