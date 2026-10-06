#!/usr/bin/env python3
"""Send downloaded ebooks to Kindle through GAM7's Gmail API support."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


GAM = "/opt/gam7/gam"
GAM_CONFIG_DIR = "/config/gam"
FROM_EMAIL_SECRET = Path("/run/secrets/kindle-from-email")
TO_EMAIL_SECRET = Path("/run/secrets/kindle-to-email")
SUPPORTED_TYPES = {".epub", ".pdf"}
MAX_ATTACHMENT_BYTES = 20_000_000


def read_secret(path: Path) -> str:
    value = path.read_text(encoding="utf-8").strip()
    if not value:
        raise ValueError(f"Missing or empty runtime secret: {path}")
    return value


def parse_metadata(arguments: list[str]) -> dict[str, str]:
    if len(arguments) % 2:
        raise ValueError("LazyLibrarian supplied an incomplete metadata pair")

    return {
        arguments[index]: arguments[index + 1]
        for index in range(0, len(arguments), 2)
    }


def main() -> int:
    try:
        metadata = parse_metadata(sys.argv[1:])
        if metadata.get("Event") != "Added to Library":
            return 0
        if metadata.get("AuxInfo") != "eBook":
            return 0

        book_path = Path(metadata.get("BookFile", ""))
        if book_path.suffix.lower() not in SUPPORTED_TYPES:
            raise ValueError(f"Unsupported Kindle ebook format: {book_path.suffix}")
        if not book_path.is_file():
            raise ValueError(f"Downloaded ebook is missing: {book_path}")
        if book_path.stat().st_size > MAX_ATTACHMENT_BYTES:
            raise ValueError(f"Downloaded ebook exceeds the 20 MB mail limit: {book_path.name}")

        sender = read_secret(FROM_EMAIL_SECRET)
        recipient = read_secret(TO_EMAIL_SECRET)
        title = metadata.get("BookName") or book_path.stem

        environment = os.environ.copy()
        environment["GAMCFGDIR"] = GAM_CONFIG_DIR
        subprocess.run(
            [
                GAM,
                "user",
                sender,
                "sendemail",
                "to",
                recipient,
                "from",
                sender,
                "subject",
                title,
                "textmessage",
                "Automatically sent from the Electricpeak book library.",
                "attach",
                str(book_path),
            ],
            check=True,
            env=environment,
        )
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Kindle Gmail API delivery failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
