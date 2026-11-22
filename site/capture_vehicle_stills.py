"""Render the two vehicle studio views from the shipped GLBs using the site's viewer.

Run with Playwright 1.61.0 (Chromium installed) and Pillow 12.3.0:
    python site/capture_vehicle_stills.py
"""
import base64
from io import BytesIO
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

SITE = Path(__file__).resolve().parent
APP = SITE.parent / "app/assets"
MODELS = (
    ("ion-r5", "multirotors/ion-r5/ion_r5.glb", "-145deg 62deg 78%"),
    ("rc-blimp", "airships/rc-blimp-5m/tiburon-blanco.glb", "-114deg 76deg 76%"),
)


def main():
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        for name, source, orbit in MODELS:
            page = browser.new_page(viewport={"width": 1200, "height": 675})
            page.route("http://studio.local/viewer.js", lambda route: route.fulfill(
                path=SITE / "assets/vendor/model-viewer-4.4.0.min.js", content_type="text/javascript"))
            page.route("http://studio.local/model.glb", lambda route: route.fulfill(
                path=APP / source, content_type="model/gltf-binary"))
            page.route("http://studio.local/", lambda route: route.fulfill(
                content_type="text/html", body=f"""<!doctype html><meta charset="utf-8">
                <style>*{{margin:0}}model-viewer{{display:block;width:100vw;height:100vh}}</style>
                <script type="module" src="/viewer.js"></script>
                <model-viewer src="/model.glb" camera-orbit="{orbit}" field-of-view="26deg"
                 environment-image="neutral" shadow-intensity=".65" shadow-softness="1"
                 exposure="1" tone-mapping="neutral" interaction-prompt="none"></model-viewer>"""))
            page.goto("http://studio.local/")
            page.wait_for_function("document.querySelector('model-viewer').loaded === true")
            pixels = page.locator("model-viewer").evaluate("""async model => {
                model.jumpCameraToGoal();
                await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
                return model.toDataURL("image/png");
            }""")
            output = SITE / f"assets/{name}-studio.webp"
            with Image.open(BytesIO(base64.b64decode(pixels.split(",", 1)[1]))) as view:
                alpha = view.getchannel("A")
                if not alpha.getbbox() or alpha.getextrema() != (0, 255):
                    raise ValueError(f"Incomplete studio render for {name}")
                studio = Image.new("RGB", view.size, "#d2dbd7")
                studio.paste(view, mask=alpha)
                studio.save(output, "WEBP", quality=89, method=6)
            print(output.name, output.stat().st_size, "bytes")
            page.close()
        browser.close()


if __name__ == "__main__":
    main()
