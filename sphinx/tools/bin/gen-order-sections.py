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


def load_config(config_file: str):
    """Load and return configuration from an INI file."""
    if not os.path.exists(config_file):
        raise ConfigError(f"Configuration file '{config_file}' not found!")
    cfg = configparser.ConfigParser()
    cfg.read(config_file)
    return cfg


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


def transform_nav(nav_item):
    """Recursively transform a mkdocs nav item into the cleaned structure.

    Return values:
      str   – a bare .md path  (title has been stripped)
      dict  – {slug: [children]}  for a section/directory
      list  – a sequence of the above
      None  – item should be omitted from output (URL, empty section, etc.)
    """
    # ── list: recurse into every element ────────────────────────────────────
    if isinstance(nav_item, list):
        out = []
        for item in nav_item:
            transformed = transform_nav(item)
            if transformed is not None:
                out.append(transformed)
        return out if out else None

    # ── bare string: keep only .md paths ────────────────────────────────────
    if isinstance(nav_item, str):
        return nav_item if nav_item.endswith(".md") else None

    # ── dict: MkDocs nav dicts always carry exactly one key ─────────────────
    if isinstance(nav_item, dict):
        for title, value in nav_item.items():

            # Leaf – "Title: path/file.md"  →  just the path
            if isinstance(value, str):
                if value.endswith(".md"):
                    return value      # drop the title, keep the path
                return None           # URL or unknown scalar – skip

            # Section – "Title:\n  - ..."  →  {slug: [children]}
            if isinstance(value, list):
                slug = title_to_slug(title)
                children = transform_nav(value)
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

    # ── load config.ini ──────────────────────────────────────────────────────
    try:
        cfg = load_config(str(config_file))
    except ConfigError as e:
        print(f"ERROR: {e}", file=sys.stderr)
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

    # ── validate inputs ──────────────────────────────────────────────────────
    if not mkdocs_yml.exists():
        print(f"ERROR: mkdocs.yml not found at '{mkdocs_yml}'", file=sys.stderr)
        sys.exit(1)

    # ── parse mkdocs.yml ─────────────────────────────────────────────────────
    with open(mkdocs_yml, "r", encoding="utf-8") as fh:
        mkdocs_config = yaml.load(fh, Loader=_IgnoreUnknownTagsLoader)

    nav = mkdocs_config.get("nav", [])
    if not nav:
        print("ERROR: 'nav' key is missing or empty in mkdocs.yml", file=sys.stderr)
        sys.exit(1)

    # ── transform ────────────────────────────────────────────────────────────
    transformed = transform_nav(nav)
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