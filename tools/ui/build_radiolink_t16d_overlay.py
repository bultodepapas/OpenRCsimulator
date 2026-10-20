"""Scale the official transparent T16D front photo for the flight overlay."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/ui/radiolink-t16d/front-original.png"
TARGET = ROOT / "app/assets/ui/radiolink_t16d.png"
OUTPUT_WIDTH = 360


def main() -> None:
    photo = Image.open(SOURCE).convert("RGBA")
    photo = photo.crop(photo.getbbox())
    height = round(photo.height * OUTPUT_WIDTH / photo.width)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    photo.resize((OUTPUT_WIDTH, height), Image.Resampling.LANCZOS).save(TARGET, optimize=True)
    print(TARGET.relative_to(ROOT))


if __name__ == "__main__":
    main()
