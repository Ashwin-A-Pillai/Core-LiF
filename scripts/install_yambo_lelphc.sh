#!/usr/bin/env bash
set -euo pipefail

TARGET_ENV="yambo-lelphc"
MODE=""
SOURCE_ENV=""
SOURCE_PATH=""
PYTHON_VERSION="3.11"
YAMBOPY_SPEC="yambopy"
LELPHC_EXE=""
FORCE=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATCHER="${SCRIPT_DIR}/patch_yambopy_core_bse.py"

usage() {
cat <<'EOF'
Usage:
  install_yambo_lelphc.sh --mode pip [options]
  install_yambo_lelphc.sh --mode clone --source-env ENV [options]
  install_yambo_lelphc.sh --mode source --source PATH [options]

Options:
  --env NAME              Target Conda environment (default: yambo-lelphc)
  --mode MODE             pip | clone | source
  --source-env NAME       Existing Conda env to clone
  --source PATH           Existing YamboPy source tree for source mode
  --python VERSION        Python for fresh envs (default: 3.11)
  --yambopy-spec SPEC     pip requirement for pip mode (default: yambopy)
                          Example: yambopy==0.7.1
  --lelphc PATH           Existing LetzElPhC executable; records LELPHC_BIN
  --force                 Remove an existing target env before creating it
  -h, --help              Show this help

The installer does NOT compile LetzElPhC itself because its MPI/FFTW/parallel
HDF5/NetCDF/BLAS build is machine-specific. Supply --lelphc if already built.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) TARGET_ENV="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --source-env) SOURCE_ENV="$2"; shift 2 ;;
        --source) SOURCE_PATH="$2"; shift 2 ;;
        --python) PYTHON_VERSION="$2"; shift 2 ;;
        --yambopy-spec) YAMBOPY_SPEC="$2"; shift 2 ;;
        --lelphc) LELPHC_EXE="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "Choose installation mode:"
    echo "  1) Fresh environment + pip install YamboPy"
    echo "  2) Clone an existing Conda environment"
    echo "  3) Fresh environment + install from existing YamboPy source tree"
    read -r -p "Selection [1-3]: " ans
    case "$ans" in
        1) MODE="pip" ;;
        2)
            MODE="clone"
            read -r -p "Source Conda environment: " SOURCE_ENV
            ;;
        3)
            MODE="source"
            read -r -p "Existing YamboPy source path: " SOURCE_PATH
            ;;
        *) echo "[ERROR] Invalid selection" >&2; exit 2 ;;
    esac
fi

case "$MODE" in
    pip|clone|source) ;;
    *) echo "[ERROR] --mode must be pip, clone, or source" >&2; exit 2 ;;
esac

if [[ "$MODE" == "clone" && -z "$SOURCE_ENV" ]]; then
    echo "[ERROR] clone mode requires --source-env" >&2
    exit 2
fi
if [[ "$MODE" == "source" && -z "$SOURCE_PATH" ]]; then
    echo "[ERROR] source mode requires --source" >&2
    exit 2
fi
if [[ ! -f "$PATCHER" ]]; then
    echo "[ERROR] patcher not found next to installer: $PATCHER" >&2
    exit 2
fi

if ! command -v conda >/dev/null 2>&1; then
    echo "[ERROR] conda is not available in PATH." >&2
    exit 1
fi

eval "$(conda shell.bash hook)"

env_exists() {
    conda env list | awk '{print $1}' | grep -Fxq "$1"
}

if env_exists "$TARGET_ENV"; then
    if [[ "$FORCE" -eq 1 ]]; then
        echo "[info] Removing existing environment: $TARGET_ENV"
        conda env remove -n "$TARGET_ENV" -y
    else
        echo "[ERROR] Target environment '$TARGET_ENV' already exists."
        echo "        Use --force to replace it, or choose --env another-name."
        exit 1
    fi
fi

echo
echo "=== Creating environment: $TARGET_ENV ==="

if [[ "$MODE" == "pip" ]]; then
    conda create -n "$TARGET_ENV" -y "python=${PYTHON_VERSION}" pip
    conda run -n "$TARGET_ENV" python -m pip install --upgrade pip setuptools wheel
    conda run -n "$TARGET_ENV" python -m pip install "$YAMBOPY_SPEC"

elif [[ "$MODE" == "source" ]]; then
    SOURCE_PATH="$(cd "$SOURCE_PATH" && pwd)"
    if [[ ! -f "$SOURCE_PATH/pyproject.toml" && ! -f "$SOURCE_PATH/setup.py" ]]; then
        echo "[ERROR] '$SOURCE_PATH' does not look like an installable YamboPy source tree." >&2
        exit 1
    fi
    conda create -n "$TARGET_ENV" -y "python=${PYTHON_VERSION}" pip
    conda run -n "$TARGET_ENV" python -m pip install --upgrade pip setuptools wheel
    # Deliberately NON-editable: keep modifications private to this environment.
    conda run -n "$TARGET_ENV" python -m pip install "$SOURCE_PATH"

elif [[ "$MODE" == "clone" ]]; then
    if ! env_exists "$SOURCE_ENV"; then
        echo "[ERROR] Source environment '$SOURCE_ENV' does not exist." >&2
        exit 1
    fi

    conda create -n "$TARGET_ENV" --clone "$SOURCE_ENV" -y

    SHOW="$(conda run -n "$TARGET_ENV" python -m pip show yambopy 2>/dev/null || true)"
    EDITABLE="$(printf '%s\n' "$SHOW" | sed -n 's/^Editable project location:[[:space:]]*//p' | head -n1)"

    if [[ -n "$EDITABLE" && -d "$EDITABLE" ]]; then
        echo "[info] Cloned env still points to editable YamboPy source:"
        echo "       $EDITABLE"
        echo "[info] Installing a private non-editable copy into $TARGET_ENV ..."
        conda run -n "$TARGET_ENV" python -m pip install \
            --force-reinstall --no-deps --no-build-isolation "$EDITABLE"
    fi
fi

echo
echo "=== Verifying environment-local YamboPy ==="

TARGET_PREFIX="$(conda run -n "$TARGET_ENV" python -c 'import sys; print(sys.prefix)')"
YAMBOPY_FILE="$(conda run -n "$TARGET_ENV" python -c 'import yambopy,os; print(os.path.realpath(yambopy.__file__))')"

echo "Target prefix : $TARGET_PREFIX"
echo "YamboPy       : $YAMBOPY_FILE"

case "$YAMBOPY_FILE" in
    "$TARGET_PREFIX"/*) ;;
    *)
        echo "[ERROR] YamboPy is still imported from outside the target environment."
        echo "        Refusing to patch a shared tree."
        conda run -n "$TARGET_ENV" python -m pip show yambopy || true
        exit 1
        ;;
esac

echo
echo "=== Applying CORE-BSE YamboPy patch ==="
conda run -n "$TARGET_ENV" python "$PATCHER"

echo
echo "=== Optional LetzElPhC executable ==="
if [[ -n "$LELPHC_EXE" ]]; then
    if [[ ! -x "$LELPHC_EXE" ]]; then
        echo "[ERROR] --lelphc is not an executable file: $LELPHC_EXE" >&2
        exit 1
    fi
    LELPHC_EXE="$(cd "$(dirname "$LELPHC_EXE")" && pwd)/$(basename "$LELPHC_EXE")"
    ACTIVATE_DIR="${TARGET_PREFIX}/etc/conda/activate.d"
    DEACTIVATE_DIR="${TARGET_PREFIX}/etc/conda/deactivate.d"
    mkdir -p "$ACTIVATE_DIR" "$DEACTIVATE_DIR"

    cat > "${ACTIVATE_DIR}/yambo_lelphc.sh" <<EOF
export _YAMBO_LELPHC_OLD_LELPHC_BIN="\${LELPHC_BIN-}"
export LELPHC_BIN="${LELPHC_EXE}"
EOF

    cat > "${DEACTIVATE_DIR}/yambo_lelphc.sh" <<'EOF'
if [[ -n "${_YAMBO_LELPHC_OLD_LELPHC_BIN+x}" ]]; then
    if [[ -n "$_YAMBO_LELPHC_OLD_LELPHC_BIN" ]]; then
        export LELPHC_BIN="$_YAMBO_LELPHC_OLD_LELPHC_BIN"
    else
        unset LELPHC_BIN
    fi
    unset _YAMBO_LELPHC_OLD_LELPHC_BIN
fi
EOF
    echo "LELPHC_BIN will be set on activation to:"
    echo "  $LELPHC_EXE"
else
    echo "No --lelphc path supplied."
    echo "Build LetzElPhC separately and use:"
    echo "  yambopy l2y ... -lelphc /path/to/LetzElPhC/src/lelphc"
fi

echo
echo "=== Final verification ==="
conda run -n "$TARGET_ENV" python "$PATCHER" --check

conda run -n "$TARGET_ENV" python - <<'PY'
import inspect
import os
import sys
import yambopy
from yambopy.exciton_phonon.excph_input_data import exc_ph_get_inputs

print("Python      :", sys.executable)
print("Prefix      :", sys.prefix)
print("YamboPy     :", os.path.realpath(yambopy.__file__))
print("EXCPH input :", inspect.signature(exc_ph_get_inputs))
PY

echo
echo "SUCCESS."
echo "Activate with:"
echo "  conda activate $TARGET_ENV"
echo
echo "Core-BSE reminders:"
echo "  * LetzElPhC must cover the full contiguous envelope (e.g. -b 1 10)."
echo "  * dipoles_path must point to the directory containing ndb.dipoles."
echo "  * Delete Dmats.npy Ex-ph.npy exc_dipoles.npy after changing the BSE band layout."
