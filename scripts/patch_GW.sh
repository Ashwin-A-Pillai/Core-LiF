#!/usr/bin/env bash
#
# patch_GW.sh
#
# Patch a generated Yambo/Lumen GW input.
#
# Usage:
#   ./patch_GW.sh GW_temp.in GW.in
#
# Example overrides:
#   Polar_band=160 Block_size=8000 k_final=256 \
#   i_corband=53 f_corband=58 \
#   ./patch_GW.sh GW_temp.in GW.in
#

set -euo pipefail


###############################################################################
# Defaults with override behavior
###############################################################################

# Polarization / GW bands
: "${Polar_band:=120}"

# Screening response block size
: "${Block_size:=6000}"

# QP k-point and band range
: "${k_final:=120}"
: "${i_corband:=53}"
: "${f_corband:=58}"

# Electric-field direction
: "${efield1_x:=1.000000}"
: "${efield1_y:=0.000000}"
: "${efield1_z:=0.000000}"

# Self-energy parallelism
: "${SE_roles:=q qp b}"
: "${SE_cpu:=1 4 4}"

export Polar_band \
       Block_size \
       k_final \
       i_corband \
       f_corband \
       efield1_x \
       efield1_y \
       efield1_z \
       SE_roles \
       SE_cpu


###############################################################################
# Arguments
###############################################################################

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <input_file> [output_file]" >&2
    exit 1
fi

infile="$1"
outfile="${2:-${infile}.modified}"

if [[ ! -f "$infile" ]]; then
    echo "[ERROR] Input file not found: $infile" >&2
    exit 2
fi


###############################################################################
# Temporary output
###############################################################################

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT


###############################################################################
# Patch GW input
###############################################################################

awk \
    -v pb="$Polar_band" \
    -v bs="$Block_size" \
    -v kf="$k_final" \
    -v ic="$i_corband" \
    -v fc="$f_corband" \
    -v ex="$efield1_x" \
    -v ey="$efield1_y" \
    -v ez="$efield1_z" \
    -v seroles="$SE_roles" \
    -v secpu="$SE_cpu" '

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
    found_se_roles = 0
    found_se_cpu   = 0
}


###############################################################################
# BndsRnXp
#
# Polarization function bands
###############################################################################

/^[[:space:]]*%[[:space:]]*BndsRnXp[[:space:]]*$/ {

    print
    block = "BndsRnXp"
    next
}


block == "BndsRnXp" {

    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf "   1 | %s |", pb

        if (c != "")
            printf "                         %s", c

        printf "\n"
        next
    }

    print
    next
}


###############################################################################
# NGsBlkXp
#
# Explicit response cutoff in mHa.
# This replaces whatever RL/default specification Yambo generated.
###############################################################################

/^[[:space:]]*NGsBlkXp[[:space:]]*=/ {

    c = get_comment($0)

    printf "NGsBlkXp= %s              mHa", bs

    if (c != "")
        printf "    %s", c

    printf "\n"
    next
}


###############################################################################
# LongDrXp
#
# Screening electric-field direction
###############################################################################

/^[[:space:]]*%[[:space:]]*LongDrXp[[:space:]]*$/ {

    print
    block = "LongDrXp"
    next
}


block == "LongDrXp" {

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
# GbndRnge
#
# Number of bands entering G(W)
###############################################################################

/^[[:space:]]*%[[:space:]]*GbndRnge[[:space:]]*$/ {

    print
    block = "GbndRnge"
    next
}


block == "GbndRnge" {

    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf "   1 | %s |", pb

        if (c != "")
            printf "                         %s", c

        printf "\n"
        next
    }

    print
    next
}


###############################################################################
# QPkrange
#
# 1 | k_final | i_corband | f_corband |
###############################################################################

/^[[:space:]]*%[[:space:]]*QPkrange[[:space:]]*$/ ||
/^[[:space:]]*%QPkrange[[:space:]]*$/ {

    print
    block = "QPkrange"
    next
}


block == "QPkrange" {

    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    if ($0 !~ /^[[:space:]]*#/ &&
        $0 !~ /^[[:space:]]*$/) {

        c = get_comment($0)

        printf "  1 | %s | %s | %s |", kf, ic, fc

        if (c != "")
            printf "   %s", c

        printf "\n"
        next
    }

    print
    next
}


###############################################################################
# Existing SE_ROLEs
###############################################################################

/^[[:space:]]*SE_ROLEs[[:space:]]*=/ {

    c = get_comment($0)

    printf "SE_ROLEs= \"%s\"", seroles

    if (c != "")
        printf "    %s", c

    printf "\n"

    found_se_roles = 1
    next
}


###############################################################################
# Existing SE_CPU
###############################################################################

/^[[:space:]]*SE_CPU[[:space:]]*=/ {

    c = get_comment($0)

    printf "SE_CPU= \"%s\"", secpu

    if (c != "")
        printf "    %s", c

    printf "\n"

    found_se_cpu = 1
    next
}


###############################################################################
# Everything else passes through unchanged
###############################################################################

{
    print
}


###############################################################################
# Add self-energy parallelism if the generated GW input did not contain it
###############################################################################

END {

    if (!found_se_roles || !found_se_cpu)
        print ""

    if (!found_se_roles)
        printf "SE_ROLEs= \"%s\"\n", seroles

    if (!found_se_cpu)
        printf "SE_CPU= \"%s\"                     # [PARALLEL] CPUs for self-energy roles\n", secpu
}

' "$infile" > "$tmp"


###############################################################################
# Install result
###############################################################################

mv "$tmp" "$outfile"
trap - EXIT


###############################################################################
# Summary
###############################################################################

echo "Patched GW input written to: $outfile"
echo
echo "  Polar_band = $Polar_band"
echo "  Block_size = $Block_size mHa"
echo "  k_final    = $k_final"
echo "  i_corband  = $i_corband"
echo "  f_corband  = $f_corband"
echo "  LongDrXp   = $efield1_x $efield1_y $efield1_z"
echo "  SE_ROLEs   = $SE_roles"
echo "  SE_CPU     = $SE_cpu"