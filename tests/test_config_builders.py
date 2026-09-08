"""docs/global-conf-builder.html, docs/profile-builder.html and
docs/offline-bundle-builder.html are standalone authoring aids whose
JavaScript duplicates schema constants from acorn/config.py, acorn/profile.py
and acorn/bundle.py -- the ACORN_* key list, the settable profile keys, the
platform list, the always-bundled packages, the editor flavors, the keys each
TOML table accepts.

A tool that quietly disagrees with the validator it claims to mirror is worse
than no tool: it would bless a file the real code then rejects, or reject one
that is fine. These tests pin the duplicated constants to their source so a
change that isn't mirrored fails here -- the same idea as test_user_placeholder
pinning the three copies of the install URL.

They also assert the three tools share a byte-identical CSS/JS prelude (so
they don't drift into three subtly different looks) and that every page is
self-contained (the audience opens them off a USB stick on a machine that has
never reached the internet).
"""

from __future__ import annotations

import re

from acorn import bundle as bundle_mod, config
from acorn import profile as profile_mod
from acorn.commands import vscode_cmd
from conftest import REPO_ROOT

DOCS = REPO_ROOT / "docs"
GLOBAL_CONF = (DOCS / "global-conf-builder.html").read_text(encoding="utf-8")
PROFILE = (DOCS / "profile-builder.html").read_text(encoding="utf-8")
BUNDLE = (DOCS / "offline-bundle-builder.html").read_text(encoding="utf-8")
INDEX = (DOCS / "config-builder.html").read_text(encoding="utf-8")
ALL_PAGES = {
    "global-conf-builder.html": GLOBAL_CONF,
    "profile-builder.html": PROFILE,
    "offline-bundle-builder.html": BUNDLE,
    "config-builder.html": INDEX,
}
BUILDERS = {k: v for k, v in ALL_PAGES.items() if k != "config-builder.html"}

BUNDLE_PY = (REPO_ROOT / "acorn-planter" / "src" / "acorn" / "bundle.py").read_text(encoding="utf-8")
INSTALL_PS1 = (REPO_ROOT / "acorn-planter" / "installers" / "install.ps1").read_text(encoding="utf-8")
GLOBAL_CONF_FILE = (REPO_ROOT / "acorn-planter" / "global.conf").read_text(encoding="utf-8")


# --- helpers -------------------------------------------------------------------

def _js_string_array(html: str, name: str) -> list[str]:
    m = re.search(rf"var {name}\s*=\s*\[(.*?)\];", html, re.S)
    assert m, f"{name} not found"
    return re.findall(r'"([^"]+)"', m.group(1))


def _js_pairs_first(html: str, name: str) -> list[str]:
    m = re.search(rf"var {name}\s*=\s*\[(.*?)\];", html, re.S)
    assert m, f"{name} not found"
    return re.findall(r'\[\s*"([^"]+)"', m.group(1))


def _py_brace_set(source: str, anchor: str) -> set[str]:
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


def _prelude(html: str) -> str:
    """The CSS + JS shared prelude, both fenced blocks concatenated."""
    parts = re.findall(
        r"/\* ==== SHARED PRELUDE.*?/\* ==== END SHARED PRELUDE ==== \*/",
        html, re.S)
    assert len(parts) == 2, f"expected 2 prelude blocks, found {len(parts)}"
    return "\n----\n".join(parts)


# --- the shared prelude -------------------------------------------------------

def test_the_three_builders_share_one_prelude():
    preludes = {name: _prelude(html) for name, html in BUILDERS.items()}
    first = next(iter(preludes.values()))
    for name, p in preludes.items():
        assert p == first, f"{name}'s shared prelude has drifted from the others"


def test_every_page_is_self_contained():
    for name, html in ALL_PAGES.items():
        for needle in ('src="http', 'href="http', "@import", "cdn.", "googleapis", "unpkg"):
            assert needle not in html, f"{name} reaches out via {needle!r}"


# --- offline-bundle-builder.html vs bundle.py --------------------------------

def test_platform_list_matches_bundle():
    assert [p.lower() for p in _js_pairs_first(BUNDLE, "PLATFORMS")] == list(bundle_mod.PLATFORM_TAGS)


def test_always_present_packages_match_bundle():
    assert _js_string_array(BUNDLE, "ALWAYS_PRESENT") == bundle_mod.ALWAYS_PRESENT
    # the profile builder carries the same list for its fit-check
    assert _js_string_array(PROFILE, "ALWAYS_PRESENT") == bundle_mod.ALWAYS_PRESENT


def test_editor_flavors_match_the_cli():
    assert tuple(_js_string_array(BUNDLE, "FLAVORS")) == vscode_cmd.FLAVORS
    assert set(_js_string_array(GLOBAL_CONF, "FLAVORS")) == set(vscode_cmd.FLAVORS)


def test_archive_values_match_bundle():
    m = re.search(r"archive in\s*\(([^)]*)\)", BUNDLE_PY)
    assert m, "archive tuple not found in bundle.py"
    accepted = re.findall(r'"([^"]+)"', m.group(1))
    assert _js_string_array(BUNDLE, "ARCHIVE_VALUES") == accepted == ["auto", "zip", "tar", "tar.gz"]


def test_bundle_top_level_keys_match_bundle_parse():
    assert set(_js_string_array(BUNDLE, "BUNDLE_TOP_KEYS")) == _py_brace_set(BUNDLE_PY, "known = {")


def test_bundle_editor_keys_match_bundle_parse():
    assert set(_js_string_array(BUNDLE, "BUNDLE_EDITOR_KEYS")) == _py_brace_set(BUNDLE_PY, "set(editor) - {")


def test_bundle_build_keys_match_bundle_parse():
    assert set(_js_string_array(BUNDLE, "BUNDLE_BUILD_KEYS")) == _py_brace_set(BUNDLE_PY, "set(build) - {")


# --- profile-builder.html vs profile.py -------------------------------------

def test_profile_settable_keys_match_profile_module():
    assert set(_js_string_array(PROFILE, "SETTABLE_KEYS")) == profile_mod.SETTABLE_KEYS


def test_profile_editors_are_a_known_set():
    assert set(_js_string_array(PROFILE, "EDITORS")) == {"vscode", "spyder"}


# --- global-conf-builder.html vs global.conf + the installers ---------------

def test_conf_key_list_matches_global_conf():
    in_file = re.findall(r"^(ACORN_[A-Z_]+)=", GLOBAL_CONF_FILE, re.M)
    assert _js_string_array(GLOBAL_CONF, "CONF_KEYS") == in_file


def test_conf_defaults_agree_with_config_module():
    # a couple of load-bearing defaults the builder writes as "unchanged" lines
    assert config.default_of("conda_channel") == "conda-forge"
    assert _js_string_array(GLOBAL_CONF, "DEFAULT_VENV_PACKAGES") == config.default_of("venv_default_packages")
    assert _js_string_array(PROFILE, "DEFAULT_VENV_PACKAGES") == config.default_of("venv_default_packages")


def test_powershell_policy_values_are_accepted_by_the_installer():
    accepted = set()
    for m in re.finditer(r'\$pref -in @\(([^)]*)\)', INSTALL_PS1):
        accepted |= set(re.findall(r'"([^"]+)"', m.group(1)))
    assert accepted, "install.ps1 policy lists not found"
    raw = re.search(r"var POLICY_VALUES\s*=\s*\[(.*?)\]", GLOBAL_CONF, re.S).group(1)
    offered = {s for s in re.findall(r'"([^"]*)"', raw) if s}
    assert offered <= accepted, f"builder offers policy values the installer rejects: {offered - accepted}"
