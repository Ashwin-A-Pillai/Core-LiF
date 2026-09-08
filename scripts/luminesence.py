import numpy as np
import matplotlib.pyplot as plt
from yambopy.exciton_phonon.excph_luminescence import exc_ph_luminescence
from yambopy.exciton_phonon.excph_input_data import exc_ph_get_inputs

# This directory should play the role of "3D_hBN" in the tutorial:
path = '/home/pillai/my_codes/yambo/LiF/pbe_sr/LiF_sr.save/'

bsepath    = f'{path}/Bfull'       # Lfull BSE (finite-Q)
bseBARpath = f'{path}/Bbar'  # Lbar BSE (Q=0)
elphpath   = path                # where ndb.elph is
dipolespath = f'{path}/screening'   # where ndb.dipoles is

# Adjust this if SAVE lives somewhere else (see section 1.1)
savepath   = f'{path}/SAVE'      # where ns.db1 is

#bands_range=[0,10]
phonons_range = [0, 6]   # 6 phonon branches for c-BN

nexc_out = 1    # finite-Q excitons
nexc_in  = 10   # Q=0 excitons

T_ph  = 10
T_exc = 10

emin  = 10.3
emax  = 11.0
estep = 0.0002
broad = 0.005

# Load all inputs
input_data = exc_ph_get_inputs(
    savepath,
    elphpath,
    bsepath,
    bse_path2=bseBARpath,
    dipoles_path=dipolespath,
    nexc_in=nexc_in,
    nexc_out=nexc_out,
    phonons_range=phonons_range,
    overwrite=False,
)
ph_energies, exc_energies, exc_energies_in, G, exc_dipoles = input_data

w, PL = exc_ph_luminescence(
    T_ph, ph_energies, exc_energies, exc_dipoles, G,
    exc_energies_in=exc_energies_in, exc_temp=T_exc,
    nexc_out=nexc_out, nexc_in=nexc_in,
    emin=emin, emax=emax, estep=estep, broad=broad
)

data = np.column_stack((w, PL))
np.savetxt("LiF_luminescence_8x16.dat", data, fmt="%.8f")