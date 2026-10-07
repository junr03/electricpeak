"""Daily subscription digest: small orchestration around Playwright and rmapi-js.

Never reads the algorithmic reader feed. A checkpoint advances only after the
complete PDF is uploaded (or the interval contains no accessible articles).
"""
import argparse
from datetime import datetime, timedelta, timezone
import fcntl
import hashlib
import html
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

UTC = timezone.utc


class DigestError(RuntimeError):
    """An operator-safe error message without remote response bodies."""



def timestamp(value):
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("Publication timestamp has no timezone")
    return result.astimezone(UTC)


def atomic_json(path, value):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def subscription_publications(payload):
    # Intersect the metadata with the actual subscriptions, even if Substack
    # adds suggested publications to its metadata block in the future.
    subscriptions = {str(s["publication_id"]): s for s in payload["subscriptions"]}
    publications = {str(p["id"]): p for p in payload["publications"]}
    if not subscriptions or not subscriptions.keys() <= publications.keys():
        raise ValueError("Empty or incomplete subscription response; refusing checkpoint")
    return [(publications[key], sub) for key, sub in subscriptions.items()]


def archive_posts(get, publication, since, until):
    subdomain = publication["subdomain"]
    if not re.fullmatch(r"[a-zA-Z0-9-]+", subdomain):
        raise ValueError("Invalid publication subdomain")
    url = f"https://{subdomain}.substack.com/api/v1/archive"
    offset, seen = 0, set()
    while True:
        batch = get(url, {"sort": "new", "limit": 20, "offset": offset})
        if not isinstance(batch, list):
            raise ValueError("Unexpected archive response")
        if not batch:
            return
        fresh = [p for p in batch if str(p["id"]) not in seen]
        if not fresh:
            raise ValueError("Archive pagination stopped making progress")
        for post in fresh:
            seen.add(str(post["id"]))
            if str(post["publication_id"]) != str(publication["id"]):
                raise ValueError("Archive returned another publication's post")
            if since <= timestamp(post["post_date"]) <= until:
                yield post
        # sort=new; tolerate overlapping pages, and include cutoff ties.
        if max(timestamp(p["post_date"]) for p in batch) < since:
            return
        offset += len(batch)


def get_json(context, url, params=None):
    for attempt in range(4):
        response = context.request.get(url, params=params, timeout=60000)
        if response.status == 429 or response.status >= 500:
            time.sleep(5 * (attempt + 1))
            continue
        if not response.ok:
            raise DigestError(f"Substack request failed (HTTP {response.status}); refresh cookies if expired")
        return response.json()
    raise DigestError("Substack request failed after retries")


def article_html(page, post, subscription):
    url = post["canonical_url"]
    if urlparse(url).scheme != "https":
        raise ValueError("Expected an HTTPS article")
    response = page.goto(url, wait_until="domcontentloaded", timeout=60000)
    if response is None or not response.ok:
        raise DigestError(f"Article {post['id']} failed to load")
    body = page.locator(".available-content .body.markup, .body.markup").first
    body.wait_for(state="visible", timeout=30000)
    page.wait_for_timeout(1500)
    paywall = page.locator('[class*="paywall" i], [aria-label="Paywall"]')
    locked = any(paywall.nth(i).is_visible() for i in range(paywall.count()))
    if locked:
        # A known free subscription cannot read paid-only content. Include an
        # explicit notice in the digest; never mistake the preview for full text.
        free = subscription.get("membership_state") == "free_subscriber" or subscription.get("type") == "free"
        if free and post.get("audience") == "only_paid":
            return '<p><em>Paid subscription required. Full article was not downloaded.</em></p>'
        raise DigestError(f"Article {post['id']} is locked; refresh the publication's login cookies")
    # Copy only the article body, not recommendations/comments/site navigation.
    # Strip active content and inline styling before rendering in a fresh context.
    return body.evaluate("""element => {
      const root = element.cloneNode(true);
      const originals = element.querySelectorAll('img');
      root.querySelectorAll('img').forEach((image, i) => {
        image.setAttribute('src', originals[i].currentSrc || originals[i].src);
      });
      root.querySelectorAll('script,style,iframe,form,button,input,video,audio,svg,link,object,embed').forEach(e => e.remove());
      root.querySelectorAll('*').forEach(e => {
        for (const a of [...e.attributes]) {
          if (!['href','src','alt','colspan','rowspan'].includes(a.name)) e.removeAttribute(a.name);
        }
        for (const name of ['href','src']) {
          if (e.hasAttribute(name)) {
            const url = new URL(e.getAttribute(name), document.baseURI);
            if (url.protocol === 'https:') e.setAttribute(name, url.href);
            else e.removeAttribute(name);
          }
        }
      });
      return root.innerHTML;
    }""")


def document(articles, config, title):
    width, height = config["page_width_mm"], config["page_height_mm"]
    css = f"""
      @page {{ size: {width}mm {height}mm; margin: {config['margin_mm']}mm;
               margin-right: {config['annotation_margin_mm']}mm; }}
      body {{ font: {config['font_size_pt']}pt/{config['line_height']} Georgia, serif; color: #111; }}
      h1 {{ font-size: 18pt; line-height: 1.15; }} h2 {{ font-size: 15pt; }}
      h1,h2,h3 {{ break-after: avoid; }} p {{ orphans: 3; widows: 3; }}
      article {{ break-before: page; }} img {{ max-width: 100%; max-height: 120mm; object-fit: contain; }}
      a {{ color: #222; overflow-wrap: anywhere; }} pre {{ white-space: pre-wrap; font-size: 9pt; }}
      pre,td {{ overflow-wrap: anywhere; }} table {{ width: 100%; table-layout: fixed; font-size: 9pt; }}
      blockquote {{ margin: 0; padding-left: 3mm; border-left: 1px solid #888; }}
      .meta {{ font: 9pt/1.4 sans-serif; }}
    """
    contents, sections = [], []
    for index, article in enumerate(articles):
        post = article["post"]
        name = html.escape(post["title"])
        contents.append(f'<p><a href="#article-{index}">{name}</a></p>')
        sections.append(f'<article id="article-{index}"><h1>{name}</h1>'
                        f'<p class="meta">{html.escape(article["publication"])} · '
                        f'{html.escape(post["post_date"][:10])}</p>'
                        f'{article["body"]}<p class="meta"><a href="{html.escape(post["canonical_url"], quote=True)}">Original article</a></p></article>')
    return f'<!doctype html><html><head><meta charset="utf-8"><title>{html.escape(title)}</title><style>{css}</style></head><body><h1>{html.escape(title)}</h1>{"".join(contents)}{"".join(sections)}</body></html>'


def render_pdf(browser, articles, config, title, path):
    # Separate cookie-free context: publisher HTML cannot read session secrets.
    context = browser.new_context(java_script_enabled=False)
    page = context.new_page()
    def resource(route):
        host = urlparse(route.request.url).hostname or ""
        allowed = host == "substackcdn.com" or host.endswith(".substackcdn.com") or host == "substack-post-media.s3.amazonaws.com"
        if route.request.resource_type == "image" and allowed and route.request.url.startswith("https://"):
            route.continue_()
        else:
            route.abort()
    page.route("**/*", resource)
    page.set_content(document(articles, config, title), wait_until="load", timeout=60000)
    broken = page.locator("img").evaluate_all("images => images.some(i => !i.complete || i.naturalWidth === 0)")
    if broken:
        raise DigestError("Article image could not be rendered; refusing an incomplete PDF")
    page.pdf(path=str(path), prefer_css_page_size=True, print_background=True,
             display_header_footer=True, header_template="<span></span>",
             footer_template='<div style="font-size:7pt;width:100%;text-align:center"><span class="pageNumber"></span> / <span class="totalPages"></span></div>')
    context.close()


def rmapi(*args):
    result = subprocess.run(["rmapi-js", *map(str, args), "--json", "--refresh"],
                            capture_output=True, text=True, timeout=300)
    if result.returncode:
        # Do not copy remote errors, cookies, or authentication material to logs.
        raise DigestError(f"reMarkable {args[0]} failed (exit {result.returncode})")
    return json.loads(result.stdout) if result.stdout.strip() else None


def deliver(pdf, folder):
    rmapi("mkdir", folder, "--parents")
    entries = rmapi("ls", folder)
    matches = [e for e in entries if e["visibleName"] == pdf.stem]
    if matches:
        if len(matches) != 1 or matches[0]["type"] != "DocumentType":
            raise DigestError("Ambiguous existing digest; refusing to replace documents")
        # A previous upload may have succeeded before the process died. Never
        # overwrite it: it may already contain handwriting.
        return
    rmapi("put", pdf, folder)


def run(config, data, collect, render, upload, now=None):
    now = now or datetime.now(UTC)
    state_path, pending_path = data / "state.json", data / "pending.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {"delivered": {}}
    if not state_path.exists():
        # Freeze the first-run boundary even when the first collection fails.
        state["cutoff"] = (now - timedelta(hours=config["first_run_hours"])).isoformat()
        state["initial"] = True
        atomic_json(state_path, state)
    if pending_path.exists():
        pending = json.loads(pending_path.read_text())
    else:
        until = now
        since = timestamp(state["cutoff"]) if "cutoff" in state else until - timedelta(hours=config["first_run_hours"])
        if not state.get("initial"):
            since -= timedelta(hours=config["overlap_hours"])
        articles = collect(since, until, state["delivered"])
        ids = {str(a["post"]["id"]): a["post"]["post_date"] for a in articles}
        digest_id = hashlib.sha256(json.dumps([until.isoformat(), sorted(ids)]).encode()).hexdigest()[:12]
        title = f"Substack {until.astimezone(ZoneInfo(config['timezone'])):%Y-%m-%d} {digest_id}"
        pdf = data / (title + ".pdf")
        if articles:
            temporary = pdf.with_suffix(".tmp.pdf")
            render(articles, config, title, temporary)
            temporary.replace(pdf)
        pending = {"cutoff": until.isoformat(), "ids": ids, "pdf": pdf.name if articles else None, "folder": config["folder"]}
        # Durable outbox created BEFORE uploading. A retry reuses this exact PDF.
        atomic_json(pending_path, pending)
    if pending["pdf"]:
        upload(data / pending["pdf"], pending["folder"])
    state.pop("initial", None)
    state["cutoff"] = pending["cutoff"]
    state["delivered"].update(pending["ids"])
    atomic_json(state_path, state)
    pending_path.unlink()
    for pdf in data.glob("*.pdf"):
        if pdf.stat().st_mtime < time.time() - config["local_retention_days"] * 86400:
            pdf.unlink()
    print(f"Digest complete: {len(pending['ids'])} articles; cutoff {pending['cutoff']}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="/config/config.json")
    parser.add_argument("--data", default="/data")
    parser.add_argument("--cookies", default="/run/secrets/substack-cookies.json")
    parser.add_argument("--token", default="/run/secrets/remarkable-token")
    args = parser.parse_args()
    os.umask(0o077)
    config = json.loads(Path(args.config).read_text())
    data = Path(args.data)
    data.mkdir(parents=True, exist_ok=True)
    with (data / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.environ["RMAPI_DEVICE_TOKEN"] = Path(args.token).read_text().strip()
        from playwright.sync_api import sync_playwright
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = browser.new_context()
            cookies = json.loads(Path(args.cookies).read_text())
            context.add_cookies(cookies["cookies"] if isinstance(cookies, dict) else cookies)
            def collect(since, until, delivered):
                payload = get_json(context, "https://substack.com/api/v1/subscriptions", {"tvOnly": "false"})
                articles = []
                page = context.new_page()
                for publication, subscription in subscription_publications(payload):
                    for post in archive_posts(lambda url, params: get_json(context, url, params), publication, since, until):
                        if str(post["id"]) in delivered or post.get("type") not in ("newsletter", None):
                            continue
                        body = article_html(page, post, subscription)
                        articles.append({"post": post, "publication": publication["name"], "body": body})
                page.close()
                return sorted(articles, key=lambda a: (a["post"]["post_date"], str(a["post"]["id"])))
            run(config, data, collect, lambda *a: render_pdf(browser, *a), deliver)
            browser.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        detail = str(error) if isinstance(error, DigestError) else "Check credentials, source availability and configuration"
        print(f"Digest failed ({type(error).__name__}): {detail}; checkpoint preserved.", file=sys.stderr)
        sys.exit(1)
