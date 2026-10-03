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


def test_pr128_campaign_table_moves_out_of_the_sponsored_modules_way(tmp_path):
    """A database first written by PR #128 (its campaigns in `sponsored_campaigns`)
    keeps its rows under `social_sponsored_campaigns`, and the Sponsored module
    then owns `sponsored_campaigns` with its own schema -- in either start order."""
    import sqlite3

    from app.repositories.sponsored_repository import SponsoredRepository
    from app.services.social_ads_offers_hub import SocialAdsOffersHub

    for first_sponsored in (False, True):
        db = str(tmp_path / f"legacy{first_sponsored}.db")
        with sqlite3.connect(db) as c:
            c.execute("CREATE TABLE sponsored_campaigns(id INTEGER PRIMARY KEY AUTOINCREMENT, owner_ref TEXT NOT NULL,"
                      " campaign_type TEXT NOT NULL, title TEXT NOT NULL, destination_url TEXT, category TEXT,"
                      " location_scope TEXT, budget REAL, starts_at TEXT, ends_at TEXT, active INTEGER NOT NULL DEFAULT 0,"
                      " metadata_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)")
            c.execute("INSERT INTO sponsored_campaigns(owner_ref,campaign_type,title,created_at,updated_at)"
                      " VALUES('seller:1','boost','Kept row','t','t')")
        if first_sponsored:
            SponsoredRepository(db)
        hub = SocialAdsOffersHub(db)
        SponsoredRepository(db)
        with sqlite3.connect(db) as c:
            assert c.execute("SELECT title FROM social_sponsored_campaigns").fetchall() == [("Kept row",)]
            cols = {r[1] for r in c.execute("PRAGMA table_info(sponsored_campaigns)")}
        assert "name" in cols and "owner_ref" not in cols
        created = hub.create_campaign("seller:2", "boost", "New one", category="tv")
        assert created["title"] == "New one"
