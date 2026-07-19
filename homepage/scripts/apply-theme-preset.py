#!/usr/bin/env python3
"""Apply a Homepage theme preset to an existing runtime config directory."""

from __future__ import annotations

import argparse
import os
import stat
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path, PurePosixPath

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"PyYAML is required to apply a theme: {exc}")


DEFAULT_GITHUB_RAW_BASE = (
    "https://raw.githubusercontent.com/DF-wu/myServices/master/"
    "homepage/config-template/themes"
)
VALID_COLORS = {
    "amber",
    "blue",
    "cyan",
    "emerald",
    "fuchsia",
    "gray",
    "green",
    "indigo",
    "lime",
    "neutral",
    "orange",
    "pink",
    "purple",
    "red",
    "rose",
    "sky",
    "slate",
    "stone",
    "teal",
    "violet",
    "white",
    "yellow",
    "zinc",
}
VALID_HEADER_STYLES = {"boxed", "boxedWidgets", "clean", "underlined"}
VALID_STATUS_STYLES = {"basic", "dot"}


class PresetError(RuntimeError):
    """Raised when a preset cannot be loaded or applied safely."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("preset")
    parser.add_argument("--config-dir", type=Path, default=Path("/app/config"))
    parser.add_argument("--preset-dir", type=Path)
    parser.add_argument("--github-raw-base", default=DEFAULT_GITHUB_RAW_BASE)
    return parser.parse_args()


def validate_preset_id(preset_id: str) -> None:
    if not preset_id or any(char not in "abcdefghijklmnopqrstuvwxyz0123456789-" for char in preset_id):
        raise PresetError(f"invalid preset id: {preset_id!r}")


def parse_manifest(text: str, label: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not key.strip():
            raise PresetError(f"invalid line in {label}: {raw_line!r}")
        values[key.strip()] = value.strip()
    return values


def require(manifest: dict[str, str], key: str, label: str) -> str:
    value = manifest.get(key, "")
    if not value:
        raise PresetError(f"missing {key} in {label}")
    return value


def require_choice(manifest: dict[str, str], key: str, choices: set[str], label: str) -> str:
    value = require(manifest, key, label)
    if value not in choices:
        raise PresetError(f"invalid {key}={value!r} in {label}")
    return value


def require_bool(manifest: dict[str, str], key: str, label: str) -> bool:
    value = require_choice(manifest, key, {"false", "true"}, label)
    return value == "true"


def require_positive_int(manifest: dict[str, str], key: str, label: str) -> int:
    value = require(manifest, key, label)
    try:
        integer = int(value)
    except ValueError as exc:
        raise PresetError(f"invalid {key}={value!r} in {label}") from exc
    if integer < 1:
        raise PresetError(f"invalid {key}={value!r} in {label}")
    return integer


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "homepage-theme-preset/1"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.read().decode("utf-8")
    except (OSError, UnicodeError, urllib.error.URLError) as exc:
        raise PresetError(f"cannot fetch {url}: {exc}") from exc


class PresetSource:
    def __init__(self, preset_dir: Path | None, github_raw_base: str) -> None:
        self.preset_dir = preset_dir
        self.github_raw_base = github_raw_base.rstrip("/")

    def read(self, relative_path: str) -> str:
        safe_path = PurePosixPath(relative_path)
        if safe_path.is_absolute() or ".." in safe_path.parts:
            raise PresetError(f"unsafe preset path: {relative_path}")
        if self.preset_dir is not None:
            path = self.preset_dir.joinpath(*safe_path.parts)
            try:
                return path.read_text()
            except OSError as exc:
                raise PresetError(f"cannot read {path}: {exc}") from exc
        return fetch(f"{self.github_raw_base}/{safe_path.as_posix()}")


def render_css(source: PresetSource, preset_id: str, manifest: dict[str, str], label: str) -> str:
    css_mode = require_choice(manifest, "css", {"base", "dracula"}, label)
    if css_mode == "dracula":
        return source.read(f"{preset_id}/custom.css")
    return (
        f"/* Homepage theme preset: {preset_id} */\n"
        f"{source.read('_base.css').rstrip()}\n\n"
        f"{source.read(f'{preset_id}/theme.css').rstrip()}\n"
    )


def apply_visual_settings(settings: dict[str, object], manifest: dict[str, str], label: str) -> None:
    settings["theme"] = require_choice(manifest, "theme", {"dark", "light"}, label)
    settings["color"] = require_choice(manifest, "color", VALID_COLORS, label)
    settings["headerStyle"] = require_choice(manifest, "headerStyle", VALID_HEADER_STYLES, label)
    settings["statusStyle"] = require_choice(manifest, "statusStyle", VALID_STATUS_STYLES, label)
    settings["iconStyle"] = require_choice(manifest, "iconStyle", {"theme"}, label)
    settings["fullWidth"] = require_bool(manifest, "fullWidth", label)
    settings["maxGroupColumns"] = require_positive_int(manifest, "maxGroupColumns", label)
    settings["maxBookmarkGroupColumns"] = require_positive_int(
        manifest, "maxBookmarkGroupColumns", label
    )

    card_blur = require_choice(manifest, "cardBlur", {"false", "omit", "true"}, label)
    if card_blur == "omit":
        settings.pop("cardBlur", None)
    else:
        settings["cardBlur"] = card_blur == "true"

    background = require_choice(manifest, "background", {"image", "none"}, label)
    if background == "none":
        settings.pop("background", None)
    else:
        settings["background"] = {
            "image": require(manifest, "backgroundImage", label),
            "blur": manifest.get("backgroundBlur", "sm"),
            "saturate": int(manifest.get("backgroundSaturate", "50")),
            "brightness": int(manifest.get("backgroundBrightness", "50")),
            "opacity": int(manifest.get("backgroundOpacity", "50")),
        }


def atomic_write(path: Path, content: str) -> None:
    try:
        metadata = path.stat()
    except FileNotFoundError:
        metadata = None

    if metadata is None:
        try:
            owner = path.parent.stat()
        except OSError:
            owner = None
        mode = 0o644
    else:
        owner = metadata
        mode = stat.S_IMODE(metadata.st_mode)

    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fchmod(handle.fileno(), mode)
            try:
                if owner is not None:
                    os.fchown(handle.fileno(), owner.st_uid, owner.st_gid)
            except PermissionError:
                # Rootless containers cannot always map the existing host IDs.
                pass
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def main() -> int:
    args = parse_args()
    try:
        validate_preset_id(args.preset)
        source = PresetSource(args.preset_dir, args.github_raw_base)
        manifest_label = f"{args.preset}/preset.conf"
        manifest = parse_manifest(source.read(manifest_label), manifest_label)
        require(manifest, "name", manifest_label)
        require(manifest, "description", manifest_label)
        settings_path = args.config_dir / "settings.yaml"
        css_path = args.config_dir / "custom.css"
        if not settings_path.is_file():
            raise PresetError(f"missing runtime settings: {settings_path}")
        settings = yaml.safe_load(settings_path.read_text())
        if not isinstance(settings, dict):
            raise PresetError(f"{settings_path} must contain a YAML mapping")

        apply_visual_settings(settings, manifest, manifest_label)
        settings_output = yaml.safe_dump(
            settings,
            allow_unicode=True,
            explicit_start=True,
            sort_keys=False,
            width=120,
        )
        css_output = render_css(source, args.preset, manifest, manifest_label)
        if not css_output.strip():
            raise PresetError("rendered custom.css is empty")

        settings_backup = settings_path.read_bytes()
        css_backup = css_path.read_bytes() if css_path.is_file() else None
        try:
            atomic_write(settings_path, settings_output)
            atomic_write(css_path, css_output)
        except Exception:
            settings_path.write_bytes(settings_backup)
            if css_backup is None:
                css_path.unlink(missing_ok=True)
            else:
                css_path.write_bytes(css_backup)
            raise
    except (OSError, PresetError, ValueError, yaml.YAMLError) as exc:
        print(f"apply-theme-preset: {exc}", file=sys.stderr)
        return 1

    print(f"Applied Homepage theme preset: {args.preset}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
