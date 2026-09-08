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
