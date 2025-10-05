#!/usr/bin/env python3

"""
Power System Benchmark Comparison Script
=======================================
Runs both PowSyBl and PowerModels.jl benchmarks and compares results
across 4 key power system analyses:
1. AC Power Flow
2. DC Power Flow
3. DC N-1 Contingency Analysis
4. PTDF Matrix Calculation

Usage: python3 run_comparison.py
"""

import subprocess
import json
import pandas as pd
from datetime import datetime
import os
import sys


def run_command(command, description):
    """Run a command and capture output"""
    print(f"\n{'='*60}")
    print(f" {description}")
    print(f"{'='*60}")
    print(f"Running: {command}")

    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=1800  # 30 minute timeout
        )

        if result.returncode == 0:
            print("✅ SUCCESS")
            if result.stdout:
                print(result.stdout)
            return True, result.stdout, result.stderr
        else:
            print(f"❌ FAILED (exit code: {result.returncode})")
            if result.stderr:
                print("STDERR:", result.stderr)
            if result.stdout:
                print("STDOUT:", result.stdout)
            return False, result.stdout, result.stderr

    except subprocess.TimeoutExpired:
        print("❌ TIMEOUT (30 minutes)")
        return False, "", "Timeout after 30 minutes"
    except Exception as e:
        print(f"❌ ERROR: {e}")
        return False, "", str(e)


def load_json_results(filename):
    """Load JSON results file"""
    try:
        with open(filename, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"⚠️  Warning: {filename} not found")
        return None
    except Exception as e:
        print(f"⚠️  Warning: Error loading {filename}: {e}")
        return None


def compare_timing_results(powsybl_results, powermodels_results):
    """Compare timing results between packages"""
    print(f"\n{'='*60}")
    print(" TIMING COMPARISON")
    print(f"{'='*60}")

    if not powsybl_results or not powermodels_results:
        print("❌ Cannot compare - missing results files")
        return None

    # Extract timing data
    powsybl_timing = powsybl_results.get('timing_ms', {})
    powermodels_timing = powermodels_results.get('timing_ms', {})

    # Create comparison table
    comparison_data = []

    for test_name in ['ac_power_flow', 'dc_power_flow',
                      'dc_contingency_analysis', 'ptdf_calculation']:
        powsybl_time = powsybl_timing.get(test_name)
        powermodels_time = powermodels_timing.get(test_name)

        if powsybl_time is not None and powermodels_time is not None:
            speedup = powsybl_time / powermodels_time if powermodels_time != 0 else float('inf')
            faster = "PowerModels.jl" if powermodels_time < powsybl_time else "PowSyBl"
        else:
            speedup = None
            faster = "N/A"

        comparison_data.append({
            'Test': test_name.replace('_', ' ').title(),
            'PowSyBl (ms)': f"{powsybl_time:.2f}" if powsybl_time is not None else "FAILED",
            'PowerModels.jl (ms)': f"{powermodels_time:.2f}" if powermodels_time is not None else "FAILED",
            'Speedup (PowSyBl/Julia)': f"{speedup:.2f}x" if speedup is not None else "N/A",
            'Faster': faster
        })

    df = pd.DataFrame(comparison_data)
    print(df.to_string(index=False))

    return df


def compare_success_rates(powsybl_results, powermodels_results):
    """Compare success rates between packages"""
    print(f"\n{'='*60}")
    print(" SUCCESS RATE COMPARISON")
    print(f"{'='*60}")

    if not powsybl_results or not powermodels_results:
        print("❌ Cannot compare - missing results files")
        return None

    powsybl_success = powsybl_results.get('success_rates', {})
    powermodels_success = powermodels_results.get('success_rates', {})

    print(f"PowSyBl Success Rates:")
    for test, rate in powsybl_success.items():
        print(f"  {test}: {rate}")

    print(f"\nPowerModels.jl Success Rates:")
    for test, rate in powermodels_success.items():
        print(f"  {test}: {rate}")


def compare_ptdf_matrices():
    """Check for PTDF matrix files (note: benchmarks don't save matrices)"""
    print(f"\n{'='*60}")
    print(" PTDF MATRIX COMPARISON")
    print(f"{'='*60}")

    print("ℹ️  PTDF matrices are not saved to CSV files")
    print("   Benchmarks only measure computation time, not results")
    print("   See timing_ms.ptdf_calculation in JSON results for performance")


def save_comparison_report(comparison_df, powsybl_results,
                           powermodels_results):
    """Save comprehensive comparison report"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = f"benchmark_comparison_{timestamp}.json"

    report = {
        "timestamp": datetime.now().isoformat(),
        "powsybl_results": powsybl_results,
        "powermodels_results": powermodels_results,
        "comparison_summary": comparison_df.to_dict('records') if
        comparison_df is not None else None
    }

    with open(report_file, 'w') as f:
        json.dump(report, f, indent=2)

    print(f"\n📊 Comprehensive comparison report saved to: {report_file}")
    return report_file


def main():
    print("🔍 POWER SYSTEM BENCHMARK COMPARISON")
    print("="*60)
    print("Running comprehensive benchmark comparison between:")
    print("  • PowSyBl (Python)")
    print("  • PowerModels.jl (Julia)")
    print("Analyzing: AC Power Flow, DC Power Flow, DC N-1 Contingency, PTDF")

    # Check if test system exists
    test_system = "./Test System/SmallSystem_case.raw"
    if not os.path.exists(test_system):
        print(f"❌ Test system not found: {test_system}")
        print("Please ensure the test system file exists before"
              "running comparison")
        return 1

    # Clean up old result files
    old_files = [
        "powsybl_results.json", "powermodels_results.json"
    ]

    print("\n🧹 Cleaning up old result files...")
    for file in old_files:
        if os.path.exists(file):
            os.remove(file)
            print(f"   Removed: {file}")

    results = {}

    # Run PowSyBl benchmark
    success, stdout, stderr = run_command(
        "python3 benchmark_powsybl.py",
        "RUNNING POWSYBL BENCHMARK"
    )
    results['powsybl_success'] = success
    results['powsybl_output'] = stdout

    # Run PowerModels.jl benchmark
    success, stdout, stderr = run_command(
        "julia benchmark_powermodels.jl",
        "RUNNING POWERMODELS.JL BENCHMARK"
    )
    results['powermodels_success'] = success
    results['powermodels_output'] = stdout

    # Load and compare results
    print(f"\n{'='*60}")
    print(" LOADING RESULTS")
    print(f"{'='*60}")

    powsybl_results = load_json_results("powsybl_results.json")
    powermodels_results = load_json_results("powermodels_results.json")

    if powsybl_results:
        print("✅ PowSyBl results loaded")
    if powermodels_results:
        print("✅ PowerModels.jl results loaded")

    # Perform comparisons
    comparison_df = compare_timing_results(powsybl_results,
                                           powermodels_results)
    compare_success_rates(powsybl_results, powermodels_results)
    compare_ptdf_matrices()

    # Save comprehensive report
    report_file = save_comparison_report(comparison_df, powsybl_results,
                                         powermodels_results)

    # Final summary
    print(f"\n{'='*60}")
    print(" BENCHMARK COMPARISON COMPLETE")
    print(f"{'='*60}")

    if results['powsybl_success'] and results['powermodels_success']:
        print("✅ Both benchmarks completed successfully")
    else:
        print("⚠️  Some benchmarks failed:")
        if not results['powsybl_success']:
            print("   ❌ PowSyBl benchmark failed")
        if not results['powermodels_success']:
            print("   ❌ PowerModels.jl benchmark failed")

    print("\nResults files:")
    for file in ["powsybl_results.json", "powermodels_results.json", report_file]:
        if os.path.exists(file):
            print(f"  ✅ {file}")
        else:
            print(f"  ❌ {file} (not created)")

    return 0 if (results['powsybl_success'] and results['powermodels_success']) else 1


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
