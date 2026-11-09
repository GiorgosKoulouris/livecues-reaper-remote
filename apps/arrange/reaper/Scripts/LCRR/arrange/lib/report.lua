-- Arrangement reports: the aggregation layer behind LCRR_Arrange_Check and
-- LCRR_Arrange_Verify (issue #21).
--
-- `lib/validate.lua` holds the primitives -- one rule per function, each
-- answering a single yes/no. This module composes them into the two verdicts a
-- user actually asks for:
--
--   * `check`  -- before a run: will applying this Arrangement refuse, and what
--                 will it do that I cannot undo by running it again?
--   * `verify` -- after a run: does the timeline now hold the properties a
--                 Repack promises?
--
-- **Why this is not part of `lib/validate.lua`.** That module states its own
-- job as the preconditions every Arrangement-aware script runs *before it
-- touches anything*. `check` is preconditions and would fit; `verify` is a
-- postcondition and would not. Rather than stretch that module's purpose,
-- `validate.lua` stays primitives and this is the one place that turns them
-- into a verdict -- so both features share a single seam instead of splitting
-- one idea across two modules.
--
-- Pure: no `reaper.*` here, per ADR-0001. The tempo oracle is injected
-- (ADR-0006), as is the automation oracle, so both entry points are testable
-- against fakes. Both return plain tables of codes and fields, with no
-- wording in them: the dialog front ends render text from them through
-- `lib/text/`, and the bridge (spec step 4) sends them as JSON. That is also
-- what keeps the specs here off message wording.

local validate = require("lib.validate")
local planner = require("lib.regions")

local report = {}

local TOLERANCE = planner.BOUNDARY_TOLERANCE

-- Findings are grouped, not sorted. `table.sort` is not stable in Lua, and the
-- order *within* a severity is meaningful -- refusals read best in the order
-- they were discovered, which is roughly cheapest-to-fix first. Bucketing
-- preserves that; sorting would scramble it for no gain.
local SEVERITIES = { "refusal", "permanent", "informational" }

-- What `check` cannot determine without writing to the project.
--
-- **This list is the honest shape of the problem, not a disclaimer.** Phase 1
-- of a run writes a Tempo Anchor at every region start, and that is what puts
-- those starts on bar lines; per ADR-0006 the tempo oracle reads live project
-- state, so it cannot be asked about a grid that does not exist yet. Everything
-- below follows from that one fact.
--
-- A future session tempted to shorten this list should note that the only way
-- to answer any of these is to write the anchors first -- which a read-only
-- check cannot do, and which was considered and rejected when this was
-- specified (issue #21). Shortening it means claiming more than the check
-- knows.
--
-- Codes, in the order they are reported. `lib/text/check.lua` words them.
local BLIND_SPOTS = {
  "padding_grid",     -- Padding against the grid the Tempo Anchors will create
  "anchor_drift",     -- whether writing the anchors moves beat-attached material
  "padding_overlap",  -- whether Padding would then run a region into its neighbour
}

-- What `verify` cannot determine, for the same reason `check` cannot determine
-- BLIND_SPOTS above: it is derived from the project as it now stands, never
-- from the plan that produced it, and that is the whole of its value.
--
-- Headroom is relative rather than absolute, so a region's length carries no
-- record of how many times it was adjusted. A correctly packed timeline and one
-- whose Headroom was applied twice are both bar-aligned, both contiguous, and
-- both in Arrangement order -- this cannot tell them apart, and saying so is
-- the point. The alternative considered and rejected was recording applied
-- lengths in the run log and diffing against them, which would make `verify`
-- trust the plan it exists to check.
--
-- Codes, as above; `lib/text/verify.lua` words them.
local VERIFY_BLIND_SPOTS = {
  "headroom_count",   -- whether a Headroom was applied once or twice
}

local function new_findings()
  local buckets = {}
  for _, severity in ipairs(SEVERITIES) do
    buckets[severity] = {}
  end
  return buckets
end

local function flatten(buckets)
  local findings = {}
  for _, severity in ipairs(SEVERITIES) do
    for _, entry in ipairs(buckets[severity]) do
      findings[#findings + 1] = entry
    end
  end
  return findings
end

--- Will applying `name` refuse, and what will it do that is permanent?
--
-- Reads nothing and writes nothing: every answer comes from the snapshot, the
-- sidecar contents and the saved `.RPP` text the caller supplies.
--
-- @param input table
--   snapshot        -- lib/project.lua's snapshot
--   name            -- the Arrangement name the user asked about
--   arrangements    -- sidecar contents, or nil when it could not be read
--   sidecar_reason  -- nil, "missing" or "invalid" (lib/sidecar.lua's reasons)
--   sidecar_error   -- the parse error, when reason is "invalid"
--   rpp_text        -- contents of the saved .RPP, or nil if unreadable
--   tempo           -- tempo oracle (ADR-0006)
--   automation      -- automation oracle, as LCRR_Arrange_Apply builds one
-- @return table { verdict, arrangement, findings, blind_spots, padding_exact,
--   region_reader }. Each finding is { severity, code, ...fields }; the fields
--   per code are listed where it is added.
function report.check(input)
  local snapshot = input.snapshot
  local buckets = new_findings()

  local function add(severity, code, fields)
    local entry = fields or {}
    entry.severity, entry.code = severity, code
    local bucket = buckets[severity]
    bucket[#bucket + 1] = entry
  end

  -- Ordered cheapest-to-fix first, and *none of these short-circuit*: the point
  -- of a precheck is to save a round trip, so a project with three problems
  -- should be told about three problems rather than sent away to fix one.
  local saved, saved_err = validate.project_saved(snapshot.project_path)
  if not saved then
    -- `message` is lib/validate.lua's own explanation, carried whole.
    add("refusal", "project_unsaved", { message = saved_err })
  end

  local arrangements = input.arrangements
  if not arrangements then
    if input.sidecar_reason == "invalid" then
      add("refusal", "sidecar_invalid", { error = input.sidecar_error })
    else
      add("refusal", "sidecar_missing")
    end
  end

  local tempo_ok, tempo_err = validate.tempo_env_is_time_based(input.rpp_text)
  if not tempo_ok then
    add("refusal", "tempo_env_beats", { message = tempo_err })
  end

  local names_ok, name_problems = validate.region_names(snapshot.regions)
  if not names_ok then
    add("refusal", "region_names", { problems = name_problems })
  end

  local arrangement
  if arrangements then
    local known, available = validate.arrangement_name_exists(input.name, arrangements)
    if known then
      arrangement = arrangements[input.name]
    else
      add("refusal", "arrangement_unknown", { name = input.name, available = available })
    end
  end

  local exists_ok = true
  if arrangement then
    local missing
    exists_ok, missing = validate.arrangement_regions_exist(arrangement, snapshot.regions)
    if not exists_ok then
      -- Deliberately distinct from the omission below. A misspelled Region Name
      -- is an error the user wants caught; an absent one is an instruction
      -- (LCRR_Arrange_Apply makes the same distinction).
      add("refusal", "arrangement_missing_regions", { missing = missing })
    end

    -- `validate.arrangement_is_exhaustive` survives #7 for callers that want to
    -- *ask* whether an Arrangement omits anything, which is not the same as
    -- refusing. This is that caller.
    local exhaustive, omitted = validate.arrangement_is_exhaustive(arrangement, snapshot.regions)
    if not exhaustive then
      add("permanent", "parked", { regions = omitted })
    end
  end

  -- The Padding figures below come from the grid as it stands. When every
  -- Tempo Anchor is already present -- the second and every later Repack,
  -- ADR-0004's idempotence case -- that *is* the post-anchor grid and the
  -- figures are exact. `plan_anchors` already knows which case this is, so the
  -- report says which rather than hedging uniformly.
  local anchor_plan = planner.plan_anchors(snapshot, input.tempo)
  local padding_exact = anchor_plan.is_noop

  -- Item timebase is a *static* property of tracks and items, so it is read
  -- straight from the snapshot rather than waiting on the planner. That matters:
  -- the planner only refuses over an item inside a region this Arrangement
  -- moves, and it does not run at all when something above stopped it -- but
  -- "which tracks do I have to change?" is answerable either way, and is the
  -- question the user acts on.
  local unsafe = {}
  for _, entry in ipairs(snapshot.items or {}) do
    if entry.timebase_safe == false then
      unsafe[#unsafe + 1] = entry
    end
  end
  if #unsafe > 0 then
    add("informational", "unsafe_timebase", { items = unsafe })
  end

  -- Planning needs a resolved Arrangement whose names all exist, and needs the
  -- Region Name invariant to hold or the planner's name lookup is ambiguous.
  local can_plan = arrangement ~= nil and exists_ok and names_ok
  if not can_plan then
    -- **Saying so is not optional.** Everything the planner would have told us
    -- -- Padding, Dropped Material, cuts, and whether the pack itself refuses
    -- -- is simply absent from this report, and a report that is quietly
    -- shorter than usual reads like a cleaner project rather than a partial
    -- answer. The blind-spot list below is fixed and cannot cover this, because
    -- it is a property of *this* run of the check, not of the check itself.
    add("informational", "not_planned")
  end

  if can_plan then
    local plan, plan_err = planner.plan_pack(snapshot, arrangement, input.tempo, input.automation)

    if not plan then
      -- Padding running a region into its neighbour, and items on a timebase
      -- this suite cannot safely reposition, both arrive here. They are not
      -- restated as separate checks on purpose: the planner is the authority on
      -- both, and a copy of its rules here would drift from the rules Apply
      -- actually enforces.
      add("refusal", "plan_refused", { error = plan_err })
    else
      -- Every category below names its members, not just its count. A count
      -- tells the user something will happen; only the list tells them which
      -- region to shorten, which track to look at, or which take to rescue --
      -- and that is the whole reason to run a check rather than just applying.
      -- Headroom is the only category here the *user* asked for by name, so it
      -- is reported even where it resolved to no change at all. A request under
      -- half a bar rounds to nothing, and a region silently missing from this
      -- list reads as a check that did not notice the edit.
      if #plan.headroom > 0 then
        add("permanent", "headroom", { headroom = plan.headroom })
      end

      if #plan.pads > 0 then
        local added = 0
        for _, pad in ipairs(plan.pads) do
          added = added + pad.added
        end
        add("permanent", "padded", { pads = plan.pads, added = added })
      end

      -- The only destructive category, and the only one the project afterwards
      -- cannot be read back to explain -- the run log is its whole record. So
      -- it is worth knowing before the run, not after.
      if #plan.drops > 0 or #plan.envelope_drops > 0 then
        add("permanent", "dropped", { items = plan.drops, envelope_points = plan.envelope_drops })
      end

      if #plan.splits > 0 then
        add("permanent", "cut", { splits = plan.splits })
      end

      if plan.is_empty then
        add("informational", "no_change")
      else
        add("informational", "moves", { counts = {
          regions = #plan.places,
          markers = #plan.marker_moves,
          tempo_markers = #plan.tempo_moves,
          envelope_points = #plan.envelope_moves,
          items = #plan.item_moves,
        } })
      end
    end
  end

  local findings = flatten(buckets)
  return {
    verdict = #buckets.refusal > 0 and "will refuse" or "will proceed",
    arrangement = input.name,
    findings = findings,
    blind_spots = BLIND_SPOTS,
    padding_exact = padding_exact,
    region_reader = snapshot.region_reader,
  }
end

--- Does the timeline hold the properties a Repack promises?
--
-- **Derived from the project as it now stands, never from the plan that
-- produced it.** That is the whole value: re-running Apply and being told
-- "already matches the timeline" tests Apply against itself, and a Repack that
-- was self-consistently wrong passes it -- issue #19 was exactly that shape and
-- went unnoticed across several sessions. This asks the project instead.
--
-- Takes the Arrangement itself rather than its name, so it is decoupled from
-- sidecar loading and can be driven from a literal list in a spec.
--
-- @param input table { snapshot, arrangement, tempo }
-- @return table { verdict, findings, blind_spots, region_reader }. Each finding
--   is { code, ...fields }.
function report.verify(input)
  local snapshot, arrangement, tempo = input.snapshot, input.arrangement, input.tempo
  local findings = {}

  local function add(code, fields)
    local entry = fields
    entry.code = code
    findings[#findings + 1] = entry
  end

  local function done()
    return {
      verdict = #findings > 0 and "fail" or "pass",
      findings = findings,
      blind_spots = VERIFY_BLIND_SPOTS,
      -- Carried so a caller can render the whole report from the result alone,
      -- the way `check`'s does. Issue #11's provenance line belongs on every
      -- report this suite prints.
      region_reader = snapshot.region_reader,
    }
  end

  local by_name = {}
  for _, region in ipairs(snapshot.regions) do
    by_name[region.name] = region
  end

  local placed = {}
  for _, name in ipairs(arrangement) do
    local region = by_name[name]
    if region then
      placed[#placed + 1] = region
    else
      add("region_absent", { region_name = name })
    end
  end

  -- Nothing below means anything against a partial Arrangement.
  if #findings > 0 or #placed == 0 then
    return done()
  end

  -- Order first, and on its own: if the regions are not in Arrangement order
  -- then this timeline is not the Arrangement, and every gap or bar-line
  -- reading below would be a true fact about the wrong question.
  for index = 2, #placed do
    if placed[index].start_time < placed[index - 1].start_time - TOLERANCE then
      add("order_mismatch", {
        region_name = placed[index].name, at = placed[index].start_time,
        after = placed[index - 1].name, after_at = placed[index - 1].start_time,
      })
      return done()
    end
  end

  -- The planner places from the start of the timeline (`lib/regions.lua`'s
  -- `cursor` opens at 0), so the Packed Block begins there.
  if math.abs(placed[1].start_time) > TOLERANCE then
    add("block_start", { at = placed[1].start_time })
  end

  for index = 2, #placed do
    local space = placed[index].start_time - placed[index - 1].end_time
    if space > TOLERANCE then
      add("gap", { region_name = placed[index].name, after = placed[index - 1].name, size = space })
    elseif space < -TOLERANCE then
      add("overlap",
        { region_name = placed[index].name, after = placed[index - 1].name, size = -space })
    end
  end

  -- ADR-0004's central promise, asked of REAPER rather than recomputed here.
  -- The tolerance is the planner's own: a check that disagreed with it about
  -- float noise would fail runs the planner considers clean.
  for _, region in ipairs(placed) do
    local bar = tempo.next_bar_at_or_after(region.start_time)
    if math.abs(bar - region.start_time) > TOLERANCE then
      add("off_bar_line", { region_name = region.name, at = region.start_time, expected = bar })
    end
  end

  -- Parked Material sits at or beyond the end of the Packed Block. `park_delta`
  -- can legitimately be zero -- material already beyond the block is left
  -- alone -- so this is a lower bound, not an equality.
  local packed_end = placed[#placed].end_time
  local arranged = {}
  for _, name in ipairs(arrangement) do
    arranged[name] = true
  end
  for _, region in ipairs(snapshot.regions) do
    if not arranged[region.name] and region.start_time < packed_end - TOLERANCE then
      add("not_parked", { region_name = region.name, at = region.start_time, packed_end = packed_end })
    end
  end

  return done()
end

--- The Headroom requests Apply must have confirmed before it moves any region
--- end, in Arrangement order: an empty list when there is nothing to confirm.
--
-- **Why this is pure, and why it takes the Arrangement rather than the plan.**
-- Deciding whether to ask is the entire guard against applying a Headroom
-- twice, so it belongs somewhere testable rather than inline in a script
-- beside a `ShowMessageBox`. Taking the Arrangement rather than the plan is
-- what makes "cancel with nothing written" true: on a project whose Tempo
-- Anchors are not yet present there is no plan until phase 1 has already
-- written them (ADR-0006), so a prompt built from a plan could only ever
-- appear after the run had touched the project. The seconds are therefore the
-- ones the user typed; what they *resolve* to is Check's job and the run log's.
--
-- The trigger is any non-zero Headroom, not "the Arrangement already matches
-- the timeline". The narrower trigger was rejected: a re-run after any small
-- manual edit produces a plan that does not match, so the guard would be absent
-- in the most common way to double-apply.
--
-- An all-zero Arrangement returns an empty list, which preserves CLAUDE.md's
-- "scripts run immediately, with no confirmation prompt" for every run that
-- behaves like today's. The wording of the prompt is `lib/text/apply.lua`'s.
-- @param arrangement table an Arrangement as lib/sidecar.lua returns it
-- @return table list of { name, seconds }
function report.headroom_requests(arrangement)
  local headroom = (arrangement or {}).headroom or {}

  local requests = {}
  for _, name in ipairs(arrangement or {}) do
    local seconds = headroom[name] or 0
    if seconds ~= 0 then
      requests[#requests + 1] = { name = name, seconds = seconds }
    end
  end
  return requests
end

--- The same Arrangement with every Headroom dropped -- what "repack only"
--- means, expressed as data rather than as a flag threaded through the planner.
-- @param arrangement table
-- @return table a copy carrying the order and nothing else
function report.without_headroom(arrangement)
  local copy = {}
  for _, name in ipairs(arrangement) do
    copy[#copy + 1] = name
  end
  return copy
end

return report
