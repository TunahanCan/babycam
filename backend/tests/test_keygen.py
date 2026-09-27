import os

import pytest

from miucam_billing.keygen import generate
from miucam_billing.licenses import LicenseSigner


def test_deployment_key_is_private_and_cannot_be_overwritten(tmp_path):
    path = tmp_path / "secrets" / "license.pem"
    public_key = generate(path)
    original = path.read_bytes()
    assert LicenseSigner.from_file(str(path)).public_key == public_key
    assert "PRIVATE" not in public_key
    if os.name != "nt":
        assert path.stat().st_mode & 0o777 == 0o600
    with pytest.raises(FileExistsError):
        generate(path)
    assert path.read_bytes() == original
