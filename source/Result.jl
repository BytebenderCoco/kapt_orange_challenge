module Result

# The persistence layer for the period-0 experiment: turn an in-memory
# `experimentRow` into the canonical result document and write it to disk. It is
# the write-side mirror of the data-layer readers (`get_*_from_instance`): those
# parse an instance's JSON into model inputs; this serializes the solve outcome
# back out as `<runDir>/<index>.json`.
#
# One sweep writes many such files into a single timestamped run directory
# (`get_runDir_by_timestamp`), one per instance, each the moment it finishes — so
# a cancelled sweep keeps whatever already completed. The document shape defined
# here is the single source of truth shared by the notebook (`t0_experiments.jl`)
# and the headless `scripts/t0_solve_instance.jl`; `scripts/collect_results.jl`
# reads it back into the summary CSV.

using Dates
using JSON3

export get_runDir_by_timestamp, record_event!,
    get_resultDoc_by_experimentRow, save_resultDoc_to_json,
    SCHEMA_VERSION, SCHEMA_VERSION_V2

# Schema versions of the result document. Bump on any shape change:
#   1.1.0  nested `results` block, per-demand `waypoints`, `events` log
#   1.2.0  added results.lowerBound
#   1.3.0  added results.maxrss (peak RSS in bytes, for RAM calibration)
#   2.0.0  multi-period: results.waypoints becomes a period → per-demand map
#          (as t1_experiments.jl produces); every other field is unchanged.
# SCHEMA_VERSION is the default single-period (period-0) document; pass
# `version = SCHEMA_VERSION_V2` to get_resultDoc_by_experimentRow for the
# two-period shape. The two differ only in the `version` label and the
# `waypoints` shape — which flows straight through `row.waypoints` either way.
const SCHEMA_VERSION = "1.3.0"
const SCHEMA_VERSION_V2 = "2.0.0"

# A fresh run directory under `resultsDir`, named by the current local time. The
# `yyyymmdd-HHMMSS` stamp is lexically sortable (so newest == last) and matches
# the RUN_ID that scripts/t0_execution.sh mints with `date +%Y%m%d-%H%M%S`, so
# notebook runs and parallel runs share one naming scheme. Minted once per sweep
# and reused for every instance's file; the directory is NOT created here — the
# first save_resultDoc_to_json mkpaths it, so a sweep cancelled before any
# instance finishes leaves no empty directory behind.
function get_runDir_by_timestamp(resultsDir)
    timestamp = Dates.format(now(), "yyyymmdd-HHMMSS")
    return joinpath(resultsDir, timestamp)
end

# Append one timestamped event to a run's in-memory log (info by default, :error
# on failure). Mutates `events`; nothing leaves the program here — the eventual
# save_resultDoc_to_json is what persists the accumulated log.
record_event!(events, message; level = :info) =
    push!(events, (time = Dates.format(now(), "yyyy-mm-ddTHH-MM-SS"), level, message))

# "01" from "setA-01": the instance's index within its set (the trailing -NN).
get_index_by_instanceName(instanceName) = replace(instanceName, r"^.*-" => "")

# JSON has no Inf/NaN and no `missing`; map any non-finite or absent number to
# null, and pass a finite number through unchanged.
to_jsonNumber(x) = (x === missing || x === nothing || !isfinite(x)) ? nothing : x

# Shape one experimentRow into the canonical, JSON-safe result document: a schema
# `version`, the instance `index`, a `succeeded` flag (false for the :error
# sentinel rows the callers' try/catch produce), a nested `results` block of the
# solve metrics, the routing `waypoints`, and the `events` log. This is a pure
# in-memory transform (`by`, not `from`): nothing is read or written. JSON has no
# native enum, so the solver status is written as its name string.
#
# `version` selects the schema: the default SCHEMA_VERSION is the single-period
# (period-0) document whose `waypoints` is a per-demand list; pass
# SCHEMA_VERSION_V2 for the two-period document whose `waypoints` is a period →
# per-demand map. The builder is otherwise identical — the differing waypoints
# shape rides through `row.waypoints` unchanged.
function get_resultDoc_by_experimentRow(row; version = SCHEMA_VERSION)
    return (
        version   = version,
        instance  = get_index_by_instanceName(row.instance),
        succeeded = row.status !== :error,
        results   = (
            vertices   = row.vertices,
            links      = row.links,
            demands    = row.demands,
            status     = string(row.status),
            mlu        = to_jsonNumber(row.mlu),
            lowerBound = to_jsonNumber(row.lowerBound),
            gap        = row.gap,
            cpuTime    = row.cpuTime,
            maxrss     = to_jsonNumber(row.maxrss),
            # Waypoint lists of JSON node ids: per-demand under SCHEMA_VERSION,
            # a period → per-demand map under SCHEMA_VERSION_V2. [] = shortest-path
            # routing, null for a failed run. Not yet the srpaths.json format.
            waypoints  = row.waypoints,
        ),
        events    = row.events,
    )
end

# Persist one result document to `<runDir>/<index>.json`, atomically (temp file +
# rename) so a concurrent reader — e.g. collect_results.jl run mid-sweep, or
# another parallel solver process — never sees a half-written file. `runDir` is
# created on demand. The write-side mirror of the `get_*_from_instance` readers.
function save_resultDoc_to_json(doc, runDir)
    mkpath(runDir)
    outPath = joinpath(runDir, "$(doc.instance).json")
    tmpPath = "$outPath.tmp"
    open(tmpPath, "w") do io
        JSON3.pretty(io, JSON3.write(doc))
    end
    mv(tmpPath, outPath; force = true)
    return outPath
end

end # module Result
