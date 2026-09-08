"""Render the illustrated ACORN user walkthrough. Requires Pillow; run manually."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "_static"
W, H = 1120, 760
BG = "#F4F6F1"
INK = "#173F35"
GREEN = "#397966"
MUTED = "#617467"
FONT = Path("C:/Windows/Fonts")


def font(size, bold=False, mono=False):
    name = ("consolab.ttf" if bold else "consola.ttf") if mono else ("arialbd.ttf" if bold else "arial.ttf")
    return ImageFont.truetype(str(FONT / name), size)


def render(scene, progress):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)

    def txt(x, y, value, size=22, color=INK, bold=False, mono=False):
        d.text((x, y), value, font=font(size, bold, mono), fill=color)

    def box(bounds, fill="white", outline=None, radius=18):
        d.rounded_rectangle(bounds, radius, fill=fill, outline=outline, width=2)

    txt(36, 24, "ACORN  /  YOUR FIRST SESSION", 18, GREEN, True)
    txt(36, 62, TITLES[scene], 36, bold=True)
    txt(36, 113, SUBTITLES[scene], 21, MUTED)
    for i in range(6):
        x = 36 + i * 176
        box((x, 161, x+164, 168), GREEN if i <= scene else "#DCE4D9", radius=3)
        txt(x, 183, STEPS[i], 17, GREEN if i == scene else MUTED, i == scene)

    if scene == 1:
        box((36, 233, 542, 601), outline="#D6E0D5")
        txt(60, 258, "READ SETTINGS + SELECT PROFILES", 17, GREEN, True)
        txt(60, 306, "global.conf", 25, bold=True, mono=True)
        txt(60, 345, "Use the organization's network resources.", 21, MUTED)
        txt(60, 403, "profile.toml  →  everyone", 23, bold=True, mono=True)
        txt(60, 442, "dev environment + VS Code", 22)
        txt(60, 499, "analysis.toml  →  Alice", 23, bold=True, mono=True)
        txt(60, 538, "analysis environment + pandas + NumPy", 21)
        box((564, 233, 1084, 601), "#142F29")
        txt(589, 258, "THE INSTALLER SETS UP", 17, "#ACCCBA", True)
        tasks = ["ACORN CLI + Python", "dev + analysis environments", "Each environment's packages", "VS Code + configured extensions"]
        active = min(3, int(progress * 4))
        for j, task in enumerate(tasks):
            y = 319 + j * 61
            color = "#FFFFFF" if j <= active else "#809A8B"
            if j < active or progress == 1:
                d.line((593, y+15, 599, y+21, 610, y+7), fill="#94D2A7", width=3)
            else:
                txt(591, y, "→" if j == active else "·", 24, "#94D2A7")
            txt(624, y, task, 21, color)
        caption="Your profiles decide what gets installed. Packages come from the configured sources."
    elif scene == 2:
        box((36, 233, 542, 601), outline="#D6E0D5")
        txt(60, 258, "STAYS ON THE NETWORK", 17, GREEN, True)
        txt(60, 309, "acorn-planter/", 27, bold=True, mono=True)
        for j, line in enumerate(["Shared configuration + profiles", "Wheel collection", "Python archives", "Native tool downloads"]):
            txt(60, 369+j*48, line, 23)
        box((564, 233, 1084, 601), "#142F29")
        txt(589, 258, "INSTALLED FOR ALICE", 17, "#ACCCBA", True)
        txt(589, 309, "~/acorn/", 27, "#FFFFFF", True, True)
        for j, line in enumerate(["python/venvs/dev", "python/venvs/analysis", "extensions/vscode", "system/  CLI + settings + caches"]):
            txt(589, 369+j*48, line, 22, "#FFFFFF", mono=True)
        caption="Open a fresh terminal. Your tools are installed; the shared download collection stays put."
    elif scene == 0:
        box((36, 233, 480, 601), outline="#D6E0D5")
        box((640, 233, 1084, 601), outline="#D6E0D5")
        txt(60, 257, "ORGANIZATION'S SHARED PLANTER", 17, GREEN, True)
        txt(60, 296, "S:\\ACORN", 27, bold=True, mono=True)
        lines = ["GET_STARTED/", "  install.cmd", "acorn-planter/", "  global.conf", "  installation-profile/", "  wheels/ + Python + tools"]
        for j,line in enumerate(lines):
            if j == 1 and scene == 0:
                box((56, 359, 456, 393), "#DFEEE1", radius=6)
            txt(64, 331+j*35, line, 20, mono=True)
        txt(664, 257, "ALICE'S COMPUTER", 17, GREEN, True)
        # Laptop illustration.
        box((728, 301, 999, 463), "#17342D", radius=12)
        d.line((702, 478, 1024, 478), fill=GREEN, width=9)
        txt(750, 328, "ACORN", 27, "#DDF2E3", True)
        screen = ["Ready to install", "Installing suite...", "Ready to work"][scene]
        txt(750, 376, screen, 18, "#DDF2E3")
        if scene == 1:
            box((750, 419, 976, 432), "#36554B", radius=4)
            box((750, 419, 752+int(224*progress), 432), "#9AD4AB", radius=4)
        txt(664, 507, "C:\\Users\\alice\\acorn", 22, bold=True, mono=True)
        txt(664, 552, ["Run the shared installer.", "Your own tools and environments.", "dev + analysis + VS Code"][scene], 19, MUTED)
        d.line((500, 395, 619, 395), fill=GREEN, width=3)
        d.polygon([(619,395),(607,388),(607,402)],fill=GREEN)
        if scene == 1:
            for offset in [0, .33, .66]:
                x=500+int(((progress*3+offset)%1)*112)
                box((x,386,x+13,404),"#93BE9D",radius=3)
        txt(504, 422, "Install", 19, GREEN, True)
        if scene == 0:
            caption="Run S:\\ACORN\\GET_STARTED\\install.cmd"
        elif scene == 1:
            caption="The installer reads global.conf and applies Alice's assigned profiles."
        else:
            caption="Default profile: dev + VS Code. Alice's opt-in profile: analysis."
    else:
        box((36, 233, 745, 601), "#142F29")
        txt(60, 254, "PowerShell  |  Alice's fresh terminal", 17, "#ACCCBA")
        d.line((60, 291, 720, 291), fill="#36554B", width=1)
        command = COMMANDS[scene-3]
        count=min(len(command),int(progress*len(command)*3.2))
        prefix="PS> " if scene == 3 else "(analysis) PS> "
        txt(60, 321, prefix, 19, "#94D2A7", mono=True)
        # Put long Python command on its own line to stay readable.
        txt(60, 356, command[:count]+("_" if count < len(command) else ""), 20, "#FFFFFF", mono=True)
        if progress > .34:
            if scene == 3:
                txt(60, 418, "(analysis) PS>", 21, "#94D2A7", mono=True)
                txt(60, 488, "Your shell now uses the analysis environment.", 20, "#BCD2C3")
            elif scene == 4:
                txt(60, 418, "6", 25, "#FFFFFF", mono=True)
                txt(60, 488, "NumPy is already installed by Alice's profile.", 20, "#BCD2C3")
            else:
                txt(60, 418, "Open your editor and start working.", 22, "#BCD2C3")
                txt(60, 488, "Select the analysis interpreter in VS Code.", 20, "#BCD2C3")
        box((769, 233, 1084, 601), outline="#D6E0D5")
        txt(791, 257, "YOUR PROFILE AT WORK", 16, GREEN, True)
        txt(791, 305, "analysis", 28, bold=True, mono=True)
        txt(791, 354, "Python environment", 20, MUTED)
        txt(791, 397, "pandas + NumPy", 22, bold=True)
        txt(791, 441, "Available in your venv", 20, MUTED)
        txt(791, 500, "VS Code", 24, bold=True)
        txt(791, 543, "From your default setup", 19, MUTED)
        caption=["Activate a profile environment whenever you need it.", "Use the packages your administrator included. No extra install step.", "Same ACORN commands, with packages and tools supplied by your network."][scene-3]
    box((36, 623, 1084, 685), "#DFEBDD", radius=12)
    txt(55, 644, caption, 21, bold=True)
    txt(36, 715, "Illustrated demo · Example network paths · Setup time shortened", 16, MUTED)
    txt(809, 715, f"{scene+1} / 6   •   loops automatically", 16, MUTED)
    return im


TITLES = ["Start with your organization's planter.", "Your profiles become your personal suite.", "What stays shared. What becomes yours.", "Activate the environment you need.", "Use the packages on your profile.", "Open your editor. Start working."]
SUBTITLES = ["The administrator has already prepared the shared distribution.", "ACORN installs from the configured network resources.", "Shared downloads stay on the network; your installed suite is yours.", "Open a fresh terminal after installation so the acorn command is available.", "This example uses NumPy from Alice's assigned analysis environment.", "VS Code and its extensions come from the prepared distribution."]
STEPS = ["1  Open share", "2  Install", "3  Your suite", "4  Activate", "5  Run Python", "6  Open editor"]
COMMANDS = ["acorn activate analysis", 'python -c "import numpy as np; print(np.arange(4).sum())"', "acorn vscode"]


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    frames=[]
    durations=[]
    for scene in range(6):
        n=20 if scene in (1,3,4,5) else 1
        for k in range(n):
            progress=k/max(1,n-1)
            frames.append(render(scene, progress).quantize(colors=128))
            durations.append(120 if n>1 else 2400)
        # Hold each completed section without slowing down its animation.
        durations[-1] += 1800 if n > 1 else 900
    target=OUT/"acorn-user-demo.gif"
    frames[0].save(target,save_all=True,append_images=frames[1:],duration=durations,loop=0,optimize=True,disposal=2)
    render(3,1).save(OUT/"acorn-user-demo-preview.png")
    print(target)


if __name__ == "__main__":
    build()
