# Discovery session 2: one pass for every open question

Goal: one in-game session answers everything still open, so Phase 1 onward
builds on facts instead of more probe rounds. Source-backed answers are in
[FOREVER-UI-NOTES.md](FOREVER-UI-NOTES.md); this session checks that they hold at
runtime, and measures what no source can tell us.

## Why a read-only probe isn't enough this time

Three kinds of questions remain:

1. **Values the client reports** (deposits, prices, skills): read-only, `/rl probe`.
2. **Whether our hooks work without the game blocking them** (menu entry, footer
   button, our own window in smart navigation, attaching, sending, chaining): these
   only show when we *do* them. They need a small active test.
3. **What you see** (does the entry appear, do the symbols match, does Cross still
   use items): Yes/No answers you give with the controller.

So the session uses two tools:

- **LedgerLink v1.3.3**: S5-S8 as today plus S8 deposits (ledger-link PR #31). Read-only.
- **Mailworthy discovery build** (`v0.1.0-alpha1`, GitHub release in the private
  repo, not CurseForge): the real mechanisms in minimal form, plus `/mw selftest`,
  a controller-driven test window whose report collects every answer, including
  your Yes/No observations. Its saved data is account-wide, so **the report from
  the bank alt at the end holds the whole session**.

## Every open question

| # | Question | Answered by | Step |
|---|---|---|---|
| U1 | Deposit rate per kind (commodity / item) and duration | LedgerLink S8 at the AH | 2 |
| U2 | AH cut | `GetInboxInvoiceInfo` on any AH sale mail (self-test reads the inbox); default 5% if none | 4 (optional prep) |
| U3 | Disenchant price for uncommon+ gear | LedgerLink S5 with a green item in bags | 2 |
| U4 | Postage: per mail, per item, or both | self-test "Attach test" reads `GetSendMailPrice()` with 0, 1, 2 items | 5 |
| U5 | Can the addon attach items (`UseContainerItem` at the Send tab) on a button press, and **without** one (timer) | Attach test | 5 |
| U6 | Does `ClearSendMail()` put attachments back | Attach test | 5 |
| U7 | Does `SendMail` work from the addon with a "First Surname" recipient | Send test (mail 1) | 5 |
| U8 | Can mail 2 follow automatically after `MAIL_SEND_SUCCESS` (no new press) | Send test (mail 2 chained) | 5 |
| U9 | Mail events and `C_Mail.IsCommandPending` timing | Send test log | 5 |
| U10 | Delivery to own alt: instant or delayed | bank alt, step 7 | 7 |
| U11 | `Menu.ModifyMenu("MORE_CONTEXT_ACTIONS")` adds our entry on bag items only, with the right bag/slot | Lock-slot entry + its log + Yes/No | 3 |
| U12 | Using/equipping items with Cross still works after our menu entry ran (no taint) | Yes/No | 3 |
| U13 | Triangle footer action on Inbox and Send Mail: shows, fires, Square still works | footer hook log + Yes/No | 4, 5 |
| U14 | Our window in smart navigation: D-pad moves, Cross presses, Circle closes, L2/R2 cycles | self-test window + Yes/No | 4 |
| U15 | Button symbols: `labelStyle` and atlas markup match your controller | report + Yes/No | 4 |
| U16 | SavedVariables survive `/reload` and relog (beta bug) | self-test writes a marker, reads it after each | 6, 7 |
| U17 | Known-character registry: both characters listed with realm + faction | report | 7 |
| U18 | Bank alt's professions / Enchanting skill (`GetProfessions` + `GetProfessionInfo`) | report on the bank alt | 7 |
| U19 | Blocked actions anywhere in the session | blocked-action recorder in both addons | all |
| U20 | Does the minimap button work with the controller | Yes/No (LedgerLink's button today) | 4 |

Out of scope this round: ForeverMail compatibility (not installed), bag-addon overlays.

## What the discovery build contains

All of it is code Mailworthy keeps; the self-test only drives it.

- **Character registry:** on login, records name, realm, faction, class, level,
  professions.
- **Lock slot:** "Mailworthy: Lock slot" / "Unlock slot" in the bag item Triangle
  menu (filtered to bag item buttons), saved per character. Logs every callback:
  owner context, bag, slot, item, filtered or not.
- **Mail footer:** "Triangle: Mailworthy" on Inbox and Send Mail (hooked on
  `FocusGamepad`, `Finalize()`); pressing it opens the self-test window. Logs adds,
  presses and errors.
- **Self-test window:** joins smart navigation (FrameControlsManager, own footer:
  Cross select, Square run step, Triangle report, Circle close), shows controller
  symbols in its text, and holds the Yes/No questions.
- **Attach test** (Send Mail tab): picks the two cheapest tradeable, unlocked
  stacks (shown before anything happens), then:
  - attaches item 1 on your press and reads postage;
  - attaches item 2 from a timer, with no press, and reads postage again;
  - runs `ClearSendMail()` and checks both items are back in your bags.
- **Send test** (after a Yes): sends item 1 to the bank alt on your press; on
  `MAIL_SEND_SUCCESS`, attaches item 2 and sends it with no press. It logs every
  event, error and blocked action. Subjects are "Mailworthy test 1/2" and "2/2".
- **Read-only extras:**
  - inbox AH invoices (bid, buyout, deposit, cut; never the other player's name);
  - controller `labelStyle`, and whether the gamepad, menu and symbol APIs exist;
  - the SavedVariables marker.
- **Report:** `/mw selftest report` (or Triangle in the window) opens a copy box.
  The game never moves focus; you click the text.

## Before the session

- [ ] A **bank alt** on the same realm and faction (create one if needed; Enchanting is a bonus).
- [ ] On your main: **one uncommon (green) armor or weapon** in your bags, and two
  cheap tradeable stacks you don't mind mailing (e.g. Rough Stone, Linen Cloth).
  Lock anything precious with the new menu entry first; the tests never touch
  locked slots.
- [ ] Optional, for U2: list a cheap item on the AH a day before; a sale mail gives the exact cut.
- [ ] Install **LedgerLink v1.3.3** and the **Mailworthy discovery build** from GitHub releases.
- [ ] `/console scriptErrors 1` once, so Lua errors pop up.

## The session (about 20 minutes)

1. **Bank alt first.** Log in, wait 10 seconds, log out. Mailworthy records it.
2. **Main, at the AH.** Open the AH, run Auctionator's full scan, keep the AH window
   open, `/rl probe`, copy and save the report (U1, U3).
3. **Bags.** Triangle on a bag item: pick **Mailworthy: Lock slot**. Triangle on it
   again: it should say **Unlock slot**. Then Triangle somewhere else that has a
   "More" menu (spellbook or character screen): the entry should **not** be there.
   Then use or equip any bag item with Cross (U11, U12).
4. **Mailbox, Inbox tab** (open it with the controller). Look for **Triangle:
   Mailworthy** in the footer and press it: the self-test window opens. Answer its
   questions with the controller: D-pad, Cross, Circle, L2/R2 to the mail window
   and back, symbols right? Also try LedgerLink's minimap button with the
   controller (U13-U15, U20).
5. **Send Mail tab** (R1). Square still says Send? Triangle opens the self-test:
   - run **Attach test** and confirm both items came back (U4-U6);
   - run **Send test**, check the two items it names, and answer Yes (U7-U9).
6. **`/reload`**, then `/mw selftest report` once to check it still has everything (U16).
7. **Bank alt.** Log in: did both test mails arrive, and how fast? Answer in
   `/mw selftest` (U10). Then `/mw selftest report` (U16-U18).
8. **Paste back:** the `/rl probe` report from step 2 and the `/mw selftest report`
   from step 7.

If anything errors or the game blocks an action, carry on; it's all recorded.

## After the session

Answers go into PLAN.md's beta unknowns, the fee formula gets real deposit, cut
and postage numbers, and Phase 1 (prices + valuation + `/mw scan`) starts.
