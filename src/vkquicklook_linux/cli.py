from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .renderer import ThumbnailError, render_thumbnail


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vk-thumbnailer",
        description="Generate a PNG thumbnail for a Keyence VK4/VK6 measurement file.",
    )
    parser.add_argument("--input", required=True, type=Path, help="Input .vk4 or .vk6 file")
    parser.add_argument("--output", required=True, type=Path, help="Output PNG path")
    parser.add_argument("--size", required=True, type=int, help="Maximum thumbnail edge in pixels")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        render_thumbnail(args.input, args.output, args.size)
    except ThumbnailError as exc:
        print(f"vk-thumbnailer: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"vk-thumbnailer: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
