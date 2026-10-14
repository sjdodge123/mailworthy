# Putting Mailworthy on CurseForge

All paths below are in the **mailworthy** repo (LedgerLink has files with the
same names in its own `media/`). Releases already work the way LedgerLink's do: pushing a `v*` tag runs
`.github/workflows/release.yml`, and the BigWigs packager builds
`Mailworthy-<tag>-forever.zip` and attaches it to a GitHub release. The upload
to CurseForge starts as soon as the project exists, the `.toc` names its ID and
the repo has an API token.

## Assets (ready in this repo)

| What | File | Where it goes |
|---|---|---|
| Project avatar (400x400) | [media/logo-400.png](../media/logo-400.png) (512x512: [media/logo-512.png](../media/logo-512.png)) | CurseForge project avatar |
| In-game icon (AddOns list) | [Mailworthy/Textures/Icon.tga](../Mailworthy/Textures/Icon.tga) (64x64, uncompressed 32-bit) | shipped; `## IconTexture` in the `.toc` |
| Description | [media/curseforge-description.html](../media/curseforge-description.html) | project description (paste into the editor's HTML/source view) |
| Screenshots | [media/ui-prototype.png](../media/ui-prototype.png) (the mailbox window) and [media/bank-alt-prototype.png](../media/bank-alt-prototype.png) (bank alt tags + tooltip), both the planned release UI | project images / gallery |
| Icon source | [media/logo.svg](../media/logo.svg) | [tools/build-icons.sh](../tools/build-icons.sh) rebuilds the PNGs, the TGA and the screenshots |

Short summary for the project card: **"One click at the mailbox sends everything
worth selling to your bank alt. Vendor the rest."**

Suggested categories: Auction & Economy, Mail, Bags & Inventory.

Dependencies: Auctionator and Disenchantry are **optional**. `.pkgmeta`
(`optional-dependencies: auctionator, disenchantry`) sets the CurseForge relations
on each upload; `## OptionalDeps: Auctionator, Disenchantry` in the `.toc` makes
them load first when installed.

## Steps

1. ~~Create the project~~ **Done:** project ID **1743661** (2026-10-13).
2. ~~Add the ID to the `.toc`~~ **Done:** `## X-Curse-Project-ID: 1743661` in
   `Mailworthy/Mailworthy.toc`.
3. ~~Add the API token~~ **Done:** `CF_API_KEY` is set (operator, 2026-10-13: every release goes to CurseForge).
   CurseForge: your account's API tokens page -> create a token, then:
   ```bash
   gh secret set CF_API_KEY --repo sjdodge123/mailworthy
   ```
   From then on every `v*` tag uploads there.
4. **Release tags:** plain `vX.Y.Z` (e.g. `v0.2.0`) upload as **release** files;
   `-alpha` / `-beta` tags would upload as alpha / beta files (not used any more).
   The packager picks the game version from `## Interface: 16001` (WoW Forever
   1.60.1) and the changelog from the commits since the previous tag.
5. CurseForge reviews new files before they show publicly
   (LedgerLink's took from minutes to a few hours).

## Toward v1.0

Releases go to CurseForge from v0.2.0 on. Before v1.0:

- [x] Phases 1-4c of `docs/PLAN.md`: prices + valuation, settings + bank alt picker,
      the real Mailworthy window (as in `media/ui-prototype.png`), sending, bank alt view.
- [x] Remove the self-test window, the Questions page, the attach / send tests and
      `/mw selftest` (`/mw report` instead); keep item locks (Alt+click, L3, window
      rows), the glow, the mail buttons and the Triangle binding.
- [x] Keep the blocked-action recorder, but quiet: one chat line per session.
- [x] Discovery session 2 passes: no blocked actions with mouse/keyboard or the
      controller (alpha4 and alpha5).
- [x] The description matches what shipped (`media/curseforge-description.html`, Phase 5).
- [ ] The v1.0 check passes (`docs/DISCOVERY-SESSION-2.md`).
- [ ] Tag `v1.0.0`.
