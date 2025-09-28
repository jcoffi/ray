# Ray Copilot Instructions

## Repository Overview

Ray is a unified framework for scaling AI and Python applications. It consists of a core distributed runtime and a set of AI libraries for simplifying ML compute, including Data, Train, Tune, RLlib, and Serve components.

**Repository Size and Type:**
- Large-scale distributed systems project (~500MB+ with dependencies)
- Primary languages: Python (core), C++ (performance-critical components), Java (limited)
- Target runtime: Linux, macOS, Windows (primary: Linux)
- Build system: Bazel with Python setuptools integration
- Test framework: pytest with custom Ray testing utilities
- Python versions supported: 3.9, 3.10, 3.11, 3.12, 3.13

## Build and Validation Process

### Prerequisites and Environment Setup

**Always install dependencies in this order:**
1. First install bazelisk (required for all builds): Download from releases or `pip install bazelisk`  
2. Install Python dependencies: `pip install -c python/requirements_compiled.txt -r python/requirements.txt`
3. For development: `pip install -c python/requirements_compiled.txt -r python/requirements/lint-requirements.txt`
4. Install pre-commit hooks: `pip install -c python/requirements_compiled.txt pre-commit && pre-commit install`

**Critical:** Always use `python/requirements_compiled.txt` as constraint file for all pip installations to avoid dependency conflicts.

### Build Process

**Core Ray Build (5-15 minutes):**
```bash
# Clean build (recommended for coding agents)
cd python/
python setup.py clean --all
python setup.py build_ext --inplace
```

**Development Installation (10-20 minutes):**
```bash
# Install Ray in development mode
pip install -e python/[all]
```

**Production Build with Bazel (15-45 minutes):**
```bash
# Build core components
bazelisk build //:ray_pkg
# Build with tests
bazelisk build //python/ray/...
```

**Documentation Build (2-5 minutes):**
```bash
cd doc/
make clean
make html
```

### Testing Process

**Always run tests in this specific order:**

1. **Lint checks first (1-3 minutes):**
```bash
# Code formatting check
pip install -c python/requirements_compiled.txt black==22.10.0 mypy==1.7.0
./ci/lint/format.sh --all-scripts

# Pre-commit checks
pip install -c python/requirements_compiled.txt pre-commit clang-format
pre-commit run --all-files
```

2. **Basic unit tests (varies by component):**
```bash
# Core tests
pytest python/ray/tests/test_basic.py -v --tb=short
# Specific component tests  
pytest python/ray/[component]/tests/ -v --tb=short
```

3. **Integration tests (component-specific timing):**
```bash
# Data tests (~5-15 minutes)
pytest python/ray/data/tests/ -v --tb=short
# Serve tests (~10-30 minutes)  
pytest python/ray/serve/tests/ -v --tb=short
```

**Test Configuration:**
- Default timeout: 180 seconds per test (configured in pytest.ini)
- Use `--tb=short` for concise error output
- Use `-v` for verbose test names
- Tests automatically treat warnings as errors (see pytest.ini)

### Validation and CI Checks

**Pre-commit validation pipeline:**
```bash
# Required formatting tools
pip install -c python/requirements_compiled.txt black==22.10.0 clang-format mypy==1.7.0

# Core linting functions (run individually to isolate failures)
./ci/lint/lint.sh clang_format
./ci/lint/lint.sh pre_commit  
./ci/lint/lint.sh code_format
./ci/lint/lint.sh banned_words
./ci/lint/lint.sh doc_readme
```

**Common Validation Issues and Solutions:**
- **Bazel network timeout:** Retry with `--timeout=600` or check internet connectivity
- **Permission errors:** Ensure write access to build directories, run `python setup.py clean --all`
- **Import errors:** Verify PYTHONPATH includes `python/` directory: `export PYTHONPATH=$PWD/python:$PYTHONPATH`
- **Memory issues:** Use `--local_ram_resources=HOST_RAM*.8` with bazelisk for large builds

## Project Layout and Architecture

### Root Directory Structure
```
├── .bazelrc, .bazelversion, WORKSPACE - Bazel build configuration
├── pyproject.toml, pytest.ini - Python project and test configuration  
├── .pre-commit-config.yaml - Pre-commit hook definitions
├── python/ - Main Ray Python package and setup.py
├── src/ - C++ core implementation and mock services
├── ci/ - Continuous integration scripts and Docker configurations
├── doc/ - Sphinx documentation with Makefile
├── rllib/ - Reinforcement learning library (separate Bazel package)
├── java/ - Java API components
├── thirdparty/ - External dependencies
├── bazel/ - Bazel build rule definitions
├── scripts/ - Utility and development scripts
└── release/ - Release automation and packaging
```

### Key Configuration Files

**Build Configuration:**
- `WORKSPACE` - Bazel workspace definition with Python toolchain (Bazel 6.5.0 required)
- `BUILD.bazel` - Root build targets and toolchain setup
- `python/setup.py` - Main Python package setup with C++ extension building
- `.bazelrc` - Bazel build flags and platform-specific configurations

**Development Configuration:**
- `pyproject.toml` - Ruff linting configuration (Python 3.9+ required)  
- `pytest.ini` - Test configuration with 180s timeout default
- `.pre-commit-config.yaml` - 30+ code quality hooks including black, ruff, mypy
- `python/requirements_compiled.txt` - Locked dependency versions (CRITICAL: always use as constraint)

### CI/CD Pipeline Structure

**Buildkite-based CI (see .buildkite/):**
- `base.rayci.yml` - Core build and test pipeline with multi-Python matrix
- `lint.rayci.yml` - Code quality and documentation checks
- `core.rayci.yml`, `data.rayci.yml`, etc. - Component-specific test suites
- `windows.rayci.yml`, `macos.rayci.yml` - Platform-specific builds

**Docker Integration:**
- `ci/docker/` - 50+ specialized build containers for different components
- Base containers: `base.build.Dockerfile`, `base.test.Dockerfile`
- Specialized: `ml.build.Dockerfile`, `serve.build.Dockerfile`, etc.

### Architecture Components

**Core Ray (`python/ray/_private/`):**
- Worker processes, object store, and distributed scheduling
- Node manager, global control store, and cluster management
- Plasma object store and shared memory management

**AI Libraries (each has separate test suite):**
- `python/ray/data/` - Scalable datasets (~200 test files, 5-15min test time)
- `python/ray/train/` - Distributed training (~150 test files, 10-25min)
- `python/ray/tune/` - Hyperparameter tuning (~100 test files, 15-30min)
- `python/ray/serve/` - Model serving (~120 test files, 10-30min)  
- `rllib/` - Reinforcement learning (separate Bazel package, 30-60min tests)

**Critical Dependencies (see python/requirements_compiled.txt):**
- `numpy`, `pandas` - Core data processing
- `protobuf`, `grpcio` - RPC communication
- `aiohttp`, `pydantic` - Async web components (Serve)
- `torch`, `tensorflow` - ML framework integration (optional)

### Deployment and Runtime

**Supported Environments:**
- Local development: `ray start --head` for single-node cluster
- Kubernetes: `ci/k8s/` contains deployment manifests
- Cloud: AWS/GCP/Azure via Anyscale integration
- Docker: Pre-built images for each component

**Performance Considerations:**
- Bazel builds use all available CPU cores by default
- Tests may require 8GB+ RAM for integration suites
- Documentation builds require 2GB+ for Sphinx processing
- Use `bazelisk build --local_ram_resources=HOST_RAM*.8` for memory-constrained environments

## Troubleshooting Guide

**Build Failures:**
1. Clean all artifacts: `cd python/ && python setup.py clean --all && rm -rf build/`
2. Update Bazel: `bazelisk version` should show 6.5.0
3. Check Python path: `export PYTHONPATH=$PWD/python:$PYTHONPATH`
4. Verify dependencies: `pip check` after installing requirements

**Test Failures:**  
1. Check test isolation: Use `pytest --forked` for problematic tests
2. Memory issues: `ray stop` between test runs to clean up processes
3. Network timeouts: Tests may require internet access for S3/GCS integration
4. Permission issues: Some tests require write access to `/tmp`

**Development Workflow:**
1. **ALWAYS** run format checks before committing: `./ci/lint/format.sh --all-scripts`
2. Test locally with component-specific suites before full CI
3. Use `pre-commit run --all-files` to catch common issues
4. For large changes, run `bazelisk test //python/ray/[component]/...` for thorough validation

**Trust these instructions** - they are based on thorough analysis of the repository structure, CI configuration, and build system. Only search for additional information if these instructions are incomplete or you encounter errors not covered in the troubleshooting section.