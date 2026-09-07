"""The {user} placeholder in ACORN_HOME_DIR / ACORN_HOME: a shared
install root gives each user a private, conflict-free folder."""

from __future__ import annotations

import subprocess


from conftest import BASH, make_repo_copy, needs_bash, plant_stub_uv
from acorn import paths


def test_runtime_expands_user_token(monkeypatch):
    monkeypatch.setattr(paths, "_current_username", lambda: "alice")
    monkeypatch.setenv("ACORN_HOME", "/shared/acorn/{user}")
    home = paths.acorn_home()
    assert "{user}" not in str(home)
    assert str(home).replace("\\", "/").endswith("/shared/acorn/alice")


def test_runtime_no_token_is_untouched(monkeypatch):
    monkeypatch.setenv("ACORN_HOME", "/plain/acorn")
    assert str(paths.acorn_home()).replace("\\", "/").endswith("/plain/acorn")


def test_current_username_never_raises(monkeypatch):
    import getpass
    monkeypatch.setattr(getpass, "getuser", lambda: (_ for _ in ()).throw(OSError()))
    monkeypatch.setenv("USERNAME", "fallbackuser")
    assert paths._current_username() == "fallbackuser"


@needs_bash
def test_installer_expands_user_token_per_user(tmp_path):
    """Two users installing from the SAME shared-root conf land in
    separate, non-colliding folders."""
    copy = make_repo_copy(tmp_path / "copy")
    shared = tmp_path / "shared"
    conf = copy / "GET_STARTED" / "global.conf"
    conf.write_text(conf.read_text().replace(
        'ACORN_HOME_DIR="~/acorn"',
        f'ACORN_HOME_DIR="{shared.as_posix()}/{{user}}"'))

    def install_as(user, home_name):
        fake_home = tmp_path / home_name
        fake_home.mkdir()
        # pre-plant a stub uv at the resolved per-user home so no network
        plant_stub_uv(shared / user)
        return subprocess.run(
            [BASH, "-c",
             f"cd '{copy.as_posix()}' && HOME='{fake_home.as_posix()}' "
             f"USER={user} SHELL=/bin/bash ACORN_AUTO_SETUP=false sh ./GET_STARTED/install.cmd"],
            capture_output=True, text=True, timeout=120)

    r1 = install_as("alice", "home_a")
    assert r1.returncode == 0, r1.stdout + r1.stderr
    r2 = install_as("bob", "home_b")
    assert r2.returncode == 0, r2.stdout + r2.stderr

    assert (shared / "alice" / "system" / "src" / "src" / "pyproject.toml").exists()
    assert (shared / "bob" / "system" / "src" / "src" / "pyproject.toml").exists()
    assert not (shared / "{user}").exists()  # no literal token folder
