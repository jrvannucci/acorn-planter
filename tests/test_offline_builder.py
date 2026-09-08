"""docs/offline-builder.html is a standalone authoring aid whose JavaScript
duplicates schema constants from acorn/bundle.py and acorn/profile.py -- the
platform list, the always-bundled packages, the valid editor flavors, and the
key names each TOML table accepts.

A tool that quietly disagrees with the validator it claims to mirror is worse
than no tool: it would bless a bundle the real build then rejects, or reject
one that is fine. These tests pin the duplicated constants to their source so
a change to bundle.py / profile.py that isn't mirrored fails here, the same
way test_user_placeholder pins the three copies of the install URL.
"""

from __future__ import annotations

import re

from acorn import bundle as bundle_mod, config
from acorn import profile as profile_mod
from acorn.commands import vscode_cmd

from tests.conftest import REPO_ROOT

HTML = (REPO_ROOT / "docs" / "offline-builder.html").read_text(encoding="utf-8")


def _js_string_array(name: str) -> list[str]:
    """Pull `var NAME = [ "a", "b", ... ];` out of the page's script, tolerating
    newlines and trailing commas. Nested arrays (the PLATFORMS pairs) are
    handled by _js_pairs_first instead."""
    m = re.search(rf"var {name}\s*=\s*\[(.*?)\];", HTML, re.S)
    assert m, f"{name} not found in offline-builder.html"
    return re.findall(r'"([^"]+)"', m.group(1))


def _js_pairs_first(name: str) -> list[str]:
    """First element of each `["key", "desc"]` pair in a `var NAME = [ ... ]`."""
    m = re.search(rf"var {name}\s*=\s*\[(.*?)\];", HTML, re.S)
    assert m, f"{name} not found"
    return re.findall(r'\[\s*"([^"]+)"', m.group(1))


def _py_brace_set(source: str, anchor: str) -> set[str]:
    """The string literals in the first `{ "...", "..." }` set literal that
    follows `anchor` in a Python source string."""
    start = source.index(anchor)
    brace = source.index("{", start)
    depth = 0
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return set(re.findall(r'"([^"]+)"', source[brace:i + 1]))
    raise AssertionError(f"unbalanced braces after {anchor!r}")


BUNDLE_SRC = (REPO_ROOT / "acorn-planter" / "src" / "acorn" / "bundle.py").read_text(encoding="utf-8")


def test_platform_list_matches_bundle():
    assert [p.lower() for p in _js_pairs_first("PLATFORMS")] == list(bundle_mod.PLATFORM_TAGS)


def test_always_present_packages_match_bundle():
    assert _js_string_array("ALWAYS_PRESENT") == bundle_mod.ALWAYS_PRESENT


def test_editor_flavors_match_the_cli():
    assert tuple(_js_string_array("FLAVORS")) == vscode_cmd.FLAVORS


def test_archive_values_match_bundle():
    # bundle.parse() accepts these plus the sentinels true/false, which the
    # builder models as the <select> options rather than string values.
    m = re.search(r"archive in\s*\(([^)]*)\)", BUNDLE_SRC)
    assert m, "archive tuple not found in bundle.py"
    accepted = re.findall(r'"([^"]+)"', m.group(1))
    assert _js_string_array("ARCHIVE_VALUES") == accepted == ["auto", "zip", "tar", "tar.gz"]


def test_default_venv_packages_match_config():
    assert _js_string_array("DEFAULT_VENV_PACKAGES") == config.default_of("venv_default_packages")


def test_bundle_top_level_keys_match_bundle_parse():
    assert set(_js_string_array("BUNDLE_TOP_KEYS")) == _py_brace_set(BUNDLE_SRC, "known = {")


def test_bundle_editor_keys_match_bundle_parse():
    assert set(_js_string_array("BUNDLE_EDITOR_KEYS")) == _py_brace_set(
        BUNDLE_SRC, "set(editor) - {")


def test_bundle_build_keys_match_bundle_parse():
    assert set(_js_string_array("BUNDLE_BUILD_KEYS")) == _py_brace_set(
        BUNDLE_SRC, "set(build) - {")


def test_profile_settable_keys_match_profile_module():
    assert set(_js_string_array("PROFILE_SETTABLE_KEYS")) == profile_mod.SETTABLE_KEYS


def test_page_is_self_contained():
    """No network. The audience installs from a USB stick on a machine that has
    never reached the internet -- a <script src>, <link>, @import or webfont URL
    would simply not load there."""
    for needle in ("src=\"http", "href=\"http", "@import", "cdn.", "googleapis"):
        assert needle not in HTML, f"offline-builder.html reaches out via {needle!r}"
