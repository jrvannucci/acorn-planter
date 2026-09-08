"""Exercise installer policy handling with mocked cmdlets; never change HKCU."""
import json
import subprocess
from pathlib import Path

import pytest
from conftest import POWERSHELL, needs_powershell


@needs_powershell
@pytest.mark.parametrize("process_override", [False, True])
@pytest.mark.parametrize("scope,policy,answer,prompt,ready,changed", [
    ("CurrentUser", "RemoteSigned", "yes", True, True, False),
    ("CurrentUser", "Restricted", "yes", True, True, True),
    ("CurrentUser", "Restricted", "no", True, False, False),
    ("LocalMachine", "Restricted", "yes", False, False, False),
    ("MachinePolicy", "Restricted", "yes", True, False, False),
    ("CurrentUser", "AllSigned", "yes", True, False, False),
    ("Default", "Undefined", "yes", True, True, True),
])
def test_persistent_policy_ignores_process_bypass(scope, policy, answer, prompt, ready, changed, process_override):
    installer = Path(__file__).resolve().parents[1] / "acorn-planter/installers/install.ps1"
    source = installer.read_text(encoding="utf-8")
    helper = source.split("function Enable-ACORNProfilePolicy {", 1)[1].split("function Add-ACORNHook", 1)[0]
    script = "function Enable-ACORNProfilePolicy {" + helper + f'''
$env:ACORN_NONINTERACTIVE = $null
$script:Changed = $false
$script:Asked = $false
function Warn($msg) {{ }}
function Info($msg) {{ }}
function Get-ExecutionPolicy {{
    param($Scope, $ErrorAction)
    if ($Scope -eq "Process") {{ throw "Process policy must not be used" }}
    if ($script:Changed -and $Scope -eq "CurrentUser") {{ return "RemoteSigned" }}
    if ($Scope -eq "{scope}") {{ return "{policy}" }}
    return "Undefined"
}}
function Read-Host($msg) {{ $script:Asked = $true; return "{answer}" }}
function Set-ExecutionPolicy {{
    param($Scope, $ExecutionPolicy, [switch]$Force, $ErrorAction)
    if ($Scope -ne "CurrentUser" -or $ExecutionPolicy -ne "RemoteSigned") {{ throw "Unexpected policy change" }}
    $script:Changed = $true
    if (${str(process_override).lower()}) {{ throw "Saved, but overridden by Process Bypass" }}
}}
$result = Enable-ACORNProfilePolicy -CanPrompt ${str(prompt).lower()}
@{{ ready = $result; changed = $script:Changed; asked = $script:Asked }} | ConvertTo-Json -Compress
'''
    result = subprocess.run([POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout.strip().splitlines()[-1])
    assert payload["ready"] is ready
    assert payload["changed"] is changed
    if changed:
        assert payload["asked"]


@needs_powershell
@pytest.mark.parametrize("preference,scope,policy,ready,changed,asked", [
    # "skip"/"false": never look at the policy, never prompt, always ready.
    ("skip", "CurrentUser", "Restricted", True, False, False),
    ("false", "MachinePolicy", "AllSigned", True, False, False),
    # "RemoteSigned"/"true": set it with no prompt on the case the installer
    # could always handle...
    ("RemoteSigned", "CurrentUser", "Restricted", True, True, False),
    ("true", "Default", "Undefined", True, True, False),
    # ...but still cannot override machine-wide policy or AllSigned.
    ("RemoteSigned", "MachinePolicy", "Restricted", False, False, False),
    ("true", "CurrentUser", "AllSigned", False, False, False),
    # already permissive: nothing to do, forced or not.
    ("RemoteSigned", "CurrentUser", "RemoteSigned", True, False, False),
])
def test_conf_preference_removes_the_prompt(preference, scope, policy, ready, changed, asked):
    installer = Path(__file__).resolve().parents[1] / "acorn-planter/installers/install.ps1"
    source = installer.read_text(encoding="utf-8")
    helper = source.split("function Enable-ACORNProfilePolicy {", 1)[1].split("function Add-ACORNHook", 1)[0]
    script = "function Enable-ACORNProfilePolicy {" + helper + f'''
$env:ACORN_NONINTERACTIVE = $null
$script:Changed = $false
$script:Asked = $false
function Warn($msg) {{ }}
function Info($msg) {{ }}
function Get-ExecutionPolicy {{
    param($Scope, $ErrorAction)
    if ($Scope -eq "Process") {{ throw "Process policy must not be used" }}
    if ($script:Changed -and $Scope -eq "CurrentUser") {{ return "RemoteSigned" }}
    if ($Scope -eq "{scope}") {{ return "{policy}" }}
    return "Undefined"
}}
function Read-Host($msg) {{ $script:Asked = $true; return "n" }}
function Set-ExecutionPolicy {{
    param($Scope, $ExecutionPolicy, [switch]$Force, $ErrorAction)
    if ($Scope -ne "CurrentUser" -or $ExecutionPolicy -ne "RemoteSigned") {{ throw "Unexpected policy change" }}
    $script:Changed = $true
}}
# -CanPrompt $false: a forced preference must not depend on a console.
$result = Enable-ACORNProfilePolicy -Preference "{preference}" -CanPrompt $false
@{{ ready = $result; changed = $script:Changed; asked = $script:Asked }} | ConvertTo-Json -Compress
'''
    result = subprocess.run([POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout.strip().splitlines()[-1])
    assert payload == {"ready": ready, "changed": changed, "asked": asked}
