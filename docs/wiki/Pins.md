# Pins

A pin means **"always bank this"** or **"always vendor this"**. Where a bank pin gets banked is your choice, per character: mailed to your bank alt (**BA**), or kept to bank on this character (**BH**).

## Pinning and unpinning

| How | Mouse / keyboard | Controller |
|---|---|---|
| In your bags | **Ctrl+Alt+click** the item | **R3** on the item |

Each press moves the pin on: **bank pin** → **vendor pin** → no pin. `/mw pins` lists your pinned items and where this character banks them. A pin is for **the item**, not the bag slot, and pins are saved for your whole account, so every character knows them.

## Bank on alt (BA) or bank here (BH)

Settings → **Pinned items** decides what pins do on this character, and switches every pin on it at once:

| Setting | What a pinned item does |
|---|---|
| **BA mail to your bank alt** (default) | Send mails it to your bank alt every time, whatever the auction house or your professions say |
| **BH bank here, on this character** | It stays in this character's bags, to go in its own bank. It's never mailed |

A character with **no bank alt**, and **the bank alt itself**, always bank their pins here: that's the only way the pin can be kept. The button and the tooltip say so.

Pinned items **always show their tag** (**BA** green or **BH** teal), on every character, and glow in the same colour while the Mailworthy window is open (Settings → **Lock glow: always** for all the time). A fresh pin glows for a moment anywhere. The item's row in the Mailworthy window and its tooltip use the same colour. See the colours in [[Your Bank Alt]].

## Vendor pins

The second press makes it a **vendor pin**: the item stays in your bags, never mailed, and shows the **V** tag (brown) on every character, whatever the auction house says. At a merchant, the vendor window sells it (see [[Selling at a Vendor]]). It works on soulbound items too, like an outgrown quest reward: those can't be mailed, but a vendor still buys them.

A vendor pin never touches a locked item, a quest's item, a conjured item, an item in use or a profession tool, and does nothing for an item no vendor buys.

## When a pin and your professions disagree

Pin something this character's own profession uses (Strange Dust on an enchanter) to the bank alt, and **the pin wins**: it's your decision, so Send mails it. A small window says so once, with three ways out:

- **Unpin it**;
- **Bank pins here (BH)**: every pin on this character stays here instead;
- **Don't show this again** (`/mw pinwarning on` brings it back).

With **This character keeps its profession materials: on my bank alt** (see [[Profession Materials]]) there's nothing to warn about: the materials go there anyway. Either way, the item's tooltip and its row in the Mailworthy window say "Your Enchanting uses it, but the pin wins" every time.

## What a pin never overrides

- A **lock** (see [[Item Locks]]): a locked, pinned item stays, glows blue, and its tooltip says it's pinned too.
- The other things Mailworthy never mails: soulbound and quest items, what a quest asks for, conjured items, items in use, profession tools (see [[What Stays in Your Bags]]). The glow's tooltip says which one keeps it.
- **[[Return to Sender]]**: with it on, a pinned item someone else mailed you goes back to them.
- A friend's binding never takes a pinned item, and the **Send by tag** switches never hold back or add a pinned item (see [[Settings]]).

A pin to the bank alt does override the price rules: a pinned green, or grey junk, goes even without Auctionator. It still waits for the item's data to load, and stays if a price lookup fails.
