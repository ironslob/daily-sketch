"""JWT verification unit tests (no database)."""

from __future__ import annotations

import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt_helpers import AUDIENCE, ISSUER, StaticTokenVerifier, generate_rsa_keypair, mint_token

from app.core.errors import AppError


@pytest.fixture
def rsa_keys() -> tuple[rsa.RSAPrivateKey, rsa.RSAPublicKey]:
    return generate_rsa_keypair()


def test_valid_jwt_accepted(rsa_keys: tuple[rsa.RSAPrivateKey, rsa.RSAPublicKey]) -> None:
    private_key, _ = rsa_keys
    verifier = StaticTokenVerifier(private_key)
    token = mint_token(private_key, subject="user-1", name="Ada")
    verified = verifier.verify(token)
    assert verified.subject == "user-1"
    assert verified.display_name == "Ada"


def test_expired_token_rejected(rsa_keys: tuple[rsa.RSAPrivateKey, rsa.RSAPublicKey]) -> None:
    private_key, _ = rsa_keys
    verifier = StaticTokenVerifier(private_key)
    token = mint_token(private_key, expires_in=-10)
    with pytest.raises(AppError) as exc_info:
        verifier.verify(token)
    assert exc_info.value.status_code == 401
    assert exc_info.value.code == "unauthenticated"
    assert exc_info.value.details.get("reason") == "token_expired"


def test_invalid_signature_rejected(rsa_keys: tuple[rsa.RSAPrivateKey, rsa.RSAPublicKey]) -> None:
    private_key, _ = rsa_keys
    other_key, _ = generate_rsa_keypair()
    verifier = StaticTokenVerifier(private_key)
    token = mint_token(other_key)
    with pytest.raises(AppError) as exc_info:
        verifier.verify(token)
    assert exc_info.value.status_code == 401
    assert exc_info.value.code == "unauthenticated"


def test_wrong_audience_rejected(rsa_keys: tuple[rsa.RSAPrivateKey, rsa.RSAPublicKey]) -> None:
    private_key, _ = rsa_keys
    verifier = StaticTokenVerifier(private_key, audience=AUDIENCE)
    token = mint_token(private_key, audience="other-audience")
    with pytest.raises(AppError) as exc_info:
        verifier.verify(token)
    assert exc_info.value.status_code == 401


def test_wrong_issuer_rejected(rsa_keys: tuple[rsa.RSAPrivateKey, rsa.RSAPublicKey]) -> None:
    private_key, _ = rsa_keys
    verifier = StaticTokenVerifier(private_key, issuer=ISSUER)
    token = mint_token(private_key, issuer="https://evil.example/issuer")
    with pytest.raises(AppError) as exc_info:
        verifier.verify(token)
    assert exc_info.value.status_code == 401
