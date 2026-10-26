"""Build six static website languages and a sitemap from shared, validated copy."""
import argparse
import json
from pathlib import Path
import subprocess

from bs4 import BeautifulSoup, Comment

SITE = Path(__file__).resolve().parent
BASE = "https://bultodepapas.github.io/OpenRCsimulator/"
LOCALES = {
    "es": {"file": "index.html", "name": "Español", "short": "ES"},
    "en": {"file": "en.html", "name": "English", "short": "EN"},
    "pt": {"file": "pt.html", "name": "Português", "short": "PT"},
    "zh-Hans": {"file": "zh-Hans.html", "name": "简体中文", "short": "中文"},
    "de": {"file": "de.html", "name": "Deutsch", "short": "DE"},
    "ru": {"file": "ru.html", "name": "Русский", "short": "RU"},
}


def locale_url(lang):
    return BASE + ("" if lang == "es" else LOCALES[lang]["file"])


def load_copy():
    # Evaluate only repository-owned data, with no browser or Node globals.
    program = """
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[1], 'utf8');
const data = vm.runInNewContext(source + '\\nJSON.stringify({translations, aircraft, labels, alts, englishMetadata, englishAttributes})', {}, {timeout: 1000});
process.stdout.write(data);
"""
    return json.loads(subprocess.check_output(
        ["node", "-e", program, str(SITE / "content.js")], text=True
    ))


def replace_html(element, markup):
    fragment = BeautifulSoup("<div>" + markup + "</div>", "html.parser").div
    element.clear()
    for child in list(fragment.contents):
        element.append(child)


def validate_translation(reference, candidate, path=""):
    if isinstance(reference, dict):
        if not isinstance(candidate, dict) or reference.keys() != candidate.keys():
            raise ValueError(f"Translation keys differ at {path}")
        for key, value in reference.items():
            validate_translation(value, candidate[key], f"{path}.{key}")
    elif not isinstance(candidate, str) or not candidate.strip():
        raise ValueError(f"Empty or invalid translation at {path}")
    else:
        # Translating prose must never change download, guide or fragment targets.
        links = lambda text: [tag['href'] for tag in BeautifulSoup('<div>' + text + '</div>', 'html.parser').select('a[href]')]
        if links(reference) != links(candidate):
            raise ValueError(f"Translated link targets differ at {path}")


def dictionaries(source, data):
    runtime = json.loads((SITE / "locales/runtime.json").read_text(encoding="utf-8"))
    keys = {tag["data-i18n"] for tag in source.select('[data-i18n]')}
    english = {
        "metadata": data["englishMetadata"],
        "translations": {key: data["translations"][key] for key in keys},
        "labels": {key: value[1] for key, value in data["labels"].items()},
        "alts": {key: value[1] for key, value in data["alts"].items()},
        "attributes": data["englishAttributes"],
        "aircraft": {key: {field: model[field][1] for field in ("category", "description", "gear")}
                     | {"status": model.get("status", ["Experimental", "Experimental"])[1]}
                     for key, model in data["aircraft"].items()},
        "ui": runtime["en"],
    }
    spanish = {
        "metadata": {"title": source.title.string, "description": source.select_one('meta[name="description"]')["content"]},
        "translations": {tag["data-i18n"]: tag.decode_contents() for tag in source.select('[data-i18n]')},
        "labels": {key: value[0] for key, value in data["labels"].items()},
        "alts": {key: value[0] for key, value in data["alts"].items()},
        "attributes": {key: key for key in data["englishAttributes"]},
        "aircraft": {key: {field: model[field][0] for field in ("category", "description", "gear")}
                     | {"status": model.get("status", ["Experimental", "Experimental"])[0]}
                     for key, model in data["aircraft"].items()},
        "ui": runtime["es"],
    }
    locales = {"es": spanish, "en": english}
    for lang in LOCALES.keys() - locales.keys():
        locales[lang] = json.loads((SITE / f"locales/{lang}.json").read_text(encoding="utf-8"))
    for lang, copy in locales.items():
        # Spanish is the content source; its editorial hyperlinks may use a different order.
        if lang != "es":
            validate_translation(english, copy, lang)
        validate_translation(runtime["en"], copy["ui"], f"{lang}.ui")
    return locales


def build():
    data = load_copy()
    original = (SITE / "index.html").read_text(encoding="utf-8")
    source = BeautifulSoup(original, "html.parser")
    if source.html["lang"] != "es":
        raise ValueError("index.html must remain the Spanish source page")
    copies = dictionaries(source, data)
    outputs = {}
    for lang, config in LOCALES.items():
        copy = copies[lang]
        soup = BeautifulSoup(original, "html.parser")
        soup.html["lang"] = lang
        if lang != "es":
            soup.insert(1, Comment(" Generated by build_locales.py; edit source copy, not this page. "))
            for element in soup.select('[data-i18n]'):
                replace_html(element, copy["translations"][element["data-i18n"]])
        for element in soup.select('[data-ui]'):
            element.string = copy["ui"][element["data-ui"]]
        for attribute, dictionary, target in [("data-label", "labels", "aria-label"), ("data-alt", "alts", "alt")]:
            for element in soup.select(f'[{attribute}]'):
                element[target] = copy[dictionary][element[attribute]]
        for element in soup.select('[aria-label], [alt]'):
            for attribute in ("aria-label", "alt"):
                value = element.get(attribute)
                if value in copy["attributes"]:
                    element[attribute] = copy["attributes"][value]
        for element in soup.select('img[src*="branding/"]'):
            element["alt"] = "OpenRC Simulator — " + copy["ui"]["earlyAlpha"]
        for selector in ['meta[property="og:image:alt"]', 'meta[name="twitter:image:alt"]']:
            soup.select_one(selector)["content"] = "OpenRC Simulator — " + copy["ui"]["earlyAlpha"]

        menu = soup.select_one('.language-menu')
        menu.clear()
        summary = soup.new_tag('summary', attrs={"aria-label": copy["ui"]["languageMenu"]})
        summary.string = config["short"] + " ▾"
        menu.append(summary)
        nav = soup.new_tag('nav', attrs={"class": "language-options", "aria-label": copy["ui"]["languageMenu"]})
        for target, target_config in LOCALES.items():
            link = soup.new_tag('a', attrs={"href": "./" if target == "es" else target_config["file"],
                                           "lang": target, "hreflang": target, "data-locale": target})
            if target == lang:
                link["aria-current"] = "page"
            link.string = target_config["name"]
            nav.append(link)
        menu.append(nav)
        for element in soup.select('link[rel="alternate"][hreflang]'):
            element.decompose()
        canonical = soup.select_one('link[rel="canonical"]')
        for target in [*LOCALES, "x-default"]:
            canonical.insert_before(soup.new_tag('link', attrs={"rel": "alternate", "hreflang": target,
                                                               "href": locale_url("es" if target == "x-default" else target)}))
        jet = copy["aircraft"]["jet"]
        for field in ("category", "description", "gear", "status"):
            soup.select_one('#aircraft-' + field).string = jet[field]
        title, description = copy["metadata"]["title"], copy["metadata"]["description"]
        soup.title.string = title
        for selector in ['meta[property="og:title"]', 'meta[name="twitter:title"]']:
            soup.select_one(selector)["content"] = title
        for selector in ['meta[name="description"]', 'meta[property="og:description"]', 'meta[name="twitter:description"]']:
            soup.select_one(selector)["content"] = description
        url = locale_url(lang)
        canonical["href"] = url
        soup.select_one('meta[property="og:url"]')["content"] = url
        schema_element = soup.select_one('#software-schema')
        schema = json.loads(schema_element.string)
        schema.update(description=description, url=url, downloadUrl=url + "#download")
        schema["offers"]["url"] = url + "#download"
        schema_element.string = "\n" + json.dumps(schema, ensure_ascii=False, indent=2) + "\n"
        # Only interactive text is embedded. The full page is already translated HTML.
        payload = {key: copy[key] for key in ("aircraft", "alts", "ui")}
        soup.select_one('#locale-data').string = json.dumps(payload, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')
        # Normalize adjacent whitespace left by replaced head elements in the
        # same pass, so rebuilding the Spanish source is immediately idempotent.
        outputs[config["file"]] = str(BeautifulSoup(str(soup), "html.parser")).rstrip() + "\n"
    outputs["sitemap.xml"] = '\n'.join([
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
        *[f'  <url><loc>{locale_url(lang)}</loc></url>' for lang in LOCALES],
        '</urlset>', '',
    ])
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if generated content is stale; do not write.")
    args = parser.parse_args()
    outputs = build()
    if args.check:
        stale = [name for name, content in outputs.items()
                 if not (SITE / name).exists() or (SITE / name).read_text(encoding="utf-8") != content]
        if stale:
            raise SystemExit("Stale generated files: " + ", ".join(stale) + ". Run python3 site/build_locales.py")
        print("Six static languages, runtime dictionaries and sitemap match their sources.")
    else:
        for name, content in outputs.items():
            (SITE / name).write_text(content, encoding="utf-8")
        print("Generated " + ", ".join(outputs))


if __name__ == "__main__":
    main()
