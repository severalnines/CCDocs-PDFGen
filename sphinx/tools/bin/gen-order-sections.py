#!/usr/bin/env python3
"""
Parse the nav section from </your-parent-directory/>cc-docs/mkdocs.yml and produce a cleaned
order-sections.yaml in cc-manual-gen/sphinx/tools/conf/ so that we can use this as the basis for
generating the PDF since sphinx is basing the *.md file from mkdocs.

Transformations applied to the nav:
  - Titled .md leaf entries. 
           Example result: 
             "Online Installation: getting-started/...md" to "getting-started/...md"
  - Section/directory titles. Take note, it's based on kebab-case directory slug (checkout https://medium.com/@takat.wicaksono/kebab-case-an-introduction-04d3ca767a20 and https://www.positional.com/blog/slug)
            Example result:
                "Your First Cluster:"  to "your-first-cluster"
                "MySQL/MariaDB:"       to "mysql-mariadb"
                "Day-1 Operations:"    to "day-1-operations"
                "Backup & Restore:"    to "backup-restore"
        This way, we just follow how did mkdocs structure our docuemntation from cc-docs as what originally Ashraf designed.
  - For URL-only entries, good to be skipped
  - Bare .md strings, then keep as is.

Output file (resolved relative to this script):
  ../conf/order-sections.yaml

The mkdocs.yml path is read from:
  ../conf/config.ini  →  [cc_gen_pdf_paths]  →  CC_MKDOCS_YML
"""

import configparser
import os
import re
import sys
import helper
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Custom YAML loader – silently ignores !!python/name:... tags used by the
# MkDocs Material theme so that yaml.load() does not raise ConstructorError.
# ---------------------------------------------------------------------------
class _IgnoreUnknownTagsLoader(yaml.SafeLoader):
    pass


def _ignore_unknown(loader, tag_suffix, node):
    """Return a plain Python object for any unrecognised YAML tag."""
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    return loader.construct_scalar(node)


_IgnoreUnknownTagsLoader.add_multi_constructor("", _ignore_unknown)


# ---------------------------------------------------------------------------
# Config loader
# ---------------------------------------------------------------------------

class ConfigError(Exception):
    pass

# ---------------------------------------------------------------------------
# Nav transformation helpers
# ---------------------------------------------------------------------------

def title_to_slug(title: str) -> str:
    """Convert a human-readable section title to a kebab-case directory slug.

    Conversion steps:
      1. Lowercase the whole string.
      2. Replace  /  &  .  with hyphens (common separators in MkDocs titles).
      3. Strip every character that is not alphanumeric, a space, or a hyphen
         (removes ? ( ) ! etc.).
      4. Collapse consecutive spaces/hyphens into a single hyphen.
      5. Strip any leading/trailing hyphens.

    Examples:
      "Getting Started"             → "getting-started"
      "Your First Cluster"          → "your-first-cluster"
      "Day-1 Operations"            → "day-1-operations"
      "MySQL/MariaDB"               → "mysql-mariadb"
      "PostgreSQL/TimescaleDB"      → "postgresql-timescaledb"
      "Redis/Valkey"                → "redis-valkey"
      "API/SDK"                     → "api-sdk"
      "Backup & Restore"            → "backup-restore"
      "How it Works?"               → "how-it-works"
      "Redundancy & High Availability" → "redundancy-high-availability"
      "v2.3.4 (Latest)"             → "v2-3-4-latest"
    """
    slug = title.lower()
    slug = re.sub(r"[/&.]", "-", slug)          # / & .  →  -
    slug = re.sub(r"[^a-z0-9\s\-]", "", slug)  # drop ? ( ) ! etc.
    slug = re.sub(r"[\s\-]+", "-", slug)        # collapse spaces/hyphens
    return slug


def _is_url(value: str) -> bool:
    return value.startswith(("http://", "https://"))


def transform_nav(nav_item, patterns=None, parent_path=""):
    """Recursively transform a mkdocs nav item into the cleaned structure.

    `patterns` is the list of ignore patterns loaded from ignore_file_list.txt.
    A directory-style pattern (e.g. ``release-notes/*``) drops both the matching
    parent section AND any matching child leaf. `parent_path` accumulates the
    section slugs so a section can be matched as a directory path.

    Return values:
      str   – a bare .md path  (title has been stripped)
      dict  – {slug: [children]}  for a section/directory
      list  – a sequence of the above
      None  – item should be omitted from output (URL, ignored, empty, etc.)
    """
    patterns = patterns or []

    # ── list: recurse into every element ────────────────────────────────────
    if isinstance(nav_item, list):
        out = []
        for item in nav_item:
            transformed = transform_nav(item, patterns, parent_path)
            if transformed is not None:
                out.append(transformed)
        return out if out else None

    # ── bare string: keep only .md paths, skip ignored ones ─────────────────
    if isinstance(nav_item, str):
        if not nav_item.endswith(".md"):
            return None
        if helper.is_ignored(nav_item, patterns):
            return None
        return nav_item

    # ── dict: MkDocs nav dicts always carry exactly one key ─────────────────
    if isinstance(nav_item, dict):
        for title, value in nav_item.items():

            # Leaf – "Title: path/file.md"  →  just the path
            if isinstance(value, str):
                if not value.endswith(".md"):
                    return None       # URL or unknown scalar – skip
                if helper.is_ignored(value, patterns):
                    return None       # ignored child leaf
                return value          # drop the title, keep the path

            # Section – "Title:\n  - ..."  →  {slug: [children]}
            if isinstance(value, list):
                slug = title_to_slug(title)
                section_path = f"{parent_path}/{slug}".strip("/")
                # Skip the WHOLE parent section if its directory is ignored.
                if helper.is_ignored(section_path, patterns):
                    return None
                children = transform_nav(value, patterns, section_path)
                if children:
                    return {slug: children}
                return None           # empty section after filtering

    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    BASE_DIR = Path(os.path.dirname(os.path.abspath(__file__)))
    CONF_DIR = BASE_DIR.parent / "conf"

    config_file = CONF_DIR / "config.ini"
    output_file = CONF_DIR / "order-sections.yaml"
    ignore_file_list = CONF_DIR / "ignore_file_list.txt"

    # ── load config.ini ──────────────────────────────────────────────────────
    try:
        cfg = helper.load_config(str(config_file))
    except helper.ConfigError as e:
        helper.log(f"ERROR: {e}", error=True)
        sys.exit(1)

    home = os.environ.get("HOME", "")
    section = "cc_gen_pdf_paths"

    mkdocs_yml = Path(
        cfg.get(section, "CC_MKDOCS_YML", fallback=f"{home}/cc-docs/mkdocs.yml")
    )

    print("Config loaded!")
    print(f"  CC_MKDOCS_YML : {mkdocs_yml}")
    print(f"  Output file   : {output_file}")
    print("-" * 60)

    # validate inputs
    if not mkdocs_yml.exists():
        print(f"ERROR: mkdocs.yml not found at '{mkdocs_yml}'", file=sys.stderr)
        sys.exit(1)

    # parse mkdocs.yml 
    with open(mkdocs_yml, "r", encoding="utf-8") as fh:
        mkdocs_config = yaml.load(fh, Loader=_IgnoreUnknownTagsLoader)

    patterns = helper.load_ignore_patterns(ignore_file_list)
    print(f"  Ignore patterns : {len(patterns)} loaded from {ignore_file_list.name}")
    for p in patterns:
        print(f"      - {p}")
    print("-" * 60)

    nav = mkdocs_config.get("nav", [])
    if not nav:
        print("ERROR: 'nav' key is missing or empty in mkdocs.yml", file=sys.stderr)
        sys.exit(1)

    # ── transform ────────────────────────────────────────────────────────────
    transformed = transform_nav(nav, patterns)
    if not transformed:
        print("ERROR: nav transformation produced no output.", file=sys.stderr)
        sys.exit(1)

    # ── write order-sections.yaml ────────────────────────────────────────────
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as fh:
        yaml.dump(
            transformed,
            fh,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
            indent=2,
        )

    print(f"  [WRITTEN] {output_file}")
    print(f"  Top-level nav entries : {len(transformed)}")


if __name__ == "__main__":
    main()