import math
import struct
import zlib
from pathlib import Path


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path: Path, size: int, rgb: bytes) -> None:
    raw = b"".join(b"\x00" + rgb[y * size * 3 : (y + 1) * size * 3] for y in range(size))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_box(px, py, cx, cy, half_w, half_h, radius):
    dx = abs(px - cx) - half_w + radius
    dy = abs(py - cy) - half_h + radius
    outside = math.hypot(max(dx, 0), max(dy, 0))
    inside = min(max(dx, dy), 0)
    return outside + inside - radius


def render(size: int) -> bytes:
    scale = 4
    big = size * scale
    acc = [[[0, 0, 0] for _ in range(size)] for _ in range(size)]
    top = (22, 64, 150)
    bottom = (15, 42, 110)
    paper = (246, 242, 232)
    ink = (28, 36, 48)
    accent = (214, 96, 52)
    for y in range(big):
        for x in range(big):
            px = x + 0.5
            py = y + 0.5
            color = mix(top, bottom, py / big)
            card = rounded_box(px, py, big * 0.50, big * 0.47, big * 0.27, big * 0.29, big * 0.07)
            if card <= 0:
                color = paper
                bar_x = big * 0.29
                bar_w = big * 0.34
                bar_h = max(2, big * 0.028)
                for index, bar_y in enumerate((big * 0.30, big * 0.40, big * 0.50)):
                    width = bar_w if index < 2 else bar_w * 0.62
                    if bar_x <= px <= bar_x + width and bar_y <= py <= bar_y + bar_h:
                        color = ink
            badge = math.hypot(px - big * 0.70, py - big * 0.70)
            if badge <= big * 0.115:
                color = accent
                local_x = (px - big * 0.70) / big
                local_y = (py - big * 0.70) / big
                stem = abs(local_x) <= 0.011 and -0.042 <= local_y <= 0.002
                head = 0.0 <= local_y <= 0.04 and abs(local_x) <= 0.034 * (1 - local_y / 0.04)
                if stem or head:
                    color = (255, 255, 255)
            oy = y // scale
            ox = x // scale
            for channel in range(3):
                acc[oy][ox][channel] += color[channel]
    pixels = bytearray()
    samples = scale * scale
    for y in range(size):
        for x in range(size):
            for channel in range(3):
                pixels.append(acc[y][x][channel] // samples)
    return bytes(pixels)


def main() -> None:
    root = Path(__file__).resolve().parents[1] / "Resources"
    root.mkdir(parents=True, exist_ok=True)
    write_png(root / "AppIcon60x60@2x.png", 120, render(120))
    write_png(root / "AppIcon60x60@3x.png", 180, render(180))
    write_png(root / "AppIcon76x76@2x.png", 152, render(152))


if __name__ == "__main__":
    main()
