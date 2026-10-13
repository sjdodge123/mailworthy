# Mailworthy

A WoW Forever addon. Open a mailbox, press the **Mailworthy** button, and
every bag item worth more on the auction house (after fees) or disenchanted
than at the vendor goes to your bank alt. The rest stays in your bags to vendor.

- **Prices** come from Auctionator (and its disenchant values); Disenchantry
  turns disenchant value on by default.
- **Preview first:** it shows the recipient, what goes and why, what stays and
  why, and a **Settings** button to fix anything before you press Send.
- **Controller first:** every window works with a gamepad alone, using Forever's own controller UI (Triangle on the mailbox opens Mailworthy).
- **Lock bag slots** you never want mailed, straight from the game's own item menu (Triangle on a bag item).

**Status: Phase 0 (discovery).** Nothing in game yet beyond `/mw`. The full
design, phases and open questions are in [docs/PLAN.md](docs/PLAN.md).

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
| Adding "Lock slot" to the bag item menu (Triangle) | S7 lines | open |
| `SendMail` to a two-part "First Surname" name | first test mail | open |
| Several mails in a row from one press | Phase 3 test | open (ForeverMail's queue suggests yes) |
| Joining Forever's built-in controller UI (footer action on Triangle, L2/R2 window cycle) | S6 lines | open: it's Blizzard's "smart navigation" (first report); the footer tables are dumped next |
| Pad-key override bindings while a window is open (fallback) | S5 gamepad lines, Phase 2 test | open |
| SavedVariables survive `/reload` and relog | bank alt still set after a relog | open (LedgerLink saw a reload bug on the beta) |

## Development

```bash
eval "$(luarocks --lua-version=5.1 path)"
busted --lua=luajit
luacheck .
```

Rules for changes (and for coding agents) are in [AGENTS.md](AGENTS.md).
Releases: push a `v*` tag; the BigWigs packager builds `Mailworthy-<tag>.zip`.
