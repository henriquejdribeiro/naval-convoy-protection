#!/usr/bin/env python3
"""
record-sim.py — open the convoy webapp in headless Chromium, click Play
Demonstration, and record the canvas animation to a video file.

Runs inside the mcr.microsoft.com/playwright/python container which has
Playwright + Chromium pre-installed. The webapp is reached at
http://host.docker.internal:8000 (Docker Desktop's host alias).

Output: /work/out/convoy-sim.webm  (Playwright records webm natively;
ffmpeg converts to mp4 in a second container.)
"""
from __future__ import annotations
import sys, time
from pathlib import Path
from playwright.sync_api import sync_playwright

URL          = "http://host.docker.internal:8000"
OUT_DIR      = Path("/work/out")
OUT_DIR.mkdir(parents=True, exist_ok=True)
VIDEO_W      = 1920
VIDEO_H      = 1080
PLAY_TIMEOUT = 200_000  # ms — safety upper bound; we stop earlier on Replay

def main() -> int:
    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage"],
        )
        ctx = browser.new_context(
            viewport={"width": VIDEO_W, "height": VIDEO_H},
            record_video_dir=str(OUT_DIR),
            record_video_size={"width": VIDEO_W, "height": VIDEO_H},
        )
        page = ctx.new_page()
        print(f"[record] navigating to {URL}", flush=True)
        page.goto(URL, wait_until="networkidle")
        print("[record] page loaded", flush=True)

        # The convoy sim has a .cs-play button. Scroll into view, then click.
        play_btn = page.locator(".cs-play").first
        play_btn.scroll_into_view_if_needed()
        # Centre the simulation widget in the viewport so the recorded frame
        # mostly shows the animation rather than the page header.
        page.evaluate("""
            () => {
                const sim = document.querySelector('.cs-play')?.closest('section, .convoy-sim, [class*=convoy], [class*=sim]') || document.querySelector('.cs-play').parentElement;
                sim.scrollIntoView({block: 'center', behavior: 'instant'});
            }
        """)
        time.sleep(0.5)
        print("[record] clicking ▶ Play Demonstration", flush=True)
        play_btn.click()

        # Poll for completion. The button text flips back to "▶ Play
        # Demonstration" or "↻ Replay" when the simulation ends.
        start = time.time()
        last_progress = ""
        while True:
            elapsed_ms = (time.time() - start) * 1000
            if elapsed_ms > PLAY_TIMEOUT:
                print("[record] timeout reached, stopping", flush=True)
                break
            try:
                txt = play_btn.inner_text(timeout=500)
            except Exception:
                txt = ""
            # While playing, button reads "⏸ Pause"; when done it flips to
            # "↻ Replay" (or back to "▶ Play Demonstration").
            if "Pause" not in txt and elapsed_ms > 3000:
                print(f"[record] playback ended (button text: {txt!r}, "
                      f"elapsed={elapsed_ms/1000:.1f}s)", flush=True)
                break
            # Light progress logging
            try:
                prog = page.locator(".cs-progress-text, [class*=progress]").first.inner_text(timeout=200)
                if prog != last_progress:
                    print(f"[record] {prog}  (t={elapsed_ms/1000:.1f}s)", flush=True)
                    last_progress = prog
            except Exception:
                pass
            time.sleep(0.5)

        # Hold the final frame for 2 s
        time.sleep(2)

        # Close — Playwright finalises the video on context.close()
        video_obj = page.video
        ctx.close()
        browser.close()

        if video_obj is None:
            print("[record] no video object — recording failed", file=sys.stderr)
            return 1
        webm = Path(video_obj.path())
        out  = OUT_DIR / "convoy-sim.webm"
        if webm != out:
            webm.replace(out)
        size = out.stat().st_size
        print(f"[record] OK — {out} ({size:,} bytes)", flush=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())
