# Putting Mailworthy on CurseForge

Releases already work the way LedgerLink's do: pushing a `v*` tag runs
`.github/workflows/release.yml`, and the BigWigs packager builds
`Mailworthy-<tag>-forever.zip` and attaches it to a GitHub release. The upload
to CurseForge starts as soon as the project exists, the `.toc` names its ID and
the repo has an API token.

## Assets (ready in this repo)

| What | File | Where it goes |
|---|---|---|
| Project avatar (400x400) | `media/logo-400.png` (512x512: `media/logo-512.png`) | CurseForge project avatar |
| In-game icon (AddOns list) | `Mailworthy/Textures/Icon.tga` (64x64, uncompressed 32-bit) | shipped; `## IconTexture` in the `.toc` |
| Description | `media/curseforge-description.html` | project description (paste into the editor's HTML/source view) |
| Screenshots | `media/ui-prototype.png` (the mailbox window) and `media/bank-alt-prototype.png` (bank alt tags + tooltip), both the planned release UI | project images / gallery |
| Icon source | `media/logo.svg` | `tools/build-icons.sh` rebuilds the PNGs, the TGA and the screenshots |

Short summary for the project card: **"One click at the mailbox sends everything
worth selling to your bank alt. Vendor the rest."**

Suggested categories: Auction & Economy, Mail, Bags & Inventory.

Dependencies: Auctionator and Disenchantry are **optional**. `.pkgmeta`
(`optional-dependencies: auctionator, disenchantry`) sets the CurseForge relations
on each upload; `## OptionalDeps: Auctionator, Disenchantry` in the `.toc` makes
them load first when installed.

## Steps

1. **Create the project** at authors.curseforge.com: Create Project → World of
   Warcraft → name **Mailworthy**, the summary above, the avatar, the description,
   license **MIT**. Leave the source link empty while the GitHub repo is private
   (or make it public first).
2. **Copy the project ID** from the project's page and add it to
   `Mailworthy/Mailworthy.toc`:
   ```
   ## X-Curse-Project-ID: <id>
   ```
3. **Add the API token** as a repo secret (CurseForge: your account's API tokens
   page → create a token), then:
   ```bash
   gh secret set CF_API_KEY --repo sjdodge123/mailworthy
   ```
4. **Tag a release.** Tags with `alpha` / `beta` upload as alpha / beta files; a
   plain `v1.0.0` uploads as a release. The packager picks the game version from
   `## Interface: 16001` (WoW Forever 1.60.1).
5. CurseForge reviews new projects and new files before they show publicly
   (LedgerLink's took from minutes to a few hours).

## Before the first public upload

The current builds are **discovery builds** (self-test window, Yes/No questions,
attach / send tests, feature switches, logging). The first CurseForge file should
be the release build only:

- [ ] Phases 1-3 of `docs/PLAN.md`: prices + valuation, settings + bank alt picker,
      the real Mailworthy window (as in `media/ui-prototype.png`) and sending.
- [ ] Remove the self-test window, the Questions page, the attach / send tests and
      `/mw selftest`; keep slot locks (Alt+click, Bag locks), the border, the mail
      buttons and the Triangle binding.
- [ ] Keep the blocked-action recorder, but quiet: no chat spam for players.
- [ ] Discovery session 2 (alpha3) passes: no blocked actions with mouse/keyboard or
      the controller.
- [ ] The description matches what shipped (update `media/curseforge-description.html`).
- [ ] Steps 1-3 above, then tag `v1.0.0` (or `v1.0.0-beta1` to start as a beta).
