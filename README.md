# AE2 OC GTNH Pattern Manager

OpenOS program for GTNH 2.9, with a **160×50 color touchscreen UI**. Scan an ME
interface, review duplicate-input changes, then apply them. The first occurrence
of an item stays unchanged. Subsequent occurrences get unique names, starting
over for each pattern. Stack quantities and recipe outputs are preserved.

The **History** tab shows recent operation reports. **Maker setup** configures
pattern-maker modes in this same application: user-selected destinations and
remote donor banks, capacity checks, reuse and sorting previews. The recipe
library is a compact material/form/rule matrix, with shared semantic rules and capability sets. See
[PATTERN_MAKER.md](PATTERN_MAKER.md) for scope and extension contracts.

## Machine setup

1. Install a **tier 1 or better Data Card**, keyboard, tier 3 GPU/screen and OpenOS.
   A database upgrade is **not required**. The renamer works with 2 MB RAM;
   large maker previews use the stated Magical Memory setup. The entire deployed
   application and matrix occupy about 0.5 MB, below the 4 MB disk cap.
2. Connect an **ME Interface Terminal** through an adapter. The target, buffer,
   and rename interfaces must be visible through this terminal on the same AE
   network. Give the target its exact name, e.g. `Advanced Assline (1)`.
3. Name a directly adapter-connected interface **`OC Buffer`**. Fill it with
   disposable **encoded processing patterns**. Their existing recipes are
   overwritten when creating missing rename recipes. Blank patterns and crafting
   patterns cannot be converted by this API and are not counted as donors.
4. Keep the buffer disconnected from machinery that could execute its temporary
   recipes. Leave one empty pattern slot for editing, or supply enough donors
   that installing a new rename recipe frees a slot first.
5. Create the rename interfaces, e.g. `Rename NAME_1`, `Rename NAME_2`, etc., with
   machines configured to perform the corresponding item renaming. The program
   writes processing patterns; it does not configure or operate those machines.
6. Install with the commands below, then run `/home/assline.lua`. Set names in
   **Settings**, enter the target, and **Scan**. Review **Input changes** and
   **Rename recipes**, then select **Apply preview**.

## Install and update with wget

The OpenOS computer needs an Internet Card for downloads. Run:

```sh
wget -f https://raw.githubusercontent.com/Contomo/AE2_OC_GTNH_PatternManagerScript/main/dist/install.lua /tmp/assline-install.lua
/tmp/assline-install.lua https://raw.githubusercontent.com/Contomo/AE2_OC_GTNH_PatternManagerScript/main/dist
/home/assline.lua
```

Updates remember the installation's URL:

```sh
/home/assline.lua --check-update
/home/assline.lua --update
```

If the repository or branch changes, set the new channel with
`/home/assline.lua --update NEW_BASE_URL`. The installer also accepts a custom
installation directory as its second argument; its launcher is `<directory>.lua`.

The installer downloads a complete release into a staging directory, checks each
file's byte count, Adler-32 checksum and Lua syntax, then switches the active
release. Failed downloads leave the installed release active. It retains one
previous release and recovers the previous pointer after interrupted activation.
Code lives under `/home/assline/releases/<release-id>/`; the launcher remains
`/home/assline.lua`. Settings, history and recovery files keep their existing
`/home/assline.*` paths. Updating does not operate on AE interfaces.

Source and deployed Lua files are readable. There is no minification or paste-size
limit. For debugging, inspect the active release's `assline_app.lua`; its source
sections are named in comments. `assline_data.lua` is a single readable, lazily
loaded material matrix. The installed probe is available at
`/home/assline/releases/<release-id>/interface_probe.lua`.

NBT access must be enabled in the OpenComputers configuration:
`allowItemStackNBTTags`. If NBT is hidden or an API is unavailable, the program
stops with a visible error instead of dropping item properties.

## Visible in the manual terminal, but not found by OC

The upstream implementations checked during troubleshooting do **not** have
identical visibility. AE's manual terminal follows pattern provider/repeater
connections into other grids. OC's terminal driver searches its own grid and
explicitly filters out P2P **output** interfaces. Its name lookup and transfers
both use that filtered list, so changing the Lua name lookup cannot expose an
interface excluded by the driver. P2P inputs are not excluded by this particular
filter. Hidden interfaces are also filtered by OC.

Connect the adapter's terminal directly to the AE grid containing the actual
pattern-holding interface / P2P input. The buffer and rename destinations must
also be accessible on that grid for the current single-terminal workflow. A
provider/repeater link alone does not give this OC driver the GUI's reach.
This is a visibility limitation, not evidence that every dual interface is
unsupported.

To inspect the installed version's actual behavior, paste
**[interface_probe.lua](interface_probe.lua)** into `/home/interface_probe.lua`
and run it. It uses your saved target/buffer names, tests exact lookup, and lists
names and locations seen by **each connected terminal**. It needs no Data Card
and performs no transfers or edits. Output is saved to
`/home/interface_probe.txt`; the diagnostic file is replaced on the next run.
Version 2 uses `getAll(false)` for exact lookups and the full name list. The old
probe's iterator still loaded pattern NBT despite its "no pattern NBT" heading,
which could exhaust Lua memory on a Large Molecular Assembler. The new probe
omits occupied-slot counts because those require reading patterns.
You can override the target with:

```text
/home/interface_probe.lua "Advanced Assline (1)"
```

Keep `(1)` if it is part of the custom name. The diagnostic quotes exact API
names rather than stripping suffixes or selecting a similarly named interface.
Its missing-entry report alone cannot distinguish a remote grid, a P2P output,
a hidden interface, or a name mismatch.

Sources: [manual terminal grid traversal](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/master/src/main/java/appeng/container/implementations/ContainerInterfaceTerminal.java)
and [OC terminal filtering](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterfaceTerminal.scala).

## Names and settings

The default names are literal `NAME_1`, `NAME_2`, etc., with a rename interface
for each suffix. Both templates can be edited in Settings.

| Setting | Default | Meaning |
| --- | --- | --- |
| Target (main page) | `Advanced Assline (1)` | Exact, unique interface name |
| Buffer interface | `OC Buffer` | Exact, unique name of the directly connected buffer |
| Item name template | `NAME_{n}` | Literal `NAME_1`, `NAME_2`, etc. |
| Rename interface template | `Rename NAME_{n}` | `Rename NAME_1`, `Rename NAME_2`, etc. |
| Usable buffer slots | `9` | Pattern slots available in the buffer |
| Usable rename slots | `9` | Available slots on each rename interface |
| Component addresses | blank | Automatically use the single component of each type |
| Pause work below energy % | `25` | Stop component work and wait for recharge |
| Resume work at energy % | `75` | Continue the same operation after recharging |

For item-specific display names, change Item name template to `{label}_{n}`.
`{label}` expands to the original item's display name; `{n}` is the suffix number.
For one rename interface per item, use `Rename {label}_{n}`. A constant interface
name also works for machines that can handle all required rename operations.
Several rename interfaces can share the same name; free slots are allocated
across them in deterministic location order.

Set usable slots to **36** only where all four pattern rows are available. The
default 9 avoids placing recipes into inactive expansion rows. The target scan
uses all slots exposed by the terminal, including sparse/expanded pattern slots.

If several terminals, directly connected interfaces or Data Cards are present,
paste the intended component's full address or unique prefix into Settings.
Multipart buffers automatically use the side reported by the terminal. Keep a
distinctive pattern in the buffer during setup so its inventory can be matched
against the direct component; two identical inventories alone cannot prove
which physical interface an adapter controls.

## Preview and apply

Example inputs:

```text
1:   1 Samarium Rod
2: 128 Fine Europium Wire
3: 128 Fine Europium Wire
4:  64 Fine Europium Wire
```

Inputs 3 and 4 become `128 NAME_1` and `64 NAME_2`, still the same underlying
Fine Europium Wire item. Corresponding processing patterns turn `128 Fine
Europium Wire -> 128 NAME_1` in `Rename NAME_1`, and `64 Fine Europium Wire ->
64 NAME_2` in `Rename NAME_2`.

- Duplicate detection compares registry name, damage and complete item NBT;
  amounts do not affect identity. Different materials that share a label are
  distinct. Other NBT, including lore, is preserved when changing `display.Name`.
  For GTNH's NBT encoder, typed string wrappers are recursively converted to
  plain strings before encoding; the checked upstream encoder otherwise silently
  drops them. Numeric/list/compound types are retained, and the complete result
  must pass decode-and-compare verification before any pattern mutation.
- Numbering restarts for every pattern. Already-used generated names are skipped
  within that pattern to avoid collisions. Scanning a completed pattern again
  does not keep adding suffixes.
- Only processing-pattern **item inputs** are renamed. Outputs, fluids, known
  fluid packet/drop items and crafting patterns are left as they are.
- Existing rename recipes must have exactly one input and one output, matching
  item identities and a positive 1:1 quantity ratio. An existing `64 -> 64` recipe
  can supply a `128` input. New recipes use the first requested quantity for each
  item/name pair. Reused batch sizes may cause normal AE overcrafting.
- Missing interfaces, insufficient donor patterns, and missing free slots appear
  as blockers. Scan does not move or edit any pattern.
- Apply rescans to check the preview. It installs and verifies missing rename
  recipes first, then moves each affected target pattern into the buffer, edits
  only its duplicate inputs, verifies it, and returns it to its original slot.
  Every transfer has an explicit destination slot.

Keep machines idle and avoid concurrent pattern changes during Apply. AE has no
transaction or interface lock API; a batch can stop after earlier patterns have
successfully completed. All setters and transfers are checked and read back.

## Energy and memory

Work checks `computer.energy()` / `computer.maxEnergy()` before AE/Data Card
calls and interface iterator reads. Below the pause threshold it waits, yielding
through `event.pull`, until the resume threshold is reached. The status line
shows the wait; **Escape** cancels it. There is **no fixed call delay** when
energy is sufficient. These readings cover the OC computer's connected energy
network, including capacitors on that network; they do not measure AE power.
Existing saved settings retain their values. With many capacitors, recharging
from the default 25% to 75% can take a long time; the thresholds are editable.

After each Scan, Apply or Recover (including a caught error), the program appends
a timing summary to `/home/assline-perf.log`. It records starting and ending
charge and free memory, total time, energy-sample count and time, recharge pauses,
`event.pull` yields and wait time, plus call counts and timings by AE/Data Card
method. `other time` is the remainder, including Lua planning, disk I/O and UI.
Open **History** for recent reports, newest first, with normal preview scrolling.
It loads only the last 16 KB when opened and releases those lines when leaving.
Use `edit /home/assline-perf.log` for the full log, which resets above 64 KB.
An abrupt computer blackout can interrupt a report before it is saved.

If energy keeps falling below half the pause threshold, or does not increase for
30 seconds, work stops with an error. A pending pattern operation stays saved
for Recover. This protects the workload; it cannot keep a computer powered if
its supply cannot sustain idle consumption or an individual call exceeds the
remaining buffer. Percentage checks use the OC energy buffer, not AE power.

Repeated item identities and verified renamed NBT reuse small, bounded caches
within a work session. Caches and the progress callback are released after work,
including caught errors. Quit also clears preview/history/editor references and
restores the screen. Program state is local; shared OpenOS libraries stay loaded
normally. No global-state leak was found during this review. Free-memory readings
are taken during the operation, before cleanup/automatic collection, so they are
diagnostics rather than proof of a leak.
Unchanged UI regions are not repainted on every event, reducing GPU work.
The program does **not** call `collectgarbage`: OC does not expose it. Unneeded
references are released and OC performs collection during normal yields.

## Recovery and files

Before each operation the program writes its intent and the original pattern to
`/home/assline.pending`, flushes it, and verifies the saved bytes. If interrupted,
**Recover** finishes that one recorded operation. It checks whether a transfer
already completed, accepts only expected partial edits, and stops on unexpected
pattern changes or an occupied destination. After recovery, **Scan** again to
continue the remaining work. Hardware and buffer selection must still match the
saved record.

Do not move buffer or destination patterns while recovery is pending. If recovery
reports an unexpected edit, inspect the indicated pattern and the saved record;
it does not guess which foreign changes to overwrite. The screen shows the full
error in the scrollable preview.

| File | Purpose |
| --- | --- |
| `/home/assline.cfg` | Saved text settings and target |
| `/home/assline.pending` | Active operation, retained on failure; removed on completion |
| `/home/assline.last` | Latest submitted plan, including original affected target/donor patterns |
| `/home/assline-perf.log` | Timing/charge summaries; rotates above 64 KB |
| `*.tmp` | Temporary files used while saving |

The latest-plan file is an inspection/backup record, **not an automatic Undo**.
Completed rename recipes and edits stay applied if a later operation stops.
Recovery files are bounded to 400 KB each; the timing log is rotated.

## Cable pattern feasibility

The adjacent inventory exposed by a GTNH ME Interface is its **nine storage
slots**, not its pattern slots. A transposer can transfer encoded patterns into
that storage inventory, but that does not install them as crafting recipes. OC's
terminal `send` transfers between interfaces' internal pattern inventories only;
its pattern setters edit an encoded pattern already in one of those slots. Thus
stacked donor patterns in a chest cannot feed hundreds of new recipes through
the proposed transposer route.

Crafting patterns themselves can be edited by the OC setters, provided the
donor is already an encoded **crafting** pattern in the directly connected
interface. The `crafting` flag lives in the pattern's NBT; the setters change
the input/output lists but cannot turn a processing donor into a crafting
donor. AE also checks the 3×3 input grid against a real crafting recipe and
derives the output from it. Empty grid positions therefore matter, and every
new recipe still needs a physical encoded pattern installed in a pattern slot.

OC can use a descriptor's registry `name`, `damage`, count, and NBT to paint
pattern ingredients. It has no NEI recipe search. For arbitrary GTNH items, a
reliable catalogue needs exact descriptors from stocked items, existing
patterns, or a known ID mapping; display names alone are not enough. An OC
database upgrade can store/copy descriptors, but cannot manufacture encoded
patterns or expose the interface's internal pattern slots to a transposer.

Sources: [GTNH interface inventories](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/master/src/main/java/appeng/helpers/DualityInterface.java),
[OC terminal transfers](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterfaceTerminal.scala),
[OC pattern setters](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/internal/PatternEnvironment.scala),
[AE crafting pattern validation](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/master/src/main/java/appeng/helpers/PatternHelper.java).

Touch fields/buttons or use **S** to scan, **A** to apply the reviewed preview,
**Q** to quit, **Escape / Cancel work** to cancel an active operation, and mouse wheel / Page Up / Page Down to scroll. Text fields
support paste, arrows, Home/End, Backspace/Delete, Ctrl+A, Enter and Escape.
Clicking a field places the cursor at that position without selecting its text;
click again to reposition or clear a selection. Only Ctrl+A selects everything.
Settings Save commits all
settings; Cancel discards the draft. Editing the main target saves it immediately
when accepted and clears the old preview.

## Build and tests

Sources live in `src/`, `lib/` and `maker/`. `build.js` embeds each shared service
once in readable `assline_app.lua`, copies the readable matrix and probe, and
produces the **`dist/` download directory** and `deployment.json`. `install.lua`
is both the wget bootstrap and the installed updater. `launcher.lua` is the
stable entry point. The combined application/library has an enforced **4 MB** cap.
There is no luamin dependency and no 64 KB file restriction.

```powershell
.\build.ps1
```

Or, with Node on PATH:

```text
npm install
npm test
```

Fengari runs the application, planner, mode and installer contract tests. It can
use the already-cached CLI or the local npm dependency. Python is needed for the
catalogue/compiler tests. Installer tests use the actual built file bytes and
checksums, with mocked OpenOS I/O and HTTP; they cover install/update, unchanged
releases, manifest-only checks, partial downloads, corrupt files, invalid Lua,
disk limits, failed activation and interruption recovery.

Publish **all files in `dist/`, including `release.manifest`, in the same Git
commit**. Their contents determine the release ID, so subsequent builds with no
changes do not trigger downloads. Do not publish local settings, journals or
research caches. The desktop-only test fixtures in `tests/lib/` are not deployed.

These are desktop mocks checked against upstream APIs, not an in-world GTNH run.
Actual AE network tick timing and physical renamer behavior still need an in-game
check with a small set of disposable patterns. Normal work polls the UI about every
100 ms without fixed sleeps at full power. Tabs and scrolling remain usable;
mutating controls and configuration are disabled while a task is active.
Quit releases previews, work caches and program-owned module cache entries.

Apply validates only the rename recipes used by the next target, using one fresh
snapshot per distinct interface. These snapshots expire after that target; they
are not a persistent cache that hides later changes. Donor editing clears only
nonempty trailing NBT cells, in reverse order, with semantic readback. Empty
padding can remain: [AE's processing pattern parser](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/master/src/main/java/appeng/helpers/PatternHelper.java)
ignores empty compounds when condensing inputs and outputs.

API sources checked:

- [Interface terminal lookup, iterator and zero-based transfers](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterfaceTerminal.scala)
- [Pattern setters: item descriptors, one-based indexes and list-removing clears](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/internal/PatternEnvironment.scala)
- [Multipart interface's implicit side argument](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterface.scala)
- [Data Card typed NBT encoding](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/server/component/DataCard.scala)
- [Item descriptor and NBT access](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/vanilla/ConverterItemStack.scala)
- [Typed NBT representation](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/vanilla/ConverterNBT.scala)

The supplied `component_probe.txt` established the available in-world methods.
