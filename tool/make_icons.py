#!/usr/bin/env python3
"""生成应用图标：Android mipmap / adaptive icon、Windows exe 图标、托盘图标。

设计：深蓝渐变圆角底 + 白色 Wi-Fi 弧 + 绿色在线徽章。
运行：python3 tool/make_icons.py
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
DESIGN = 1024
SS = 4  # 超采样倍率

BLUE = (37, 99, 235)
NAVY = (10, 18, 48)
GREEN = (34, 197, 94)
WHITE = (255, 255, 255)

ANDROID_LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ANDROID_FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def gradient(size: int) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / (size - 1)
    t = np.clip(0.72 * y + 0.28 * x, 0.0, 1.0)[..., None]
    top = np.array(BLUE, dtype=np.float32)
    bottom = np.array(NAVY, dtype=np.float32)
    rgb = top * (1.0 - t) + bottom * t
    return Image.fromarray(rgb.round().astype(np.uint8), "RGB").convert("RGBA")


def rounded_mask(size: int, radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=radius, fill=255
    )
    return mask


def add_glow(base: Image.Image) -> Image.Image:
    size = base.width
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse(
        (-size * 0.3, -size * 0.5, size * 0.85, size * 0.55), fill=70
    )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.09))
    layer = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    layer.putalpha(glow)
    return Image.alpha_composite(base, layer)


def draw_wifi(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    k: float,
    *,
    color=WHITE,
    arcs=3,
    width: float = 62,
    dot: float = 56,
    radii=(140, 285, 430),
) -> None:
    for radius in radii[:arcs]:
        r = radius * k
        w = width * k
        box = (cx - r, cy - r, cx + r, cy + r)
        draw.arc(box, 218, 322, fill=color, width=int(round(w)))
        for angle in (218, 322):
            ex = cx + r * math.cos(math.radians(angle))
            ey = cy + r * math.sin(math.radians(angle))
            draw.ellipse(
                (ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2), fill=color
            )
    dr = dot * k
    draw.ellipse((cx - dr, cy - dr, cx + dr, cy + dr), fill=color)


def draw_check(draw: ImageDraw.ImageDraw, cx: float, cy: float, k: float) -> None:
    pts = [
        (cx - 52 * k, cy + 2 * k),
        (cx - 14 * k, cy + 42 * k),
        (cx + 58 * k, cy - 48 * k),
    ]
    w = int(round(26 * k))
    draw.line(pts, fill=WHITE, width=w, joint="curve")
    for px, py in (pts[0], pts[-1]):
        draw.ellipse((px - w / 2, py - w / 2, px + w / 2, py + w / 2), fill=WHITE)


def draw_badge(
    draw: ImageDraw.ImageDraw, cx: float, cy: float, k: float, ring: tuple | None
) -> None:
    if ring is not None:
        rr = 156 * k
        draw.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=ring)
    green = 132 * k
    draw.ellipse(
        (cx - green, cy - green, cx + green, cy + green), fill=GREEN
    )
    draw_check(draw, cx, cy, k)


def render_app_icon(size: int = DESIGN * SS) -> Image.Image:
    """完整应用图标：渐变圆角底 + Wi-Fi + 在线徽章。"""
    k = size / DESIGN
    base = gradient(DESIGN).resize((size, size), Image.BICUBIC)
    base = add_glow(base)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(base, (0, 0), rounded_mask(size, 232 * k))

    draw = ImageDraw.Draw(canvas)
    draw_wifi(draw, 512 * k, 706 * k, k)
    draw_badge(draw, 790 * k, 796 * k, k, ring=NAVY)
    return canvas


def render_foreground(size: int) -> Image.Image:
    """Android adaptive icon 前景：透明底，内容缩到安全区内。"""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    s = 0.66
    k = size / DESIGN * s
    cx = size / 2
    cy = size / 2 + (706 - 512) * k
    draw_wifi(draw, cx, cy, k)
    draw_badge(draw, cx + (790 - 512) * k, cy + (796 - 706) * k, k, ring=None)
    return canvas


def render_tray(size: int = 1024) -> Image.Image:
    """托盘图标：深蓝圆底 + 两条加粗 Wi-Fi + 绿点（小尺寸可读）。"""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    k = size / 256
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((4 * k, 4 * k, 252 * k, 252 * k), fill=NAVY)
    cx, cy = 128 * k, 168 * k
    draw_wifi(draw, cx, cy, k, arcs=2, width=24, dot=22, radii=(52, 104, 156))
    dot = 24 * k
    draw.ellipse(
        (214 * k - dot, 214 * k - dot, 214 * k + dot, 214 * k + dot), fill=GREEN
    )
    return canvas


def save_png(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path)


def write_android_xml() -> None:
    drawable = RES / "drawable/ic_launcher_background.xml"
    drawable.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="#2563EB"
        android:endColor="#0A1230"
        android:type="linear" />
</shape>
""",
        encoding="utf-8",
    )
    adaptive = RES / "mipmap-anydpi-v26/ic_launcher.xml"
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    adaptive.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
""",
        encoding="utf-8",
    )
    # Android 13 主题图标（只取前景的 alpha 通道着色）
    mono = RES / "mipmap-anydpi-v33/ic_launcher.xml"
    mono.parent.mkdir(parents=True, exist_ok=True)
    mono.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
""",
        encoding="utf-8",
    )


def main() -> None:
    icon = render_app_icon()
    save_png(icon, ROOT / "assets/icon/app_icon.png", 1024)

    for density, px in ANDROID_LEGACY.items():
        save_png(icon, RES / f"mipmap-{density}/ic_launcher.png", px)

    foreground = render_foreground(1024)
    for density, px in ANDROID_FOREGROUND.items():
        save_png(foreground, RES / f"mipmap-{density}/ic_launcher_foreground.png", px)

    write_android_xml()

    icon_ico = [16, 24, 32, 48, 64, 128, 256]
    icon.resize((256, 256), Image.LANCZOS).save(
        ROOT / "windows/runner/resources/app_icon.ico",
        format="ICO",
        sizes=[(s, s) for s in icon_ico],
    )
    render_tray().resize((256, 256), Image.LANCZOS).save(
        ROOT / "assets/tray.ico",
        format="ICO",
        sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64)],
    )
    print("icons written")


if __name__ == "__main__":
    main()
