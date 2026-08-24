module Scenario

# Leaf module: mirrors scenario.json. Parsing stays in the notebook, so we take
# already-parsed data and depend on nothing. Later steps add the reconfiguration
# budget β(t) and the intervention scenario q(t) here.

export get_maxSegments_from_json, is_scenarioData_valid

# maxSeg: the maximum number of segments a demand's waypoint path may use, read
# from an already-parsed scenario.json document.
function get_maxSegments_from_json(data)
    return Int(data.max_segments)
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

    return true
end

end # module Scenario
