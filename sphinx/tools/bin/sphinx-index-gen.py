#!/usr/bin/env python3
"""
sphinx-index-gen.py

Reads tools/conf/order-sections.yaml and generates Sphinx index.md files
in CC_SPHINX_SRC_DIR for the root and for each top-level section.

Root  →  CC_SPHINX_SRC_DIR/index.md
            Uses index_main_template.md.
            {files} = top-level section slugs, one per line (e.g. getting-started).

Per-section  →  CC_SPHINX_SRC_DIR/<section>/index.md
            Uses index_sub_template.md.
            {title} = human title derived from the slug.
            {files} = section labels interspersed with Sphinx refs:
              - Section labels kept as-is from YAML with colon appended (hyphens preserved)
              - File paths: hyphens removed, .md stripped (index stays as index)

Example: given the YAML fragment under "getting-started":
  - tutorials:
    - getting-started/tutorials/index.md
    - day-1-operations:
      - your-first-cluster:
        - mysql-mariadb:
          - getting-started/tutorials/.../standalone.md

Output lines written to {files}:
  tutorials:
  gettingstarted/tutorials/index
  day-1-operations:
  your-first-cluster:
  mysql-mariadb:
  gettingstarted/tutorials/.../standalone

File path transformation rules:
  1. Strip .md extension
  2. Remove hyphens from ALL path characters
  → getting-started/overview/how-it-works.md  →  gettingstarted/overview/howitworks
  → getting-started/tutorials/index.md        →  gettingstarted/tutorials/index
  → getting-started/installation/online-installation.md → gettingstarted/installation/onlineinstallation

Section label rules:
  → kept exactly as they appear in order-sections.yaml, colon appended
  → tutorials            →  tutorials:
  → day-1-operations     →  day-1-operations:
  → your-first-cluster   →  your-first-cluster:
  → mysql-mariadb        →  mysql-mariadb:
"""

import configparser
import os
import sys
import pprint,json
import shutil
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Config loader
# ---------------------------------------------------------------------------

class ConfigError(Exception):
    pass


def load_config(config_file: str):
    if not os.path.exists(config_file):
        raise ConfigError(f"Config file not found: {config_file}")
    cfg = configparser.ConfigParser()
    cfg.read(config_file)
    return cfg


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def slug_to_title(slug: str) -> str:
    """Convert a kebab-case slug to a human-readable title.

    Examples:
      "getting-started"      → "Getting Started"
      "administration-guide" → "Administration Guide"
      "reference-manuals"    → "Reference Manuals"
    """
    return " ".join(word.capitalize() for word in slug.replace("-", " ").split())


def to_file_ref(path: str) -> str:
    """Convert a docs-relative .md path to a Sphinx toctree reference.

    Rules:
      1. Strip .md extension.
      2. Remove ALL hyphens from the path string.

    index.md is NOT replaced with the parent directory name — it stays as 'index'.

    Examples:
      getting-started/tutorials/index.md         → gettingstarted/tutorials/index
      getting-started/overview/how-it-works.md   → gettingstarted/overview/howitworks
      getting-started/installation/online-installation.md
          → gettingstarted/installation/onlineinstallation
      getting-started/tutorials/day-1-operations/your-first-cluster/mysql/standalone.md
          → gettingstarted/tutorials/day1operations/yourfirstcluster/mysql/standalone
    """
    # Strip .md
    if path.endswith(".md"):
        path = path[:-3]
    # Remove all hyphens
    # path = path.replace("-", "")
    return path


# ---------------------------------------------------------------------------
# Nav → output lines  (section labels + file refs, structure preserved)
# ---------------------------------------------------------------------------

def nav_to_lines(nav_item: list, top_level_slugs: list=None) -> list:
    """Recursively convert a nav subtree into output lines.

    Rules:
      str   → convert to file ref via to_file_ref(), append as a line
      dict  → for each {slug: children}: emit "slug:" label line, then recurse
      list  → recurse into each element in order
    """
    lines = []

    if (top_level_slugs is not None):
        top_level_dict = {slug: slug for slug in top_level_slugs}

    if isinstance(nav_item, str):        
        # if (top_level_slugs is not None):
        #     print(json.dumps({"is-instance-nav_item":label,"top_level_slugs": top_level_slugs}, indent=2))
        lines.append(to_file_ref(nav_item))

    elif isinstance(nav_item, dict):
        for label, children in nav_item.items():
            #lines.append(label + ":")       # section label kept as-is, colon added
            lines.extend(nav_to_lines(children))

    elif isinstance(nav_item, list):
        for item in nav_item:
            if isinstance(item, str) and top_level_slugs is not None:
                file_md = Path(item).parent.name
                matched_slug = top_level_dict.get(file_md)
                
                # print(json.dumps({"item-value":item, "boolean-value": (item.endswith("/index.md")), "matched_slug":matched_slug, "file_md": file_md}, indent=2))
                                                
                if item.endswith("/index.md") and matched_slug == file_md:
                    lines.append((matched_slug + "/" + matched_slug))
                    # print(json.dumps({"lines-value":lines}, indent=2))
        
                    continue
                    
            lines.extend(nav_to_lines(item))

    return lines


def move_top_level_md_file(nav_item: list, sphinx_src_dir: Path):
    
    first_child = next(iter(nav_item), None)
    top_level_md_idxfile = sphinx_src_dir / first_child
    # print(json.dumps({"first_child":first_child,"sphinx_src_dir": str(sphinx_src_dir)}, indent=2))

    if first_child is None:
        return
        
    if not top_level_md_idxfile.exists():
        return
    
    if first_child is not None and top_level_md_idxfile.exists():
        p = Path(top_level_md_idxfile)
        top_level_md_newfile = p.parent / (p.parent.name + ".md")
        shutil.move(Path((sphinx_src_dir / first_child)), Path(sphinx_src_dir / top_level_md_newfile))
        print(f"  [MOVE] From {(sphinx_src_dir / first_child)} to {(sphinx_src_dir / top_level_md_newfile)}")


def clear_top_level_names(context_per_line: list, top_level_slugs: list) -> list:
    
    cleaned_context_per_line = []

    for line in context_per_line:
        cleaned_line = line

        for top_level_file in top_level_slugs:
            prefix = top_level_file + "/"

            if line.startswith(prefix):
                # strip the "getting-started/" prefix
                cleaned_line = line[len(prefix):]
                break  # no need to check other slugs once matched
            
            continue

        cleaned_context_per_line.append(cleaned_line)

    return cleaned_context_per_line
     

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    BASE_DIR = Path(os.path.dirname(os.path.abspath(__file__)))
    CONF_DIR = BASE_DIR.parent / "conf"
    TMPL_DIR = BASE_DIR.parent / "template"   # directory is named "template"

    config_file    = CONF_DIR / "config.ini"
    order_file     = CONF_DIR / "order-sections.yaml"
    main_tmpl_file = TMPL_DIR / "index_main_template.md"
    sub_tmpl_file  = TMPL_DIR / "index_sub_template.md"
    top_level_tmpl_file  = TMPL_DIR / "index_top_level_template.md"

    # ── load config.ini ──────────────────────────────────────────────────────
    try:
        cfg = load_config(str(config_file))
    except ConfigError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    ini_section = "cc_gen_pdf_paths"
    home        = os.environ.get("HOME", "")
    sphinx_src_dir    = Path(
        cfg.get(ini_section, "CC_SPHINX_SRC_DIR",
                fallback=f"{home}/cc-manual-gen/sphinx/src")
    ).expanduser()

    print("Config loaded!")
    print(f"  CC_SPHINX_SRC_DIR : {sphinx_src_dir}")
    print(f"  order-sections     : {order_file}")
    print(f"  main template      : {main_tmpl_file}")
    print(f"  sub  template      : {sub_tmpl_file}")
    print("-" * 60)

    # ── validate required files ───────────────────────────────────────────────
    for path, label in [
        (order_file,     "order-sections.yaml"),
        (main_tmpl_file, "index_main_template.md"),
        (sub_tmpl_file,  "index_sub_template.md"),
        (top_level_tmpl_file,  "index_top_level_template.md")
    ]:
        if not path.exists():
            print(f"ERROR: {label} not found at '{path}'", file=sys.stderr)
            sys.exit(1)

    # ── read order-sections.yaml ─────────────────────────────────────────────
    with open(order_file, "r", encoding="utf-8") as fh:
        nav = yaml.safe_load(fh)

    if not nav:
        print("ERROR: order-sections.yaml is empty.", file=sys.stderr)
        sys.exit(1)

    # ── read templates ────────────────────────────────────────────────────────
    main_tmpl = main_tmpl_file.read_text(encoding="utf-8")
    sub_tmpl  = sub_tmpl_file.read_text(encoding="utf-8")
    top_level_tmpl  = top_level_tmpl_file.read_text(encoding="utf-8")

    # ── collect top-level section slugs (skip bare strings like "index.md") ──
    top_level_slugs = []
    for item in nav:
        if isinstance(item, dict):
            for key in item:
                top_level_slugs.append(key)


    #pprint.pprint(top_level_slugs)
    # print(json.dumps(top_level_slugs, indent=2))
    # sys.exit(0)
    
    
    
    # ── write root CC_SPHINX_SRC_DIR/index.md ───────────────────────────────
    sphinx_src_dir.mkdir(parents=True, exist_ok=True)
    root_index   = sphinx_src_dir / "index.md"
    root_files   = "\n".join(top_level_slugs)
    root_content = main_tmpl.replace("${files}", root_files)
    root_index.write_text(root_content, encoding="utf-8")
    print(f"  [WRITTEN] {root_index}")
    
    # ── write also top-level slugs CC_SPHINX_SRC_DIR/<top-level-slug>.md ───────────────────────────────
    for top_level_file in top_level_slugs:            
        if not (sphinx_src_dir / (top_level_file + ".md")).exists():
            print(f"Creating file {(sphinx_src_dir / (top_level_file + '.md'))}")
            top_level_content = top_level_tmpl.replace("${file}", top_level_file)
            (sphinx_src_dir / (top_level_file + ".md")).write_text(top_level_content, encoding="utf-8")
        else:
            print(f"Top level file {(sphinx_src_dir / (top_level_file + '.md'))} already exist. Skipping ...")
            
    sphinx_src_dir.mkdir(parents=True, exist_ok=True)
    root_index   = sphinx_src_dir / "index.md"
    root_files   = "\n".join(top_level_slugs)
    root_content = main_tmpl.replace("${files}", root_files)
    root_index.write_text(root_content, encoding="utf-8")
    print(f"  [WRITTEN] {root_index}")

    # print(json.dumps(nav, indent=2))
    # sys.exit(0)
    
    # ── write per-section CC_SPHINX_SRC_DIR/<section>/index.md ──────────────
    for item in nav:
        
        if not isinstance(item, dict):
            continue
        
        for section_slug, children in item.items():
            section_dir = sphinx_src_dir / section_slug
            section_dir.mkdir(parents=True, exist_ok=True)
            
            move_top_level_md_file(children, sphinx_src_dir)

            # Build lines: section labels kept as "slug:", file paths as refs
            lines = nav_to_lines(children, top_level_slugs)
            lines = clear_top_level_names(lines,top_level_slugs)

            title   = slug_to_title(section_slug)
            files   = "\n".join(lines)
            content = sub_tmpl.replace("${title}", title).replace("${files}", files)

            section_index = section_dir / "index.md"
            section_index.write_text(content, encoding="utf-8")
            print(f"  [WRITTEN] {section_index}  ({len(lines)} lines)")

    print("-" * 60)
    print(f"Done. Root index + {len(top_level_slugs)} section index file(s) written.")


if __name__ == "__main__":
    main()
