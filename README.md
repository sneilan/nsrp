# nsrp

_nsrp_ is a Steam(TM) game review downloader, that outputs in Markdown, HTML, or JSON; for either casual reading, or consumption by an LLM for analysis. It is heavily inspired by Wok's [steamreviews](https://github.com/woctezuma/download-steam-reviews) package for Python.

## Examples

_Adding -l:value_ to the start of a command, limits it to that number of newest responses.

- nsrp -l:50 -m:1459560 -> generates 1459560_review.md for "Untitled Space Game", newest 50 responses
- nsrp -d:"cs2data" -h:730 -> generates 730_review.html for "Counter-Strike 2", and saves it in "cs2data" subfolder
- nsrp -j:1454400 -> generates 1454400_review.json for "Cookie Clicker"

## Changelog

- 2026.08.30.1 -> First release
