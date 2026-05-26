#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "appstore-assets/source/cribble-knowledge-base-1440x900.png"
ICON = ROOT / "Sources/Cribble/Resources/AppIconLight.png"
OUT_DIR = ROOT / "appstore-assets/screenshots"

W, H = 1440, 900
FONT = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"

INK = (18, 31, 45)
MUTED = (78, 95, 111)
BLUE = (74, 150, 236)
BLUE_2 = (121, 190, 252)
GLASS = (247, 252, 255)


def font(size: int, mono: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(MONO if mono else FONT, size=size)


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def bg() -> Image.Image:
    top = (250, 253, 255)
    bottom = (208, 230, 249)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        for x in range(W):
            t2 = min(1, max(0, t * 0.82 + (x / W) * 0.18))
            px[x, y] = tuple(lerp(top[i], bottom[i], t2) for i in range(3)) + (255,)

    haze = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(haze)
    d.rounded_rectangle((780, -160, 1540, 520), radius=160, fill=(*BLUE_2, 42))
    d.rounded_rectangle((-260, 610, 680, 1080), radius=180, fill=(*BLUE, 20))
    d.polygon([(970, -80), (1460, -80), (1180, 900), (760, 900)], fill=(255, 255, 255, 62))
    haze = haze.filter(ImageFilter.GaussianBlur(32))
    return Image.alpha_composite(img, haze)


def wrapped(d: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, size: int, fill: tuple[int, int, int],
            width: int, gap: int = 8) -> int:
    f = font(size)
    lines: list[str] = []
    current = ""
    for word in text.split():
        candidate = f"{current} {word}".strip()
        if not current or d.textlength(candidate, font=f) <= width:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    y = xy[1]
    for line in lines:
        d.text((xy[0], y), line, font=f, fill=fill)
        y += size + gap
    return y


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img.convert("RGBA"), (0, 0), mask)
    return out


def shadow(base: Image.Image, img: Image.Image, xy: tuple[int, int], blur: int = 34, alpha: int = 116) -> None:
    mask = img.getchannel("A")
    sh = Image.new("RGBA", img.size, (20, 48, 74, alpha))
    sh.putalpha(mask)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(sh, (xy[0], xy[1] + 22))
    base.alpha_composite(img, xy)


def app_window(source: Image.Image, width: int) -> Image.Image:
    height = round(source.height * width / source.width)
    shot = source.resize((width, height), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (width + 26, height + 26), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((0, 0, out.width - 1, out.height - 1), radius=34,
                        fill=(30, 32, 32, 255), outline=(255, 255, 255, 72), width=1)
    out.alpha_composite(rounded(shot, 24), (13, 13))
    return out


def title_band(base: Image.Image, eyebrow: str, title: str, body: str) -> None:
    d = ImageDraw.Draw(base)
    raw_icon = Image.open(ICON).convert("RGBA").resize((76, 76), Image.Resampling.LANCZOS)
    icon_shadow = Image.new("RGBA", raw_icon.size, (38, 82, 132, 86))
    icon_shadow.putalpha(raw_icon.getchannel("A").filter(ImageFilter.GaussianBlur(8)))
    base.alpha_composite(icon_shadow, (76, 62))
    base.alpha_composite(raw_icon, (76, 52))
    d.text((166, 64), "Cribble", font=font(31), fill=INK)
    d.text((167, 102), "Markdown KB Manager", font=font(17), fill=MUTED)

    d.text((470, 58), eyebrow, font=font(22), fill=BLUE)
    wrapped(d, (470, 96), title, 39, INK, 510, 5)
    wrapped(d, (1016, 86), body, 21, MUTED, 315, 7)


def button(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str, primary: bool = False) -> None:
    fill = (*BLUE, 255) if primary else (255, 255, 255, 218)
    outline = (*BLUE, 80) if not primary else (*BLUE, 255)
    text = (255, 255, 255) if primary else INK
    d.rounded_rectangle(box, radius=18, fill=fill, outline=outline, width=1)
    tw = d.textlength(label, font=font(20))
    d.text((box[0] + (box[2] - box[0] - tw) / 2, box[1] + 14), label, font=font(20), fill=text)


def readme_overlay() -> Image.Image:
    panel = Image.new("RGBA", (620, 330), (0, 0, 0, 0))
    d = ImageDraw.Draw(panel)
    d.rounded_rectangle((0, 0, 619, 329), radius=28, fill=(*GLASS, 244), outline=(255, 255, 255, 255))
    d.text((36, 32), "This README is empty", font=font(30), fill=INK)
    d.line((36, 84, 584, 84), fill=(108, 144, 174, 120), width=1)
    wrapped(d, (38, 112), "Generate a folder overview, contents list, and useful links from the Markdown files in this folder.",
            21, MUTED, 500, 7)
    button(d, (38, 222, 238, 276), "Use Codex", True)
    button(d, (258, 222, 468, 276), "Use Claude")
    d.rounded_rectangle((38, 296, 582, 318), radius=11, fill=(210, 230, 245, 230))
    d.text((58, 299), "Preview the AI patch before applying it.", font=font(14), fill=MUTED)
    return panel


def diff_overlay() -> Image.Image:
    panel = Image.new("RGBA", (760, 430), (0, 0, 0, 0))
    d = ImageDraw.Draw(panel)
    d.rounded_rectangle((0, 0, 759, 429), radius=28, fill=(*GLASS, 246), outline=(255, 255, 255, 255))
    d.text((36, 30), "Review AI Link Changes", font=font(30), fill=INK)
    button(d, (574, 24, 718, 66), "Apply", True)
    d.line((36, 84, 724, 84), fill=(108, 144, 174, 120), width=1)
    d.rounded_rectangle((36, 112, 724, 336), radius=16, fill=(8, 10, 12, 255))
    lines = [
        ("--- a/Research/Markdown Rendering.md", (156, 160, 164)),
        ("+++ b/Research/Markdown Rendering.md", (156, 160, 164)),
        ("@@ -12,3 +12,4 @@", (126, 167, 230)),
        ("-Compare renderer behavior with the project plan.", (238, 135, 135)),
        ("+Compare renderer behavior with [[Project Plan]].", (112, 233, 165)),
        ("+See also [[Home#Highlights]] for navigation goals.", (112, 233, 165)),
    ]
    y = 132
    for line, fill in lines:
        d.text((62, y), line, font=font(18, True), fill=fill)
        y += 32
    button(d, (36, 362, 176, 400), "Discard")
    d.rounded_rectangle((194, 362, 436, 400), radius=18, fill=(214, 233, 247, 230), outline=(*BLUE, 50))
    d.text((218, 372), "Preview before mutation", font=font(16), fill=MUTED)
    return panel


def linked_overlay() -> Image.Image:
    panel = Image.new("RGBA", (520, 310), (0, 0, 0, 0))
    d = ImageDraw.Draw(panel)
    d.rounded_rectangle((0, 0, 519, 309), radius=28, fill=(*GLASS, 246), outline=(255, 255, 255, 255))
    d.text((36, 30), "Linked files", font=font(30), fill=INK)
    d.line((36, 84, 484, 84), fill=(108, 144, 174, 120), width=1)
    rows = [
        ("Markdown Rendering", "Research/Markdown Rendering.md", BLUE),
        ("Project Plan", "Projects/Project Plan.md", BLUE_2),
    ]
    y = 112
    for title, subtitle, color in rows:
        d.rounded_rectangle((36, y, 484, y + 68), radius=18, fill=(255, 255, 255, 238), outline=(112, 158, 196, 110))
        d.text((66, y + 14), title, font=font(20), fill=INK)
        d.text((66, y + 41), subtitle, font=font(14), fill=MUTED)
        d.ellipse((442, y + 26, 460, y + 44), fill=color)
        y += 86
    return panel


def app_hero(base: Image.Image, source: Image.Image, width: int = 1120, y: int = 190) -> tuple[int, int, Image.Image]:
    window = app_window(source, width)
    x = (W - window.width) // 2
    shadow(base, window, (x, y), 42, 125)
    return x, y, window


def slide_native(source: Image.Image) -> Image.Image:
    base = bg()
    title_band(
        base,
        "Native Markdown",
        "Your Markdown knowledge base, native on Mac",
        "Browse folders, read polished Markdown, and keep files plain.",
    )
    app_hero(base, source, 1020, 230)
    return base.convert("RGB")


def slide_readme(source: Image.Image) -> Image.Image:
    base = bg()
    title_band(
        base,
        "AI README builder",
        "Use AI to add useful README overviews",
        "Generate contents, gist, and useful links from your local Markdown.",
    )
    x, y, _ = app_hero(base, source, 1000, 245)
    panel = readme_overlay()
    shadow(base, panel, (x + 330, y + 250), 26, 115)
    return base.convert("RGB")


def slide_links(source: Image.Image) -> Image.Image:
    base = bg()
    title_band(
        base,
        "AI link suggestions",
        "Review AI-suggested wiki links before applying",
        "Cribble shows a unified diff so changes stay transparent.",
    )
    x, y, _ = app_hero(base, source, 1000, 245)
    panel = diff_overlay()
    shadow(base, panel, (x + 190, y + 182), 26, 120)
    return base.convert("RGB")


def slide_linked_files(source: Image.Image) -> Image.Image:
    base = bg()
    title_band(
        base,
        "Linked file navigation",
        "Related notes stay one click away",
        "Linked-file cards turn wiki links into fast local navigation.",
    )
    x, y, _ = app_hero(base, source, 1000, 245)
    panel = linked_overlay()
    shadow(base, panel, (x + 470, y + 88), 26, 112)
    return base.convert("RGB")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGB")
    outputs = [
        ("01-native-markdown-knowledge-base-1440x900.png", slide_native(source)),
        ("02-ai-readme-builder-1440x900.png", slide_readme(source)),
        ("03-ai-link-suggestions-1440x900.png", slide_links(source)),
        ("04-linked-file-navigation-1440x900.png", slide_linked_files(source)),
    ]
    for name, image in outputs:
        path = OUT_DIR / name
        image.save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main()
