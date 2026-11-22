# Suggested bindings and paybacks (proposal, 2026-11-22)

Not built. A design for the operator to pick from; the interactive sheet is
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

**Who.** Anyone `Routes.Candidates` already lists, when Mailworthy knows a crafting profession of
theirs:

| Source | What says their profession | Needs their Mailworthy? |
|---|---|---|
| Your alts | `Characters.Mailable` (saved professions and ranks), as today | no |
| Party / raid | their hello (`H2`) and skills (`S2`), already sent on PARTY / RAID at group changes | yes |
| Guild | the roster's `profession1ID` / `profession2ID` (+ ranks), already read by `Routes.Skill` | no |

The sources combine into tags on the suggestion (Party, Guild, Your alt, MW, offline). A party member
who is neither in the guild nor running Mailworthy shows as "professions unknown": the game doesn't
show another player's professions.

**Order.** Party first (they're here now; party and guild above party alone), then alts, then guild
members online, then offline. Three at a time with **More**. Open question: offline guild members at all?

**What it takes.** Counted exactly as `Routes.Offer` counts now: every scanned item through
`Routes.Divert` with the bindings in force plus the suggested one, so hard keeps, the cap, the tier
tables, the crafter's real skill and "me first" (this character's own professions keep their
materials) all apply. Never this character, the bank alt, a profession this character has, or one a
binding already names. Items that were Staying can be taken too (Rough Stone in the sheet).

**Answers.** Three buttons per suggestion:

- **This visit**: a binding that lasts until `MAIL_CLOSED` (new scope `"visit"` beside `"account"`
  and `"character"`, cleared like Skip once). For the stranger in tonight's dungeon group.
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
- A setting, "Tell crafters what I could use" (on by default? open question), and switch `paybacks`.
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
  visit, with a To: line and a **PB** "back to <sender>" chip. Open question: start on or off.

### The ledger

- A payback is a counted mail, so the ledger already lowers the balance by its value: no new math.
- Its subject says what it is: "Mailworthy: made for you (Woolen Bag)".
- **Value**: its auction price, as any item. A crafted item with no auction price: its materials'
  value at the crafter's prices (`source = "craft"` in the log and export). On the sender's side such
  a value is accepted only up to what the sender had sent the crafter on balance: a payback can clear
  a debt, never make one (the 3x cap needs a price of the receiver's own, which a fresh craft may lack).
  The `M2` value list carries no source today, so this needs a field (an `M3` kind, or a suffix older
  Mailworthys ignore; `comms_wire_spec` pins the choice). Open question: count it, or leave unpriced
  paybacks uncounted.
- The sender's chat line: "Grace Thorn made you a Woolen Bag (35s)". The sender never sees what the
  crafter owed.
- The ledger window lists paybacks under each balance; **Mark paid** stays for paying in person
  (enchants, trades).

## 3. Rules this would change (AGENTS.md "Safety")

Each needs the operator's word before it's built, and its critical path case:

1. **A binding for one visit** is a binding: same recipients (the bound player, or the character of
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
| `LedgerUI.lua` | paybacks under each balance |
| `spec/dpad_reach_spec.lua` | the new buttons in the mailbox window's walk |

Controller: every new button is a mailbox-window button on the D-pad (`Nav`); no Blizzard UI is
touched (no hook into the profession window: ideas show at the mailbox and in the ledger window).

## 5. Suggested order

1. Suggested bindings for party and guild (no new wire format; `Routes.Offer` grown, "This visit").
2. The meter on the owed notice and the "made for you" subject (ledger only).
3. `TierCheck` crafts, the needs note, payback ideas for Tailoring bags and Engineering ammo (the two
   clearest checks), then the rest of the table.

## 6. Open questions

1. Both **This visit** and **Bind** on a suggestion, or only one?
2. Suggest offline guild members, or only people online / in the party?
3. The needs note: on by default, or opt-in?
4. The payback pick: start on (lined up for the sender) or off, one click away?
5. A crafted payback without an auction price: count its materials (capped at what's owed), or leave it uncounted?
6. Enchants done in person: a "Mark part paid" with an amount, or keep Mark paid all-or-nothing?
