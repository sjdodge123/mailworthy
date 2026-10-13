# Mailworthy agent rules

Mailworthy is a WoW Forever addon (`## Interface: 16001`). The design lives in
`docs/PLAN.md`; read it before changing behaviour.

## Safety (STRICT)

- Mail goes **only** to the saved bank alt shown in the preview, and only after
  the player presses Send. Never attach money. Never mail an item that is
  locked, soulbound, a quest item, on the never-mail list or unpriced.
- Re-check each slot right before attaching it; skip anything that changed.

## Controller support (STRICT)

- Every window must be usable with a gamepad alone (see "Controller support" in
  `docs/PLAN.md`): navigation through `Nav.lua`, no right-click, modifier-click,
  drag, hover-only information or required typing.
- **Never call `SetFocus`** from addon code: in LedgerLink it set off a blocked
  `SetPreferredGamepadInteractTarget()` and crashed the client.
- Override bindings only while a window is open and out of combat; always clear them.

## Working rules

- Branches and PRs only; never push to `main`, never force-push.
- Never invent WoW API functions. Wrap anything unverified on the beta in
  `pcall` / nil checks and list it under "Beta unknowns" in README.md.
- In-game checks go into `/mw probe` (one copyable report), not lists of `/dump` lines.
- Before every push: `eval "$(luarocks --lua-version=5.1 path)"`, then
  `busted --lua=luajit` and `luacheck .`.
