from app.repositories.category_intelligence_repository import CategoryIntelligenceRepository

def test_seeds_goods_services_and_bfsi(tmp_path):
    repo=CategoryIntelligenceRepository(str(tmp_path/"test.db"))
    assert repo.get("COMMERCE")["question_schema"]
    assert "preferred_time" in repo.get("SERVICES")["question_schema"]
    assert "tenure" in repo.get("BFSI")["question_schema"]

def test_category_definition_is_db_editable(tmp_path):
    repo=CategoryIntelligenceRepository(str(tmp_path/"test.db"))
    repo.upsert("PET_CARE","Pet care",question_schema=["pet","service","location"],keywords=["pet grooming","vet"])
    assert repo.get("PET_CARE")["question_schema"] == ["pet","service","location"]
    assert repo.match("need pet grooming near me")["category_key"] == "PET_CARE"

def test_bfsi_keyword_match(tmp_path):
    repo=CategoryIntelligenceRepository(str(tmp_path/"test.db"))
    result=repo.match("I need a home loan for 20 lakhs")
    assert result["category_key"] == "BFSI"
    assert "amount" in result["question_schema"]
