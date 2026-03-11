# GitHub Pages Debug

The deployed page still shows v2.0.0 as the latest changelog entry and v2.0.0 badge.
The v2.1 entry is missing from the rendered page.

This could be:
1. GitHub Pages CDN cache (takes a few minutes to propagate)
2. The gh-pages branch was pushed but the page source might be set to main branch
3. Need to verify the actual deployed file content

The markdown extraction shows "v2.0.0" as hero badge, not "v2.1".
