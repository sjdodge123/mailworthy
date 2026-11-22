# Suggested bindings and paybacks (proposal, 2026-11-22)

Phases 1 (section 1, with the upgrades in 5b) and 2 (the meter and Mark part paid) are built; payback ideas
(section 2) are not. The operator answered
every question on 2026-11-22 (sections 5b and 6); the interactive sheet is
[media/recommendations-prototype.html](../media/recommendations-prototype.html) ->
[.png](../media/recommendations-prototype.png).

The ask (operator, 2026-11-22): "recommended bindings that show up for party members or guild
members or alts, combination of them ... Ex: I join a group with a tailor, a recommendation should
come up to send them tailoring materials. likewise when the materials arrive, a recommendation could
be made if the sender could benefit from a new bag ... Id like this to work for all professions and
encourage paybacks. these paybacks should also work with our value ledger system so that the 'debt'
is slowly cleared".

It's one loop with two halves, each on its own player's mailbox:

1. **Suggested bindings** (the sender, Aldric): crafters around him who'd use what's on his list.
2. **Payback ideas** (the crafter, Grace): what she can make that Aldric could use, sent back
   as an ordinary counted mail, so the ledger's balance goes down a bit with each one.

## 1. Suggested bindings

Today's own-crafter offer (`Routes.Offer`, QoL pass F, `MailBanners.lua`) already does this for the
account's own characters, one at a time. The proposal widens who it looks at and shows up to three.

**Who.** Your party and your alts only (operator, 2026-11-22: "Party and alts only"): a guild member
is suggested only while in your party. Each needs a crafting profession Mailworthy knows:

| Who | What says their profession | Needs their Mailworthy? |
|---|---|---|
| Your alts | `Characters.Mailable` (saved professions and ranks), as today | no |
| Party / raid member | their hello (`H2`) and skills (`S2`), already sent on PARTY / RAID at group changes | yes |
| Party / raid member in your guild | the above, else the roster's `profession1ID` / `profession2ID` (+ ranks), already read by `Routes.Skill` | no |

The sources combine into tags on the suggestion (Party, Guild, Your alt, MW). A party member who is
neither in the guild nor running Mailworthy shows as "professions unknown": the game doesn't show
another player's professions.

**Order.** Party first (party and guild above party alone), then alts. Three at a time with **More**.

**What it takes.** Counted exactly as `Routes.Offer` counts now: every scanned item through
`Routes.Divert` with the bindings in force plus the suggested one, so hard keeps, the cap, the tier
tables, the crafter's real skill and "me first" (this character's own professions keep their
materials) all apply. Never this character, the bank alt, a profession this character has, or one a
binding already names. Items that were Staying can be taken too (Rough Stone in the sheet).

**Answers.** Three buttons per suggestion (operator, 2026-11-22: both This visit and Bind):

- **While grouped** (a party member): a binding that lasts until either player leaves the group (new scope
  `"group"`, cleared on `GROUP_ROSTER_UPDATE`). For the stranger in tonight's dungeon group.
- **This visit** (an alt): a binding that lasts until `MAIL_CLOSED` (new scope `"visit"` beside
  `"account"` and `"character"`, cleared like Skip once).
- **Bind**: `Routes.Add`, an ordinary binding, as today's offer.
- **Not for <name>**: `Routes.DismissOffer`, as today (keyed by name and profession).

Either accept redraws the list: the rows move to Mailing under that player with their chip, and the
To: lines, postage and Send update before anything goes (previewed = sent, unchanged).

## 2. Payback ideas

### What the crafter can make

`TierCheck` already reads every learned recipe's reagents and output when the player opens their own
profession window (`C_TradeSkillUI.GetRecipeSchematic`: `outputItemID`, `reagentSlotSchematics`). It
would also save, per character and skill line, `crafts[outputItemID] = { recipeID, reagents = { [itemID]
= count } }`. Reagent counts (`quantityRequired`) are not read today: a Beta unknown until checked.

### What the sender could use: the needs note

A new message kind, **`N2`**, WHISPER only, sent by the sender's Mailworthy with a counted mail's values
(`M2`), to the same recipient character and under the same rules (`LedgerWire` outbox, online check):

`N2|<sender>|<level>|<class token>|<bag slots: 6,6,6,6>|<ranged: gun|bow|crossbow|thrown|wand|->|<ammo it fires: bullet|arrow|->|<main hand: blade|blunt|->|<empty slots: 4,15>`

- Only to a player this character just mailed counted materials to: the crafter who'd make something.
- A setting, "Tell crafters what I could use", **on by default** (operator, 2026-11-22), and switch `paybacks`.
- The receiver keeps the latest per sender for 30 days (`ledger[realm|faction].needs`), shows its age.
- Facts only: no stats, no item links, nothing about money. `Ammo.Fires` and `Ammo.RangedItem` already
  give the ranged facts; bag sizes come from `C_Container.GetContainerNumSlots(1..4)`.

### Matching

An idea is a recipe the crafter knows whose output passes a fixed check against the needs note
(full table in the sheet's view 3):

| Profession | Idea | Check |
|---|---|---|
| Tailoring | a bag | its slots > the sender's smallest bag's |
| Tailoring, Leatherworking, Blacksmithing | armor / cloak / shirt | an empty slot, armor type the class wears |
| Leatherworking | quiver / ammo pouch | a hunter with none (or a smaller one) |
| Blacksmithing | sharpening / weight stone | main-hand blade / blunt |
| Engineering | ammo, scope | what the ranged weapon fires / is |
| Alchemy, Cooking, First Aid | potions, food, bandages | level band; mana potions for a mana user |
| Enchanting | a wand | a wand user with an empty ranged slot; enchants are cast in person (not mailable) |
| Gatherers | materials back | the sender's own professions use them (their hello): a suggested binding back, for this visit |

Level band: required level at or under the sender's level, no more than 10 under. "Not suggested"
lines name what was left out and why ("Brown Linen Robe: Aldric wears mail").

Item facts the checks need: item class / subclass / equip slot / required level from
`GetItemInfoInstant` / `C_Item.GetItemInfo` (used already); a bag's slot count from its tooltip's
"N Slot Bag" line (`C_TooltipInfo.GetItemByID`, as `Classes` reads "Classes:"): a Beta unknown.

### Showing it (the crafter's mailbox)

- The **owed** notice (`MailBanners`) grows a meter: paid back so far, and a striped part for what
  this Send would pay. Only the crafter's own side shows, as now.
- Under it, **Payback ideas for <sender>** (up to three): the item, why ("his bags hold 6; this
  holds 8"), each one's materials with what she has, how many he'd still use, **Not for <sender>**.
- Mailworthy never crafts. Once the item is in the bags, its row gets the row pick button with
  **Me -> <sender>** (`Routes.PickStates`, as the Here / Alt pick): one click is a payback for this
  visit, with a To: line and a **PB** "back to <sender>" chip. It starts **off**, one click away
  (operator, 2026-11-22): nothing new goes out unless picked.

### The ledger

- A payback is a counted mail, so the ledger already lowers the balance by its value: no new math.
- Its subject says what it is: "Mailworthy: made for you (Woolen Bag)".
- **Value**: its auction price, as any item. A crafted item with no auction price: its materials'
  value at the crafter's prices (`source = "craft"` in the log and export). On the sender's side such
  a value is accepted only up to what the sender had sent the crafter on balance: a payback can clear
  a debt, never make one (the 3x cap needs a price of the receiver's own, which a fresh craft may lack).
  The `M2` value list carries no source today, so this needs a field (an `M3` kind, or a suffix older
  Mailworthys ignore; `comms_wire_spec` pins the choice). Decided (operator, 2026-11-22): count the
  materials, capped.
- The sender's chat line: "Grace Thorn made you a Woolen Bag (35s)". The sender never sees what the
  crafter owed.
- The ledger window lists paybacks under each balance.
- **Mark part paid** (operator, 2026-11-22), for paying in person (an enchant cast on them, a trade,
  gold in hand): an amount stepper (5s steps, up to what's owed) and a two-press button ("Sure? 20s",
  `Widgets.ConfirmButton`), in the ledger window and on the owed notice. `Ledger.MarkPaid(name, amount)`
  adds the amount to the records' `settled` instead of settling all of it, and logs `dir = "paid"`
  with that money, as Mark paid does now. **Mark paid** (no amount) still clears the rest.

## 3. Rules this would change (AGENTS.md "Safety")

Each needs the operator's word before it's built, and its critical path case:

1. **A binding for one visit, or while grouped**, is a binding: same recipients (the bound player, or the character of
   theirs with the profession), same keeps, cap and me first. Added to the binding sentence.
2. **A payback** is a new recipient kind: "the player whose counted mail this character took, for an
   item this character crafted that the payback idea named, only when the player picks it for the
   visit (shown in the preview like any recipient), never past a hard keep". Return to sender still
   wins over it.
3. **The needs note** shares level, class, bag sizes, ranged / main-hand kind and empty slots with a
   player this character just mailed. Privacy line in README.

`spec/critical_path_spec.lua` would add: a suggestion taken for this visit (mouse and controller),
declined, and gone at the next visit; a payback picked and sent (the mail and the ledger's balance);
a payback idea for an item that's locked or soulbound (no pick).

## 4. Where it would live

| Module | Change |
|---|---|
| `Routes.lua` | `Routes.Suggest(scan, bankAlt)` (grows `Routes.Offer`: candidates from alts, group, guild; returns a list), the `"visit"` scope |
| `TierCheck.lua` | save `crafts` (outputs and reagent counts) |
| `Paybacks.lua` (new) | needs note (encode / decode / store), `Paybacks.Ideas(sender, crafts, needs, bags)` (pure), the row's payback pick |
| `LedgerWire.lua` | `N2` with `M2`; the craft value's source |
| `MailBanners.lua` | the suggestions block, the meter, the ideas block |
| `MailRows.lua` | Me -> <sender> on a crafted row |
| `Ledger.lua` | `Ledger.MarkPaid(name, amount)`: a part payment (`settled` grows by the amount) |
| `LedgerUI.lua` | paybacks under each balance; the Part paid stepper and its two-press button |
| `spec/dpad_reach_spec.lua` | the new buttons in the mailbox window's walk |

Controller: every new button is a mailbox-window button on the D-pad (`Nav`); no Blizzard UI is
touched (no hook into the profession window: ideas show at the mailbox and in the ledger window).

## 5. Suggested order

1. **Built (2026-11-22):** suggested bindings for the party and your alts (no new wire format; `Routes.Offer`
   grown into `Routes.Suggestions`, While grouped / This visit / Bind, the 5b upgrades except the profession
   window reminder, which belongs to the paybacks). Short-lived bindings live in memory: a `/reload` ends them.
2. **Built (2026-11-22):** the meter on the owed notice (paid back so far, what this Send would pay) and Mark
   part paid (notice and ledger window). The "made for you" subject moves to step 3: only a payback pick is one.
3. `TierCheck` crafts, the needs note, payback ideas for Tailoring bags and Engineering ammo (the two
   clearest checks), then the rest of the table.

## 5b. Upgrades (operator, 2026-11-22; the sheet's "Try:" buttons)

All decided:

- **Fold** the suggestions block to one line ("Suggested (3) · Grace, Brann, Sadie"), remembered for the
  account. It **opens again for something new**: a suggestion not seen before is unfolded, tagged "new" and
  put on the first page; folding or answering one counts as seen. The payback ideas block folds the same way.
  (WoW's fonts may lack ▾ / ▸: the built button would say "+" / "−".)
- **Not now**: hidden for this visit (cleared at `MAIL_CLOSED`, like Skip once).
- **Off for good**: a Settings checkbox, "Suggest crafters around me", over the existing `crafterOffer` switch.
- **Its rows light up** while the mouse or the D-pad highlight is on a suggestion.
- **While grouped**: a party member's suggestion offers While grouped (until either player leaves the group,
  `GROUP_ROSTER_UPDATE`) and Bind; an alt's, who is never in the group, This visit and Bind. A new binding
  lifetime: the one-visit binding rule in section 3 becomes "for one visit, or while grouped".
- **No price on a suggestion** (operator: "I want to encourage paying back. if we have the value listed people
  might think twice"): it lists what it takes, never what that's worth or the AH gain given up.
- **The profession window reminder**: when the crafter opens their own profession window (`TierCheck`'s
  events), one chat line with the payback ideas they can make right now. Chat only, nothing written into
  Blizzard's window.
- **One suggestion** uses today's one-line offer layout, no header ("Grace Thorn is a tailor in your party.
  Send Wool Cloth x40, Linen Cloth x18?", the buttons on the right, "Not now" a link under it):
  [media/recommendations-one-vs-list.png](../media/recommendations-one-vs-list.png) (left; the full block right).
- **A crafter joins your group**: one chat line away from the mailbox, per player per session, like the Trip
  line ("Dorn Ashby (Engineering) joined your group: he could use 30 of your bars and stone at your next
  mailbox."). On the group's hello (`H2` / `S2` on PARTY) or the roster when a guild member joins; counted
  with the same `Routes.Divert` run against the bags (`Bags.Evaluate`), never printed in combat; switch
  `crafterOffer` and the Settings checkbox cover it too.

## 6. Decisions (operator, 2026-11-22)

1. A suggestion offers **Bind** and a short-lived choice: **While grouped** for a party member, **This visit** for
   an alt (5b), and Not for <name>.
2. Party and alts only: a guild member is suggested only while in the party (the roster can still
   name their profession).
3. The needs note is on by default, with a setting to turn it off.
4. The payback pick starts off, one click away.
5. A crafted payback without an auction price counts its materials, capped at what's owed.
6. Paid in person: add **Mark part paid** with an amount.
