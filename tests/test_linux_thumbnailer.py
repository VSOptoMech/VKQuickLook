from __future__ import annotations

import io
import struct
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image

from vkquicklook_linux.renderer import render_thumbnail


REPO_ROOT = Path(__file__).resolve().parents[1]


def test_cli_renders_vk4_with_special_characters(tmp_path: Path) -> None:
    source = tmp_path / "scan with spaces [1] #.vk4"
    output = tmp_path / "thumb out.png"
    source.write_bytes(_synthetic_vk4())
    original = source.read_bytes()

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "vkquicklook_linux.cli",
            "--input",
            str(source),
            "--output",
            str(output),
            "--size",
            "2",
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0
    assert result.stdout == ""
    assert result.stderr == ""
    assert source.read_bytes() == original
    with Image.open(output) as rendered:
        assert rendered.format == "PNG"
        assert max(rendered.size) <= 2


def test_renderer_renders_vk6_embedded_bmp(tmp_path: Path) -> None:
    source = tmp_path / "synthetic.vk6"
    output = tmp_path / "thumb.png"
    source.write_bytes(_synthetic_vk6())

    render_thumbnail(source, output, 3)

    with Image.open(output) as rendered:
        assert rendered.format == "PNG"
        assert rendered.mode == "RGB"
        assert max(rendered.size) <= 3


def test_cli_returns_nonzero_for_corrupt_file(tmp_path: Path) -> None:
    source = tmp_path / "broken.vk4"
    output = tmp_path / "thumb.png"
    source.write_bytes(b"VK4_")

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "vkquicklook_linux.cli",
            "--input",
            str(source),
            "--output",
            str(output),
            "--size",
            "128",
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 1
    assert "file too small" in result.stderr
    assert not output.exists()


def test_vk4_falls_back_to_peak_thumbnail(tmp_path: Path) -> None:
    source = tmp_path / "fallback.vk4"
    output = tmp_path / "thumb.png"
    source.write_bytes(_synthetic_vk4(primary_slot=9, primary_color=(90, 80, 70)))

    render_thumbnail(source, output, 128)

    with Image.open(output) as rendered:
        assert rendered.getpixel((0, 0)) == (90, 80, 70)


def test_same_directory_output_does_not_leave_temporary_files(tmp_path: Path) -> None:
    source = tmp_path / "scan.vk4"
    output = tmp_path / "thumb.png"
    source.write_bytes(_synthetic_vk4())

    render_thumbnail(source, output, 128)

    assert sorted(path.name for path in tmp_path.iterdir()) == ["scan.vk4", "thumb.png"]


def test_gnome_resource_files_register_expected_mime_types() -> None:
    mime_xml = REPO_ROOT / "linux/mime/vsoptomech-keyence-vk.xml"
    thumbnailer = REPO_ROOT / "linux/thumbnailers/vkquicklook.thumbnailer.in"

    root = ET.parse(mime_xml).getroot()
    namespace = {"mime": "http://www.freedesktop.org/standards/shared-mime-info"}
    mime_types = {node.attrib["type"] for node in root.findall("mime:mime-type", namespace)}

    assert mime_types == {
        "application/x-vsoptomech-keyence-vk4",
        "application/x-vsoptomech-keyence-vk6",
    }
    assert "value=\"VK4_\"" in mime_xml.read_text(encoding="utf-8")
    assert "value=\"VK6\"" in mime_xml.read_text(encoding="utf-8")

    text = thumbnailer.read_text(encoding="utf-8")
    assert "Exec=@VK_THUMBNAILER@ --input %i --output %o --size %s" in text
    assert "application/x-vsoptomech-keyence-vk4;application/x-vsoptomech-keyence-vk6;" in text


def _synthetic_vk4(
    *,
    primary_slot: int = 10,
    primary_color: tuple[int, int, int] = (10, 20, 30),
) -> bytes:
    header = bytearray(84)
    header[:4] = b"VK4_"
    section = _rgb_section(4, 2, primary_color)
    struct.pack_into("<I", header, 12 + primary_slot * 4, len(header))
    return bytes(header) + section


def _rgb_section(width: int, height: int, color: tuple[int, int, int]) -> bytes:
    pixels = bytes(color) * width * height
    return struct.pack("<IIIII", width, height, 24, 0, len(pixels)) + pixels


def _synthetic_vk6() -> bytes:
    image = Image.new("RGB", (4, 2), (20, 40, 60))
    buffer = io.BytesIO()
    image.save(buffer, format="BMP")
    bmp = buffer.getvalue()
    return b"VK6" + struct.pack("<I", len(bmp)) + bmp
