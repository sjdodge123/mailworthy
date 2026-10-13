# Forever UI notes (from Blizzard's source)

Source: [Ketho/wow-ui-source-forever](https://github.com/Ketho/wow-ui-source-forever)
(`forever` branch). Paths are under `Interface/AddOns/`. Read 2026-10-13.
**(inferred)** marks conclusions drawn from reading, not seen in game.
Runtime checks for each of these are in [DISCOVERY-SESSION-2.md](DISCOVERY-SESSION-2.md).

## Pad keys

`Blizzard_SharedXML/Shared/GamepadConstants.lua:7-10`

| Constant | Key | PlayStation | Xbox |
|---|---|---|---|
| `GAMEPAD_FACE_BOTTOM` | `PAD1` | Cross | A |
| `GAMEPAD_FACE_RIGHT` | `PAD2` | Circle | B |
| `GAMEPAD_FACE_LEFT` | `PAD3` | Square | X |
| `GAMEPAD_FACE_TOP` | `PAD4` | Triangle | Y |

## Bag item "More" menu (Triangle) -> "Mailworthy: Lock slot"

- Built by `ContainerFrameCombinedBagsMixin:SetupGamepad`
  (`Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:3226-3325`) with
  `GamepadSharedUtility.CreateMoreActionsPromptedBinding(GAMEPAD_FACE_TOP)`.
  Triangle runs `CreateMoreActionsMenu` (`Blizzard_GamepadSharedUtility/PromptedBindings/PromptedBinding.lua:126-181`):
  `MenuUtil.CreateContextMenu(ownerRegion, gen)`, `rootDescription:SetTag("MORE_CONTEXT_ACTIONS")`.
- **Use `Menu.ModifyMenu("MORE_CONTEXT_ACTIONS", function(owner, rootDescription, contextData) ... end)`.**
  It runs inside `securecallfunction` (`Blizzard_Menu/Menu.lua:2708-2740`).
  - `owner` is the focused bag item button; `contextData` is always nil.
  - Slot: `owner:GetBagID()`, `owner:GetID()` (`ContainerFrame.lua:1825-1829`);
    `owner.hasItem` tells whether there's an item.
  - **Filter:** the same tag is used by professions, the spellbook, the
    character screen, raid frames and character select. Only add the entry when
    `owner.buttonContext == "ButtonContext_ContainerFrameItemButton"` and `owner.GetBagID` exists.
  - `ModifyMenu` calls the callback once immediately if that tag was already
    generated (`Menu.lua:2727-2736`), with a stale owner: guard against it.
  - A button's responder is called `responder(data, menuInputData, menu)` (`Menu.lua:892`).
- The menu only opens with no item on the cursor, not in repair mode, and no merchant open
  (`Gamepad_IsMoreActionsContextActionValid`, `ContainerFrame.lua:3108`).
- Alternative `PromptedBinding:AddMoreActionsEntry` exists, but the bag's binding is
  a local inside Blizzard code and writing into it risks taint on a footer that uses
  and equips items **(inferred)**. Don't.

## Mail window footer: DO NOT add bindings (tested 2026-10-13)

**Result in game (alpha1):** adding a prompted binding to `InboxFrame.gamepadFooter` /
`SendMailFrame.gamepadFooter` (`AddPromptedBinding` + `Finalize`) at login, and
registering our own window with `FrameControlsManager:FrameShown` plus our own
`CreatePromptedBindingFooter`, **tainted the whole gamepad input stack**. From login
on the game blocked `SetPreferredGamepadInteractTarget()` constantly, plus
`DescendStop()` / `RunBinding()` (jumping), `InteractUnit()`, `SpellStopCasting()`,
`ClearTarget()` and bag item use. Mailworthy must never write into these systems.
What works instead: a plain child `Button` of `MailFrame` (smart navigation picks up
descendant buttons of the focused panel by itself, see "Mailworthy windows" below).

What the source says (kept for reference):

- Inbox footer (`Blizzard_MailFrame/MailFrame.lua:272-283`): Select, Square Open All, Back.
  Send Mail (`1194-1208`): Square Send. Open mail (`598-608`): **Triangle = Options (taken)**.
  Triangle is free on Inbox and Send Mail.
- Add from an addon:
  ```lua
  local pb = GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_TOP, function(isDown) ... end, "Mailworthy")
  InboxFrame.gamepadFooter:AddPromptedBinding(pb)
  InboxFrame.gamepadFooter:Finalize() -- not Refresh: only Finalize re-reads the list
  ```
  The callback is `fn(isDown)`, fired on button-down. A late key draws after Back.
- `gamepadFooter` exists only after `SetupGamepad` (at `OnLoad` in gamepad mode,
  otherwise on the first switch to gamepad, `Blizzard_SharedXML/InputUtil.lua:54-60, 115-125`).
  `SetupGamepad` can't be hooked (captured with `GenerateClosure`). **Hook
  `InboxFrame:FocusGamepad` / `SendMailFrame:FocusGamepad`** instead (called by name,
  `MailFrame.lua:91`), idempotently, and again after `INPUT_DEVICE_INTERFACE_TRANSITION`.
- Footer activation sets override bindings (`InputFunctionBinding.lua:45-50`): only
  `Finalize` / `Refresh` out of combat. Callbacks run unsecured from a shared
  `InputFunctionBindingButton_PAD4` **(inferred)**; fine for mail, which isn't protected.

## Mailworthy windows in smart navigation

**Don't register** (tainted gamepad input in alpha1, see above). Use plain buttons
inside a Blizzard panel the game already focuses (alpha2: our window is a child of
`MailFrame` at the mailbox). The recipe below is Blizzard's own, for reference only.

`Blizzard_GamepadSharedUtility/FrameControlsManager.lua`, `Blizzard_GamepadSmartNavigation/`

1. **Window cycle (L2/R2):** `ShowUIPanel(f)` (returns early when protected calls
   aren't allowed) or `GamepadMode.FrameControlsManager:FrameShown(f)` in `OnShow`
   and `:FrameHidden(f)` in `OnHide`. Windows are ordered by screen x.
2. **D-pad:** focusing runs `SmartNavigation:HandlePanelOpen(f)`, which picks up
   visible Buttons, EditBoxes, mouse-scripted frames and frames marked with
   `SmartNavigation_MarkFrameFocusable` (`Utility.lua:196-206`). Also
   `SmartNavigation_MarkFrameIgnored`, `SmartNavigation_MarkFrameSubSection` +
   `EnterFocusGroup`, `OnSmartNavSelect` / `OnSmartNavDeselect`.
3. **Cross** = `SmartNavigation:Click()` -> `btn:OnSmartNavClick()` or mouse down/up.
   **Circle** = `f:SmartNavigationCloseHandler()` (return true to consume), else
   `f.CloseButton`, else a button named `*CloseButton` (`SmartNavigation.lua:1500-1558`).
4. **Footer:** `f.gamepadFooter = GamepadSharedUtility.CreatePromptedBindingFooter(f, "MWFooter")`,
   `AddStandardSelectPrompt()`, `AddPromptedBinding(...)` (Square / Triangle),
   `AddStandardFrameControlManagerBindings(f)` (L2/R2 hints), `AddStandardBackPrompt()`,
   `Finalize()`. `f:FocusGamepad()` -> `ShowAndActivateBindings()`,
   `f:UnfocusGamepad()` -> `HideAndDeactivateBindings()`. Set
   `f.useFooterJumpHints = true` and `f:GetJumpHintLabel()`.

Risk **(inferred)**: taint in shared tables (`FrameControlsManager.shownFrames`,
`SmartNavigation.activePanels`) while a Blizzard window that uses or equips
items (bags) is open, especially entering combat.

## Button symbols

- `C_InputInterfaceStyle.GetCurrentStyle()` only says mouse/keyboard vs gamepad.
- The set comes from `C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID()).labelStyle`
  via `InputDeviceIconSetManager:GetActiveGamepadDeviceIconSet()`: "Shapes" =
  PlayStation, "Generic" / "Letters" = Xbox, "Reverse" = Switch.
- In text: `CreateAtlasMarkup(InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture(GAMEPAD_FACE_TOP), 16, 16)`;
  re-render on `InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(cb, owner)`.
- As a widget: `InputIconTextureFrameTemplate` + `:SetInputKey(key)` (updates itself),
  or `InputPromptOneIconWithTextTemplate` + `:SetPromptInputIconKey(1, key)` / `:SetPromptText(label)`.

## Mail and auction house

**Measured 2026-10-13:** postage is a flat **30c per attached item** (5 items = 1s 50c;
30c with none). Deposit = **floor(vendor value of the stack x 5%) x 1 / 4 / 12** for
12h / 24h / 48h, the same for commodities and items (Linen Bandage x20, vendor 200c:
10 / 40 / 120c), and `CalculateCommodityDeposit` / `CalculateItemDeposit` answer even
with the AH closed (0 for items the client hasn't cached yet).

- Send button runs `SendMail(name, subject, body)` (`MailFrame.lua:1271-1273`);
  attachment buttons call `ClickSendMailItemButton(id)`. `ATTACHMENTS_MAX_SEND = 12`.
  Postage is computed by the game (`GetSendMailPrice()`), not in UI code.
- AH sale mails: `GetInboxInvoiceInfo(index)` returns `invoiceType, itemName,
  playerName, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin, count,
  commerceAuction` (`MailFrame.lua:785`); `consignment` is the house cut.
- Deposits: `C_AuctionHouse.CalculateItemDeposit(itemLocation, duration, quantity)`,
  `C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, quantity)`, duration 1-3
  = 12h / 24h / 48h, nil when unavailable
  (`Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua`).
- Bag item buttons can be walked with `EnumerateValidItems` (`ContainerFrame.lua`).
