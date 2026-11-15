# Mailworthy architecture

A navigational index of the addon's code: what each module is for, how data moves through
it, and where to look before changing something. It names functions and files and does not
copy the code. Line numbers are left out on purpose: search for the function name.

- **Why** things are the way they are (decisions, pitfalls, state, what's left):
  [HANDOFF.md](HANDOFF.md). Its section 3 is the long per-module history; this file is the
  short map.
- **Design** (player flow, decision rule, bindings, guild template, tiers, ledger):
  [PLAN.md](PLAN.md).
- **Blizzard source findings and taint rules**: [FOREVER-UI-NOTES.md](FOREVER-UI-NOTES.md).
- **Rules** (Safety, controller, critical path, working rules): [AGENTS.md](../AGENTS.md).

Keep this file current: `AGENTS.md` ("Working rules") says when a PR has to update it.

## 1. Shape of the addon

- One addon folder, `Mailworthy/`. Every file starts with `local _, ns = ...` and puts its
  module on the shared namespace as `ns.<Module>` (`ns.Bags`, `ns.Routes`, ...). Window
  modules often alias their table as a local `UI`.
- **Events**: modules never register events themselves (one exception: `Blocked.lua`). They
  call `ns.On(event, fn)` (Core), which registers the event on one frame (`ns.eventFrame`)
  and runs every handler under `pcall`; errors go to the log.
- **Module-to-module listeners** (not game events): `Locks.OnChanged`, `Pins.OnChanged`,
  `Mailer.OnChanged`, `Mailer.OnSent`, `Ledger.OnChanged`, `Comms.OnMarksChanged`,
  `Version.OnChanged`, each a `ns.Util.Signal` (a listener's error is logged, never dropped);
  and Border's draw pipeline, `Border.AddDecorator` / `Border.AddRefresher`.
- **Shared helpers**: `ns.Util.Call` (a guarded call returning every result; files take it as a
  local `call`) and `ns.Util.Signal(area)` (`Util.lua`, loaded after `Log`).
- **Frames** are all created at `PLAYER_LOGIN` (or `ADDON_LOADED`), on `UIParent` and then
  `SetParent`, never while a gamepad panel is open (AGENTS.md "Never write into Blizzard's
  controller UI").
- **Kill switches**: every piece that touches Blizzard UI checks `ns.Features.On(name)`
  (section 8), toggled with `/mw feature <name> on|off` + `/reload`.
- **Pure functions** (no WoW API calls, tested directly) hold most of the rules:
  `Valuation`, `Tiers`, `Disenchant`, and the pure helpers in `Routes`, `Returns`, `Ledger`,
  `Mailer.Plan`, `MailWindow`'s `*Text` functions.
- **Tests**: `spec/*_spec.lua`, busted on LuaJIT, against the WoW stub
  `spec/support/wow_stub.lua`; `spec/support/load_addon.lua` loads every file the `.toc` lists, in order.

## 2. Load order

From `Mailworthy/Mailworthy.toc` (`## Interface: 16001`; `SavedVariables: MailworthyDB`,
`SavedVariablesPerCharacter: MailworthyCharDB`; optional deps: Auctionator,
TradeSkillMaster, DisenchantValue, Disenchantry, Baganator, Bagnon, ArkInventory,
BetterBags). Files load top to bottom; a module may call another one at run time whatever
the order, but anything run at file load (constants built from other modules,
`Border.AddDecorator`) needs the earlier file.

| # | Layer | Files |
|---|---|---|
| 1 | Foundation | `Core`, `Log`, `Util`, `Blocked`, `Characters`, `Gamepad`, `Locks`, `Palette`, `Pins`, `Border` |
| 2 | Pricing and rules | `Prices`, `Disenchant`, `Tiers`, `TierData` (fills `ns.Tiers`), `TierCheck`, `Quests`, `Conjured`, `Recipes`, `Ammo`, `Valuation`, `Config`, `Classes` |
| 3 | Bindings and peers | `Routes`, `Comms`, `Guild`, `Stale`, `Version` |
| 4 | Scan, send, records | `Bags`, `Mailer`, `Ledger`, `Contributions`, `Returns`, `Trip` |
| 5 | Windows and input | `Widgets`, `MailButton`, `Nav`, `PadKey`, `SettingsUI`, `RoutesUI`, `LedgerUI`, `LocksUI`, `PinWarning`, `MinimapButton`, `MailWindow`, `BankAlt`, `Vendor` |
| 6 | Integrations, report | `BagAddons`, `AuctionatorTags`, `Report` |

## 3. Module map

One row per file, in load order. "API" lists the entry points other modules use, not every
function. Specs: the module's own spec first; `critical_path` = `spec/critical_path_spec.lua`.

| File | Purpose | Main API | Specs |
|---|---|---|---|
| `Core.lua` | Namespace, SavedVariables init, event dispatch, feature switches, `/mw` | `ns.On`, `ns.Fire`, `ns.Init`, `ns.Print`, `ns.Features.On/Describe/DEFAULTS`, `ns.HandleSlash` | core |
| `Log.lua` | Account-wide dated diagnostics log (300 lines) | `Log.Add(area, fmt, ...)`, `Log.Lines`, `Log.Trim` (pure) | core |
| `Util.lua` | Helpers every module shares: a guarded call, listener lists | `Util.Call`, `Util.Signal(area)` (`Add`, `Fire`, `Count`) | util |
| `Blocked.lua` | Records `ADDON_ACTION_FORBIDDEN/BLOCKED` blamed on Mailworthy with the last command | `Blocked.OnEvent`, `Blocked.Lines` | blocked, report |
| `Characters.lua` | Known characters of the account; who this one can mail | `ns.PlayerName`, `Characters.Current/Record/Mailable/Key/Professions` | characters |
| `Gamepad.lua` | Read-only controller helpers: button names, glyphs, API presence | `Gamepad.Name/NameFor/Fill/Glyph/LabelStyle/Presence` | gamepad |
| `Locks.lua` | Per-character item locks (Alt+click, L3, LocksUI) | `Locks.IsItemLocked`, `ToggleItem`, `Toggle`, `List`, `BagCounts`, `OnChanged`, `ToggleSelectedBagSlot`, `MigrateSlotLocks` | locks, locks_ui |
| `Palette.lua` | One colour and label per destination (AH, DE, V, BA, BH, F, R, ...) | entries, `ORDER`, `LEGEND`, `Hex`, `Letters` | border, bank_alt |
| `Pins.lua` | Account-wide pins (bank / vendor) and the per-character BA/BH mode | `Pins.Effective`, `Set`, `Toggle`, `SetMode`, `Mode`, `Kind`, `OnChanged`, `ToggleSelectedBagSlot` | pins, pin_mode |
| `Border.lua` | Lock/pin glow on item buttons; the shared per-button draw pipeline; glow tooltip line | `Border.RefreshButton`, `DrawBagSlot`, `AddDecorator`, `AddRefresher`, `RefreshAll`, `Clear`, `Install` | border |
| `Prices.lua` | Price-source adapter: Auctionator first, else TSM; disenchant value; vendor price | `Prices.Source`, `Lookup`, `LookupTSM`, `MaterialPrice`, `Vendor`, `DisenchantValueFor`, `ClassID`, `History` | prices |
| `Disenchant.lua` | Era disenchant tables and expected value (port of Disenchantry 1.1.5) | `Disenchant.Outcomes`, `ExpectedValue` (pure), `Value` | disenchant |
| `Tiers.lua` | Material tiers: the skill at which a profession is done with a material | `Tiers.Threshold`, `Outgrown`, `OutgrownNames`, `PastText`, `Step`, `WorthConverting` (pure) | tiers |
| `TierData.lua` | **Generated** tier tables (`tools/tiers/build.py` from `tools/tiers/data.py`; edit those) | `Tiers.DONE`, `Tiers.KEEP`, `Tiers.CONVERT` | tiers (indirect) |
| `TierCheck.lua` | Reads the player's own profession window; materials past the table still used | `TierCheck.Scan`, `Annotate`, `Findings`, `Latest`, `ReportLines` | tier_check |
| `Quests.lua` | Items an active quest's objective names | `Quests.For(link)`, `Update`, `Invalidate` | quests |
| `Conjured.lua` | Conjured items (ID list, else the tooltip's "Conjured Item" line) | `Conjured.Is`, `Known` (pure), `How` | conjured |
| `Recipes.lua` | Recipes this character already knows (the tooltip's "Already known" line, `ITEM_SPELL_KNOWN`); per visit | `Recipes.Known`, `IsKnownLine` (pure), `Forget`, `ReportLines` | recipes |
| `Ammo.lua` | The ammo the equipped ranged weapon fires (bow / crossbow: arrows, gun: bullets): a hard keep, reason `"ammo"` | `Ammo.Is(item or link, fires)`, `Equipped`, `Fires`, `Matches` (pure), `RangedItem`, `ReportLines`, `REASON` | ammo, critical_path |
| `Valuation.lua` | **The decision rule** (pure): mail or keep, and the route, for one item; **verdict kinds** (`KINDS`: each keep's `kind`, display text and flags `hard` / `unmailable` / `priceKeep` / `quiet`; code reads the kind, never the reason text: `verdict_kinds_spec`) | `Valuation.Evaluate`, `KINDS`, `K`, `Keep`, `Is`, `Flag`, `HardKeep`, `Unpriced`, `Unmailable`, `NeededBy`, `ProfessionKeep`, `DisenchantsHere`, `Settings`, `DEFAULTS`, `STAPLES`, `SEND*`, `Money` | valuation |
| `Config.lua` | Saved settings over `Valuation.DEFAULTS`; bank alt per realm/faction; flags | `Config.Values/Get/Set/Step/Flag`, `Tooltips` / `CycleTooltips` (item tooltips: full / short / off), `BankAlt`, `SetBankAlt`, `SetBankAltHere`, `IsBankAltHere`, `Choices` | config |
| `Classes.lua` | Class-only items from the tooltip "Classes:" line | `Classes.Of`, `Mine`, `ForOther` (pure), `Token`, `Name` | classes |
| `Routes.lua` | **Bindings**: a profession's materials (or a class's items) to a player; skip once; row picks | `Routes.Divert`, `Divertible`, `Matches`, `Before`, `Force`, `Choices`, `Pick/Picked/ClearPicks`, `Active`, `List`, `Add/Remove`, `Crafter`, `Recipient`, `ClassPriced`, `PriceKeep`, `GearBeaten` | routes |
| `Comms.lua` | Addon messages between Mailworthys (prefix `Mailworthy`); peers; the name mark | `Comms.Announce`, `Ask`, `Hear` (a skills or hello message marks the bag tags stale: `BankAlt.Invalidate`), `SendGuild`, `Whisper`, `Peers/Peer`, `Skill`, `Mark`, `OnMarksChanged` | peer_mark, routes |
| `Guild.lua` | **Guild template**: GM/officer rules, shared on GUILD, opted into per player | `Guild.Rules`, `Offer`, `Hear`, `Broadcast`, `Ask`, `CanPublish`, `InUse/SetUse/ToggleUse`, `Draft*`, `Publish` | guild |
| `Stale.lua` | Stale-price nudge; peers' scan days (display only) | `Stale.OwnAge`, `Nudge` (pure), `Hear`, `Message`, `Current` | stale |
| `Version.lua` | "Your Mailworthy is out of date" from peers' release versions | `Version.Parse/Newer` (pure), `Hear`, `Message`, `Outdated`, `OnChanged` | version |
| `Bags.lua` | **The scan**: bag slots into items, each valued; the preview list | `Bags.Evaluate`, `Slots`, `Fingerprint` / `FingerprintOf` (pure; bag contents without ammo stack sizes), `Group`, `CurrentSettings`, `ApplySendSwitches`, `SkipBankAlt/BankAltSkipped`, `HoldReason`, `ProfessionKeep`, `Scan` | bags, send_switches |
| `Mailer.lua` | **The send**: plan 12 stacks per mail, re-check, attach, send, chain | `Mailer.Start`, `Plan` (pure), `Blocker`, `Short` (the list's postage + `RESERVE` against `GetMoney`), `Affords` (pure: postage + the 5s `RESERVE`), `ReserveText`, `StillThere` (ammo of a weapon equipped since the preview stays; so does a stack already attached), `Stop`, `RequestStop`, `Busy`, `Status`, `OnChanged`, `OnSent` | mailer |
| `Ledger.lua` | Mail ledger: every mail sent and taken, values, balances; M2/R2 value exchange | `Ledger.RecordSent`, `Add`, `Debts`, `Net`, `MarkPaid`, `Store`, `Install`, `Hear*`, `ExportText` | ledger |
| `Contributions.lua` | What this account mailed because of guild rules; `MailworthyAPI.v1.GetGuildExport` | `Contributions.Tag`, `Count`, `Hear`, `Share`, `Export`, `Build` | contributions |
| `Returns.lua` | Return to sender: per-visit toggle (its button shows only while on or when `Due`); what each sender is owed from the ledger | `Returns.On/Toggle/Available`, `Owed` (pure), `Split` (pure), `Due` (pure), `Result`, `Current` | returns |
| `Trip.lua` | "Worth a mailbox trip" nudge away from a mailbox | `Trip.Check`, `Summary`, `TooltipText` | trip |
| `Widgets.lua` | Shared window/button/label/footer/pager builders | `Widgets.Window`, `Button`, `SetToggled`, `Label`, `Footer`, `PagerBack`, `PlaceBeside` | widgets |
| `MailButton.lua` | "Mailworthy" button under the mail window (both tabs); `Activate` entry point | `MailButton.Activate`, `GamepadUI`, `Refresh` | mailbutton |
| `Nav.lua` | Mailworthy's own D-pad navigation and highlight over its windows (a window's own X is never a candidate: Circle closes it) | `Nav.Attach`, `Move`, `Press`, `CloseTop`, `Follow`, `Root`, `Pick` (pure), `AnyShown(except)` | nav, dpad_reach |
| `PadKey.lua` | Mailworthy's own override bindings (sets: mail, window, bags, merchant, settings: every `Nav.Attach` window but the mailbox one, `Nav.AnyShown`) | `PadKey.Wanted`, `Check`, `SETS`, `KEY_FEATURE` | padkey |
| `SettingsUI.lua` | Settings window (views: main, pick = bank alt picker) | `SettingsUI.Show/Toggle/Refresh`, `Choose`, `UseTyped`, `ToggleHere`, `TooltipsText` (the Item tooltips button, `MailworthySettingsTooltips`) | settings_ui, ux_views |
| `RoutesUI.lua` | Friends window: bindings list, add (two steps), guild template view | `RoutesUI.Show`, `ShowGuild`, `Pick`, `Bind`, `Reload` | routes, guild, ux_views |
| `LedgerUI.lua` | Ledger window: debts, Mark paid (two presses), Export log | `LedgerUI.Show`, `Export` | ledger |
| `LocksUI.lua` | Locked items window with Unlock / Lock | `LocksUI.Show`, `Refresh` | locks_ui |
| `PinWarning.lua` | One-time warning when a BA pin takes an item a profession uses | `PinWarning.Check`, `Show` | pin_mode |
| `MinimapButton.lua` | Minimap button (Settings; Trip line in the tooltip) | `MinimapButton.Create`, `Refresh` | trip |
| `MailWindow.lua` | **The Mailworthy window** at the mailbox: To, bindings, Mailing, Staying, total, Send | `MailWindow.Show/Toggle/Refresh/RefreshIfShown`, `Send`, `Changed`, `Recipients`, `SendText`, `Result`, `Frame` | mail_window, ux_views |
| `BankAlt.lua` | Bag tag verdicts and their decorator, tooltip lines, legend, summary window | `BankAlt.Verdict`, `Tag`, `Decorate`, `Refresh/Redraw/Invalidate`, `Waiting`, `TooltipLines(item, record, settings, mode)`, `ReportLines`, `LegendText`, `TagShown`, `AnchorTag`, `ShowWindow` | bank_alt |
| `Vendor.lua` | Merchant-side seller for items tagged V (12 a press, re-checked) | `Vendor.Toggle`, `Stacks`, `StillThere` (never the ranged weapon's ammo), `Sell` | vendor |
| `BagAddons.lua` | Tags + glow in Baganator, Bagnon, ArkInventory, BetterBags | `BagAddons.Install*`, `On`, `RefreshAll`, `ReportLines` | bag_addons |
| `AuctionatorTags.lua` | Tags on Auctionator's Selling tab item buttons | `AuctionatorTags.Install`, `OnSetItemInfo`, `RefreshAll` | auctionator_tags |
| `Report.lua` | `/mw report`; the shared copy box (`/mw scan`, ledger export); AH invoice cut | `Report.Open`, `Build`, `Show(text, heading)` | report |

## 4. Data flows

### 4.1 A mailbox visit (preview, then send)

1. **Open.** `MAIL_SHOW` resets per-visit state in several modules (`Mailer`, `Conjured.Forget`, `Recipes.Forget`,
   `Report`, `Trip`, `Stale`, `Comms`). `MailWindow`'s tab watcher (`MailworthyTabWatcher`,
   `OnUpdate` every 0.2 s: `FollowTab`, `AutoOpen`, `CheckTab`, `RecheckEmpty`) opens the
   window when the Send Mail tab appears (switch `autoOpen`; on the bank alt also
   `bankAltMail`). The `MailButton` or Triangle (`PadKey` "mail" set) calls
   `MailWindow.Toggle`. Mailworthy never switches mail tabs itself.
2. **Scan.** `MailWindow.Refresh` calls `Bags.Evaluate(Bags.CurrentSettings())`:
   - `Bags.Slots` (bags 0..`LastBag`, reagent bag included) then `Bags.Group` (per link +
     bound + in use).
   - Per item, the local `value(item)` gathers facts (`Locks.IsItemLocked`,
     `Pins.Effective`, `Quests.For`, `Conjured.Is`, `Recipes.Known` (recipes only: `item.known`), `Classes.Of`, `Prices.Vendor`,
     `Prices.Lookup` when `Prices.Source()` is set), then:
     `Valuation.Evaluate` (section 4.2) → `Routes.Divert` (section 4.3) → `Routes.Choices`
     and the row pick (`Routes.Picked` → `Routes.Force`) → `settings.hold` (no bank alt,
     or skipped for the visit: the bank alt's share stays) → `Bags.ApplySendSwitches` (the
     Send A/D/B/V switches).
   - Return to sender: when `Returns.On()`, `settings.returns = Returns.Current()`; an item
     that is not a hard keep is split by `Returns.Split` into whole stacks per sender
     (`Returns.Result`, no row pick); the rest is valued as usual.
   - Each item is filed into `mail`, `keep` or `unmailable`; totals per recipient
     (`totals.byRecipient`, bank alt first as `""`), mails = stacks / 12 rounded up.
3. **Preview.** The window draws "To:" lines for every recipient (`UI.Recipients`), binding
   rows (`Routes.List`), Mailing rows with a chip each ("to X", "back to X", route chip),
   Staying rows with the reason, the total, and the Send button labelled with the
   recipients (`UI.SendText`).
4. **Send.** `UI.Send` keeps the shown list, re-scans, and runs
   `UI.Changed(shown, fresh, ...)`; any change of recipient, a Staying item now mailed, or a
   changed count aborts with "Not sent: ...". Otherwise
   `Mailer.Start(result.mail, Config.BankAlt(), settings)`:
   - `Mailer.Plan` groups the previewed slots by recipient (bank alt first), 12 stacks a
     mail; `Mailer.Blocker` refuses (already running, a binding naming this character, a
     bank-alt mail with no bank alt, combat, Send Mail tab hidden, postage short: `Mailer.Short`, which keeps `Mailer.RESERVE` = 5s on the character).
   - `sendNext(i)`: `ClearSendMail`; each stack must pass `Mailer.StillThere` before
     `C_Container.UseContainerItem`; failures are skipped and listed as stayed.
   - `sendMail(i)`: attached count must match, `SetSendMailCOD(0)`, `SetSendMailMoney(0)`,
     postage check (`GetSendMailPrice` + `Mailer.RESERVE` against `GetMoney`, `Mailer.Affords`), `SendMail(to, subject, "")`, 10 s watchdog.
   - `MAIL_SEND_SUCCESS`: credit (`MailworthyDB.mailed`, `Contributions.Tag/Count`,
     `Ledger.RecordSent` with exactly what was attached), then the next mail.
   - Stops on `MAIL_FAILED`, `MAIL_CLOSED`, `PLAYER_REGEN_DISABLED`, tab hidden, timeout,
     count mismatch, postage short, the player's Stop (`Mailer.RequestStop`). The receipt
     goes to `Mailer.OnSent` listeners (BankAlt redraw, chat line).
5. **Close.** `MAIL_CLOSED` clears the per-visit state: `Routes` (skip once, row picks),
   `Returns` (toggle off), `Bags` (bank alt skip), `Mailer.Stop`, `Ledger` (commit pending
   takes), `Contributions.Share`, `Border.RefreshAll`, `Trip`.

While `Mailer.Busy()`, anything that would change the list is refused (`Pins.Toggle`,
`Pins.SetMode`, `LocksUI`, `PinWarning` Unpin, MailWindow actions), so what goes out is
what was previewed.

### 4.2 The decision rule: `Valuation.Evaluate(item, price, settings)`

Checks in order (each returns a keep or mail verdict with a reason string; full detail in
PLAN.md "Decision rule"):

1. Hard keeps: locked, vendor pin (keep, tagged V), soulbound, quest item, conjured,
   "a quest needs it", in use, profession tool, the ranged weapon's ammo (`Valuation.IsAmmo` →
   `Ammo.Is`).
2. Pins: item info not loaded yet; bank here (BH); bank pin (mail to the bank alt, route
   `bank`, unless the price call failed).
3. Profession keep ("your X needs it", `ProfessionKeep` / `NeededBy` with tiers and
   `TierCheck` findings); with `matsToBankAlt` it mails to the bank alt instead.
4. Local `evaluate`: no price source → whites and `Valuation.STAPLES` mail as `common`,
   the rest stays; `price.failed` → stays; else AH net vs disenchant net vs threshold
   (`Valuation.Threshold`, `MinGain`, `BankReason`), mail `ah` / `de` / `bank`, or
   "not worth it".
5. `Valuation.Unpriced` (no AH price, or older than `maxAgeDays`): failed stays, grey stays,
   staples mail, otherwise route `noprice` (the bank alt).
6. Disenchant-here override for an Enchanting character (`DisenchantsHere`).

The verdict (`item.result`) carries `action`, `route`, `reason`, `gain`, `postage`,
`threshold`, pin and keep flags (`pinned`, `vendorPin`, `neededBy`, `deHere`, `failed`, ...);
`Routes.Force` and `Returns.Result` add `to`, `what`, `guild`, `key`.

### 4.3 Bindings: `Routes.Divert(item, verdict, price, settings, routes)`

1. `Routes.Divertible`: never a hard keep (`Valuation.HardKeep`: a kind flagged `hard`), a pin, a failed price
   call or a verdict kept for this character.
2. `verdict.neededBy` (this character's own profession keep) wins: me first.
3. `Routes.Units` (unit price; the cap price takes the higher of auction and vendor for
   gear).
4. Each binding from `Routes.Active()` (personal, account, then `Guild.Rules`) that
   `Routes.Matches` (profession materials by tier, recipes via
   `Valuation.RecipeProfession`, class items with `Routes.ClassPriced`; a recipe this character
   already knows, `item.known`, never matches a binding whose recipient `Routes.IsMe`); the winner by
   `Routes.Before`: character, then account, then guild; lower known skill first.
5. At or above the cap → the normal rule. `Routes.GearBeaten` (Enchanting Gear switch) → the
   normal rule.
6. `Routes.Force` builds the mail verdict (`route = "friend"`, `to` from
   `Routes.Recipient` → `Routes.Crafter`, the peer's own character with that profession).

The row pick (`Routes.Pick`, one visit) goes through `Routes.Choices`, which skips the tier
table, cap, Gear switch and profession keep but not `Divertible`, `ClassPriced`, a binding
naming this character, or Return to sender.

### 4.4 Bag tags and tooltip lines

1. `BankAlt.Refresh` runs `Bags.Evaluate(BankAlt.Settings())` and stores
   `BankAlt.Verdict(item)` (AH / DE / V / BA / BH / F / R) per slot, link and item ID. The
   cache is redrawn on lock/pin changes, `Mailer.OnSent`, Settings closing, Auctionator's
   `RegisterForDBUpdate`, and on `BAG_UPDATE_DELAYED` only when `Bags.Fingerprint()` changed
   or `BankAlt.Waiting()` (an item's data or vendor price not loaded, or a failed price
   call). A bag update that changed only an ammo stack's size (each shot of a bow or gun)
   just marks the cache stale (`BankAlt.Invalidate`), read again at the next hover or bag
   draw: redrawing every bag-addon button on each shot stuttered (CurseForge, 2026-11-14).
   `Comms.Hear` marks it stale too (a friend's skills can change a binding's verdict).
   `/mw report`: "bag tags: N bag update(s) this session, M redrew the tags".
2. `BankAlt.Decorate` (registered at load with `Border.AddDecorator`) draws the tag letter;
   `Border.RefreshButton` draws the glow then runs every decorator.
3. Blizzard bags: `Border` post-hooks `UpdateItems` on the combined and individual bag
   frames. Bag addons: `BagAddons` calls `Border.DrawBagSlot` from each addon's own API.
   Auctionator: `AuctionatorTags` post-hooks `AuctionatorGroupsViewItemMixin.SetItemInfo`.
   Each registers a `Border.AddRefresher` so `Border.RefreshAll` reaches it.
4. Tooltips: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item)` in
   `Border` (lock/pin line), `BankAlt` (verdict explanation) and `MailWindow` (its own rows).
   `Config.Tooltips()` (Settings > Item tooltips) sizes the first two: "full", "short" (the
   tag line and any warning; one sentence for a lock or pin), "off" (none). `MailWindow`'s
   row lines ignore it: they say what a click on the row does.
5. Textures and font strings sit on other addons' buttons but are kept in our own weak
   tables; no Lua field is written on a Blizzard or bag-addon frame.

### 4.5 Peers: Comms, Guild, Ledger

`Comms.Hear` validates every `CHAT_MSG_ADDON` with prefix `Mailworthy` and dispatches by kind:

| Kind | Sent by | Channel | Meaning |
|---|---|---|---|
| `H2` | `Comms.Announce` | GUILD + PARTY/RAID | Hello: own crafting skill lines and crafting alts |
| `A2` | `Comms.Ask` | GUILD + PARTY/RAID | Please say hello |
| `S2` | `Comms.Announce` | GUILD + PARTY/RAID | Skill ranks (material tiers) |
| `F2` | `Stale.Message` | GUILD + PARTY/RAID | Day of the freshest Auctionator scan (display only) |
| `U2` | `Version.Message` | GUILD + PARTY/RAID | Release version (release builds only) |
| `G2` | `Contributions.Messages` | GUILD | Guild-rule giving totals |
| `T2` | `Guild.Broadcast` | GUILD | One guild template rule part |
| `Q2` | `Guild.Ask` | GUILD | Ask for a newer template |
| `M2` | `Ledger` outbox via `Comms.Whisper` | WHISPER | A sent mail's per-item values, to the recipient |
| `R2` | `Ledger.EncodeAnswers` | WHISPER | The recipient's settled value when it differs |
| `V2` | (no longer sent) | WHISPER | Old value format, still decoded by `Ledger.DecodeValues` |

Peers are stored in `MailworthyDB.peers` and read by `Routes.Crafter` (which character of a
bound player has the profession), `Routes.Skill`, `Comms.Mark` (the name mark) and
`Version`. The ledger sees mail through post-hooks on `SendMail`, `TakeInboxItem`,
`TakeInboxMoney`, `AutoLootMailItem` and the send-tab events; `Returns.Owed` reads its log.

### 4.6 Away from the mailbox

- `Trip.Check` (on `BAG_UPDATE_DELAYED` / `PLAYER_REGEN_ENABLED`): 4 or fewer free slots →
  one chat line a session, and the minimap tooltip line.
- `Vendor` (at a merchant): lists V-tagged stacks, sells 12 a press, re-checking each slot
  (`Vendor.StillThere`); never sells what another player mailed and is owed back.
- `TierCheck` reads the profession window on `TRADE_SKILL_*` / `CRAFT_*`.
- `Stale` asks peers for their scan day at login when its own prices are old, and nudges in
  chat at the mailbox.

## 5. Events

Every `ns.On` handler, by event. `Blocked.lua` registers `ADDON_ACTION_FORBIDDEN` and
`ADDON_ACTION_BLOCKED` on its own frame.

| Event | Modules |
|---|---|
| `ADDON_LOADED` | Core (`ns.Init`), BagAddons, MailButton (`Blizzard_MailFrame`) |
| `PLAYER_LOGIN` | Core (first), Characters, Locks, Pins, Border, Config, Quests, Comms, Guild, Stale, Mailer, Ledger, Contributions, PadKey, MailButton, SettingsUI, RoutesUI, LedgerUI, LocksUI, PinWarning, MinimapButton, MailWindow, BankAlt, Vendor, BagAddons, AuctionatorTags, Report |
| `MAIL_SHOW` | Conjured, Recipes, Comms, Stale, Mailer, Trip, MailButton, Report |
| `MAIL_CLOSED` | Border, Routes, Bags, Mailer, Ledger, Contributions, Returns, Trip, MailWindow |
| `MAIL_SEND_SUCCESS` | Mailer, Ledger |
| `MAIL_FAILED` | Mailer, Ledger |
| `MAIL_SUCCESS` | Ledger |
| `MAIL_INBOX_UPDATE` | Report (AH invoice cut) |
| `MAIL_SEND_INFO_UPDATE`, `SEND_MAIL_MONEY_CHANGED`, `SEND_MAIL_COD_CHANGED` | Ledger (send-tab snapshot) |
| `UI_ERROR_MESSAGE` | Mailer (log) |
| `BAG_UPDATE_DELAYED` | Recipes (before BankAlt: forgets "not known"), BankAlt, MailWindow, LocksUI, Trip, Vendor |
| `PLAYER_MONEY` | MailWindow |
| `PLAYER_REGEN_DISABLED` | PadKey (clear bindings), Mailer (stop) |
| `PLAYER_REGEN_ENABLED` | Trip |
| `CHAT_MSG_ADDON` | Comms, Ledger, RoutesUI |
| `GROUP_ROSTER_UPDATE` | Comms, RoutesUI |
| `GUILD_ROSTER_UPDATE` | Guild, Contributions, RoutesUI |
| `QUEST_LOG_UPDATE` | Quests |
| `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_DATA_SOURCE_CHANGED`, `TRADE_SKILL_UPDATE`, `CRAFT_SHOW`, `CRAFT_UPDATE` | TierCheck |
| `MERCHANT_SHOW`, `MERCHANT_CLOSED` | Vendor |
| `INPUT_DEVICE_INTERFACE_TRANSITION` | PadKey, MailButton, Vendor |

## 6. Hooks and outside APIs

Every hook is a post-hook installed under `pcall`. The taint rules are in AGENTS.md and
FOREVER-UI-NOTES.md; `spec/no_gamepad_taint_spec.lua` guards them.

| Target | Kind | Module (switch) |
|---|---|---|
| `HandleModifiedItemClick` | `hooksecurefunc` | Locks (`altClickLock`), Pins (`pinClick`) |
| `SendMail`, `TakeInboxItem`, `TakeInboxMoney`, `AutoLootMailItem` | `hooksecurefunc` | Ledger (`ledger`) |
| `ContainerFrameCombinedBags` / `ContainerFrameContainer.ContainerFrames[i]` `:UpdateItems` | `hooksecurefunc` on the frame | Border (`slotBorder` or `bankAltTags`) |
| `TooltipDataProcessor.AddTooltipPostCall(Item)` | tooltip post-call | Border (`slotBorder`), BankAlt (`tooltipLines`), MailWindow (`tooltipLines`) |
| `AuctionatorGroupsViewItemMixin.SetItemInfo` | `hooksecurefunc` on the mixin | AuctionatorTags (`auctionatorTags`) |
| Auctionator `API.v1` (prices, age, exact, disenchant, `RegisterForDBUpdate`) | API calls | Prices, Stale, BankAlt |
| `TSM_API` (`ToItemString`, `GetCustomPriceValue`, `IsCustomPriceValid`) | API calls | Prices |
| `DisenchantValueAPI.GetValue`; Disenchantry detected only | API calls | Prices |
| `Baganator.API.RegisterCornerWidget`, `CallbackRegistry` "ViewComplete" | addon API | BagAddons (`baganatorTags`) |
| `Bagnon.ContainerItem:Update` | `hooksecurefunc` | BagAddons (`bagnonTags`) |
| `ArkInventory.API.ItemFrameUpdated` | `hooksecurefunc` | BagAddons (`arkInventoryTags`) |
| BetterBags `Events:RegisterMessage` ("item/Updated", "item/Clearing", "bags/Draw/*/Done", "bags/DesignChanged") | addon messages | BagAddons (`betterBagsTags`) |
| `SetOverrideBindingClick` / `ClearOverrideBindings` on `MailworthyPadWatcher` | override bindings | PadKey (`padNav`, `padTriangle`, `padLock`, `padPin`, `padVendor`) |
| `OnUpdate` watchers | own frames | PadKey (0.1 s), MailWindow tab watcher (0.2 s), MinimapButton (drag only) |
| `HookScript` | own frames only | MailWindow, Nav, BankAlt, Widgets |
| `GetInventoryItemID("player", INVSLOT_RANGED)`, `GetItemInfoInstant` (the weapon's and the ammo's class) | API calls (pcall'd) | Ammo; `GetItemInfoInstant` also Prices, `Bags.Fingerprint` |

Read-only: `FrameControlsManager:GetActiveFrame()`, `SmartNavigation:GetCurrentButton()`
(Locks, Pins, PadKey). Global API for other addons: `MailworthyAPI.v1.GetGuildExport`
(Contributions).

## 7. SavedVariables

`Core.Init` (at `ADDON_LOADED`) creates the tables marked *init*; the rest are created
lazily by their module. Keys `realm|faction` and `realm|faction|guild` scope data per
server side.

**`MailworthyDB`** (account)

| Field | Shape | Owner |
|---|---|---|
| `log` *init* | `{ "MM-DD HH:MM:SS name [area] msg" }`, 300 lines | Log |
| `blocked` *init* | `{ {event, fn, at, after, version} }`, 10 | Blocked |
| `characters` *init* | `["name|realm|faction"] = {name, realm, faction, class, level, professions, lastSeen}` | Characters |
| `features` *init* | `[switch] = bool` (only what the player changed) | Core |
| `routes` *init* | `[realm|faction] = { binding }` (account scope) | Routes |
| `peers` *init* | `[realm|faction][lowername] = {name, professions, characters, version, at, skills, release}` | Comms (`release`: Version) |
| `pins` *init* | `[itemID] = {kind = "bank"|"vendor", link, at}` | Pins |
| `settings` | `[key] = value` (only what the player touched; defaults in `Valuation.DEFAULTS`, flags in `Config.FLAGS`, `tooltips` = "full" / "short" / "off") | Config |
| `bankAlts` | `[realm|faction] = name` | Config |
| `names` | `{ {name, realm, faction} }`, 40 | Config |
| `realms` | `[realm] = {firstSeen}` | Config |
| `crafterOffers` | `[realm|faction]["name|prof"] = true` | Routes |
| `fresh` | `[realm|faction][lowername] = {name, day, at}` | Stale |
| `tierCheck` | `[charKey][skillLine] = {rank, at, recipes, reagents, findings, ...}` | TierCheck |
| `mailed` | `[itemID] = {route, listRoute, reason, gain, at, from, to}`, 30 days | Mailer (BankAlt reads) |
| `ledger` | `[realm|faction] = {log, players, expect, outbox, nextId}` | Ledger (Returns reads) |
| `guildTemplates` | `[realm|faction|guild] = {rev, from, via, at, rules = { {profession, to, cap, gear} }, use}` | Guild |
| `guildDrafts`, `guildPublished` | drafts per guild key; `[key][rev] = true` | Guild |
| `guildGiven`, `guildHeard` | `[guild key][lowername] = {name, total, since, days, ...}` | Contributions |
| `minimap` | `{angle}` | MinimapButton |
| `selftest` | removed at init (discovery builds) | Core |

A binding record: `{to, profession = skillLineID | class = "MAGE", cap, gear = "de"|nil, at}`.

**`MailworthyCharDB`** (per character)

| Field | Shape | Owner |
|---|---|---|
| `lockedItems` *init* | `[itemID] = {link, at}` | Locks |
| `routes` *init* | `{ binding }` (character scope) | Routes |
| `settings` | `keepProfessionMats`, `matsToBankAlt` (`Config.CHARACTER`) | Config |
| `pinMode` | `"here"` or nil | Pins |
| `tagsAfterSend` | bool | BankAlt |
| `lockedSlots` | old slot locks; migrated to `lockedItems` and removed by `Locks.MigrateSlotLocks` | Locks |

Migrations live in `Core.Init`, `Locks.MigrateSlotLocks`, `Guild.ReadSaved` (old odd caps)
and `Contributions.Migrate`; `critical_path` loads an older build's SavedVariables.

## 8. Feature switches and slash commands

All default on (`ns.Features.DEFAULTS` in `Core.lua`; the help line there lists them too).

| Switch | Checked in |
|---|---|
| `mailButton` | MailButton |
| `autoOpen` | MailWindow, MailButton |
| `bankAltMail` | MailWindow, MailButton |
| `padTriangle`, `padNav`, `padLock`, `padPin`, `padVendor` | PadKey |
| `altClickLock` | Locks |
| `pinClick` | Pins |
| `slotBorder` | Border, BagAddons |
| `bankAltTags` | BankAlt, Border, BagAddons |
| `tooltipLines` | BankAlt, MailWindow (the Settings setting `tooltips` sizes BankAlt's and Border's lines: section 4.4) |
| `vendorButton` | Vendor, PadKey |
| `minimapButton` | MinimapButton |
| `comms`, `peerMark` | Comms |
| `staleNudge` | Stale |
| `versionNotice` | Version |
| `crafterOffer` | MailWindow |
| `tiers` | Tiers |
| `tierCheck` | TierCheck |
| `guildTemplate` | Guild |
| `ledger` | Ledger, Returns |
| `returnToSender` | Returns |
| `questNeeds` | Quests |
| `tripNudge` | Trip |
| `baganatorTags`, `bagnonTags`, `arkInventoryTags`, `betterBagsTags` | BagAddons (`BagAddons.FEATURE`) |
| `auctionatorTags` | AuctionatorTags |

`/mw` (or `/mailworthy`), in `ns.HandleSlash`: (none) / `settings` → SettingsUI; `report` →
Report; `feature <name> on|off`; `locks` → LocksUI; `pins` → `Pins.PrintList`;
`pinwarning on|off`; `friends` / `bindings` → RoutesUI; `guild` → `RoutesUI.ShowGuild`;
`scan` → `Bags.Scan`; `ledger` / `log` → LedgerUI; `summary` → `BankAlt.ShowWindow`;
`vendor` → `Vendor.Toggle`; anything else → help.

## 9. Where the Safety rules are enforced

The rules are in AGENTS.md "Safety"; `spec/critical_path_spec.lua` checks every mail
against them.

| Rule | Enforced in |
|---|---|
| Mail only to recipients shown in the preview, only after Send | `MailWindow`: `UI.Recipients` ("To:" lines), row chips, `UI.SendText`; `UI.Send` → `UI.Changed` (previewed = sent); `Mailer.Plan` takes only the previewed slots and `result.to` / the bank alt; `Mailer.Blocker` |
| A binding goes to the bound player, or their character with the profession (never their bank alt) | `Routes.Recipient` → `Routes.Crafter` (peer data from `Comms`); `Routes.Offer` |
| A guild rule is a binding only when on, authored by a GM/officer in the player's roster, to a roster member | `Guild.Rules` (`InUse`), `Guild.Offer` (`RankOf(author) <= PUBLISHER_RANK`, recipients in roster), `Guild.Hear` (GUILD only); editing: `Guild.CanPublish`, `DraftAdd`, `Publish` |
| Return to sender: only what the ledger shows was mailed and not mailed back; whole stacks; no system/COD/returned mail; shown like any recipient | `Returns.Owed`, `Returns.Split`, `Returns.Available` (needs `ledger`); `Bags.Evaluate` (no split for a hard keep; returns win over pins and picks); "back to" chip in `MailWindow` |
| Never attach money | `Mailer` local `sendMail` (`SetSendMailCOD(0)`, `SetSendMailMoney(0)`) |
| Postage never leaves the character with less than 5s | `Mailer.RESERVE`, `Mailer.Affords`: `Mailer.Short` → `Mailer.Blocker` and `UI.SendState` / `UI.PostageText` (before Send); the postage check in `Mailer` local `sendMail` (each mail); money or postage the game won't say: nothing goes |
| Never mail a locked item | `Valuation.Evaluate` (first check); `Mailer.StillThere` |
| Never mail an item an active quest names | `Quests.For` → `Valuation.Evaluate`; `Mailer.StillThere`; `Vendor.StillThere` |
| Never mail a conjured item | `Conjured.Is` → `Valuation.Evaluate`, `Valuation.Unmailable`; `Mailer.StillThere` |
| Never mail the ammo the equipped ranged weapon fires | `Ammo.Is` → `Valuation.IsAmmo` → `Valuation.Evaluate` (kind `ammo`, flagged `hard`); `Mailer.StillThere` and the attached-stack check in `Mailer` (a weapon equipped mid-send); `Vendor.StillThere` |
| No bank alt, or skipped for the visit: its share stays | `Bags.HoldReason` / `settings.hold` in `Bags.Evaluate`; `Bags.SkipBankAlt`; `Mailer.Blocker` |
| A binding or return never overrides a hard keep | `Routes.Divertible` (`Valuation.HardKeep`); `Bags.Evaluate` before `Returns.Split` |
| Cap: at or above it the normal rule applies; green/blue against max(auction, vendor) | `Routes.Divert`, `Routes.Units`; `Valuation.DisenchantsHere` |
| Enchanting Gear switch | `Routes.GearBeaten` (in `Routes.Divert`); wire format `Guild.WireCap` / `ReadCap` |
| Me first, then friends, then guild | `Valuation.ProfessionKeep` / `NeededBy` → `Routes.Divert` returns nil on `neededBy`; `Routes.Before`; `Guild.Rules` / `Guild.Why` drop what this character has or bound itself |
| The row pick and what it can't bypass | `Routes.Pick` / `Picked` / `ClearPicks` (`MAIL_CLOSED`), `Routes.Choices` (uses `Divertible`, `ClassPriced`, `IsMe`); `Bags.Evaluate` (returns carry no pick) |
| Re-check each slot right before attaching | `Mailer.StillThere` in `sendNext`; attached-count check in `sendMail` |
| No price source: only whites and `Valuation.STAPLES` (recipes only to their binding) | `Prices.Source`; `Valuation` local `evaluate`; `Routes.Matches` + `Valuation.RecipeProfession` |
| Priced but no or stale price → bank alt, never a class binding; failed price call stays; grey stays | `Valuation.Unpriced`; `Prices.Lookup` / `TSMUnit` (`failed`); `Routes.PriceKeep`, `Routes.ClassPriced` |
| Bank pin mails to the bank alt (never past a hard keep, unloaded data or a failed call; never to a binding) | `Pins.Effective` → `Valuation.Evaluate` pin branch; `Routes.Divertible` (pinned) |
| A profession binding mails its materials and recipes whatever the price, under its cap | `Routes.Matches`, `Routes.Force` |
| A binding naming this character keeps the item here (not a recipe it already knows: regular rules) | `Routes.Force` (`forMe`), `Routes.Divertible`, `Mailer.Blocker`; `Routes.Divert` + `Recipes.Known` |
| The list can't change during a send | `Mailer.Busy` checks in `Pins`, `LocksUI`, `PinWarning`, `MailWindow` |

## 10. Tests

- **Shipping gate**: `spec/critical_path_spec.lua` (CI job `critical-path`); `verdict_kinds_spec` runs it
  again with every reason reworded and fails on any source line that compares a reason's text. AGENTS.md
  "Critical path" says what it covers and what a new way to mail must add.
- **Controller gate** (CI job `controller`): `dpad_reach_spec` (D-pad walk of every view;
  a new window or view adds its walk), `padkey_spec`, `nav_spec`, `ux_views_spec`,
  `no_gamepad_taint_spec`.
- **Everything else**: one `<module>_spec.lua` per module (section 3; `util_spec` for `Util`), plus
  `send_switches_spec` (Bags.ApplySendSwitches), `pin_mode_spec` (BA/BH, PinWarning),
  `peer_mark_spec` (Comms.Mark).
- Run: `eval "$(luarocks --lua-version=5.1 path)"`, `busted --lua=luajit`, `luacheck .`
  (`.luacheckrc` lists every WoW global the code reads).
