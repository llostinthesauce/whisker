# Whisker Stats — Design Spec
**Date:** 2026-06-12  
**Status:** Approved

## Overview

Add usage statistics to Whisker: a compact 3-tile strip on the main recorder screen (replacing the existing status badge panel), plus a full stats sheet accessible by tapping the strip. Stats are computed on the fly from the existing `HistoryStore` — no new persistence layer.

---

## Data Layer

### `WhiskerStats` (new value type)

```swift
struct WhiskerStats {
    let totalWords: Int
    let transcriptionsToday: Int
    let totalAudioSeconds: Double
    let totalTranscriptions: Int
    let averageDurationSeconds: Double
    let longestSessionSeconds: Double
    let perEngineBreakdown: [(engine: String, count: Int, words: Int)]

    static func compute(from entries: [DictationResult]) -> WhiskerStats
}
```

- `totalWords`: sum of `entry.displayText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count` across all entries
- `transcriptionsToday`: entries where `Calendar.current.isDateInToday(entry.createdAt)`
- `totalAudioSeconds`: sum of `entry.rawTranscript.durationSeconds`
- `perEngineBreakdown`: grouped by `entry.rawTranscript.engineName`, sorted by count descending
- All computed purely from the passed `entries` array — no side effects, fully testable

### `HistoryStore` addition

```swift
var stats: WhiskerStats { WhiskerStats.compute(from: entries) }
```

Reactive: any view observing `historyStore` recomputes stats automatically when `entries` changes.

---

## Main Screen Changes

### What's removed

The existing `statusPanel` in `RecorderView` (the 4-badge row: model / cleanup / timeout / keyboard) is **removed from the main screen**. These values remain accessible in Settings.

### What replaces it

Two stacked elements between the toolbar and transcript area:

**1. Server status row** (replaces top half of old panel — one line only):
- Colored dot (green/blue/red/gray) + text label (`"server ready"` etc.)
- Trailing: server host label (e.g. `"matti → 100.x.x.x"`)
- Same `foam` background, no badges

**2. Stats strip** (new — below the server row):
- 3 equal tiles: **Words** · **Today** · **Audio**
- Each tile: large number in `deepOcean`, caption label in secondary
- Trailing `chevron.right` icon signals tappability
- `foam` background + `pacific` border — consistent with existing `StatusBadge`
- Entire strip is a `Button` that presents `StatsView` as `.sheet`
- Numbers update reactively from `historyStore.stats`

**Formatting:**
- Words: `12,847` (integer with thousands separator)
- Today: `3` (plain integer)
- Audio: `4.2 hrs` (if ≥ 1 hr), `42 min` (if ≥ 1 min), `42s` (if < 1 min)

---

## Stats Sheet (`StatsView`)

Presented as `.sheet` from the stats strip tap. Drag-to-dismiss. No explicit close button.

### All Time section — 2×2 card grid

| Words | Audio |
|---|---|
| 12,847 | 4.2 hrs |

| Transcriptions | Time Saved |
|---|---|
| 142 | ~5.3 hrs |

- **Time saved** = `totalWords / 40` minutes (40 WPM typing baseline, same as WisprFlow/SuperWhisper). Displayed with `~` prefix to signal approximation.

### Per Session section — 2×2 card grid

| Average | Avg Words |
|---|---|
| 1m 48s | 90.5 |

- Average and longest use `m:ss` formatting for durations ≥ 60s, plain `Xs` below that.
- The Per Session section is a **2-tile row** (Average duration + Avg words) followed by a **single full-width tile** (Longest session). No empty placeholder slot.

### By Engine section — plain list

```
parakeet-tdt-0.6b-v3    98 sessions   11,240 words
Qwen3-ASR-0.6B-4bit     31 sessions    1,340 words
```

- Sorted by session count descending
- Engine name in primary, counts in secondary/trailing
- Only shown if `perEngineBreakdown` has entries

### Styling

- Sheet background: `WhiskerTheme.appBackground`
- Cards: `foam` fill + `pacific` border (same as strip tiles)
- Section headers: uppercase caption in secondary, matching existing `Form` section style
- Tint: `WhiskerTheme.pacific` throughout

---

## New Files

| File | Purpose |
|---|---|
| `Whisker/Shared/Models/WhiskerStats.swift` | Value type + `compute(from:)` |
| `Whisker/Features/Stats/StatsView.swift` | Full stats sheet |

## Modified Files

| File | Change |
|---|---|
| `Whisker/Shared/Services/HistoryStore.swift` | Add `var stats: WhiskerStats` computed property |
| `Whisker/Features/Recorder/RecorderView.swift` | Replace `statusPanel` with server row + stats strip; add sheet presentation |

---

## What's Explicitly Out of Scope

- Streak tracking (requires per-day persistence beyond existing history)
- Time-period breakdowns (today / week / all time toggle)
- Charts or graphs
- Export/share of stats
