import sqlite3

from app.database.database import Database


class DuplicateInboundMessageError(RuntimeError):
    """Raised when Meta retries an inbound WhatsApp message already claimed."""


class InboundMessageRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    def exists(self, provider_message_id: str) -> bool:
        row = self.database.fetchone(
            """
            SELECT 1
            FROM inbound_messages
            WHERE provider_message_id = ?
            """,
            (provider_message_id,)
        )
        return row is not None

    def claim(self, provider_message_id: str, sender_mobile: str, message_text: str) -> bool:
        cursor = self.database.execute(
            """
            INSERT OR IGNORE INTO inbound_messages (
                provider_message_id,
                sender_mobile,
                message_text
            ) VALUES (?, ?, ?)
            """,
            (provider_message_id, sender_mobile, message_text)
        )
        return int(cursor.rowcount or 0) == 1

    def save(self, provider_message_id: str, sender_mobile: str, message_text: str) -> None:
        try:
            self.database.execute(
                """
                INSERT INTO inbound_messages (
                    provider_message_id,
                    sender_mobile,
                    message_text
                ) VALUES (?, ?, ?)
                """,
                (provider_message_id, sender_mobile, message_text)
            )
        except sqlite3.IntegrityError as error:
            raise DuplicateInboundMessageError(provider_message_id) from error
