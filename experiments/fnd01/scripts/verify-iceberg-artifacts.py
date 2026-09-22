#!/usr/bin/env python3
"""Download and verify the two Iceberg JARs before Spark uses them."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys
import tempfile
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen


MAVEN_BASE_URL = "https://repo1.maven.org/maven2/org/apache/iceberg"
ARTIFACTS = (
    (
        "iceberg-spark-runtime-3.5_2.12",
        "ICEBERG_SPARK_RUNTIME_SHA256",
    ),
    ("iceberg-aws-bundle", "ICEBERG_AWS_BUNDLE_SHA256"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, required=True)
    parser.add_argument("--paths-file", type=Path)
    parser.add_argument(
        "--expected-sha256",
        action="append",
        default=[],
        metavar="ARTIFACT=SHA256",
        help="Override one expected checksum for a controlled negative test.",
    )
    return parser.parse_args()


def parse_overrides(values: list[str]) -> dict[str, str]:
    overrides = {}
    known_names = {name for name, _ in ARTIFACTS}
    for value in values:
        name, separator, checksum = value.partition("=")
        if not separator or name not in known_names or len(checksum) != 64:
            raise ValueError("invalid checksum override")
        int(checksum, 16)
        overrides[name] = checksum.lower()
    return overrides


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: Path) -> None:
    request = Request(url, headers={"User-Agent": "projeto-data-platform-fnd02"})
    with urlopen(request, timeout=120) as response, destination.open("wb") as stream:
        shutil.copyfileobj(response, stream)


def verify_artifact(
    artifact: str,
    checksum_env: str,
    version: str,
    cache_dir: Path,
    overrides: dict[str, str],
) -> tuple[Path, str, str]:
    expected = overrides.get(artifact) or os.environ.get(checksum_env, "").lower()
    if len(expected) != 64:
        raise ValueError(f"missing checksum for {artifact}")
    int(expected, 16)

    filename = f"{artifact}-{version}.jar"
    destination = cache_dir / filename
    source = "cache"
    if destination.exists():
        actual = sha256(destination)
        if actual != expected:
            raise ValueError(f"checksum mismatch for cached {artifact}")
    else:
        cache_dir.mkdir(parents=True, exist_ok=True)
        url = f"{MAVEN_BASE_URL}/{artifact}/{version}/{filename}"
        with tempfile.NamedTemporaryFile(
            dir=cache_dir, prefix=f".{filename}.", suffix=".part", delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
        try:
            download(url, temporary_path)
            actual = sha256(temporary_path)
            if actual != expected:
                raise ValueError(f"checksum mismatch for downloaded {artifact}")
            temporary_path.replace(destination)
            source = "download"
        finally:
            temporary_path.unlink(missing_ok=True)

    actual = sha256(destination)
    if actual != expected:
        raise ValueError(f"checksum mismatch for {artifact}")
    print(f"FND02_MAVEN_CHECKSUM=PASS artifact={artifact} source={source} sha256={actual}")
    return destination, source, actual


def main() -> int:
    args = parse_args()
    try:
        overrides = parse_overrides(args.expected_sha256)
        version = os.environ["ICEBERG_VERSION"]
        paths = [
            verify_artifact(artifact, checksum_env, version, args.cache_dir, overrides)[0]
            for artifact, checksum_env in ARTIFACTS
        ]
        if args.paths_file:
            args.paths_file.write_text("\n".join(str(path) for path in paths) + "\n")
        return 0
    except (OSError, URLError, KeyError, ValueError) as error:
        print(f"FND02_MAVEN_CHECKSUM=FAIL reason={error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
