# Diagnosing a DiskRings hang on the Mac

Use this when DiskRings stops responding (spinning cursor, progress frozen, Stop doesn't react).
Both tools only **read** the running process; neither changes DiskRings, your files or settings.
Run them **while the hang is happening**, in Terminal.

## 1. `sample` (recommended, no sudo)

```bash
sample DiskRings 10 -file /tmp/diskrings-sample.txt
```

| | |
|---|---|
| What it does | Records DiskRings' call stacks for 10 seconds (every 1 ms) and writes a text report. Shows which function the main thread is stuck in. |
| Writes | `/tmp/diskrings-sample.txt` only (a few hundred KB to a few MB). |
| sudo | **No.** Works on your own processes. |
| Risks | DiskRings is paused for microseconds per sample; it keeps running. The report contains file/folder **paths** from your disk and function names; review before sharing. |
| Undo | `rm /tmp/diskrings-sample.txt` |

If "DiskRings" is not found, use its PID: `pgrep -x DiskRings`, then `sample <PID> 10 -file /tmp/diskrings-sample.txt`.

## 2. `spindump` (optional, needs sudo)

```bash
sudo spindump DiskRings 10 -file /tmp/diskrings-spindump.txt
```

| | |
|---|---|
| What it does | Like `sample`, but also includes kernel stacks and all threads' blocking reasons (useful if the hang is in disk I/O or a lock). |
| Writes | `/tmp/diskrings-spindump.txt` (can be several MB; owned by root). |
| sudo | **Yes** — asks for your admin password. Nothing else is changed. |
| Risks | Sampling for 10 s adds some CPU load. The report may include names of **other** processes and paths; review before sharing. |
| Undo | `sudo rm /tmp/diskrings-spindump.txt` |

## What to send

The `.txt` file(s). Do not send anything from `~/Library` unless asked.

## Known cause fixed in this build (P1, Oct 2026)

Main thread stuck in `SunburstView.rebuild → SegmentMarkers.annotate → FileNode.dominantCategory → categoryMix` (recursive whole-subtree walk per visible sector, with full-path string matching). Since this build the category mix / reclaimable data are precomputed once in the background (`TreeAnalysis`) and the view only reads cached values.
