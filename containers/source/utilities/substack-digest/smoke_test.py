"""Offline integration test in the real image; produces a reviewable sample PDF."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright
from pypdf import PdfReader
import digest

config = json.loads(Path('/config/config.json').read_text())
post = {"id": 1, "title": "A morning on the small screen", "post_date": "2026-10-07T10:00:00Z", "canonical_url": "https://example.substack.com/p/sample", "audience": "only_paid"}
paragraph = '<p>A good reading layout leaves room to think. This sample uses a comfortable serif face, short lines, and space in the right margin for handwritten notes. Highlight a sentence or write a question beside it.</p>'
body = '<h2>Space for annotations</h2>' + paragraph * 9 + '<blockquote>Keep the text readable without zooming.</blockquote><h2>A second section</h2>' + paragraph * 7
with sync_playwright() as playwright:
    browser = playwright.chromium.launch()
    context = browser.new_context()
    context.route('**/*', lambda route: route.fulfill(body='<html><body><div class="available-content"><div class="body markup">' + body + '</div></div></body></html>', content_type='text/html'))
    page = context.new_page()
    extracted = digest.article_html(page, post, {"type": "paid"})
    assert 'Space for annotations' in extracted
    # Paid users seeing a paywall must fail, not receive a preview as full text.
    context.unroute('**/*')
    context.route('**/*', lambda route: route.fulfill(body='<div class="body markup">Preview</div><div class="paywall">Subscribe</div>', content_type='text/html'))
    try:
        digest.article_html(page, post, {"type": "paid"})
        raise AssertionError('Paywall was silently accepted')
    except RuntimeError:
        pass
    assert 'Paid subscription required' in digest.article_html(page, post, {"type": "free"})
    output = Path('/output/sample.pdf')
    articles = [{"post": post, "publication": "Sample publication", "body": extracted}]
    digest.render_pdf(browser, articles, config, 'Substack · October 7', output)
    browser.close()
reader = PdfReader(output)
assert len(reader.pages) >= 3
for page in reader.pages:
    assert abs(float(page.mediabox.width) - 91.8 * 72 / 25.4) < 1
    assert abs(float(page.mediabox.height) - 163.2 * 72 / 25.4) < 1
text = '\n'.join(p.extract_text() for p in reader.pages)
assert text.count('A good reading layout') == 16
assert 'Original article' in text
print(f'Rendering and paywall smoke test passed: {len(reader.pages)} pages')
