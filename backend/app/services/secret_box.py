"""At-rest encryption for credentials ASKODOX stores (partner API keys,
feed tokens, postback tokens).

Keys come from the environment, never from the database:
  ASKODOX_SECRETS_KEY            current Fernet key (urlsafe base64, 32 bytes)
  ASKODOX_SECRETS_KEY_PREVIOUS   optional, comma-separated older keys that can
                                 still DECRYPT during a rotation

Values are stored as "enc:v1:<fernet token>". Without a configured key the
box refuses to store anything (fail closed) -- secrets are never written in
plain text. Rows written in plain text by an earlier version are still
readable and are re-encrypted by rotate().
"""
from __future__ import annotations

from typing import Iterable, Sequence

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

PREFIX = "enc:v1:"


class SecretsNotConfigured(RuntimeError):
    pass


class SecretBox:
    def __init__(self, primary: str = "", previous: Sequence[str] | str = ()) -> None:
        if isinstance(previous, str):
            previous = [p for p in previous.split(",") if p.strip()]
        keys = [k.strip() for k in [primary, *previous] if str(k or "").strip()]
        self._fernets = []
        for key in keys:
            try:
                self._fernets.append(Fernet(key.encode()))
            except (ValueError, TypeError) as error:
                raise ValueError("ASKODOX_SECRETS_KEY(_PREVIOUS) must be Fernet keys "
                                 "(python -c 'from cryptography.fernet import Fernet; "
                                 "print(Fernet.generate_key().decode())')") from error
        self._box = MultiFernet(self._fernets) if self._fernets else None
        self.primary_configured = bool(str(primary or "").strip())

    @property
    def configured(self) -> bool:
        return self._box is not None and self.primary_configured

    def encrypt(self, value: str) -> str:
        if not self.configured:
            raise SecretsNotConfigured("Set ASKODOX_SECRETS_KEY in Railway before storing partner credentials.")
        return PREFIX + self._box.encrypt(value.encode()).decode()

    def decrypt(self, stored: str) -> str:
        """Plain value; '' when it cannot be decrypted with the known keys."""
        text = str(stored or "")
        if not text.startswith(PREFIX):
            return text  # legacy plain row (re-encrypted by rotate())
        if self._box is None:
            return ""
        try:
            return self._box.decrypt(text[len(PREFIX):].encode()).decode()
        except InvalidToken:
            return ""

    def needs_rewrite(self, stored: str) -> bool:
        """True for plain rows and rows not encrypted with the current key."""
        text = str(stored or "")
        if not text.startswith(PREFIX):
            return True
        if not self._fernets:
            return False
        try:
            self._fernets[0].decrypt(text[len(PREFIX):].encode())
            return False
        except InvalidToken:
            return True

    @staticmethod
    def generate_key() -> str:
        return Fernet.generate_key().decode()


def box_from_settings(settings) -> SecretBox:
    return SecretBox(str(getattr(settings, "secrets_key", "") or ""),
                     str(getattr(settings, "secrets_key_previous", "") or ""))


def all_encrypted(values: Iterable[str]) -> bool:
    return all(str(v).startswith(PREFIX) for v in values)
