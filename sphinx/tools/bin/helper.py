import sys
from datetime import datetime
from pathlib import Path


def log(message: str, log_file: Path | None = None, error: bool = False) -> None:
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {message}"
    print(line, file=sys.stderr if error else sys.stdout)
    if log_file is not None:
        with open(log_file, "a") as f:
            f.write(line + "\n")
