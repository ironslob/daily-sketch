#!/usr/bin/env python3
"""Load profile for Phase 13 performance review."""

from __future__ import annotations

import asyncio
import json
import statistics
import sys
import time
from pathlib import Path

import httpx

BASE_URL = "http://localhost:8000"
ITERATIONS = 20
TARGETS_MS = {
    "prompt": 300,
    "feed": 500,
    "profile": 500,
    "like": 300,
    "reflection": 500,
    "submission": 700,
    "image_render": 500,
}


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = max(int(len(ordered) * pct) - 1, 0)
    return ordered[idx]


async def timed(client: httpx.AsyncClient, method: str, path: str, **kwargs: object) -> float:
    started = time.perf_counter()
    response = await client.request(method, path, **kwargs)
    elapsed_ms = (time.perf_counter() - started) * 1000
    response.raise_for_status()
    return elapsed_ms


async def main() -> int:
    results: dict[str, dict[str, float]] = {}
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=30.0) as client:
        try:
            await client.get("/health/live")
        except httpx.HTTPError as exc:
            print(f"Backend unavailable at {BASE_URL}: {exc}", file=sys.stderr)
            return 1

        prompt_samples: list[float] = []
        feed_samples: list[float] = []
        for _ in range(ITERATIONS):
            prompt_samples.append(await timed(client, "GET", "/api/v1/prompts/today"))
            feed_samples.append(await timed(client, "GET", "/api/v1/feed/recent"))

        results["prompt"] = {
            "p50_ms": statistics.median(prompt_samples),
            "p95_ms": percentile(prompt_samples, 0.95),
            "target_ms": TARGETS_MS["prompt"],
        }
        results["feed"] = {
            "p50_ms": statistics.median(feed_samples),
            "p95_ms": percentile(feed_samples, 0.95),
            "target_ms": TARGETS_MS["feed"],
        }

        feed_body = (await client.get("/api/v1/feed/recent")).json()
        image_ms = 0.0
        items = feed_body.get("items") or []
        if items:
            image_url = items[0].get("image_url") or items[0].get("thumbnail_url")
            if image_url:
                started = time.perf_counter()
                image_response = await client.get(image_url)
                image_response.raise_for_status()
                image_ms = (time.perf_counter() - started) * 1000
        results["image_render"] = {
            "p50_ms": image_ms,
            "p95_ms": image_ms,
            "target_ms": TARGETS_MS["image_render"],
        }

    out_path = Path(__file__).resolve().parents[2] / "docs" / "ops" / "performance-review.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
