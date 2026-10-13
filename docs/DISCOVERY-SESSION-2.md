# Discovery session 2: one pass for every open question

Goal: one in-game session answers everything still open, so Phase 1 onward
builds on facts instead of more probe rounds. Source-backed answers are in
[FOREVER-UI-NOTES.md](FOREVER-UI-NOTES.md); this session checks that they hold at
runtime, and measures what no source can tell us.

## Results of the first run (alpha1, 2026-10-13)

| # | Result |
|---|---|
| U1 | **Settled.** Deposit = floor(vendor value of the stack x 5%) x 1 / 4 / 12 for 12h / 24h / 48h, commodities and items alike; calculable with the AH closed |
| U4 | **Settled.** Postage is a flat 30c per attached item |
| U11 | **Settled.** The Lock slot entry appears on bag items only (character slots got none), with the right bag and slot |
| U13, U14 | **Replaced.** The footer Triangle and our window's controller registration worked visually, but **tainted gamepad input from login on** (jumping, targeting, interacting and item use were blocked). Never write into Blizzard's controller UI; alpha2 uses a plain Mailworthy button on the mail window instead |
| U15 | **Settled.** `labelStyle` "Shapes" (PlayStation); atlas markup draws the right symbols |
| U16 | **Settled.** SavedVariables survived login, character switch and `/reload` |
| U17, U18 | **Settled.** Both characters recorded with realm, faction, class, level and professions (no Enchanting on either yet) |
| U20 | **Settled: no.** The controller can't reach minimap buttons; the minimap button is keyboard/mouse only |
| U5-U10 | **Open.** The attach and send tests crashed (`tonumber` on an empty Auctionator answer); fixed in alpha2 |
| U12 | **Open.** Cross stopped using items, but the footer taint was already active, so the lock menu isn't proven guilty or clean |
| U2, U3 | **Open.** No AH sale mail yet; no green item in bags |

## Results of the alpha2 run (2026-10-13)

| # | Result |
|---|---|
| U5 | **Settled.** Attaching works on a press and **from a timer** |
| U6 | **Settled.** `ClearSendMail()` puts both items back |
| U7 | **Settled.** `SendMail` to "First Surname" works |
| U8 | **Settled.** Mail 2 sent automatically after `MAIL_SEND_SUCCESS`, no press |
| U9 | **Settled.** `MAIL_SEND_SUCCESS` per mail; `IsCommandPending` false before each |
| U10 | **Settled.** Both mails were in the bank alt's inbox 89 s after sending |
| U11-U12 | **Replaced.** The More-menu entry works but taints controller input, even unclicked (blocks began within seconds of opening the menu; none on the bank alt, which never opened it). Removed in alpha3 |
| U13-U14 | **Open.** The alpha2 button and window were children of `MailFrame`, outside the mail window's navigation groups, so the D-pad couldn't reach them. alpha3 puts them under `SendMailFrame` |
| new | Keyboard/mouse locking and a visible lock marker requested; alpha3 adds Alt+click and a blue border |
| new | AH duration index 2 is labelled "8 Hours" (deposit x4); alpha3's report reads the three labels |

## Results of the alpha4 run (2026-10-13)

| Check | Result |
|---|---|
| Blocked actions | **none**, with the controller or mouse/keyboard (all logged blocks predate alpha3) |
| Triangle at the mailbox (own binding) | **works**: 9 presses, Blizzard replaced it only twice in two minutes |
| Inbox hint, bags' own Triangle | **work** |
| Alt+click lock, blue border, mouse button on the Inbox | **work** |
| D-pad to the Mailworthy button / window (smart navigation, children of SendMailFrame) | **no**, although the source says they're in the "Send Mail" group; replaced by our own navigation in alpha5 |
| Cross using items afterwards | answered "no" with no blocked action logged; recheck in alpha5 |
| AH durations | 2 / 8 / 24 hours |
| Requests | lock the item not the slot; quest-style glow; controller locking without a menu entry |

## Rerun with v0.2.0 (alpha5 changes, about 10 minutes)

1. Install `Mailworthy v0.2.0` (CurseForge or the GitHub release). Old slot locks become item locks at login.
2. **AddOns list:** is the envelope icon there?
3. **Mouse/keyboard (controller off):**
   - Alt+click an item: it **glows blue** like a quest item.
   - Sort your bags or move the item: it's **still locked**. Alt+click again unlocks it.
   - Open a mailbox and click the **Mailworthy** button.
4. **Controller (on, `/reload`):**
   - **Play a minute:** any "The game blocked" message?
   - **Bags:** select an item, press **L3**: it locks and glows; L3 again unlocks. Triangle still opens the More menu; Cross still uses items.
   - **Mailbox:** R1 to Send Mail, then Triangle opens the window with a **gold highlight** on the first button.
   - **In the window:** the D-pad moves the highlight to every button, Cross presses, Circle closes only the Mailworthy window, and Triangle toggles it.
5. Answer the Questions page, then `/mw selftest report` and paste it back.

If anything is blocked, run `/mw feature padNav off` (then `padLock`, `padTriangle`), then
`/reload` after each, and note which one made it stop.

## Rerun with alpha3 (superseded)

**Mouse and keyboard come first** (most players will use Mailworthy that way);
the controller is checked second. Everything that wrote into Blizzard's
controller UI is gone. Each remaining piece has a switch
(`/mw feature <name> off`, then `/reload`), and the log records which
switches were on at login.

**Part A: mouse and keyboard, controller off** (as a mouse-only player would play)
1. Install `Mailworthy v0.1.0-alpha3`. Turn the controller off (Options ->
   Controller -> Enable Gamepad, unticked), `/reload`.
2. **Play for a minute** (move, jump, target, loot, talk to an NPC): any "The game
   blocked" message?
3. **Bags:**
   - Alt+click a bag item: it locks (chat line) and gets a **blue border**.
   - Alt+click again: it unlocks.
   - Nothing else should happen to the item (not picked up, not used).
   - Check the border in the individual bags too, not just the combined view, if you use both.
4. **Mailbox, Inbox tab:** click the **Mailworthy** button under the mail window. The
   window opens on the right.
   - Go to **Bag locks**: hovering a slot shows the item's tooltip, and a click locks it (blue border in your bags).
   - Answer the **Questions** page with the mouse.
   - Close it with its X or Escape, and reopen it from the **Send Mail** tab's button.
5. Use or equip an item from your bags with a normal click.

**Part B: controller** (turn it back on, `/reload`)

6. **Play for a minute** again: any "The game blocked" message?
7. **Mailbox:**
   - Inbox: Triangle prints "switch to the Send Mail tab (R1)".
   - **R1**, then **Triangle**: the window opens. Triangle again closes it.
   - Reach the **Mailworthy** button under the mail window with the D-pad and press Cross.
8. **In the window, with the D-pad:** Bag locks (Cross locks a slot), Questions.
9. **L2/R2 to your bags while the mailbox is open:** Triangle on a bag item still opens
   its More menu; use or equip an item with Cross.
10. `/mw selftest report`, paste it back.

**If something is blocked:** run `/mw feature padTriangle off`, then `/reload`, and repeat the
minute of play. If it still happens, do the same with `slotBorder`, then `altClickLock`,
then `mailButton`, and note which switch made it stop.

## Rerun with alpha2 (superseded)

alpha2 removes everything that wrote into the controller UI and fixes the crash.
Each piece that touches Blizzard UI has a kill switch, so if anything is still
blocked we can isolate it without a new build.

1. **Install `Mailworthy v0.1.0-alpha2`** (GitHub release), log in on your main.
2. **Play for a minute:** move, jump, target, loot, talk to an NPC. Any "The game
   blocked ..." message? (If yes: `/mw feature lockMenu off`, `/reload`, try again,
   and note whether it stopped.)
3. **Bags:** Triangle on an item -> Lock slot, then Triangle -> Unlock slot; then use or
   equip a bag item with Cross.
4. **Mailbox:**
   - Click the **Mailworthy** button with the mouse.
   - Then reach the same button with the D-pad and press Cross. The self-test opens beside the mail window.
   - Check the D-pad reaches its buttons too.
5. **Send Mail tab:**
   - **Attach test**, then **Clear attachments**.
   - Choose the **Recipient** (your bank alt).
   - Press **Send test** twice.
6. Answer the questions in the window (with the controller or the mouse).
7. **Bank alt:** log in, check the mails arrived, answer the last two questions, then
   `/mw selftest report`, and paste it back.
8. Optional: have a green item in your bags for `/rl probe` (U3), and list something
   cheap on the AH for a sale mail (U2).

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
