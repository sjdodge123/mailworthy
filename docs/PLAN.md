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

## Controller support (every window)

Every window Mailworthy shows (mailbox button, preview, settings, bank alt
picker, lock grid, confirmations) is fully usable with a gamepad alone. One
shared module, `Nav.lua`, gives each window the same controls:

| Pad | Action |
|---|---|
| D-pad | move the highlight between the window's buttons (each window declares its buttons as a grid) |
| A (`PAD1`) | press the highlighted button |
| B (`PAD2`) | back / close the window (the settings panel returns to the preview if it came from there) |
| Shoulders | switch tabs or pages (settings sections, long preview lists) |
| D-pad left/right on a number | step the value down/up |

Rules:
- The highlight is drawn by Mailworthy (a border plus `LockHighlight`); it
  never moves keyboard focus (`SetFocus` crashed the gamepad UI in LedgerLink).
- The pad keys are bound with `SetOverrideBindingClick` only while a
  Mailworthy window is open and only out of combat, and are cleared when it
  closes or combat starts.
- No action needs a mouse-only gesture: no right-click, modifier-click, drag or
  hover-only information. What a tooltip shows also shows for the highlighted
  row.
- No action needs typing: names are picked from a list, numbers use steppers.
  Edit boxes exist only as an optional fallback.
- Buttons are large enough for the native gamepad cursor and are plain
  `Button`s, so ConsolePort's cursor can reach them too.
- Beta unknowns: whether override bindings on pad keys win over the native
  gamepad UI navigation while a window is open, and which pad keys are free
  (S5 lists current bindings).

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
throughout.

| Setting | Default | Scope |
|---|---|---|
| Bank alt (mail recipient) | none; the mailbox button opens settings until it's set | account, per realm + faction |
| Include disenchant value | **on if Disenchantry is installed**, otherwise off. The default applies only until the player touches the checkbox; after that their choice persists | account |
| Minimum gain over vendor | 50s and 25% (both must hold) | account |
| Max price age | 7 days (only if the price source reports age) | account |
| AH cut | 5% (faction AH) | account |
| Deposit rate, listing length, relist factor | from the probe (classic formula: a % of vendor price, scaled by duration) | account |
| Postage per item | 30c (confirmed by `GetSendMailPrice` at the mailbox) | account |
| Gamepad button for the mailbox button | a pad button the probe shows as free | account |
| Locked bag slots | none | **per character** |
| Never-mail items | none (add from the preview) | account |
| Minimap button | shown | account |

### Bank alt picker (no mistypes)

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
ahNet  = a * n * (1 - cut) - deposit(v, n, duration) * relistFactor - postage
deNet  = d * n - postage                 -- only when disenchant is enabled and the item can be disenchanted
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

Disenchant eligibility: armor or weapon (class 4 / 2), uncommon or better. A
later option limits it to items whose required Enchanting skill is at or below
the bank alt's recorded skill.

## Price sources (adapters, in priority order)

| Source | Calls | Status |
|---|---|---|
| Auctionator | `Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, link)`, `GetDisenchantPriceByItemLink`, `GetVendorPriceByItemLink` | names confirmed in Auctionator's source; Forever build to confirm via LedgerLink `/rl probe` S5 |
| Disenchantry | no documented API; S5 lists its globals and saved-table keys | read its data only if the probe shows a readable table; otherwise Auctionator's disenchant price |
| TSM | `TSM_API.ToItemString`, `TSM_API.GetCustomPriceValue("DBMarket", s)` | optional; S5 reports whether it's on Forever at all |
| Vendor | `C_Item.GetItemInfo` / `GetItemInfo` 11th return | standard |

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

### Mailbox button + controller

- On `MAIL_SHOW`: show the **Mailworthy** button anchored to the mail window,
  and (out of combat) `SetOverrideBindingClick(owner, true, padKey, "MailworthyMailButton")`
  so the chosen pad button presses it. On `MAIL_CLOSED`:
  `ClearOverrideBindings(owner)` and close the preview.
- While the preview is open the same pad button presses **Send**.
- The buttons stay reachable with the gamepad cursor too, and also with
  ConsolePort if it's installed.
- Anything the game blocks is recorded (`ADDON_ACTION_FORBIDDEN/BLOCKED`, as
  in LedgerLink) and shown by `/mw probe`.
- **ForeverMail compatibility:** ForeverMail replaces the standard mailbox
  window, so a button anchored to `MailFrame` may never show for its users.
  Anchor to whichever mail window is visible (ForeverMail's frame if present,
  found via the probe) and fall back to a free-floating button near the
  mailbox UI.

## Slot locks

- Saved per character as `lockedSlots["bag:slot"] = true`.
- **Settings grid:** one row per bag, one button per slot showing the item
  that's in it now and a lock overlay. Click (or gamepad-cursor press) to toggle.
- **Bag overlay (Phase 4b):** a small lock icon on Blizzard's own bag buttons,
  if the probe confirms their frame names. Bag addons (Bagnon, Baganator) come
  later, if at all.
- Locks belong to the slot, not the item, as requested. Sorting bags or looting
  moves items, so the never-mail item list covers "always keep this item".

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
| `MailButton.lua` | the mailbox button and gamepad override binding | busted (widget stubs) + in game |
| `Preview.lua` | recipient, mail / kept lists, totals, Send / Settings / Close | busted (rows + totals) + in game |
| `Nav.lua` | controller navigation shared by every window: button grid, highlight, pad bindings while open | busted (pure grid moves + bind/unbind) |
| `Settings.lua` | settings panel: bank alt picker, toggles, numbers, lock grid | in game |
| `Minimap.lua` | minimap button that opens settings (from LedgerLink) | busted |
| `Probe.lua` | `/mw probe`, one copyable report | busted |

SavedVariables: `MailworthyDB` (account: characters, bank alt per
realm+faction, name history, settings, never-mail list, blocked actions) and
`MailworthyCharDB` (locked slots).

## Phases

| Phase | Delivers | Done when |
|---|---|---|
| **0 - Discovery** | LedgerLink `/rl probe` S5 (ledger-link PR #28); repo, CI, packaging | the S5 report is back and its answers are in README "Beta unknowns" |
| **1 - Prices + valuation** | `Prices`, `Valuation`, `Bags`; `/mw scan` prints what would be mailed and why (sends nothing) | `/mw scan` agrees with a hand calculation on real bags |
| **2 - Settings + characters** | `Nav` controller navigation, settings panel, minimap button, bank alt picker with history and auto-complete, disenchant checkbox default, thresholds, fees | bank alt survives `/reload` and relog (the beta's SavedVariables bug), and every settings control works with the gamepad alone |
| **3 - Mailbox + mailing** | mailbox button (opens settings when not set up), preview with recipient + Settings button, one mail per press, gamepad binding, then chaining if allowed | 30+ items reach the bank alt in under 3 presses, with nothing locked, bound or unpriced sent; works with ForeverMail installed |
| **4 - Slot locks** | lock grid in settings, never-mail list from the preview, bag overlay | locked slots never appear in the preview's mail list |
| **5 - Polish** | tooltip line ("Mailworthy: AH +2g 10s vs vendor"), release on GitHub + CurseForge (Forever flavor) | tagged release installs cleanly |

## Beta unknowns to settle (the S5 probe answers most)

- Auctionator on Forever: loaded, version, does `GetAuctionPriceByItemLink` return prices; does the API have an age or freshness call?
- Disenchantry: any readable global or saved table with disenchant values?
- `C_Container.GetContainerItemInfo` fields on Forever (`isBound`, `hasNoValue`, `isLocked`, `quality`)
- `GetItemInfo` 11th return (sell price) populated for bag items
- Postage per item (`GetSendMailPrice` with the Send tab open), `ATTACHMENTS_MAX_SEND`
- AH deposit and cut rules on Forever (none are exposed as constants; confirm by posting one item by hand)
- `SendMail` with a two-part "First Surname" recipient
- Whether mails can chain without a new hardware event
- `SetOverrideBindingClick` on a pad key, which pad buttons are free (S5 lists bindings), and whether override bindings win over the native gamepad UI navigation while a window is open
- Blizzard bag button frame names (`ContainerFrame1Item1`) and combined bags, for the overlay
- Settings API: `Settings.RegisterCanvasLayoutCategory` vs `InterfaceOptions_AddCategory`
- Mail auto-complete flags (`AUTOCOMPLETE_` constants, `SendMailNameEditBox.autoCompleteParams`)
- ForeverMail's mail window frame name (for anchoring the button); add it to the S5 addon list

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
