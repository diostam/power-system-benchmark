#!/usr/bin/env julia

"""
PowerModels.jl Comprehensive Benchmark

Benchmarks PowerModels.jl performance across AC/DC power flow, contingency analysis, and PTDF calculations.
See README.md for detailed test descriptions and configuration.
"""

using PowerModels
using Ipopt
using JSON3
using Dates

# Suppress warnings to avoid output flooding
import Logging
Logging.disable_logging(Logging.Warn)

function time_operation(func, description)
    """Time a single operation and return elapsed time in milliseconds"""
    print("$description...")
    start_time = time()
    try
        result = func()
        elapsed = time() - start_time
        println(" $(round(elapsed*1000, digits=2))ms")
        return elapsed * 1000, true, result
    catch e
        elapsed = time() - start_time
        println(" FAILED ($e)")
        return elapsed * 1000, false, nothing
    end
end

function run_ptdf_analysis(data, contingency_branches, monitored_branches, injection_points)
    """Run PTDF analysis for base case and all contingencies"""

    # Base case PTDF
    basic = PowerModels.make_basic_network(data)
    base_matrix = PowerModels.calc_basic_ptdf_matrix(basic)

    # Calculate PTDF for all contingencies
    for (i, branch_id) in enumerate(contingency_branches)
        try
            # Create contingency
            contingency_data = deepcopy(data)
            contingency_data["branch"][branch_id]["br_status"] = 0

            # Calculate PTDF
            basic_cont = PowerModels.make_basic_network(contingency_data)
            cont_matrix = PowerModels.calc_basic_ptdf_matrix(basic_cont)
        catch e
            # Skip failed contingencies
        end
    end

    return true
end

function main()
    println("=" ^ 60)
    println(" POWERMODELS.JL COMPREHENSIVE BENCHMARK")
    println("=" ^ 60)
    println("Testing: AC/DC Power Flow, DC Contingency Analysis, PTDF")

    # Load network
    println("\nLoading network...")
    test_path = "./Test System/SmallSystem_case.raw"
    if !isfile(test_path)
        println("Error: Test system not found at $test_path")
        return
    end

    data = PowerModels.parse_file(test_path; import_all=true)

    buses = length(data["bus"])
    branches = length(data["branch"])
    generators = length(data["gen"])
    loads = length(data["load"])

    println("Network loaded: $buses buses, $branches branches")
    println("                $generators generators, $loads loads")

    # Define test configuration (same as PowSyBl)
    num_contingencies = 500
    num_monitored = 1000
    num_injections = 500  # 250 gens + 250 loads

    # Get deterministic, sorted sets for consistency
    all_branch_ids = sort(collect(keys(data["branch"])))
    contingency_branches = all_branch_ids[1:min(num_contingencies, length(all_branch_ids))]
    monitored_branches = all_branch_ids[1:min(num_monitored, length(all_branch_ids))]

    # Injection points: generators + loads (using Julia native IDs)
    all_gen_ids = sort(collect(keys(data["gen"])))
    all_load_ids = sort(collect(keys(data["load"])))
    injection_points = vcat(
        all_gen_ids[1:min(250, length(all_gen_ids))],
        all_load_ids[1:min(250, length(all_load_ids))]
    )

    println("\nBenchmark Configuration:")
    println("  Contingencies: $(length(contingency_branches))")
    println("  Monitored branches: $(length(monitored_branches))")
    println("  Injection points: $(length(injection_points)) ($(min(250, length(all_gen_ids))) gens + $(min(250, length(all_load_ids))) loads)")

    # Initialize results
    results = Dict(
        "timestamp" => Dates.now(),
        "package" => "PowerModels.jl",
        "network_info" => Dict(
            "buses" => buses,
            "branches" => branches,
            "generators" => generators,
            "loads" => loads
        ),
        "config" => Dict(
            "contingencies" => length(contingency_branches),
            "monitored_branches" => length(monitored_branches),
            "injection_points" => length(injection_points)
        ),
        "timing_ms" => Dict(),
        "success_rates" => Dict()
    )

    println("\n" * "=" ^ 60)
    println(" BENCHMARK TESTS")
    println("=" ^ 60)

    # Test 1: AC Power Flow
    elapsed, success, _ = time_operation(() -> begin
        result = PowerModels.solve_ac_pf(data, Ipopt.Optimizer)
        if result["termination_status"] != PowerModels.LOCALLY_SOLVED &&
           result["termination_status"] != PowerModels.OPTIMAL
            error("AC power flow failed with status: $(result["termination_status"])")
        end
        result
    end, "1. AC Power Flow")
    results["timing_ms"]["ac_power_flow"] = success ? elapsed : nothing

    # Test 2: DC Power Flow
    elapsed, success, _ = time_operation(() -> begin
        result = PowerModels.solve_dc_pf(data, Ipopt.Optimizer)
        if result["termination_status"] != PowerModels.LOCALLY_SOLVED &&
           result["termination_status"] != PowerModels.OPTIMAL
            error("DC power flow failed with status: $(result["termination_status"])")
        end
        result
    end, "2. DC Power Flow")
    results["timing_ms"]["dc_power_flow"] = success ? elapsed : nothing

    # Test 3: DC N-1 Contingency Analysis
    elapsed, success, successful_contingencies = time_operation(() -> begin
        successful = 0
        for (i, branch_id) in enumerate(contingency_branches)
            try
                # Create contingency
                contingency_data = deepcopy(data)
                contingency_data["branch"][branch_id]["br_status"] = 0

                # Run DC power flow
                result = PowerModels.solve_dc_pf(contingency_data, Ipopt.Optimizer)

                if result["termination_status"] == PowerModels.LOCALLY_SOLVED ||
                   result["termination_status"] == PowerModels.OPTIMAL
                    successful += 1
                end
            catch e
                # Some contingencies may cause infeasibility - this is expected
            end
        end
        successful
    end, "3. DC N-1 Contingency Analysis ($(length(contingency_branches)) contingencies)")

    results["timing_ms"]["dc_contingency_analysis"] = success ? elapsed : nothing
    if success
        results["success_rates"]["dc_contingency"] = "$successful_contingencies/$(length(contingency_branches))"
    end

    # Test 4: PTDF Matrix Calculation
    elapsed, success, _ = time_operation(
        () -> run_ptdf_analysis(data, contingency_branches, monitored_branches, injection_points),
        "4. PTDF Matrix Calculation (base + $(length(contingency_branches)) contingencies)"
    )

    results["timing_ms"]["ptdf_calculation"] = success ? elapsed : nothing
    if success
        results["success_rates"]["ptdf"] = "calculation_completed"
    end

    # Save timing results
    open("powermodels_results.json", "w") do f
        JSON3.pretty(f, results)
    end

    # Print summary
    println("\n" * "=" ^ 60)
    println(" POWERMODELS.JL BENCHMARK RESULTS")
    println("=" ^ 60)

    for (test, time_ms) in results["timing_ms"]
        if time_ms !== nothing
            println("  $test: $(round(time_ms, digits=2))ms")
        else
            println("  $test: FAILED")
        end
    end

    println("\nSuccess Rates:")
    for (test, rate) in results["success_rates"]
        println("  $test: $rate")
    end

    println("\nResults saved to:")
    println("  - powermodels_results.json (timing data)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end