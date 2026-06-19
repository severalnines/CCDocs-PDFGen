import configparser
import fnmatch
import os, sys
from datetime import datetime
from pathlib import Path

class ConfigError(Exception):
    pass


def log(message: str, log_file: Path | None = None, error: bool = False) -> None:
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {message}"
    print(line, file=sys.stderr if error else sys.stdout)
    if log_file is not None:
        with open(log_file, "a") as f:
            f.write(line + "\n")


def load_config(config_file: str):
    """Load and return configuration from an INI file."""
    if not os.path.exists(config_file):
        log(f"Configuration file '{config_file}' not found!", error=True)
        sys.exit(1)
    cfg = configparser.ConfigParser()
    cfg.read(config_file)
    return cfg


def load_ignore_patterns(ignore_file):
    """Load ignore patterns from an external file.

    Returns a list of the non-blank, non-comment lines. If the file does not
    exist, logs a warning and returns an empty list (ignores are optional).
    """
    patterns = []
    if not os.path.exists(ignore_file):
        log(f"WARNING: Ignore file '{ignore_file}' not found. "
            f"Proceeding without ignores.", error=True)
        return patterns

    with open(ignore_file, "r") as f:
        for line in f:
            line = line.strip()
            # Skip empty lines and comments
            if line and not line.startswith("#"):
                patterns.append(line)

    return patterns


def is_ignored(path, ipatterns):
    # ignore the whole path from its parent down to its children if it matches any of the patterns.
    path = path.strip("/")
    for ipat in ipatterns:
        ipat = ipat.strip()
        if not ipat:
            continue
        # Directory-style pattern -> reduce to its base directory.
        base = ipat[:-2] if ipat.endswith("/*") else ipat
        base = base.rstrip("/")
        if base and (path == base or path.startswith(base + "/")):
            return True
        # then ignore the path if it matches the pattern from ignored patterns (from ignore file)
        if fnmatch.fnmatch(path, ipat):
            return True
    return False
