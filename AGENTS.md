# Mailworthy agent rules

Mailworthy is a WoW Forever addon (`## Interface: 16001`). Start with
`docs/HANDOFF.md` (state, decisions, pitfalls, what's left), then `docs/PLAN.md`
(design) and `docs/FOREVER-UI-NOTES.md` (Blizzard source findings, taint rules).
To find code, use `docs/ARCHITECTURE.md` (module map, data flows, events, hooks,
SavedVariables, feature switches, where each Safety rule is enforced) before reading files.

## Safety (STRICT)

- Mail goes **only** to the recipients shown in the preview, and only after the
  player presses Send: the saved bank alt, and, for a binding (`Routes.lua`), the
  bound player, or the character of theirs that has the bound profession as their
  own Mailworthy reported it (never their bank alt for the AH). A binding can be short-lived, from a
  suggestion (`Suggest.lua`, `Routes.AddTemp`; operator, 2026-11-22): **While grouped** (a player in this
  character's group, until either leaves it) or **This visit** (one of this account's characters, or a player this
  character owes in the mail ledger, paying back in kind: operator, 2026-11-22, "build the rest of the table";
  until the mailbox closes), made only when the player presses it, never saved, under the same rules as any binding (a
  run already sending when its player leaves the group finishes as previewed; it ends after). A
  guild template rule
  (`Guild.lua`) is a binding only once the player turned the guild rules on, only when its
  author is a guild master or officer in their own roster (any member may pass a copy on), and
  only to a player in that roster (operator, 2026-11-07). With **Return to sender**
  (`Returns.lua`) on for the visit, also the player who mailed this character an item, for
  what the mail ledger shows they mailed it and it hasn't mailed back (whole stacks; no
  system, COD or returned mail), whatever its price, and only when that player is shown in
  the preview like any recipient, a "To:" line and the "back to <name>" chip on each row
  (operator, 2026-11-08: "any new recipient should be shown even if its a return to
  sender"). A **payback** (`Paybacks.lua`; operator, 2026-11-22: "build phase 3" of docs/RECOMMENDATIONS.md
  with "the payback pick starts off, one click away"): the player whose counted mail this character took
  and who it still owes, for an item this character's own professions make that the payback idea named for
  that player, only once the player picks it on the row for the visit, shown in the preview like any
  recipient (a "To:" line and the "PB back to <name>" chip), never past a hard keep, a pin, a failed price
  call or what this character's own professions keep; Return to sender still wins. Its value counts off the
  debt (with no auction price: its materials, never more than what's owed). The **needs note** this
  character whispers with a counted mail's values tells only that player's character its level, class, bag
  sizes and the ammo its ranged weapon fires, and its **gear note** (2026-11-22) what its main hand and ranged
  weapon are, its quiver's size and which gear slots are empty; nothing else (Settings > Tell crafters, on by
  default). Never attach money. Never send a mail whose postage would leave the character
  with less than 5s (`Mailer.RESERVE`; operator, 2026-11-14: "you should always have a reserve
  of 5s before mailworthy will auto send"): Send stays greyed out, and a run stops before the
  mail that would.
  Never mail a locked item.
- Never mail an item an active quest's objective names, quest item or not (operator,
  2026-11-08). Never mail a conjured item (a Healthstone, a mana gem, a mage's food and water;
  `Conjured.lua`; operator, 2026-11-10: "should always be keep as they are ephemeral items"). Never mail the
  ammo the equipped ranged weapon fires (arrows for a bow or a crossbow, bullets for a gun; `Ammo.lua`;
  operator, 2026-11-14: "Matching type only"); the other type, and all ammo while no bow, crossbow or gun
  is equipped, follows the normal rule. Without a bank alt (optional), or with it skipped for the visit, its share
  stays in the bags; only bindings mail.
- A binding or a return never overrides a hard keep (locked, soulbound, quest, conjured, in use, tool, ammo); at or
  above its price cap the normal rule applies and the item goes to the bank alt. An Enchanting
  binding or guild rule with its Gear switch on (`Routes.GearBeaten`; operator, 2026-11-11) leaves a
  green or blue piece to the normal rule too, when it disenchants for no more than it sells for. A
  green or blue piece's cap is checked against the higher of its auction and vendor price.
- Me first, then friends, then the guild (operator, 2026-11-14: "Make me a profit/level my professions
  first, then the same to my friend rules, then the same to my guild rules"): what this character's own
  professions still use stays with it before any binding takes it; then the player's own bindings, then
  guild rules. "Still use" is per profession and per material, for every crafting profession (First Aid,
  Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, Leatherworking, Tailoring; `Tiers.lua`,
  `TierData.lua`; operator, 2026-11-06 and 2026-11-23: "confirm this type of check for all professions"):
  a profession that uses the material keeps it until its own skill reaches the skill at which it is done
  with it (First Aid cloth: where the next bandage is learnable; the rest: where its last recipe using it
  turns grey), or while its profession window still shows a non-grey recipe using it (`TierCheck.lua`;
  not First Aid cloth, `TierCheck.EXEMPT`: the next bandage's learn skill alone decides),
  or while converting it up pays (leathers); a profession that doesn't use it never keeps it, and with
  two that do, it stays until both are done with it. The keep names that profession, the skill it is
  done at and this character's skill now ("your Blacksmithing needs it (until skill 210, you're at
  150)"). The row's pick button (`Routes.Pick`, one mailbox visit, cleared at MAIL_CLOSED) sends an
  item to any binding whose profession or class takes it, past the profession keep, the cap, the Gear
  switch and the tier table ("my click wins"), and the row shows where it goes; never past a hard keep,
  a pin, a failed price call, a class binding's price rule, Return to sender or a binding naming this
  character. On a bank-here row (BH: what this character's own professions still use, or a bank-here pin;
  `Routes.BankHere`) the same button names the item's own rule **Here** and, next, **Alt** mails it to the
  bank alt for the visit like a bank pin (operator, 2026-11-21: "i want to be able to click a toggle between
  Here/Alt"; "use the same ui interaction that the other toggle does"; `Routes.AltOffered`): past the
  bank-here pin and the price rules, never past a hard keep, item data not loaded yet, a failed price call
  or a binding naming this character, and only while the bank alt takes this visit's mail (none while it
  is skipped, unset, or this character); the send switches don't hold it, and it never sends a bank-here
  pin to a binding.
- Re-check each slot right before attaching it; skip anything that changed.
- Without Auctionator (no price source), the only items mailed are unlocked, tradeable white
  (common) items and the staple trade goods (`Valuation.STAPLES`, whatever their quality)
  (operator, 2026-11-08: "Whites + staples + recipes"; recipes only to their profession's
  binding). With Auctionator (or TSM), an item without an auction price, or whose only price
  is past the age limit, goes to the **bank alt**, never to a class binding (operator,
  2026-11-08: "going to the bank alt on no data is better than holding on the main";
  "Yes, gear goes too"; "Stale prices go too"; replaces "an item without a price stays in
  the bags" and its launch-days 0-13 exception for white trade goods). With both installed, each
  item's price is the more up-to-date of the two (`Prices.Fresher`; operator, 2026-11-17: "it
  shouldnt be a fixed rule, it should be whichever addon has the most up to date scan data";
  replaces "Auctionator + TSM: unpriced stays, never priced by TSM"), so it goes to the bank alt
  unpriced only when neither has a current price; a failed Auctionator call is never replaced by
  TSM's price, and a TSM call that fails counts as TSM not installed (Auctionator's own result
  stands, as before 2026-11-17; operator chose "a TSM failure ... leaves today's result"). Grey junk stays, with an auction price too when a vendor buys it
  (vendor trash: what the merchant's Sell All Junk button sells, `Valuation.IsVendorTrash`; operator,
  2026-11-20: "Those items shouldnt be suggested to AH even if the price is favorable. those dont
  sell"), an item whose price call failed stays, and the hard keeps above come first.
  A **bank pin** (`Pins.lua`, Ctrl+Alt+click / R3) mails the pinned item to the bank alt whatever
  its price or quality, grey junk too and without a price source (operator, 2026-11-13: "Pins
  override them"); never past a hard keep, item data not loaded yet or a failed price call, and
  never to a binding. With Return to sender on, what another player mailed goes back to them,
  pinned or not (operator, 2026-11-13: "return to sender should win").
  A profession binding mails its materials and its profession's recipes to the bound player
  whatever their price (operator, 2026-11-08: "keep as is"; recipes: "recipes should go to
  their respective profession mappings"), under its price cap when there is a price; a class
  binding follows the price rules above, except for what its class's own skill levels on
  (`ClassSkills.lua`): a rogue's binding takes locked lockboxes and a mage's Comprehension
  scrolls like a profession's materials, whatever their price, under the cap when there is a
  price (operator, 2026-11-20: "Lock boxes can route to rouges for training ... comprehension
  items to mages(class specific profession)"; "Like profession mats"). Without a binding for
  that class they follow the normal rule ("Normal rule, as today"); a lockbox already
  unlocked is no lockbox, and no binding takes a kind of lockbox while one of its boxes is, or
  while the game doesn't say whether it is locked. On a rogue or a mage itself they stay like its professions'
  materials ("Yes, they stay"; me first: the row's pick and a bank pin still move them).

## Never write into Blizzard's controller UI (STRICT)

Every one of these tainted gamepad input in game (jumping, targeting, item use
blocked until /reload):

- no prompted bindings on Blizzard footers, no `GamepadSharedUtility` footers of
  our own, no `FrameControlsManager` registration, no `ShowUIPanel` for our frames;
- no entries in the gamepad "More" menu (`Menu.ModifyMenu("MORE_CONTEXT_ACTIONS")`);
- no Lua fields written on Blizzard frames, no `smartNavigation*` / `OnSmartNav*` /
  `buttonContext` keys on ours;
- no `CreateFrame` while a gamepad panel is open: create every frame at login
  (on UIParent, then `SetParent`);
- never switch mail tabs from addon code (`MailFrameTab_OnClick`);
- **never call `SetFocus`** (it crashed the gamepad UI in LedgerLink).

Allowed: our own override bindings on our own frame (`PadKey.lua`, out of combat,
cleared on focus loss and at `PLAYER_REGEN_DISABLED`), `hooksecurefunc` post-hooks,
textures / font strings on Blizzard frames kept in our own tables, read-only
`FrameControlsManager:GetActiveFrame()` / `SmartNavigation:GetCurrentButton()`.
`spec/no_gamepad_taint_spec.lua` guards this; keep it passing.

## Input (STRICT)

- **Keyboard/mouse first**, controller too: every feature works with both.
- Controller navigation in our windows goes through `Nav.lua` + `PadKey.lua`
  (Mailworthy's own highlight and bindings), not Blizzard's smart navigation.
- No right-click-only, modifier-only (Alt+click has the controller's L3 twin),
  drag or hover-only actions; no required typing.
- Every piece that touches Blizzard UI has a `/mw feature` switch.
- CI's `controller` job is the controller gate: `spec/dpad_reach_spec.lua` walks the D-pad over
  every view of every window (each button reachable from the top-left one, a way back from each)
  and fails for a window with no walk; with the padkey, nav, ux_views and no_gamepad_taint specs.
  A new window or view adds its walk there; never loosen it to make a change pass.

## Critical path (STRICT)

`spec/critical_path_spec.lua` is the shipping gate: a mailbox visit with a realistic
bag, by mouse and by controller, with and without Auctionator, with a binding, with a suggested binding
(While grouped, This visit, its player leaving the group), with a payback (picked by mouse and by controller,
left alone, locked), with paying back in kind (This visit to a player owed), with a bank pin, with a bank-here row's Alt, with vendor trash, with a hunter's
ammo, with a guild
template (on and off), with Return to sender (on a main and on the bank alt), with the 5s
money reserve (before Send and mid-run), with no realm name from the game (`Characters.Realm`: the
saved bank alt still found, unnamed realms never sharing one), and on
an older build's SavedVariables; every mail checked against the Safety rules above, and
what was previewed must be exactly what was sent. CI runs it as its own job,
`critical-path`, which main's branch protection requires (operator, 2026-11-07); `release.yml`
publishes a tag only after all of CI passes.

- Never loosen, skip or delete one of its assertions to make a change pass; fix the
  change. If the operator changes a rule on purpose, update the test in the same PR
  and say so in the PR description.
- A new way to mail (a recipient kind, a send path, a SavedVariables migration) adds
  its case here. Keep it to outcomes: thresholds and prices belong in other specs.

## Working rules

- Branches and PRs only; never push to `main`, never force-push.
- The operator merges PRs without saying so: gate every push to a PR branch on
  `gh pr view N --json state --jq .state` being `OPEN`; if merged, branch from
  `origin/main` and open a new PR.
- Tag only when the operator says so ("tag vX.Y.Z"). Every tag publishes to
  CurseForge (project 1743661); plain `vX.Y.Z` = release file. Watch the release run
  and report the CurseForge upload line.
- Never invent WoW API functions: read Blizzard's Forever source
  (Ketho/wow-ui-source-forever) first; wrap anything unverified in `pcall` / nil
  checks and list it under "Beta unknowns" in README.md.
- In-game checks go into one copyable report (`/mw report`), not
  lists of `/dump` lines. Ask for an in-game test only when research shows the fix
  is real.
- Mailworthy files share names with LedgerLink's (`media/logo-400.png`, ...): link
  them by full path in messages.
- Before every push: `eval "$(luarocks --lua-version=5.1 path)"`, then
  `busted --lua=luajit` and `luacheck .`.
- **Codex review before every PR** (operator, 2026-11-07): before opening a PR, have Codex
  review the branch's diff against `origin/main` (Claude Code: the `codex:codex-rescue`
  subagent, review only, no edits), check each finding against the code, fix the real ones
  with a spec each, and list in the PR description what Codex found and what was fixed or why
  not. Commits pushed to an open PR that change behaviour get the same review.
  **Not for a docs-only PR** (operator, 2026-11-09: "theres no reason to codex review a docs
  only pr"): a PR that changes no Lua, spec, `.toc` / packaging or CI workflow (markdown,
  prototype sheets and images under `media/`) skips it; its description says "docs only".
- **Keep `docs/ARCHITECTURE.md` current (STRICT).** Before opening a PR, or pushing commits to
  an open one, that adds, removes or renames a module, a public function (`ns.<Module>.<Name>`
  that another module or a spec calls), an event handler (`ns.On`), a hook (`hooksecurefunc`,
  `HookScript`, `TooltipDataProcessor`, a bag-addon or Auctionator API), a SavedVariables field
  (`MailworthyDB`, `MailworthyCharDB`), a feature switch or a `/mw` command, or moves where a
  Safety rule is enforced, update `docs/ARCHITECTURE.md` in the same PR. The PR description
  says it was updated, or why no update was needed.
