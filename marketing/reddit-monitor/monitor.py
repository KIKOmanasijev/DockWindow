#!/usr/bin/env python3
"""Find new Reddit posts where DogBar could genuinely help, and print a Markdown digest.

Reads each subreddit's public "new posts" RSS feed (no Reddit account or API key needed),
keeps posts that match DogBar's problem space, and skips posts already reported in an
earlier run. It never posts or comments: a person decides what, if anything, to reply.

Usage: python3 monitor.py [--hours 48] [--all]   (--all ignores the seen-posts list)
"""
import argparse
import html
import json
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from pathlib import Path

SUBREDDITS = ["macapps", "MacOS", "mac", "apple", "productivity", "MacOSBeta"]

# (pattern, weight). Strong signals name the exact problem DogBar solves.
SIGNALS = [
    (r"\bdock\b.{0,40}\b(per|each|every|separate|current)\b.{0,20}\b(desktop|space)s?\b", 5),
    (r"\b(desktop|space)s?\b.{0,40}\bdock\b", 3),
    (r"\b(dock)\s+(replacement|alternative|app)\b", 4),
    (r"\b(alt[- ]?tab|cmd[- ]?tab|command[- ]?tab|option[- ]?tab)\b", 3),
    (r"\bwindow\s+switch(er|ing)?\b|\bswitch(ing)?\s+(between\s+)?windows\b", 4),
    (r"\b(hyperdock|dockdoor|alttab|ubar|witch|contexts)\b", 4),
    (r"\bwindow\s+previews?\b|\bpreview\s+windows\b", 3),
    (r"\bmission control\b", 1),
    (r"\b(multiple|many)\s+(desktops|spaces)\b", 2),
    (r"\bdock\b", 1),
]
MIN_SCORE = 4
# Another developer announcing their own app: competitor news, not a thread to reply in.
LAUNCH_POST = re.compile(r"\bI(?:'ve| have)? (?:built|made|created|released)\b|\bdeveloper of\b|\bintroducing\b|\bmy (?:new )?app\b", re.IGNORECASE)
STATE = Path.home() / ".dogbar-monitor" / "seen.json"
ATOM = "{http://www.w3.org/2005/Atom}"
USER_AGENT = "Mozilla/5.0 (Macintosh) DogBarMonitor/0.1 (+https://dogbar.hristijan.dev)"


def fetch(url: str) -> bytes:
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=20) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 2:
                raise
            time.sleep(30 * (attempt + 1))  # Reddit rate limit: back off and retry
    raise RuntimeError("unreachable")


def text_of(entry_html: str) -> str:
    plain = re.sub(r"<[^>]+>", " ", html.unescape(entry_html or ""))
    plain = re.sub(r"\s+", " ", plain)
    return re.sub(r"submitted by .*$", "", plain).strip()


def score(text: str) -> tuple[int, list[str]]:
    total, hits = 0, []
    for pattern, weight in SIGNALS:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            total += weight
            hits.append(match.group(0).lower())
    return total, hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hours", type=int, default=48)
    parser.add_argument("--all", action="store_true", help="include posts reported before")
    args = parser.parse_args()

    seen = set(json.loads(STATE.read_text())) if STATE.exists() else set()
    since = datetime.now(timezone.utc) - timedelta(hours=args.hours)
    found, errors = [], []
    for sub in SUBREDDITS:
        try:
            root = ET.fromstring(fetch(f"https://www.reddit.com/r/{sub}/new/.rss?limit=100"))
        except Exception as error:  # one failing feed must not hide the others
            errors.append(f"r/{sub}: {error}")
            continue
        for entry in root.iter(f"{ATOM}entry"):
            post_id = entry.findtext(f"{ATOM}id", "")
            updated = datetime.fromisoformat(entry.findtext(f"{ATOM}updated", "").replace("Z", "+00:00"))
            if updated < since or (post_id in seen and not args.all):
                continue
            title = html.unescape(entry.findtext(f"{ATOM}title", ""))
            body = text_of(entry.findtext(f"{ATOM}content", ""))
            points, hits = score(f"{title} {body}")
            if points < MIN_SCORE:
                continue
            link = entry.find(f"{ATOM}link").get("href", "")
            found.append({"id": post_id, "sub": sub, "title": title, "body": body[:600],
                          "launch": bool(LAUNCH_POST.search(f"{title} {body[:300]}")),
                          "link": link, "score": points, "hits": hits, "updated": updated})
        time.sleep(8)  # Reddit rate-limits anonymous feed reads; space them out

    found.sort(key=lambda post: (-post["score"], post["updated"]))
    threads = [post for post in found if not post["launch"]]
    launches = [post for post in found if post["launch"]]
    print(f"# Reddit digest, {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
    print(f"{len(threads)} threads worth a look and {len(launches)} competitor launches "
          f"in the last {args.hours} h across {len(SUBREDDITS)} subreddits.\n")
    for heading, posts in (("Threads worth a look", threads), ("Competitor launches", launches)):
        if not posts:
            continue
        print(f"# {heading}\n")
        for post in posts:
            age = (datetime.now(timezone.utc) - post["updated"]).total_seconds() / 3600
            print(f"## [{post['title']}]({post['link']})")
            print(f"r/{post['sub']} · {age:.0f} h ago · score {post['score']} · matched: {', '.join(post['hits'])}\n")
            print(f"> {post['body'] or '(no text)'}\n")
    if errors:
        print("Feeds that failed: " + "; ".join(errors))

    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(sorted(seen | {post["id"] for post in found})[-5000:]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
