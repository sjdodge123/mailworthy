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

**Status: Phase 1 (prices + valuation).** The current build is a **discovery build**:
a Mailworthy button and window at the mailbox (mouse; controller: Triangle,
then the D-pad / Cross / Circle), item locks (Alt+click, or L3 in the bags) with a
blue glow, the known-character list and a self-test (`/mw selftest`) for
[discovery session 2](docs/DISCOVERY-SESSION-2.md). `/mw scan` values your bags
and shows what it would mail and why, but nothing mails them yet; the only mail it sends is the opt-in send test (two cheap
stacks to your bank alt, after a second press). The full design, phases and
open questions are in [docs/PLAN.md](docs/PLAN.md).

## Discovery build commands

```
/mw selftest          the self-test window (also: the Mailworthy button on the mail window)
/mw selftest report   the copyable report (paste it to the addon developer)
/mw locks             this character's locked items
/mw scan              what Mailworthy would mail and why, with the numbers (sends nothing)
/mw feature <name> on|off   mailButton, padTriangle, padNav, padLock, altClickLock, slotBorder (then /reload)
```

At a mailbox: click the **Mailworthy** button under the mail window (either tab). Controller: Send Mail tab (R1), then Triangle (Y).
Lock an item (it stays locked wherever it moves): **Alt+click** it, or **L3** in your bags. Locked items glow blue.

## Discovery (Phase 0)

The first in-game checks run through LedgerLink's `/rl probe` (the `S5 …`
lines from v1.3.0, plus the `S6 …` lines from PR #29). With Auctionator and Disenchantry
installed and an Auctionator scan done: open a mailbox, click the **Send Mail**
tab, run `/rl probe`, and paste the report back. Its answers go into the table
below.

## Beta unknowns (check in game)

Everything unverified is wrapped defensively (pcall / nil checks). Results of
each in-game round are in [docs/DISCOVERY-SESSION-2.md](docs/DISCOVERY-SESSION-2.md).

| API / behaviour | What to check | Status |
|---|---|---|
| `## Interface: 16001` | addon loads without "out of date" | confirmed for LedgerLink (build 1.60.1.70205) |
| Auctionator `API.v1` on Forever | S5 | **confirmed** (Auctionator 340; price, age, exactness, disenchant calls) |
| Real AH prices for bag items | `/mw scan` after an Auctionator scan | open; Mailworthy assumes `GetAuctionPriceByItemLink` is per unit and `GetAuctionAgeByItemLink` is in days (Auctionator's convention; S5 saw age 0) |
| Disenchantry installed | `C_AddOns.IsAddOnLoaded("Disenchantry")` (in Forever's API docs), else `DisenchantryDB` exists | open |
| Adding "Lock slot" to the bag item menu (Triangle) | alpha1 + alpha2 | **taints controller input even unclicked**: removed; Alt+click and a Bag locks grid instead |
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
| SavedVariables survive `/reload` and relog | self-test marker | **work** (login, character switch, `/reload`) |

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
