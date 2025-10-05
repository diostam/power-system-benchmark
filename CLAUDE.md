# Claude Code Configuration

This file contains configuration and commands for Claude Code to help with development tasks in this power system benchmark project.

## Quick Commands

### Run Complete Benchmark Comparison
```bash
python3 run_comparison.py
```

### Run Individual Benchmarks
```bash
# PowSyBl benchmark
python3 benchmark_powsybl.py

# PowerModels.jl benchmark
julia benchmark_powermodels.jl
```

### Lint and Type Check Commands
```bash
# Python linting (if available)
python3 -m flake8 *.py
python3 -m mypy *.py

# Julia package testing (if tests exist)
julia -e "using Pkg; Pkg.test()"
```

## Project Structure

```
├── benchmark_powsybl.py          # PowSyBl comprehensive benchmark
├── benchmark_powermodels.jl      # PowerModels.jl comprehensive benchmark
├── run_comparison.py             # Main comparison orchestrator
├── README.md                     # Project documentation
├── CLAUDE.md                     # This file
└── Test System/
    └── SmallSystem_case.raw      # Test power system case
```

## Development Notes

### Key Analysis Types
1. **AC Power Flow** - Full non-linear power flow solution
2. **DC Power Flow** - Linear approximation for faster analysis
3. **DC N-1 Contingency Analysis** - System reliability with one component out
4. **PTDF Matrix Calculation** - Power Transfer Distribution Factor matrices

### Configuration Parameters
- **Contingencies**: 500 branches (deterministically selected)
- **Monitored Branches**: 1,000 branches
- **Injection Points**: 500 (250 generators + 250 loads)
- **Timeout**: 30 minutes per benchmark

### Common Issues and Solutions

#### Missing Test System
**Error**: `Test system not found at ./Test System/SmallSystem_case.raw`
**Solution**: Ensure the PSS/E RAW file exists in the Test System directory

#### Package Import Errors
**PowSyBl**: `pip install pypowsybl pandas numpy`
**PowerModels.jl**: In Julia REPL run `using Pkg; Pkg.add(["PowerModels", "Ipopt", "CSV", "DataFrames", "Dates", "JSON3"])`

#### Branch ID Mismatch
- PowSyBl uses string IDs like `"L-110001-110041-1"`
- PowerModels.jl uses native dictionary keys from parsed data
- Scripts handle this automatically with deterministic sorting

#### PTDF Matrix Format
- PowSyBl returns DataFrames (injections × branches) - requires transpose
- PowerModels.jl returns arrays (branches × injections) - direct use
- Both saved as 2D CSV with monitored_branch, contingency, injection_1, injection_2, ...

### Expected Output Files
```
powsybl_results.json              # PowSyBl timing and metadata
powermodels_results.json          # PowerModels.jl timing and metadata
powsybl_ptdf.csv                  # PowSyBl PTDF matrices (2D format)
powermodels_ptdf.csv              # PowerModels.jl PTDF matrices (2D format)
benchmark_comparison_YYYYMMDD_HHMMSS.json  # Comprehensive comparison report
```

### Performance Expectations
- **AC Power Flow**: ~1-10 seconds
- **DC Power Flow**: ~0.1-1 seconds
- **DC N-1 Contingency (500)**: ~10-60 seconds
- **PTDF Calculation (500)**: ~30-300 seconds

Times vary significantly based on system size and package optimization.

### Debugging Commands
```bash
# Check Python environment
python3 -c "import pypowsybl; print('PowSyBl OK')"

# Check Julia environment
julia -e "using PowerModels; println(\"PowerModels.jl OK\")"

# Verify test system exists
ls -la "Test System/SmallSystem_case.raw"

# Clean up old results
rm -f *.json *.csv
```

## Code Style Notes

### Python (PowSyBl)
- Use type hints where beneficial
- Handle exceptions gracefully for contingency failures
- Transpose PowSyBl PTDF matrices for consistency

### Julia (PowerModels.jl)
- Use native Julia idioms (collect, keys, etc.)
- Handle solver status symbols (`:LOCALLY_SOLVED`, `:OPTIMAL`)
- Leverage built-in sorting and array operations

### Shared Principles
- Deterministic contingency selection for fair comparison
- Consistent error handling and progress reporting
- Clear separation of timing vs validation logic
- Comprehensive result metadata for analysis