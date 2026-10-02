# AE2 OC GTNH Pattern Manager

OpenOS program for GTNH 2.9, with a **160×50 color touchscreen UI**. Scan an ME
interface, review duplicate-input changes, then apply them. The first occurrence
of an item stays unchanged. Subsequent occurrences get unique names, starting
over for each pattern. Stack quantities and recipe outputs are preserved.

One application runs several programs through **Run program**: assembly-line
renaming, wire insulation, wiremill patterns for 1x wire and fine wire,
bending-machine patterns for plates, foil, sheet metal and springs, and Fluid
Shaper patterns for verified molten-fluid solid parts.
Navigation is on the left; Scan, Execute, Pause/Resume, Stop and Quit are at the bottom.
Settings has shared interfaces/hardware and a separate section for each program.
[Program architecture and recipe matrix](PATTERN_MAKER.md).
[Source files, generated outputs and shared services](SOURCE_MAP.md).

## Machine setup

1. Install OpenOS, a tier 3 GPU/screen, keyboard and a tier 1+ Data Card. An
   Internet Card is needed for installation/updates. Large recipe previews use
   the user's 16 MB Magical Memory setup. The deployed files occupy about 0.6 MB.
2. Connect an **ME Interface Terminal** to OC. All editor, donor and destination
   interfaces must be visible through this terminal on the same AE grid.
3. Name an adapter-connected interface **`OC Pattern Editor`**. It is the shared
   editor, and needs an empty pattern slot. Keep it disconnected from machinery
   that could execute temporary recipes.
4. Name one or more remote interfaces **`OC Pattern Buffer`**. Fill them with
   disposable encoded processing patterns. All matching interfaces and all their
   occupied slots are scanned; no direct connection or slot-count setting is
   required for these banks. Crafting donors are counted separately.
   A donor shortage is a warning: execution starts with the available processing
   patterns, then waits for refills. Refill any matching terminal-visible buffer;
   newly added matching banks are discovered too. Stop/Escape stops the wait; Pause/Resume suspends and continues it.
   Completed work is retained and reused by the next preview.
5. Configure destination names in **Settings**, under the appropriate program.
   All destination interfaces with a matching exact name participate. The editor
   and donor bank must have different names and must not overlap destinations.
6. **Run program** opens the chooser. Select a program, then **Preview selected**.
   Review the plan, donor budget and capacity. Destinations are assumed to have
   **36 usable slots each**; the preview states the minimum interface count.
   Verify the interfaces in game, select **Verify 36 slots**, then **Execute preview**.

Wiremill selects one input route per output: both default to **Ingot**. Fine wire
can instead use Rod or 1x wire. Only recipes present in the scrape are generated.
Wiremill, the insulator and the bending machine each have a **Pattern multiplier** setting, default
`1`. Enter a positive whole number: `256` makes a 1-ingot → 2-wire recipe request
256 ingots and produce 512 wires. The multiplier applies to every encoded input
and output in the selected recipe, including requested polymer/PPS.
Numeric settings accept case-insensitive decimal shorthand: `4k` means `4000`,
`4M` means `4000000`, and `1.5k` means `1500`. Values expand when saved; existing
whole-number and range checks still apply. Interface names remain unchanged.
**Settings > Tier multipliers** adds a shared tiered policy for every recipe
program. New installs start at LuV; existing installations keep **Fixed** until
you enable **Tiered**. Current progression and voltage reference tiers have
popup selectors covering ULV through MAX, including OpV.

The shared policy is exclusive: **Fixed** exposes per-program multipliers;
**Tiered** ignores those retained fixed values and exposes its curve and limits.
The generated curve has a current-tier batch, a maximum, and a number of tier
steps until that maximum. Choose geometric or logarithmic growth. The conservative
preset grows from 4x to 512x over seven steps (4, 8, 16, 32, 64, 128, 256, 512).
Changing your progression tier shifts the curve. The maximum is both its endpoint
and the final ceiling. Custom points and optional absolute tier overrides use
compact editable tables; blank overrides follow the curve.

Materials above progression default to **Skip**. Unclassified materials can use
**Recipe voltage**, **Fixed fallback**, or **Skip**. Voltage fallback is explicitly
an estimate, not a claim of earliest material accessibility. Missing voltage uses
the fallback multiplier. The separate voltage constraint can be disabled; when
enabled it caps batches and skips recipes above the selected voltage reference.
Cheap processing never increases a known high-tier material's budget.
Voltage constraint and future-material inclusion use single checkboxes. Blank
shared component addresses display muted `auto`; they remain blank in saved settings.

Tiered batches default to limits of 4096 items or 589824 mB per ingredient. The
whole batch shrinks together; stocked molds/circuits and omitted supplies do not
consume those limits. Effective tiers shows material budgets before these caps.

Fluid Shaper ingots require a native liquid-producing route in the full scrape.
Alloy synthesis counts; fluid extraction, remelting finished parts and unpacking
containers do not. Plasma cooling counts only with an independent liquid source.
Materials with both solid and native liquid routes remain eligible. This is recipe
evidence, not a check of which production routes your base has installed. Plates
and other shapes can still use extracted fluid. Existing ingot patterns excluded
by this check appear in Existing and must be removed manually to stop an already
installed extract/solidify loop.

The preview uses labels such as `30,720 EU/t (LuV)` with tier-colored text
blended at 50%, and explains exclusions in Excluded and Existing. Existing patterns
excluded by settings are kept. Selecting no recipes gives a non-executable preview.

Material tiers come from the pinned beta-3 questbook's item/ingredient lists,
side-chapter prerequisites and pinned GT ore placement rules. Dusts, ores,
optional ingredient lists and alternative forms count; icons/rewards/tools do
not. One-hop recipe evidence must be shared by all eligible alternative routes,
and must have material-creation evidence; chance byproducts and recycling are
excluded. These are availability estimates rather than an exact tech-tree solver.
`data/material-tiers.json` retains paths, recipes, dimensions and production
constraints for audit. Ore/recipe estimates are marked in the preview; remaining
materials follow the chosen unclassified policy. EU/t comes from the recipe export.
The insulator selects PVC pulp, small PVC pulp, PDMS pulp, small PDMS pulp, or
nothing. PPS sheets have a separate toggle. Normal piles use the scraped
four-cable batches; small piles and nothing use single-cable batches. The scrape
has **306 material/size candidates (51 materials x 6 sizes)**; the current
non-recycling-use check retains **183**. For example, normal
PVC uses 4 Annealed Copper wires + 1 PVC pulp ? 4 Annealed Copper cables.
Existing PVC On/Off settings migrate to Small PVC pulp/Nothing, preserving the
previous recipe choice. New installations default to normal PVC pulp.

The Patterns tab groups readable ingredients by destination and material, marks
CREATE/REUSE in color, and prints an interface location once per group. Capacity
shows space requirements. Existing lists every encoded pattern in the selected
destination interfaces, whether it matches or is kept, its final slot, and each
labeled sorting move. Excluded lists each selected output rejected by the recipe-use
check. Details contains buffer discovery and source
coverage. Buffer counts come from the terminal and include empty encoded
processing patterns. Ultimate processing patterns are recognized even without a `crafting` NBT tag.
**Export report** saves those diagnostics and the complete plan to
`/home/assline-preview.txt` for inspection or sharing. It does not execute the plan.
Details explains rejected donors, including substitution or invalid-pattern flags.
Unsupported tagged items are not donor patterns. Existing
processing recipes compare actual item IDs, input/output proportions, substitution flags and semantic NBT;
missing and empty ingredient NBT are equivalent.
Thus an existing 256 → 512 pattern matches a requested 1 → 2 recipe. It appears
as **RESIZE** when its batch differs from the configured multiplier, and its
existing pattern item is edited through the shared editor without using a donor.
Patterns already at the requested batch appear as **REUSE**. A different yield,
ingredient, ingredient NBT or substitution policy is still a different recipe.
Normal PVC's base batch is 4 wires + 1 pulp → 4 cables; multiplier `2` gives
8 wires + 2 pulp → 8 cables. The multiplier does not change the selected polymer.

The bending machine has ten independent output switches: 1x, 2x, 3x, 4x, 5x
and dense plates, foil, sheet metal, small springs and large springs. New
installations start with all ten on. Existing settings retain their selected
outputs; the three newly added switches start off until selected.
**Larger plate / foil input** chooses Ingot or 1x plate for 2x–5x and dense
plates and foil. 1x plates always use ingots. Sheet metal always uses 1x plates;
large springs use long rods. **Small spring input** independently chooses Rod or
1x wire. A route is generated only when that exact material and input appear
in the scrape. For example, foil yields four per ingot *or* plate; the ingot
route uses circuit 10 and the plate route uses circuit 1. Sheet metal uses
circuit 11. The circuits are **externally stocked** machine selectors, not
requested by the AE pattern. Plate-to-plate recipes that produce the chosen
output are included; alternatives such as double-plate → quadruple-plate are
outside this selector.
All pattern programs automatically skip an output form when the full recipe
export shows no path from that exact item to a non-recycling product. Converting
a plate into unused foil, or a double plate into another unused plate, does not
make it useful. The preview counts skipped routes. In the current export,
Cerium Foil, Lithium Chloride Foil and Lithium Chloride Plate are excluded.
Turning off 1x plates removes them from the desired plan without deleting existing
patterns, so another program can take over that route later. Each destination
name can be left blank when all of its output switches are off. Wire combining
remains unavailable.

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
and run it. It uses your saved target, editor and donor names, tests exact lookup, and lists
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

All settings live in `/home/assline.cfg`, schema 2. Accepting an edit with Enter,
clicking another field, changing page, or clicking Quit saves it. Esc discards
only the active edit. Old settings migrate into the shared/program sections;
obsolete slot limits are not carried forward.

| Section | Fields |
| --- | --- |
| Shared interfaces | Pattern editor name, new pattern buffer name, terminal/editor/Data Card addresses, energy thresholds |
| Assembly line renamer | Target interface, item-name template, rename-destination template |
| Wire insulator | Destination interface name, five-way polymer selector, request PPS |
| Wiremill | 1x wire and fine-wire destination names; separate input routes, default Ingot |
| Wire combining | Bare-wire destination, insulated-cable destination (future rules) |
| Bending machine | Plate, foil, sheet-metal and spring destinations; ten output switches, larger-plate/foil and small-spring input selectors, pattern multiplier |
| Fluid Shaper | An interface and inline enable switch per mold (including shared fluid/item pipe molds); molten fluid is requested, and the reusable mold stays in the machine. Settings use pages. |

Shared default names are `OC Pattern Editor` and `OC Pattern Buffer`. Component
addresses are optional when only one component of each type is connected.
Only the editor is directly connected to OC. Donor banks are remote name matches.
The terminal API does not expose destination capacity: plans use the agreed
36-slot assumption and require in-game confirmation before execution. Editor
slots are checked through its direct read API. No dummy moves are used to probe
capacity, and previews never change patterns.

The default assembly-line templates are `NAME_{n}` and `Rename NAME_{n}`.
`{label}` expands to the original item's display name; `{n}` is the duplicate
number. Constant rename-destination names work too. Multiple matching interfaces
are ordered by dimension/x/y/z/side; slots begin at zero in the terminal API.

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
  recipes first, then moves each affected target pattern into the editor, edits
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

After each preview, execution or continuation (including a caught error), the program appends
a timing summary to `/home/assline-perf.log`. It records starting and ending
charge and free memory, total time, energy-sample count and time, recharge pauses,
`event.pull` yields and wait time, plus call counts and timings by AE/Data Card
method. `other time` is the remainder, including Lua planning, disk I/O and UI.
Open **History** for recent reports, newest first, with normal preview scrolling.
It loads only the last 16 KB when opened.
Use `edit /home/assline-perf.log` for the full log, which resets above 64 KB.
An abrupt computer blackout can interrupt a report before it is saved.

If energy keeps falling below half the pause threshold, or does not increase for
30 seconds, work stops with an error. A pending pattern operation stays saved
for Continue last operation. This protects the workload; it cannot keep a computer powered if
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

**Pause** suspends execution at a component-call boundary; **Resume** continues the
same in-memory run. **Stop**, Escape and Quit finish the current journaled pattern
transaction before stopping. During sorting, they finish the current cycle so its
temporarily parked pattern returns from the editor. Completed changes remain applied.
Stopping while waiting for donors ends the wait without creating a transaction.

A stopped or interrupted execution keeps its program choice in `/home/assline.run`.
**Continue last operation**, available at the bottom of Programs/Preview, finishes
any interrupted transaction, then builds a fresh preview for the saved program
using current settings and interface contents. Review it and Execute to carry on.
Completed patterns are reused; an old full preview is never replayed blindly.
If the fresh preview has no remaining work, the saved run is cleared automatically.

Before each transaction the program writes its intent and original pattern to
`/home/assline.pending`, flushes it, and verifies the saved bytes. Sorting also
keeps a progress cursor. Continuation checks the hardware, fingerprints and expected
partial edits; it stops on foreign changes rather than overwriting them.

Continuation is optional. Read-only previews remain available with a saved operation.
**Stop saved** opens a discard dialog: it archives the saved records to
`/home/assline.abandoned` and clears the active continuation records. It does not
undo edits or move any patterns. If a failure left a pattern in the editor, it stays
there and the next scan treats that slot as occupied. Discard the old transaction
before executing a different plan; a clean stopped run can be replaced directly.

| File | Purpose |
| --- | --- |
| `/home/assline.cfg` | Shared configuration and per-program settings |
| `/home/assline.pending` | Active operation, retained on failure; removed on completion |
| `/home/assline.pending.step` | Verified progress through an active sorting stage |
| `/home/assline.run` | Saved program choice for optional continuation after Stop/restart |
| `/home/assline.abandoned` | Latest discarded transaction/run records; no automatic Undo |
| `/home/assline.last` | Latest submitted assembly-line plan or generator operation summary |
| `/home/assline-perf.log` | Timing/charge summaries; rotates above 64 KB |
| `*.tmp` | Temporary files used while saving |

The latest-plan file is an inspection/backup record, **not an automatic Undo**.
Completed rename recipes and edits stay applied if a later operation stops.
Active recovery files are bounded to 400 KB each. The combined discard archive is
bounded to 900 KB and replaces the previous archive; the timing log is rotated.

OC terminal `send` returns success and the destination slot; the executor checks
both, then reads the pattern back. Success alone does not prove that the slot is
enabled: AE2 keeps a 36-slot pattern inventory behind its capacity-card row limit.
A transfer into a disabled row can succeed while remaining invisible to the terminal.
Opening the interface GUI removes patterns from disabled rows and drops them.
All destinations must therefore have three capacity cards, as required by the preview.
If read-back fails, the error identifies the interface coordinates and zero-based
slot, distinguishes an absent pattern from a mismatched pattern, and retains the
operation. Add the missing cards before continuing; if the pattern dropped, return
that same encoded pattern to its saved editor slot rather than supplying a new donor.
Sources: [OC transfer and visible-row snapshot](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterfaceTerminal.scala),
[AE2 physical pattern inventory](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/master/src/main/java/appeng/helpers/DualityInterface.java),
[AE2 disabled-row removal](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/master/src/main/java/appeng/container/implementations/ContainerInterface.java).

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

Touch navigation, program cards, fields and bottom-row actions. **S** rebuilds the
current preview; **Q** quits; **Escape / Stop** stops active work at a safe boundary. Mouse wheel
and Page Up / Page Down scroll the preview and history. The scrollbar can also
be dragged using native OC `touch`, `drag`, and `drop` screen signals, or clicked
to jump to a position. Text fields support
paste, arrows, Home/End, Backspace/Delete, Ctrl+A, Enter and Escape. Clicking a
field places the cursor; only Ctrl+A selects all its text.

## Build and tests

All editable application and build sources live under `source/` (`app/`, `lib/`,
`tools/`, installer and launcher). `source/build.js` embeds each shared service
once in readable `assline_app.lua`, copies the generated matrix and probe, and
produces the **`dist/` download directory** and `deployment.json`. `source/install.lua`
is both the wget bootstrap and the installed updater. `source/launcher.lua` is the
stable entry point. The combined application/library has an enforced **4 MB** cap.
There is no luamin dependency and no 64 KB file restriction.

```powershell
.\source\build.ps1
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

Legacy `ae2fc:fluid_drop` ingredients are compared as fluids: one drop equals one mB,
with the fluid name read from the ingredient's `Fluid` tag. Both `Count` and `Cnt`
layouts remain supported. Resizing preserves existing drops and their NBT; ordinary
AE2 donors also receive drops for new fluid inputs because their pattern reader is
item-only. Ultimate and fluid-pattern donors accept native fluids. The older
duplicated `Inputs`/`Outputs` lists remain untouched; AE2FC reads `in`/`out`.
These rules are checked against [AE2FC drop encoding](https://github.com/GTNewHorizons/AE2FluidCraft-Rework/blob/master/src/main/java/com/glodblock/github/common/item/ItemFluidDrop.java),
[AE2FC pattern reading](https://github.com/GTNewHorizons/AE2FluidCraft-Rework/blob/master/src/main/java/com/glodblock/github/util/FluidPatternDetails.java),
and [ordinary AE2 pattern reading](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/master/src/main/java/appeng/helpers/PatternHelper.java).

API sources checked:

- [Interface terminal lookup, iterator and zero-based transfers](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterfaceTerminal.scala)
- [Pattern setters: item descriptors, one-based indexes and list-removing clears](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/internal/PatternEnvironment.scala)
- [Multipart interface's implicit side argument](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterface.scala)
- [Data Card typed NBT encoding](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/server/component/DataCard.scala)
- [Item descriptor and NBT access](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/vanilla/ConverterItemStack.scala)
- [Typed NBT representation](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/vanilla/ConverterNBT.scala)

The supplied `component_probe.txt` established the available in-world methods.
