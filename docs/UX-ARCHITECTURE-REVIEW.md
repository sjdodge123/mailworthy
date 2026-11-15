# UX and architecture review (2026-11-15)

A pass over the whole addon (about 16,000 lines in 49 files, 911 specs) for tech debt and simplification.
Each item says what was found (file:function, so it survives line moves), why it matters and what to do.

**Status (2026-11-15): every item below is built** on branch `claude/ux-architecture-improvements-ba85c8`,
with specs (B1-B4 first, then A1 and A7 in order, then A2-A6, A8-A10 and U1-U9 on four parallel branches,
merged). Departures from the text below: U4's pick button stays for the mouse and `/mw feature padPick
off` makes it a D-pad stop again; U8 keeps "Profession materials: on my bank alt (BA)" in full (the critical
path reads it); in A2 the mail counts share `Mailer.PER_MAIL` but are not taken from `Mailer.Plan`; every
SavedVariables migration in A10 is kept. In-game checks: README "Beta unknowns" (key bindings, Square on a
row). The text below is the review as written; docs/ARCHITECTURE.md has the code as it is now. The UX proposals are drawn in
[media/simplify-prototype.html](../media/simplify-prototype.html) → [.png](../media/simplify-prototype.png).

Constraints kept throughout: AGENTS.md Safety, controller parity (D-pad reach of every view), no taint,
the critical path unchanged.

## Built on this branch

| # | What | Why | Where |
|---|---|---|---|
| B1 | **The D-pad highlight never starts on a window's X** | `Nav.TopLeft` took the highest button, which is every window's close X (`Widgets.Window`, TOPRIGHT -6,-6): the first Cross after opening Settings, Friends, the ledger, ... closed the window, and the mail window's Down-from-the-bottom wrap landed there too. Seen in the stub layout (Settings started on `MailworthySettingsFrameCloseButton`); Circle and Escape still close. The report box gets a Done button (its X was its only button). | `Nav.Candidates`, `Report.Create`; `nav_spec`, `locks_ui_spec` |
| B2 | **PadKey's window list comes from Nav** | `PadKey.Wanted` kept a hand list of the 8 free-standing windows; a new window that forgot it got no controller bindings, and no spec caught it. Now `Nav.AnyShown(mail window)`. | `PadKey.Wanted`, `Nav.AnyShown` |
| B3 | **`Util.lua`: one guarded call, one listener list** | 18 byte-identical `local function call` copies; 7 hand-rolled listener lists, 4 of which (Locks, Pins, Mailer, Ledger) dropped listener errors without a log line: the HANDOFF "pcall hides errors" pitfall. `ns.Util.Signal(area)` logs them. | `Util.lua`, 24 files; `util_spec` |
| B4 | **Solo players: Return to sender only when something is owed** (operator, 2026-11-15) | A player who only mails a bank alt saw "Return to sender" on every visit. It now shows while on, or when an item in the bags was mailed here by another player (`Returns.Due`). The row pick button (Me / Friend / Guild) was already hidden with no binding to pick; a spec now pins the whole solo window: no pick buttons, no bindings block, no Return to sender. | `Returns.Due`, `MailWindow` Refresh; `mail_window_spec`, `returns_spec` |

## UX proposals (controller-safe)

### U1. Solo mode for Settings (follows B4; high payoff, small)
Settings' "More" block always shows Friends..., Guild..., Mail ledger... and Bank alt summary... (27 buttons
in the main view, 600 px). For a player with no binding, no guild template in use and nothing in the ledger,
fold Friends / Guild / Mail ledger into one **"Friends and guild..."** button that opens the friends window
(which already has the guild line and Mail ledger...). The window loses a row; the D-pad walk loses two stops.
Shows the full set again as soon as any of them is in use. Prototype sheet, panel 2.

### U2. Settings in two views: "Mailing" and "Bags and more" (high payoff, medium)
The main view is one fixed-position column (`SettingsUI` hard-codes y from -46 to -568; adding a setting
renumbers everything under it). Split it with `SettingsUI`'s existing view mechanism (`mainWidgets` /
`pickWidgets`): **Mailing** (bank alt, gain steppers, listing length, disenchant, profession materials,
Sell what I gather, Send by tag) and **Bags and more** (tags, glow, pins, tooltips, locked items, minimap,
summary, ledger, friends/guild, report). Two tab buttons on the top row: Up from anywhere reaches them, a
walk per view goes into `dpad_reach_spec`. About 300 px each. Panel 3.

### U3. Controller-reachable "report" and "pins" (high payoff for support)
`/mw report`, `/mw pins` and `/mw pinwarning on` have no button: a controller player can't file a bug
report, can't remove a pin on an item that left the bags (no pins window like `LocksUI`), and can't turn the
pin warning back on after "Don't show this again". Proposal: a **Report...** button in Settings (Bags and
more), a **Pinned items (N)...** window built like `LocksUI` (it already has the undo row pattern), and the
pin warning as a toggle beside Pins. Panel 3.

### U4. One stop per mailbox row (medium payoff)
Each Mailing / Staying row with a pick button is two D-pad stops (row, then its pick). With 8 + 5 rows the
walk to Send doubles. Option: keep the button for the mouse, and give the controller **Square on a row**
to cycle its pick (an override binding on our own frame, PadKey set "window", like Cross). The row tooltip
already shows the pick lines through `Nav.OnSelect`. Panel 1.

### U5. Wrap and pagers everywhere (small)
Only the mail window wraps (`Nav.SetWrap`): in Settings it is about 14 Downs to Done and Down at the bottom
does nothing. Make "Down from the bottom row goes to the top-left" the default for every `Nav.Attach`
window. Put each list's pager on the list's last row (Locks already does), not on the heading line the
D-pad has to walk back up to (MailWindow Staying, Ledger, Friends).

### U6. One word for each thing (small)
- Closing: "Done" in four windows, "Close" in Vendor and the bank alt summary → "Done" everywhere.
- "..." means "opens a window": add it to the mail window's "Settings", keep it off toggles.
- "Ledger..." / "Mail ledger..."; "Summary..." / "Bank alt summary..." / title "what to sell": pick one each.
- Toggled state shows three ways (green fill, `> text <`, ": on"): keep the green fill + ": on".
- Messages still point at slash commands where a button exists (`MailWindow` "Turn them back on with /mw
  guild", `UI.MoreText` "guild rules, /mw guild").

### U7. Confirm destructive presses the same way (small)
Mark paid and "Use name" take two presses; **Remove** (a binding, beside Skip once in the mail window),
**Forget** (settings picker) and **Publish** take one. A `Widgets.ConfirmButton(label, confirm, fn)` ("Remove"
→ "Sure?" for 3 s) gives all of them the Mark paid behaviour.

### U8. Long button labels (small)
"This character keeps its profession materials: on my bank alt (BA) (First Aid 80, Tailoring 130)" on a
372 px button, "Item tooltips: full (the verdict and its numbers)": `Widgets.Fit` shrinks or cuts them.
Short label on the button ("Profession materials: on (BA)"), the explanation in its tooltip / the
controller's `Nav.OnSelect` line, as the mail window's rows already do.

### U9. A controller way into Settings away from the mailbox (research)
Away from a mailbox the only ways into Settings are `/mw` and the minimap button (mouse only). A
`Bindings.xml` entry ("Mailworthy: Settings") would let a controller player bind it in the game's own key
bindings; it touches no Blizzard frame. Needs a check against Forever's gamepad binding UI before building.

## Architecture proposals

### A1. Verdict kinds instead of reason strings (highest payoff; built: `Valuation.KINDS`, guarded by `verdict_kinds_spec`)
The `reason` text is both what the player reads and what the code branches on: `Routes.HARD_KEEPS` is keyed
by display strings (`["quest item"]`, `["item info not loaded yet"]`), `BankAlt` `QUIET_KEEPS` is a second
overlapping list, and about 30 comparisons in Routes, Bags, BankAlt, Border, Valuation test the text.
Rewording a reason silently breaks a Safety check. One dead branch already exists: `Routes.PriceKeep`
tests `reason:find("^price too old")`, which nothing produces since stale prices became a
`NO_PRICE` mail. Proposal: `Valuation` sets `verdict.kind` (an enum) and flags (`hard`, `unmailable`,
`priceKeep`, `quiet`) once, in its local `keep()`; every consumer reads those; reasons become display only.
Do it with the critical path as the gate; it touches the hard-keep enforcement.

### A2. Split `Bags.Evaluate` (180 lines) and stop rewriting `item.result`
One function fills the caller's settings table, gathers facts from 9 modules, runs Evaluate → Divert →
Choices → pick → hold → send switches, tallies totals, splits returns and sorts. Later steps mutate the
verdict (`capped`, `pastFor`, `gearBeaten`, `picked`, `held`, `keptFor`), and `own.picked = true` writes
into the pre-binding verdict. Proposal: `prepareSettings(s)`, `facts(item)`, `decide(item, ctx)` returning
`{ own, final, choices, pick }`, `tally(result)`; take mail counts from `Mailer.Plan` (the per-mail count
exists twice: `Bags.ATTACHMENTS`, `Mailer.PER_MAIL`). `Report.Build` runs a full `Bags.Evaluate` only to
read `.settings`: give it `prepareSettings`.

### A3. Layering: `Bags` → `BankAlt` → `Bags`
`Bags.ApplySendSwitches` (layer 4) calls `BankAlt.Verdict` (layer 5), and `BankAlt.Refresh` calls
`Bags.Evaluate`. `Verdict` is pure: move it to `Valuation`. Also `BankAlt` calls `MailWindow.StayReason`;
`Valuation` reads `Routes.DEFAULT_CAP`; name cleaning (`Routes.Clean` on `Config.Clean`) is imported by
Config, Ledger, Comms, Guild and Contributions: it belongs in `Characters` or `Util`.

### A4. A `Widgets.ListWindow` (and `Pager`, `Views`) for the UI (high payoff, ~250 lines)
LedgerUI, LocksUI, RoutesUI, SettingsUI, Vendor and PinWarning repeat the same skeleton: `W.Window` +
`FULLSCREEN_DIALOG` + title/sub labels, a local `at()` (5 copies), the legend at the bottom, a row pool, the
pager (`"%d/%d  >"` + `W.PagerBack` + wrap, 5 copies), an empty-state label, Done, `Show(opener)` (place
beside, page 1, refresh, raise, log), `RefreshIfShown`, and the end of every Refresh (`W.Footer`, height,
`Nav.Revalidate`). `MailWindow` already has a generic `fillList` nobody else uses. One
`W.ListWindow{ name, width, title, rows, rowHeight, makeRow, fillRow, emptyText, buttons }` returns the
frame, pager, legend, hint and Done and does paging, layout, footer, height and Revalidate. A
`W.Views(frame, { main = {...}, pick = {...} })` replaces RoutesUI's 83-line hide/show by hand and can feed
`ux_views_spec` its button lists.

### A5. Split `MailWindow.lua` (1,542 lines)
`UI.Refresh` (166 lines) does six jobs: To line, banners, rows, totals and receipt, Send state, Return
button and footer. Natural files: **MailRows** (rows, pick button, tooltips), **MailTotals** (total box,
receipt, postage text), **MailSend** (`SendState`, `SendText`, `Changed`, `Send`, `Stop`: the
Safety-critical "previewed = sent" part, worth isolating), **MailRecipients** (To lines), the bindings
block, and the tab watcher. Stale / owed / offer are each "a label and 0-2 buttons": one banner helper
shrinks Refresh and Layout together.

### A6. A registry for addon messages
`Comms.Decode` (63 lines) and `Comms.Hear` (83) are two parallel if-chains by message kind, and
`Comms.Announce` hard-codes the Stale, Version and Contributions follow-ups. Each new peer field means
editing Comms (`Hear` carries `skills` / `release` across by hand). `Comms.Register(letter, decode, hear,
{ channels, after = "hello" })` lets Ledger, Guild, Contributions, Stale and Version own their kinds.

### A7. Util, round two (mechanical, ~300 lines)
After B3, the next copies: `realm|faction` keys (7), per-realm SavedVariables stores
(`DB.x = type(DB.x) == "table" and DB.x or {}`, 11; `tableOr` twice), `GetServerTime() or time()` (11),
the `C_Timer.After` guard (9), throttles (7), the guild roster walk (C_Club, else `GetGuildRosterInfo`; 4),
the bag-slot walk (4; `Trip.scanKey` re-implements `Bags.Fingerprint`), "is this me / my character" (7, and
`Mailer.Blocker` compares raw lower-case names without `Clean`, unlike `Routes.IsMe`), name → lower-case key
(~30), item name from a link (5), and the "prune older than N days" loops (5).

### A8. Twins that could drift
- `Mailer.StillThere` and `Vendor.StillThere`: the same 7 re-checks with different wording and slot readers.
  These enforce Safety rules at the last moment; one shared `StillThere(slot, expect, rules)` keeps them
  equal.
- `Locks` / `Pins`: `OnModifiedItemClick`, `ToggleSelectedBagSlot`, `Install` differ only in modifier keys,
  log tag and switch (~45 lines each).
- Multipart reassembly in `Guild.Hear` and `Contributions.Hear` (Guild's is keyed by sender only;
  Contributions keys by guild after a Codex review; only matters if a player changes guild mid-transfer).
- The settings builders `Bags.CurrentSettings`, `BankAlt.Settings`, `Report.Build`, `Trip.Check`, and the
  report's "settings:" line, formatted twice (`Bags.Report`, `Report.Build`).

### A9. Per-visit state and cache invalidation
Nine modules reset their own state at `MAIL_SHOW` / `MAIL_CLOSED`; that is fine. Less fine: the BankAlt tag
cache is invalidated by pushes from Returns, Quests, Recipes, Comms and SettingsUI, while `Routes.Pick`,
`Routes.SkipOnce` and `Bags.SkipBankAlt` push nothing (not yet checked whether the tags read them; if they
do, the tags lag until the next bag update). One "scan inputs changed" `Util.Signal` that BankAlt,
MailWindow and Trip listen to replaces the scattered pushes and makes any such gap impossible.

### A10. Smaller items
- `Returns.Split` is documented pure but decrements its `owed` argument (the caller relies on it: make
  the sharing explicit or copy).
- `Valuation.Evaluate`: the `item.vendor == nil` check after the pin branch can't run (both pin kinds
  returned before it).
- `Routes.Active` runs a full guild roster scan per binding on every bag scan (`Routes.Skill`); cache per
  scan.
- `Ledger` (941 lines) has six concerns along its own section markers: log, balances, M2/R2 wire,
  outbox/expect queues, mail hooks, export.
- Dead or test-only: `Locks.PrintList` (no caller); spec-only `Prices.ResetTSM`, `Locks.IsLocked`,
  `Routes.Count`, `Config.IsKnown`, `Ledger.Pending`, `Stale.Peers`, `Version.ResetSession`. About 60
  `ns.X.Y` exports are used only inside their own file.
- Old migrations still run at every login: `Locks.MigrateSlotLocks` (alpha slot locks),
  `MailworthyDB.selftest = nil`, the `V2` ledger decode, `Guild.ReadSaved`'s odd caps. `critical_path`
  loads an older build's SavedVariables: check it before removing any.

## Suggested order

1. Merge B1-B4 (this branch).
2. U1 + U3 + U6 (small, visible, controller wins).
3. A1 (verdict kinds), with the critical path as the gate.
4. A4 + U2 together (the list-window helper makes the Settings split cheap).
5. A2 / A3, then A5.
6. A6, A7, A8, A9 as the code is next touched.
