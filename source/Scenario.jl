module Scenario

# Leaf module: mirrors scenario.json. Parsing stays in the notebook, so we take
# already-parsed data and depend on nothing. Holds the three scenario quantities:
# maxSeg, the intervention scenario q(t) (its down links per period), and the
# reconfiguration budget β(t).

export get_maxSegments_from_json, get_downtimeLinks_from_json, get_budget_from_json,
    is_scenarioData_valid

# maxSeg: the maximum number of segments a demand's waypoint path may use, read
# from an already-parsed scenario.json document.
function get_maxSegments_from_json(data)
    return Int(data.max_segments)
end

# downtimeLinks: the JSON link ids down at period t (the `interventions` entry
# whose t matches). q(t) with the links removed at that period. Empty when the
# scenario schedules no intervention at t (e.g. the nominal period t = 0).
function get_downtimeLinks_from_json(data, t)
    hasproperty(data, :interventions) || return Int[]
    for intervention in data.interventions
        Int(intervention.t) == t && return Int.(intervention.links)
    end
    return Int[]
end

# β(t): the reconfiguration budget at period t (the `budget` entry whose t
# matches) — the cap on how many segment changes a reroute from t-1 may make.
# `nothing` when no budget is scheduled at t (⇒ no budget constraint at t).
function get_budget_from_json(data, t)
    hasproperty(data, :budget) || return nothing
    for entry in data.budget
        Int(entry.t) == t && return Int(entry.value)
    end
    return nothing
end

# Return `true` if already-parsed scenario.json data is well-formed for the
# scenario accessors, `false` otherwise. A `@warn` describes the first problem
# found so failures stay diagnosable; the caller decides whether to error().
function is_scenarioData_valid(data)
    if !hasproperty(data, :max_segments)
        @warn "Missing JSON field: max_segments"
        return false
    end

    # maxSeg >= 2: segment routing needs at least a source→target segment.
    if Int(data.max_segments) < 2
        @warn "max_segments must be >= 2, got $(data.max_segments)."
        return false
    end

    # If interventions are present, each entry must name its period and links.
    if hasproperty(data, :interventions)
        for intervention in data.interventions
            for field in (:t, :links)
                if !hasproperty(intervention, field)
                    @warn "Intervention entry is missing JSON field: $field"
                    return false
                end
            end
        end
    end

    # If a budget is present, each entry must name its period and value.
    if hasproperty(data, :budget)
        for entry in data.budget
            for field in (:t, :value)
                if !hasproperty(entry, field)
                    @warn "Budget entry is missing JSON field: $field"
                    return false
                end
            end
        end
    end

    return true
end

end # module Scenario
