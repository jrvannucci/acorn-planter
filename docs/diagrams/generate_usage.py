"""Generate the administrator-to-user ACORN usage graphic."""
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).parent


def build():
    parts = ['''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1570" viewBox="0 0 1200 1570" role="img" aria-labelledby="title desc">
<title id="title">From one shared planter to each person's development suite</title>
<desc id="desc">An administrator declares and builds the offline resource superset, transfers the complete distribution to a shared location, and supplies validated user profiles. Users install ACORN once and manage their own environments, tools and repositories through the CLI. Shared downloads stay on the network; each user's installed suite lives in their acorn folder.</desc>
<defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10Z" fill="#488475"/></marker></defs>
<rect width="1200" height="1570" rx="24" fill="#F5F7F2"/>
<g font-family="Arial, Helvetica, sans-serif">
''']

    def label(x, y, value, size=20, fill="#173F35", bold=False, mono=False):
        font = ' font-family="Consolas, monospace"' if mono else ''
        parts.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{700 if bold else 400}"{font}>{escape(value)}</text>')

    def box(x, y, w, h, fill="#FFFFFF", stroke="#D7E1D8", radius=16):
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}"/>')

    def icon(x, y, kind):
        parts.append(f'<g transform="translate({x} {y})" fill="none" stroke="#397966" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">')
        if kind == 'build':
            parts.append('<path d="M0 16L28 2L56 16L28 30Z M0 16V47L28 62L56 47V16 M28 30V62 M14 9L42 23"/>')
        elif kind == 'share':
            parts.append('<rect x="2" y="2" width="52" height="22" rx="5"/><rect x="2" y="33" width="52" height="22" rx="5"/><path d="M12 13H14 M12 44H14 M24 13H44 M24 44H44"/>')
        else:
            parts.append('<rect x="0" y="0" width="58" height="42" rx="5"/><path d="M29 43V55 M14 55H44 M12 13L20 21L12 29 M28 29H42"/>')
        parts.append('</g>')

    def stage(y, number, role, title, subtitle, kind, height):
        box(36, y, 1128, height)
        box(56, y+24, 48, 48, '#173F35', '#173F35', 24)
        label(72, y+56, str(number), 25, '#FFFFFF', True)
        label(124, y+43, role, 14, '#547467', True)
        label(124, y+78, title, 30, bold=True)
        label(124, y+110, subtitle, 19, '#53665C')
        icon(1060, y+31, kind)

    label(44, 49, 'ACORN  /  HOW IT WORKS', 16, '#397966', True)
    label(44, 99, 'One shared planter.', 42, bold=True)
    label(44, 148, 'A development suite for every user.', 42, bold=True)
    label(44, 186, 'Global Python environments and development suites, ready when you are.', 23, '#53665C')

    stage(220, 1, 'ADMINISTRATOR  ·  CONNECTED MACHINE', 'Build what your users can install',
          'The offline bundle is the resource superset. Profiles must fit what it contains.', 'build', 340)
    box(62, 356, 515, 155, '#EEF4ED', '#EEF4ED')
    label(82, 387, 'DECLARE', 13, '#547467', True)
    label(82, 419, 'acorn-planter/offline-bundle.toml', 20, bold=True, mono=True)
    label(82, 450, 'Python versions, package versions and dependencies,', 18)
    label(82, 478, 'native tools, editor and required extensions.', 18)
    box(597, 356, 541, 155, '#EEF4ED', '#EEF4ED')
    label(617, 387, 'RUN', 13, '#547467', True)
    label(617, 419, 'GET_STARTED_OFFLINE_BUNDLE/', 19, mono=True)
    label(617, 447, 'offline-bundler.cmd', 22, bold=True, mono=True)
    label(617, 479, 'Download resources; check profiles and editor settings.', 18)
    label(63, 539, 'Result: a compressed distribution + UNPACK.cmd, with an inventory and license manifest.', 19, bold=True)

    parts.append('<path d="M92 562V598" stroke="#488475" stroke-width="3" marker-end="url(#arrow)"/>')
    label(123, 588, 'TRANSFER THE COMPLETE DISTRIBUTION TO THE OFFLINE NETWORK', 14, '#547467', True)

    stage(610, 2, 'ADMINISTRATOR  ·  SHARED NETWORK LOCATION', 'Publish the planter and choose who gets what',
          'Extract the bundle, configure network paths, and validate the profiles you supply.', 'share', 365)
    box(62, 746, 515, 170, '#EEF4ED', '#EEF4ED')
    label(82, 777, 'SHARED DISTRIBUTION', 13, '#547467', True)
    label(82, 809, 'GET_STARTED/  +  acorn-planter/', 20, bold=True, mono=True)
    label(82, 840, 'Planter: config, profiles, installers and source;', 18)
    label(82, 868, 'wheels, Python builds, conda channel and native tools.', 18)
    label(82, 895, 'Keep both GET_STARTED folders with the planter.', 17, '#53665C')
    box(597, 746, 541, 170, '#EEF4ED', '#EEF4ED')
    label(617, 777, 'ADMINISTRATOR CONTROLS', 13, '#547467', True)
    label(617, 809, 'global.conf', 20, bold=True, mono=True)
    label(617, 838, 'Shared settings; resource paths may point elsewhere.', 18)
    label(617, 866, 'installation-profile/*.toml', 20, bold=True, mono=True)
    label(617, 895, 'Default for everyone; extra profiles select users.', 18)
    label(63, 950, 'New profiles can be created inside the air gap and checked against the existing bundle.', 19, bold=True)

    parts.append('<path d="M92 977V1013" stroke="#488475" stroke-width="3" marker-end="url(#arrow)"/>')
    label(123, 1004, 'USERS INSTALL FROM THE SHARE  ·  SHARED DOWNLOADS STAY THERE', 14, '#547467', True)

    stage(1025, 3, 'USER  ·  THEIR OWN MACHINE', 'Install once. Use ACORN every day.',
          'Run GET_STARTED/install.cmd, then open a fresh terminal to use your personal suite.', 'user', 439)
    box(62, 1161, 515, 238, '#17342D', '#17342D')
    label(82, 1193, 'YOUR TERMINAL', 13, '#A7D5BE', True)
    label(82, 1233, 'acorn activate dev', 23, '#FFFFFF', mono=True)
    label(82, 1262, 'Work in the environment you need.', 18, '#B8CEC1')
    label(82, 1301, 'acorn install pandas', 23, '#FFFFFF', mono=True)
    label(82, 1330, 'Add packages available from your configured source.', 17, '#B8CEC1')
    label(82, 1370, 'acorn vscode', 23, '#FFFFFF', mono=True)
    box(597, 1161, 541, 238, '#EEF4ED', '#EEF4ED')
    label(617, 1193, 'YOUR INSTALLED SUITE  ·  DEFAULT LOCATION', 13, '#547467', True)
    label(617, 1227, '~/acorn/', 24, bold=True, mono=True)
    label(637, 1260, 'python/       interpreters + environments', 18, mono=True)
    label(637, 1292, 'extensions/   editor + Python applications', 18, mono=True)
    label(637, 1324, 'repo/         your cloned repositories', 18, mono=True)
    label(637, 1356, 'system/       CLI, settings, logs + caches', 18, mono=True)
    label(617, 1383, 'Each user has their own installation.', 17, '#53665C')
    label(63, 1438, 'Repositories come from your internal network. The offline builder does not bundle them.', 19, bold=True)
    label(44, 1508, 'Connected installations can use online sources directly; the CLI and personal suite are the same.', 19, '#53665C')
    label(44, 1541, 'PLAN → BUILD → DISTRIBUTE → INSTALL → WORK', 16, '#397966', True)
    parts.append('</g></svg>')
    (OUT / 'usage-workflow.svg').write_text('\n'.join(parts), encoding='utf-8')


if __name__ == '__main__':
    build()
