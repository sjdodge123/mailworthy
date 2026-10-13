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
| **Minimap button** | Opens the settings panel anywhere. Works with the controller. Same pattern as LedgerLink's minimap button. |
| Slash commands (`/mailworthy`, `/mw`) | Backup for both, plus `/mw probe` and `/mw scan`. Not the main way in. |

## Input: controller and keyboard/mouse (every window)

Every feature works with **both** a gamepad alone and keyboard + mouse
(operator, 2026-10-13: "the addon should still support kb/mouse as well").

**Never write into Blizzard's controller UI.** alpha1 added a Triangle binding to
the mail footer and registered its own window with the FrameControlsManager;
that tainted gamepad input game-wide (jumping, targeting and item use were
blocked from login). Details in [FOREVER-UI-NOTES.md](FOREVER-UI-NOTES.md).

What works (alpha2 tests it):
- **Plain buttons inside a panel the game already focuses.** The mail window's
  **Mailworthy** button is a child `Button` of `MailFrame`: a mouse click works,
  and smart navigation reaches it with the D-pad like any mail-window button
  (Cross presses). Our preview and settings windows open as children of the
  mail window at the mailbox, for the same reason.
- **Menu entries through `Menu.ModifyMenu`** (Blizzard's extension point, run
  under `securecallfunction`): the bag item Triangle menu gets
  **Mailworthy: Lock slot**. alpha2 checks it on its own (alpha1's footer
  taint hid whether it's clean).
- **Button symbols** as texture markup only (`CreateAtlasMarkup`), drawn in our
  own text: "Cross select, Circle back".

Per input:

| Task | Controller | Keyboard / mouse |
|---|---|---|
| Start at the mailbox | D-pad to the **Mailworthy** button, Cross | click **Mailworthy** |
| Preview: send / settings / close | D-pad + Cross on its buttons | click |
| Lock a slot | Triangle on the item -> **Mailworthy: Lock slot** | the lock grid in settings (the Triangle menu doesn't exist with keyboard/mouse); a modifier-click on bag items is a later option if it can be done without taint |
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
   disenchant value" on. Optionally lock bag slots. Close the settings panel
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
4. **Send.** Mail 1 of N goes to the bank alt (12 items per mail). It chains
   to the next mail if the game allows; otherwise each press of **Send** (or
   the gamepad button) sends the next one.
5. **Vendor the rest.** Whatever stays in your bags is worth more at the vendor
   (or has no price data, or is locked).

Prices come from Auctionator's own scans. Mailworthy never scans the AH itself.

## Settings panel

Opened from the mailbox button (when not set up), the preview's **Settings**
button, the minimap button or `/mw`. One panel, controller-reachable
throughout. Registered with `Settings.RegisterCanvasLayoutCategory` (the old
`InterfaceOptions_AddCategory` is gone on Forever).

| Setting | Default | Scope |
|---|---|---|
| Bank alt (mail recipient) | none; the mailbox button opens settings until it's set | account, per realm + faction |
| Include disenchant value | **on if Disenchantry is installed**, otherwise off. The default applies only until the player touches the checkbox; after that their choice persists | account |
| Minimum gain over vendor | **5s and 25%** (both must hold); two steppers in the settings window (gold/silver amount, percent), changeable any time, including from the preview's Settings button | account |
| Max price age | 7 days (Auctionator `GetAuctionAgeByItemLink`, confirmed on Forever) | account |
| AH cut | 5% | account |
| Listing length, relist factor | 24h, 1.0 (deposit = floor(vendor x 5%) x 1 / 4 / 12 for 12h / 24h / 48h, measured) | account |
| Postage | **30c per attached item** (measured 2026-10-13) | account |
| Gamepad button for the mailbox button | a pad button the probe shows as free | account |
| Locked bag slots | none | **per character** |
| Never-mail items | none (add from the preview) | account |
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
  2026-10-05). Whether `SendMail` takes the full two-part name is a beta
  unknown that Phase 3 must check first.
- Mailworthy never calls `SetFocus` (the LedgerLink gamepad crash); the player
  clicks the box.

## Decision rule

For each bag stack (count `n`, vendor `v` per unit, AH price `a` per unit,
disenchant value `d` per item):

```
vendor = v * n
ahNet  = a * n * (1 - cut) - deposit(item, n, duration) * relistFactor - postageShare
deNet  = d * n - postageShare            -- only when disenchant is enabled and the item can be disenchanted
postageShare = postage of the mail it rides in / items in that mail
best   = max(ahNet, deNet)
mail   = best - vendor >= max(minGain, vendor * minGainPct)
```

The item stays in your bags (listed in the preview's kept list with the
reason) when any of these hold:
- it's in a locked slot, or on the never-mail list;
- it's soulbound, a quest item, or currently locked by the game;
- it has no price (missing data never means "mail it");
- its price is older than the age limit;
- the player is the bank alt, or no bank alt is set.

`hasNoValue` items have `vendor = 0`, so any AH price above the threshold mails them.

**Fees on Forever's AH.** Forever uses the modern auction house
(`C_AuctionHouse`): stackable goods are "commodities" priced per unit, other
items are listed one by one. The deposit can only be calculated while the AH
is open (`C_AuctionHouse.CalculateItemDeposit` / `CalculateCommodityDeposit`).
So whenever any character with Mailworthy (usually the bank alt) opens the AH,
Mailworthy samples deposits for items in its bags and stores the deposit as a
fraction of vendor price, per kind (item / commodity). Until a sample exists it
uses a cautious default and marks the gain as "estimated".

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
  The Send tab is opened for the player when they press **Send** in the preview.
- Before attaching, re-check that the slot still holds the previewed item
  (same link and count). Anything that changed is skipped, not guessed.
- `SendMail(bankAlt, subject, "")` with subject "Mailworthy 1/3". Never attaches
  money. The recipient is always the saved bank alt shown in the preview.
- Wait for `MAIL_SEND_SUCCESS` (next batch) or `MAIL_FAILED` (stop and say why).
  Stop on `MAIL_CLOSED` or on entering combat.
- **Beta unknown:** whether a batch can follow automatically after
  `MAIL_SEND_SUCCESS`, or each `SendMail` needs its own hardware event (a key
  or button press). ForeverMail (Forever, 2026-10) advertises a mailing queue
  that retries after errors, which suggests chaining works. Build for one
  press = one mail, then switch on chaining once the in-game test confirms it.

### Mailbox button

- On `MAIL_SHOW`: the **Mailworthy** button, a plain child `Button` of
  `MailFrame` (mouse click; the controller reaches it with the D-pad, Cross
  presses). No override bindings: binding pad keys from addon code is the kind
  of write into the controller UI that tainted gamepad input in alpha1.
- On `MAIL_CLOSED`: close the preview.
- Anything the game blocks is recorded (`ADDON_ACTION_FORBIDDEN/BLOCKED`, as
  in LedgerLink) and shown by `/mw probe`.
- **ForeverMail compatibility:** ForeverMail replaces the standard mailbox
  window, so a button anchored to `MailFrame` may never show for its users.
  Anchor to whichever mail window is visible (ForeverMail's frame if present,
  found via the probe) and fall back to a free-floating button near the
  mailbox UI.

## Slot locks

- Saved per character as `lockedSlots["bag:slot"] = true`.
- **In the game's own item menu (the main way):** on a bag item, Triangle opens
  the game's "More" menu. Mailworthy adds **Mailworthy: Lock slot** (or
  **Unlock slot** when it's locked) to it. No extra window, fully native on the
  controller. How to add the entry is a beta unknown: LedgerLink `/rl probe`
  S7 (ledger-link PR #30) names the menu and its tag. If it's a Blizzard
  `Menu` menu, `Menu.ModifyMenu(tag, …)` adds the entry; if it's the gamepad
  context-action system, we hook that instead.
- **Settings grid (overview):** one row per bag, one button per slot showing
  the item that's in it now and a lock overlay; press to toggle. Also "Unlock
  all". Works with the controller like every other window.
- **Preview:** locked items show in the kept list as "locked slot".
- **Bag overlay (Phase 4b):** a small lock icon on the game's bag buttons. On
  Forever they have no global names (`ContainerFrame1Item1` is missing) and
  combined bags exist (`ContainerFrameCombinedBags`), so the overlay walks the
  open container frames' item buttons instead. Bag addons (Bagnon, Baganator)
  come later, if at all.
- Locks belong to the slot, not the item, as requested. Bag sorting
  (`C_Container.SortBags` exists) and looting move items, so the never-mail
  item list covers "always keep this item".

## Modules

| File | Role | Tested how |
|---|---|---|
| `Core.lua` | namespace, SavedVariables, slash commands, events | busted |
| `Blocked.lua` | records blocked actions (from LedgerLink) | busted |
| `Characters.lua` | known-character registry, saved-name history, auto-complete matching, realm/faction filter | busted (pure) |
| `Prices.lua` | price-source adapters | busted with stubbed addons |
| `Valuation.lua` | the decision rule: item facts + prices + settings -> mail-AH / mail-DE / keep + reason + gain | busted (pure, most tests live here) |
| `Bags.lua` | bag scan -> item facts, applies locks and filters | busted with stubbed `C_Container` |
| `Mailer.lua` | batch queue and state machine (attach, send, wait, next, stop) | busted with stubbed mail events |
| `Preview.lua` | recipient, mail / kept lists, totals, Send / Settings / Close | busted (rows + totals) + in game |
| `MailButton.lua` | the Mailworthy button on the mail window (mouse + D-pad/Cross through smart navigation; writes nothing into the controller UI) | busted + in game |
| `Settings.lua` | settings panel: bank alt picker, toggles, numbers, lock grid | in game |
| `Minimap.lua` | minimap button that opens settings (from LedgerLink) | busted |
| `Probe.lua` | `/mw probe`, one copyable report | busted |

SavedVariables: `MailworthyDB` (account: characters, bank alt per
realm+faction, name history, settings, never-mail list, blocked actions) and
`MailworthyCharDB` (locked slots).

## Phases

| Phase | Delivers | Done when |
|---|---|---|
| **0 - Discovery** | LedgerLink `/rl probe` S5 (ledger-link PR #28, released in v1.3.0) and S6 (PR #29); repo, CI, packaging | the S5 + S6 report is back and its answers are in README "Beta unknowns" |
| **1 - Prices + valuation** | `Prices`, `Valuation`, `Bags`; `/mw scan` prints what would be mailed and why (sends nothing) | `/mw scan` agrees with a hand calculation on real bags |
| **2 - Settings + characters** | settings panel, minimap button, bank alt picker with history and auto-complete, disenchant checkbox default, thresholds, fees | bank alt survives `/reload` and relog (the beta's SavedVariables bug), and every settings control works with the gamepad alone |
| **3 - Mailbox + mailing** | mailbox button (opens settings when not set up), preview with recipient + Settings button, one mail per press, gamepad binding, then chaining if allowed | 30+ items reach the bank alt in under 3 presses, with nothing locked, bound or unpriced sent; works with ForeverMail installed |
| **4 - Slot locks** | lock grid in settings, never-mail list from the preview, bag overlay | locked slots never appear in the preview's mail list |
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
- Settings API: `Settings.RegisterCanvasLayoutCategory`.
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
