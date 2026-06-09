#!/usr/bin/env python3
"""
md_to_sphinx.py

Discovers and runs all bash helper scripts under sphinx/tools/helpers/ in
sorted order. Each helper is responsible for converting a specific set of
MkDocs tags or syntax that is incompatible with Sphinx/MyST.

Each helper script is called with one positional argument:
  $1 = CC_SPHINX_SRC_DIR  (the sphinx/src directory)

Usage:
  python sphinx/tools/bin/md_to_sphinx.py
"""

import configparser
import os
import subprocess
import sys
import helper
from pathlib import Path


class ConfigError(Exception):
    pass


def load_config(config_file: str):
    if not os.path.exists(config_file):
        raise ConfigError(f"Config file not found: {config_file}")
    cfg = configparser.ConfigParser()
    cfg.read(config_file)
    return cfg


def main():
    BASE_DIR = Path(os.path.dirname(os.path.abspath(__file__)))
    CONF_DIR = BASE_DIR.parent / "conf"
    HELPERS_DIR = BASE_DIR.parent / "helpers"
    LOGS_DIR = BASE_DIR.parent / "logs"

    config_file = CONF_DIR / "config.ini"

    home = os.environ.get("HOME", "")
    ini_section = "cc_gen_pdf_paths"

    try:
        cfg = load_config(str(config_file))
    except ConfigError as e:
        helper.log(f"ERROR: {e}")
        sys.exit(1)

    sphinx_src_dir = Path(
        cfg.get(ini_section, "CC_SPHINX_SRC_DIR",
                fallback=f"{home}/cc-manual-gen/sphinx/src")
    ).expanduser()
    cc_log_file = Path(
        cfg.get(ini_section, "CC_LOG_FILE",
                fallback=f"{home}/cc-manual-gen/sphinx/logs/pdf_gen.log")
    ).expanduser()

    cc_log_file.parent.mkdir(parents=True, exist_ok=True)

    helper.log("Config loaded!", cc_log_file)
    helper.log(f"  CC_SPHINX_SRC_DIR : {sphinx_src_dir}", cc_log_file)
    helper.log(f"  CC_LOG_FILE       : {cc_log_file}", cc_log_file)
    helper.log(f"  Helpers directory  : {HELPERS_DIR}", cc_log_file)
    helper.log("-" * 60, cc_log_file)

    if not sphinx_src_dir.exists():
        helper.log(f"ERROR: Destination directory '{sphinx_src_dir}' does not exist.", cc_log_file, error=True)
        helper.log("       Run copy-docs-ver2.py first.", cc_log_file, error=True)
        sys.exit(1)

    if not HELPERS_DIR.exists():
        helper.log(f"ERROR: Helpers directory '{HELPERS_DIR}' not found.", cc_log_file, error=True)
        sys.exit(1)

    ## only run scripts that start with a number and have an underscore (e.g. 01_convert_images.sh) to ensure order and avoid running non-helper scripts
    scripts = sorted(s for s in HELPERS_DIR.glob("*.sh") if s.name[0].isdigit() and "_" in s.name)

    if not scripts:
        helper.log("No helper scripts found in helpers/. Nothing to do.", cc_log_file)
        sys.exit(0)

    helper.log(f"Found {len(scripts)} helper script(s). Running in order...", cc_log_file)

    errors = 0
    for script in scripts:
        helper.log(f"[RUNNING HELPER SCRIPT:] {script.name}", cc_log_file)
        result = subprocess.run(
            ["bash", str(script), str(sphinx_src_dir), str(config_file)],
        )
        if result.returncode != 0:
            helper.log(f"[FAIL] {script.name} exited with code {result.returncode}", cc_log_file, error=True)
            errors += 1
        else:
            helper.log(f"[OK]   {script.name}", cc_log_file)

    helper.log("-" * 60, cc_log_file)
    if errors:
        helper.log(f"Done with {errors} error(s).", cc_log_file, error=True)
        sys.exit(1)
    else:
        helper.log(f"Done. All {len(scripts)} helper script(s) completed successfully.", cc_log_file)


if __name__ == "__main__":
    main()
