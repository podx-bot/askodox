"""Small, failure-tolerant Google Maps Platform client for PODX server-side use."""
from __future__ import annotations

import os
import re
from typing import Any
from urllib.parse import quote_plus

import httpx

from app.services import external_call_budget


class GoogleMapsService:
    GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json"
    ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
    PLACES_TEXT_URL = "https://places.googleapis.com/v1/places:searchText"
    PLACES_FIELDS = (
        "places.id,places.displayName,places.formattedAddress,places.location,"
        "places.rating,places.userRatingCount,places.googleMapsUri,"
        "places.businessStatus,places.currentOpeningHours.openNow"
    )

    def __init__(self, api_key: str | None = None, timeout_seconds: float | None = None, client=None) -> None:
        self.api_key = str(api_key if api_key is not None else os.getenv("GOOGLE_MAPS_API_KEY", "")).strip()
        raw_timeout = timeout_seconds if timeout_seconds is not None else os.getenv("GOOGLE_MAPS_TIMEOUT_SECONDS", "5")
        try:
            self.timeout_seconds = max(1.0, float(raw_timeout))
        except (TypeError, ValueError):
            self.timeout_seconds = 5.0
        self.client = client or httpx.Client(timeout=self.timeout_seconds)
        # True when the latest Places call failed at the provider (API not
        # enabled, key restricted, quota) -- reported as an error, not as
        # "no nearby shops".
        self.last_error = False

    @property
    def enabled(self) -> bool:
        return bool(self.api_key)

    def geocode(self, place: str, region: str = "in") -> dict[str, Any] | None:
        query = " ".join(str(place or "").strip().split())
        if not self.enabled or not query:
            return None
        try:
            response = self.client.get(
                self.GEOCODE_URL,
                params={"address": query, "region": region, "key": self.api_key},
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError, TypeError):
            return None
        if str(payload.get("status") or "").upper() != "OK":
            return None
        results = payload.get("results") or []
        if not results:
            return None
        first = results[0] or {}
        location = ((first.get("geometry") or {}).get("location") or {})
        try:
            lat, lon = float(location["lat"]), float(location["lng"])
        except (KeyError, TypeError, ValueError):
            return None
        return {
            "name": str(first.get("formatted_address") or query),
            "latitude": lat,
            "longitude": lon,
            "place_id": str(first.get("place_id") or ""),
        }

    def api_status(self, latitude: float = 16.5062, longitude: float = 80.6480) -> dict[str, str]:
        """Live, per-API readiness of THIS key (Admin: Integrations → Check).

        Each Google API is enabled separately on the key's Cloud project;
        this names which ones answer and quotes Google's own error for the
        others (e.g. "This API project is not authorized to use this API").
        The key itself is never returned. Not cached.
        """
        if not self.enabled:
            return {"key": "missing (GOOGLE_MAPS_API_KEY not set)"}

        def call(method: str, url: str, **kwargs) -> tuple[int, Any]:
            try:
                response = getattr(self.client, method)(url, timeout=self.timeout_seconds, **kwargs)
                try:
                    return response.status_code, response.json()
                except ValueError:
                    return response.status_code, {}
            except httpx.HTTPError as error:
                return 0, {"error": {"message": type(error).__name__}}

        def verdict(code: int, data: Any, ok: bool) -> str:
            if ok:
                return "OK"
            message = str(((data or {}).get("error") or {}).get("message")
                          or (data or {}).get("error_message") or (data or {}).get("status") or "")
            return f"FAILED (HTTP {code}) {message[:160]}".strip()

        status: dict[str, str] = {}
        code, data = call("get", self.GEOCODE_URL,
                          params={"latlng": f"{latitude},{longitude}", "key": self.api_key})
        status["geocoding"] = verdict(code, data, str((data or {}).get("status")) == "OK")
        headers = {"X-Goog-Api-Key": self.api_key, "X-Goog-FieldMask": "places.displayName"}
        code, data = call("post", self.PLACES_TEXT_URL, headers=headers,
                          json={"textQuery": "AC repair near Vijayawada", "regionCode": "IN", "maxResultCount": 1})
        status["places_text_search"] = verdict(code, data, code == 200)
        code, data = call("post", self.PLACES_NEARBY_URL, headers=headers, json={
            "includedTypes": ["locality"], "maxResultCount": 1,
            "locationRestriction": {"circle": {"center": {"latitude": latitude, "longitude": longitude},
                                               "radius": 10000.0}}})
        status["places_nearby"] = verdict(code, data, code == 200)
        code, data = call("post", self.ROUTES_URL, headers={
            "X-Goog-Api-Key": self.api_key, "X-Goog-FieldMask": "routes.distanceMeters"}, json={
            "origin": {"location": {"latLng": {"latitude": latitude, "longitude": longitude}}},
            "destination": {"location": {"latLng": {"latitude": latitude + 0.05, "longitude": longitude + 0.05}}},
            "travelMode": "DRIVE"})
        status["routes"] = verdict(code, data, code == 200)
        return status

    _AREA_TYPES = ("sublocality_level_1", "sublocality", "neighborhood", "sublocality_level_2")

    def reverse_geocode(self, latitude: float, longitude: float) -> dict[str, Any] | None:
        """Readable place for a GPS point: area / city / district / state.

        Returns None when Maps is not configured or the provider fails --
        callers must then keep saying "current location" honestly rather
        than inventing a place name.
        """
        try:
            lat, lon = float(latitude), float(longitude)
        except (TypeError, ValueError):
            return None
        if not self.enabled:
            return None

        def fetch() -> Any:
            response = self.client.get(
                self.GEOCODE_URL,
                params={"latlng": f"{lat:.5f},{lon:.5f}", "key": self.api_key, "language": "en"},
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            return response.json()

        try:
            payload = external_call_budget.cached_call("google_geocode", (round(lat, 4), round(lon, 4)), fetch)
        except (httpx.HTTPError, ValueError, TypeError):
            self.last_error = True
            return None
        if str((payload or {}).get("status") or "").upper() != "OK":
            # Geocoding API not enabled on the key (REQUEST_DENIED) or no
            # result: name the town from the nearest Places locality instead.
            return self._locality_from_places(lat, lon)
        parts: dict[str, str] = {}
        for result in (payload.get("results") or [])[:5]:
            for component in (result or {}).get("address_components") or []:
                types = component.get("types") or []
                name = str(component.get("long_name") or "").strip()
                if not name:
                    continue
                if "area" not in parts and any(t in types for t in self._AREA_TYPES):
                    parts["area"] = name
                elif "city" not in parts and "locality" in types:
                    parts["city"] = name
                elif "district" not in parts and "administrative_area_level_3" in types:
                    parts["district"] = name
                elif "district" not in parts and "administrative_area_level_2" in types:
                    parts["district"] = name
                elif "state" not in parts and "administrative_area_level_1" in types:
                    parts["state"] = name
                elif "country" not in parts and "country" in types:
                    parts["country"] = name
                    parts["country_code"] = str(component.get("short_name") or "").upper()
        if not parts:
            return None
        label_parts = [parts.get("area"), parts.get("city") or parts.get("district"), parts.get("state")]
        label = ", ".join(dict.fromkeys(p for p in label_parts if p))
        return {**parts, "label": label, "latitude": lat, "longitude": lon}

    PLACES_NEARBY_URL = "https://places.googleapis.com/v1/places:searchNearby"

    def _locality_from_places(self, lat: float, lon: float) -> dict[str, Any] | None:
        """Nearest town/locality around the point (Places API), or None."""
        body = {
            "includedTypes": ["locality", "sublocality", "neighborhood"],
            "maxResultCount": 3,
            "rankPreference": "DISTANCE",
            "locationRestriction": {"circle": {"center": {"latitude": lat, "longitude": lon}, "radius": 10000.0}},
        }

        def fetch() -> Any:
            response = self.client.post(
                self.PLACES_NEARBY_URL,
                json=body,
                headers={"X-Goog-Api-Key": self.api_key,
                         "X-Goog-FieldMask": "places.displayName,places.addressComponents"},
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            return response.json()

        try:
            payload = external_call_budget.cached_call("google_places", ("locality", round(lat, 3), round(lon, 3)), fetch)
        except (httpx.HTTPError, ValueError, TypeError):
            return None
        for place in (payload or {}).get("places") or []:
            name = str(((place or {}).get("displayName") or {}).get("text") or "").strip()
            if not name:
                continue
            state = ""
            for component in place.get("addressComponents") or []:
                if "administrative_area_level_1" in (component.get("types") or []):
                    state = str(component.get("longText") or "").strip()
            label = ", ".join(p for p in (name, state) if p)
            return {"city": name, "state": state or None, "label": label, "latitude": lat, "longitude": lon,
                    "source": "places"}
        return None

    def search_places(
        self,
        query: str,
        *,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_m: float = 5000.0,
        limit: int = 8,
        region: str = "in",
    ) -> list[dict[str, Any]]:
        """Nearby offline shops/providers for a need (Places API text search).

        Used for "nearby external/offline businesses" in chat results. Never
        raises; returns [] when disabled or on any provider failure.
        """
        clean = " ".join(str(query or "").strip().split())
        if not self.enabled or not clean:
            return []
        body: dict[str, Any] = {
            "textQuery": clean,
            "maxResultCount": max(1, min(int(limit), 20)),
            # India-first: results and names for the Indian region.
            "regionCode": region.upper(),
            "languageCode": "en",
        }
        if latitude is not None and longitude is not None:
            body["locationBias"] = {
                "circle": {
                    "center": {"latitude": float(latitude), "longitude": float(longitude)},
                    "radius": float(max(500.0, min(radius_m, 50000.0))),
                }
            }

        def fetch() -> Any:
            response = self.client.post(
                self.PLACES_TEXT_URL,
                json=body,
                headers={"X-Goog-Api-Key": self.api_key, "X-Goog-FieldMask": self.PLACES_FIELDS},
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            return response.json()

        key = (clean, body["maxResultCount"], body["regionCode"], repr(body.get("locationBias")))
        self.last_error = False
        try:
            payload = external_call_budget.cached_call("google_places", key, fetch)
        except (httpx.HTTPError, ValueError, TypeError):
            self.last_error = True
            return []
        places = []
        for place in (payload or {}).get("places") or []:
            if not isinstance(place, dict):
                continue
            if str(place.get("businessStatus") or "OPERATIONAL").upper() != "OPERATIONAL":
                continue
            name = str(((place.get("displayName") or {}).get("text")) or "").strip()
            location = place.get("location") or {}
            if not name:
                continue
            places.append({
                "place_id": str(place.get("id") or ""),
                "name": name,
                "address": str(place.get("formattedAddress") or "").strip(),
                "latitude": location.get("latitude"),
                "longitude": location.get("longitude"),
                "rating": place.get("rating"),
                "rating_count": place.get("userRatingCount"),
                "maps_url": str(place.get("googleMapsUri") or ""),
                "open_now": (place.get("currentOpeningHours") or {}).get("openNow"),
            })
        return places

    def compute_route(self, points: list[dict[str, Any]]) -> dict[str, Any] | None:
        coords = [self._lat_lng(point) for point in points]
        coords = [point for point in coords if point is not None]
        if not self.enabled or len(coords) < 2:
            return None
        body: dict[str, Any] = {
            "origin": {"location": {"latLng": coords[0]}},
            "destination": {"location": {"latLng": coords[-1]}},
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
        }
        if len(coords) > 2:
            body["intermediates"] = [{"location": {"latLng": point}} for point in coords[1:-1]]
        headers = {
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
            "Content-Type": "application/json",
        }
        try:
            response = self.client.post(self.ROUTES_URL, json=body, headers=headers, timeout=self.timeout_seconds)
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError, TypeError):
            return None
        routes = payload.get("routes") or []
        if not routes:
            return None
        route = routes[0] or {}
        try:
            distance_m = int(route.get("distanceMeters") or 0)
        except (TypeError, ValueError):
            distance_m = 0
        duration_s = self._duration_seconds(route.get("duration"))
        polyline = ((route.get("polyline") or {}).get("encodedPolyline") or "")
        return {
            "distance_meters": distance_m,
            "distance_km": round(distance_m / 1000.0, 2) if distance_m else None,
            "duration_seconds": duration_s,
            "duration_minutes": round(duration_s / 60) if duration_s is not None else None,
            "encoded_polyline": str(polyline),
        }

    @staticmethod
    def directions_url(origin: str, destination: str, waypoints: list[str] | None = None) -> str:
        params = [
            "api=1",
            f"origin={quote_plus(str(origin or '').strip())}",
            f"destination={quote_plus(str(destination or '').strip())}",
            "travelmode=driving",
        ]
        clean_waypoints = [str(x).strip() for x in (waypoints or []) if str(x).strip()]
        if clean_waypoints:
            params.append("waypoints=" + quote_plus("|".join(clean_waypoints)))
        return "https://www.google.com/maps/dir/?" + "&".join(params)

    @staticmethod
    def _lat_lng(point: dict[str, Any]) -> dict[str, float] | None:
        try:
            return {"latitude": float(point["latitude"]), "longitude": float(point["longitude"])}
        except (KeyError, TypeError, ValueError):
            return None

    @staticmethod
    def _duration_seconds(value: Any) -> int | None:
        match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)s\s*", str(value or ""))
        return int(round(float(match.group(1)))) if match else None
