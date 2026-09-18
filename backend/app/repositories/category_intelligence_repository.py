"""DB-backed category intelligence for ASKODOX."""
from __future__ import annotations
import json, sqlite3
from datetime import datetime, timezone
from typing import Any

_SEEDS = (
    ("COMMERCE","Goods / local commerce",["subject","quantity","budget","location"],["product","buy","sell","కొనాలి","అమ్మాలి"]),
    ("SERVICES","Local services",["service","problem","location","preferred_time","budget"],["service","repair","electrician","plumber","సర్వీస్","రిపేర్"]),
    ("BFSI","Banking, financial services and insurance",["product_type","amount","goal","tenure","location"],["loan","insurance","credit card","mutual fund","bank account","లోన్","ఇన్సూరెన్స్"]),
)

class CategoryIntelligenceRepository:
    def __init__(self, db_path: str="podx.db"):
        self.db_path=db_path; self._ensure_schema(); self._seed_defaults()
    def _connect(self):
        c=sqlite3.connect(self.db_path); c.row_factory=sqlite3.Row; return c
    @staticmethod
    def _now(): return datetime.now(timezone.utc).isoformat()
    def _ensure_schema(self):
        with self._connect() as c:
            c.execute("""CREATE TABLE IF NOT EXISTS category_definitions(category_key TEXT PRIMARY KEY,display_name TEXT NOT NULL,question_schema_json TEXT NOT NULL DEFAULT '[]',keywords_json TEXT NOT NULL DEFAULT '[]',active INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)""")
    def _seed_defaults(self):
        now=self._now()
        with self._connect() as c:
            for key,name,questions,keywords in _SEEDS:
                c.execute("""INSERT OR IGNORE INTO category_definitions(category_key,display_name,question_schema_json,keywords_json,active,created_at,updated_at) VALUES(?,?,?,?,1,?,?)""",(key,name,json.dumps(questions,ensure_ascii=False),json.dumps(keywords,ensure_ascii=False),now,now))
    @staticmethod
    def _decode(row):
        d=dict(row); d["question_schema"]=json.loads(d.pop("question_schema_json") or "[]"); d["keywords"]=json.loads(d.pop("keywords_json") or "[]"); d["active"]=bool(d["active"]); return d
    def get(self,key):
        with self._connect() as c: row=c.execute("SELECT * FROM category_definitions WHERE category_key=? AND active=1",(str(key or "").strip().upper(),)).fetchone()
        return self._decode(row) if row else None
    def list_active(self):
        with self._connect() as c: rows=c.execute("SELECT * FROM category_definitions WHERE active=1 ORDER BY category_key").fetchall()
        return [self._decode(r) for r in rows]
    def upsert(self,key,name,*,question_schema,keywords,active=True):
        key=str(key or "").strip().upper(); name=str(name or "").strip()
        if not key or not name: raise ValueError("category_key and display_name required")
        now=self._now()
        with self._connect() as c:
            c.execute("""INSERT INTO category_definitions(category_key,display_name,question_schema_json,keywords_json,active,created_at,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(category_key) DO UPDATE SET display_name=excluded.display_name,question_schema_json=excluded.question_schema_json,keywords_json=excluded.keywords_json,active=excluded.active,updated_at=excluded.updated_at""",(key,name,json.dumps(question_schema,ensure_ascii=False),json.dumps(keywords,ensure_ascii=False),int(active),now,now))
        return self.get(key)
    def match(self,message):
        text=" ".join(str(message or "").casefold().split()); best=None; score=0
        for cat in self.list_active():
            s=sum(1 for k in cat["keywords"] if k.casefold() in text)
            if s>score: best,score=cat,s
        if best: best=dict(best); best["keyword_score"]=score
        return best
