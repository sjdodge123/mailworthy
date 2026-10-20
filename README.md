# Mailworthy

A WoW Forever addon. Open a mailbox, press the **Mailworthy** button, and
every bag item worth more on the auction house (after fees) or disenchanted
than at the vendor goes to your bank alt. The rest stays in your bags to vendor.

- **Prices** come from Auctionator (optional, recommended); Disenchantry
  (optional) switches on the disenchant comparison. Without Auctionator,
  Mailworthy mails every unlocked, tradeable white (common) item.
- **Preview first:** it shows the recipient, what goes and why, what stays and
  why, and a **Settings** button to fix anything before you press Send.
- **Keyboard/mouse first, controller too:** everything works with keyboard and mouse, and with a gamepad alone.
- **Lock items** you never want mailed: Alt+click (mouse) or L3 in your bags (controller); the lock follows the item.

## Using it

- **At a mailbox:** click **Mailworthy** under the mail window (controller: Send Mail
  tab with R1, then Triangle). The window shows who gets the mail, what goes and why,
  what stays and why, and the total gain. **Send** mails it all in one press, 12 stacks
  per mail. Pressing an item locks it, so it stays.
- **Lock items** you never want mailed: Alt+click (mouse), L3 in your bags (controller),
  or press the item in the Mailworthy window. Locked items glow blue and stay locked
  wherever they move.
- **On your bank alt:** bag slots carry **AH / B / DE / V** tags (list it, bank it for a
  later phase, disenchant it, vendor it now) recomputed with that character's own prices;
  tooltips show today's verdict and why the item was mailed; the Mailworthy button (or
  `/mw summary`) sums it up.
- **No math needed:** prices are the 3-day median of Auctionator's scans (one undercut
  can't flip a verdict), half the deposit counts (the game refunds it on a sale), a flooded
  market is valued at its floor, and the rule knows the realm's launch day: in launch week
  unpriced white trade goods are mailed, before the first raids enchanting materials, herbs
  and elementals are tagged **B** (bank them, they sell higher later), and later the
  minimum gain grows with the gold supply. Details: `docs/PLAN.md` "Decision rule".
- **After sending:** your main's bags tag what's left for the vendor with **V** (grey
  junk too) for the rest of the session. Lock an item to keep it and its V goes.
- Profession tools (fishing poles, Mining Pick, Blacksmith Hammer, Skinning Knife, ...)
  always stay. Gold is never attached.

```
/mw                   settings: bank alt, minimum gain, disenchant, listing length, tags, minimap button
/mw scan              what Mailworthy would mail and why, with the numbers (sends nothing)
/mw summary           on your bank alt: what to list, disenchant or vendor
/mw locks             this character's locked items
/mw report            a copyable report for bug reports
/mw feature <name> on|off   turn one piece off to isolate a problem (then /reload); /mw feature lists them
/mw help              all commands
```

The design, decision rule and phases are in [docs/PLAN.md](docs/PLAN.md).

## Beta unknowns (check in game)

Everything unverified is wrapped defensively (pcall / nil checks). Results of
each in-game round are in [docs/DISCOVERY-SESSION-2.md](docs/DISCOVERY-SESSION-2.md).

| API / behaviour | What to check | Status |
|---|---|---|
| `## Interface: 16001` | addon loads without "out of date" | confirmed for LedgerLink (build 1.60.1.70205) |
| Auctionator `API.v1` on Forever | S5 | **confirmed** (Auctionator 340; price, age, exactness, disenchant calls) |
| Real AH prices for bag items | `/mw scan` after an Auctionator scan | **seen** (v0.2.0 scan: Copper Ore 1s 74c, Fishing Pole 9s, all age 0); per unit still to confirm against the tooltip; Mailworthy assumes `GetAuctionPriceByItemLink` is per unit and `GetAuctionAgeByItemLink` is in days (Auctionator's convention; S5 saw age 0) |
| Auctionator's history: `Auctionator.Database:GetPriceHistory(key)` rows `{ rawDay, minSeen, maxSeen, available }` and `Auctionator.Utilities.BasicDBKeyFromLink(link)` (not its stable API; guarded, nil = last scan's price only) | `/mw scan` workings show "(3-day median; last scan ...)" and "market: N listed" | open |
| `GetServerTime()` as the launch-day anchor (`Valuation.LAUNCH_EPOCH` = Nov 4, 2026 15:00 PST) | `/mw report` "server: launch day N" | open |
| Trade-goods subclass numbers on Forever (`GetItemInfoInstant`: 7 metal, 9 herb, 10 elemental, 12 enchanting) | a Strange Dust / Bruiseweed stack shows **B** before Dec 9 | open |
| Controller in the settings window away from the mailbox (our own D-pad / Cross / Circle bindings with no Blizzard window focused) | v0.4.0 report | **works**, no blocked actions |
| Tooltip lines through `TooltipDataProcessor.AddTooltipPostCall` (item tooltips, bags and controller) | Phase 4c check | open |
| Disenchantry installed | `C_AddOns.IsAddOnLoaded("Disenchantry")` (in Forever's API docs), else `DisenchantryDB` exists | open |
| Adding "Lock slot" to the bag item menu (Triangle) | alpha1 + alpha2 | **taints controller input even unclicked**: removed; Alt+click, L3 and the Mailworthy window's rows instead |
| Our own Triangle binding at the mailbox | alpha3/alpha4 self-test | **works**, no blocked actions |
| D-pad to buttons under SendMailFrame (smart navigation) | alpha3/alpha4 self-test | **no**; Mailworthy's own D-pad / Cross / Circle bindings instead, **work** (alpha5) |
| L3 lock in the bags, item locks that follow the item, blue glow | alpha5 self-test | **work** |
| Attach / send / chain mails from addon code | alpha2 self-test | **works**, including from a timer (no button press) |
| `SendMail` to a two-part "First Surname" name | alpha2 send test | **works** |
| Several mails in a row from one press | alpha2 send test | **works** (mail 2 sent after `MAIL_SEND_SUCCESS`, no press) |
| Writing into Forever's controller UI (footer bindings, FrameControlsManager) | alpha1 self-test | **never do it**: tainted gamepad input game-wide (2026-10-13) |
| Postage / AH deposit | alpha1 self-test, LedgerLink S8 | **30c per item**; deposit floor(vendor x 5%) x 1 / 4 / 12 (2h / 8h / 24h) |
| AH cut | an AH sale mail (`GetInboxInvoiceInfo`) | open (5% assumed) |
| Disenchant prices for green items | Auctionator with a green item in bags | open |
| SavedVariables survive `/reload` and relog | self-test marker, v0.4.0 settings | **work** (login, character switch, `/reload`) |
| One-press sending from the Mailworthy window (no money, no COD) | v0.4.0 | **works** (operator, 2026-10-14) |

## Picking up the work

Start with [docs/HANDOFF.md](docs/HANDOFF.md): state, decisions, pitfalls (taint!)
and what's left. Agent rules: [AGENTS.md](AGENTS.md).

## Release

CurseForge setup, assets and the first-release checklist: [docs/CURSEFORGE.md](docs/CURSEFORGE.md).
Icon and screenshot sources are in `media/`; `tools/build-icons.sh` rebuilds them.

## Development

```bash
eval "$(luarocks --lua-version=5.1 path)"
busted --lua=luajit
luacheck .
```

Rules for changes (and for coding agents) are in [AGENTS.md](AGENTS.md).
Releases: push a `v*` tag; the BigWigs packager builds `Mailworthy-<tag>.zip`.
