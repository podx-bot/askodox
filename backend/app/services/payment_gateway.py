"""Pluggable settlement adapters.

Today ASKODOX settles directly between customer and seller/provider (cash on
delivery, cash on pickup, direct cash, direct UPI with a UTR reference). A
real payment gateway / escrow / wallet is added later by registering an
adapter here -- the order lifecycle (deal_lifecycle.py, routes/orders.py)
only talks to this interface and never changes for it.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

from app.services import deal_lifecycle as lifecycle


@dataclass(frozen=True)
class SettlementInstruction:
    method: str
    payer_action: str       # what the customer does
    payee_action: str       # what the seller/provider confirms
    needs_reference: bool   # a UTR / receipt is expected
    online: bool            # money moves through a gateway (never true today)


class PaymentAdapter(Protocol):
    name: str

    def configured(self) -> bool: ...

    def instruction(self, order: dict[str, Any]) -> SettlementInstruction: ...


class DirectSettlementAdapter:
    """Cash / direct UPI between the parties -- no money through ASKODOX."""

    name = "direct"

    def configured(self) -> bool:
        return True

    def instruction(self, order: dict[str, Any]) -> SettlementInstruction:
        method = lifecycle.settlement_method(order.get("settlement_method"))
        if method == lifecycle.DIRECT_UPI:
            return SettlementInstruction(method, "Pay the seller by UPI, then add the UTR reference",
                                         "Confirm the money arrived", True, False)
        when = {lifecycle.COD: "on delivery", lifecycle.CASH_ON_PICKUP: "at pickup"}.get(method, "directly")
        return SettlementInstruction(method, f"Pay cash {when}", "Confirm cash received", False, False)


class UnconfiguredGatewayAdapter:
    """Placeholder slot for a future gateway: honestly not available."""

    name = "gateway"

    def configured(self) -> bool:
        return False

    def instruction(self, order: dict[str, Any]) -> SettlementInstruction:
        raise lifecycle.LifecycleError("Online payment is not available yet; choose cash or direct UPI")


_ADAPTERS: dict[str, PaymentAdapter] = {
    "direct": DirectSettlementAdapter(),
    "gateway": UnconfiguredGatewayAdapter(),
}


def register_adapter(adapter: PaymentAdapter) -> None:
    """Install a real gateway/escrow/wallet adapter (future)."""
    _ADAPTERS[adapter.name] = adapter


def adapter_for(method: str) -> PaymentAdapter:
    return _ADAPTERS["gateway" if lifecycle.settlement_method(method) == lifecycle.GATEWAY else "direct"]
