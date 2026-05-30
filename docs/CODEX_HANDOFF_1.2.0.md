# Codex Handoff — Cribble 1.2.0 (App Store IAP + Website)

Two deliverables for Codex: **(1)** create the in-app purchase in App Store
Connect using **computer use**, and **(2)** update the Cribble website for the
1.2.0 "Local Chat HUD" release. Do them in order. Stop and ask the human before
anything irreversible (submitting for review, publishing the live site).

Repo root: `/Users/amanpandey/projects/cribble`. Read
`docs/RELEASE_NOTES_1.2.0.md` first — it's the source of truth for copy.

---

## Part 1 — Create the IAP in App Store Connect (computer use)

**Goal:** register the non-consumable that unlocks the Local Chat HUD so the
StoreKit code (`LLMEntitlementStore`) and the App Store build (`-DAPPSTORE`)
work in production.

**Exact product to create — must match the code constant byte-for-byte:**
- Type: **Non-Consumable**
- Product ID (Reference: `LLMEntitlementStore.productID`): `com.cribble.reader.llm.unlock`
- Reference Name: `Local AI Unlock`
- Price: **$6.99** (USD tier — pick the tier whose USD price is 6.99)
- Display Name: `Unlock Local AI`
- Description: `Unlock the on-device Cribble AI chat assistant. One-time purchase.`
- Review screenshot: capture the unlock sheet (see Part 1 step 6).

**Steps (computer use via Safari/Chrome → App Store Connect):**
1. Request screen access for the browser, open `https://appstoreconnect.apple.com`.
   If not logged in, **pause and ask the human to authenticate** (do not type
   credentials yourself).
2. Go to **Apps → Cribble** (bundle `com.cribble.reader`, team `JP4HU7X6G7`).
3. Open **Monetization → In-App Purchases** → **＋** (Create).
4. Choose **Non-Consumable**. Enter the Product ID, Reference Name, price, and
   the localization (Display Name + Description) exactly as above.
5. Set availability to all territories (or match the app's territories).
6. For the **review screenshot**: in a Terminal run
   `bash script/build_and_run.sh run`, open the HUD (toolbar **Cribble AI** or
   press **C**); on an App-Store-style build the unlock sheet appears. Screenshot
   it (1290×2796 or any accepted size) and upload. If you can't reach the App
   Store build state, ask the human for the screenshot.
7. Save as **Ready to Submit** (it ships attached to the 1.2.0 build). **Do not
   submit the app for review** — leave that to the human.

**Then add the price/up-front note:** confirm the app's base price is **$2.49**
under **Pricing and Availability** (only change if the human confirms).

**Verification:** the new IAP shows status "Ready to Submit" and the Product ID
reads `com.cribble.reader.llm.unlock`. Report the final status back.

---

## Part 2 — Website update for 1.2.0

The site lives in `/Users/amanpandey/projects/cribble/website` (+ `vercel.json`
at the repo root). Inspect the existing structure and the prior release pattern
(the 1.1.x changes referenced in `git log`) before editing — **match the
existing components, styling, and tone; don't restyle the site.**

**Make these content changes:**
1. **Headline feature block / "What's new":** add the **Local Chat HUD** —
   on-device AI chat (Apple MLX), `@`-tag notes for context, safe reviewable
   diffs, fully private/offline. Pull copy from `docs/RELEASE_NOTES_1.2.0.md`.
2. **Version bump:** update any visible version string / download badges from
   1.1.3 → **1.2.0** (the repo `VERSION` file is already `1.2.0`).
3. **Pricing/availability copy (if the site mentions it):**
   - Mac App Store: paid app + **$6.99** one-time in-app purchase to unlock Local AI.
   - Direct DMG download: Local AI **included/unlocked**.
4. **Requirements note:** macOS 15+, Apple Silicon, ~1.2–2.9 GB model download on
   first use.
5. If the site has a changelog/release-notes page, add a 1.2.0 entry mirroring
   `docs/RELEASE_NOTES_1.2.0.md`.

**Build/preview, don't auto-deploy:**
- Run the site's local build/dev command (check `website/package.json` /
  `vercel.json`) and verify it builds with no errors.
- **Do not publish to production / push a deploy.** Show the diff and the local
  preview, then ask the human to approve before any deploy.

**Verification:** site builds locally; 1.2.0 + Local Chat HUD copy visible on the
landing page; version strings updated; no styling regressions.

---

## Out of scope (already done in the app repo — don't touch)
- App code, `LLMUnlockSheet`, StoreKit wiring, model catalog, `-DAPPSTORE` flag
  in `script/package_app_store.sh`, `VERSION`, `Fixtures/Cribble.storekit`.
