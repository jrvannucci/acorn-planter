# Registered in custom-commands.toml as `script = "bootstrap.py"`,
# `toplevel = true`.
# Try it: acorn config set custom_commands ./examples/custom-commands/custom-commands.toml
#         acorn bootstrap          (bare -- toplevel = true)
#         acorn custom bootstrap   (also works, namespaced)
#
# The "build a venv, then run a function in it" case. No SDK needed --
# orchestration scripts just shell out to `acorn` itself, the same thing
# `acorn apply` already does internally. See docs/CUSTOM-COMMANDS.md.
import subprocess
import sys


def main(argv):
    subprocess.run(["acorn", "venv", "myproj", "--python", "312"], check=True)
    subprocess.run(["acorn", "run", "-n", "myproj", "--",
                     "python", "-m", "myorg_tools.setup", *argv], check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
