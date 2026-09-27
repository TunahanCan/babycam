"""Generate a deployment key without printing private material or overwriting keys."""

import argparse
import os
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from .licenses import LicenseSigner


def generate(path: Path) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    key = Ed25519PrivateKey.generate()
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption())
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as output:
        output.write(pem)
        output.flush()
        os.fsync(output.fileno())
    return LicenseSigner(key).public_key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    # Only the public key is suitable for the Flutter build configuration.
    print(generate(args.path))


if __name__ == "__main__":
    main()
