#!/usr/bin/env python3

"""
PowSyBl Comprehensive Benchmark

Benchmarks PowSyBl performance across AC/DC power flow, contingency analysis, and PTDF calculations.
See README.md for detailed test descriptions and configuration.
"""

import time
import json
from datetime import datetime
import pypowsybl.network as pn
import pypowsybl.loadflow as lf
import pypowsybl.sensitivity as sens
import pypowsybl.security as sec


def time_operation(func, description):
    """Time a single operation and return elapsed time in milliseconds"""
    print(f"{description}...", end="", flush=True)
    start_time = time.time()
    try:
        result = func()
        elapsed = time.time() - start_time
        print(f" {elapsed*1000:.2f}ms")
        return elapsed * 1000, True, result
    except Exception as e:
        elapsed = time.time() - start_time
        print(f" FAILED ({e})")
        return elapsed * 1000, False, None


def run_ptdf_analysis(network, contingency_branches,
                      monitored_branches, injection_points):
    """Run PTDF analysis for base case and all contingencies using single analysis object"""

    # Create single sensitivity analysis with all contingencies
    analysis = sens.create_dc_analysis()

    # Add the PTDF matrix
    analysis.add_branch_flow_factor_matrix(
        branches_ids=monitored_branches,
        variables_ids=injection_points
    )

    # Add all contingencies to the analysis
    for branch_id in contingency_branches:
        analysis.add_single_element_contingency(branch_id)

    # Run analysis once for base case and all contingencies
    result = analysis.run(network)

    return result


def main():
    print("=" * 60)
    print(" POWSYBL COMPREHENSIVE BENCHMARK")
    print("=" * 60)
    print("Testing: AC/DC Power Flow, DC Contingency Analysis, PTDF")

    # Load network
    print("\nLoading network...")
    network = pn.load("./Test System/SmallSystem_case.raw", {})

    buses = network.get_buses()
    branches = network.get_branches()
    generators = network.get_generators()
    loads = network.get_loads()

    print(f"Network loaded: {len(buses)} buses, {len(branches)} branches")
    print(f"                {len(generators)} generators, {len(loads)} loads")

    # Define test configuration (same as PowerModels.jl)
    num_contingencies = 500
    num_monitored = 1000
    num_injections = 500  # 250 gens + 250 loads

    # Get deterministic, sorted sets for consistency
    all_branch_ids = sorted(branches.index.tolist())
    contingency_branches = all_branch_ids[:num_contingencies]
    monitored_branches = all_branch_ids[:num_monitored]

    # Injection points: generators + loads
    all_gen_ids = sorted(generators.index.tolist())
    all_load_ids = sorted(loads.index.tolist())
    injection_points = all_gen_ids[:250] + all_load_ids[:250]

    print(f"\nBenchmark Configuration:")
    print(f"  Contingencies: {len(contingency_branches)}")
    print(f"  Monitored branches: {len(monitored_branches)}")
    print(f"  Injection points: {len(injection_points)} ({len(all_gen_ids[:250])} gens + {len(all_load_ids[:250])} loads)")

    # Initialize results
    results = {
        'timestamp': datetime.now().isoformat(),
        'package': 'PowSyBl',
        'network_info': {
            'buses': len(buses),
            'branches': len(branches),
            'generators': len(generators),
            'loads': len(loads)
        },
        'config': {
            'contingencies': len(contingency_branches),
            'monitored_branches': len(monitored_branches),
            'injection_points': len(injection_points)
        },
        'timing_ms': {},
        'success_rates': {}
    }

    print("\n" + "=" * 60)
    print(" BENCHMARK TESTS")
    print("=" * 60)

    # Test 1: AC Power Flow
    elapsed, success, _ = time_operation(
        lambda: lf.run_ac(network, lf.Parameters()),
        "1. AC Power Flow"
    )
    results['timing_ms']['ac_power_flow'] = elapsed if success else None

    # Test 2: DC Power Flow
    elapsed, success, _ = time_operation(
        lambda: lf.run_dc(network, lf.Parameters(distributed_slack=True)),
        "2. DC Power Flow"
    )
    results['timing_ms']['dc_power_flow'] = elapsed if success else None

    # Test 3: DC N-1 Contingency Analysis using built-in security analysis
    def run_security_analysis():
        sa = sec.create_analysis()
        sa.add_single_element_contingencies(contingency_branches)
        return sa.run_dc(network, parameters=lf.Parameters(distributed_slack=True))

    elapsed, success, sa_result = time_operation(
        run_security_analysis,
        f"3. DC N-1 Contingency Analysis ({len(contingency_branches)} contingencies)"
    )

    if success:
        successful_contingencies = len([c for c in sa_result.post_contingency_results.values() if c.status == sec.ComputationStatus.CONVERGED])
        results['success_rates']['dc_contingency'] = f"{successful_contingencies}/{len(contingency_branches)}"

    results['timing_ms']['dc_contingency_analysis'] = elapsed if success else None

    # Test 4: PTDF Matrix Calculation
    elapsed, success, ptdf_result = time_operation(
        lambda: run_ptdf_analysis(network, contingency_branches, monitored_branches, injection_points),
        f"4. PTDF Matrix Calculation (base + {len(contingency_branches)} contingencies)"
    )

    results['timing_ms']['ptdf_calculation'] = elapsed if success else None
    if success:
        results['success_rates']['ptdf'] = "calculation_completed"

    # Save timing results
    with open('powsybl_results.json', 'w') as f:
        json.dump(results, f, indent=2)

    # Print summary
    print("\n" + "=" * 60)
    print(" POWSYBL BENCHMARK RESULTS")
    print("=" * 60)

    for test, time_ms in results['timing_ms'].items():
        if time_ms is not None:
            print(f"  {test}: {time_ms:.2f}ms")
        else:
            print(f"  {test}: FAILED")

    print("\nSuccess Rates:")
    for test, rate in results['success_rates'].items():
        print(f"  {test}: {rate}")

    print("\nResults saved to:")
    print("  - powsybl_results.json (timing data)")


if __name__ == "__main__":
    main()