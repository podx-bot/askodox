"""Social/video, sponsored placement, partner offers and scratch rewards.

One persistence layer for the next ASKODOX growth block. External credentials
are never stored here: provider tokens/keys stay in environment/Railway.
Organic relevance is independent from sponsorship.
"""
from __future__ import annotations
import json, secrets, sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

def _now() -> str:
    return datetime.now(timezone.utc).isoformat()

@dataclass
class SocialAdsOffersHub:
    db_path: str
    def __post_init__(self) -> None:
        with self._connect() as c:
            c.executescript("""
            CREATE TABLE IF NOT EXISTS social_video_sources(
              provider_id TEXT PRIMARY KEY, provider_type TEXT NOT NULL,
              api_enabled INTEGER NOT NULL DEFAULT 0, embed_enabled INTEGER NOT NULL DEFAULT 1,
              active INTEGER NOT NULL DEFAULT 0, metadata_json TEXT NOT NULL DEFAULT '{}', updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS social_videos(
              id INTEGER PRIMARY KEY AUTOINCREMENT, provider_id TEXT NOT NULL, external_video_id TEXT NOT NULL,
              canonical_url TEXT NOT NULL, title TEXT, creator TEXT, category TEXT, thumbnail_url TEXT,
              related_ref TEXT, active INTEGER NOT NULL DEFAULT 1, metadata_json TEXT NOT NULL DEFAULT '{}',
              created_at TEXT NOT NULL, UNIQUE(provider_id,external_video_id));
            CREATE TABLE IF NOT EXISTS video_discussions(
              id INTEGER PRIMARY KEY AUTOINCREMENT, video_id INTEGER NOT NULL, user_ref TEXT NOT NULL,
              kind TEXT NOT NULL DEFAULT 'question', body TEXT NOT NULL, parent_id INTEGER,
              created_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS sponsored_campaigns(
              id INTEGER PRIMARY KEY AUTOINCREMENT, owner_ref TEXT NOT NULL, campaign_type TEXT NOT NULL,
              title TEXT NOT NULL, destination_url TEXT, category TEXT, location_scope TEXT,
              budget REAL, starts_at TEXT, ends_at TEXT, active INTEGER NOT NULL DEFAULT 0,
              metadata_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS partner_offers(
              id INTEGER PRIMARY KEY AUTOINCREMENT, partner_id TEXT NOT NULL, offer_type TEXT NOT NULL,
              title TEXT NOT NULL, bank_name TEXT, card_network TEXT, merchant TEXT, promo_code TEXT,
              discount_value REAL, discount_unit TEXT, starts_at TEXT, ends_at TEXT, terms_url TEXT,
              source_url TEXT, verified INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 0,
              metadata_json TEXT NOT NULL DEFAULT '{}', updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS scratch_rewards(
              id INTEGER PRIMARY KEY AUTOINCREMENT, user_ref TEXT NOT NULL, trigger_type TEXT NOT NULL,
              trigger_ref TEXT NOT NULL, reward_type TEXT NOT NULL, reward_value REAL NOT NULL DEFAULT 0,
              status TEXT NOT NULL DEFAULT 'LOCKED', reveal_token TEXT NOT NULL UNIQUE,
              expires_at TEXT, revealed_at TEXT, redeemed_at TEXT, metadata_json TEXT NOT NULL DEFAULT '{}',
              created_at TEXT NOT NULL, UNIQUE(user_ref,trigger_type,trigger_ref));
            CREATE TABLE IF NOT EXISTS growth_events(
              id INTEGER PRIMARY KEY AUTOINCREMENT, event_type TEXT NOT NULL, source_type TEXT NOT NULL,
              source_id TEXT NOT NULL, user_ref TEXT, value REAL, metadata_json TEXT NOT NULL DEFAULT '{}',
              created_at TEXT NOT NULL);
            """)
    def _connect(self):
        c=sqlite3.connect(self.db_path); c.row_factory=sqlite3.Row; return c
    def upsert_video_source(self, provider_id:str, provider_type:str, **v:Any)->dict[str,Any]:
        pid=provider_id.strip().lower()
        with self._connect() as c:
            c.execute("""INSERT INTO social_video_sources(provider_id,provider_type,api_enabled,embed_enabled,active,metadata_json,updated_at)
              VALUES(?,?,?,?,?,?,?) ON CONFLICT(provider_id) DO UPDATE SET provider_type=excluded.provider_type,
              api_enabled=excluded.api_enabled,embed_enabled=excluded.embed_enabled,active=excluded.active,
              metadata_json=excluded.metadata_json,updated_at=excluded.updated_at""",
              (pid,provider_type.strip().lower(),int(bool(v.get("api_enabled"))),int(bool(v.get("embed_enabled",True))),
               int(bool(v.get("active"))),json.dumps(v.get("metadata") or {}),_now()))
            return dict(c.execute("SELECT * FROM social_video_sources WHERE provider_id=?",(pid,)).fetchone())
    def create_campaign(self, owner_ref:str, campaign_type:str, title:str, **v:Any)->dict[str,Any]:
        if campaign_type not in {"sponsored","boost"}: raise ValueError("campaign_type must be sponsored or boost")
        now=_now()
        with self._connect() as c:
            cur=c.execute("""INSERT INTO sponsored_campaigns(owner_ref,campaign_type,title,destination_url,category,
              location_scope,budget,starts_at,ends_at,active,metadata_json,created_at,updated_at)
              VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",(owner_ref,campaign_type,title,v.get("destination_url"),
              v.get("category"),v.get("location_scope"),v.get("budget"),v.get("starts_at"),v.get("ends_at"),
              int(bool(v.get("active"))),json.dumps(v.get("metadata") or {}),now,now))
            return dict(c.execute("SELECT * FROM sponsored_campaigns WHERE id=?",(cur.lastrowid,)).fetchone())
    def create_offer(self, partner_id:str, offer_type:str, title:str, **v:Any)->dict[str,Any]:
        with self._connect() as c:
            cur=c.execute("""INSERT INTO partner_offers(partner_id,offer_type,title,bank_name,card_network,merchant,
              promo_code,discount_value,discount_unit,starts_at,ends_at,terms_url,source_url,verified,active,
              metadata_json,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",(partner_id,offer_type,title,
              v.get("bank_name"),v.get("card_network"),v.get("merchant"),v.get("promo_code"),v.get("discount_value"),
              v.get("discount_unit"),v.get("starts_at"),v.get("ends_at"),v.get("terms_url"),v.get("source_url"),
              int(bool(v.get("verified"))),int(bool(v.get("active"))),json.dumps(v.get("metadata") or {}),_now()))
            return dict(c.execute("SELECT * FROM partner_offers WHERE id=?",(cur.lastrowid,)).fetchone())
    def issue_scratch(self,user_ref:str,trigger_type:str,trigger_ref:str,reward_type:str,reward_value:float=0,**v:Any)->dict[str,Any]:
        token=secrets.token_urlsafe(24); now=_now()
        with self._connect() as c:
            c.execute("""INSERT OR IGNORE INTO scratch_rewards(user_ref,trigger_type,trigger_ref,reward_type,reward_value,
              status,reveal_token,expires_at,metadata_json,created_at) VALUES(?,?,?,?,?,'READY',?,?,?,?,?)""",
              (user_ref,trigger_type,trigger_ref,reward_type,float(reward_value),token,v.get("expires_at"),
               json.dumps(v.get("metadata") or {}),now))
            return dict(c.execute("""SELECT * FROM scratch_rewards WHERE user_ref=? AND trigger_type=? AND trigger_ref=?""",
                                  (user_ref,trigger_type,trigger_ref)).fetchone())
    def reveal_scratch(self,user_ref:str,token:str)->dict[str,Any]|None:
        with self._connect() as c:
            row=c.execute("SELECT * FROM scratch_rewards WHERE user_ref=? AND reveal_token=?",(user_ref,token)).fetchone()
            if not row: return None
            if row["status"]=="READY":
                c.execute("UPDATE scratch_rewards SET status='REVEALED',revealed_at=? WHERE id=?",(_now(),row["id"]))
            return dict(c.execute("SELECT * FROM scratch_rewards WHERE id=?",(row["id"],)).fetchone())
