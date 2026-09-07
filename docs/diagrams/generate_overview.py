"""Generate ACORN's product overview graphics for the documentation homepage."""

from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).parent
GREEN = "#1B4332"
PALE = "#E9F5EC"


def text(x, y, label, size=20, color=GREEN, bold=False):
    return (f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" '
            f'font-weight="{700 if bold else 400}">{escape(label)}</text>')


def build():
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 770" '
        'role="img" aria-labelledby="title desc" font-family="Arial, Helvetica, sans-serif">',
        '<title id="title">ACORN: your Python development suite</title>',
        '<desc id="desc">Global settings connect your Python environments, packages, '
        'editors, and tools. Profiles describe suites; offline bundles carry their resources.</desc>',
        '<rect width="1000" height="770" rx="18" fill="#FFFFFF"/>',
        '<g transform="translate(42 27)" stroke="#1B4332" stroke-width="3">'
        '<path d="M8 28 Q7 58 30 69 Q53 58 52 28 Z" fill="#D8A66D"/>'
        '<path d="M3 29 Q4 9 30 9 Q56 9 57 29 Z" fill="#1B4332"/>'
        '<path d="M30 10 Q27 0 36 -2" fill="none" stroke-linecap="round"/></g>',
        text(125, 78, "ACORN", 46, bold=True),
        text(44, 129, "Global Python environments and development suites,", 27, bold=True),
        text(44, 166, "ready when you are.", 27, bold=True),
        text(44, 207, "One CLI. Shared settings across your environments. A suite that fits your work.", 20),
    ]
    rows = [
        ("Configure globally", "global.conf supplies installation settings; acorn config manages your defaults."),
        ("Build your environments", "Manage Python versions, virtual environments, packages, and repositories."),
        ("Bring your development tools", "Connect VS Code, Spyder, Python applications, and conda-forge tools."),
        ("Prepare for offline work", "Bundle resources online, validate profiles, then install on the offline network."),
    ]
    for i, (title, detail) in enumerate(rows):
        y = 240 + i * 104
        parts += [f'<rect x="40" y="{y}" width="920" height="88" rx="12" fill="{PALE}"/>',
                  text(62, y + 33, title, 23, bold=True), text(62, y + 62, detail, 18)]
    parts += [text(44, 704, "Your managed suite lives under ~/acorn", 24, bold=True),
              text(44, 737, "acorn venv dev   ·   acorn install pandas   ·   acorn vscode", 20), '</svg>']
    (OUT / "mission.svg").write_text("\n".join(parts), encoding="utf-8")

    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 390" '
        'role="img" aria-labelledby="title" font-family="Arial, Helvetica, sans-serif">',
        '<title id="title">From shared configuration to your development suite</title>',
        '<rect width="1000" height="390" rx="16" fill="#FFFFFF"/>',
        text(36, 46, "A development suite configured for you", 28, bold=True),
    ]
    rows = [
        ("1  Set your defaults", "Use global.conf for installation and acorn config for ongoing settings."),
        ("2  Choose a profile", "Describe the Python environments, packages, and tools you want."),
        ("3  Start working", "Activate an environment, run your code, and open your editor with acorn."),
    ]
    for i, (title, detail) in enumerate(rows):
        y = 72 + i * 96
        parts += [f'<rect x="32" y="{y}" width="936" height="80" rx="10" fill="{PALE}"/>',
                  text(52, y + 30, title, 22, bold=True), text(52, y + 57, detail, 18)]
    parts += ['</svg>']
    (OUT / "development-suite.svg").write_text("\n".join(parts), encoding="utf-8")


if __name__ == "__main__":
    build()
