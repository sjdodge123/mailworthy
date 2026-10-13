# Mailworthy

A WoW Forever addon. Open a mailbox, press the **Mailworthy** button, and
every bag item worth more on the auction house (after fees) or disenchanted
than at the vendor goes to your bank alt. The rest stays in your bags to vendor.

- **Prices** come from Auctionator (and its disenchant values); Disenchantry
  turns disenchant value on by default.
- **Preview first:** it shows the recipient, what goes and why, what stays and
  why, and a **Settings** button to fix anything before you press Send.
- **Controller and keyboard/mouse:** every window works with a gamepad alone or with keyboard and mouse.
- **Lock bag slots** you never want mailed: Triangle on a bag item with a controller, or the lock grid in settings with keyboard and mouse.

**Status: Phase 0 (discovery).** The current build is a **discovery build**:
the Lock-slot menu entry, a Mailworthy button on the mail window (mouse, or
D-pad + Cross), the known-character list and a self-test (`/mw selftest`) for
[discovery session 2](docs/DISCOVERY-SESSION-2.md). It doesn't value or mail
your bags yet; the only mail it sends is the opt-in send test (two cheap
stacks to your bank alt, after a second press). The full design, phases and
open questions are in [docs/PLAN.md](docs/PLAN.md).

## Discovery build commands

```
/mw selftest          the self-test window (also: the Mailworthy button on the mail window)
/mw selftest report   the copyable report (paste it to the addon developer)
/mw locks             this character's locked slots
/mw feature <name> on|off   switch lockMenu or mailButton off to isolate a problem (then /reload)
```

Triangle (Y) on a bag item: **Mailworthy: Lock slot / Unlock slot**.

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
| Adding "Lock slot" to the bag item menu (Triangle) | alpha1 self-test | **works** (bag items only); alpha2 checks it causes no blocked actions on its own |
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
