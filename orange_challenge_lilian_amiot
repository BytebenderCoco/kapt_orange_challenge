### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# ╔═╡ 2b21c7fe-04d9-4bf3-93bd-3a70d629ae3a
begin
    using PlutoUI
    using JSON3
    using Graphs
    using GraphPlot
    using Colors
    using JuMP
    using HiGHS
end

# ╔═╡ 720129d0-5263-49db-8b34-997e05907a9d
md"""
# Step 1
"""

# ╔═╡ 58b31548-f348-47c2-ba44-0b8cd7a765e0
struct NetworkGraph{G<:AbstractGraph}
    graph::G

    # One entry per Julia vertex.
    # node_data[v] = (json_id = ..., name = ...)
    node_data::Vector{NamedTuple{(:json_id, :name), Tuple{Int, String}}}

    # Translation from JSON node id to Graphs.jl vertex number.
    json_to_vertex::Dict{Int, Int}

    # Edge attributes indexed by Julia endpoints (u,v).
    edge_data::Dict{
        Tuple{Int, Int},
        NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}
    }
end

# ╔═╡ 447f1cd2-9d3a-11f1-ab31-a58a501fd009
function json_to_network(json_text::AbstractString)
    data = JSON3.read(json_text)

    hasproperty(data, :directed) ||
        error("Missing JSON field: directed")
    hasproperty(data, :multigraph) ||
        error("Missing JSON field: multigraph")
    hasproperty(data, :nodes) ||
        error("Missing JSON field: nodes")
    hasproperty(data, :links) ||
        error("Missing JSON field: links")

    Bool(data.multigraph) &&
        error("This notebook uses SimpleGraph/SimpleDiGraph and therefore does not support multigraph=true.")

    n = length(data.nodes)

    # Map JSON ids to Julia vertices 1,...,n.
    json_to_vertex = Dict{Int, Int}()
    node_data = Vector{
        NamedTuple{(:json_id, :name), Tuple{Int, String}}
    }(undef, n)

    for (v, node) in enumerate(data.nodes)
        id = Int(node.id)

        haskey(json_to_vertex, id) &&
            error("Duplicate node id in JSON: $id")

        json_to_vertex[id] = v
        node_data[v] = (
            json_id = id,
            name = String(node.name),
        )
    end

    # Directed or undirected graph according to the JSON field.
    g = Bool(data.directed) ? SimpleDiGraph(n) : SimpleGraph(n)

    edge_data = Dict{
        Tuple{Int, Int},
        NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}
    }()

    for link in data.links
        from_id = Int(link.from)
        to_id   = Int(link.to)

        haskey(json_to_vertex, from_id) ||
            error("Unknown node id in link: $from_id")
        haskey(json_to_vertex, to_id) ||
            error("Unknown node id in link: $to_id")

        u = json_to_vertex[from_id]
        v = json_to_vertex[to_id]

        key = Bool(data.directed) ? (u, v) : minmax(u, v)

        haskey(edge_data, key) &&
            error("Multiple links between the same endpoints are not supported when multigraph=false.")

        added = add_edge!(g, u, v)
        added ||
            error("Could not add edge ($from_id,$to_id). Check the JSON for duplicate links.")

        edge_data[key] = (
            id       = Int(link.id),
            metric   = Float64(link.metric),
            capacity = Float64(link.capacity),
        )
    end

    return NetworkGraph(g, node_data, json_to_vertex, edge_data)
end

# ╔═╡ e1daff7f-60b8-416a-9c7c-31da083943ae
function load_network_json(filename::AbstractString)
    return json_to_network(read(filename, String))
end

# ╔═╡ 09b7d7fe-23ad-47e3-b606-2822a365c66f
net_01 = load_network_json("summer-school-ISIMA-OTH/project/setA/setA-01-net.json")

# ╔═╡ 55a556dd-5234-40bb-9452-1ec2ec11109f
(
    nombre_sommets = nv(net_01.graph),
    nombre_arcs = ne(net_01.graph),
    est_oriente = is_directed(net_01.graph)
)

# ╔═╡ 612ca1d2-78ab-4982-923c-fb4ae286a1cd
begin
    json_id(net::NetworkGraph, v::Integer) =
        net.node_data[v].json_id

    node_name(net::NetworkGraph, v::Integer) =
        net.node_data[v].name

    vertex_from_json_id(net::NetworkGraph, id::Integer) =
        net.json_to_vertex[Int(id)]

    function edge_attributes(net::NetworkGraph, u::Integer, v::Integer)
        key = is_directed(net.graph) ? (Int(u), Int(v)) : minmax(Int(u), Int(v))
        return net.edge_data[key]
    end
end

# ╔═╡ 15aa21dd-e17c-414c-859b-dba024893631
md"""
# Step 2
"""

# ╔═╡ ffdd71f6-4b79-4a24-a4df-07c34b9536f3
function metric_matrix(net::NetworkGraph)
    g = net.graph
    n = nv(g)

    D = fill(Inf, n, n)

    for v in vertices(g)
        D[v, v] = 0.0
    end

    for e in edges(g)
        u, v = src(e), dst(e)
        w = edge_attributes(net, u, v).metric

        w < 0 &&
            error("Dijkstra's algorithm requires non-negative metric values.")

        D[u, v] = w

        if !is_directed(g)
            D[v, u] = w
        end
    end

    return D
end

# ╔═╡ 9b8d0a7b-42c7-453d-9d42-ec8e3d967bb6
function all_pairs_shortest_data(g, distmx)
    n = nv(g)
    d = fill(Inf, n, n)
    sigma = zeros(Float64, n, n)
    for i in vertices(g)
        state = dijkstra_shortest_paths(g, i, distmx; allpaths = true)
        d[i, :] .= state.dists
        sigma[i, :] .= state.pathcounts
    end
    return d, sigma
end

# ╔═╡ 75804758-9026-4593-aa66-c1a7593f59da
function compute_split_coefficients(net::NetworkGraph)
    g = net.graph
    n = nv(g)
    distmx = metric_matrix(net)
    d, sigma = all_pairs_shortest_data(g, distmx)
    
    r = Dict{Tuple{Int, Int, Tuple{Int, Int}}, Float64}()
    
    for i in 1:n, j in 1:n
        if i == j || !isfinite(d[i, j]) || sigma[i, j] == 0
            continue
        end
        for e in edges(g)
            u, v = src(e), dst(e)
            c_a = distmx[u, v]
            
            # Égalité de la page 3 du PDF : d_iu + c_a + d_vj == d_ij
            if isapprox(d[i, u] + c_a + d[v, j], d[i, j]; atol=1e-6)
                r[(i, j, (u, v))] = (sigma[i, u] * sigma[v, j]) / sigma[i, j]
            end
        end
    end
    return r
end

# ╔═╡ d9523cad-947d-45bd-a39f-9ab10cc1ff65
r_0 = compute_split_coefficients(net_01)

# ╔═╡ bfeb0823-904d-4fca-b95c-d795c4c4fd2b
md"""
# Step 3
"""

# ╔═╡ 447db7f4-9882-4b10-992b-da4df83cd95a
function load_instance_parameters(net_file::String, tm_file::String, scenario_file::String)
    # 1. Charger le réseau et calculer r_0 (fonctions des étapes 1 et 2)
    net = load_network_json(net_file)
    r_0 = compute_split_coefficients(net)
    g = net.graph
    
    # 2. Lire le fichier scenario.json
    scenario_data = JSON3.read(read(scenario_file, String))
    max_seg = Int(scenario_data.max_segments)
    
    # 3. Lire le fichier tm.json (matrice de trafic)
    tm_data = JSON3.read(read(tm_file, String))
    
    # Extraire les demandes pour la période t=0 (v[1] est le volume à t=0)
    demands = []
    for (d_idx, d) in enumerate(tm_data.demands)
        s_julia = vertex_from_json_id(net, d.s)
        t_julia = vertex_from_json_id(net, d.t)
        vol_t0 = Float64(d.v[1])
        
        push!(demands, (id=d_idx, s=s_julia, t=t_julia, vol=vol_t0))
    end
    
    # 4. Récupérer la capacité c(a) pour chaque arc
    cap = Dict{Tuple{Int, Int}, Float64}()
    for e in edges(g)
        u, v = src(e), dst(e)
        cap[(u, v)] = edge_attributes(net, u, v).capacity
    end
    
    return (
        net = net,
        r_0 = r_0,
        max_seg = max_seg,
        demands = demands,
        capacities = cap
    )
end

# ╔═╡ 4062647d-d861-49fc-8ddd-a1e7582fadcd
data_01 = load_instance_parameters(
    "summer-school-ISIMA-OTH/project/setA/setA-01-net.json",
    "summer-school-ISIMA-OTH/project/setA/setA-01-tm.json",
    "summer-school-ISIMA-OTH/project/setA/setA-01-scenario.json"
)

# ╔═╡ a4031b67-3d8b-4861-a9f3-d577b9775783
md"""
# Step 4
"""

# ╔═╡ b9bd1cea-5df2-4ebc-90b3-1a6714b6c352
# Modèle JuMP basé sur la formulation des pages 4 et 5 du sujet ROADEF
function solve_model_t0(data, time_limit_sec=900)
    net = data.net
    g = net.graph
    n = nv(g)
    E = collect(edges(g))
    D = data.demands
    max_seg = data.max_seg
    capacities = data.capacities
    r_0 = data.r_0

    # Création du modèle avec le solveur HiGHS
    model = Model(HiGHS.Optimizer)
    set_time_limit_sec(model, time_limit_sec)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01) # S'arrête à 1% de gap
    set_silent(model)

    # 1. Variables de décision
    # x[d.id, i, j] = 1 si le segment (i,j) est utilisé par la demande d
    @variable(model, x[d in D, i in 1:n, j in 1:n; i != j], Bin)
    
    # MLU (Maximum Link Utilization)
    @variable(model, lambda_max >= 0)

    # 2. Contraintes

    # (1) Conservation du flot sur les segments pour chaque demande d
    for d in D
        for i in 1:n
            rhs = (i == d.s) ? 1 : ((i == d.t) ? -1 : 0)
            @constraint(model, 
                sum(x[d, i, j] for j in 1:n if i != j) - 
                sum(x[d, j, i] for j in 1:n if i != j) == rhs
            )
        end
    end

    # (2) Nombre maximal de segments
    for d in D
        @constraint(model, sum(x[d, i, j] for i in 1:n, j in 1:n if i != j) <= max_seg)
    end

    # (3) Contraintes de charge sur chaque arc a = (u, v)
    for e in E
        u, v = src(e), dst(e)
        cap = capacities[(u, v)]
        
        # Somme du trafic acheminé à travers l'arc (u, v)
        flow_on_arc = @expression(model, sum(
            get(r_0, (i, j, (u, v)), 0.0) * d.vol * x[d, i, j]
            for d in D, i in 1:n, j in 1:n if i != j
        ))
        
        @constraint(model, flow_on_arc <= lambda_max * cap)
    end

    # 3. Objectif : Minimiser la charge maximale
    @objective(model, Min, lambda_max)

    # 4. Résolution et mesure du temps CPU
    start_time = time()
    optimize!(model)
    cpu_time = time() - start_time

    # Extraction du statut et des résultats
    term_status = termination_status(model)
    primal_stat = primal_status(model)

    obj_val = (primal_stat == FEASIBLE_POINT || primal_stat == NEARLY_FEASIBLE_POINT) ? objective_value(model) : Inf

    # Récupération de la borne inférieure (Lower Bound) de manière sécurisée
    bound_val = try
        objective_bound(model)
    catch
        0.0
    end

    # Calcul du gap relatif
    gap = 0.0
    if isfinite(obj_val) && obj_val > 0
        gap = max(0.0, 1.0 - (bound_val / obj_val))
    end

    return (
        model = model,
        status = term_status,
        obj_value = obj_val,
        lower_bound = bound_val,
        gap = gap,
        cpu_time = cpu_time
    )
end

# ╔═╡ 328fcc99-47b4-41b5-b427-9ac7978b6ed6
res_01_t0 = solve_model_t0(data_01, 900)

# ╔═╡ dfd9a595-455e-4be3-9c81-722d932b26d7
(
    Statut = res_01_t0.status,
    MLU_t0 = res_01_t0.obj_value,
    Lower_Bound = res_01_t0.lower_bound,
    Gap = res_01_t0.gap,
    Temps_CPU_sec = round(res_01_t0.cpu_time, digits=2)
)

# ╔═╡ 7fd5b2cb-b034-4b48-94bc-754de17f4fbe
md"""
# Step 5
"""

# ╔═╡ 731dcedf-94f2-42c7-b9e2-fc94ba5f75e5
function run_setA_t0_experiments(setA_dir::String, instance_numbers)
    results = []
    
    for num in instance_numbers
        # Formater l'identifiant (ex: "01", "02", etc.)
        str_num = lpad(num, 2, '0')
        
        net_path = joinpath(setA_dir, "setA-$(str_num)-net.json")
        tm_path = joinpath(setA_dir, "setA-$(str_num)-tm.json")
        scen_path = joinpath(setA_dir, "setA-$(str_num)-scenario.json")
        
        # Vérifier si les fichiers existent avant de lancer
        if isfile(net_path) && isfile(tm_path) && isfile(scen_path)
            data = load_instance_parameters(net_path, tm_path, scen_path)
            res = solve_model_t0(data, 900) # 15 minutes max par instance
            
            push!(results, (
                Instance = "setA-$(str_num)",
                Sommets = nv(data.net.graph),
                Arcs = ne(data.net.graph),
                Demandes = length(data.demands),
                Status = string(res.status),
                MLU = round(res.obj_value, digits=4),
                LB = round(res.lower_bound, digits=4),
                Gap_pct = round(res.gap * 100, digits=2),
                Time_sec = round(res.cpu_time, digits=2)
            ))
        end
    end
    
    return results
end

# ╔═╡ ce883421-b02b-4aa4-921c-1953d7336630
setA_dir = "summer-school-ISIMA-OTH/project/setA"

# ╔═╡ 024fcae3-ef64-4cbb-9b7a-6f9dd9c81872
results_setA_t0 = run_setA_t0_experiments(setA_dir, 1:3)

# ╔═╡ 495b4c94-9c96-4fb4-ab40-432d19056ece
md"""
# Step 6
"""

# ╔═╡ cebe9e55-9aa0-4041-8da7-16fe8af94a40
# Fonction pour extraire kappa_1 quel que soit le format du JSON
function extract_kappa(data)
    raw = if hasproperty(data, :reconfiguration_budget)
        data.reconfiguration_budget
    elseif hasproperty(data, :budget)
        data.budget
    elseif hasproperty(data, :k1)
        data.k1
    else
        0.0
    end

    if raw isa AbstractVector && !isempty(raw)
        raw = raw[1]
    end

    if raw isa JSON3.Object
        if hasproperty(raw, :k)
            return Float64(raw.k)
        elseif hasproperty(raw, :value)
            return Float64(raw.value)
        elseif hasproperty(raw, :max)
            return Float64(raw.max)
        else
            for k in keys(raw)
                val = raw[k]
                if val isa Real
                    return Float64(val)
                end
            end
        end
    elseif raw isa Real
        return Float64(raw)
    end

    return 0.0
end

# ╔═╡ b3dd28b5-4c1a-4035-b886-d3324405c51c
# Charge les données initiales t=0 ET applique les pannes pour t=1
function load_instance_parameters_t1(net_file::String, tm_file::String, scenario_file::String)
    # 1. Charger la structure initiale t=0
    net_0 = load_network_json(net_file)
    r_0 = compute_split_coefficients(net_0)
    
    # 2. Lire le scénario (budget kappa_1 et pannes)
    scenario_data = JSON3.read(read(scenario_file, String))
    max_seg = Int(scenario_data.max_segments)
    kappa_1 = extract_kappa(scenario_data)
    
    # 3. Créer le graphe dégradé g_1 pour t=1 en supprimant les arcs en panne
    g_1 = copy(net_0.graph)
    edge_data_1 = copy(net_0.edge_data)
    
    if hasproperty(scenario_data, :failures)
        for fail in scenario_data.failures
            u_julia = vertex_from_json_id(net_0, fail.from)
            v_julia = vertex_from_json_id(net_0, fail.to)
            
            # Suppression de l'arc
            rem_edge!(g_1, u_julia, v_julia)
            delete!(edge_data_1, (u_julia, v_julia))
        end
    end
    
    net_1 = NetworkGraph(g_1, net_0.node_data, net_0.json_to_vertex, edge_data_1)
    
    # 4. Recalculer les split coefficients r pour t=1 sur le graphe dégradé
    r_1 = compute_split_coefficients(net_1)
    
    # 5. Charger la matrice de trafic (demandes et volumes pour t=0 et t=1)
    tm_data = JSON3.read(read(tm_file, String))
    demands = []
    for (d_idx, d) in enumerate(tm_data.demands)
        s_julia = vertex_from_json_id(net_0, d.s)
        t_julia = vertex_from_json_id(net_0, d.t)
        vol_t0 = Float64(d.v[1])
        vol_t1 = Float64(d.v[2])
        
        push!(demands, (id=d_idx, s=s_julia, t=t_julia, vol_0=vol_t0, vol_1=vol_t1))
    end
    
    # 6. Capacités des arcs
    cap_0 = Dict{Tuple{Int, Int}, Float64}()
    for e in edges(net_0.graph)
        u, v = src(e), dst(e)
        cap_0[(u, v)] = edge_attributes(net_0, u, v).capacity
    end

    cap_1 = Dict{Tuple{Int, Int}, Float64}()
    for e in edges(g_1)
        u, v = src(e), dst(e)
        cap_1[(u, v)] = edge_attributes(net_1, u, v).capacity
    end
    
    return (
        net_0 = net_0,
        net_1 = net_1,
        r_0 = r_0,
        r_1 = r_1,
        max_seg = max_seg,
        kappa_1 = kappa_1,
        demands = demands,
        capacities_0 = cap_0,
        capacities_1 = cap_1
    )
end

# ╔═╡ 932310f0-9a69-45f2-a7d9-bf98c562fb12
data_01_full = load_instance_parameters_t1(
    "summer-school-ISIMA-OTH/project/setA/setA-01-net.json",
    "summer-school-ISIMA-OTH/project/setA/setA-01-tm.json",
    "summer-school-ISIMA-OTH/project/setA/setA-01-scenario.json"
)

# ╔═╡ 5eaf9aec-f7b9-401b-b072-9bf98bc57fc8
md"""
# Step 7
"""

# ╔═╡ e96e8e6b-058d-402a-9977-8ba0cbfc76be
# Formulation complète basée sur les équations (1) à (5) de la page 4-5 du sujet ROADEF
function solve_model_t0_t1(data_full, time_limit_sec=900)
    net_0 = data_full.net_0
    net_1 = data_full.net_1
    n = nv(net_0.graph)
    D = data_full.demands
    max_seg = data_full.max_seg
    kappa_1 = data_full.kappa_1
    
    r_0 = data_full.r_0
    r_1 = data_full.r_1
    cap_0 = data_full.capacities_0
    cap_1 = data_full.capacities_1
    
    E_0 = collect(edges(net_0.graph))
    E_1 = collect(edges(net_1.graph))

    model = Model(HiGHS.Optimizer)
    set_time_limit_sec(model, time_limit_sec)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)
    set_silent(model)

    # 1. Variables de décision
    # x[d.id, i, j, t] = 1 si le segment (i,j) est utilisé par la demande d au temps t (0 ou 1)
    @variable(model, x[d in D, i in 1:n, j in 1:n, t in 0:1; i != j], Bin)
    
    # Variable de linéarisation de la valeur absolue |x_t1 - x_t0|
    @variable(model, y[d in D, i in 1:n, j in 1:n; i != j] >= 0)
    
    # Variable globale MLU minimisée
    @variable(model, lambda_max >= 0)

    # 2. Contraintes

    # Conservation du flot pour chaque période t ∈ {0, 1}
    for t in 0:1, d in D, i in 1:n
        rhs = (i == d.s) ? 1 : ((i == d.t) ? -1 : 0)
        @constraint(model, 
            sum(x[d, i, j, t] for j in 1:n if i != j) - 
            sum(x[d, j, i, t] for j in 1:n if i != j) == rhs
        )
    end

    # Nombre maximal de segments pour chaque période t ∈ {0, 1}
    for t in 0:1, d in D
        @constraint(model, sum(x[d, i, j, t] for i in 1:n, j in 1:n if i != j) <= max_seg)
    end

    # Linéarisation de la valeur absolue pour le budget de reconfiguration
    for d in D, i in 1:n, j in 1:n
        if i != j
            @constraint(model, y[d, i, j] >= x[d, i, j, 1] - x[d, i, j, 0])
            @constraint(model, y[d, i, j] >= x[d, i, j, 0] - x[d, i, j, 1])
        end
    end

    # Contrainte de budget de reconfiguration kappa(1)
    @constraint(model, sum(y[d, i, j] for d in D, i in 1:n, j in 1:n if i != j) <= kappa_1)

    # Charge sur les arcs à t = 0
    for e in E_0
        u, v = src(e), dst(e)
        c_a = cap_0[(u, v)]
        flow_0 = @expression(model, sum(
            get(r_0, (i, j, (u, v)), 0.0) * d.vol_0 * x[d, i, j, 0]
            for d in D, i in 1:n, j in 1:n if i != j
        ))
        @constraint(model, flow_0 <= lambda_max * c_a)
    end

    # Charge sur les arcs à t = 1 (sur le réseau dégradé)
    for e in E_1
        u, v = src(e), dst(e)
        c_a = cap_1[(u, v)]
        flow_1 = @expression(model, sum(
            get(r_1, (i, j, (u, v)), 0.0) * d.vol_1 * x[d, i, j, 1]
            for d in D, i in 1:n, j in 1:n if i != j
        ))
        @constraint(model, flow_1 <= lambda_max * c_a)
    end

    # 3. Objectif : Minimiser la charge maximale globale
    @objective(model, Min, lambda_max)

    # 4. Résolution
    start_time = time()
    optimize!(model)
    cpu_time = time() - start_time

    term_status = termination_status(model)
    primal_stat = primal_status(model)

    obj_val = (primal_stat == FEASIBLE_POINT || primal_stat == NEARLY_FEASIBLE_POINT) ? objective_value(model) : Inf

    bound_val = try
        objective_bound(model)
    catch
        0.0
    end

    gap = 0.0
    if isfinite(obj_val) && obj_val > 0
        gap = max(0.0, 1.0 - (bound_val / obj_val))
    end

    return (
        model = model,
        status = term_status,
        obj_value = obj_val,
        lower_bound = bound_val,
        gap = gap,
        cpu_time = cpu_time
    )
end

# ╔═╡ ec4dd787-9c79-4e40-bcf4-74caaba593e7
res_01_full = solve_model_t0_t1(data_01_full, 900)

# ╔═╡ a9e330b8-91cc-46ff-97e8-fee792eef8eb
md"""
# Step 8
"""

# ╔═╡ 140a357a-3f3c-4d93-bfcb-635b3560d1ed
function run_setA_full_experiments(setA_dir::String, instance_numbers)
    results = []
    
    for num in instance_numbers
        str_num = lpad(num, 2, '0')
        
        net_path = joinpath(setA_dir, "setA-$(str_num)-net.json")
        tm_path = joinpath(setA_dir, "setA-$(str_num)-tm.json")
        scen_path = joinpath(setA_dir, "setA-$(str_num)-scenario.json")
        
        if isfile(net_path) && isfile(tm_path) && isfile(scen_path)
            data_full = load_instance_parameters_t1(net_path, tm_path, scen_path)
            res = solve_model_t0_t1(data_full, 1800) # 30 minutes max par instance
            
            push!(results, (
                Instance = "setA-$(str_num)",
                Sommets = nv(data_full.net_0.graph),
                Arcs = ne(data_full.net_0.graph),
                Demandes = length(data_full.demands),
                Status = string(res.status),
                MLU_Max = round(res.obj_value, digits=4),
                LB = round(res.lower_bound, digits=4),
                Gap_pct = round(res.gap * 100, digits=2),
                Time_sec = round(res.cpu_time, digits=2)
            ))
        end
    end
    
    return results
end

# ╔═╡ 83c155ab-d323-42e2-b266-91cc003d4f33
# Lance par exemple sur les 3 premières instances pour valider
results_setA_full = run_setA_full_experiments(setA_dir, 1:3)

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
GraphPlot = "a2cc645c-3eea-5389-862e-a155d0052231"
Graphs = "86223c79-3864-5bf0-83f7-82e725a168b6"
HiGHS = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
JSON3 = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"

[compat]
Colors = "~0.13.1"
GraphPlot = "~0.6.2"
Graphs = "~1.14.0"
HiGHS = "~1.24.1"
JSON3 = "~1.14.3"
JuMP = "~1.31.2"
PlutoUI = "~0.7.83"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.12.7"
manifest_format = "2.0"
project_hash = "83a96683889af5139d2dfff339ddf9158ae5cffe"

[[deps.AbstractPlutoDingetjes]]
git-tree-sha1 = "6c3913f4e9bdf6ba3c08041a446fb1332716cbc2"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.4.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.2"

[[deps.ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "d57bd3762d308bded22c3b82d033bff85f6195c6"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.4.0"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1b96ea4a01afe0ea4090c5c8039690672dd13f2e"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.9+0"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "TranscodingStreams"]
git-tree-sha1 = "84990fa864b7f2b4901901ca12736e45ee79068c"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.8.5"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "970758a3d591a2a5c2a907c53f2e2f8c1b1d3537"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.9"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "67e11ee83a43eb71ddc950302c53bf33f0690dfe"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.12.1"
weakdeps = ["StyledStrings"]

    [deps.ColorTypes.extensions]
    StyledStringsExt = "StyledStrings"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "37ea44092930b1811e666c3bc38065d7d87fcc74"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.13.1"

[[deps.CommonSubexpressions]]
deps = ["MacroTools"]
git-tree-sha1 = "cda2cfaebb4be89c9084adaca7dd7333369715c5"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.1"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.3.1+2"

[[deps.Compose]]
deps = ["Base64", "Colors", "DataStructures", "Dates", "IterTools", "JSON", "LinearAlgebra", "Measures", "Printf", "Random", "Requires", "Statistics", "UUIDs"]
git-tree-sha1 = "d75431a71f82758e218779ccb3369f3243fd2bc1"
uuid = "a81c6b42-2e10-5240-aca2-a61377ecd94b"
version = "0.9.7"

[[deps.DataStructures]]
deps = ["OrderedCollections"]
git-tree-sha1 = "b0bc6d2cad1fed8b7fd59a1551a991cb3d2809e6"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.19.6"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
git-tree-sha1 = "9e2f36d3c96a820c678f2f1f1782582fcf685bae"
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"
version = "1.9.1"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "79a2aca180a85c690c58a020d47b426954b590f8"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.16.0"

[[deps.DocStringExtensions]]
git-tree-sha1 = "7442a5dfe1ebb773c29cc2962a8980f47221d76c"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.5"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.7.0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
version = "1.11.0"

[[deps.FixedPointNumbers]]
deps = ["Random", "Statistics"]
git-tree-sha1 = "59af96b98217c6ef4ae0dfe065ac7c20831d1a84"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.6"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "1b86cca764a61dcac4fef4c5e16e378e5ed6953c"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "1.4.5"
weakdeps = ["StaticArrays"]

    [deps.ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

[[deps.GraphPlot]]
deps = ["ArnoldiMethod", "Colors", "Compose", "DelimitedFiles", "Graphs", "LinearAlgebra", "Random", "SparseArrays"]
git-tree-sha1 = "066c87e33a8fcc3518c9e9970a1cbf85aa79fd6c"
uuid = "a2cc645c-3eea-5389-862e-a155d0052231"
version = "0.6.2"

[[deps.Graphs]]
deps = ["ArnoldiMethod", "DataStructures", "Inflate", "LinearAlgebra", "Random", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "7eb45fe833a5b7c51cf6d89c5a841d5967e44be3"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.14.0"

    [deps.Graphs.extensions]
    GraphsSharedArraysExt = "SharedArrays"

    [deps.Graphs.weakdeps]
    Distributed = "8ba89e20-285c-5b6f-9357-94700520ee1b"
    SharedArrays = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.HiGHS]]
deps = ["HiGHS_jll", "LinearAlgebra", "MathOptIIS", "MathOptInterface", "OpenBLAS32_jll", "PrecompileTools", "SparseArrays"]
git-tree-sha1 = "01a5241985559c08a5baadbcebd6d87daaf84a84"
uuid = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
version = "1.24.1"

[[deps.HiGHS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Zlib_jll", "libblastrampoline_jll"]
git-tree-sha1 = "2d9747b79d17c4320fe48048a3a768fe6d6d82de"
uuid = "8fd58aa0-07eb-5a78-9b36-339c94fd15ea"
version = "1.15.1+1"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "d1a86724f81bcd184a38fd284ce183ec067d71a0"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "1.0.0"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "0ee181ec08df7d7c911901ea38baf16f755114dc"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "1.0.0"

[[deps.Inflate]]
git-tree-sha1 = "d1b1b796e47d94588b3757fe84fbf65a5ec4a80d"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.5"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "b2d91fe939cae05960e760110b328288867b5758"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.6"

[[deps.IterTools]]
git-tree-sha1 = "42d5f897009e7ff2cf88db414a389e5ed1bdd023"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.10.0"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7204148362dafe5fe6a273f855b8ccbe4df8173e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.8.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JSON3]]
deps = ["Dates", "Mmap", "Parsers", "PrecompileTools", "StructTypes", "UUIDs"]
git-tree-sha1 = "411eccfe8aba0814ffa0fdf4860913ed09c34975"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.14.3"

    [deps.JSON3.extensions]
    JSON3ArrowExt = ["ArrowTypes"]

    [deps.JSON3.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

[[deps.JuMP]]
deps = ["LinearAlgebra", "MacroTools", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays"]
git-tree-sha1 = "4f27b21df3b47e8c08a83ead049afb621b2f5b3c"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.31.2"

    [deps.JuMP.extensions]
    JuMPDimensionalDataExt = "DimensionalData"

    [deps.JuMP.weakdeps]
    DimensionalData = "0703355e-b756-11e9-17c0-8b28908087d0"

[[deps.JuliaSyntaxHighlighting]]
deps = ["StyledStrings"]
uuid = "ac6e5ff7-fb65-4e79-a425-ec3bc9c03011"
version = "1.12.0"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "OpenSSL_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.15.0+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "OpenSSL_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.3+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.12.0"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "bba2d9aa057d8f126415de240573e86a8f39d2a1"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "1.0.1"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.MIMEs]]
git-tree-sha1 = "c64d943587f7187e751162b3b84445bbbd79f691"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "1.1.0"

[[deps.MacroTools]]
git-tree-sha1 = "1e0228a030642014fe5cfe68c2c0a818f9e3f522"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.16"

[[deps.Markdown]]
deps = ["Base64", "JuliaSyntaxHighlighting", "StyledStrings"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.MathOptIIS]]
deps = ["MathOptInterface"]
git-tree-sha1 = "3b3d69130d8ab8c39d5fa4d30e20a8e6428c9d37"
uuid = "8c4f8055-bd93-4160-a86b-a0c04941dbff"
version = "0.2.0"

[[deps.MathOptInterface]]
deps = ["CodecBzip2", "CodecZlib", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays", "SpecialFunctions", "Test"]
git-tree-sha1 = "f1ccd9ffcb8577e207deb9aaebeb3f961de70380"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.52.0"

    [deps.MathOptInterface.extensions]
    MathOptInterfaceBenchmarkToolsExt = "BenchmarkTools"
    MathOptInterfaceCliqueTreesExt = "CliqueTrees"

    [deps.MathOptInterface.weakdeps]
    BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
    CliqueTrees = "60701a23-6482-424a-84db-faee86b9b1f8"

[[deps.Measures]]
git-tree-sha1 = "b513cedd20d9c914783d8ad83d08120702bf2c77"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.3"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"
version = "1.11.0"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2025.11.4"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "dc5b2c4c111c46bc79ac4405eeb563523b39c004"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.8.0"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "dbd2e8cd2c1c27f0b584f6661b4309609c5a685e"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.1.4"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.3.0"

[[deps.OpenBLAS32_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "libblastrampoline_jll"]
git-tree-sha1 = "30870d0f2dc0b2dba76b10df1c58c7f018413e56"
uuid = "656ef2d0-ae68-5445-9ca0-591084a874a2"
version = "0.3.34+0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.29+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.7+0"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.5.6+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1346c9208249809840c91b26703912dff463d335"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.6+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "05f45c2e0de6259db764adbfd2f1dc6d3f8de13c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "2.0.1"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "3de8f5e6e90ebfa8d6d1f86997d6cdcd6a912ff3"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.7"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Downloads", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "e189d0623e7ce9c37389bac17e80aac3b0302e75"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.83"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "edbeefc7a4889f528644251bdb5fc9ab5348bc2c"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.3.4"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "8b770b60760d4451834fe79dd483e318eee709c4"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.5.2"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "62389eeff14780bfe55195b7204c0d8738436d64"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.1"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "7ddb0b49c109481b046972c0e4ab02b2127d6a75"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.6"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.12.0"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "429071b23f4c9a13fb6582f807cc2ef454082408"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.9.0"

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

    [deps.SpecialFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "PrecompileTools", "Random", "StaticArraysCore"]
git-tree-sha1 = "fac51faf3bb96e8bc0bf6f9f39ca4955652776bb"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.9.19"

    [deps.StaticArrays.extensions]
    StaticArraysChainRulesCoreExt = "ChainRulesCore"
    StaticArraysStatisticsExt = "Statistics"

    [deps.StaticArrays.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6ab403037779dae8c514bad259f32a447262455a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.4"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "ae3bb1eb3bba077cd276bc5cfc337cc65c3075c0"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.1"
weakdeps = ["SparseArrays"]

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

[[deps.StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "159331b30e94d7b11379037feeb9b690950cace8"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.11.0"

[[deps.StyledStrings]]
uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
version = "1.11.0"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.8.3+2"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.TranscodingStreams]]
git-tree-sha1 = "0c45878dcfdcfa8480052b6ab162cdd138781742"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.11.3"

[[deps.Tricks]]
git-tree-sha1 = "311349fd1c93a31f783f977a71e8b062a57d4101"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.13"

[[deps.URIs]]
git-tree-sha1 = "908fec9df6c5de98548ead82a468c95ccf6cd263"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.7.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.3.1+2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.15.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.64.0+1"
"""

# ╔═╡ Cell order:
# ╠═720129d0-5263-49db-8b34-997e05907a9d
# ╠═2b21c7fe-04d9-4bf3-93bd-3a70d629ae3a
# ╠═58b31548-f348-47c2-ba44-0b8cd7a765e0
# ╠═447f1cd2-9d3a-11f1-ab31-a58a501fd009
# ╠═e1daff7f-60b8-416a-9c7c-31da083943ae
# ╠═09b7d7fe-23ad-47e3-b606-2822a365c66f
# ╠═55a556dd-5234-40bb-9452-1ec2ec11109f
# ╠═612ca1d2-78ab-4982-923c-fb4ae286a1cd
# ╠═15aa21dd-e17c-414c-859b-dba024893631
# ╠═ffdd71f6-4b79-4a24-a4df-07c34b9536f3
# ╠═9b8d0a7b-42c7-453d-9d42-ec8e3d967bb6
# ╠═75804758-9026-4593-aa66-c1a7593f59da
# ╠═d9523cad-947d-45bd-a39f-9ab10cc1ff65
# ╠═bfeb0823-904d-4fca-b95c-d795c4c4fd2b
# ╠═447db7f4-9882-4b10-992b-da4df83cd95a
# ╠═4062647d-d861-49fc-8ddd-a1e7582fadcd
# ╠═a4031b67-3d8b-4861-a9f3-d577b9775783
# ╠═b9bd1cea-5df2-4ebc-90b3-1a6714b6c352
# ╠═328fcc99-47b4-41b5-b427-9ac7978b6ed6
# ╠═dfd9a595-455e-4be3-9c81-722d932b26d7
# ╠═7fd5b2cb-b034-4b48-94bc-754de17f4fbe
# ╠═731dcedf-94f2-42c7-b9e2-fc94ba5f75e5
# ╠═ce883421-b02b-4aa4-921c-1953d7336630
# ╠═024fcae3-ef64-4cbb-9b7a-6f9dd9c81872
# ╠═495b4c94-9c96-4fb4-ab40-432d19056ece
# ╠═cebe9e55-9aa0-4041-8da7-16fe8af94a40
# ╠═b3dd28b5-4c1a-4035-b886-d3324405c51c
# ╠═932310f0-9a69-45f2-a7d9-bf98c562fb12
# ╠═5eaf9aec-f7b9-401b-b072-9bf98bc57fc8
# ╠═e96e8e6b-058d-402a-9977-8ba0cbfc76be
# ╠═ec4dd787-9c79-4e40-bcf4-74caaba593e7
# ╠═a9e330b8-91cc-46ff-97e8-fee792eef8eb
# ╠═140a357a-3f3c-4d93-bfcb-635b3560d1ed
# ╠═83c155ab-d323-42e2-b266-91cc003d4f33
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
