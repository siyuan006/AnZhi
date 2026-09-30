import math
import os

from PIL import Image, ImageDraw

BRAND = (30, 111, 217, 255)

DENSITIES = [
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
]

SUPERSAMPLE = 4

SHIELD_ASPECT = 1.15
LEGACY_SHIELD_RATIO = 0.56
FOREGROUND_SHIELD_RATIO = 0.58
LEGACY_CORNER_RATIO = 0.22


def shield_points(cx, cy, width, height):
    half = width / 2.0
    top = cy - height / 2.0
    bottom = cy + height / 2.0
    shoulder = top + 0.46 * height
    corner = 0.09 * width
    points = [(cx, bottom)]

    steps = 64
    for i in range(steps + 1):
        u = i / steps
        y = bottom + (shoulder - bottom) * u
        offset = half * (1.0 - (1.0 - u) ** 2) ** 0.6
        points.append((cx + offset, y))

    points.append((cx + half, top + corner))
    for i in range(1, 25):
        angle = (i / 24.0) * (math.pi / 2.0)
        points.append(
            (
                cx + half - corner + corner * math.cos(angle),
                top + corner - corner * math.sin(angle),
            )
        )
    points.append((cx - half + corner, top))
    for i in range(1, 25):
        angle = math.pi / 2.0 + (i / 24.0) * (math.pi / 2.0)
        points.append(
            (
                cx - half + corner + corner * math.cos(angle),
                top + corner - corner * math.sin(angle),
            )
        )
    points.append((cx - half, top + corner))
    points.append((cx - half, shoulder))

    for i in range(steps + 1):
        u = 1.0 - i / steps
        y = bottom + (shoulder - bottom) * u
        offset = half * (1.0 - (1.0 - u) ** 2) ** 0.6
        points.append((cx - offset, y))

    return points


def draw_shield(size, shield_ratio, background):
    canvas = size * SUPERSAMPLE
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if background is not None:
        radius = int(canvas * LEGACY_CORNER_RATIO)
        draw.rounded_rectangle([0, 0, canvas - 1, canvas - 1], radius, fill=background)

    height = canvas * shield_ratio
    width = height / SHIELD_ASPECT
    points = shield_points(canvas / 2.0, canvas / 2.0, width, height)
    draw.polygon(points, fill=(255, 255, 255, 255))

    return image.resize((size, size), Image.LANCZOS)


def main():
    root = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "android",
        "app",
        "src",
        "main",
        "res",
    )

    for density, size in DENSITIES:
        target = os.path.join(root, "mipmap-" + density)
        os.makedirs(target, exist_ok=True)
        legacy = draw_shield(size, LEGACY_SHIELD_RATIO, BRAND)
        legacy.save(os.path.join(target, "ic_launcher.png"))
        foreground = draw_shield(int(size * 2.25), FOREGROUND_SHIELD_RATIO, None)
        foreground.save(os.path.join(target, "ic_launcher_foreground.png"))
        print(density, size, legacy.size, foreground.size)


if __name__ == "__main__":
    main()
