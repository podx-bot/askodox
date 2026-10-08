"""Where the user wants results FROM: online, local, or both (mixed).

One rule for every category and language (en / te / hi), read from the
user's own words anywhere in the message -- not only at its end (APK 1312:
"show me online shops for paint" still ran local discovery and showed
nearby shop cards). Mirrored in the app as ``askodoxChannelPreference``.

  online  -> local sources are skipped, the online search always runs
  local   -> the online search is skipped
  None    -> both (nothing said, or both named)
"""

from __future__ import annotations

import re

ONLINE, LOCAL = "online", "local"

_ONLINE = re.compile(
    # Longer phrases first: "online shops" is removed whole, so its "shops"
    # never counts as a local ask.
    r"\b(online (?:shops?|stores?|links?|sites?|sellers?|marketplaces?)|order (?:it )?online|buy online|"
    r"online|on-line|websites?|web ?sites?|e-?commerce|internet)\b|"
    r"ఆన్\s*లైన్\S*|ఆన్‌లైన్\S*|వెబ్‌సైట్\S*|ऑनलाइन|वेबसाइट",
    re.IGNORECASE)
_LOCAL = re.compile(
    r"\b(near ?(?:me|by|here)|nearby|around me|in my area|local(?:ly)?|offline|walk-?in|"
    r"shops?|stores?|dealers?|showrooms?|outlets?)\b|"
    r"దగ్గర\S*|నా దగ్గర|స్థానిక\S*|షాప్\S*|షాపు\S*|దుకాణ\S*|लोकल|पास में|नज़दीक|नजदीक|दुकान",
    re.IGNORECASE)


def detect(text: str) -> str | None:
    """The channel the user named in [text], or None (both / not said)."""
    said = str(text or "")
    online = bool(_ONLINE.search(said))
    local = bool(_LOCAL.search(_ONLINE.sub(" ", said)))
    if online and not local:
        return ONLINE
    if local and not online:
        return LOCAL
    return None
