# Mailworthy

A WoW Forever addon. Open a mailbox, press the **Mailworthy** button, and
every bag item worth more on the auction house (after fees) or disenchanted
than at the vendor goes to your bank alt. The rest stays in your bags to vendor.

- **Prices** come from Auctionator (and its disenchant values); Disenchantry
  turns disenchant value on by default.
- **Preview first:** it shows the recipient, what goes and why, what stays and
  why, and a **Settings** button to fix anything before you press Send.
- **Keyboard/mouse first, controller too:** everything works with keyboard and mouse, and with a gamepad alone.
- **Lock bag slots** you never want mailed: Triangle on a bag item with a controller, or the lock grid in settings with keyboard and mouse.

**Status: Phase 0 (discovery).** The current build is a **discovery build**:
a Mailworthy button and window on the Send Mail tab (mouse; D-pad + Cross;
Triangle), slot locks (Alt+click, or the window's Bag locks grid) with a blue
border, the known-character list and a self-test (`/mw selftest`) for
[discovery session 2](docs/DISCOVERY-SESSION-2.md). It doesn't value or mail
your bags yet; the only mail it sends is the opt-in send test (two cheap
stacks to your bank alt, after a second press). The full design, phases and
open questions are in [docs/PLAN.md](docs/PLAN.md).

## Discovery build commands

```
/mw selftest          the self-test window (also: the Mailworthy button on the mail window)
/mw selftest report   the copyable report (paste it to the addon developer)
/mw locks             this character's locked slots
/mw feature <name> on|off   mailButton, padTriangle, altClickLock, slotBorder (then /reload)
```

At a mailbox: click the **Mailworthy** button under the mail window (either tab). Controller: Send Mail tab (R1), then Triangle (Y).
Lock a slot: **Alt+click** it, or the window's **Bag locks** page. Locked slots get a blue border.

## Discovery (Phase 0)

The first in-game checks run through LedgerLink's `/rl probe` (the `S5 …`
lines from v1.3.0, plus the `S6 …` lines from PR #29). With Auctionator and Disenchantry
installed and an Auctionator scan done: open a mailbox, click the **Send Mail**
tab, run `/rl probe`, and paste the report back. Its answers go into the table
below.

## Beta unknowns (check in game)

Every one of these will be wrapped defensively (pcall / nil checks). None is
confirmed on Forever yet; see "Beta unknowns to settle" in docs/PLAN.md for
the full list.

| API / behaviour | What to check | Status |
|---|---|---|
| `## Interface: 16001` | addon loads without "out of date" | confirmed for LedgerLink (build 1.60.1.70205) |
| Auctionator `API.v1` on Forever | S5 | **confirmed** (Auctionator 340; price, age, exactness, disenchant calls) |
| Real AH prices for bag items | S5 `item` lines after an Auctionator scan | open |
| Adding "Lock slot" to the bag item menu (Triangle) | alpha1 + alpha2 | **taints controller input even unclicked**: removed; Alt+click and a Bag locks grid instead |
| Our own Triangle binding at the mailbox; D-pad to buttons under SendMailFrame | alpha3 self-test | open |
| Attach / send / chain mails from addon code | alpha2 self-test | **works**, including from a timer (no button press) |
| `SendMail` to a two-part "First Surname" name | first test mail | open |
| Several mails in a row from one press | Phase 3 test | open (ForeverMail's queue suggests yes) |
| Writing into Forever's controller UI (footer bindings, FrameControlsManager) | alpha1 self-test | **never do it**: tainted gamepad input game-wide (2026-10-13) |
| Postage / AH deposit | alpha1 self-test, LedgerLink S8 | **30c per item**; deposit floor(vendor x 5%) x 1 / 4 / 12 (12h / 24h / 48h) |
| SavedVariables survive `/reload` and relog | bank alt still set after a relog | open (LedgerLink saw a reload bug on the beta) |

## Development

```bash
eval "$(luarocks --lua-version=5.1 path)"
busted --lua=luajit
luacheck .
```

Rules for changes (and for coding agents) are in [AGENTS.md](AGENTS.md).
Releases: push a `v*` tag; the BigWigs packager builds `Mailworthy-<tag>.zip`.
