module Scenario

# Leaf module: mirrors scenario.json. Parsing stays in the notebook, so we take
# already-parsed data and depend on nothing. Later steps add the reconfiguration
# budget β(t) and the intervention scenario q(t) here.

export get_maxSegments_from_json

# maxSeg: the maximum number of segments a demand's waypoint path may use, read
# from an already-parsed scenario.json document.
function get_maxSegments_from_json(data)
    return Int(data.max_segments)
end

end # module Scenario
