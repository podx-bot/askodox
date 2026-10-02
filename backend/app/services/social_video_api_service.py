"""Official social-video API adapters.

Credentials are read only from deployment environment variables.  No token is
persisted or returned.  Adapters fail closed and the existing ASKODOX web/video
fallback remains available when a provider is not configured.
"""
from __future__ import annotations
import json, os
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from typing import Any

class SocialVideoApiService:
    def __init__(self, timeout_seconds: int = 8) -> None:
        self.timeout_seconds=max(1,min(int(timeout_seconds),20))

    @staticmethod
    def _youtube_api_key() -> str:
        """Read the production key, while accepting the Admin/Railway legacy name."""
        return (os.getenv("YOUTUBE_DATA_API_KEY","").strip()
                or os.getenv("YOUTUBE_API_KEY","").strip())

    def status(self) -> list[dict[str,Any]]:
        return [
            {"provider_id":"youtube","provider_type":"youtube_data_api_v3",
             "configured":bool(self._youtube_api_key())},
            {"provider_id":"meta","provider_type":"meta_graph_api",
             "configured":bool(os.getenv("META_GRAPH_ACCESS_TOKEN","").strip())},
        ]

    def youtube_search(self, query:str, max_results:int=10) -> list[dict[str,Any]]:
        key=self._youtube_api_key()
        query=" ".join(str(query or "").split())
        if not key or not query: return []
        params=urlencode({"part":"snippet","type":"video","q":query,
                          "maxResults":max(1,min(int(max_results),25)),"key":key})
        data=self._json("https://www.googleapis.com/youtube/v3/search?"+params)
        rows=[]
        for item in data.get("items",[]) if isinstance(data,dict) else []:
            vid=(item.get("id") or {}).get("videoId")
            snippet=item.get("snippet") or {}
            if not vid: continue
            thumbs=snippet.get("thumbnails") or {}
            thumb=((thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {}).get("url") or "")
            rows.append({"provider_id":"youtube","external_video_id":vid,
                         "canonical_url":"https://www.youtube.com/watch?v="+vid,
                         "title":snippet.get("title") or "","creator":snippet.get("channelTitle") or "",
                         "thumbnail_url":thumb})
        return rows

    def meta_object(self, object_id:str, fields:str="id,permalink_url") -> dict[str,Any]:
        token=os.getenv("META_GRAPH_ACCESS_TOKEN","").strip()
        object_id=str(object_id or "").strip()
        if not token or not object_id: return {}
        version=os.getenv("META_GRAPH_API_VERSION","v24.0").strip() or "v24.0"
        safe_fields=",".join(x for x in fields.split(",") if x.replace("_","").isalnum())
        params=urlencode({"fields":safe_fields or "id,permalink_url","access_token":token})
        return self._json(f"https://graph.facebook.com/{version}/{object_id}?{params}")

    def _json(self,url:str)->dict[str,Any]:
        req=Request(url,headers={"Accept":"application/json","User-Agent":"ASKODOX/1.0"})
        with urlopen(req,timeout=self.timeout_seconds) as response:
            payload=response.read(2_000_000)
        data=json.loads(payload.decode("utf-8"))
        return data if isinstance(data,dict) else {}
