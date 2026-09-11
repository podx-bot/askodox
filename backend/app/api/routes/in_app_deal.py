from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.repositories.purchase_history_repository import PurchaseHistoryRepository
from app.services.deal_completion_memory_service import DealCompletionMemoryService
from app.services.party_conversation_answer_service import PartyConversationAnswerService

router = APIRouter(prefix="/debug", tags=["Debug"])


class InterestDecisionRequest(BaseModel):
    user_id: str
    request_id: int
    responder_user_id: str
    action: str


class DealMessageRequest(BaseModel):
    user_id: str
    request_id: int
    other_user_id: str
    message: str = Field(min_length=1, max_length=2000)


class DealStatusRequest(BaseModel):
    user_id: str
    request_id: int
    other_user_id: str
    status: str


def _app_user(value: str, field: str = "user_id") -> str:
    user_id = str(value or "").strip()
    if not user_id.lower().startswith("app-"):
        raise HTTPException(status_code=400, detail=f"ASKODOX app {field} required")
    return user_id


def _ensure_messages_table(db) -> None:
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS in_app_deal_messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            request_id INTEGER NOT NULL,
            buyer_user_id TEXT NOT NULL,
            seller_user_id TEXT NOT NULL,
            sender_user_id TEXT NOT NULL,
            message_text TEXT NOT NULL,
            message_type TEXT NOT NULL DEFAULT 'USER',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    db.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_in_app_deal_messages_thread
        ON in_app_deal_messages(request_id,buyer_user_id,seller_user_id,id)
        """
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS in_app_deal_notifications(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            request_id INTEGER NOT NULL,
            buyer_user_id TEXT NOT NULL,
            seller_user_id TEXT NOT NULL,
            recipient_user_id TEXT NOT NULL,
            source_message_id INTEGER,
            notification_type TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            read_at TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    db.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_in_app_deal_notifications_recipient
        ON in_app_deal_notifications(recipient_user_id,read_at,id)
        """
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS in_app_deal_threads(
            request_id INTEGER NOT NULL,
            buyer_user_id TEXT NOT NULL,
            seller_user_id TEXT NOT NULL,
            deal_status TEXT NOT NULL DEFAULT 'NEGOTIATING',
            status_updated_by TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(request_id,buyer_user_id,seller_user_id)
        )
        """
    )


def _ensure_thread(db, request_id: int, party_a: str, party_b: str) -> None:
    _ensure_messages_table(db)
    db.execute(
        """
        INSERT OR IGNORE INTO in_app_deal_threads(
            request_id,buyer_user_id,seller_user_id,deal_status
        ) VALUES(?,?,?,'NEGOTIATING')
        """,
        (request_id, party_a, party_b),
    )


def _notify(db, request_id: int, party_a: str, party_b: str, recipient: str,
            notification_type: str, title: str, body: str, source_message_id: int | None = None) -> None:
    db.execute(
        """
        INSERT INTO in_app_deal_notifications(
            request_id,buyer_user_id,seller_user_id,recipient_user_id,
            source_message_id,notification_type,title,body
        ) VALUES(?,?,?,?,?,?,?,?)
        """,
        (request_id, party_a, party_b, recipient, source_message_id, notification_type, title, body),
    )


def _accepted_interest(container, request_id: int, user_a: str, user_b: str):
    demand = container.universal_demand_repository.get(request_id)
    if not demand:
        raise HTTPException(status_code=404, detail="request not found")
    party_a = str(demand.get("user_id") or "")
    if party_a not in {user_a, user_b}:
        raise HTTPException(status_code=403, detail="user is not a participant in this deal")
    party_b = user_b if user_a == party_a else user_a
    interest = container.universal_notification_repository.get_interest(request_id, party_b)
    if not interest or str(interest.get("requester_user_id") or "") != party_a:
        raise HTTPException(status_code=404, detail="deal interest not found")
    if str(interest.get("requester_status") or "").upper() != "ACCEPTED":
        raise HTTPException(status_code=409, detail="deal is not accepted yet")
    return demand, interest, party_a, party_b


def _looks_like_question(text: str) -> bool:
    normalized = " ".join(str(text or "").strip().lower().split())
    if not normalized:
        return False
    if "?" in normalized:
        return True
    hints = (
        "what", "how", "when", "where", "which", "is it", "can you", "do you",
        "price", "rate", "available", "stock", "size", "quantity", "delivery",
        "pickup", "warranty", "location", "timing", "custom",
        "ఎలా", "ఏం", "ఎప్పుడు", "ఎక్కడ", "ఎంత", "ఉందా", "దొరుక", "ధర", "రేట్",
        "డెలివరీ", "పికప్", "వారంటీ", "సైజ్", "ఎన్ని",
        "कैसे", "क्या", "कब", "कहाँ", "कितना", "कीमत", "डिलीवरी",
    )
    return any(hint in normalized for hint in hints)


def _record_completed_purchase_memory(container, demand: dict, party_a: str, party_b: str, request_id: int) -> dict:
    """Persist structured purchase memory while retaining legacy buyer/seller storage compatibility."""
    service = getattr(container, "deal_completion_memory_service", None)
    if service is None:
        purchases = PurchaseHistoryRepository(container.settings.database_path)
        service = DealCompletionMemoryService(purchases)

    side = str(demand.get("side") or "").strip().upper()
    return service.record(
        {
            "deal_id": request_id,
            "status": "COMPLETED",
            "domain": demand.get("domain"),
            "intent": "BUY" if side == "NEED" else "OFFER",
            "buyer_id": party_a,
            "seller_id": party_b,
            "subject": demand.get("subject"),
            "quantity": demand.get("quantity"),
            "unit": demand.get("unit"),
            "unit_price": demand.get("price"),
        }
    )


@router.post("/interest-action")
def interest_action(payload: InterestDecisionRequest, request: Request) -> dict:
    """Party A accepts or declines Party B's in-app interest."""
    container = request.app.state.container
    requester = _app_user(payload.user_id)
    responder = _app_user(payload.responder_user_id, "responder_user_id")
    action = payload.action.strip().upper()
    if action not in {"ACCEPT", "DECLINE"}:
        raise HTTPException(status_code=400, detail="action must be ACCEPT or DECLINE")

    demand = container.universal_demand_repository.get(payload.request_id)
    if not demand or str(demand.get("status") or "").upper() != "ACTIVE":
        raise HTTPException(status_code=404, detail="active request not found")
    if str(demand.get("user_id") or "") != requester:
        raise HTTPException(status_code=403, detail="only the request owner can decide this interest")

    interest = container.universal_notification_repository.get_interest(payload.request_id, responder)
    if not interest or str(interest.get("requester_user_id") or "") != requester:
        raise HTTPException(status_code=404, detail="interest not found")
    if str(interest.get("requester_status") or "").upper() != "PENDING":
        raise HTTPException(status_code=409, detail="interest already decided")

    accepted = action == "ACCEPT"
    result = container.universal_notification_service.confirm_lead(
        demand, requester, responder, accepted,
    )

    if accepted and str(result.get("status") or "") == "IN_APP_READY_FOR_BUYER":
        db = container.database
        _ensure_thread(db, payload.request_id, requester, responder)
        cursor = db.execute(
            """
            INSERT INTO in_app_deal_messages(
                request_id,buyer_user_id,seller_user_id,sender_user_id,message_text,message_type
            ) VALUES(?,?,?,?,?,'SYSTEM')
            """,
            (payload.request_id, requester, responder, "system",
             "Deal accepted. Party A and Party B can continue inside ASKODOX."),
        )
        _notify(
            db, payload.request_id, requester, responder, responder,
            "DEAL_ACCEPTED", "Deal accepted",
            "Party A accepted your interest. Open ASKODOX to continue the deal.",
            int(cursor.lastrowid),
        )
        return {
            **result,
            "action": action,
            "conversation_ready": True,
            "thread": {
                "request_id": payload.request_id,
                "party_a_user_id": requester,
                "party_b_user_id": responder,
                "deal_status": "NEGOTIATING",
            },
        }

    return {**result, "action": action, "conversation_ready": False}


@router.post("/deal-message")
def deal_message(payload: DealMessageRequest, request: Request) -> dict:
    """Send free-text deal chat and let ASKODOX assist from trusted Party A/B deal data."""
    container = request.app.state.container
    sender = _app_user(payload.user_id)
    other = _app_user(payload.other_user_id, "other_user_id")
    demand, interest, party_a, party_b = _accepted_interest(container, payload.request_id, sender, other)
    body = " ".join(payload.message.strip().split())
    if not body:
        raise HTTPException(status_code=400, detail="message is required")

    db = container.database
    _ensure_thread(db, payload.request_id, party_a, party_b)
    cursor = db.execute(
        """
        INSERT INTO in_app_deal_messages(
            request_id,buyer_user_id,seller_user_id,sender_user_id,message_text,message_type
        ) VALUES(?,?,?,?,?,'USER')
        """,
        (payload.request_id, party_a, party_b, sender, body),
    )
    message_id = int(cursor.lastrowid)
    _notify(
        db, payload.request_id, party_a, party_b, other,
        "MESSAGE", "New deal message", body, message_id,
    )

    askodox_assistance = None
    if sender == party_a and _looks_like_question(body):
        service = getattr(container, "party_conversation_answer_service", None)
        if service is None:
            service = PartyConversationAnswerService()
        answer = service.answer(
            body,
            trusted_party_b_data=interest,
            trusted_deal_data=demand,
        )
        askodox_assistance = answer.as_dict()

        if answer.status == "ANSWERED_FROM_TRUSTED_DATA" and answer.answer:
            db.execute(
                """
                INSERT INTO in_app_deal_messages(
                    request_id,buyer_user_id,seller_user_id,sender_user_id,message_text,message_type
                ) VALUES(?,?,?,?,?,'ASSISTANT')
                """,
                (payload.request_id, party_a, party_b, "askodox", answer.answer),
            )
        elif answer.requires_party_b_confirmation:
            confirmation_text = (
                "ASKODOX needs Party B confirmation for this detail. "
                "The question has been routed to Party B."
            )
            assistant_cursor = db.execute(
                """
                INSERT INTO in_app_deal_messages(
                    request_id,buyer_user_id,seller_user_id,sender_user_id,message_text,message_type
                ) VALUES(?,?,?,?,?,'ASSISTANT')
                """,
                (payload.request_id, party_a, party_b, "askodox", confirmation_text),
            )
            _notify(
                db, payload.request_id, party_a, party_b, party_b,
                "PARTY_B_CONFIRMATION_REQUIRED",
                "ASKODOX needs your confirmation",
                body,
                int(assistant_cursor.lastrowid),
            )

    db.execute(
        """
        UPDATE in_app_deal_threads SET updated_at=CURRENT_TIMESTAMP
        WHERE request_id=? AND buyer_user_id=? AND seller_user_id=?
        """,
        (payload.request_id, party_a, party_b),
    )
    return {
        "status": "SENT",
        "channel": "in_app",
        "message_id": message_id,
        "request_id": payload.request_id,
        "sender_user_id": sender,
        "recipient_user_id": other,
        "message": body,
        "askodox_assistance": askodox_assistance,
    }


@router.get("/deal-thread/{request_id}/{user_id}/{other_user_id}")
def deal_thread(request_id: int, user_id: str, other_user_id: str, request: Request) -> dict:
    """Read the accepted ASKODOX deal conversation and mark its notifications read."""
    container = request.app.state.container
    viewer = _app_user(user_id)
    other = _app_user(other_user_id, "other_user_id")
    demand, interest, party_a, party_b = _accepted_interest(container, request_id, viewer, other)
    db = container.database
    _ensure_thread(db, request_id, party_a, party_b)
    rows = db.fetchall(
        """
        SELECT id,sender_user_id,message_text,message_type,created_at
        FROM in_app_deal_messages
        WHERE request_id=? AND buyer_user_id=? AND seller_user_id=?
        ORDER BY id ASC LIMIT 200
        """,
        (request_id, party_a, party_b),
    )
    db.execute(
        """
        UPDATE in_app_deal_notifications SET read_at=CURRENT_TIMESTAMP
        WHERE request_id=? AND recipient_user_id=? AND read_at IS NULL
        """,
        (request_id, viewer),
    )
    thread = db.fetchone(
        """
        SELECT deal_status,status_updated_by,updated_at
        FROM in_app_deal_threads
        WHERE request_id=? AND buyer_user_id=? AND seller_user_id=?
        """,
        (request_id, party_a, party_b),
    )
    return {
        "status": "OPEN",
        "channel": "in_app",
        "request_id": request_id,
        "viewer_user_id": viewer,
        "other_user_id": other,
        "party_a_user_id": party_a,
        "party_b_user_id": party_b,
        "deal": {
            "subject": demand.get("subject"),
            "quantity": demand.get("quantity"),
            "unit": demand.get("unit"),
            "price": demand.get("price"),
            "currency": demand.get("currency"),
            "qualification_status": interest.get("qualification_status"),
            "deal_status": thread["deal_status"] if thread else "NEGOTIATING",
        },
        "messages": [dict(row) for row in rows],
    }


@router.get("/deal-inbox/{user_id}")
def deal_inbox(user_id: str, request: Request) -> dict:
    """List ASKODOX accepted Party A/B deal threads with unread counts and latest activity."""
    user = _app_user(user_id)
    db = request.app.state.container.database
    _ensure_messages_table(db)
    rows = db.fetchall(
        """
        SELECT t.request_id,t.buyer_user_id,t.seller_user_id,t.deal_status,t.updated_at,
               (SELECT COUNT(*) FROM in_app_deal_notifications n
                WHERE n.request_id=t.request_id AND n.recipient_user_id=? AND n.read_at IS NULL) AS unread_count,
               (SELECT message_text FROM in_app_deal_messages m
                WHERE m.request_id=t.request_id AND m.buyer_user_id=t.buyer_user_id
                  AND m.seller_user_id=t.seller_user_id ORDER BY m.id DESC LIMIT 1) AS latest_message
        FROM in_app_deal_threads t
        WHERE t.buyer_user_id=? OR t.seller_user_id=?
        ORDER BY t.updated_at DESC
        LIMIT 100
        """,
        (user, user, user),
    )
    threads = []
    total_unread = 0
    for row in rows:
        item = dict(row)
        item["party_a_user_id"] = item.pop("buyer_user_id")
        item["party_b_user_id"] = item.pop("seller_user_id")
        item["other_user_id"] = item["party_b_user_id"] if item["party_a_user_id"] == user else item["party_a_user_id"]
        item["unread_count"] = int(item.get("unread_count") or 0)
        total_unread += item["unread_count"]
        threads.append(item)
    return {
        "user_id": user,
        "channel": "in_app",
        "thread_count": len(threads),
        "total_unread": total_unread,
        "threads": threads,
    }


@router.post("/deal-status")
def deal_status(payload: DealStatusRequest, request: Request) -> dict:
    """Progress an accepted ASKODOX deal and notify the other participant."""
    container = request.app.state.container
    actor = _app_user(payload.user_id)
    other = _app_user(payload.other_user_id, "other_user_id")
    demand, _interest, party_a, party_b = _accepted_interest(container, payload.request_id, actor, other)
    status = payload.status.strip().upper().replace(" ", "_")
    allowed = {
        "NEGOTIATING", "CONFIRMED", "READY_FOR_PICKUP", "OUT_FOR_DELIVERY",
        "COMPLETED", "CANCELLED",
    }
    if status not in allowed:
        raise HTTPException(status_code=400, detail="unsupported deal status")

    db = container.database
    _ensure_thread(db, payload.request_id, party_a, party_b)
    db.execute(
        """
        UPDATE in_app_deal_threads
        SET deal_status=?,status_updated_by=?,updated_at=CURRENT_TIMESTAMP
        WHERE request_id=? AND buyer_user_id=? AND seller_user_id=?
        """,
        (status, actor, payload.request_id, party_a, party_b),
    )
    cursor = db.execute(
        """
        INSERT INTO in_app_deal_messages(
            request_id,buyer_user_id,seller_user_id,sender_user_id,message_text,message_type
        ) VALUES(?,?,?,?,?,'STATUS')
        """,
        (payload.request_id, party_a, party_b, actor, f"Deal status changed to {status}."),
    )
    _notify(
        db, payload.request_id, party_a, party_b, other,
        "DEAL_STATUS", "Deal status updated", f"Deal is now {status}.", int(cursor.lastrowid),
    )
    memory = None
    if status == "COMPLETED":
        container.universal_demand_repository.update_status(payload.request_id, "COMPLETED")
        memory = _record_completed_purchase_memory(container, demand, party_a, party_b, payload.request_id)
    elif status == "CANCELLED":
        container.universal_demand_repository.update_status(payload.request_id, "CANCELLED")

    return {
        "status": status,
        "request_id": payload.request_id,
        "updated_by": actor,
        "recipient_user_id": other,
        "channel": "in_app",
        "purchase_memory": memory,
    }
