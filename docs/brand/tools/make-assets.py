#!/usr/bin/env python3
"""Regenerates the Stillbreak brand assets that are drawn, not captured:
social-preview.png, dmg-background*.png/.tiff and the favicon set.

Needs macOS (SF Pro at /System/Library/Fonts/SFNS.ttf, tiffutil), Pillow and
rsvg-convert (brew install librsvg). Screenshots in ../screenshots are real
captures and are not produced here.
"""
import re
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[3]
BRAND = ROOT / "docs" / "brand"
ICON_SVG = ROOT / "Assets" / "AppIcon" / "AppIcon-1024.svg"
ICON_SMALL_SVG = ROOT / "Assets" / "AppIcon" / "AppIcon-small-sizes.svg"
SF = "/System/Library/Fonts/SFNS.ttf"

BLUE = (10, 132, 255)
BLUE_DEEP = (5, 86, 214)
RED = (255, 69, 58)


def font(size, weight):
    f = ImageFont.truetype(SF, size)
    # axes: Width, Optical Size, GRAD, Weight
    f.set_variation_by_axes([100, min(96, max(17, size)), 400, weight])
    return f


def rsvg(svg_text, size, out):
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as t:
        t.write(svg_text)
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), t.name, "-o", str(out)],
        check=True,
    )
    Path(t.name).unlink()


def render_icon(size, path=ICON_SVG):
    out = Path(tempfile.mkstemp(suffix=".png")[1])
    rsvg(path.read_text(), size, out)
    img = Image.open(out).convert("RGBA")
    out.unlink()
    return img


def vgrad(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


# ---------------------------------------------------------------- social preview
def social_preview():
    W, H, S = 1280, 640, 2
    img = vgrad((W * S, H * S), (22, 24, 30), (11, 12, 15)).convert("RGBA")

    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        (-40 * S, 40 * S, 640 * S, 720 * S), fill=BLUE + (70,)
    )
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(120 * S)))

    icon = render_icon(400 * S)
    img.alpha_composite(icon, (96 * S, (H * S - icon.height) // 2))

    d = ImageDraw.Draw(img)
    x = 560 * S
    d.text((x, 150 * S), "Stillbreak", font=font(132 * S, 700), fill=(255, 255, 255))
    d.text(
        (x, 318 * S),
        "Break reminders that follow your",
        font=font(40 * S, 500),
        fill=(220, 224, 232),
    )
    d.text(
        (x, 370 * S),
        "real keyboard and mouse activity.",
        font=font(40 * S, 500),
        fill=(220, 224, 232),
    )
    d.text(
        (x, 450 * S),
        "No Accessibility permission  ·  No tracking  ·  No account",
        font=font(26 * S, 500),
        fill=(150, 157, 170),
    )
    d.text(
        (x, 510 * S),
        "Free and open source menu bar app for macOS 14+",
        font=font(22 * S, 400),
        fill=(110, 117, 130),
    )

    # Activity stripe echoing the Dashboard: blue work blocks, red overtime tail.
    bars = [(0, 150, 0), (170, 120, 30), (310, 180, 0), (510, 90, 45), (620, 150, 0)]
    y0 = 586
    for i, (bx, bw, over) in enumerate(bars):
        left = x + bx * S * 0.8
        d.rounded_rectangle(
            (left, y0 * S, left + bw * S * 0.8, (y0 + 10) * S), 5 * S, fill=BLUE
        )
        if over:
            r0 = left + (bw - over) * S * 0.8
            d.rounded_rectangle(
                (r0, y0 * S, left + bw * S * 0.8, (y0 + 10) * S), 5 * S, fill=RED
            )

    img.convert("RGB").resize((W, H), Image.LANCZOS).save(
        BRAND / "social-preview.png", optimize=True
    )


# ---------------------------------------------------------------- DMG background
def dmg_background(scale):
    W, H, K = 660, 400, 4
    S = scale * K
    img = vgrad((W * S, H * S), (250, 251, 253), (232, 236, 242)).convert("RGBA")
    d = ImageDraw.Draw(img)

    title = "Drag Stillbreak to Applications"
    f = font(26 * S, 600)
    w = d.textlength(title, font=f)
    d.text(((W * S - w) / 2, 52 * S), title, font=f, fill=(29, 29, 31))

    # Dashed arrow between the two icon slots (icons sit at x=165 and x=495, y=205).
    y = 205 * S
    x0, x1 = 250 * S, 405 * S
    dash, gap = 16 * S, 12 * S
    x_ = x0
    while x_ < x1 - dash:
        d.rounded_rectangle((x_, y - 3 * S, x_ + dash, y + 3 * S), 3 * S, fill=BLUE)
        x_ += dash + gap
    tip = 420 * S
    d.line([(tip - 22 * S, y - 20 * S), (tip, y), (tip - 22 * S, y + 20 * S)],
           fill=BLUE, width=7 * S, joint="curve")
    for p in [(tip - 22 * S, y - 20 * S), (tip, y), (tip - 22 * S, y + 20 * S)]:
        d.ellipse((p[0] - 3.5 * S, p[1] - 3.5 * S, p[0] + 3.5 * S, p[1] + 3.5 * S), fill=BLUE)

    note = "Not notarized: macOS asks you to confirm the first launch. Steps are in the README."
    f2 = font(12 * S, 400)
    w2 = d.textlength(note, font=f2)
    d.text(((W * S - w2) / 2, 362 * S), note, font=f2, fill=(110, 110, 115))

    out = img.convert("RGB").resize((W * scale, H * scale), Image.LANCZOS)
    name = "dmg-background.png" if scale == 1 else f"dmg-background@{scale}x.png"
    out.save(BRAND / name, optimize=True)


# ---------------------------------------------------------------- favicons
def favicon_svg(body, glyph_variant):
    """Icon cropped to the squircle body (no padding, no drop shadow)."""
    svg = glyph_variant.read_text()
    svg = svg.replace(' filter="url(#shadow)"', "")
    svg = re.sub(r"<filter id=\"shadow\".*?</filter>", "", svg, flags=re.S)
    svg = svg.replace('width="1024" height="1024" viewBox="0 0 1024 1024"',
                      'width="824" height="824" viewBox="100 100 824 824"')
    return svg


def touch_svg():
    """Full-bleed square for apple-touch-icon / PWA icons (iOS applies its own mask)."""
    svg = ICON_SVG.read_text()
    svg = re.sub(r"<filter id=\"shadow\".*?</filter>", "", svg, flags=re.S)
    svg = re.sub(
        r'<path d="[^"]+" fill="url\(#bg\)" filter="url\(#shadow\)"/>',
        '<rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>',
        svg,
    )
    svg = re.sub(
        r'<path d="[^"]+" fill="url\(#sheen\)"/>',
        '<rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/>',
        svg,
    )
    svg = svg.replace('width="1024" height="1024" viewBox="0 0 1024 1024"',
                      'width="824" height="824" viewBox="100 100 824 824"')
    return svg


def favicons():
    out = BRAND / "favicon"
    out.mkdir(exist_ok=True)
    small = favicon_svg(None, ICON_SMALL_SVG)
    (out / "favicon.svg").write_text(favicon_svg(None, ICON_SVG))

    def png(svg, size, name):
        rsvg(svg, size, out / name)

    png(small, 16, "favicon-16x16.png")
    png(small, 32, "favicon-32x32.png")
    png(small, 48, "favicon-48x48.png")
    png(touch_svg(), 180, "apple-touch-icon.png")
    png(touch_svg(), 192, "icon-192.png")
    png(touch_svg(), 512, "icon-512.png")

    frames = [Image.open(out / f"favicon-{n}x{n}.png").convert("RGBA") for n in (16, 32, 48)]
    frames[2].save(out / "favicon.ico", append_images=frames[:2], sizes=[(16, 16), (32, 32), (48, 48)])

    (out / "site.webmanifest").write_text(
        '{\n'
        '  "name": "Stillbreak",\n'
        '  "short_name": "Stillbreak",\n'
        '  "icons": [\n'
        '    { "src": "icon-192.png", "sizes": "192x192", "type": "image/png" },\n'
        '    { "src": "icon-512.png", "sizes": "512x512", "type": "image/png" }\n'
        '  ],\n'
        '  "theme_color": "#0A84FF",\n'
        '  "background_color": "#FFFFFF",\n'
        '  "display": "browser"\n'
        '}\n'
    )


if __name__ == "__main__":
    social_preview()
    dmg_background(1)
    dmg_background(2)
    subprocess.run(
        ["tiffutil", "-cathidpicheck", str(BRAND / "dmg-background.png"),
         str(BRAND / "dmg-background@2x.png"), "-out", str(BRAND / "dmg-background.tiff")],
        check=True,
    )
    favicons()
