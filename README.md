# `yambo-lelphc` reproducible environment + CORE-BSE patch

This bundle creates an **isolated YamboPy Conda environment** and applies the
modifications needed for exciton–phonon/luminescence calculations where
`BSEFrozenBands` creates a gap between the active core/valence manifold and the
active conduction manifold.

Representative case:

```text
BSEBands       = 1 ... 10
BSEFrozenBands = "2 - 5"

active valence/core-hole = [1]
active conduction        = [6,7,8,9,10]
```

Stock YamboPy's exciton–phonon path assumes an operator basis ordered
contiguously as `[valence, conduction]`. The patch keeps the full contiguous
electronic envelope for raw databases, then projects the symmetry `D`,
electron–phonon `g`, and luminescence dipole matrices onto the compact
BSE-active ordering before the existing YamboPy contractions.

## Files

- `install_yambo_lelphc.sh` — create/clone environment, isolate YamboPy, patch, verify.
- `patch_yambopy_core_bse.py` — standalone idempotent patcher/restorer.
- `verify_core_bse_mapping.py` — verify a real calculation's band mapping.

## A. Fresh YamboPy install

```bash
chmod +x install_yambo_lelphc.sh

./install_yambo_lelphc.sh \
  --mode pip \
  --env yambo-lelphc
```

Optional version pin:

```bash
./install_yambo_lelphc.sh \
  --mode pip \
  --env yambo-lelphc \
  --yambopy-spec 'yambopy==0.7.1'
```

## B. Clone an existing Conda environment

```bash
./install_yambo_lelphc.sh \
  --mode clone \
  --source-env yambo-env \
  --env yambo-lelphc
```

This explicitly handles a shared editable YamboPy install. A plain Conda clone
can leave both environments importing the same external source tree; this
installer detects that and installs a private non-editable copy into the new
environment before patching it.

## C. Install from an existing YamboPy source tree

```bash
./install_yambo_lelphc.sh \
  --mode source \
  --source /path/to/existing/yambopy \
  --env yambo-lelphc
```

No YamboPy Git clone is required.

## Optional LetzElPhC binary

If already compiled:

```bash
./install_yambo_lelphc.sh \
  --mode clone \
  --source-env yambo-env \
  --lelphc /path/to/LetzElPhC/src/lelphc
```

Then:

```bash
conda activate yambo-lelphc
echo "$LELPHC_BIN"
```

The installer intentionally does **not** compile LetzElPhC. Its build is
machine/HPC-specific and requires a C99 compiler, MPI, FFTW3 or MKL, parallel
HDF5, parallel NetCDF-C, BLAS, GNU Make, and a site-specific `src/make.inc`.

## Reference LiF workflow: QE → Yambo/Lumen → LetzElPhC → luminescence

A complete working LiF example is available in the
[`Core-LiF`](https://github.com/Ashwin-A-Pillai/Core-LiF) repository.

The main production jobs are in:

- [`scripts/SLURM/scf.job`](https://github.com/Ashwin-A-Pillai/Core-LiF/blob/main/scripts/SLURM/scf.job)
- [`scripts/SLURM/X_P.job`](https://github.com/Ashwin-A-Pillai/Core-LiF/blob/main/scripts/SLURM/X_P.job)
- [`scripts/luminesence.py`](https://github.com/Ashwin-A-Pillai/Core-LiF/blob/main/scripts/luminesence.py)

The overall workflow is:

```text
Quantum ESPRESSO
    │
    ├── SCF
    ├── NSCF
    └── ph.x
         │
         ▼
pbe_sr/LiF_sr.save + phonon data
         │
         ▼
p2y / Yambo initialization
         │
         ├── GW0
         ├── static screening
         ├── BSE full, finite Q
         └── BSE BAR, Q = 0
                │
                ▼
             LetzElPhC
                │
                ▼
             ndb.elph
                │
                ▼
       patched yambo-lelphc
                │
                ▼
       exciton-phonon matrix G
                │
                ▼
      phonon-assisted luminescence
```

### Stage 1 — QE SCF, NSCF and phonons

Use:

```text
scripts/SLURM/scf.job
```

Reference:

```text
https://github.com/Ashwin-A-Pillai/Core-LiF/blob/main/scripts/SLURM/scf.job
```

Submit it from the **Core-LiF project root**, i.e. the directory containing
`LiF.scf_sr.in`, `LiF.nscf_sr.in`, `LiF.pho.in`, and `PS/`:

```bash
cd Core-LiF
sbatch scripts/SLURM/scf.job
```

The current reference job:

1. loads the Quantum ESPRESSO/HPC module stack;
2. creates the SCF input from `LiF.scf_sr.in`;
3. creates the NSCF input from `LiF.nscf_sr.in`;
4. applies the requested cutoff, band count and k mesh;
5. runs `pw.x` for the SCF calculation;
6. verifies that the SCF output contains `JOB DONE`;
7. runs `pw.x` for the NSCF calculation;
8. runs `ph.x` using `LiF.pho.in`.

The current reference parameters include:

```text
SCF_NK  = 8
NSCF_NK = 8
ECUTWFC = 80 Ry
NBND    = 10
NPOOL   = 4
```

The reference job uses 24 MPI ranks with 2 OpenMP threads per rank. These
SLURM resources and module names are site-specific and should be adapted on
another machine.

The important electronic output is:

```text
pbe_sr/LiF_sr.save/
```

This is the QE database used by `p2y` in the next stage. The phonon calculation
must also finish successfully because the later LetzElPhC step uses the QE
phonon data and `LiF.pho.in`.

### Stage 2 — GW0, screening, BSE, LetzElPhC and luminescence

Use:

```text
scripts/SLURM/X_P.job
```

Reference:

```text
https://github.com/Ashwin-A-Pillai/Core-LiF/blob/main/scripts/SLURM/X_P.job
```

This job should be run from the QE save directory produced in Stage 1:

```bash
cd Core-LiF/pbe_sr/LiF_sr.save
sbatch ../../scripts/SLURM/X_P.job
```

The working-directory assumption matters. The reference LetzElPhC call uses:

```bash
-ph "../../LiF.pho.in"
```

which is correct when the current directory is:

```text
Core-LiF/pbe_sr/LiF_sr.save/
```

The reference `X_P.job` performs the following sequence.

#### 2.1 Convert QE data and initialize Yambo

```text
p2y
yambo
```

This creates the local Yambo `SAVE/` database from the QE calculation.

#### 2.2 GW0

The job generates and patches a GW input and runs a `GW0` calculation. In the
reference LiF setup the electronic range extends over bands 1–10.

#### 2.3 Static screening

The job performs static screening and creates the `screening` job database.

This is also where the `ndb.dipoles` database used by the reference
luminescence post-processing is located:

```text
screening/ndb.dipoles
```

Therefore the Python input uses:

```python
dipolespath = f"{path}/screening"
```

rather than assuming `ndb.dipoles` is located in `Bfull`.

#### 2.4 Finite-Q BSE: `Bfull`

The first BSE uses:

```text
LKind = "full"
```

and spans the finite-Q BSE databases required by the exciton-phonon
calculation.

For the current LiF core-BSE reference:

```text
BSEBands       = 1 ... 10
BSEFrozenBands = 2 ... 5
```

so the actual active transition space is:

```text
core/valence hole : band 1
conduction        : bands 6,7,8,9,10
```

The finite-Q BSE databases are written under:

```text
Bfull/
```

#### 2.5 Q=0 BAR BSE: `Bbar`

The second BSE uses:

```text
LKind = "BAR"
```

with only the Q=0 database. Its output is stored under:

```text
Bbar/
```

This database supplies the Q=0/intermediate excitons used by the
phonon-assisted luminescence calculation.

#### 2.6 Remove stale YamboPy caches

Before regenerating the exciton-phonon quantities, the reference job removes:

```bash
rm -f Dmats.npy Ex-ph.npy exc_dipoles.npy
```

This is required whenever the BSE band layout, wavefunctions, phonons or
relevant databases have changed.

#### 2.7 Run LetzElPhC through YamboPy

The job activates the patched environment:

```bash
conda activate yambo-lelphc
```

and then runs:

```bash
yambopy l2y   -ph "../../LiF.pho.in"   -b 1 10   -par 4 2   -lelphc "/path/to/LetzElPhC/src/lelphc"
```

For the LiF core-BSE case, **keep `-b 1 10`**.

Bands 2–5 are frozen in the BSE, but the raw LetzElPhC/YamboPy electronic
database must still span the full contiguous envelope containing both the
core-hole band and the active conduction bands. The CORE-BSE patch performs the
later projection:

```text
[1,2,3,4,5,6,7,8,9,10]
            ↓
[1,6,7,8,9,10]
```

before the symmetry and exciton-phonon contractions.

#### 2.8 Luminescence

The last step is:

```bash
python3 luminesence.py
```

Reference:

```text
https://github.com/Ashwin-A-Pillai/Core-LiF/blob/main/scripts/luminesence.py
```

The reference script reads:

```text
SAVE/ns.db1
Bfull/ndb.BS_diago_Q*
Bbar/ndb.BS_diago_Q1
ndb.elph
screening/ndb.dipoles
```

and calculates the phonon-assisted luminescence using
`exc_ph_get_inputs()` and `exc_ph_luminescence()`.

For a portable checkout, either copy the script into the save directory:

```bash
cp ../../scripts/luminesence.py .
python3 luminesence.py
```

or change `X_P.job` to call it through its repository path:

```bash
python3 ../../scripts/luminesence.py
```

The `path` variable inside `luminesence.py` must also point to the actual
calculation directory on the local machine.

### Complete reference submission sequence

Starting from a checkout:

```bash
git clone https://github.com/Ashwin-A-Pillai/Core-LiF.git
cd Core-LiF
```

Run Quantum ESPRESSO first:

```bash
sbatch scripts/SLURM/scf.job
```

After that job completes successfully:

```bash
cd pbe_sr/LiF_sr.save
cp ../../scripts/luminesence.py .
sbatch ../../scripts/SLURM/X_P.job
```

The intended dependency chain is:

```text
scf.job
   │
   ├─ pw.x SCF
   ├─ pw.x NSCF
   └─ ph.x
       │
       ▼
X_P.job
   │
   ├─ p2y + yambo initialization
   ├─ GW0
   ├─ screening
   ├─ Bfull
   ├─ Bbar
   ├─ yambopy l2y / LetzElPhC
   └─ luminesence.py
```

### Paths and settings that must be adapted on another cluster

The reference SLURM files are working examples, not universally portable job
files. At minimum, review:

```text
#SBATCH --partition
#SBATCH --nodes
#SBATCH --ntasks
#SBATCH --cpus-per-task
```

and the `module load` commands.

In `X_P.job`, also change the machine-specific paths for:

```text
YAMBO
P2Y
YNL
YRT
YPP
scripts
LetzElPhC/src/lelphc
```

The calculation parameters must also be checked rather than copied blindly:

```text
QE_NBND
BSE_NBND
DEFAULT_K_FINAL
NGBlk
BSE_EX
BSE band range
BSEFrozenBands
GW/QP parameters
parallel CPU layouts
```

For a different material or k mesh, `DEFAULT_K_FINAL` in particular must match
the finite-Q BSE database range required by the calculation.

The SLURM reference directory is:

```text
https://github.com/Ashwin-A-Pillai/Core-LiF/tree/main/scripts/SLURM
```


## Core-BSE usage rules

For:

```text
active physical bands = [1,6,7,8,9,10]
```

keep raw databases on the **full contiguous envelope**:

```bash
yambopy l2y ... -b 1 10 ...
```

Do not change that to `-b 6 10`: the core-hole band is required.

YamboPy revisions differ on whether `exc_ph_get_inputs` exposes `bands_range`
or infers it internally. This patch does not require modifying
`excph_input_data.py`; it only requires the resulting `YamboWFDB` to span the
full envelope containing the active bands.

### Dipoles path

`dipoles_path` must be the directory that actually contains `ndb.dipoles`, for
example:

```python
dipolespath = f"{path}/screening"
```

It need not be `Bfull`.

### Cache invalidation

After installing the patch, or after changing the BSE band layout:

```bash
rm -f Dmats.npy Ex-ph.npy exc_dipoles.npy
```

After a successful unchanged run, caches can be reused with `overwrite=False`.

## Verify

```bash
conda activate yambo-lelphc
python patch_yambopy_core_bse.py --check
```

In a calculation directory:

```bash
python verify_core_bse_mapping.py --save SAVE --bse Bfull
```

For the LiF example, expected mapping:

```text
Valence physical bands    : [1]
Conduction physical bands : [ 6  7  8  9 10]
active_local zero-based   : [0 5 6 7 8 9]
active physical bands     : [ 1  6  7  8  9 10]
Akcv shape                : (..., 5, 1)
```

## Scope

Supported: a frozen-band gap **between** internally contiguous active valence
and conduction manifolds, e.g.

```text
v=[1],   c=[6,7,8,9,10]
v=[1,2], c=[6,7,8,9,10]
```

Not claimed:

```text
v=[1,3], c=[6,8,9]
```

because `YamboExcitonDB.get_Akcv()` itself assumes contiguous indexing within
each valence/conduction block.

## Restore

```bash
conda activate yambo-lelphc
python patch_yambopy_core_bse.py --restore
```

A future YamboPy release may change the relevant source. The patcher is
fail-safe: if its expected anchors no longer match, it stops rather than
guessing and risking a silently incorrect physics calculation.
