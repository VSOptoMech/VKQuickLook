from __future__ import annotations

import io
import os
import struct
import tempfile
from pathlib import Path
from typing import BinaryIO

from PIL import Image, UnidentifiedImageError

VK4_MAGIC = b"VK4_"
VK6_MAGIC_PREFIX = b"VK6"
MAX_EMBEDDED_PREVIEW_BYTES = 128 * 1024 * 1024
MAX_VK4_RGB_SECTION_BYTES = 256 * 1024 * 1024

VK4_THUMBNAIL_PRIORITY: tuple[tuple[int, str, str], ...] = (
    (10, "clr_thumb", "Color thumbnail"),
    (9, "clr_peak_thumb", "Peak color thumbnail"),
    (11, "light_thumb", "Light thumbnail"),
    (12, "height_thumb", "Height thumbnail"),
)


class ThumbnailError(ValueError):
    """A concise, user-facing thumbnail generation failure."""


def render_thumbnail(input_path: str | Path, output_path: str | Path, size: int) -> None:
    source = Path(input_path)
    output = Path(output_path)
    if size <= 0:
        raise ThumbnailError("--size must be a positive integer")
    if not source.is_file():
        raise ThumbnailError(f"input file does not exist: {source}")

    with source.open("rb") as handle:
        magic = _read_exact(handle, 4, "file header")
        handle.seek(0)
        if magic == VK4_MAGIC:
            image = _load_vk4_thumbnail(handle, source)
        elif magic[:3] == VK6_MAGIC_PREFIX:
            image = _load_vk6_bmp_preview(handle, source)
        else:
            ext = source.suffix.lower()
            if ext not in {".vk4", ".vk6"}:
                raise ThumbnailError(f"unsupported input file: {source.name}; expected .vk4 or .vk6")
            raise ThumbnailError(f"invalid VK file header: {source.name}")

    rendered = _fit_image(image, size)
    _write_png(rendered, output, source)


def _load_vk6_bmp_preview(handle: BinaryIO, source: Path) -> Image.Image:
    file_size = source.stat().st_size
    header = _read_exact(handle, 7, "VK6 header")
    bmp_size = struct.unpack_from("<I", header, 3)[0]
    if bmp_size <= 0 or bmp_size > MAX_EMBEDDED_PREVIEW_BYTES:
        raise ThumbnailError(f"invalid VK6 embedded BMP size: {bmp_size} bytes")
    if 7 + bmp_size > file_size:
        raise ThumbnailError("invalid VK6 container: embedded BMP span exceeds file size")

    bmp = _read_exact(handle, bmp_size, "VK6 embedded BMP preview")
    if bmp[:2] != b"BM":
        raise ThumbnailError("invalid VK6 container: missing embedded BMP header")
    try:
        with Image.open(io.BytesIO(bmp)) as image:
            return image.convert("RGB")
    except (UnidentifiedImageError, OSError) as exc:
        raise ThumbnailError("unable to decode embedded VK6 BMP preview") from exc


def _load_vk4_thumbnail(handle: BinaryIO, source: Path) -> Image.Image:
    file_size = source.stat().st_size
    if file_size < 84:
        raise ThumbnailError(f"file too small to be a valid VK4 file: {source.name}")

    rejected: list[str] = []
    for slot, key, _label in VK4_THUMBNAIL_PRIORITY:
        offset = _read_vk4_section_offset(handle, file_size, slot, key)
        if offset == 0:
            continue
        try:
            return _read_vk4_rgb_section(handle, file_size, offset, key)
        except ThumbnailError as exc:
            rejected.append(f"{key}: {exc}")

    if rejected:
        raise ThumbnailError(f"no usable VK4 thumbnail found in {source.name}: {'; '.join(rejected)}")
    raise ThumbnailError(f"no embedded VK4 thumbnail found in {source.name}")


def _read_vk4_section_offset(handle: BinaryIO, file_size: int, slot: int, key: str) -> int:
    table_offset = 12
    table_size = 18 * 4
    _ensure_span(file_size, table_offset, table_size, "VK4 offset table")
    offset_position = table_offset + slot * 4
    handle.seek(offset_position)
    offset = struct.unpack("<I", _read_exact(handle, 4, f"VK4 {key} offset"))[0]
    if offset:
        _ensure_span(file_size, offset, 4, f"VK4 {key} section")
    return offset


def _read_vk4_rgb_section(handle: BinaryIO, file_size: int, offset: int, key: str) -> Image.Image:
    _ensure_span(file_size, offset, 20, f"{key} header")
    handle.seek(offset)
    header = _read_exact(handle, 20, f"{key} header")
    width, height, bit_depth, compression, data_byte_size = struct.unpack("<IIIII", header)
    if width <= 0 or height <= 0:
        raise ThumbnailError(f"invalid dimensions: {width}x{height}")
    if bit_depth != 24 or compression != 0:
        raise ThumbnailError("unsupported image encoding")

    pixel_count = _checked_pixel_count(width, height, 3, key)
    expected_bytes = pixel_count * 3
    if data_byte_size < expected_bytes:
        raise ThumbnailError("incomplete image data")
    if expected_bytes > MAX_VK4_RGB_SECTION_BYTES or data_byte_size > MAX_VK4_RGB_SECTION_BYTES:
        raise ThumbnailError("refusing oversized image data")
    _ensure_span(file_size, offset + 20, data_byte_size, f"{key} data")
    rgb = _read_exact(handle, expected_bytes, f"{key} RGB data")
    try:
        return Image.frombytes("RGB", (width, height), rgb)
    except ValueError as exc:
        raise ThumbnailError("unable to decode RGB thumbnail data") from exc


def _fit_image(image: Image.Image, size: int) -> Image.Image:
    rendered = image.copy()
    if rendered.mode not in {"RGB", "RGBA"}:
        rendered = rendered.convert("RGB")
    if max(rendered.size) > size:
        rendered.thumbnail((size, size), Image.Resampling.LANCZOS)
    return rendered


def _write_png(image: Image.Image, output: Path, source: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if _same_directory(output.parent, source.parent):
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")
        output.write_bytes(buffer.getvalue())
        return

    temp_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix=f".{output.name}.",
            suffix=".tmp.png",
            dir=output.parent,
            delete=False,
        ) as temp_file:
            temp_name = temp_file.name
            image.save(temp_file, format="PNG")
        os.replace(temp_name, output)
        temp_name = None
    finally:
        if temp_name is not None:
            try:
                os.unlink(temp_name)
            except FileNotFoundError:
                pass


def _same_directory(left: Path, right: Path) -> bool:
    try:
        return left.resolve() == right.resolve()
    except OSError:
        return False


def _read_exact(handle: BinaryIO, count: int, label: str) -> bytes:
    data = handle.read(count)
    if len(data) != count:
        raise ThumbnailError(f"unexpected end of file while reading {label}")
    return data


def _ensure_span(file_size: int, offset: int, size: int, label: str) -> None:
    if offset < 0 or size < 0 or offset + size > file_size:
        raise ThumbnailError(f"invalid {label} span")


def _checked_pixel_count(width: int, height: int, bytes_per_pixel: int, key: str) -> int:
    pixel_count = width * height
    if pixel_count <= 0:
        raise ThumbnailError(f"invalid {key} dimensions")
    if pixel_count > MAX_VK4_RGB_SECTION_BYTES // bytes_per_pixel:
        raise ThumbnailError(f"{key} dimensions are too large")
    return pixel_count
