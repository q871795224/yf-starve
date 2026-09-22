#!/usr/bin/env python3
"""Serve the repository root for the offline animation browser."""

from __future__ import annotations

import argparse
import functools
import http.server
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    if not (root / "temp" / "animation-lab").is_dir():
        print("Warning: temp/animation-lab is missing; prepare the local reference assets first.")
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
    with http.server.ThreadingHTTPServer((args.host, args.port), handler) as server:
        print(f"Animation lab: http://{args.host}:{args.port}/tools/animation-lab/index.html")
        print("Press Ctrl-C to stop.")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
