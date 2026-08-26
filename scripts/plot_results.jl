# Render the benchmark charts from a t0 run into presentation/assets/plots/.
# Re-run whenever new results land; the deck references the fixed SVG filenames.
#
# Usage:
#   julia --project=. scripts/plot_results.jl [runId]
#
# Without a runId it picks the most recent directory under t0_results/. It reads
# the per-instance result JSONs directly (both the nested 1.2.0 `results` schema
# and the flat 1.3.0 schema), so it does not depend on collect_results.jl having
# been run. The "network scale" chart is independent of any run: it reads node /
# arc / demand counts straight from data/*.json.
#
# Charts written (SVG):
#   benchmark_mlu.svg   MLU per instance, colored by status, gap annotated
#   solve_time.svg      CPU time vs instance (log y), with the time-limit line
#   network_scale.svg   nodes / arcs / demands across the full setA (log y)

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

using Pkg
Pkg.activate(REPO_ROOT; io = devnull)

using JSON3
using Plots

gr()
Plots.reset_defaults()
theme(:default)

const PLOTS_DIR  = joinpath(REPO_ROOT, "presentation", "assets", "plots")
const DATA_DIR   = joinpath(REPO_ROOT, "data")
const T0_DIR     = joinpath(REPO_ROOT, "t0_results")

# Cartesian (warm-stone editorial) chart palette — ink primary series, dashed
# taupe comparison, warm sandstone canvas. No vivid colors.
const C_INK     = "#1A1A1A"   # primary series / text
const C_GRAY    = "#5A5A5A"   # secondary text
const C_TAUPE   = "#8A8178"   # axis ticks / labels
const C_LINE    = "#B8B0A4"   # comparison series (dashed) / borders
const C_STONE   = "#FFFFFF"   # canvas background
const C_STONE2  = "#EDE8E0"   # grid lines

const STATUS_FILL = Dict("OPTIMAL" => C_INK, "TIME_LIMIT" => C_LINE)

# ---------------------------------------------------------------------------
# Run selection
# ---------------------------------------------------------------------------

# The most recent run id under t0_results/, or `nothing` if there are none.
function get_latest_runId(t0Dir)
    isdir(t0Dir) || return nothing
    ids = sort([d for d in readdir(t0Dir) if isdir(joinpath(t0Dir, d))])
    return isempty(ids) ? nothing : ids[end]
end

# ---------------------------------------------------------------------------
# Read one run's per-instance results (both result-document schemas).
# ---------------------------------------------------------------------------

# The instance index ("01" from "setA-01" / "01.json"): the trailing -NN.
function get_index_by_instanceName(name)
    idx = match(r"(\d+)$", name)
    return idx === nothing ? name : idx.match
end

# Pull the solve metrics out of a result document regardless of schema:
#   1.2.0 nested `results` block, or 1.3.0 flat top-level fields.
function get_metrics_by_doc(doc)
    r = hasproperty(doc, :results) ? doc.results : doc
    inst = hasproperty(doc, :instance) ? string(doc.instance) : ""
    get = (field) -> hasproperty(r, field) ? getproperty(r, field) : nothing
    return (
        instance  = inst,
        vertices  = get(:vertices),
        links     = get(:links),
        demands   = get(:demands),
        status    = get(:status),
        mlu       = get(:mlu),
        lowerBound = get(:lowerBound),
        gap       = get(:gap),
        cpuTime   = get(:cpuTime),
    )
end

# A finite number or `nothing` (JSON has no Inf/NaN; missing cells may be null).
to_finite(x) = (x === nothing || x === missing || !isfinite(x)) ? nothing : x

# Load the result JSONs of one run, sorted by instance index.
function get_rows_from_run(runDir)
    isdir(runDir) || error("No results directory: $runDir")
    files = sort([f for f in readdir(runDir) if endswith(f, ".json")])
    isempty(files) && error("No result files in $runDir")
    rows = NamedTuple[]
    for f in files
        doc = JSON3.read(read(joinpath(runDir, f), String))
        m = get_metrics_by_doc(doc)
        push!(rows, (
            instance   = isempty(m.instance) ? get_index_by_instanceName(f) : get_index_by_instanceName(m.instance),
            vertices   = m.vertices,
            links      = m.links,
            demands    = m.demands,
            status     = string(m.status),
            mlu        = to_finite(m.mlu),
            lowerBound = to_finite(m.lowerBound),
            gap        = to_finite(m.gap),
            cpuTime    = to_finite(m.cpuTime),
        ))
    end
    sort!(rows; by = r -> parse(Int, r.instance))
end

# ---------------------------------------------------------------------------
# Full setA scale (independent of any run): nodes / arcs / demands.
# ---------------------------------------------------------------------------

function get_instanceScale(dataDir)
    nets = sort([f for f in readdir(dataDir) if endswith(f, "-net.json")])
    scale = NamedTuple[]
    for f in nets
        stem = replace(f, "-net.json" => "")
        net = JSON3.read(read(joinpath(dataDir, f), String))
        nNodes = length(net.nodes)
        nLinks = length(net.links)
        nDemands = 0
        tmFile = joinpath(dataDir, "$stem-tm.json")
        if isfile(tmFile)
            tm = JSON3.read(read(tmFile, String))
            nDemands = length(tm.demands)
        end
        push!(scale, (
            instance   = get_index_by_instanceName(stem),
            nodes      = nNodes,
            links      = nLinks,
            demands    = nDemands,
            multigraph = Bool(get(net, :multigraph, false)),
        ))
    end
    sort!(scale; by = r -> parse(Int, r.instance))
    return scale
end

# Attach the per-instance `multigraph` flag to the run rows so charts can keep the
# out-of-scope multigraph instances separate.
function with_multigraph(rows, scale)
    flag = Dict(s.instance => s.multigraph for s in scale)
    return [(; r..., multigraph = get(flag, r.instance, false)) for r in rows]
end

# ---------------------------------------------------------------------------
# Chart 1 — MLU per instance, colored by status, gap annotated.
# ---------------------------------------------------------------------------

function make_benchmark_mlu(rows)
    rows = [r for r in rows if !r.multigraph]
    isempty(rows) && error("No non-multigraph instances in this run.")
    labels = ["setA-" * r.instance for r in rows]
    # Bar height = MLU where a primal was found, else the lower bound (outline).
    heights = Float64[]
    fills   = String[]
    for r in rows
        y = r.mlu !== nothing ? r.mlu : r.lowerBound
        push!(heights, y === nothing ? 0.0 : y)
        push!(fills, r.status == "OPTIMAL" ? C_INK : C_LINE)
    end
    outline = [c == C_LINE for c in fills]

    p = bar(labels, heights; label = "",
        color = fills, fillalpha = [o ? 0.0 : 0.9 for o in outline],
        linecolor = fills, linewidth = 2, legend = false,
        size = (900, 480), title = "Maximum link utilization — nominal period (t = 0)",
        xlabel = "instance", ylabel = "MLU  (λ*)",
        background_color_inside = C_STONE,
        foreground_color = C_INK,
        titlefontsize = 15, titlefontfamily = "Palatino",
        xtickfontsize = 9, ytickfontsize = 9,
        guidefontsize = 12, guidefontfamily = "Palatino",
        grid = true, gridcolor = C_STONE2, gridlinewidth = 1,
        bottom_margin = 20Plots.mm, left_margin = 20Plots.mm,
        top_margin = 6Plots.mm, right_margin = 6Plots.mm, framestyle = :box)

    for (i, r) in enumerate(rows)
        if r.mlu !== nothing
            ann = r.gap === nothing ? "" : (r.gap < 1e-4 ? "gap 0%" : "gap " * string(round(100 * r.gap, digits = 1)) * "%")
            annotate!(p, i, heights[i], text(ann, 9, :top, C_GRAY))
        else
            annotate!(p, i, heights[i] + 0.02, text("time limit", 9, :top, C_TAUPE))
        end
    end
    ylims!(p, 0, (maximum(heights) * 1.28 + 0.02))
    return p
end

# ---------------------------------------------------------------------------
# Chart 2 — CPU time vs instance (log y), time-limit line.
# ---------------------------------------------------------------------------

function make_solve_time(rows; timeLimitSec = 900)
    rows = [r for r in rows if !r.multigraph]
    isempty(rows) && error("No non-multigraph instances in this run.")
    xs = [parse(Int, r.instance) for r in rows]
    ys = [r.cpuTime === nothing ? 0.0 : r.cpuTime for r in rows]
    ok  = [r.status == "OPTIMAL" for r in rows]

    p = scatter(xs[ok], ys[ok]; label = "optimal",
        color = C_INK, markersize = 7, markerstrokewidth = 0)
    scatter!(p, xs[.!ok], ys[.!ok]; label = "time limit",
        color = C_STONE, markercolor = C_LINE, markersize = 7, markerstrokewidth = 2)
    hline!(p, [timeLimitSec]; label = "time limit (900 s)",
        line = (C_GRAY, :dash), linewidth = 1.5)

    plot!(p; yscale = :log10, size = (900, 480),
        title = "Solve time vs instance size (log scale)",
        xlabel = "instance index", ylabel = "CPU time (s)",
        background_color_inside = C_STONE,
        foreground_color = C_INK,
        titlefontsize = 15, titlefontfamily = "Palatino",
        xticks = xs, xtickfontsize = 9, ytickfontsize = 9,
        guidefontsize = 12, guidefontfamily = "Palatino",
        grid = true, gridcolor = C_STONE2, gridlinewidth = 1,
        legend = :topleft, legendfontsize = 11,
        framestyle = :box,
        left_margin = 26Plots.mm, bottom_margin = 20Plots.mm,
        top_margin = 6Plots.mm, right_margin = 6Plots.mm)
    return p
end

# ---------------------------------------------------------------------------
# Chart 3 — nodes / arcs / demands across the full setA (log y).
# ---------------------------------------------------------------------------

function make_network_scale(scale)
    xs = [parse(Int, s.instance) for s in scale]
    labels = ["setA-" * s.instance for s in scale]
    multi = [s.multigraph for s in scale]
    simple = .!multi
    p = plot(size = (900, 480),
        title = "Set A instance scale (log scale)",
        xlabel = "instance", ylabel = "count",
        background_color_inside = C_STONE,
        foreground_color = C_INK,
        titlefontsize = 15, titlefontfamily = "Palatino",
        xticks = (xs, labels), xtickfontsize = 7, ytickfontsize = 9,
        guidefontsize = 12, guidefontfamily = "Palatino",
        grid = true, gridcolor = C_STONE2, gridlinewidth = 1,
        legend = :topleft, legendfontsize = 11,
        framestyle = :box,
        left_margin = 20Plots.mm, bottom_margin = 20Plots.mm,
        top_margin = 6Plots.mm, right_margin = 6Plots.mm)
    for (name, get, mk, col, ls) in (("nodes",   s -> s.nodes,   :circle, C_INK,  :solid),
                                     ("arcs",    s -> s.links,   :diamond, C_GRAY, :solid),
                                     ("demands", s -> s.demands, :square, C_TAUPE, :solid))
        plot!(p, xs[simple], [get(s) for s in scale[simple]];
            label = name, linewidth = 2, linestyle = ls, color = col,
            marker = mk, markersize = 4)
        plot!(p, xs[multi], [get(s) for s in scale[multi]];
            label = "", linewidth = 1.5, linestyle = :dot, color = C_LINE,
            marker = mk, markersize = 4, markerstrokewidth = 1,
            markercolor = C_LINE, markeralpha = 0.7, linealpha = 0.7)
    end
    plot!(p, [NaN], [NaN]; label = "multigraph (out of scope)", line = (C_LINE, :dot),
        marker = :circle, markeralpha = 0.7, markercolor = C_LINE)
    plot!(p; yscale = :log10)
    return p
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function main()
    runId = isempty(ARGS) ? get_latest_runId(T0_DIR) : ARGS[1]
    runId === nothing && error("No runs found under t0_results/. Run run_parallel.sh first.")
    runDir = joinpath(T0_DIR, runId)

    rows  = get_rows_from_run(runDir)
    scale = get_instanceScale(DATA_DIR)
    rows  = with_multigraph(rows, scale)

    mkpath(PLOTS_DIR)

    p1 = make_benchmark_mlu(rows)
    savefig(p1, joinpath(PLOTS_DIR, "benchmark_mlu.svg"))

    p2 = make_solve_time(rows)
    savefig(p2, joinpath(PLOTS_DIR, "solve_time.svg"))

    p3 = make_network_scale(scale)
    savefig(p3, joinpath(PLOTS_DIR, "network_scale.svg"))

    println("wrote charts from run ", runId, " (", length(rows), " instances) to ", PLOTS_DIR)
    return 0
end

try
    exit(main())
catch err
    @error "uncaught error" exception = (err, catch_backtrace())
    exit(1)
end
