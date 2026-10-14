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
| `Config.lua` | saved settings (`MailworthyDB.settings` only what the player touched, `bankAlts[realm|faction]`, `names` history); choices, auto-complete, steppers |
| `Widgets.lua` | window / button / label / legend helpers shared by all windows |
| `Mailer.lua` | sending: plan 12 stacks per mail, re-check each slot, attach, zero money/COD, `SendMail`, chain on `MAIL_SEND_SUCCESS`; stops on failure / close / combat / 10 s; a run id kills a stopped run's timers; records `MailworthyDB.mailed` (30 days) |
| `MailWindow.lua` | the window at the mailbox (`media/ui-prototype.png`): To, Mailing rows (chip + gain), Staying rows (reason), total, Send / Settings / Close; rows toggle item locks; pages of 8 / 5 |
| `BankAlt.lua` | bank alt view: verdicts with no postage (`Verdict`: ah / de / v), tags on bag buttons (a `Border` decorator), tooltip lines via `TooltipDataProcessor`, summary window (`/mw summary`, mail button on the bank alt); switches `bankAltTags`, `tooltipLines`; setting `tagsEverywhere` |
| `SettingsUI.lua` | settings window (bank alt buttons + optional typed name with "not seen" second press, steppers, disenchant, 2/8/24h, minimap toggle); controller via `PadKey` set `settings` (works away from the mailbox) |
| `MinimapButton.lua` | LedgerLink's minimap button (click: settings; drag: move); feature `minimapButton` |
| `Report.lua` | `/mw report` (one copyable report: build, controller, switches, bank alt, settings, locks, last send, blocked actions, log), the copy box `/mw scan` uses, and the AH sale-mail reader (house cut). Replaced the discovery self-test in Phase 5 |

Tests: `spec/` (busted on LuaJIT, 111 specs) with a WoW stub in
`spec/support/wow_stub.lua` (bags, mail send tab, postage, timers with delays,
override bindings, focused frame, item buttons that **error on any field write**).
`Nav` drives the most recently shown visible window (`Nav.Root`); Circle closes only that one.
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
- Settings API: `Settings.RegisterCanvasLayoutCategory` (no `InterfaceOptions_AddCategory`); not used (taint risk).
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

**Timers outliving their run.** A `C_Timer.After` callback queued by a send run still
fires after that run stops (combat, mailbox closed): the first Mailer draft would then
call `SendMail` anyway. Every Mailer timer checks the run id and `busy`.

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
  **No never-mail list** (operator, 2026-10-13: locks cover it).
- After a send, the main's bags get **V** tags (vendor items, grey junk) for the session;
  locks re-evaluate tags at once (operator, 2026-10-14). `BankAlt.Mode()` = "vendor".
- Settings: our own window, not Blizzard's options panel (registering there hands our
  tables to a controller-navigated panel; same taint pattern as the More menu).
  Valuation defaults apply until the player touches a setting.
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

- alpha5's in-game check passed (DISCOVERY-SESSION-2.md "Results of the alpha5 run");
  the one bug it showed (`PadKey.Check` erroring while idle) is fixed in v0.2.0.
- Tags so far: v0.2.0 (Phase 1), v0.3.0 (settings), v0.4.0 (sending), v0.5.0 (bank alt
  view), v0.5.1 (window refreshes after sending); every one uploaded to CurseForge.
- Confirmed in game: the `/mw scan` math (v0.2.0, by hand), settings with mouse and
  controller and after `/reload`, one-press sending with no money / COD, the window
  lists, row locks, minimap button (v0.4.0; operator 2026-10-14).
- Phase 5 (release clean-up) built: the self-test is gone, `/mw report` replaces it.
  Pending: the Phase 4c check and a v1.0 spot check on one build
  (DISCOVERY-SESSION-2.md "v1.0 check"), then tag `v1.0.0` when the operator says so.
- Still open: AH cut (needs a sale mail; the invoice reader in `Report.lua` logs it),
  disenchant prices for green items, ForeverMail compatibility (replaces the mailbox window).

## 8. What's left (in order)

1. Phases 1-5 are built (see PLAN "Phases" and the module table above).
2. **Run the v1.0 check** with the operator (DISCOVERY-SESSION-2.md "v1.0 check"); fix
   what fails in its own PR first.
3. **Tag `v1.0.0`** when the operator says so.
4. After 1.0: the AH cut from a sale mail (`[invoice]` lines in `/mw report`),
   disenchant values for green items, ForeverMail compatibility.
5. README "Beta unknowns" table and PLAN's "Still open" list kept current after each report.
