#!/usr/bin/env python3
"""
Patch YamboPy's exciton-phonon/luminescence path to support a core-BSE
band layout with a gap between active valence and conduction manifolds.

Example:
    BSEBands       = 1 ... 10
    BSEFrozenBands = "2 - 5"

Active basis:
    valence/core hole : [1]
    conduction        : [6, 7, 8, 9, 10]

The patch keeps YamboWFDB / LetzElPhC on the full contiguous envelope, but
projects symmetry matrices, electron-phonon matrices, and luminescence dipoles
onto the compact BSE-active basis before the existing YamboPy contractions.

Scope: the active valence set and active conduction set must each be internally
contiguous. A frozen-band gap BETWEEN them is supported; arbitrary holes inside
either active manifold are not.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import py_compile
import shutil
import subprocess
import sys

MARKER_EXCPH = "# CORE-BSE sparse-band support"
MARKER_DIP = "# CORE-BSE sparse dipole selection"


def die(msg: str) -> None:
    raise SystemExit(f"[ERROR] {msg}")


def imported_yambopy_root() -> Path:
    import yambopy
    return Path(yambopy.__file__).resolve().parent


def conda_prefix() -> Path | None:
    value = os.environ.get("CONDA_PREFIX")
    return Path(value).resolve() if value else None


def pip_show() -> str:
    try:
        return subprocess.check_output(
            [sys.executable, "-m", "pip", "show", "yambopy"],
            text=True,
            stderr=subprocess.STDOUT,
        )
    except Exception:
        return ""


def editable_location(show: str) -> str | None:
    for line in show.splitlines():
        if line.lower().startswith("editable project location:"):
            return line.split(":", 1)[1].strip()
    return None


def assert_environment_local(root: Path, allow_external: bool) -> None:
    prefix = conda_prefix()
    if prefix is None:
        print("[WARNING] CONDA_PREFIX is not set; cannot prove environment isolation.")
        return

    try:
        root.relative_to(prefix)
        return
    except ValueError:
        pass

    show = pip_show()
    editable = editable_location(show)
    details = f"\nImported YamboPy: {root}\nCONDA_PREFIX: {prefix}"
    if editable:
        details += f"\nEditable project location: {editable}"

    if not allow_external:
        die(
            "YamboPy is imported from outside the active Conda environment. "
            "Patching it could modify another environment/shared checkout."
            + details
            + "\nUse install_yambo_lelphc.sh to make an environment-local copy first."
        )
    print("[WARNING] Patching an external/shared YamboPy tree." + details)


def backup(path: Path) -> Path:
    dest = path.with_suffix(path.suffix + ".corebse.orig")
    if not dest.exists():
        shutil.copy2(path, dest)
        print(f"[backup] {dest}")
    else:
        print(f"[backup] already exists: {dest}")
    return dest


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        die(
            f"Could not safely patch {description}: expected exactly one anchor, "
            f"found {count}. The installed YamboPy source may have changed."
        )
    return text.replace(old, new, 1)


def patch_excph(path: Path) -> None:
    text = path.read_text()
    if MARKER_EXCPH in text:
        print(f"[skip] EXCPH patch already present: {path}")
        return

    backup(path)

    helper_anchor = "from tqdm import tqdm\n"
    helper = r'''

# CORE-BSE sparse-band support
def _bse_active_local_indices(excdb, wfdb):
    """Return BSE-active bands as compact indices relative to ``wfdb``."""
    v_abs = np.asarray(excdb.unique_vbands, dtype=int)
    c_abs = np.asarray(excdb.unique_cbands, dtype=int)

    if len(v_abs) == 0 or len(c_abs) == 0:
        raise ValueError("CORE-BSE mapping requires non-empty valence and conduction sets.")

    # YamboExcitonDB.get_Akcv itself assumes contiguous indexing within each
    # block. Reject more general sparse manifolds rather than silently err.
    if len(v_abs) > 1 and not np.all(np.diff(v_abs) == 1):
        raise NotImplementedError(
            "CORE-BSE patch does not support gaps inside the active valence manifold: "
            f"{(v_abs + 1).tolist()}"
        )
    if len(c_abs) > 1 and not np.all(np.diff(c_abs) == 1):
        raise NotImplementedError(
            "CORE-BSE patch does not support gaps inside the active conduction manifold: "
            f"{(c_abs + 1).tolist()}"
        )

    active_abs = np.concatenate((v_abs, c_abs))
    active_local = active_abs - int(wfdb.min_bnd)

    if len(np.unique(active_local)) != len(active_local):
        raise ValueError("Duplicate bands found while constructing CORE-BSE mapping.")

    if np.any(active_local < 0) or np.any(active_local >= wfdb.nbands):
        raise ValueError(
            "BSE-active bands are outside the YamboWFDB range. "
            f"active physical bands={(active_abs + 1).tolist()}, "
            f"wfdb physical range=[{wfdb.min_bnd + 1}, "
            f"{wfdb.min_bnd + wfdb.nbands}]"
        )

    return active_local
'''
    text = replace_once(text, helper_anchor, helper_anchor + helper, "CORE-BSE helper insertion")

    old = "    bse_bnds_range = [wfdb.min_bnd,wfdb.min_bnd + wfdb.nbands]\n"
    new = (
        "    bse_bnds_range = [wfdb.min_bnd,wfdb.min_bnd + wfdb.nbands]\n"
        "    # CORE-BSE: compact the contiguous electronic envelope to the\n"
        "    # bands actually present in the BSE transition table.\n"
        "    active_local = _bse_active_local_indices(exdbs[0], wfdb)\n"
    )
    text = replace_once(text, old, new, "electron-phonon active-band setup")

    old = "        elph_mat = elph_mat.transpose(1,0,2,4,3)\n"
    new = (
        "        elph_mat = elph_mat.transpose(1,0,2,4,3)\n"
        "\n"
        "        # CORE-BSE: remove frozen/intermediate bands and reorder the\n"
        "        # operator as [active valence, active conduction].\n"
        "        elph_mat = np.take(elph_mat, active_local, axis=-2)\n"
        "        elph_mat = np.take(elph_mat, active_local, axis=-1)\n"
    )
    text = replace_once(text, old, new, "electron-phonon matrix projection")

    old = "        AQibz = excdbin.get_Akcv()\n"
    new = "        AQibz = excdbin.get_Akcv()\n        excdb_for_bands = excdbin\n"
    text = replace_once(text, old, new, "Lin BSE band-source assignment")

    old = "    else : AQibz = exdbs[iQ_iBZ].get_Akcv()\n"
    new = (
        "    else:\n"
        "        excdb_for_bands = exdbs[iQ_iBZ]\n"
        "        AQibz = excdb_for_bands.get_Akcv()\n"
    )
    text = replace_once(text, old, new, "Lout BSE band-source assignment")

    old = (
        "    AQ_rot = rotate_exc_wf(AQibz,symm_mat_red,wfdb.kBZ,"
        "exe_iQIBZ,Dmats[iQ_isymm],trev,wfdb.ktree)\n"
    )
    new = (
        "    # CORE-BSE: rotate_exc_wf assumes D is ordered as\n"
        "    # [valence, conduction]. Project D onto the actual active bands.\n"
        "    active_local = _bse_active_local_indices(excdb_for_bands, wfdb)\n"
        "\n"
        "    expected_nv = len(excdb_for_bands.unique_vbands)\n"
        "    expected_nc = len(excdb_for_bands.unique_cbands)\n"
        "    if AQibz.shape[-2:] != (expected_nc, expected_nv):\n"
        "        raise ValueError(\n"
        "            'Unexpected Akcv shape for CORE-BSE mapping: '\n"
        "            f'{AQibz.shape[-2:]}; expected ({expected_nc}, {expected_nv})'\n"
        "        )\n"
        "\n"
        "    dmat_iQ = Dmats[iQ_isymm]\n"
        "    dmat_iQ = np.take(dmat_iQ, active_local, axis=-2)\n"
        "    dmat_iQ = np.take(dmat_iQ, active_local, axis=-1)\n"
        "\n"
        "    AQ_rot = rotate_exc_wf(\n"
        "        AQibz, symm_mat_red, wfdb.kBZ, exe_iQIBZ,\n"
        "        dmat_iQ, trev, wfdb.ktree\n"
        "    )\n"
    )
    text = replace_once(text, old, new, "symmetry D-matrix projection")

    path.write_text(text)
    print(f"[patched] {path}")


def patch_dipoles(path: Path) -> None:
    text = path.read_text()
    if MARKER_DIP in text:
        print(f"[skip] dipole patch already present: {path}")
        return

    backup(path)

    old = "        dipoles = ydip.dipoles\n"
    new = (
        "        dipoles = ydip.dipoles\n"
        "        # CORE-BSE bookkeeping: physical zero-based origins of the\n"
        "        # valence and conduction axes in this dipole array.\n"
        "        dip_v0 = ydip.min_band - 1\n"
        "        dip_c0 = ydip.indexc\n"
    )
    text = replace_once(text, old, new, "normal dipole band-origin bookkeeping")

    old = (
        "        dipoles = quick_read_dipoles("
        "f'{dipoles_path}/ndb.dipoles',yexc.bs_bands,ylat.nbandsv)\n"
    )
    new = (
        "        dipoles = quick_read_dipoles("
        "f'{dipoles_path}/ndb.dipoles',yexc.bs_bands,ylat.nbandsv)\n"
        "        dip_v0 = yexc.bs_bands[0] - 1\n"
        "        dip_c0 = ylat.nbandsv\n"
    )
    text = replace_once(text, old, new, "fallback dipole band-origin bookkeeping")

    anchor = "    # Expand dipoles\n"
    insertion = r'''    # CORE-BSE sparse dipole selection
    # ndb.dipoles can contain occupied bands frozen out of a core BSE.
    # Keep only the valence/conduction bands present in BS_TABLE.
    v_active = np.asarray(yexc.unique_vbands, dtype=int)
    c_active = np.asarray(yexc.unique_cbands, dtype=int)

    if len(v_active) > 1 and not np.all(np.diff(v_active) == 1):
        raise NotImplementedError(
            "CORE-BSE patch does not support gaps inside the active valence manifold: "
            f"{(v_active + 1).tolist()}"
        )
    if len(c_active) > 1 and not np.all(np.diff(c_active) == 1):
        raise NotImplementedError(
            "CORE-BSE patch does not support gaps inside the active conduction manifold: "
            f"{(c_active + 1).tolist()}"
        )

    v_rel = v_active - int(dip_v0)
    c_rel = c_active - int(dip_c0)

    if (
        np.any(v_rel < 0) or np.any(v_rel >= dipoles.shape[-1])
        or np.any(c_rel < 0) or np.any(c_rel >= dipoles.shape[-2])
    ):
        raise ValueError(
            "Active BSE bands cannot be mapped onto ndb.dipoles. "
            f"active valence physical={(v_active + 1).tolist()}, "
            f"active conduction physical={(c_active + 1).tolist()}, "
            f"dipole shape={dipoles.shape}, dip_v0={dip_v0}, dip_c0={dip_c0}"
        )

    dipoles = np.take(dipoles, c_rel, axis=-2)
    dipoles = np.take(dipoles, v_rel, axis=-1)

'''
    text = replace_once(text, anchor, insertion + anchor, "sparse dipole projection")

    path.write_text(text)
    print(f"[patched] {path}")


def restore_file(path: Path) -> None:
    source = path.with_suffix(path.suffix + ".corebse.orig")
    if not source.exists():
        print(f"[skip] no backup for {path}")
        return
    shutil.copy2(source, path)
    print(f"[restored] {path}")


def check(root: Path) -> bool:
    excph = root / "exciton_phonon" / "excph_matrix_elements.py"
    dip = root / "bse" / "excitondipoles.py"
    ok = True

    print(f"YamboPy root: {root}")
    for path, marker in ((excph, MARKER_EXCPH), (dip, MARKER_DIP)):
        if not path.exists():
            print(f"[FAIL] missing: {path}")
            ok = False
            continue
        present = marker in path.read_text()
        print(f"[{'OK' if present else 'FAIL'}] {path.name}: marker {'present' if present else 'absent'}")
        ok = ok and present

    if ok:
        try:
            py_compile.compile(str(excph), doraise=True)
            py_compile.compile(str(dip), doraise=True)
            print("[OK] Python syntax check")
        except Exception as exc:
            print(f"[FAIL] Python syntax check: {exc}")
            ok = False
    return ok


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", help="Path to the yambopy package directory")
    ap.add_argument("--check", action="store_true", help="Verify patch markers and syntax")
    ap.add_argument("--restore", action="store_true", help="Restore *.corebse.orig backups")
    ap.add_argument(
        "--allow-external",
        action="store_true",
        help="Allow patching outside CONDA_PREFIX (unsafe for shared editable installs)",
    )
    args = ap.parse_args()

    root = Path(args.root).expanduser().resolve() if args.root else imported_yambopy_root()
    if not root.exists():
        die(f"YamboPy root does not exist: {root}")

    if not args.root:
        assert_environment_local(root, args.allow_external)

    excph = root / "exciton_phonon" / "excph_matrix_elements.py"
    dip = root / "bse" / "excitondipoles.py"

    if args.restore:
        restore_file(excph)
        restore_file(dip)
        print("Restore complete.")
        return

    if args.check:
        raise SystemExit(0 if check(root) else 1)

    if not excph.exists() or not dip.exists():
        die(f"Required YamboPy files not found:\n  {excph}\n  {dip}")

    patch_excph(excph)
    patch_dipoles(dip)

    if not check(root):
        die("Patch verification failed.")
    print("\nCORE-BSE YamboPy patch installed successfully.")


if __name__ == "__main__":
    main()
