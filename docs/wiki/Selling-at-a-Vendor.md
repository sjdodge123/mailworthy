# Selling at a Vendor

The **V** tag means "a vendor pays more for this today". At a merchant, Mailworthy sells those for you, one press at a time.

## How

At any merchant, a **Mailworthy: sell V (N)** button sits under the merchant window. Press it (or `/mw vendor`; **Triangle** on a controller while the merchant window has the focus) and a window lists every **V** stack in your bags with what the vendor pays for it.

**Sell** sells exactly that list:

- **12 stacks a press**, the size of the merchant's Buyback tab, so one press can always be bought back. More than 12? The window says how many are left; press Sell again.
- Each slot is checked again right before it sells: if the item moved, changed or got locked, it's skipped.
- It stops if the merchant window closes or combat starts.
- Nothing is ever sold without the press.

## What's on the list

Only what the bag tags call **V**, valued the way the tags are: items the auction house prices under a vendor, grey junk, and your [[vendor pins|Pins]]. Never on the list:

- locked items (lock one to keep it off: Alt+click, or L3), quest items and what a quest asks for, conjured items, items in use, profession tools;
- soulbound items, unless you vendor-pinned them;
- anything a friend's binding takes (its tag is **F**, not V);
- **anything another player mailed you**: it may go back to them with [[Return to Sender]]. The window says how many V stacks stayed for that reason.

## Switches

`/mw feature vendorButton off` removes the button and the window, `/mw feature padVendor off` gives Triangle back to the game at a merchant (then `/reload`).
