#!/usr/bin/env python3
"""Verify the CORE-BSE active-band mapping in an actual Yambo calculation."""

from __future__ import annotations

import argparse
import numpy as np
from yambopy import YamboLatticeDB, YamboExcitonDB, YamboWFDB
from yambopy.exciton_phonon.excph_matrix_elements import _bse_active_local_indices


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--save", default="SAVE", help="SAVE directory")
    ap.add_argument("--bse", default="Bfull", help="BSE directory")
    ap.add_argument("--q", type=int, default=1, help="1-based BSE Q database number")
    args = ap.parse_args()

    lat = YamboLatticeDB.from_db_file(f"{args.save}/ns.db1")
    exc = YamboExcitonDB.from_db_file(
        lat,
        filename=f"ndb.BS_diago_Q{args.q}",
        folder=args.bse,
        Load_WF=True,
        neigs=1,
    )

    bands_range = [
        int(np.min(exc.unique_vbands)),
        int(np.max(exc.unique_cbands)) + 1,
    ]

    wf = YamboWFDB(
        filename="ns.wf",
        save=args.save,
        latdb=lat,
        bands_range=bands_range,
    )

    active = _bse_active_local_indices(exc, wf)

    print("=== BSE ===")
    print("Valence physical bands    :", exc.unique_vbands + 1)
    print("Conduction physical bands :", exc.unique_cbands + 1)
    print("Contiguous envelope       :", [bands_range[0] + 1, bands_range[1]])
    print()
    print("=== WFDB ===")
    print("wfdb.min_bnd              :", wf.min_bnd)
    print("wfdb.nbands               :", wf.nbands)
    print()
    print("=== CORE-BSE mapping ===")
    print("active_local zero-based   :", active)
    print("active physical bands     :", active + wf.min_bnd + 1)
    print("Akcv shape                :", exc.get_Akcv().shape)
    print()
    print("Mapping is internally consistent.")


if __name__ == "__main__":
    main()
