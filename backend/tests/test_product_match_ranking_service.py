from app.services.product_match_ranking_service import ProductMatchRankingService

def test_rank_prefers_query_location_budget_and_availability():
    rows=[
        {"id":1,"subject":"Mango pickle","price":250,"location_label":"Vijayawada","stock_status":"IN_STOCK","id_verification_status":"VERIFIED"},
        {"id":2,"subject":"Mango pickle","price":400,"location_label":"Hyderabad","stock_status":"UNKNOWN"},
        {"id":3,"subject":"Rice","price":60,"location_label":"Vijayawada","stock_status":"IN_STOCK"},
    ]
    ranked=ProductMatchRankingService().rank("mango pickle",rows,location="Vijayawada",budget=300)
    assert [x["id"] for x in ranked]==[1,2,3]
    assert {"query_match","location_match","within_budget","available","verified"} <= set(ranked[0]["match_reasons"])

def test_rank_is_deterministic_on_ties():
    rows=[{"id":2,"subject":"Rice"},{"id":1,"subject":"Rice"}]
    assert [x["id"] for x in ProductMatchRankingService().rank("rice",rows)]==[1,2]
