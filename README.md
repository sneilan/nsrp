# nsrp: "Nim Steam Review Parser"

_nsrp_ is a Steam(TM) game review downloader, that outputs in Markdown, HTML, or JSON; for either casual reading, or consumption by an LLM for analysis.

## Examples

_HTML output not yet supported!_

- nsrp -n:50 -m:1459560 -> generates 1459560_review.md for "Untitled Space Game", newest 50 responses
- nsrp -d:"cs2data" -h:730 -> generates 730_review.html for "Counter-Strike 2", and saves it in "cs2data" subfolder
- nsrp -j:1454400 -> generates 1454400_review.json for "Cookie Clicker"

## References

- https://partner.steamgames.com/doc/store/getreviews -> API documentation
- https://github.com/woctezuma/download-steam-reviews -> Inspired this application
- https://www.markdownguide.org/ -> Markdown documentation

## AI usage

Anthropic Claude was used to supply minor changes and functions, and acted as a code review mechanism.

## Changelog

- 2026.09.02.3 -> Added Markdown output
- 2026.08.30.1 -> First release: JSON-only
