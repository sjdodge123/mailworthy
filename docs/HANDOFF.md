# Mailworthy handoff (2026-10-13)

Everything a new agent needs to continue Mailworthy from this directory. It
was built in one long session that started in the LedgerLink repo; this file
replaces that conversation. Read it fully, then `docs/PLAN.md`.

## 1. What Mailworthy is

A WoW **Forever** addon (client 1.60.1, `## Interface: 16001`; classic-style game,
retail-style UI code). At a mailbox, one button mails every bag item worth more on
the auction house (after fees) or disenchanted than at a vendor to the player's
**bank alt**; the rest stays in the bags for the vendor. The bank alt then sees
tags (AH / DE / Vendor) recomputed with fresh prices. Optional integrations:
Auctionator (prices, recommended) and Disenchantry (switches on the disenchant
comparison).

The operator (repo owner) plays on a **Windows PC with a gamepad**, tests in
game, and pastes reports back. **Keyboard/mouse is the priority** ("if mouse/kb
doesn't work no one will use it"); the controller is a must-have bonus that
must never break the game.

## 2. Where things are

| What | Where |
|---|---|
| Repo | `~/Documents/Projects/mailworthy`, GitHub `sjdodge123/mailworthy` (private), `main` |
| Design + phases + decision rule | [docs/PLAN.md](PLAN.md) |
| Blizzard source findings + **taint rules** | [docs/FOREVER-UI-NOTES.md](FOREVER-UI-NOTES.md) |
| In-game discovery history (U1-U20 results, rerun scripts) | [docs/DISCOVERY-SESSION-2.md](DISCOVERY-SESSION-2.md) |
| CurseForge setup, assets, path to v1.0 | [docs/CURSEFORGE.md](CURSEFORGE.md) |
| Controller UI screenshot (reference) | [docs/img/forever-mailbox-gamepad.webp](img/forever-mailbox-gamepad.webp) |
| Logo source / avatar / in-game icon | [media/logo.svg](../media/logo.svg), [media/logo-400.png](../media/logo-400.png), [media/logo-512.png](../media/logo-512.png), [Mailworthy/Textures/Icon.tga](../Mailworthy/Textures/Icon.tga) |
| **Target release UI** (mailbox window) | [media/ui-prototype.html](../media/ui-prototype.html) -> [.png](../media/ui-prototype.png) |
| **Target bank alt view** (tags + tooltip + summary) | [media/bank-alt-prototype.html](../media/bank-alt-prototype.html) -> [.png](../media/bank-alt-prototype.png) |
| CurseForge description (paste into the project page) | [media/curseforge-description.html](../media/curseforge-description.html) |
| Rebuild icon/avatar/TGA/screenshots | [tools/build-icons.sh](../tools/build-icons.sh) (Chrome headless + Pillow) |
| Package layout check (CI) | [tools/check-package-layout.sh](../tools/check-package-layout.sh) |
| Agent rules | [AGENTS.md](../AGENTS.md) (CLAUDE.md includes it) |
| Blizzard's Forever UI source | GitHub `Ketho/wow-ui-source-forever` (branch `forever`); read with `gh api repos/Ketho/wow-ui-source-forever/contents/<path>?ref=forever --jq .content \| base64 -d`, search with `gh search code --repo Ketho/wow-ui-source-forever "<term>"`. Snapshot of build 70205: `Bleakfiber/Blizzard-Interface-Assets---Forever-1.60.1.70205` |
| Sibling project | LedgerLink at `~/Documents/Projects/ledger-link` (CurseForge 1728299). Its `/rl probe` sections S5-S8 (v1.3.0-v1.3.3) were Mailworthy's first discovery tool: price addons, bag values, mail/AH/gamepad APIs, smart navigation dumps, the bag "More" menu recorder, AH deposits. LedgerLink's own rules (wire format owned by Raid Ledger) don't apply here |

**Same-named files trap:** LedgerLink also has `media/logo-400.png`,
`media/curseforge-description.html`, etc. Always use paths inside this repo.

## 3. Code (Mailworthy/, load order = .toc)

| File | Role |
|---|---|
| `Core.lua` | namespace, SavedVariables (`MailworthyDB` account, `MailworthyCharDB` per char), event dispatch `ns.On/ns.Fire`, slash `/mw`, **feature switches** `/mw feature <name> on|off` (mailButton, padTriangle, padNav, padLock, altClickLock, slotBorder; logged at login) |
| `Log.lua` | account-wide self-test log (400 lines) |
| `Blocked.lua` | records `ADDON_ACTION_FORBIDDEN/BLOCKED` blamed on Mailworthy, with the last command; chat line |
| `Characters.lua` | known characters (name "First Surname", realm, faction, class, level, professions); `Mailable()` = same realm+faction; SavedVariables marker per login/reload |
| `Gamepad.lua` | read-only helpers: button symbols (`labelStyle`, `CreateAtlasMarkup`), API presence |
| `Locks.lua` | **item locks** (by item ID, per character; follow the item; slot locks migrate); Alt+click via `hooksecurefunc("HandleModifiedItemClick")`; L3 via read-only `SmartNavigation:GetCurrentButton()` |
| `Border.lua` | blue glow on locked items: Blizzard's quest border texture tinted blue, on bag buttons via `hooksecurefunc(frame, "UpdateItems")` on combined + individual bag frames |
| `MailButton.lua` | "Mailworthy" button under the mail window on both tabs (children of InboxFrame / SendMailFrame, created at login); `Activate` toggles the window; controller on the Inbox gets an "R1 first" hint (we never switch tabs) |
| `Nav.lua` | Mailworthy's **own** controller navigation for its window: nearest button within 45 degrees, top-left start, gold highlight |
| `PadKey.lua` | Mailworthy's **own override bindings** (watcher every 0.1 s, re-apply when replaced, clear on focus loss and at `PLAYER_REGEN_DISABLED`): set `mail` (Triangle), `window` (Triangle, D-pad, Cross, Circle), `bags` (L3 lock) |
| `Prices.lua` | Auctionator adapter (`Lookup`: AH price per unit, age in days, exact, disenchant; nil without Auctionator), vendor price (`GetItemInfo` 11th return), class ID, `DisenchantryInstalled` |
| `Valuation.lua` | **pure** decision rule: settings (defaults + saved, disenchant follows Disenchantry), deposit, thresholds, keep reasons, no-Auctionator rule, `Money` formatting |
| `Bags.lua` | scan bags 0-4 -> slots -> items (grouped per link + bound + in-use), locks, prices, verdicts, totals; `/mw scan` report in the copy box (sends nothing) |
| `SelfTest.lua` / `SelfTestUI.lua` | **discovery build only**: window with pages Questions / Bag locks / Tests, attach + chained send tests, inbox checks, `/mw selftest report`. To be replaced by the real window (Phase 3) and removed before v1.0 |

Tests: `spec/` (busted on LuaJIT, 79 specs) with a WoW stub in
`spec/support/wow_stub.lua` (bags, mail send tab, postage, timers with delays,
override bindings, focused frame, item buttons that **error on any field write**).
Guard spec `no_gamepad_taint_spec.lua`: Mailworthy may only *read*
`FrameControlsManager:GetActiveFrame()` and `SmartNavigation:GetCurrentButton()`.

## 4. Measured facts (in game, 2026-10-13)

- Auctionator 340/341 on Forever: `Auctionator.API.v1` has `GetAuctionPriceByItemLink`,
  `GetAuctionAgeByItemLink`, `IsAuctionDataExactByItemLink`, `GetDisenchantPriceByItemLink`,
  `GetVendorPriceByItemLink`, `RegisterForDBUpdate` (caller ID "Mailworthy"). Prices only
  after a scan. Disenchant values were never seen (no green item tested).
- Disenchantry 1.1.1: no readable price data (`DisenchantryDB` = settings only).
- Postage: **30c per attached item** (30c empty). 12 attachments per mail.
- AH: modern `C_AuctionHouse`; durations index 1/2/3 = **2 / 8 / 24 hours**;
  deposit = **floor(vendor value of stack x 5%) x 1 / 4 / 12**, same for commodities
  and items, computable with the AH closed (0 for uncached items).
  `GetItemCommodityStatus`: 1 = item, 2 = commodity. AH cut assumed **5%** (not yet
  verified; `GetInboxInvoiceInfo` on a sale mail gives `consignment`).
- Attaching with `C_Container.UseContainerItem` works on a press **and from a timer**;
  `ClearSendMail()` returns items; `SendMail(name, subject, "")` to "First Surname"
  works; mail 2 chained after `MAIL_SEND_SUCCESS` with no press works; mails were in
  the bank alt's inbox 89 s later.
- Bags: backpack 20 slots, `NUM_BAG_SLOTS` 4; `GetContainerItemInfo` gives
  `isBound, hasNoValue, isLocked, quality, stackCount, itemID, hyperlink, iconFileID`;
  quest via `GetContainerItemQuestInfo`; sell price = `GetItemInfo` 11th return.
- Settings API: `Settings.RegisterCanvasLayoutCategory` (no `InterfaceOptions_AddCategory`).
- Mail auto-complete has no "my characters" flag (own list needed).
- SavedVariables persist across login, character switch and `/reload`.
- `labelStyle` "Shapes" (PlayStation); atlas markup works. Minimap buttons are not
  reachable with the controller.
- **alpha3/alpha4/alpha5: zero blocked actions** with controller and mouse/keyboard.
  Own Triangle binding: 9 presses, Blizzard replaced it twice in 2 minutes.
- **alpha5 (all 11 questions yes):** envelope icon, Alt+click and L3 locks, locks
  follow the item through sorting, blue glow, Triangle toggles the window, D-pad
  highlight reaches every button, Cross presses, Circle closes only our window,
  bags keep their Triangle, Cross still uses items.

## 5. Pitfalls (each cost a test round)

**Taint (the big one).** Any addon write into Blizzard's gamepad UI taints gamepad
input until `/reload`; the game then blocks `SetPreferredGamepadInteractTarget`,
jumping (`DescendStop`, `RunBinding`), `InteractUnit`, `ClearTarget`, `SpellStopCasting`
and bag item use (`UNKNOWN()`). Proven unsafe:
1. Prompted bindings on Blizzard footers (`AddPromptedBinding` + `Finalize`) - alpha1, tainted at login.
2. Registering our window: `FrameControlsManager:FrameShown`, own `CreatePromptedBindingFooter` (and by source/prior art `ShowUIPanel`) - this is why **L2/R2 into our window is not possible**.
3. **`Menu.ModifyMenu("MORE_CONTEXT_ACTIONS")`** (bag item Triangle "More" menu), even unclicked - alpha2. The operator asked for it twice; the answer is L3 + Bag locks.
4. `CreateFrame` while a gamepad panel is open (SmartNavigation's CreateFrame hook runs in our context). **Create every frame at login**, on UIParent, then `SetParent`.
5. Writing any Lua field on a Blizzard frame, or any `smartNavigation*` / `OnSmartNav*` / `buttonContext` key on ours.
6. `MailFrameTab_OnClick` from addon code (writes `MailFrame.activeSubFrame`, read by focus code): **never switch mail tabs ourselves**.
7. `SetFocus` from addon code (LedgerLink: blocked `SetPreferredGamepadInteractTarget`, client crash). The player clicks edit boxes.

Safe (verified or source-backed): own override bindings on our own frame
(`SetOverrideBindingClick(ourFrame, true, key, ourButton)`; gamepad modules don't
listen to `UPDATE_BINDINGS`); `hooksecurefunc` post-hooks; textures / font strings
on Blizzard frames kept in our own weak tables; read-only `GetActiveFrame`,
`GetCurrentButton`, `InputUtil.IsGamepadUIEnabled`; mail API calls from timers;
tooltip lines (Auctionator adds them, never blamed).

**Unsolved:** plain buttons under `SendMailFrame` should be in smart navigation's
"Send Mail" group (`Utility.FindButtonGroups` walks all descendants, no bounds
check), but the D-pad never reached them in alpha3/alpha4. Hence `Nav` + `PadKey`.
Blizzard ships `SmartNavigationDebug` (overlay of navigable buttons) if this needs
revisiting; showing it needs `/run`, which the operator shouldn't be asked to do lightly.

**Process pitfalls.**
- The operator **merges PRs silently**. Before pushing to a PR branch, gate the push
  on `gh pr view N --json state --jq .state` == OPEN (a printed check in the same
  script is not enough: PR #6 lost two commits that way, recovered in PR #7).
- zsh doesn't word-split `$(...)` in `for` loops; pass commit lists explicitly.
- Code run from `OnUpdate` / events is wrapped in `pcall` and only *logs* errors, so a
  spec passes while the code errors every tick (alpha5: `PadKey.Check` on `pairs(nil)`
  ten times a second flooded the 400-line log). Specs for such code assert the log
  has no error lines (`spec/padkey_spec.lua` `after_each`).
- The stub's `GetCenter`, `IsVisible` and parent tracking matter for `Nav` specs.
- Reports come back as one .txt with several reports (main + bank alt); read them all.
- Ask for in-game tests only when the source research says the fix is real; the
  operator wants few iterations.

## 6. Decisions

- Keyboard/mouse first; controller everywhere too; no mouse-only gestures, no
  required typing; `SetFocus` never.
- Locks are **per item ID** (all stacks, follow moves), per character; Alt+click
  (mouse), L3 in bags (controller), Bag locks page; blue quest-style glow.
- Mailbox entry: "Mailworthy" button under the mail window (both tabs); controller:
  R1 then Triangle; Mailworthy's own D-pad / Cross / Circle while its window is
  open; no L2/R2 cycling into it; no More-menu entry.
- Decision rule (PLAN): AH net = price x count x 0.95 - deposit - 30c postage vs
  vendor; deposit for the **24h listing** (operator, 2026-10-13) = floor(vendor x
  count x 5%) x 12, counted as a full cost; mail when gain >= **5s and 25%** (defaults, steppers in settings);
  disenchant compared when enabled (default on if Disenchantry is installed).
  **Without Auctionator: mail every unlocked, tradeable white (common) item**;
  greys and uncommon+ stay. Soulbound / quest items can't be mailed (don't list them).
- Bank alt picked from known characters (same realm + faction), never typed by default.
- Bank alt view: AH / DE / V tags on bag slots recomputed with the bank alt's own
  prices; tooltip shows fresh verdict + "Mailed for: ..." (recorded at send time,
  `MailworthyDB.mailed`, 30-day expiry); summary window.
- Releases: **every tag publishes to CurseForge** (project **1743661**, `CF_API_KEY`
  set, `.toc` has the ID). Operator asked for plain release tags `vX.Y.Z` going
  forward (next: **v0.2.0**); alpha tags upload as alpha files (v0.1.0-alpha5 did).
  Tag only when the operator says "tag X"; then watch the release run and report
  the CurseForge "Success!" line.
- Optional deps: `.pkgmeta` `optional-dependencies` (auctionator, disenchantry) and
  `## OptionalDeps`.

## 7. State right now

- Latest tag `v0.1.0-alpha5` (first CurseForge upload, alpha file). Its in-game
  check passed (DISCOVERY-SESSION-2.md "Results of the alpha5 run"); the one bug it
  showed (`PadKey.Check` erroring while idle) is fixed on main after it.
- Phase 1 built (`Prices`, `Valuation`, `Bags`, `/mw scan`); in-game check pending
  (DISCOVERY-SESSION-2.md "Phase 1 check").
- Still open: AH cut (needs a sale mail), disenchant prices for green items,
  ForeverMail compatibility (replaces the mailbox window).

## 8. What's left (in order)

1. ~~Process the alpha5 report~~ **Done** (all checks passed; idle `PadKey` error fixed).
2. **Phase 1 - prices + valuation** (built; finish with the in-game `/mw scan` check): `Prices.lua` (Auctionator adapter: price, age,
   exact, disenchant; vendor from `GetItemInfo`), `Valuation.lua` (pure decision rule
   incl. deposit formula, postage share, thresholds, no-Auctionator common-items rule,
   disenchant eligibility), `Bags.lua` (scan -> facts, locks, filters); `/mw scan`
   prints what would be mailed and why. Most specs live here.
3. **Phase 2 - settings:** settings window (our own frame, controller via `Nav`/`PadKey`;
   register with `Settings.RegisterCanvasLayoutCategory` too): bank alt picker
   (known characters as buttons, typed fallback with auto-complete + "not seen" warning,
   saved name history), min gain steppers (5s / 25%), disenchant checkbox (default on
   with Disenchantry, sticky once touched), listing length (2/8/24 h), minimap button
   (keyboard/mouse only). Must survive `/reload`.
4. **Phase 3 - the real mailbox window** per `media/ui-prototype.png`: To: bank alt,
   mailing list with reason chips and gains, staying list with reasons, total, Send /
   Settings / Close; Send = batches of 12 (attach, verify slot unchanged, `SendMail`,
   chain on `MAIL_SEND_SUCCESS`, stop on `MAIL_FAILED`/close/combat); never money;
   records `MailworthyDB.mailed`. Same `Nav`/`PadKey` controller model. Only on the
   Send Mail tab for sending (we can't switch tabs; on the Inbox, mouse users click
   the Send Mail tab, controller users press R1).
5. **Phase 4c - bank alt view** per `media/bank-alt-prototype.png` (tags via the
   `Border` technique, tooltip lines, summary).
6. **Phase 5 - polish:** tooltip line on all characters (optional), remove the
   self-test window / Questions / Tests / `/mw selftest`, keep switches + blocked
   recorder (quiet), update `media/curseforge-description.html` to what shipped,
   tag `v1.0.0`.
7. README "Beta unknowns" table and PLAN's "Still open" list kept current after each report.
