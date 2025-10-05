#!/bin/bash

# Power System Benchmark Environment Setup
# =======================================
# Sets up local environment for running Jupyter notebooks with both
# Python (PowSyBl) and Julia (PowerModels.jl) kernels

set -e  # Exit on any error

echo "🔧 Setting up Power System Benchmark Environment"
echo "================================================"

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed"
    exit 1
fi

# Check if Julia is available
if ! command -v julia &> /dev/null; then
    echo "❌ Julia is required but not installed"
    echo "   Install Julia from: https://julialang.org/downloads/"
    exit 1
fi

# Create Python virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "📦 Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔌 Activating virtual environment..."
source venv/bin/activate

# Upgrade pip
echo "⬆️  Upgrading pip..."
pip install --upgrade pip

# Install Python dependencies
echo "📥 Installing Python dependencies..."
pip install -r requirements.txt

# Install Julia packages for PowerModels.jl
echo "📥 Installing Julia packages..."
julia -e 'using Pkg; Pkg.add(["PowerModels", "Ipopt", "CSV", "DataFrames", "Dates", "JSON3"])'

# Install IJulia for Jupyter integration
echo "🔗 Installing IJulia for Jupyter integration..."
julia -e 'using Pkg; Pkg.add("IJulia")'

# Install Julia kernel for Jupyter
echo "⚙️  Installing Julia kernel for Jupyter..."
julia -e 'using IJulia; IJulia.installkernel("Julia", "--project=@.")'

# Verify installation
echo "✅ Verifying installation..."
echo "Available Jupyter kernels:"
jupyter kernelspec list

echo ""
echo "🎉 Environment setup complete!"
echo ""
echo "To use the environment:"
echo "1. Activate the virtual environment: source venv/bin/activate"
echo "2. Start Jupyter: jupyter notebook"
echo "3. Both Python and Julia kernels should be available"
echo ""
echo "Available notebooks:"
echo "  - PowSyBl_test_simulation.ipynb (Python/PowSyBl)"
echo "  - PowerModels_test_simulation.ipynb (Julia/PowerModels.jl)"
echo ""
echo "Note: Make sure './Test System/SmallSystem_case.raw' exists before running notebooks"