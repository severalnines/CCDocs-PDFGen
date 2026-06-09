#!/usr/bin/env python3
"""
Parse mkdocs.yml nav section and copy all referenced .md files
to a target directory, preserving the directory structure.

Paths are read from:
  ../conf/config.ini  (relative to this script)

Required keys under [cc_gen_pdf_paths]:
  CC_MKDOCS_YML        - full path to mkdocs.yml
  CC_MKDOCS_SOURCE_DIR - full path to the docs/ directory containing .md files
  CC_SPHINX_SRC_DIR   - full path to the destination directory
"""

import configparser
import os
import shutil
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Custom YAML loader that silently ignores unknown Python-specific tags such
# as  !!python/name:material.extensions.emoji.twemoji  used by MkDocs
# Material theme.  safe_load() raises a ConstructorError on those tags, so
# we register a catch-all constructor that just returns None for any tag that
# the SafeLoader does not already know about.
# ---------------------------------------------------------------------------
class _IgnoreUnknownTagsLoader(yaml.SafeLoader):
    pass


def _ignore_unknown(loader, tag_suffix, node):
    """Return None for any unrecognised YAML tag."""
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    return loader.construct_scalar(node)


_IgnoreUnknownTagsLoader.add_multi_constructor(
    "",  # matches every tag prefix
    _ignore_unknown,
)


class ConfigError(Exception):
    pass


def load_config(config_file):
    """Load configuration from INI file."""
    if not os.path.exists(config_file):
        try:
            raise ConfigError(f"Configuration file '{config_file}' not found or does not exist!")
        except ConfigError as e:
            print(e)
            sys.exit(1)

    config = configparser.ConfigParser()
    config.read(config_file)
    return config


def extract_md_files(nav_item):
    """Recursively extract all .md file paths from a nav item."""
    md_files = []

    if isinstance(nav_item, str):
        if nav_item.endswith(".md"):
            md_files.append(nav_item)
    elif isinstance(nav_item, dict):
        for value in nav_item.values():
            md_files.extend(extract_md_files(value))
    elif isinstance(nav_item, list):
        for item in nav_item:
            md_files.extend(extract_md_files(item))

    return md_files


def copy_docs(mkdocs_yml: Path, source_docs: Path, target_dir: Path):
    """Parse mkdocs.yml nav and copy referenced .md files to target_dir."""
    with open(mkdocs_yml, "r") as f:
        config = yaml.load(f, Loader=_IgnoreUnknownTagsLoader)

    nav = config.get("nav", [])
    md_files = extract_md_files(nav)

    target_dir.mkdir(parents=True, exist_ok=True)

    copied = 0
    missing = 0

    for rel_path in md_files:
        src = source_docs / rel_path
        dst = target_dir / rel_path

        if not src.exists():
            print(f"  [MISSING]  {src}")
            missing += 1
            continue

        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        print(f"  [COPIED]   {rel_path}")
        copied += 1

    print("-" * 60)
    print(f"Summary:")
    print(f"  Files copied : {copied}")
    print(f"  Files missing: {missing}")
    print(f"  Total in nav : {len(md_files)}")


def copy_image_dir(source_docs: Path, target_dir: Path):

    src = source_docs / "images"
    dst = target_dir / "images"

    if not src.exists():
        print(f"Error: images directory from path 'source_docs' not found!", file=sys.stderr)
        sys.exit(1)

    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst,dirs_exist_ok=True)
    print(f"FINALLY: IMAGES DIRECTORY COPIED TO PATH {dst}")



def main():
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    config = load_config(os.path.join(BASE_DIR, "..", "conf", "config.ini"))

    home = os.environ.get("HOME", "")
    section = "cc_gen_pdf_paths"

    mkdocs_yml  = Path(config.get(section, "CC_MKDOCS_YML",        fallback=f"{home}/cc-docs/mkdocs.yml"))
    source_docs = Path(config.get(section, "CC_MKDOCS_SOURCE_DIR", fallback=f"{home}/cc-docs/docs/"))
    target_dir  = Path(config.get(section, "CC_SPHINX_SRC_DIR",   fallback=f"{home}/cc-manual-gen/sphinx/src/"))

    print(f"Config loaded! See allocated params:")
    print(f"  CC_MKDOCS_YML       : {mkdocs_yml}")
    print(f"  CC_MKDOCS_SOURCE_DIR: {source_docs}")
    print(f"  CC_SPHINX_SRC_DIR  : {target_dir}")
    print("-" * 60)

    if not mkdocs_yml.exists():
        print(f"Error: mkdocs.yml not found at '{mkdocs_yml}'!", file=sys.stderr)
        sys.exit(1)

    if not source_docs.exists():
        print(f"Error: Source docs directory '{source_docs}' not found!", file=sys.stderr)
        sys.exit(1)

    copy_docs(mkdocs_yml, source_docs, target_dir)
    
    ## Finally, copy the images directory
    copy_image_dir(source_docs, target_dir)


if __name__ == "__main__":
    main()
