"""Deterministic ranking over real seller_products rows."""
from __future__ import annotations
import re
from typing import Any

class ProductMatchRankingService:
    @staticmethod
    def _tokens(value: str) -> set[str]:
        return {x for x in re.findall(r"[\w]+", str(value or "").casefold(), flags=re.UNICODE) if len(x)>1}

    def rank(self, query: str, rows: list[dict[str, Any]], location: str | None=None, budget: float | None=None) -> list[dict[str, Any]]:
        q=self._tokens(query); wanted_location=str(location or "").casefold().strip()
        ranked=[]
        for row in rows:
            hay=" ".join(str(row.get(k) or "") for k in ("subject","brand","variant","category_tag","service_area"))
            tokens=self._tokens(hay)
            overlap=len(q & tokens)
            score=overlap*10.0
            reasons=[]
            if overlap: reasons.append("query_match")
            row_location=" ".join(str(row.get(k) or "") for k in ("location_label","precise_location","service_area")).casefold()
            if wanted_location and wanted_location in row_location:
                score+=5; reasons.append("location_match")
            price=row.get("price")
            if budget is not None and price is not None:
                if float(price)<=float(budget): score+=3; reasons.append("within_budget")
                else: score-=2
            stock=str(row.get("stock_status") or "").upper()
            if stock in {"IN_STOCK","AVAILABLE"}: score+=2; reasons.append("available")
            if str(row.get("id_verification_status") or "").upper()=="VERIFIED": score+=1; reasons.append("verified")
            item=dict(row); item["match_score"]=score; item["match_reasons"]=reasons; ranked.append(item)
        return sorted(ranked,key=lambda x:(-x["match_score"], int(x.get("id") or 0)))
