# Lab Wizard 2 — design spec

Direction **C · The Store Room**. This file is the contract I build against: the jar
maths, the gestures, the motion. No database changes are required for any of it.

---

## 1. The jar — how the level is decided

The jar answers one question: **"how much of this do I have left, relative to how much
it holds?"** It is a fraction, so it is unit-agnostic — 500 mL and 32 drops behave the
same way.

Two separate things are being shown, and keeping them apart is what makes it work:

| What | Decided by | Shown as |
|---|---|---|
| **Level** (how full the jar looks) | amount ÷ capacity | liquid height + 5 ticks |
| **State** (does it need attention) | your order level | colour + flag word |

They are deliberately independent. A 500 mL bottle with an order level of 300 can sit at
60% full *and* be flagged "order" — because that's the truth: it's more than half full
and it's still below where you want it.

### Capacity

```
capacity = max(initial_quantity, quantity)
fill     = quantity ÷ capacity        (clamped to 0–100%)
```

`initial_quantity` is what you had when the item was created — the best available
"this is a full jar" reference. Taking the **max** with the current quantity means the
jar self-heals: buy a bigger bottle and restock to 800 on an item that started at 500,
and the jar reads full rather than overflowing past the lid.

**No database change.** The capacity is computed for display only; `initial_quantity` is
never rewritten, so the web app keeps seeing exactly what it expects.

Fallbacks, because old rows can have `initial_quantity = 0`:

- `capacity > 0` → normal.
- `capacity == 0` and `quantity > 0` → jar renders full. We have no reference for "full",
  so claiming a fraction would be inventing one.
- `capacity == 0` and `quantity == 0` → empty jar outline, 0 ticks.

### State — including items with no limit set

Your rule, exactly as you said it: **an item with no order level shows as fine until you
set one.**

| Condition | State | Colour | Flag word |
|---|---|---|---|
| `quantity <= 0` | **empty** | berry red | `empty` |
| limit set (`> 0`) and `quantity <= limit` | **low** | clay | `order` |
| limit not set (`0`) | **fine** | sage | `set limit` (quiet nudge, not a warning) |
| otherwise | **fine** | sage | — |

One exception to "no limit means fine": **quantity 0 is always empty**, even with no
limit set. Zero needs no threshold to be unambiguous, and a silent zero would be the
worst possible result.

The nudge matters — it's how the app gets smarter over time instead of staying
permanently blind. See §3.

### The threshold notch

When a limit is set, a fine hairline is drawn across the jar at the height where "order"
begins — `limit ÷ capacity`. You can then see *both* facts at once: how much is left,
and how far above the line it is. If `limit >= capacity` (a limit set higher than the
bottle) the notch pins to the top edge and the row flags as soon as stock drops below it.

### Ticks

Five segments, 20% each, rounded **down** — so 90% reads as 4 ticks and a nearly-full
jar, never as "full". One exception: any liquid at all guarantees at least 1 tick, so a
jar can't look empty while it isn't.

For apparatus counted in whole pieces, ticks become individual units when capacity ≤ 6 —
so "3 of 5 beakers" is literally 3 ticks, not a percentage.

### Dashboard counts

"3 need a look" counts only items that are empty, or low **against a set limit**. Items
with no limit are never counted as needing attention — otherwise the number cries wolf
and you stop trusting it.

---

## 2. Gestures

| Gesture | Where | Does |
|---|---|---|
| **Swipe right** | any row | Log **use**. Cross a threshold → tick; release → opens the amount sheet pre-filled with last amount used for that item |
| **Swipe left** | any row | Log **restock** |
| **Full swipe** | any row | Commits with the pre-filled amount, no sheet |
| **Tap** | row | Detail sheet — history, QR, edit, delete |
| **Long-press** | row | Quick actions wheel: use · restock · edit · QR · delete |
| **Tap the jar** | row | 30-day usage sparkline expands in place |
| **Pull down** | any list | Sync. The indicator is ink, not a spinner |
| **Pinch** | shelf | Smoothly interpolates the row from jar-card to dense text list and back |
| **Drag handle** | any sheet | Drag up to expand full height, down to dismiss; flick dismisses |
| **Swipe sideways** | undo bar | Dismiss the undo early |
| **Tap-to-focus** | scanner | Focus point; **long-press** = torch |
| **Predictive back** | Android | Already in the theme — sheet follows your finger on gesture nav |

Every commit gesture pairs with haptics: `selectionClick` when the swipe crosses its
threshold, `mediumImpact` on commit, `heavyImpact` on failure. You feel the action before
you see it.

---

## 3. Motion

Nothing moves without a reason. Every animation below either confirms an action or
explains a change.

| Moment | Motion | Timing |
|---|---|---|
| **Level changes** | Liquid surface does a damped sine wave that settles — drops with a slight overshoot, rises with a small splash | spring, ~450 ms, stiffness 180 / damping 18 |
| **Crossing into low** | Colour lerps sage → clay; `order` writes itself in left-to-right like pen | 300 ms, easeOut |
| **Hitting empty** | Single pulse 1.0 → 1.02 → 1.0. Not a shake, not a loop | 320 ms |
| **Number change** | Count up/down, tabular numerals so nothing reflows | 260 ms, easeOut |
| **List first paint** | Rows fade + rise 8 dp, 40 ms apart | easeOutCubic |
| **Sheet open** | Rises with slight overshoot; page behind dims **and** scales to 0.98, so paper lifts | 320 ms |
| **Saving a log** | A single ink checkmark stroke draws in, then the row settles | 220 ms |
| **Undo bar** | Slides up with the action's icon and a hairline draining over 5 s | 5 s linear |
| **Threshold notch appears** | Draws from the jar's edge inward when you set a limit — you see it land | 260 ms |
| **Pull-to-sync** | Ink line stretches, then snaps back and leaves a brief "synced" tick | 400 ms |
| **Report bars** | Grow with easeOutBack, staggered 55 ms | 400 ms + 55/bar |

**Reduced motion is a real setting, not an afterthought.** With it on (or Android's own
setting), every spring becomes a 0 ms cut, the wave stops, the stagger goes, and lists
appear instantly. The existing app already reads this — v2 keeps the same contract.

**Performance:** the wave only repaints while a level is actually animating, each row sits
in its own `RepaintBoundary`, and off-screen tabs stay frozen — the tab shell already
suspends tickers for hidden pages.

---

## 4. Undo, so gestures stay safe

Swipe gestures are fast, which means they're also easy to get wrong. Every action that
changes stock shows the undo bar for 5 seconds: one tap restores the previous quantity
*and* removes the log entry. This is the biggest gap between the current Android app and
the web app, and fast gestures make it non-optional.

---

## 5. Data safety rules

Carried over from the review, because they're design constraints, not just bugs:

1. Signing out with unsynced changes **warns and offers to wait** — it never silently
   discards them.
2. A refresh never overwrites something that hasn't uploaded yet.
3. Batch actions are all-or-nothing, or they say exactly what got through.
4. Deleting an item is one transaction — the history and the item go together or not at all.

---

## Status

**Built (shelf-first, as agreed):**

| File | What it is |
|---|---|
| `lib/core/widgets/jar_metrics.dart` | The jar rule. Pure logic, no widgets, unit-tested. |
| `lib/core/widgets/glass_jar.dart` | The jar itself, with the damped surface wave, the order-level notch and the pulse on empty. |
| `lib/core/widgets/shelf_row.dart` | One reagent: jar, ticks, quantity, flag. Swipe right to use, left to restock, long-press for the action wheel. |
| `lib/core/motion.dart` | Shared springs and timings, the row entrance stagger, and count-up. Honours reduced motion everywhere. |
| `lib/core/theme/app_theme.dart` | Direction C. A `LabPalette` theme extension so light and dark lerp instead of switching. |
| `lib/features/shelf/presentation/shelf_screen.dart` | The shelf: header, summary, search, list, empty state, undo bar, item sheet, add sheet, menu. |
| `lib/features/shelf/presentation/action_sheet.dart` | Log use / restock, pre-filled with the amount you usually use, with a live jar preview. |
| `lib/features/auth/presentation/auth_screen.dart` | Sign in / sign up, same Supabase account as the web app. |

**Deliberately not built yet:** the scanner, reports, apparatus, and the QR label
printing. They come after the shelf has been in your hands — the shelf is where the
design either works or doesn't, and there's no point porting the rest of a screen
language you might still want changed.

**Known gap in this batch:** undo currently records a compensating action (a "use"
followed by an "undo" restock) rather than deleting the original log entry. It gets the
quantity right and leaves an honest audit trail, but the reports will show the pair.
Proper log deletion needs the repository work below.

**Still to do from the review, carried as design constraints:** keep the outbox across
sign-out, merge rather than replace on refresh, make batch actions atomic, and make
deletes transactional.
