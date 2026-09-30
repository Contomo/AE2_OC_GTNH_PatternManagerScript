# Pattern maker backbone

Target: GTNH 2.9 beta 3. Programs share one application, configuration, editor,
remote donor banks, component adapter, energy controls, history and recovery.
There is no second application or recipe-profile format.

## Use

Install using the [wget bootstrap](README.md#install-and-update-with-wget).
The launcher supports `--update` and `--check-update`. The readable application
and matrix occupy about 0.5 MB, within the 4 MB cap.

Settings has shared hardware/interfaces and a separate section per program.
Wire insulator has its destination, five-way polymer selector and independent PPS switch; wiremill has separate
1x wire and fine-wire destinations and independent input-route choices (Ingot by default). Fields save on acceptance or navigation.
All buffers matching the shared donor name are counted from their actual
patterns, independently of their capacity. Only the shared editor is local.

**Run program** opens the chooser. Select a program and build its preview.
Review reuse, preserved patterns, sorting, new recipes, donor requirements and
capacity. Destination interfaces are assumed to have 36 slots; the report states
the minimum number required, including preserved patterns. Confirm these slots
are actually available in game before pressing **Execute preview**.

The processing-pattern executor sorts existing patterns first, then stages each
remote donor through the shared editor, imprints and verifies its ingredients,
and installs it in the planned destination slot. A sorting stage and its small
progress cursor are durable, so Recover completes an interrupted permutation
cycle. Imprints reuse the same durable pattern-edit/recovery service as the
assembly-line renamer. Fresh snapshots reject stale plans before any writes.
Registry spelling is recovered from registration code and source recipe references. All current selectable wiremill and insulation routes resolve; future unresolved IDs block execution and appear in Details.

Combining and bending have independent settings sections reserved for future
verified rules. Their preview/execution controls stay disabled until implemented.
Crafting donors are counted, but the current executable generators use processing
patterns; crafting-grid execution remains a future capability.

## Compact data model

`tools/material_forms.py` reads the full registered resource index and source-annotated
ore dictionary. `tools/compile_matrix.py` emits matrix schema **2**:

- `materials`: name, resolver family/suffix, shared capability-set index (`a`),
  shared production-flag set (`p`), optional conductor/pipe bases, coating class,
  and form overrides or rare rule exclusions. There are **no recipe lists** here.
- `capabilities`: deduplicated sets of registered semantic forms. These cover gears,
  rods, rings, bolts, screws, rotors, springs, casings, all registered plate variants,
  frame boxes, fluid/item/restrictive pipes, bolted/rebolted casings, sheetmetal,
  rounds, foil and other registered forms. Not every material supports every form.
- `families`: shared GT metadata prefixes, BW metadata resolvers and GT++ naming
  templates. They use separate material namespaces; BW IDs are not GT suffixes.
- `production`: shared semantic route flags, such as `ingot_wire` or
  `stick_wireFine`. Registering forms does not grant a machine route.
- `rules`: material-neutral transformations with required forms and a production
  flag or coating class. The **21 wiremill rules** include one
  `1 ingot(material) -> 2 wire1(material)`, and shared larger-wire/fine-wire routes.
  The **96 coating rules** serve two shared classes (`standard` and `pps`);
  each class is selected once per material, rather than repeating its recipe list.
- `items`: **12** shared literal supplies/circuits, with scraped display names.
- `registryNames`: shared case-preserving IDs recovered from source declarations.
  `data/registry-names.json` records the source evidence; this is a desktop import, not a hand-maintained exception list.
- `source`: recipe provenance, registry version, compatibility evidence and
  unsupported-recipe counts.

The matrix covers **1,159 materials**, including materials without a currently
implemented production mode. Identical availability and production flags are
stored once. Only **two explicit recipe exclusions** are needed to reproduce
unusual source behavior. No material contains numeric foreign keys into recipes. The current modes
select one polymer route per material/size, producing 306 patterns. The four
scraped consumed-polymer routes are normal/small PVC and normal/small PDMS.
Normal piles use four-output batches; small piles use one-output batches.
Nothing uses the small-PVC route with that polymer omitted from the pattern;
PPS can independently be requested or omitted. Batch quantities, including PPS,
come from the source recipes. The 44 recipes with unsupported output forms are
recorded by output name in provenance and shown in Details.

`maker/modes.lua` owns `supports`, `resolve` and `eligible`. Future modes should
call those services. Nonstandard item IDs are discovered from scraped ore tags;
the primary item in an actual recipe selects among registered alternatives.
The compiler compares that item with the family formula and generates a form
override when needed. There is no hand-written material-to-item exception table.
Changing scraped material names or recipe item IDs updates these mappings on
rebuild. Missing identity evidence is not filled in from illustrative examples.
Niobium-Titanium's conductor base is **1720**; wire sizes use offsets 0..5 and
cable sizes use 6..11. Pipe bases are checked against actual registrations;
noncontiguous variants use explicit form overrides.

Recipes expand only in memory for the selected mode. Interface names never occur
in the matrix or recipe templates: the scanner binds the current mode's routing
from settings. Equivalent solid patterns are deduplicated; different external
stock alternatives remain internal recipe evidence and are omitted from the pattern preview. Omitting polymer/PPS moves that requirement
to external stocking; it does not change what the machine consumes.

## Source and rebuild

The adjacent `OreDictScript/research/recipes.json.gz` is the recipe evidence.
Its recorded version is beta 2; the user confirmed these recipes are unchanged
in beta 3. That remains provenance, not a mismatch warning or preview blocker.
The registry rules pin GT5 **5.09.54.133**. The normalized export lowercases IDs. `tools/import_registry_names.py` recovers their case from the pinned GT source archive (registration formulas and `getModItem` references), plus EnderIO registration declarations. It uses the existing scraped material names; no illustrative material examples are compiler overrides.

```powershell
python tools/import_catalog.py ..\OreDictScript\research\recipes.json.gz `
  --machine "Cable Coating" --machine "Wiremill" `
  --target-version 2.9.0-beta-3 --out .research\pattern-catalog.json.gz
python tools/import_registry_names.py .research\gt-5.09.54.133.zip `
  ..\OreDictScript\data\registry-rules.json .research\pattern-catalog.json.gz `
  .research\EnderIO-ItemAlloy.java .research\EnderIO-ModObject.java data\registry-names.json
python tools/compile_matrix.py .research\pattern-catalog.json.gz `
  ..\OreDictScript\data\registry-rules.json data\matrix.lua `
  --resources ..\OreDictScript\research\resource-index.json.gz `
  --ore-resources ..\OreDictScript\data\ores.json.gz `
  --registry-names data\registry-names.json `
  --compatible-target 2.9.0-beta-3 `
  --compatibility-basis "User confirmed recipes unchanged from beta 2 to beta 3"
node build.js
```

The importer streams the large scrape on the desktop. The expanded export stays
on the desktop; it is not a runtime library. The compiler selects a primary item
only when that exact descriptor occurs among listed alternatives. It rejects
NBT-bearing or stochastic ingredients requiring a separate resolver. Unsupported
output families do not silently inherit rules from similar material names.

## Shared code and extension points

`lib/programs.lua` owns program definitions and their fields. `lib/config.lua`
owns schema migration, defaults and validation; UI and execution use those same
definitions. `C.runner` dispatches the selected program through preview/execute.

`lib/util.lua` owns copying, validation, canonical identities, interface endpoints
and numeric location order. Both the existing renamer and pure planner use it.
`src/00_core.lua` owns component calls, discovery, fresh reads, NBT, energy and
work controls. `maker/scan.lua` uses those services rather than copying them.
`maker/modes.lua` expands the compact matrix; `maker/planner.lua` owns placement.
The build embeds each service once; pure tests load the same sources as modules.

The scanner supplies compact pattern fingerprints and recipe identities. The
planner orders interfaces by dimension/x/y/z/side, then slots from zero. It reuses
matching patterns, reserves foreign/duplicate patterns after the requested layout,
checks the entire capacity and reports the donor budget. Capacity errors block
execution; donor shortages warn and execution waits for refills as needed.
It returns no operations on a blocked plan. It sorts existing patterns before proposing creations; permutation
cycles use the empty workspace. Stale fingerprints, capacities, source data,
external supplies and mode options invalidate a reviewed plan.
Donor contents are live supply and can change after preview. Both executors use
the shared donor pool in `src/20_apply.lua`; refill waits use the existing
cooperative event handling. See [SOURCE_MAP.md](SOURCE_MAP.md) for source/output
ownership and the limits of the simulated tests.

Next stages are additional verified **LATEX**, **combining**, bending and
fluid-shaping rules. Combining can use the requested 2?1, 4?1, 8?1, 4+8 and
8+8 routes once their crafting grids/machine recipes are resolved. Later wiremill
routes, plates, extruder forms and fluid shaping add eligible shared rules and
resolvers rather than expanded recipe lists. Registering an item form alone
must never manufacture a machine recipe.

Sorting and imprints share `/home/assline.pending`. Sorting writes its complete
move list once and persists a small `/home/assline.pending.step` cursor after each
verified move. Recovery verifies the hardware binding and pattern fingerprints.
A missing/corrupt cursor or a foreign edit stops recovery rather than guessing.
Per-pattern imprints retain the original donor and accept only expected partial
ingredient changes. New programs should extend these services, not copy them.

## Validation

`node test.js` checks the readable application and wget installer/updater, UI cancellation at full
power, durable recovery, padded donors, interface-call scaling, metadata discovery,
mixed donors, 20 named banks, capacities, stale plans and all 720 permutations of
six occupied slots. It also checks the material/rule compiler and Python import
contracts. With the local scrape present, a round-trip check verifies every
represented recipe's quantities, IDs, consumed solids and external supplies.
It also checks that every claimed form resolves to a registered item and that
generic rules generate no recipes missing from the evidence.
Invented-material tests cover unfamiliar item IDs, misleading display names,
multiple registered candidates and changing the source recipe's primary item.
These are desktop contract tests; actual in-world timings still need measurement.


## UI controls and ultimate patterns

Buttons derive painted width and hitbox from the same label. Selected choices
and On toggles share one selected background; shrinking a label clears its old
bounds. Scrollbars consume the screen's native touch/drag/drop signals and map
the dragged thumb position to the viewport offset. The originating screen,
button and player identify the active drag; releasing it ends scrolling.

Ultimate processing patterns may omit the `crafting` tag. OC reads its absent
boolean as false. Donor validation therefore checks the encoded input/output
lists and preserved behavior flags without requiring that tag. The same
validation feeds both program families, and Details counts rejection reasons.

Sources: [OC screen signals](https://ocdoc.cil.li/component:signals),
[UltimatePatternHelper](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/master/src/main/java/appeng/helpers/UltimatePatternHelper.java),
[OC pattern converter](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/ConverterPattern.scala).
