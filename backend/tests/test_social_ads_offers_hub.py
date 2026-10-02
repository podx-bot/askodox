from app.services.social_ads_offers_hub import SocialAdsOffersHub

def test_video_source_disabled_until_explicitly_enabled(tmp_path):
    hub=SocialAdsOffersHub(str(tmp_path/"social.db"))
    row=hub.upsert_video_source("youtube","youtube_data_api")
    assert row["active"] == 0
    assert row["api_enabled"] == 0

def test_campaign_distinguishes_sponsored_and_boost(tmp_path):
    hub=SocialAdsOffersHub(str(tmp_path/"social.db"))
    a=hub.create_campaign("merchant-1","sponsored","Festival offer")
    b=hub.create_campaign("merchant-1","boost","Boost listing")
    assert a["campaign_type"] == "sponsored"
    assert b["campaign_type"] == "boost"
    assert a["active"] == 0

def test_partner_offer_not_live_until_verified_and_activated(tmp_path):
    hub=SocialAdsOffersHub(str(tmp_path/"social.db"))
    row=hub.create_offer("bank-x","card","Card cashback")
    assert row["verified"] == 0
    assert row["active"] == 0

def test_scratch_is_idempotent_per_trigger_and_reveals_once(tmp_path):
    hub=SocialAdsOffersHub(str(tmp_path/"social.db"))
    one=hub.issue_scratch("u1","order","o1","credit",10)
    two=hub.issue_scratch("u1","order","o1","credit",99)
    assert one["id"] == two["id"]
    shown=hub.reveal_scratch("u1",one["reveal_token"])
    assert shown["status"] == "REVEALED"
    again=hub.reveal_scratch("u1",one["reveal_token"])
    assert again["status"] == "REVEALED"

def test_video_qa_is_attached_to_video(tmp_path):
    hub=SocialAdsOffersHub(str(tmp_path/"social.db"))
    video=hub.upsert_video("youtube","abc123","https://www.youtube.com/watch?v=abc123",title="Demo")
    q=hub.add_discussion(video["id"],"u1","Is this suitable?","question")
    a=hub.add_discussion(video["id"],"staff1","Yes, check the specifications.","answer",q["id"])
    rows=hub.discussions(video["id"])
    assert [x["kind"] for x in rows] == ["question","answer"]
    assert a["parent_id"] == q["id"]
