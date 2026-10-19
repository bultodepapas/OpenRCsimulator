# FW-MOON-10: assembles the eclipse evidence sheets from a moon_capture.gd run with --cases=eclipse --close-fov=1.2:
# the 2028-12-31 phases (close-ups), the 2032-10-18 eclipse over the reference field and the 2028-12-31 moonrise.
# Usage: python3 -I research/field-world/fw-moon-10/sheets.py /abs/capture/dir
# (the capture: xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy \
#   --rendering-driver opengl3 --script "$PWD/tools/world/moon_capture.gd" -- --out=/abs/capture/dir --cases=eclipse \
#   --close-fov=1.2)
import json
import os
import sys

from PIL import Image, ImageDraw

PHASES = ["eclipse_a_penumbral", "eclipse_b_partial", "eclipse_c_deep_partial", "eclipse_d_total_start",
          "eclipse_e_greatest", "eclipse_f_partial_out"]
TILE = 240


def pair(out, wide, close, title, name):
    sheet = Image.new("RGB", (2 * 640 + 10, 360 + 18), (255, 255, 255))
    ImageDraw.Draw(sheet).text((4, 2), title, fill=(0, 0, 0))
    sheet.paste(Image.open(os.path.join(out, wide)).convert("RGB").resize((640, 360)), (0, 18))
    sheet.paste(Image.open(os.path.join(out, close)).convert("RGB").resize((640, 360)), (650, 18))
    sheet.save(os.path.join(out, name), quality=88)


def main(out):
    manifest = json.load(open(os.path.join(out, "manifest.json"), encoding="utf-8"))
    info = {(c["case_id"], c["view"]): c for c in manifest["cases"]}
    sheet = Image.new("RGB", (len(PHASES) * (TILE + 6) + 6, TILE + 44), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for i, case in enumerate(PHASES):
        image = Image.open(os.path.join(out, case + "-close.png")).convert("RGB")
        w, h = image.size
        side = min(w, h)
        square = image.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2)).resize((TILE, TILE))
        sheet.paste(square, (6 + i * (TILE + 6), 38))
        entry = info[(case, "close")]
        draw.text((6 + i * (TILE + 6), 4), case.replace("eclipse_", "").replace("_", " "), fill=(0, 0, 0))
        draw.text((6 + i * (TILE + 6), 20), "%s UT, umbral mag %.2f" % (entry["arguments"][1][7:],
                  entry["moon"]["umbral_magnitude"]), fill=(0, 0, 0))
    sheet.save(os.path.join(out, "eclipse-phases.jpg"), quality=88)
    pair(out, "eclipse_field_2032-wide.png", "eclipse_field_2032-close.png",
         "2032-10-18 19:00 UT over the reference field: the pilot's view toward the eclipsed moon (60 deg) | close-up (1.2 deg)",
         "eclipse-field-2032.jpg")
    pair(out, "eclipse_moonrise-wide.png", "eclipse_moonrise-close.png",
         "2028-12-31 17:20 UT eclipsed moonrise at the reference field (moon 3.5 deg, civil twilight): wide | close-up",
         "eclipse-moonrise-2028.jpg")
    print("sheets written to", out)


if __name__ == "__main__":
    main(sys.argv[1])
