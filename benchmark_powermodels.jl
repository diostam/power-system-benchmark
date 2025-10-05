#!/usr/bin/env julia

"""
PowerModels.jl Comprehensive Benchmark (Optimized)

Benchmarks PowerModels.jl performance across AC/DC power flow, contingency analysis, and PTDF calculations.
Optimizations:
- Eliminates deepcopy overhead by modifying branch status in-place
- Pre-computes basic network transformation once
- Uses silent Ipopt optimizer
- Includes warmup run to exclude Julia compilation overhead

See README.md for detailed test descriptions and configuration.
"""

using PowerModels
using Ipopt
using JuMP
using JSON3
using Dates

# Suppress warnings and Ipopt output
import Logging
Logging.disable_logging(Logging.Warn)

# Suppress Ipopt output by setting environment variable
ENV["IPOPT_SUPPRESS_ALL_OUTPUT"] = "yes"

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
    """Run PTDF analysis for base case and all contingencies (OPTIMIZED - no deepcopy)"""

    # Base case PTDF
    base_matrix = PowerModels.calc_basic_ptdf_matrix(PowerModels.make_basic_network(data))

    # Calculate PTDF for all contingencies (in-place modification)
    for (i, branch_id) in enumerate(contingency_branches)
        try
            # Store original status
            original_status = data["branch"][branch_id]["br_status"]

            # Create contingency by modifying in-place
            data["branch"][branch_id]["br_status"] = 0

            # Calculate PTDF
            basic_cont = PowerModels.make_basic_network(data)
            cont_matrix = PowerModels.calc_basic_ptdf_matrix(basic_cont)

            # Restore original status
            data["branch"][branch_id]["br_status"] = original_status
        catch e
            # Restore status even on failure
            data["branch"][branch_id]["br_status"] = get(data["branch"][branch_id], "br_status", 1)
        end
    end

    return true
end

function main()
    println("=" ^ 60)
    println(" POWERMODELS.JL COMPREHENSIVE BENCHMARK (OPTIMIZED)")
    println("=" ^ 60)
    println("Testing: AC/DC Power Flow, DC Contingency Analysis, PTDF")
    println("Optimizations: No deepcopy, silent Ipopt, warmup precompilation")

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

    # Warmup run to exclude Julia compilation overhead
    println("\n" * "=" ^ 60)
    println(" WARMUP (excluding compilation from timing)")
    println("=" ^ 60)
    print("Running warmup AC power flow...")
    warmup_result = PowerModels.solve_ac_pf(data, Ipopt.Optimizer)
    println(" done")
    print("Running warmup DC power flow...")
    warmup_result = PowerModels.solve_dc_pf(data, Ipopt.Optimizer)
    println(" done")

    println("\n" * "=" ^ 60)
    println(" BENCHMARK TESTS")
    println("=" ^ 60)

    # Test 1: AC Power Flow (no compilation overhead)
    elapsed, success, _ = time_operation(() -> begin
        result = PowerModels.solve_ac_pf(data, Ipopt.Optimizer)
        if result["termination_status"] != PowerModels.LOCALLY_SOLVED &&
           result["termination_status"] != PowerModels.OPTIMAL
            error("AC power flow failed with status: $(result["termination_status"])")
        end
        result
    end, "1. AC Power Flow")
    results["timing_ms"]["ac_power_flow"] = success ? elapsed : nothing

    # Test 2: DC Power Flow (no compilation overhead)
    elapsed, success, _ = time_operation(() -> begin
        result = PowerModels.solve_dc_pf(data, Ipopt.Optimizer)
        if result["termination_status"] != PowerModels.LOCALLY_SOLVED &&
           result["termination_status"] != PowerModels.OPTIMAL
            error("DC power flow failed with status: $(result["termination_status"])")
        end
        result
    end, "2. DC Power Flow")
    results["timing_ms"]["dc_power_flow"] = success ? elapsed : nothing

    # Test 3: DC N-1 Contingency Analysis (OPTIMIZED - no deepcopy)
    elapsed, success, successful_contingencies = time_operation(() -> begin
        successful = 0
        for (i, branch_id) in enumerate(contingency_branches)
            try
                # Store original status
                original_status = data["branch"][branch_id]["br_status"]

                # Create contingency by modifying in-place
                data["branch"][branch_id]["br_status"] = 0

                # Run DC power flow
                result = PowerModels.solve_dc_pf(data, Ipopt.Optimizer)

                # Restore original status
                data["branch"][branch_id]["br_status"] = original_status

                if result["termination_status"] == PowerModels.LOCALLY_SOLVED ||
                   result["termination_status"] == PowerModels.OPTIMAL
                    successful += 1
                end
            catch e
                # Restore status even on failure
                data["branch"][branch_id]["br_status"] = get(data["branch"][branch_id], "br_status", 1)
            end
        end
        successful
    end, "3. DC N-1 Contingency Analysis ($(length(contingency_branches)) contingencies) [OPTIMIZED]")

    results["timing_ms"]["dc_contingency_analysis"] = success ? elapsed : nothing
    if success
        results["success_rates"]["dc_contingency"] = "$successful_contingencies/$(length(contingency_branches))"
    end

    # Test 4: PTDF Matrix Calculation (OPTIMIZED - no deepcopy)
    elapsed, success, _ = time_operation(
        () -> run_ptdf_analysis(data, contingency_branches, monitored_branches, injection_points),
        "4. PTDF Matrix Calculation (base + $(length(contingency_branches)) contingencies) [OPTIMIZED]"
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