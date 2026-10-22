"""Original geometric AkiChat mark. Pillow is only needed to regenerate committed PNGs."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "AkiChat/Assets.xcassets"

def icon(size):
    scale = 3
    s = size * scale
    image = Image.new("RGB", (s, s))
    pixels = image.load()
    for y in range(s):
        t = y / s
        color = (int(40 + 25*t), int(65 + 30*t), int(146 + 65*t))
        for x in range(s): pixels[x, y] = color
    draw = ImageDraw.Draw(image)
    def p(x): return round(x*s)
    draw.rounded_rectangle([p(.20), p(.23), p(.80), p(.73)], radius=p(.15), fill=(243, 248, 255))
    draw.polygon([(p(.29), p(.65)), (p(.29), p(.83)), (p(.48), p(.68))], fill=(243, 248, 255))
    draw.line([(p(.34), p(.57)), (p(.46), p(.37)), (p(.58), p(.57))], fill=(57, 87, 194), width=p(.048), joint="curve")
    draw.line([(p(.39), p(.50)), (p(.53), p(.50))], fill=(57, 87, 194), width=p(.035))
    draw.ellipse([p(.64), p(.38), p(.69), p(.43)], fill=(104, 158, 236))
    return image.resize((size, size), Image.Resampling.LANCZOS)

def main():
    directory = ROOT / "AppIcon.appiconset"
    directory.mkdir(parents=True, exist_ok=True)
    entries = []
    for points, scales in [(20, [2, 3]), (29, [2, 3]), (40, [2, 3]), (60, [2, 3])]:
        for scale in scales:
            filename = f"icon-{points}@{scale}x.png"
            icon(points*scale).save(directory / filename)
            entries.append({"idiom": "iphone", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": filename})
    icon(1024).save(directory / "icon-1024.png")
    entries.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "icon-1024.png"})
    (directory / "Contents.json").write_text(json.dumps({"images": entries, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    (ROOT / "Contents.json").write_text('{"info":{"version":1,"author":"xcode"}}\n')

if __name__ == "__main__": main()
