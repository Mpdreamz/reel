"""Patch the HTML pages docs-builder wrote, for scripts/docs-finish.sh.

    python3 -I scripts/docs-pages.py <output dir> <docs dir> <path prefix>

- Links to the site root load it whole (hx-boost="false"). The root is the landing page, which has none of the docs
  shell, so htmx's boosted swap of #main-container would find nothing to swap and leave the reader on the docs.
  Under a path prefix docs-builder writes the root both as /prefix/ (the header brand) and /prefix (the sidebar and
  the pager), so both forms are patched.
- The header shows the reel mark, the docset's branding.icon, beside the title as the landing page's nav does. The
  design-system header has a slot for it (site-header__logo) that docs-builder never fills. It is inlined, not an
  <img>, so it takes the theme's accent colour (currentColor): Gate amber in dark, the deep amber in light.
"""

import re
import sys
from pathlib import Path

out, docs, prefix = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3].strip("/")
root = f"/{prefix}/" if prefix else "/"
root_href = re.escape(f"/{prefix}") + "/?" if prefix else "/"

icon = re.search(r"^\s+icon:\s*['\"]?([^'\"\s#]+)", (docs / "_docset.yml").read_text(encoding="utf-8"), flags=re.M)
if not icon or not icon.group(1).endswith(".svg") or not (docs / icon.group(1)).is_file():
    print(f"docs: branding.icon in {docs / '_docset.yml'} is not an SVG file under {docs}", file=sys.stderr)
    sys.exit(1)
source = (docs / icon.group(1)).read_text(encoding="utf-8")
svg, n_open = re.subn(
    r"<svg\b[^>]*>",
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" class="site-header__logo"'
    ' aria-hidden="true" focusable="false">',
    re.sub(r"<!--.*?-->\s*", "", source, flags=re.S).strip(),
    count=1,
)
svg, n_fill = re.subn(r'\bfill="#[0-9A-Fa-f]{3,8}"', 'fill="currentColor"', svg)
if n_open != 1 or n_fill == 0 or 'viewBox="0 0 64 64"' not in source:
    print(f"docs: {docs / icon.group(1)} is not the 64x64 filled mark this expects", file=sys.stderr)
    sys.exit(1)
logo_svg = re.sub(r">\s+<", "><", svg)

brand = re.compile(r'(<a\b[^>]*\bclass="site-header__brand"[^>]*>)(?!\s*<(?:img|svg)\b)')
root_link = re.compile(r'<a\b(?![^>]*\bhx-boost=)([^>]*\bhref="' + root_href + r'")')
any_root = re.compile(r'<a\b[^>]*\bhref="' + root_href + r'"')

pages = links = logos = 0
seen_root = seen_brand = False
for page in out.rglob("*.html"):
    html = page.read_text(encoding="utf-8")
    seen_root = seen_root or bool(any_root.search(html))
    seen_brand = seen_brand or 'class="site-header__brand"' in html
    new, n_links = root_link.subn(r'<a hx-boost="false"\1', html)
    new, n_logos = brand.subn(lambda m: m.group(1) + logo_svg, new)
    if new != html:
        page.write_text(new, encoding="utf-8")
        pages += 1
        links += n_links
        logos += n_logos

if not seen_root:
    print(f'docs: no links to "{root}" found; the docs-builder markup changed', file=sys.stderr)
    sys.exit(1)
if not seen_brand:
    print("docs: no site-header__brand found for the logo; the docs-builder markup changed", file=sys.stderr)
    sys.exit(1)
print(f"docs: {pages} pages patched ({links} root links unboosted, {logos} logos)")
