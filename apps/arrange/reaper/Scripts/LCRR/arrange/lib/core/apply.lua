-- Apply, headless: Repack the project's regions into an Arrangement.
--
-- The run itself -- two phases inside one undo block (ADR-0006), the run log
-- written before the applier touches anything, every refusal -- lives here,
-- unchanged from when it was the body of LCRR_Arrange_Apply. What a front end
-- does is ask for input between the steps:
--
--   local prepared = apply.prepare({ api = reaper })
--   -- prepared.sidecar_missing: a host-only import, `apply.import_sidecar`
--   -- prepared.available: the Arrangement names to choose from
--   local result = apply.run(prepared, { name = "Radio" })
--   -- result.status == "confirm": the Arrangement moves region ends by
--   -- Headroom (ADR-0007). Nothing has been written. Run again with
--   -- headroom = "apply" (Yes), "zero" (No) or "cancel".
--
-- Every step returns `{ status = "refused", error = { code, ... } }` when it
-- cannot go on. A refusal carrying `anchors_written` came after phase 1 wrote
-- its Tempo Anchors (one undo step); every other refusal wrote nothing.

local env_lib = require("lib.core.env")
local validate = require("lib.validate")
local sidecar = require("lib.sidecar")
local regions = require("lib.regions")
local report = require("lib.report")
local undo = require("lib.undo")
local text = require("lib.text.apply")

local apply = {}

apply.TITLE = text.TITLE

-- Fills in the names once the sidecar is known to have some.
local function with_arrangements(prepared, arrangements)
  if not next(arrangements) then
    return env_lib.refused({ code = "no_arrangements" })
  end
  prepared.arrangements = arrangements
  prepared.available = sidecar.names(arrangements)
  prepared.sidecar_missing = false
  return prepared
end

--- Read the project, and refuse on anything wrong with it before an
--- Arrangement is even chosen.
-- @return table { status = "ok", available, sidecar_missing, ... } or a
--   refusal with code project_unsaved { message }, tempo_env_beats { message },
--   no_regions, region_names { problems }, sidecar_invalid { error } or
--   no_arrangements
function apply.prepare(given)
  local env = env_lib.new(given)
  local snapshot = env.snapshot()

  local saved, saved_err = validate.project_saved(snapshot.project_path)
  if not saved then
    return env_lib.refused({ code = "project_unsaved", message = saved_err })
  end

  -- Checked before anything else about the Arrangement, because it is a
  -- property of the project rather than of the plan, and getting it wrong
  -- aborts a run halfway through (lib/validate.lua's own comment).
  local tempo_ok, tempo_err = validate.tempo_env_is_time_based(env.read(snapshot.project_path))
  if not tempo_ok then
    return env_lib.refused({ code = "tempo_env_beats", message = tempo_err })
  end

  if #snapshot.regions == 0 then
    return env_lib.refused({ code = "no_regions" })
  end

  local names_ok, problems = validate.region_names(snapshot.regions)
  if not names_ok then
    return env_lib.refused({ code = "region_names", problems = problems })
  end

  local prepared = {
    status = "ok",
    env = env,
    snapshot = snapshot,
    project_path = snapshot.project_path,
    available = {},
  }

  local arrangements, load_err, reason = sidecar.load(snapshot.project_path, env.open)
  if reason == "invalid" then
    return env_lib.refused({ code = "sidecar_invalid", error = load_err })
  end

  -- Importing one is a host-only step: the front end that offers it calls
  -- `import_sidecar`, and one that cannot gets `sidecar_missing` from `run`.
  if reason == "missing" then
    prepared.sidecar_missing = true
    return prepared
  end

  return with_arrangements(prepared, arrangements)
end

--- Import an Arrangement sidecar from another file and save it beside the
--- project. The one host-only step: only the dialog front end offers it.
-- @param prepared table from `apply.prepare`, with sidecar_missing
-- @param path string the file the user picked
-- @return table `prepared`, now with its Arrangements, or a refusal with code
--   import_unreadable { path, error }, import_invalid { path, error },
--   save_failed { error } or no_arrangements
function apply.import_sidecar(prepared, path)
  local env = prepared.env

  local handle, open_err = env.open(path, "r")
  if not handle then
    return env_lib.refused({ code = "import_unreadable", path = path, error = open_err })
  end
  local source = handle:read("a")
  handle:close()

  local imported, parse_err = sidecar.parse(source)
  if not imported then
    return env_lib.refused({ code = "import_invalid", path = path, error = parse_err })
  end

  local written, save_err = sidecar.save(prepared.project_path, imported, env.open)
  if not written then
    return env_lib.refused({ code = "save_failed", error = save_err })
  end

  return with_arrangements(prepared, imported)
end

--- Repack the project into one Arrangement.
-- @param prepared table from `apply.prepare` (or `import_sidecar`)
-- @param request table
--   name      the Arrangement
--   headroom  nil until confirmed; then "apply", "zero" or "cancel"
-- @return table one of
--   { status = "ok", name, plan, anchor_plan, noop, project_path }
--   { status = "confirm", confirm = { code = "headroom", name, headroom } }
--   { status = "cancelled" }
--   a refusal with code sidecar_missing, arrangement_unknown { name, available },
--   arrangement_missing_regions { name, missing }, plan_refused { error },
--   plan_out_of_scope { name, error } or anchors_moved_items { moved }; the
--   last three carry anchors_written when phase 1 had already run
function apply.run(prepared, request)
  local env, snapshot = prepared.env, prepared.snapshot

  if prepared.sidecar_missing or not prepared.arrangements then
    return env_lib.refused({ code = "sidecar_missing" })
  end

  local name = env_lib.trim(request.name)

  local known_ok, known_names = validate.arrangement_name_exists(name, prepared.arrangements)
  if not known_ok then
    return env_lib.refused({ code = "arrangement_unknown", name = name, available = known_names })
  end
  local arrangement = prepared.arrangements[name]

  local exists_ok, missing = validate.arrangement_regions_exist(arrangement, snapshot.regions)
  if not exists_ok then
    return env_lib.refused({ code = "arrangement_missing_regions", name = name, missing = missing })
  end

  -- An Arrangement naming only some of the project's regions is accepted, and
  -- is the point of the feature -- a radio edit is a subset (ADR-0003, #7).
  -- The omitted regions become Parked Material rather than being refused, so
  -- there is no exhaustiveness check here; `validate.arrangement_is_exhaustive`
  -- survives for callers that want to *ask*, which is not the same as refusing.
  --
  -- What still refuses is a name the project does not have, checked just above.
  -- That is the distinction worth keeping: a misspelled Region Name is an error
  -- the user wants caught, while an absent one is an instruction.

  -- **The one confirmation this suite has, and the last thing that happens
  -- before anything is written.**
  --
  -- Every other part of a Repack is idempotent: run it twice and the second run
  -- reports nothing to do. Headroom is not -- it moves a region's end from
  -- wherever that end currently is, so a second run moves it again, and neither
  -- the project nor `Verify Arrangement` can tell that apart from a correct
  -- one. So the confirmation is the whole of the guard, and its position
  -- matters as much as its wording: it is built from the Arrangement rather
  -- than from the plan precisely because a plan does not exist until phase 1's
  -- anchors are on the timeline (ADR-0006), and "cancel" has to mean nothing
  -- was written.
  --
  -- An Arrangement whose Headroom is all zero needs no confirmation at all,
  -- which keeps CLAUDE.md's "scripts run immediately, no confirmation prompt"
  -- true of every run that behaves like the ones before this feature existed.
  local requests = report.headroom_requests(arrangement)
  if #requests > 0 then
    if request.headroom == "zero" then
      -- Repack only, treating every Headroom as zero.
      arrangement = report.without_headroom(arrangement)
    elseif request.headroom == "cancel" then
      return { status = "cancelled" }
    elseif request.headroom ~= "apply" then
      -- Anything that is not an explicit "apply" or "zero" asks. Defaulting
      -- the other way would apply the one operation in the suite that a second
      -- run cannot take back.
      return { status = "confirm", confirm = { code = "headroom", name = name, headroom = requests } }
    end
  end

  local api, applier = env.api, env.applier

  -- Bar lines come from REAPER, through the oracle (ADR-0006). It reads live
  -- project state on every call, so once phase 1's anchors are written it
  -- reflects them with no rebuilding.
  local oracle = env.tempo()

  -- The Automation Anchor oracle (lib/regions.lua's `envelope_anchors`).
  --
  -- Called only while building the plan, before the applier touches anything,
  -- so every value read here reflects the original timeline.
  local automation = env.automation()

  -- Phase 1: Tempo Anchors. An anchor starts a new measure at a region's start,
  -- which is what puts that start on a bar line -- so the oracle cannot answer
  -- phase 2's Padding questions until these are written (ADR-0006).
  local anchor_plan = regions.plan_anchors(snapshot, oracle)

  -- Write the plan to the console and to the log beside the project.
  --
  -- Logging only when something changes mirrors the undo convention: an
  -- Arrangement that already matches the timeline leaves no trace in either
  -- (CLAUDE.md, Undo convention; lib/log.lua).
  local plan_logged = false
  -- Set just before the anchors are written. The plan cannot be logged until
  -- they are (phase 2 is planned against the grid they make), so a failure in
  -- that window would otherwise leave a rewritten tempo map and no log at all.
  local anchors_started = false
  local function log_plan(planned_from, plan)
    if plan.is_empty and anchor_plan.is_noop then
      return
    end
    local logger = env.logger(planned_from.project_path)
    logger:heading(text.heading(name))
    for _, line in ipairs(text.log_lines(planned_from, anchor_plan, plan)) do
      logger:line(line)
    end
    logger:write()
    plan_logged = true
  end

  -- **A failure after the plan was logged is logged too (issue 10).** The plan
  -- goes to the log before the applier runs so a run that dies halfway still has
  -- its record, but the record alone reads like a run that finished. So when the
  -- applier raises after that point, say so in the log, then raise again for the
  -- front end. Before the plan is logged nothing was claimed, so nothing is added,
  -- except that a run which began writing anchors has already changed the tempo
  -- map, so that failure is logged under its own heading.
  local function run_logged(body)
    local ok, err = pcall(body)
    if ok then
      return
    end
    if plan_logged or anchors_started then
      local logger = env.logger(snapshot.project_path)
      if not plan_logged then
        logger:heading(text.heading(name))
      end
      logger:line(text.failure_line(err))
      logger:write()
    end
    error(err, 0)
  end

  local function done(plan)
    return {
      status = "ok",
      name = name,
      plan = plan,
      anchor_plan = anchor_plan,
      noop = plan.is_empty and anchor_plan.is_noop,
      project_path = snapshot.project_path,
    }
  end

  -- The plan and the refusal both come out of the phased run below, so they are
  -- declared here and filled in there.
  local plan, plan_err

  -- Phase 2, given a snapshot whose tempo map already reflects the anchors.
  local function plan_phase_two(current)
    local packed, err = regions.plan_pack(current, arrangement, oracle, automation)
    if not packed then
      return nil, { code = "plan_refused", error = err }
    end
    local scoped_ok, scope_err = validate.plan_is_region_move_only(packed)
    if not scoped_ok then
      return nil, { code = "plan_out_of_scope", name = name, error = scope_err }
    end
    return packed
  end

  -- When every anchor is redundant the tempo map already carries them, so the
  -- current grid *is* the post-anchor grid: phase 2 can be planned with nothing
  -- written first, and a run that turns out to change nothing leaves no undo
  -- point at all (CLAUDE.md's undo convention). This is the second and every
  -- subsequent Repack of the same project -- ADR-0004's idempotence claim.
  if anchor_plan.is_noop then
    plan, plan_err = plan_phase_two(snapshot)
    if not plan then
      return env_lib.refused(plan_err)
    end

    log_plan(snapshot, plan)
    run_logged(function()
      undo.run({
        api = api,
        description = text.TITLE,
        skip = plan.is_empty,
        apply = function()
          applier.plan(api, plan)
        end,
      })
    end)
    return done(plan)
  end

  -- Otherwise both phases run, inside one undo block, so REAPER sees a single
  -- step (ADR-0006).
  --
  -- **Phase 2 is planned after phase 1 has already written**, which is forced:
  -- its Padding cannot be computed against a grid that does not exist yet. So a
  -- phase-2 refusal arrives with the anchors already on the timeline. The block
  -- still closes, the anchors are still a single undo step, and the refusal
  -- says so -- silently rolling back would be worse, since REAPER offers no way
  -- to discard part of an undo block, and the anchors are correct in their own
  -- right. Everything cheap to check up front already has been (region names,
  -- the Arrangement, the tempo-env timebase), so what can still refuse here is
  -- an unsafe item timebase (#9) or Padding running a region into its
  -- neighbour.
  run_logged(function()
    undo.run({
      api = api,
      description = text.TITLE,
      apply = function()
        anchors_started = true
        applier.anchors(api, anchor_plan.anchors)

        -- Re-read: the tempo map changed, and `plan_pack`'s own contract asks for
        -- a snapshot taken after the anchors land, so that both the oracle and
        -- `snapshot.tempo_markers` reflect them. Reusing the stale snapshot would
        -- transplant tempo markers by their old values.
        local after_anchors = env.snapshot()

        -- Nothing should have moved: an anchor records the tempo already in
        -- effect, so writing it is tempo-neutral. When something did, beat-
        -- attached material has followed a tempo-map edit and the timeline phase
        -- 2 is about to plan against is not the one the user has been looking at
        -- -- and because phase 2 re-reads by design, it would plan a perfectly
        -- self-consistent Repack against the drifted positions and nothing
        -- downstream would notice (issue #19). Refusing here is the whole point:
        -- the alternative is not a worse Repack, it is a silent one.
        local held, moved = validate.items_did_not_move(snapshot, after_anchors)
        if not held then
          plan_err = { code = "anchors_moved_items", moved = moved }
          return
        end

        plan, plan_err = plan_phase_two(after_anchors)
        if not plan then
          return
        end

        log_plan(after_anchors, plan)
        applier.plan(api, plan)
      end,
    })
  end)

  if not plan then
    plan_err.anchors_written = anchor_plan.changing
    return env_lib.refused(plan_err)
  end

  return done(plan)
end

return apply
