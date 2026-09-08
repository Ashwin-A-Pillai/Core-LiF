#!/usr/bin/env bash
#
# patch_SEX.sh
#
# Patch ONLY existing values in a Yambo/Lumen static-screening input.
# No variables or blocks are added if they are absent from the input.
#
# Usage:
#   ./patch_SEX.sh screening_temp.in screening.in
#
# Example overrides:
#   i_corband=1 f_corband=80 NGBlk=6000 \
#   efield1_x=1 efield1_y=1 efield1_z=1 \
#   ./patch_SEX.sh screening_temp.in screening.in
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

# Polarization bands
: "${i_corband:=1}"
: "${f_corband:=10}"

# Response block cutoff
#
# NGsBlkXs will be explicitly written in mHa.
: "${NGBlk:=6000}"

# Electric-field direction
: "${efield1_x:=1.000000}"
: "${efield1_y:=0.000000}"
: "${efield1_z:=0.000000}"

# Response-function approximation
: "${CHI_MOD:=HARTREE}"


###############################################################################
# Export variables
###############################################################################

export i_corband f_corband \
       NGBlk \
       efield1_x efield1_y efield1_z \
       CHI_MOD


###############################################################################
# Temporary output
###############################################################################

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT


###############################################################################
# Patch existing values only
###############################################################################

awk \
    -v ic="$i_corband" \
    -v fc="$f_corband" \
    -v ngblk="$NGBlk" \
    -v ex="$efield1_x" \
    -v ey="$efield1_y" \
    -v ez="$efield1_z" \
    -v chimod="$CHI_MOD" '

###############################################################################
# Helper:
# Preserve original inline comments.
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
# BndsRnXs
#
# Polarization-function band range.
###############################################################################

/^[[:space:]]*%[[:space:]]*BndsRnXs[[:space:]]*$/ {

    print
    block = "BndsRnXs"
    next
}


block == "BndsRnXs" {

    # Closing %
    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    # Replace only the active data line.
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
# LongDrXs
#
# Electric-field direction used for the static response.
###############################################################################

/^[[:space:]]*%[[:space:]]*LongDrXs[[:space:]]*$/ {

    print
    block = "LongDrXs"
    next
}


block == "LongDrXs" {

    # Closing %
    if ($0 ~ /^[[:space:]]*%[[:space:]]*$/) {
        print
        block = ""
        next
    }

    # Replace only the active data line.
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
# Chimod
###############################################################################

/^[[:space:]]*Chimod[[:space:]]*=/ {

    c = get_comment($0)

    printf "Chimod= \"%s\"", chimod

    if (c != "")
        printf "                %s", c

    printf "\n"
    next
}


###############################################################################
# NGsBlkXs
#
# IMPORTANT:
#
# Explicitly replace the generated RL specification with an energy cutoff:
#
#     NGsBlkXs = <NGBlk> mHa
#
# Example:
#
#     NGsBlkXs=6000 mHa
#
# This is a deliberately chosen cutoff, NOT a numerical RL -> mHa conversion.
###############################################################################

/^[[:space:]]*NGsBlkXs[[:space:]]*=/ {

    c = get_comment($0)

    printf "NGsBlkXs= %s       mHa", ngblk

    if (c != "")
        printf "    %s", c

    printf "\n"
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