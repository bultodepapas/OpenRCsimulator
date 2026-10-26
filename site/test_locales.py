"""Static locale publication checks; run with python3 site/test_locales.py."""
import json
import unittest
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

from bs4 import BeautifulSoup

from build_locales import BASE, SITE, build


class LocalePublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pages = {lang: BeautifulSoup((SITE / name).read_text(encoding="utf-8"), "html.parser")
                     for lang, name in [("es", "index.html"), ("en", "en.html")]}

    def test_generated_pages_are_current(self):
        for name, content in build().items():
            self.assertEqual((SITE / name).read_text(encoding="utf-8"), content, name)

    def test_locales_have_reciprocal_routes_and_consistent_metadata(self):
        routes = {"es": BASE, "en": BASE + "en.html"}
        for lang, page in self.pages.items():
            with self.subTest(lang=lang):
                self.assertEqual(page.html["lang"], lang)
                self.assertEqual(page.select_one('link[rel="canonical"]')["href"], routes[lang])
                self.assertEqual(page.select_one('meta[property="og:url"]')["content"], routes[lang])
                self.assertEqual({t["hreflang"]: t["href"] for t in page.select('link[hreflang]')},
                                 {**routes, "x-default": BASE})
                self.assertNotIn("noindex", page.select_one('meta[name="robots"]')["content"])
                schema = json.loads(page.select_one('#software-schema').string)
                self.assertEqual(schema["url"], routes[lang])
                self.assertEqual(schema["downloadUrl"], routes[lang] + "#download")
                for selector in ['meta[property="og:title"]', 'meta[name="twitter:title"]']:
                    self.assertEqual(page.select_one(selector)["content"], page.title.string)
                for selector in ['meta[name="description"]', 'meta[property="og:description"]', 'meta[name="twitter:description"]']:
                    self.assertEqual(page.select_one(selector)["content"], schema["description"])
                self.assertTrue(page.select_one('a.language[href][hreflang]'))
                self.assertEqual(len(page.select('h1')), 1)
        root = ET.parse(SITE / "sitemap.xml").getroot()
        self.assertEqual({tag.text for tag in root.findall('{*}url/{*}loc')}, set(routes.values()))

    def test_no_script_content_and_downloads_remain_available(self):
        downloads = []
        for lang, page in self.pages.items():
            with self.subTest(lang=lang):
                downloads.append({a["href"] for a in page.select('a[href]')
                                  if '/releases/download/' in a["href"]})
                for tag in page.select('[data-i18n]'):
                    self.assertTrue(tag.get_text(strip=True), tag["data-i18n"])
                self.assertEqual(len(page.select('.faq-list article')), 5)
                self.assertFalse(page.select('.faq details, .faq [hidden]'))
        self.assertTrue(downloads[0])
        self.assertEqual(*downloads)

    def test_assets_and_internal_links_resolve_in_project_subdirectory(self):
        for lang, page in self.pages.items():
            with self.subTest(lang=lang):
                ids = [tag["id"] for tag in page.select('[id]')]
                self.assertEqual(len(ids), len(set(ids)))
                for tag in page.select('[src], [href], [data-src]'):
                    for attribute in ("src", "href", "data-src"):
                        if attribute not in tag.attrs:
                            continue
                        url = urlsplit(tag[attribute])
                        if url.scheme or url.netloc:
                            continue
                        self.assertFalse(url.path.startswith('/'), tag[attribute])
                        if url.path:
                            target = SITE / unquote(url.path)
                            self.assertTrue(target.exists(), tag[attribute])
                        elif url.fragment:
                            self.assertIn(unquote(url.fragment), ids)


if __name__ == "__main__":
    unittest.main()
