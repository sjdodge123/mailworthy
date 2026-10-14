# Mailworthy plan

Mailworthy prices every item in your bags three ways (vendor, auction house
after fees, disenchant). At a mailbox, one button sends everything worth more
than its vendor price to your bank alt. The bank alt lists on the AH and
disenchants. Everything else stays in your bags for the vendor.

Target: WoW Forever (`## Interface: 16001`, classic-style client with modern
`C_` namespaces), played with a gamepad. Learnings carried over from
LedgerLink are listed at the end.

## Entry points

| Where | What it does |
|---|---|
| **Mailbox button (the main entry)** | Opening a mailbox shows a **Mailworthy** button on the mail window. Not set up yet: pressing it opens the settings panel right there. Set up: pressing it opens the preview; pressing **Send** in the preview mails. |
| **Minimap button** | Opens the settings panel anywhere. Keyboard/mouse only (the controller can't reach minimap buttons, U20). Same pattern as LedgerLink's minimap button. |
| Slash commands (`/mailworthy`, `/mw`) | `/mw` alone opens the settings window; `/mw scan`, `/mw help`. Not the main way in. |

## Input: controller and keyboard/mouse (every window)

Every feature works with **both** keyboard + mouse and a gamepad alone.
**Keyboard and mouse are the priority** (operator, 2026-10-13: "if mouse/kb
doesn't work for our addon no one will use it"); the controller is a bonus
that must never break the game.

**Never write into Blizzard's controller UI.** alpha1 added a Triangle binding to
the mail footer and registered its own window with the FrameControlsManager;
that tainted gamepad input game-wide (jumping, targeting and item use were
blocked from login). Details in [FOREVER-UI-NOTES.md](FOREVER-UI-NOTES.md).

What works (from Blizzard's source; alpha3 checks each in game):
- **Plain buttons in the focused panel's active group.** The mail window only
  navigates the active tab's group, so Mailworthy's button and window are
  children of **SendMailFrame** ("Send Mail"), created at login. D-pad + Cross
  reach them; the mouse clicks them.
- **Our own bindings** (override bindings on our own frame, re-applied if
  Blizzard replaces them, cleared on focus loss and combat; proven in game with
  Triangle, zero blocks): Triangle at a focused mail window; while the
  Mailworthy window is open, the D-pad moves Mailworthy's own highlight over
  every button, Cross presses, Circle closes; L3 locks in the bags. Blizzard's
  smart navigation didn't reach our window (alpha3/alpha4) and joining it
  taints, so we don't use it. L2/R2 window cycling into Mailworthy stays out
  (it needs FrameControlsManager registration, which taints; GatherLite reports
  the same).
- **No entries in the gamepad More menu** (taints by design, see FOREVER-UI-NOTES).
- **Button symbols** as texture markup only (`CreateAtlasMarkup`).

Per input:

| Task | Controller | Keyboard / mouse |
|---|---|---|
| Start at the mailbox | Send Mail tab (R1), then **Triangle**, or D-pad to the **Mailworthy** button + Cross | click **Mailworthy** under the mail window (either tab) |
| Preview: send / settings / close | D-pad + Cross on its buttons; Triangle closes | click |
| Lock an item | **L3** on the item in your bags, or the **Bag locks** page | **Alt+click** the bag item |
| See locked items | blue quest-style glow in your bags | same |
| Settings | the Mailworthy button (when not set up), the preview's Settings button | same, plus `/mw` and the minimap button |

Notes:
- The minimap button is keyboard/mouse only: the controller can't reach
  minimap buttons (LedgerLink's, tested 2026-10-13).
- No action needs a mouse-only gesture: no right-click, drag or hover-only
  information; what a tooltip shows also shows for the highlighted row.
- No action needs typing: names are picked from a list, numbers use steppers.
  Edit boxes exist only as an optional fallback.
- Never move keyboard focus (`SetFocus` crashed the gamepad UI in LedgerLink).
- Every piece that touches Blizzard UI has a kill switch:
  `/mw feature <name> off` + `/reload`.

## Player flow

1. **Open a mailbox.** The **Mailworthy** button is on the mail window, and a
   gamepad button is bound to it while the mailbox is open.
2. **First time:** the button opens the settings panel. Pick the bank alt from
   the characters Mailworthy has seen (or type a name). Leave "Include
   disenchant value" on. Optionally lock items. Close the settings panel
   and you're back at the mailbox.
3. **Preview.** The button opens the preview:
   - **To: <bank alt>** at the top, so a wrong recipient is obvious before
     anything is sent;
   - the **mail list**: each item with its count, reason (AH or disenchant),
     price source and gain over vendoring;
   - the **kept list** (collapsed): items staying in your bags and why (locked,
     soulbound, no price, not worth it);
   - totals: "14 items in 2 mails, about 3g 20s more than vendoring, postage 4s 20c";
   - buttons: **Send**, **Settings** (opens the settings panel on top of the
     preview; the preview recalculates when it closes), **Close**.
4. **Send.** Mail 1 of N goes to the bank alt (12 items per mail), and each
   next mail follows on `MAIL_SEND_SUCCESS` without another press.
5. **Vendor the rest.** Whatever stays in your bags is worth more at the vendor
   (or has no price data, or is locked).

Prices come from Auctionator's own scans. Mailworthy never scans the AH itself.

## Settings panel

Opened from the mailbox button (when not set up), the preview's **Settings**
button (in the discovery build: the Mailworthy window's **Settings** button), the
minimap button or `/mw`. One window (`SettingsUI.lua`, data in `Config.lua`), every
control a button, so the controller reaches all of it: while it's open (out of
combat), Mailworthy's own bindings drive it anywhere, not just at the mailbox (D-pad
moves the highlight, Cross presses, Circle closes).

**Not registered in Blizzard's options panel** (`Settings.RegisterCanvasLayoutCategory`):
that hands our frame and category tables to a panel the controller UI navigates,
the same pattern that made the More-menu entry taint gamepad input (alpha2).

| Setting | Default | Scope |
|---|---|---|
| Bank alt (mail recipient) | none; the mailbox button opens settings until it's set | account, per realm + faction |
| Include disenchant value | **on if Disenchantry is installed**, otherwise off. The default applies only until the player touches the checkbox; after that their choice persists | account |
| Minimum gain over vendor | **5s and 25%** (both must hold); two steppers in the settings window (gold/silver amount, percent), changeable any time, including from the preview's Settings button | account |
| Max price age | 7 days (Auctionator `GetAuctionAgeByItemLink`, confirmed on Forever) | account |
| AH cut | 5% | account |
| Listing length, relist factor | **24h** (duration 3), 1.0 (operator, 2026-10-13). Deposit = floor(vendor value of the stack x 5%) x 1 / 4 / 12 for 2h / 8h / 24h (measured; the game labels durations 1/2/3 "2 / 8 / 24 Hours"), so the default is **x12** | account |
| Postage | **30c per attached item** (measured 2026-10-13) | account |
| Locked items | none | **per character** |
| Minimap button | shown | account |

### Bank alt picker (no mistypes)

- The game's mail auto-complete has no "my characters" option (its flags are
  group, guild, friend, BNet, interacted-with, online), so Mailworthy keeps its
  own list.
- **Known characters:** every character that logs in with Mailworthy is
  recorded account-wide (name, realm, faction, class, level, last seen, and,
  for the enchanter check, its Enchanting skill). Only characters on the
  current realm + faction are offered, since mail can't cross either.
- **Saved names:** every name the player confirms is kept in a history list,
  so re-configuring is a pick, not a retype. The player can remove entries.
- **Pick first, type second:** the panel shows known + saved names as large
  buttons (gamepad-cursor friendly). The edit box is the fallback and
  auto-completes (prefix match, case-insensitive) from the same list.
- **Validation:** a typed name that matches no known character asks
  "Mailworthy hasn't seen this character - save anyway?" before it's stored.
- **Forever names have a space** ("First Surname", LedgerLink probe
  2026-10-05). `SendMail` takes the full two-part name (alpha2 send test, U7).
- Mailworthy never calls `SetFocus` (the LedgerLink gamepad crash); the player
  clicks the box.

## Decision rule

For each item, i.e. every stack of one item link in the bags together (count `n`,
vendor `v` per unit, AH price `a` per unit, disenchant value `d` per item), so one
item never splits into "mail 20, keep 3" (`Valuation.lua`):

```
vendor  = v * n
deposit = floor(v * n * 0.05) * 12      -- 24h listing (x1 / x4 for 2h / 8h)
ahNet   = a * n * (1 - cut) - deposit * relistFactor - postage
deNet   = d * n - postage               -- only when disenchant is enabled and the item can be disenchanted
postage = 30c x stacks                  -- 30c per attached stack, so no batching needed
best    = max(ahNet, deNet)
mail    = best - vendor >= max(minGain, vendor * minGainPct)
```

The deposit counts as a full cost (relist factor 1.0): conservative, since the
game refunds it when the item sells. Example: 20 Linen Cloth, vendor 10c, AH
40c each: vendor 2s, deposit floor(200 x 5%) x 12 = 1s 20c, ahNet = 7s 60c -
1s 20c - 30c = 6s 10c, gain 4s 10c: under the 5s minimum, so it stays.

**Without Auctionator** (no price source) there's nothing to compare, so the rule
is simple: mail every tradeable **white (common, quality 1)** item that isn't
locked; grey junk and everything uncommon or better stay in the bags
(operator, 2026-10-13). The preview says "no price data: mailing common items".

The item stays in your bags (listed in the preview's kept list with the
reason) when any of these hold:
- it's locked (item lock; there's no separate never-mail list, operator 2026-10-13);
- it's soulbound or a quest item (never listed in the window: it can't be mailed),
  or currently locked by the game;
- it's a profession tool (fishing poles, Mining Pick, Blacksmith Hammer, Skinning
  Knife, Flint and Tinder, Arclight Spanner, enchanting rods): the v0.2.0 scan put
  a Fishing Pole on the mail list;
- it has no price while Auctionator is installed (missing data for one item never
  means "mail it"; without Auctionator at all, the common-items rule above applies);
- its price is older than the age limit;
- the player is the bank alt, or no bank alt is set.

`hasNoValue` items have `vendor = 0`, so any AH price above the threshold mails them.

**Fees on Forever's AH.** Forever uses the modern auction house
(`C_AuctionHouse`): stackable goods are "commodities" priced per unit, other
items are listed one by one. Measured (LedgerLink S8, 2026-10-13): the deposit is
floor(vendor value of the stack x 5%) x 1 / 4 / 12 for 2h / 8h / 24h, the same for
commodities and items, so Mailworthy computes it from the vendor price; no AH
visit or sampling needed. The AH cut is assumed 5% until a sale mail confirms it
(`GetInboxInvoiceInfo`, U2).

Disenchant eligibility: armor or weapon (class 4 / 2), uncommon or better. A
later option limits it to items whose required Enchanting skill is at or below
the bank alt's recorded skill.

## Price sources (adapters, in priority order)

| Source | Calls | Status |
|---|---|---|
| Auctionator | `Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, link)`, `GetAuctionAgeByItemLink`, `IsAuctionDataExactByItemLink`, `GetDisenchantPriceByItemLink`, `RegisterForDBUpdate` | **confirmed** on Forever (Auctionator 340, 2026-10-13); prices themselves still to see after a scan |
| Disenchantry | none: `DisenchantryDB` holds settings only (blacklist, quality filter, statistics) | used only to switch the disenchant checkbox on by default; disenchant values come from Auctionator |
| TSM | `TSM_API.ToItemString`, `TSM_API.GetCustomPriceValue("DBMarket", s)` | optional, later; not installed in the first report |
| Vendor | `C_Item.GetItemInfo` / `GetItemInfo` 11th return | **confirmed** |

Each adapter returns copper per unit or `nil`, plus its source name. The
preview shows which source priced each line.

## Mailing

- Attach with `C_Container.UseContainerItem(bag, slot)` while the Send Mail tab
  is open (fallback: `C_Container.PickupContainerItem` + `ClickSendMailItemButton(i)`).
  Mailworthy never switches mail tabs itself (`MailFrameTab_OnClick` taints the
  controller UI): sending needs the player on the Send Mail tab.
- Before attaching, re-check that the slot still holds the previewed item
  (same link and count). Anything that changed is skipped, not guessed.
- `SendMail(bankAlt, subject, "")` with subject "Mailworthy 1/3". Never attaches
  money. The recipient is always the saved bank alt shown in the preview.
- Wait for `MAIL_SEND_SUCCESS` (next batch) or `MAIL_FAILED` (stop and say why).
  Stop on `MAIL_CLOSED` or on entering combat.
- Chaining works: mail 2 was attached and sent after `MAIL_SEND_SUCCESS` with
  no new press (alpha2, U8), so one press of **Send** sends every batch.

### Mailbox button

- The **Mailworthy** button sits under the mail window on both tabs (children of
  `InboxFrame` and `SendMailFrame`, created at login). Mouse: click it.
  Controller: on the Send Mail tab, **Triangle** (Mailworthy's own override
  binding, `PadKey.lua`); on the Inbox it shows an "R1 first" hint. Blizzard's
  smart navigation never reached these buttons (alpha3/alpha4), so the
  controller doesn't rely on it.
- On `MAIL_CLOSED`: close the preview.
- Anything the game blocks is recorded (`ADDON_ACTION_FORBIDDEN/BLOCKED`, as
  in LedgerLink) and shown by `/mw probe`.
- **ForeverMail compatibility:** ForeverMail replaces the standard mailbox
  window, so a button anchored to `MailFrame` may never show for its users.
  Anchor to whichever mail window is visible (ForeverMail's frame if present,
  found via the probe) and fall back to a free-floating button near the
  mailbox UI.

## Item locks

- A lock belongs to the **item** (its item ID), not a bag slot: it follows the
  item when you move it or sort your bags, and covers every stack of it
  (operator, 2026-10-13). Saved per character; alpha3/alpha4 slot locks are
  converted at login. A non-stackable item locks every copy of it.
- **Keyboard/mouse:** Alt+click a bag item (post-hook of `HandleModifiedItemClick`;
  Alt alone matches none of Blizzard's modified-click cases for bag items).
- **Controller:** **L3** while the bags have focus: Mailworthy's own override
  binding (only while the bags are the focused window; L3 is auto-run in the
  world, untouched), reading the selected slot from
  `SmartNavigation:GetCurrentButton()` (read-only); a hint under the bags says so.
  Also the **Bag locks** page of the Mailworthy window. Not the gamepad Triangle
  "More" menu: entries there taint controller input (alpha1/alpha2).
- **Visible:** locked items glow blue: Blizzard's quest-item border
  (`UI-Icon-QuestBorder`) desaturated and tinted blue, plus an additive copy.

## Bank alt view (operator, 2026-10-13)

On the bank alt, Mailworthy shows what each item is for, **recomputed with the
bank alt's own, fresh Auctionator data** ([media/bank-alt-prototype.png](../media/bank-alt-prototype.png)):

- **Tags on bag slots:** a small corner badge, **AH** (Auction, blue), **DE**
  (Disenchant, purple) or **V** (Vendor now, grey/gold), the same colours as the
  preview's chips. Drawn like the lock border: textures and a font string on the
  game's bag buttons, refreshed by the `UpdateItems` post-hooks and on
  `AUCTIONATOR` price updates (`Auctionator.API.v1.RegisterForDBUpdate`).
- **Tooltip lines:** the fresh verdict with today's price and its age, and the
  original reason: "Mailed for: Auction +8s 21c, Oct 13, from <main>". If the
  market moved (e.g. now better at a vendor), both are visible.
- **Summary** (the Mailworthy window when opened on the bank alt): items to list
  with the expected gain, items to disenchant, items now better at a vendor.
- **Data:** when mail is sent, Mailworthy records per item ID the reason, the gain
  at send time, the date and the sender in `MailworthyDB.mailed` (account-wide,
  capped and expired after 30 days). The verdict itself is always recomputed with
  the same decision rule on the bank alt; without Auctionator there it shows
  only the original reason.
- **Where tags show:** on the bank alt by default (any character that is someone's
  configured bank alt); a setting shows them on every character.
- **Taint:** textures / font strings on bag buttons and tooltip lines only (tooltip
  lines are what Auctionator itself adds; no blocks were ever blamed on it).
  Nothing is written into Blizzard tables. Tooltip lines use
  `TooltipDataProcessor.AddTooltipPostCall`, which Forever runs insecurely by design
  (`forceinsecure` behind an attribute delegate, `TooltipDataHandler.lua`).
- **As built:** no postage in the bank alt's verdicts (nothing is mailed from there);
  V = the vendor wins today; the Mailworthy button (Triangle) on the bank alt opens the
  summary, also `/mw summary` and the settings' "Bank alt summary" button; switches
  `bankAltTags`, `tooltipLines`; setting "AH / DE / V tags: every character".

## Release and CurseForge

How to publish, the assets (icon, description, screenshot) and the checklist for
the first public file: [CURSEFORGE.md](CURSEFORGE.md). Auctionator and
Disenchantry are optional dependencies (`.pkgmeta`, `## OptionalDeps`).

## Modules

| File | Role | Tested how |
|---|---|---|
| `Core.lua` | namespace, SavedVariables, slash commands, events | busted |
| `Blocked.lua` | records blocked actions (from LedgerLink) | busted |
| `Characters.lua` | known-character registry, saved-name history, auto-complete matching, realm/faction filter | busted (pure) |
| `Prices.lua` | price-source adapters | busted with stubbed addons |
| `Valuation.lua` | the decision rule: item facts + prices + settings -> mail-AH / mail-DE / keep + reason + gain | busted (pure, most tests live here) |
| `Bags.lua` | bag scan -> item facts, applies locks and filters | busted with stubbed `C_Container` |
| `Mailer.lua` | batch queue and state machine (attach, send, wait, next, stop); each run's timers die with it | busted with stubbed mail events |
| `MailWindow.lua` | the window at the mailbox: recipient, mail / staying lists (rows lock / unlock), totals, Send / Settings / Close | busted + in game |
| `MailButton.lua` | the Mailworthy button under the mail window (mouse; controller via Triangle, `PadKey.lua`; writes nothing into the controller UI) | busted + in game |
| `Nav.lua` / `PadKey.lua` | Mailworthy's own controller highlight and override bindings for its windows | busted + in game |
| `Locks.lua` / `Border.lua` | item locks (Alt+click, L3) and their blue glow | busted + in game |
| `Config.lua` | saved settings: bank alt per realm + faction, name history, steppers, sticky disenchant default | busted |
| `SettingsUI.lua` / `Widgets.lua` | the settings window (bank alt picker, steppers, toggles); shared window helpers | busted + in game |
| `MinimapButton.lua` | minimap button that opens settings (from LedgerLink) | busted |
| `Probe.lua` | `/mw probe`, one copyable report | busted |

SavedVariables: `MailworthyDB` (account: characters, bank alt per
realm+faction, name history, settings, blocked actions) and
`MailworthyCharDB` (locked items).

## Phases

| Phase | Delivers | Done when |
|---|---|---|
| **0 - Discovery** | LedgerLink `/rl probe` S5 (ledger-link PR #28, released in v1.3.0) and S6 (PR #29); repo, CI, packaging | the S5 + S6 report is back and its answers are in README "Beta unknowns" |
| **1 - Prices + valuation** | `Prices`, `Valuation`, `Bags`; `/mw scan` shows what would be mailed and why, with the numbers (sends nothing). **Built**, in-game check pending | `/mw scan` agrees with a hand calculation on real bags |
| **2 - Settings + characters** | settings panel, minimap button, bank alt picker with history and auto-complete, disenchant checkbox default, thresholds, fees | bank alt survives `/reload` and relog (the beta's SavedVariables bug), and every settings control works with the gamepad alone. **Built**, in-game check pending |
| **3 - Mailbox + mailing** | mailbox button (opens settings when not set up), preview with recipient + Settings button, one press sends every batch (chained). **Built**, in-game check pending | 30+ items reach the bank alt in under 3 presses, with nothing locked, bound or unpriced sent; works with ForeverMail installed |
| **4 - Item locks** | **done** in alpha5 (Alt+click, L3, Bag locks page, blue glow); no never-mail list (operator, 2026-10-13: locks cover it) | locked items never appear in the preview's mail list |
| **4c - Bank alt view** | tags on the bank alt's bag slots (recomputed with fresh prices), tooltip lines with the original reason, summary window | tags match a hand calculation with fresh prices; a changed verdict shows both. **Built** (`BankAlt.lua`), in-game check pending |
| **5 - Polish** | tooltip line ("Mailworthy: AH +2g 10s vs vendor"), release on GitHub + CurseForge (Forever flavor) | tagged release installs cleanly |

## Beta unknowns

**Settled by the first report** (LedgerLink v1.3.1, build 70338, 2026-10-13):
- Auctionator 340 runs on Forever; its API has price, age, exactness,
  disenchant and DB-update calls.
- Disenchantry exposes no price data.
- `C_Container.GetContainerItemInfo` gives `isBound`, `hasNoValue`, `isLocked`,
  `quality`, `stackCount`, `itemID`, `hyperlink`; quest items via
  `GetContainerItemQuestInfo`; sell price is `GetItemInfo`'s 11th return.
- Backpack has 20 slots; `NUM_BAG_SLOTS` is 4.
- `ATTACHMENTS_MAX_SEND` 12; `GetSendMailPrice()` 30 with nothing attached;
  `C_Mail.IsCommandPending` exists (useful for sending mails in a row).
- The AH is the modern `C_AuctionHouse` (commodities); no classic AH functions.
- Settings API: `Settings.RegisterCanvasLayoutCategory` (exists; Mailworthy doesn't use it, see "Settings panel").
- Mail auto-complete has no account-characters flag.
- Bag item buttons have no global names; combined bags exist; bags can be sorted.
- The controller UI is Blizzard's "smart navigation" (`gamepadFooter` tables,
  `…FooterinputLegend` frames, `smartNavigationFocusKey`, gamepad mixins,
  `C_Navigation`); pad buttons have no normal key bindings.
- The bag item "More" menu is a `Menu` with tag `MORE_CONTEXT_ACTIONS`
  (LedgerLink v1.3.2, 2026-10-13); Auctionator 341 returns prices (age 0, exact).

**Still open:** every remaining question, and how one session answers all of
it, is in [DISCOVERY-SESSION-2.md](DISCOVERY-SESSION-2.md) (U1-U20).

## Related addons (checked 2026-10-13)

| Addon | Overlap | Difference |
|---|---|---|
| [ForeverMail](https://www.curseforge.com/wow/addons/forevermail) (Forever, active) | rule-based auto-mailing with a queue | rules per item, not by value; no disenchant, slot locks or controller; replaces the mailbox window |
| [Larlen Mail Mule](https://www.curseforge.com/wow/addons/larlen-mail-mule) (Retail) | mails Auctionator-priced items to bank alts, queues mails | Retail only; no vendor/fee comparison, disenchant, locks or controller |
| [MuleMate](https://www.curseforge.com/wow/addons/mulemate) (Classic Era) | AH-after-cut vs 110% of vendor, prepares one mail for a bank alt | Classic Era only; player clicks Send per mail; no disenchant, locks or controller |
| [AuctionWorthy](https://www.curseforge.com/wow/addons/auctionworthy) (Classic Era) | vendor vs AH (deposit + cut) on tooltips | tooltips only, no mailing; similar name, `/worthy` |

## Carried over from LedgerLink

- One command for in-game checks (`/mw probe`), never lists of `/dump` lines.
- Every unverified API is wrapped in `pcall` / nil checks and listed in README "Beta unknowns".
- Never call `SetFocus` (gamepad crash, 2026-10-05). Record blocked actions.
- Keep the logic pure and test it with busted on LuaJIT; `luacheck .` stays clean.
- The beta's SavedVariables reload bug: test settings persistence first.
- Branches and PRs only; CI runs busted, luacheck and a packaging dry run.
