#!/usr/bin/env python3
"""
create-index-templates.py

Recursively walks a root directory and generates an `index.md` file
inside any subdirectory that contains a Markdown file matching the
subdirectory's own name (e.g., admin-guide/admin-guide.md).

The generated `index.md` is built from an external template file.

Usage:
    python create-index-template.py --root <path-to-root> --template <path-to-template>
    
    or

    python create-index-template.py --root <path-to-root> --template <path-to-template> --overwrite
Example:
    python create-index-template.py --root ./src-test --template ./index_template.md
"""

import os
import argparse
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
script_dir = Path(__file__).parent
INDEX_FILENAME = "index.md"
INDEX_MAIN_FILE_TEMPLATE = script_dir.parent/"conf"/"index_main_template.md"
INDEX_SUB_FILE_TEMPLATE = script_dir.parent/"conf"/"index_sub_template.md"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_template(template_path: str) -> str:
    """
    Load and return the raw contents of the external template file.

    Args:
        template_path: Absolute or relative path to the template file.

    Returns:
        The template string.

    Raises:
        FileNotFoundError: If the template file does not exist.
    """
    
    if not os.path.isfile(template_path):
        raise FileNotFoundError(
            f"[ERROR] Template file not found: {template_path}"
        )

    with open(template_path, "r", encoding="utf-8") as fh:
        return fh.read()


def should_create_index(dir_path: str, dir_name: str) -> bool:
    """
    Determine whether an index.md should be created inside `dir_path`.

    The rule: the directory must contain a Markdown file whose stem
    (filename without extension) exactly matches the directory name.

    Args:
        dir_path: Full path to the directory being inspected.
        dir_name: The bare name of the directory (e.g. 'admin-guide').

    Returns:
        True  → create index.md
        False → skip this directory
    """
    trigger_file = f"{dir_name}.md"
    return os.path.isfile(os.path.join(dir_path, trigger_file))


def collect_md_files(dir_path: str) -> list[str]:
    """
    Return a sorted list of all *.md filenames that live *directly*
    inside `dir_path`, excluding any pre-existing or to-be-created
    index.md file.

    Only files (not subdirectories) at the immediate level are included
    so that nested sub-folders are not mixed into the toctree list.

    Args:
        dir_path: Full path to the directory.

    Returns:
        Sorted list of filenames, e.g. ['admin-guide.md', 'housekeeping.md']
    """
    entries = []

    for entry in os.scandir(dir_path):
        if (
            entry.is_file()
            and entry.name.endswith(".md")
            and entry.name.lower() != INDEX_FILENAME
        ):
            entry_str = Path(entry.name).stem
            # print(f"[DEBUG] Only file..... Entry is: {entry_str}")
            entries.append(entry_str)
        elif entry.is_dir() :
            if entry.name != "images" :
                entries.append(f"{entry.name}/index")
        #else :
        #    return entries

    return sorted(entries)


def render_template(template: str, dir_name: str, md_files: list[str], is_root_dir: bool = False) -> str:
    """
    Substitute placeholders in the template string.

    Placeholders:
        {title}  → the directory name used as the H1 heading
        {files}  → newline-separated list of .md filenames

    Args:
        template:  Raw template string loaded from disk.
        dir_name:  Name of the subdirectory (e.g. 'admin-guide').
        md_files:  Sorted list of .md filenames to list in the toctree.

    Returns:
        Fully rendered string ready to be written to index.md.
    """
    files_block = "\n".join(md_files)
    # print(f"[DEBUG] files_block  value is: {files_block}")
    # print(f"[DEBUG] dir_name  value is: {dir_name}")
    # print(f"[DEBUG] The contents to be written should be: {template.format(title=dir_name, files=files_block)} ")
    if is_root_dir :
        return template.format(title="", files=files_block)
    else :
        return template.format(title=dir_name, files=files_block)


def write_index(index_path: str, content: str, overwrite: bool = False) -> bool:
    """
    Write the rendered content to `index_path`.

    Args:
        index_path: Full path where index.md will be written.
        content:    Rendered Markdown string.
        overwrite:  If False (default) and the file already exists, skip.

    Returns:
        True  → file was written
        False → file was skipped (already exists and overwrite=False)
    """
    if os.path.exists(index_path) and not overwrite:
        print(f"  [SKIP]    Already exists → {index_path}")
        return False

    # print(f"[DEBUG] Going to write to file {index_path} with content {content}.........")
    with open(index_path, "w", encoding="utf-8") as fh:
        fh.write(content)

    return True

# ---------------------------------------------------------------------------
# CLI entry-point
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate index.md files in subdirectories that contain "
            "a Markdown file matching the directory name."
        )
    )
    parser.add_argument(
        "--root",
        required=True,
        help="Path to the root documentation directory (e.g. {ROOT_OF_SPHINX/src).",
    )
    parser.add_argument(
        "--template",
        action="store_true",
        default=INDEX_SUB_FILE_TEMPLATE,
        help="Path to the external Markdown template file (defaults to ../conf/index_sub_template.md).",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        default=False,
        help="Overwrite existing index.md files (default: skip them).",
    )
    return parser.parse_args()

# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

def process_directory_tree(root: str, template: str, overwrite: bool) -> None:
    """
    Walk the entire directory tree under `root` and generate index.md
    files wherever the naming convention is satisfied.

    Args:
        root:      Root directory to start the walk from.
        template:  Raw template string.
        overwrite: Whether to overwrite existing index.md files.
    """
    root = os.path.abspath(root)

    if not os.path.isdir(root):
        print(f"[ERROR] Root path is not a directory: {root}")
        sys.exit(1)

    print(f"\n🔍  Scanning: {root}\n")

    created_count = 0
    skipped_count = 0
    checked_count = 0

    # os.walk yields (dirpath, subdirs, files) for every node in the tree.
    # We skip the root itself — it is never treated as a "subdirectory".
    for dirpath, dirnames, _ in os.walk(root):

        dir_name = os.path.basename(dirpath)
        checked_count += 1
        is_root_dir = os.path.abspath(dirpath) == root
        
        # print(f"  [CHECKING - debug]  os.path.abspath(dirpath) is '{os.path.abspath(dirpath)}")
        # print(f"  [CHECKING - debug]  root is '{root}")
        # print(f"  [CHECKING - debug]  IS IT TRUE??? '{os.path.abspath(dirpath) == root}")

        # ── Gate: only proceed when <dir_name>.md exists inside ──────────
        if not should_create_index(dirpath, dir_name) and not is_root_dir:
            print(f"  [IGNORE]  No matching file '{dir_name}.md' → {dirpath}")
            continue

        # ── Collect sibling .md files (direct children only) ─────────────
        md_files = collect_md_files(dirpath)

        if not md_files and not is_root_dir:
            print(f"  [WARN]    No .md files found inside → {dirpath}")
            continue

        # Create the main index root
        if is_root_dir:
            print(f"  [CHECKING - ROOT MAIN INDEX]  Expecting to create the main index file here....")
            # ── Render and write ──────────────────────────────────────────────
            str_main_template = INDEX_MAIN_FILE_TEMPLATE.read_text()
            rendered = render_template(str_main_template, dir_name, md_files, is_root_dir)
            index_path = os.path.join(dirpath, INDEX_FILENAME)
            was_written = write_index(index_path, rendered, overwrite=overwrite)
            
            if was_written:
                print(f"  [CREATED_ROOT_INDEX] {index_path}")
                created_count += 1
            else:
                skipped_count += 1
        else:
            # ── Render and write ──────────────────────────────────────────────
            str_sub_template = INDEX_SUB_FILE_TEMPLATE.read_text()
            rendered = render_template(str_sub_template, dir_name, md_files)
            index_path = os.path.join(dirpath, INDEX_FILENAME)
            was_written = write_index(index_path, rendered, overwrite=overwrite)
            
            if was_written:
                print(f"  [CREATED] {index_path}")
                created_count += 1
            else:
                skipped_count += 1
            



    # ── Summary ───────────────────────────────────────────────────────────
    print(f"\n{'─'*60}")
    print(f"  Directories checked : {checked_count}")
    print(f"  index.md created    : {created_count}")
    print(f"  index.md skipped    : {skipped_count}")
    print(f"{'─'*60}\n")


def main() -> None:
    args = parse_args()

    # Load the template once — fail fast if it's missing
    try:
        template = load_template(args.template)
    except FileNotFoundError as exc:
        print(exc)
        sys.exit(1)

    process_directory_tree(
        root=args.root,
        template=template,
        overwrite=args.overwrite,
    )


if __name__ == "__main__":
    main()