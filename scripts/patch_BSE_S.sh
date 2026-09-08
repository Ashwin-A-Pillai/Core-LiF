#!/usr/bin/env bash
#
# patch_BSE_S.sh
#
# Patch ONLY existing values in a Yambo/Lumen BSE input.
# No variables or blocks are added if they are absent.
#
# Usage:
#   ./patch_BSE_S.sh bse_s.in BSE.in
#
# Example:
#   BSE_EX=20000 LKind=BAR iE=0 fE=10 \
#   ./patch_BSE_S.sh bse_s.in BSE.in
#

set -euo pipefail

###############################################################################
# Arguments
###############################################################################

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <input_file> [output_file]" >&2
    exit 1
fi

infile="$1"
outfile="${2:-${infile%.in}_patched.in}"

if [[ ! -f "$infile" ]]; then
    echo "[ERROR] Input file not found: $infile" >&2
    exit 2
fi

###############################################################################
# User-tunable defaults
###############################################################################

# Database I/O
: "${DB_off:=BS}"

# Dipole bands
: "${i_db:=1}"
: "${f_db:=10}"

# BSE kernel
# BSENGexx is explicitly written in mHa.
# BSENGBlk is kept at -1 RL.
: "${BSE_EX:=8000}"

# QP database
: "${QPdir:=E < GW0/ndb.QP}"

# Scissor/stretch parameters
: "${KE_V:=6.00000}"
: "${KE_v:=1.050000}"
: "${KE_c:=1.050000}"

# BSE q-points
: "${iq:=1}"
: "${fq:=1}"

# Response kind
: "${LKind:=BAR}"

# BSE bands
: "${i_corband:=1}"
: "${f_corband:=10}"

# Frozen bands
: "${i_FzB:=2}"
: "${f_FzB:=2}"

# Spectrum
: "${iE:=0.00000}"
: "${fE:=10.00000}"
: "${BS_Esteps:=5001}"

# Electric-field direction
: "${efield1_x:=1.000000}"
: "${efield1_y:=0.000000}"
: "${efield1_z:=0.000000}"

# BSE properties
: "${B_prp:=abs esrt}"

# Diagonalization library
: "${BdL:=e2}"

# Parallelization
: "${BS_CPU_LAYOUT:=4.6}"
: "${BS_ROLES:=eh.k}"
: "${BS_INV_CPUS:=4}"
: "${BS_DIAGO_CPUS:=4}"

export DB_off \
       i_db f_db \
       BSE_EX \
       QPdir \
       KE_V KE_v KE_c \
       iq fq LKind \
       i_corband f_corband \
       i_FzB f_FzB \
       iE fE BS_Esteps \
       efield1_x efield1_y efield1_z \
       B_prp BdL \
       BS_CPU_LAYOUT BS_ROLES \
       BS_INV_CPUS BS_DIAGO_CPUS

###############################################################################
# Temporary output
###############################################################################

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

###############################################################################
# Patch existing variables only
###############################################################################

awk \
    -v db_off="$DB_off" \
    -v idb="$i_db" \
    -v fdb="$f_db" \
    -v bex="$BSE_EX" \
    -v qpdir="$QPdir" \
    -v kev="$KE_V" \
    -v kevs="$KE_v" \
    -v kecs="$KE_c" \
    -v iq="$iq" \
    -v fq="$fq" \
    -v lkind="$LKind" \
    -v ic="$i_corband" \
    -v fc="$f_corband" \
    -v ifz="$i_FzB" \
    -v ffz="$f_FzB" \
    -v ie="$iE" \
    -v fe="$fE" \
    -v esteps="$BS_Esteps" \
    -v ex="$efield1_x" \
    -v ey="$efield1_y" \
    -v ez="$efield1_z" \
    -v bprop="$B_prp" \
    -v bdlib="$BdL" \
    -v bscpu="$BS_CPU_LAYOUT" \
    -v bsroles="$BS_ROLES" \
    -v invcpu="$BS_INV_CPUS" \
    -v diagcpu="$BS_DIAGO_CPUS" '

###############################################################################
# Helper
###############################################################################

function get_comment(s,    p) {
    p = index(s, "#")
    if (p > 0)
        return substr(s, p)
    return ""
}

BEGIN {
    block = ""
}

###############################################################################
# DipBands
###############################################################################

/^[[:space:]]*%[[:space:]]*DipBands[[:space:]]*$/ {
    print
    block = "DipBands"
    next
}

block == "DipBands" {
    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf "  %s | %s |", idb, fdb

        if (c != "")
            printf "                           %s", c

        printf "\n"
        next
    }

    print
    next
}

###############################################################################
# KfnQP_E
###############################################################################

/^[[:space:]]*%[[:space:]]*KfnQP_E[[:space:]]*$/ {
    print
    block = "KfnQP_E"
    next
}

block == "KfnQP_E" {
    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf " %s | %s | %s |", kev, kevs, kecs

        if (c != "")
            printf "        %s", c

        printf "\n"
        next
    }

    print
    next
}

###############################################################################
# BSEQptR
###############################################################################

/^[[:space:]]*%[[:space:]]*BSEQptR[[:space:]]*$/ {
    print
    block = "BSEQptR"
    next
}

block == "BSEQptR" {
    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf " %s | %s |", iq, fq

        if (c != "")
            printf "                             %s", c

        printf "\n"
        next
    }

    print
    next
}

###############################################################################
# BSEBands
###############################################################################

/^[[:space:]]*%[[:space:]]*BSEBands[[:space:]]*$/ {
    print
    block = "BSEBands"
    next
}

block == "BSEBands" {
    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf "  %s | %s |", ic, fc

        if (c != "")
            printf "                           %s", c

        printf "\n"
        next
    }

    print
    next
}

###############################################################################
# BEnRange
###############################################################################

/^[[:space:]]*%[[:space:]]*BEnRange[[:space:]]*$/ {
    print
    block = "BEnRange"
    next
}

block == "BEnRange" {
    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf "  %s | %s |         eV", ie, fe

        if (c != "")
            printf "    %s", c

        printf "\n"
        next
    }

    print
    next
}

###############################################################################
# BLongDir
###############################################################################

/^[[:space:]]*%[[:space:]]*BLongDir[[:space:]]*$/ {
    print
    block = "BLongDir"
    next
}

block == "BLongDir" {
    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf " %s | %s | %s |", ex, ey, ez

        if (c != "")
            printf "        %s", c

        printf "\n"
        next
    }

    print
    next
}

###############################################################################
# Scalar values
###############################################################################

# DBsIOoff
/^[[:space:]]*DBsIOoff[[:space:]]*=/ {
    c = get_comment($0)

    printf "DBsIOoff= \"%s\"", db_off

    if (c != "")
        printf "                 %s", c

    printf "\n"
    next
}

# Lkind
/^[[:space:]]*Lkind[[:space:]]*=/ {
    c = get_comment($0)

    printf "Lkind= \"%s\"", lkind

    if (c != "")
        printf "                     %s", c

    printf "\n"
    next
}

# BSENGexx
# Explicit exchange cutoff in mHa.
/^[[:space:]]*BSENGexx[[:space:]]*=/ {
    c = get_comment($0)

    printf "BSENGexx= %s            mHa", bex

    if (c != "")
        printf "    %s", c

    printf "\n"
    next
}

# BSENGBlk
#
# -1 RL means use all G-vectors available in the screening database.
# Do NOT convert this to mHa.
/^[[:space:]]*BSENGBlk[[:space:]]*=/ {
    c = get_comment($0)

    printf "BSENGBlk= -1             RL"

    if (c != "")
        printf "    %s", c

    printf "\n"
    next
}

# KfnQPdb
/^[[:space:]]*KfnQPdb[[:space:]]*=/ {
    c = get_comment($0)

    printf "KfnQPdb= \"%s\"", qpdir

    if (c != "")
        printf "                  %s", c

    printf "\n"
    next
}

# Frozen bands
/^[[:space:]]*BSEFrozenBands[[:space:]]*=/ {
    c = get_comment($0)

    printf "BSEFrozenBands=\"%s - %s\"", ifz, ffz

    if (c != "")
        printf "               %s", c

    printf "\n"
    next
}

# Spectrum points
/^[[:space:]]*BEnSteps[[:space:]]*=/ {
    c = get_comment($0)

    printf "BEnSteps= %s", esteps

    if (c != "")
        printf "                    %s", c

    printf "\n"
    next
}

# BSE properties
/^[[:space:]]*BSEprop[[:space:]]*=/ {
    c = get_comment($0)

    printf "BSEprop= \"%s\"", bprop

    if (c != "")
        printf "                   %s", c

    printf "\n"
    next
}

# Diagonalization library
/^[[:space:]]*BSSldiaLib[[:space:]]*=/ {
    c = get_comment($0)

    printf "BSSldiaLib= \"%s\"", bdlib

    if (c != "")
        printf "                  %s", c

    printf "\n"
    next
}

###############################################################################
# Parallelization
###############################################################################

/^[[:space:]]*BS_CPU[[:space:]]*=/ {
    c = get_comment($0)

    printf "BS_CPU= \"%s\"", bscpu

    if (c != "")
        printf "                       %s", c

    printf "\n"
    next
}

/^[[:space:]]*BS_ROLEs[[:space:]]*=/ {
    c = get_comment($0)

    printf "BS_ROLEs= \"%s\"", bsroles

    if (c != "")
        printf "                    %s", c

    printf "\n"
    next
}

/^[[:space:]]*BS_nCPU_LinAlg_INV[[:space:]]*=/ {
    c = get_comment($0)

    printf "BS_nCPU_LinAlg_INV=%s", invcpu

    if (c != "")
        printf "            %s", c

    printf "\n"
    next
}

/^[[:space:]]*BS_nCPU_LinAlg_DIAGO[[:space:]]*=/ {
    c = get_comment($0)

    printf "BS_nCPU_LinAlg_DIAGO=%s", diagcpu

    if (c != "")
        printf "          %s", c

    printf "\n"
    next
}

###############################################################################
# Uncomment WRbsWF only if it already exists commented
###############################################################################

/^[[:space:]]*#[[:space:]]*WRbsWF([[:space:]]|$)/ {
    line = $0
    sub(/#[[:space:]]*/, "", line)
    print line
    next
}

###############################################################################
# Everything else is preserved exactly
###############################################################################

{
    print
}

' "$infile" > "$tmp"

###############################################################################
# Install result
###############################################################################

mv "$tmp" "$outfile"
trap - EXIT

echo "Wrote: $outfile"
echo "  Lkind             = $LKind"
echo "  BSE bands         = $i_corband - $f_corband"
echo "  Frozen bands      = $i_FzB - $f_FzB"
echo "  BSENGexx          = $BSE_EX mHa"
echo "  BSENGBlk          = -1 RL"
echo "  BS_CPU            = $BS_CPU_LAYOUT"
echo "  BS_ROLEs          = $BS_ROLES"