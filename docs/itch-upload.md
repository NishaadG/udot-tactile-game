# Uploading Mine Line to itch.io (about 3 minutes)

**File to upload:** `build/mine-line-web.zip`. It has `index.html` at the top level, which is what itch needs.

1. Go to https://itch.io/game/new while logged in.
2. **Title:** `Mine Line`. **Project URL:** `mine-line` (gives `https://<your-username>.itch.io/mine-line`).
3. **Short description:** `Find two mines by sound, then guess the rest from the line. A tactile + audio graph game for blind kids.`
4. **Classification:** Games. **Kind of project:** **HTML** (important).
5. **Release status:** Released (or Prototype).
6. **Pricing:** No payments.
7. **Uploads:** upload `mine-line-web.zip`, then tick **"This file will be played in the browser"**.
8. **Embed options:**
   - Viewport dimensions: **1280 × 800**
   - Leave **Click to launch in fullscreen** off. The default "Run game" button is enough, and that first click also unlocks audio.
   - Tick **Fullscreen button**.
   - Leave **SharedArrayBuffer support** off. The build is single-threaded and doesn't need it.
9. **Description:** paste the "Page description" below.
10. **Genre:** Puzzle. **Tags:** `accessibility`, `audio-game`, `blind`, `educational`, `math`, `godot`.
11. **Accessibility** section: tick **Blind friendly**, **Configurable controls?** (no), **Interactive tutorial**, **Subtitles**.
12. **Cover image:** `docs/itch-cover.png` (630×500). **Screenshots:** the images in `docs/screenshots/`.
13. **Visibility:** **Public** (so the uDot team can open it). Save, then open the page and play through Training once with sound on.

Then put the link in the README (replace "_itch.io link coming soon_") and in your email.

---

## Page description (paste into itch)

**Mine Line** is a game for blind and visually impaired kids, designed for a refreshable tactile (pin) display and prototyped here in the browser.

A saboteur has buried mines along a line, so every column hides one. Find two with your detector: it ticks faster the closer you get. Then it overheats, and you have to guess the next mine from the pattern. Guess right and the whole line chain-defuses. Miss three times: BOOM.

**Play with sound on and your eyes closed.** Headphones help. Start with Training, which teaches itself in about a minute.

**Controls:** Arrows move · Enter digs · P plays your mines as notes · C: where am I? · R repeats · V speaks every step · H toggles the sighted helper view · Esc for the menu. Mouse works too (hover = finger, click = dig). Reviewers: Shift+U on the menu unlocks all missions.

Made with Godot 4. Every sound is synthesised in code. Built for the uDot Braille Tech game-design challenge.
