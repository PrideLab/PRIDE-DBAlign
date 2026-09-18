#!/bin/bash

###############################################################################
##                                                                           ##
##  PURPOSE: Merge ALGIRC logs and plot day-boundary heatmaps                ##
##                                                                           ##
##  AUTHOR : PRIDE LAB      pride@apm.ac.cn                                  ##
##                                                                           ##
##  VERSION: ver 1.0                                                         ##
##                                                                           ##
##  DATE   : July-07, 2026                                                   ##
##                                                                           ##
##   @ State Key Laboratory of Precision Geodesy,                            ##
##   Chinese Academy of Sciences                                             ##
##                                                                           ##
##    Copyright (C) 2026 by SKLPG, CAS and Wuhan University                  ##
##                                                                           ##
##    This program is free software: you can redistribute it and/or modify   ##
##    it under the terms of the GNU General Public License (version 3) as    ##
##    published by the Free Software Foundation.                             ##
##                                                                           ##
##    This program is distributed in the hope that it will be useful,        ##
##    but WITHOUT ANY WARRANTY; without even the implied warranty of         ##
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the           ##
##    GNU General Public License (version 3) for more details.               ##
##                                                                           ##
##    You should have received a copy of the GNU General Public License      ##
##    along with this program. If not, see <https://www.gnu.org/licenses/>.  ##
##                                                                           ##
###############################################################################

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
readonly SUM_LOG="algirc-sum.out"
readonly LOG_PATTERN="algirc-[0-9][0-9][0-9][0-9][0-9].out"
readonly SAT_PARAMETERS_URL="ftp://igs.gnsswhu.cn/pub/whu/phasebias/table/sat_parameters"
readonly PLOT_SCRIPTS="${PDBA_PLOT_SCRIPTS:-
plot-orbdbd.py
plot-wlpdbd.py
plot-dcbdbd.py
plot-ircdbd.py
}"

print_usage() {
    local prog
    prog=${PDBA_PLOT_PROGRAM:-$(basename "$0")}

    cat <<EOF
usage: $prog log_directory

  log_directory    directory containing algirc-MJD.out files or
                   an existing algirc-sum.out summary

example:
  $prog align_run/2025_aligned
EOF
}

resolve_python() {
    if command -v python3 >/dev/null 2>&1; then
        command -v python3
        return
    fi
    if command -v python >/dev/null 2>&1; then
        command -v python
        return
    fi

    echo "***ERROR: python3 or python not found in PATH" >&2
    exit 1
}

ymd2mjd() {
    local year=$1
    local mon=$((10#$2))
    local day=$((10#$3))
    [ $year -lt 100 ] && year=$((year+2000))
    if [ $mon -le 2 ];then
        mon=$(($mon+12))
        year=$(($year-1))
    fi
    local mjd=`echo $year | awk '{print $1*365.25-$1*365.25%1-679006}'`
    mjd=`echo $mjd $year $mon $day | awk '{print $1+int(30.6001*($3+1))+2-int($2/100)+int($2/400)+$4}'`
    echo $mjd
}

summary_end_mjd() {
    local summary_log=$1

    awk '
        substr($0, 1, 1) == " " &&
        substr($0, 14, 5) ~ /^[0-9][0-9][0-9][0-9][0-9]$/ &&
        (length($0) == 38 || length($0) == 78 || length($0) == 80 ||
         length($0) == 89 || length($0) == 98) {
            mjd = substr($0, 14, 5) + 0
            found = 1
        }
        END { if (found) print mjd; else exit 1 }
    ' "$summary_log"
}

valid_sat_parameters() {
    local sat_file=$1

    [ -s "$sat_file" ] && grep -q '^-prn_indexed' "$sat_file"
}

sat_parameters_mjd() {
    local sat_file=$1
    local header

    header=$(sed -n '1p' "$sat_file")
    if [[ "$header" =~ UTC\+0[[:space:]]+([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
        ymd2mjd "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return
    fi

    return 1
}

download_sat_parameters() {
    local url=$1
    local output=$2

    if command -v wget >/dev/null 2>&1 && \
       wget -q -nv -t 3 --connect-timeout=10 --read-timeout=60 \
           -O "$output" "$url"; then
        return
    fi

    if command -v curl >/dev/null 2>&1 && \
       curl --fail --location --silent --show-error --retry 3 \
           --connect-timeout 10 --max-time 60 --output "$output" "$url"; then
        return
    fi

    echo "***WARNING: cannot download sat_parameters with wget or curl" >&2
    return 1
}

prepare_sat_parameters() {
    local log_dir=$1
    local summary_log=$2
    local sat_dst="$log_dir/sat_parameters"
    local sat_src
    local bundled_sat
    local end_mjd
    local table_mjd=""
    local update_reason=""
    local download_tmp=""

    if [ -f "$SCRIPT_DIR/sat_parameters" ]; then
        bundled_sat="$SCRIPT_DIR/sat_parameters"
    elif [ -f "$SCRIPT_DIR/../table/sat_parameters" ]; then
        bundled_sat="$SCRIPT_DIR/../table/sat_parameters"
    elif [ -d "$SCRIPT_DIR/../table" ]; then
        bundled_sat="$SCRIPT_DIR/../table/sat_parameters"
    else
        bundled_sat="$SCRIPT_DIR/sat_parameters"
    fi

    if [ -f "$sat_dst" ]; then
        sat_src=$sat_dst
    else
        sat_src=$bundled_sat
    fi

    end_mjd=$(summary_end_mjd "$summary_log")
    if valid_sat_parameters "$sat_src"; then
        table_mjd=$(sat_parameters_mjd "$sat_src" || true)
        if [ -z "$table_mjd" ]; then
            update_reason="has no valid generation date"
        elif [ "$table_mjd" -lt "$end_mjd" ]; then
            update_reason="is older than the plotted data"
        fi
    elif [ -e "$sat_src" ]; then
        update_reason="is invalid"
    else
        update_reason="is missing"
    fi

    if [ -n "$update_reason" ]; then
        echo ":: sat_parameters $update_reason; checking for an update"
        if download_tmp=$(mktemp "${TMPDIR:-/tmp}/pdba_sat_parameters.XXXXXX"); then
            SAT_PARAMETERS_TEMP=$download_tmp
            if download_sat_parameters "$SAT_PARAMETERS_URL" "$download_tmp" && \
               valid_sat_parameters "$download_tmp" && \
               sat_parameters_mjd "$download_tmp" >/dev/null; then
                chmod 644 "$download_tmp"
                if [ ! -L "$sat_src" ] && mv -f "$download_tmp" "$sat_src" 2>/dev/null; then
                    SAT_PARAMETERS_TEMP=""
                    echo ":: updated sat_parameters from $SAT_PARAMETERS_URL"
                else
                    sat_src=$download_tmp
                    echo "***WARNING: cannot update the stored sat_parameters; use the downloaded copy for this run" >&2
                fi
            else
                echo "***WARNING: failed to download a valid sat_parameters from $SAT_PARAMETERS_URL" >&2
            fi
        else
            echo "***WARNING: cannot create a temporary file for updating sat_parameters" >&2
        fi
    fi

    if ! valid_sat_parameters "$sat_src" && \
       [ "$sat_src" != "$bundled_sat" ] && \
       valid_sat_parameters "$bundled_sat"; then
        echo "***WARNING: use bundled sat_parameters instead" >&2
        sat_src=$bundled_sat
    fi

    if ! valid_sat_parameters "$sat_src"; then
        echo "***ERROR: valid sat_parameters not found; download it from $SAT_PARAMETERS_URL" >&2
        exit 1
    fi

    table_mjd=$(sat_parameters_mjd "$sat_src" || true)
    if [ -z "$table_mjd" ] || [ "$table_mjd" -lt "$end_mjd" ]; then
        echo "***WARNING: sat_parameters remains older than the plotted data" >&2
    fi

    if [ "$sat_src" != "$sat_dst" ]; then
        if [ -L "$sat_dst" ]; then
            rm -f "$sat_dst"
        elif [ -e "$sat_dst" ]; then
            if valid_sat_parameters "$sat_dst"; then
                echo "***ERROR: cannot prepare sat_parameters: $sat_dst already exists" >&2
                exit 1
            fi
            rm -f "$sat_dst"
        fi
        ln -s "$sat_src" "$sat_dst"
        SAT_PARAMETERS_LINKED=1
    fi
}

cleanup_sat_parameters() {
    if [ "${SAT_PARAMETERS_LINKED:-0}" -eq 1 ] && [ -L "$LOG_DIR/sat_parameters" ]; then
        rm -f "$LOG_DIR/sat_parameters"
    fi
    if [ "${MPLCONFIGDIR_CREATED:-0}" -eq 1 ] && [ -n "${MPLCONFIGDIR:-}" ]; then
        rm -rf "$MPLCONFIGDIR"
    fi
    if [ -n "${SAT_PARAMETERS_TEMP:-}" ] && [ -f "$SAT_PARAMETERS_TEMP" ]; then
        rm -f "$SAT_PARAMETERS_TEMP"
    fi
}

prepare_matplotlib_cache() {
    if [ -n "${MPLCONFIGDIR:-}" ]; then
        return
    fi

    MPLCONFIGDIR="${TMPDIR:-/tmp}/pdba_plot_mpl_$$"
    export MPLCONFIGDIR
    mkdir -p "$MPLCONFIGDIR"
    MPLCONFIGDIR_CREATED=1
}

valid_summary_log() {
    local summary_log=$1

    [ -s "$summary_log" ] || return 1
    awk '
        substr($0, 1, 1) == " " &&
        substr($0, 14, 5) ~ /^[0-9][0-9][0-9][0-9][0-9]$/ &&
        (length($0) == 38 || length($0) == 78 || length($0) == 80 ||
         length($0) == 89 || length($0) == 98) {
            mjd = substr($0, 14, 5) + 0
            if (found && mjd < previous_mjd) {
                exit 1
            }
            previous_mjd = mjd
            found = 1
        }
        END { if (!found) exit 1 }
    ' "$summary_log"
}

main() {
    if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        print_usage
        exit 0
    fi
    if [ $# -ne 1 ]; then
        print_usage >&2
        exit 1
    fi

    local log_arg=$1
    local python
    local script
    local log
    local nlog
    local sum_tmp
    local logs=()

    if [ ! -d "$log_arg" ]; then
        echo "***ERROR: no such directory: $log_arg" >&2
        exit 1
    fi

    LOG_DIR="$(cd "$log_arg" && pwd -P)"
    python=$(resolve_python)

    for log in "$LOG_DIR"/$LOG_PATTERN
    do
        [ -f "$log" ] || continue
        logs+=("$log")
    done
    nlog=${#logs[@]}
    if [ "$nlog" -gt 0 ]; then
        sum_tmp=$(mktemp "$LOG_DIR/.${SUM_LOG}.XXXXXX")
        if ! for log in "${logs[@]}"
        do
            cat "$log"
        done > "$sum_tmp"
        then
            rm -f "$sum_tmp"
            echo "***ERROR: failed to merge ALGIRC logs in $LOG_DIR" >&2
            exit 1
        fi
        if ! valid_summary_log "$sum_tmp"; then
            rm -f "$sum_tmp"
            echo "***ERROR: merged ALGIRC summary contains no valid ordered MJD records" >&2
            exit 1
        fi
        mv -f "$sum_tmp" "$LOG_DIR/$SUM_LOG"
        echo ":: merged $nlog ALGIRC logs to $LOG_DIR/$SUM_LOG"
    elif valid_summary_log "$LOG_DIR/$SUM_LOG"; then
        echo ":: use existing ALGIRC summary log $LOG_DIR/$SUM_LOG"
    elif [ -e "$LOG_DIR/$SUM_LOG" ]; then
        echo "***ERROR: invalid, empty, or unsorted ALGIRC summary log: $LOG_DIR/$SUM_LOG" >&2
        exit 1
    else
        echo "***ERROR: no algirc-MJD.out files or valid $SUM_LOG found in $LOG_DIR" >&2
        exit 1
    fi

    trap cleanup_sat_parameters EXIT
    prepare_sat_parameters "$LOG_DIR" "$LOG_DIR/$SUM_LOG"
    prepare_matplotlib_cache

    cd "$LOG_DIR"
    for script in $PLOT_SCRIPTS
    do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            echo "***ERROR: plot script not found: $SCRIPT_DIR/$script" >&2
            exit 1
        fi
        "$python" "$SCRIPT_DIR/$script" "$SUM_LOG"
    done

    echo ":: figures are saved in $LOG_DIR"
}

main "$@"
