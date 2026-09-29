# Pattern maker backbone

Target: GTNH 2.9 beta 3. Maker modes run inside **assline.lua**, using the existing
UI, hardware calls, energy controls and history. There is no second application
and no recipe-profile format. The assembly-line Apply/Recover path remains active;
new maker modes currently produce **read-only plans**.

## Use

Install through the wget bootstrap described in [README.md](README.md#install-and-update-with-wget).
The installed `/home/assline.lua` launcher supports `--update` and
`--check-update`. Downloads are staged and verified before release activation.
The readable application and matrix total about **0.5 MB**, below the 4 MB cap;
there is no minification or per-paste restriction. The matrix loads only when a
maker preview needs it. Settings and recovery files survive updates.

Open **Maker setup**, choose **wiremill** or **coating**, and enter:

- Destination name: exact name of every interface participating in that layout.
- Donor-bank name: exact name of every remote bank containing disposable encoded
  patterns. Banks need no local/direct component.
- Workspace name: a dedicated interface with an empty editing slot.
- Unlocked slot capacity per interface for each role.
- Independent **request PVC** and **request PPS** switches (`on`/`off`).

Preview shows recipe ingredients, external supplies, capacity/donor blockers,
final positions, reuse and proposed sorting moves in the **Pattern maker** tab.
Scrolling, tab changes and cancellation remain available during work. Maker
previews perform no setters or transfers. Crafting and processing donors are
counted independently; unrelated and duplicate destination patterns are preserved.
A workspace's physical direct connection is not verified until an executor exists.

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
  `ingot(material) ?1 ? wire1(material) ?2`, and shared larger-wire/fine-wire routes.
  The **120 coating variants** serve two shared classes (`standard` and `pps`);
  each class is selected once per material, rather than repeating its recipe list.
- `items`: **13** shared literal supplies/circuits, including PVC and PPS.
- `source`: recipe provenance, registry version, compatibility evidence and
  unsupported-recipe counts.

The matrix covers **1,159 materials**, including materials without a currently
implemented production mode. Identical availability and production flags are
stored once. Only **two explicit recipe exclusions** are needed to reproduce
unusual source behavior. No material contains numeric foreign keys into recipes. The current modes
represent 4,398 source recipes; 44 recipes in unsupported output families remain
excluded and are recorded in provenance.

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
stock alternatives are retained for review. Omitting PVC/PPS moves that requirement
to external stocking; it does not change what the machine consumes.

## Source and rebuild

The adjacent `OreDictScript/research/recipes.json.gz` is the recipe evidence.
Its recorded version is beta 2; the user confirmed these recipes are unchanged
in beta 3. That remains provenance, not a mismatch warning or preview blocker.
The registry rules pin GT5 **5.09.54.133**. Normalized non-GT item names whose
actual registry spelling still needs resolution are marked in the preview.

```powershell
python tools/import_catalog.py ..\OreDictScript\research\recipes.json.gz `
  --machine "Cable Coating" --machine "Wiremill" `
  --target-version 2.9.0-beta-3 --out .research\pattern-catalog.json.gz
python tools/compile_matrix.py .research\pattern-catalog.json.gz `
  ..\OreDictScript\data\registry-rules.json data\matrix.lua `
  --resources ..\OreDictScript\research\resource-index.json.gz `
  --ore-resources ..\OreDictScript\data\ores.json.gz `
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

`lib/util.lua` owns copying, validation, canonical identities, interface endpoints
and numeric location order. Both the existing renamer and pure planner use it.
`src/00_core.lua` owns component calls, discovery, fresh reads, NBT, energy and
work controls. `maker/scan.lua` uses those services rather than copying them.
`maker/modes.lua` expands the compact matrix; `maker/planner.lua` owns placement.
The build embeds each service once; pure tests load the same sources as modules.

The scanner supplies compact pattern fingerprints and recipe identities. The
planner orders interfaces by dimension/x/y/z/side, then slots from zero. It reuses
matching patterns, reserves foreign/duplicate patterns after the requested layout,
checks the entire capacity and donor budget, and returns no operations on a
blocked plan. It sorts existing patterns before proposing creations; permutation
cycles use the empty workspace. Stale fingerprints, capacities, source data,
external supplies and mode options invalidate a reviewed plan.

Next stages are a verified **LATEX** compiler, verified **combining** rules, and a
journaled maker executor. Combining can use the requested 2?1, 4?1, 8?1, 4+8 and
8+8 routes once their crafting grids/machine recipes are resolved. Later wiremill
routes, plates, extruder forms and fluid shaping add eligible shared rules and
resolvers rather than expanded recipe lists. Registering an item form alone
must never manufacture a machine recipe.

The existing durable renamer journal must not be treated as a complete maker
executor. New sorting/donor-staging/grid operations need their own versioned
recovery contract, physical editor binding, pre-write revalidation and readback.

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
