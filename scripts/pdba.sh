#!/usr/bin/env bash

###############################################################################
##                                                                           ##
##  PURPOSE: Align one day of GNSS clock/bias products to the previous day   ##
##                                                                           ##
##  AUTHOR : PRIDE LAB      pride@apm.ac.cn                                  ##
##                                                                           ##
##  VERSION: ver 1.0                                                         ##
##                                                                           ##
##  DATE   : August-06, 2026                                                 ##
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

set -u
set -o pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION_NUM="1.0"
readonly WORK_DIR="$(pwd -P)"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly ALGFILE="algirc"
readonly GPS_EPOCH_MJD=44244
readonly SHORT_PRODUCT_NAME_LENGTH=12

CONFIG_TMP=""
EDIT_TMP=""

cleanup() {
    if [ -n "$CONFIG_TMP" ]; then
        rm -f -- "$CONFIG_TMP"
    fi
    if [ -n "$EDIT_TMP" ]; then
        rm -f -- "$EDIT_TMP"
    fi
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

print_version() {
    printf "PRIDE DBAlign pdba version %s\n" "$VERSION_NUM"
}

print_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME -clk <file> -bia <file> -sp3 <file> [options]

Align the target-day clock and bias products to the previous day's original
products using the corresponding SP3 orbits. The target date is read from
the product filenames.

Start up:
  -V, -v, --version                         display version information
  -H, -h, --help                            display this help

Product options:
  -clk <file>, --clock <file>               target-day clock product (required)
  -bia <file>, --bias <file>                target-day code/phase bias product (required)
  -sp3 <file>, --sp3 <file>                 target-day SP3 orbit product (required)

Processing options:
  -cfg <file>, --config <file>              configuration file for PRIDE DBAlign
  -wdocb <YES|NO>                           write day-boundary discontinuity records
                                              * default: YES
  -sys <char>, --system <char>              GNSS systems selected from G, E and C
                                              * default: GEC)
  -ubd23 <YES|NO>, --unify-bds23 <YES|NO>  unify BDS-2/3 datum
                                              * default: YES for MJD >= 61152, otherwise NO

Configuration precedence:
  command-line option > configuration file > built-in default

Notes:
  * -clk, -bia and -sp3 are always required and are never read from -cfg.
  * Clock, bias and SP3 inputs must use the same filename format and date.
  * If the reference-day clock lacks 24:00, an additional reference-day
    _predicted clock is written with extrapolated 24:00 records appended.
  * Reference-day SP3 copies extended by extrapolation also use _predicted.
  * The target-day clock must start at 00:00:00; that epoch is never
    synthesized from the reference-day extrapolation.

Examples:
  $SCRIPT_NAME \\
    -clk WUM0MGXRAP_20250020000_01D_30S_CLK.CLK \\
    -bia WUM0MGXRAP_20250020000_01D_01D_OSB.BIA \\
    -sp3 WUM0MGXRAP_20250020000_01D_05M_ORB.SP3

  $SCRIPT_NAME -clk cod22906.clk -bia cod22906.bia -sp3 cod22906.sp3
EOF
}

error() {
    printf "%s: %s\n" "$SCRIPT_NAME" "$*" >&2
}

warning() {
    printf "%s: warning: %s\n" "$SCRIPT_NAME" "$*" >&2
}

die() {
    error "$*"
    exit 1
}

require_option_value() {
    local option=$1
    local count=$2

    if [ "$count" -lt 2 ]; then
        die "option '$option' requires an argument"
    fi
}

normalize_yes_no() {
    local value
    value=$(printf "%s" "$1" | tr '[:lower:]' '[:upper:]')

    case "$value" in
        YES|Y|TRUE|T|1)
            NORMALIZED_VALUE="YES"
            ;;
        NO|N|FALSE|F|0)
            NORMALIZED_VALUE="NO"
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_systems() {
    local value
    local system
    local normalized=""

    value=$(printf "%s" "$1" | tr '[:lower:]' '[:upper:]')
    if [[ ! "$value" =~ ^[GEC]+$ ]]; then
        return 1
    fi

    for system in G E C; do
        if [[ "$value" == *"$system"* ]]; then
            normalized="${normalized}${system}"
        fi
    done

    NORMALIZED_SYSTEMS=$normalized
}

resolve_existing_file() {
    local argument=$1
    local label=$2
    local path
    local directory
    local basename_value

    if [[ "$argument" = /* ]]; then
        path=$argument
    else
        path="$WORK_DIR/${argument#./}"
    fi

    if [ ! -f "$path" ]; then
        error "$label file does not exist: $argument"
        return 1
    fi

    directory=$(cd "$(dirname "$path")" && pwd -P) || return 1
    basename_value=$(basename "$path")
    if [[ "$basename_value" =~ [[:space:]] ]]; then
        error "$label filename must not contain whitespace: $basename_value"
        return 1
    fi

    RESOLVED_FILE="$directory/$basename_value"
}

resolve_default_config() {
    local candidate

    for candidate in \
        "$SCRIPT_DIR/config_template" \
        "$SCRIPT_DIR/../table/config_template"
    do
        if [ -f "$candidate" ]; then
            resolve_existing_file "$candidate" "default configuration" || return 1
            DEFAULT_CONFIG=$RESOLVED_FILE
            return 0
        fi
    done

    error "default configuration file not found beside pdba or in ../table"
    return 1
}

days_in_year() {
    local year=$1

    if (( year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) )); then
        DAYS_IN_YEAR=366
    else
        DAYS_IN_YEAR=365
    fi
}

# Time-conversion functions follow the implementation used by pdba_old.sh.
ydoy2mjd() {
    local iyear=$1
    local idoy=$2
    local imon
    local iday

    read -r iyear imon iday <<< "$(ydoy2ymd "$iyear" "$idoy")"
    ymd2mjd "$iyear" "$imon" "$iday"
}

ymd2mjd() {
    local year=$1
    local mon=$((10#$2))
    local day=$((10#$3))
    local mjd

    [ "$year" -lt 100 ] && year=$((year + 2000))
    if [ "$mon" -le 2 ]; then
        mon=$((mon + 12))
        year=$((year - 1))
    fi
    mjd=$(awk -v year="$year" 'BEGIN {print int(year * 365.25) - 679006}')
    awk -v mjd="$mjd" -v year="$year" -v mon="$mon" -v day="$day" \
        'BEGIN {print mjd + int(30.6001 * (mon + 1)) + 2 - int(year / 100) + int(year / 400) + day}'
}

mjd2ydoy() {
    local mjd=$1
    local year=$(((mjd + 678940) / 365))
    local mjd0
    local doy

    mjd0=$(ymd2mjd "$year" 1 1)
    doy=$((mjd - mjd0))
    while [ "$doy" -le 0 ]; do
        year=$((year - 1))
        mjd0=$(ymd2mjd "$year" 1 1)
        doy=$((mjd - mjd0 + 1))
    done
    printf "%d %03d\n" "$year" "$doy"
}

ydoy2ymd() {
    local iyear=$1
    local idoy=$((10#$2))
    local days_in_month=(31 28 31 30 31 30 31 31 30 31 30 31)
    local iday=0
    local id
    local imon=0
    local days

    [ "$iyear" -lt 100 ] && iyear=$((iyear + 2000))
    if (( (iyear % 4 == 0 && iyear % 100 != 0) || iyear % 400 == 0 )); then
        days_in_month[1]=29
    fi
    id=$idoy
    for days in "${days_in_month[@]}"; do
        id=$((id - days))
        imon=$((imon + 1))
        if [ "$id" -gt 0 ]; then
            continue
        fi
        iday=$((id + days))
        break
    done
    printf "%d %02d %02d\n" "$iyear" "$imon" "$iday"
}

gpswd2mjd() {
    local week=$((10#$1))
    local dow=$((10#$2))

    printf "%d\n" "$((GPS_EPOCH_MJD + week * 7 + dow))"
}

mjd2gpswd() {
    local mjd=$1
    local gps_days=$((mjd - GPS_EPOCH_MJD))
    local week
    local dow

    if [ "$gps_days" -lt 0 ]; then
        return 1
    fi
    week=$((gps_days / 7))
    dow=$((gps_days % 7))
    if [ "$week" -gt 9999 ]; then
        return 1
    fi
    printf "%04d %d\n" "$week" "$dow"
}

extract_product_date() {
    local filename=$1
    local label=$2
    local filename_length=${#filename}
    local year
    local doy
    local gps_week
    local gps_dow
    local year_number
    local doy_number
    local gps_week_number
    local matched_text
    local leading_boundary
    local text_before_match

    # The legacy 8.3 product convention has a 12-character basename, such as
    # igs22906.clk. Classify by basename length before interpreting its date.
    if [ "$filename_length" -eq "$SHORT_PRODUCT_NAME_LENGTH" ]; then
        if [[ ! "$filename" =~ (^|[^[:digit:]])([[:digit:]]{4})([0-6])([^[:digit:]]|$) ]]; then
            error "cannot find a WWWWD date field in short $label filename: $filename"
            return 1
        fi

        gps_week=${BASH_REMATCH[2]}
        gps_dow=${BASH_REMATCH[3]}
        matched_text=${BASH_REMATCH[0]}
        leading_boundary=${BASH_REMATCH[1]}
        text_before_match=${filename%%"$matched_text"*}
        gps_week_number=$((10#$gps_week))
        PARSED_GPS_WEEK=$(printf "%04d" "$gps_week_number")
        PARSED_GPS_DOW=$((10#$gps_dow))
        PARSED_DATE_FORMAT="GPS_WEEK_DAY"
        PARSED_DATE_TOKEN="${PARSED_GPS_WEEK}${PARSED_GPS_DOW}"
        PARSED_DATE_OFFSET=$((${#text_before_match} + ${#leading_boundary}))
        PARSED_DATE_LENGTH=5
        PARSED_MJD=$(gpswd2mjd "$PARSED_GPS_WEEK" "$PARSED_GPS_DOW")
        read -r PARSED_YEAR PARSED_DOY <<< "$(mjd2ydoy "$PARSED_MJD")"
        return 0
    fi

    # IGS long product names normally contain an 11-digit YYYYDDDHHMM token.
    # A delimiter-bounded YYYYDDD token is also accepted.
    if [[ "$filename" =~ (^|[^[:digit:]])([[:digit:]]{4})([[:digit:]]{3})([[:digit:]]{4})([^[:digit:]]|$) ]]; then
        year=${BASH_REMATCH[2]}
        doy=${BASH_REMATCH[3]}
        matched_text=${BASH_REMATCH[0]}
        leading_boundary=${BASH_REMATCH[1]}
    elif [[ "$filename" =~ (^|[^[:digit:]])([[:digit:]]{4})([[:digit:]]{3})([^[:digit:]]|$) ]]; then
        year=${BASH_REMATCH[2]}
        doy=${BASH_REMATCH[3]}
        matched_text=${BASH_REMATCH[0]}
        leading_boundary=${BASH_REMATCH[1]}
    fi

    if [ -n "${year:-}" ]; then
        year_number=$((10#$year))
        doy_number=$((10#$doy))
        if [ "$year_number" -lt 1980 ] || [ "$year_number" -gt 2199 ]; then
            error "invalid year in $label filename: $year"
            return 1
        fi

        days_in_year "$year_number"
        if [ "$doy_number" -lt 1 ] || [ "$doy_number" -gt "$DAYS_IN_YEAR" ]; then
            error "invalid day-of-year in $label filename: $year/$doy"
            return 1
        fi

        PARSED_YEAR=$(printf "%04d" "$year_number")
        PARSED_DOY=$(printf "%03d" "$doy_number")
        PARSED_DATE_FORMAT="YDOY"
        PARSED_DATE_TOKEN="${PARSED_YEAR}${PARSED_DOY}"
        text_before_match=${filename%%"$matched_text"*}
        PARSED_DATE_OFFSET=$((${#text_before_match} + ${#leading_boundary}))
        PARSED_DATE_LENGTH=7
        PARSED_MJD=$(ydoy2mjd "$year_number" "$doy_number")
        return 0
    fi

    error "cannot find a YYYYDDD[HHMM] date field in long $label filename: $filename"
    return 1
}

calculate_previous_date() {
    local target_mjd=$1
    local gps_date

    PREVIOUS_MJD=$((target_mjd - 1))
    read -r PREVIOUS_YEAR PREVIOUS_DOY <<< "$(mjd2ydoy "$PREVIOUS_MJD")"
    if ! gps_date=$(mjd2gpswd "$PREVIOUS_MJD"); then
        error "previous day cannot be represented as a four-digit GPS week/day"
        return 1
    fi
    read -r PREVIOUS_GPS_WEEK PREVIOUS_GPS_DOW <<< "$gps_date"
}

previous_product_name() {
    local filename=$1
    local date_format=$2
    local current_date=$3
    local date_offset=$4
    local date_length=$5
    local previous_date
    local suffix_offset

    case "$date_format" in
        YDOY)
            previous_date="${PREVIOUS_YEAR}${PREVIOUS_DOY}"
            ;;
        GPS_WEEK_DAY)
            previous_date="${PREVIOUS_GPS_WEEK}${PREVIOUS_GPS_DOW}"
            ;;
        *)
            error "unsupported product date format: $date_format"
            return 1
            ;;
    esac

    if [ "${filename:date_offset:date_length}" != "$current_date" ]; then
        error "target date field $current_date is not present at the detected position in filename: $filename"
        return 1
    fi

    suffix_offset=$((date_offset + date_length))
    PREVIOUS_BASENAME="${filename:0:date_offset}${previous_date}${filename:suffix_offset}"
}

find_reference_erp() {
    local reference_sp3=$1
    local directory filename candidate name reference_mjd reference_prefix
    local prefix score best_score=-1
    local LC_ALL=C

    FOUND_ERP_PATH=NONE
    directory=$(dirname "$reference_sp3")
    filename=$(basename "$reference_sp3")
    extract_product_date "$filename" "reference SP3" || return 1
    reference_mjd=$PARSED_MJD
    reference_prefix=$(printf '%s' "${filename:0:PARSED_DATE_OFFSET}" | tr '[:upper:]' '[:lower:]')

    # Unmatched glob literals are skipped by -f; do not change shell glob options.
    # Date filtering prevents a target-day/weekly ERP from being used accidentally.
    for candidate in "$directory"/*.[eE][rR][pP]; do
        [ -f "$candidate" ] || continue
        name=${candidate##*/}
        [[ "$name" =~ [[:space:]!] ]] && continue
        extract_product_date "$name" "ERP" >/dev/null 2>&1 || continue
        [ "$PARSED_MJD" -eq "$reference_mjd" ] || continue
        prefix=$(printf '%s' "${name:0:PARSED_DATE_OFFSET}" | tr '[:upper:]' '[:lower:]')
        score=0
        if [[ "$prefix" == "$reference_prefix" ]]; then
            score=2
        elif [[ "${name:0:3}" == "${filename:0:3}" ]]; then
            score=1
        fi
        if [ "$score" -gt "$best_score" ] ||
            { [ "$score" -eq "$best_score" ] && [[ "$candidate" < "$FOUND_ERP_PATH" ]]; }; then
            FOUND_ERP_PATH=$candidate
            best_score=$score
        fi
    done
}

find_previous_product() {
    local target_path=$1
    local label=$2
    local target_directory
    local candidate_same_directory

    target_directory=$(dirname "$target_path")
    candidate_same_directory="$target_directory/$PREVIOUS_BASENAME"

    if [ -f "$candidate_same_directory" ]; then
        FOUND_PREVIOUS_PATH=$candidate_same_directory
        FOUND_CONFIG_NAME=$PREVIOUS_BASENAME
        return 0
    fi

    error "previous-day $label product not found"
    error "  checked: $candidate_same_directory"
    return 1
}

# Debian 10 ships mawk 1.3.3, which does not recognize POSIX character
# classes such as [[:space:]]. Keep AWK whitespace matching explicit.
set_config_value() {
    local config=$1
    local key=$2
    local value=$3

    EDIT_TMP="${config}.edit.$$"
    if ! awk -v wanted="$key" -v replacement="$value" '
        function trim(text) {
            sub(/^[ \t]+/, "", text)
            sub(/[ \t]+$/, "", text)
            return text
        }
        {
            separator = index($0, "=")
            if (separator > 0) {
                lhs = trim(substr($0, 1, separator - 1))
                if (lhs == wanted) {
                    if (!written) {
                        printf "%-22s = %s\n", wanted, replacement
                        written = 1
                    }
                    next
                }
            }
            print
        }
        END {
            if (!written) {
                printf "%-22s = %s\n", wanted, replacement
            }
        }
    ' "$config" > "$EDIT_TMP"; then
        rm -f -- "$EDIT_TMP"
        EDIT_TMP=""
        error "failed to update configuration item: $key"
        return 1
    fi

    if ! mv -f -- "$EDIT_TMP" "$config"; then
        rm -f -- "$EDIT_TMP"
        EDIT_TMP=""
        error "failed to replace generated configuration: $config"
        return 1
    fi
    EDIT_TMP=""
}

get_config_logical() {
    local config=$1
    local key=$2
    local value

    value=$(awk -v wanted="$key" '
        function trim(text) {
            sub(/^[ \t]+/, "", text)
            sub(/[ \t]+$/, "", text)
            return text
        }
        {
            separator = index($0, "=")
            if (separator <= 0) next
            lhs = trim(substr($0, 1, separator - 1))
            if (lhs != wanted) next
            rhs = substr($0, separator + 1)
            sub(/!.*/, "", rhs)
            rhs = trim(rhs)
            split(rhs, fields, /[ \t]+/)
            print fields[1]
            exit
        }
    ' "$config")

    case "$value" in
        ''|[Dd][Ee][Ff][Aa][Uu][Ll][Tt]) CONFIG_LOGICAL=Default; return 0 ;;
    esac
    if ! normalize_yes_no "$value"; then
        error "invalid $key value in configuration: $value"
        return 1
    fi
    CONFIG_LOGICAL=$NORMALIZED_VALUE
}

filter_satellite_systems() {
    local config=$1
    local systems=$2

    EDIT_TMP="${config}.systems.$$"
    if ! awk -v selected="$systems" '
        /^[ \t]*[+]GNSS satellites[ \t]*$/ {
            inside = 1
            begin_found = 1
            print
            next
        }
        /^[ \t]*-GNSS satellites[ \t]*$/ {
            inside = 0
            end_found = 1
            print
            next
        }
        {
            line = $0
            if (inside && line ~ /^[ \t]+[A-Z][0-9][0-9]([ \t]|$)/) {
                item = line
                sub(/^[ \t]+/, "", item)
                syschar = substr(item, 1, 1)
                if (index(selected, syschar) == 0) {
                    sub(/^[ \t]+/, "#", line)
                }
            }
            print line
        }
        END {
            if (!begin_found || !end_found) exit 42
        }
    ' "$config" > "$EDIT_TMP"; then
        rm -f -- "$EDIT_TMP"
        EDIT_TMP=""
        error "failed to filter GNSS systems; satellite block is missing or invalid"
        return 1
    fi

    if ! mv -f -- "$EDIT_TMP" "$config"; then
        rm -f -- "$EDIT_TMP"
        EDIT_TMP=""
        error "failed to replace generated configuration: $config"
        return 1
    fi
    EDIT_TMP=""
}

inspect_satellite_systems() {
    local config=$1
    local result
    local status

    result=$(awk '
        /^[ \t]*[+]GNSS satellites[ \t]*$/ {
            inside = 1
            begin_found = 1
            next
        }
        /^[ \t]*-GNSS satellites[ \t]*$/ {
            inside = 0
            end_found = 1
            next
        }
        inside && /^[ \t]+[A-Z][0-9][0-9]([ \t]|$)/ {
            item = $0
            sub(/^[ \t]+/, "", item)
            syschar = substr(item, 1, 1)
            count++
            if (syschar == "G") has_g = 1
            else if (syschar == "E") has_e = 1
            else if (syschar == "C") has_c = 1
            else bad = bad syschar
        }
        END {
            if (!begin_found || !end_found) exit 2
            if (bad != "") {
                print bad
                exit 3
            }
            if (count == 0) exit 4
            result = ""
            if (has_g) result = result "G"
            if (has_e) result = result "E"
            if (has_c) result = result "C"
            print result
        }
    ' "$config")
    status=$?

    case "$status" in
        0)
            EFFECTIVE_SYSTEMS=$result
            ;;
        2)
            error "GNSS satellite block is missing from configuration"
            return 1
            ;;
        3)
            error "configuration enables unsupported GNSS system(s): $result"
            error "only G, E and C are supported"
            return 1
            ;;
        4)
            error "configuration does not enable any GNSS satellites"
            return 1
            ;;
        *)
            error "failed to inspect GNSS satellite configuration"
            return 1
            ;;
    esac
}

main() {
    local clock_argument=""
    local bias_argument=""
    local sp3_argument=""
    local config_argument=""
    local system_argument=""
    local ubd23_argument=""
    local wdocb_argument=""
    local clock_seen=0
    local bias_seen=0
    local sp3_seen=0
    local config_seen=0
    local system_seen=0
    local ubd23_seen=0
    local wdocb_seen=0
    local clock_path
    local bias_path
    local sp3_path
    local product_directory
    local clock_basename
    local bias_basename
    local sp3_basename
    local clock_date_format
    local bias_date_format
    local sp3_date_format
    local clock_date_token
    local bias_date_token
    local sp3_date_token
    local clock_date_offset
    local bias_date_offset
    local sp3_date_offset
    local clock_date_length
    local bias_date_length
    local sp3_date_length
    local parsed_year
    local parsed_doy
    local parsed_mjd
    local gps_date
    local previous_clock_path
    local previous_bias_path
    local previous_sp3_path
    local previous_clock_name
    local previous_bias_name
    local previous_sp3_name
    local config_source
    local config_output
    local effective_ubd23
    local algexe

    if [ "$#" -eq 0 ]; then
        print_usage >&2
        return 1
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -clk|--clock)
                [ "$clock_seen" -eq 0 ] || die "conflicting option: $1"
                require_option_value "$1" "$#"
                clock_argument=$2
                clock_seen=1
                shift 2
                ;;
            -bia|--bias)
                [ "$bias_seen" -eq 0 ] || die "conflicting option: $1"
                require_option_value "$1" "$#"
                bias_argument=$2
                bias_seen=1
                shift 2
                ;;
            -sp3|--sp3)
                [ "$sp3_seen" -eq 0 ] || die "conflicting option: $1"
                require_option_value "$1" "$#"
                sp3_argument=$2
                sp3_seen=1
                shift 2
                ;;
            -cfg|--config)
                [ "$config_seen" -eq 0 ] || die "conflicting option: $1"
                require_option_value "$1" "$#"
                config_argument=$2
                config_seen=1
                shift 2
                ;;
            -sys|--system)
                [ "$system_seen" -eq 0 ] || die "conflicting option: $1"
                require_option_value "$1" "$#"
                if ! normalize_systems "$2"; then
                    die "invalid GNSS system '$2'; select one or more from G, E and C"
                fi
                system_argument=$NORMALIZED_SYSTEMS
                system_seen=1
                shift 2
                ;;
            -wdocb)
                [ "$wdocb_seen" -eq 0 ] || die "conflicting option: $1"
                require_option_value "$1" "$#"
                if ! normalize_yes_no "$2"; then
                    die "invalid -wdocb value '$2'; use YES or NO"
                fi
                wdocb_argument=$NORMALIZED_VALUE
                wdocb_seen=1
                shift 2
                ;;
            -ubd23|--unify-bds23)
                [ "$ubd23_seen" -eq 0 ] || die "conflicting option: $1"
                require_option_value "$1" "$#"
                if ! normalize_yes_no "$2"; then
                    die "invalid -ubd23 value '$2'; use YES or NO"
                fi
                ubd23_argument=$NORMALIZED_VALUE
                ubd23_seen=1
                shift 2
                ;;
            -V|-v|--version)
                print_version
                return 0
                ;;
            -H|-h|--help)
                print_usage
                return 0
                ;;
            --)
                shift
                [ "$#" -eq 0 ] || die "unexpected positional argument: $1"
                ;;
            -*)
                die "unrecognized option: $1"
                ;;
            *)
                die "unexpected positional argument: $1"
                ;;
        esac
    done

    [ "$clock_seen" -eq 1 ] || die "required option is missing: -clk <file>"
    [ "$bias_seen" -eq 1 ] || die "required option is missing: -bia <file>"
    [ "$sp3_seen" -eq 1 ] || die "required option is missing: -sp3 <file>"

    resolve_existing_file "$clock_argument" "clock" || return 1
    clock_path=$RESOLVED_FILE
    resolve_existing_file "$bias_argument" "bias" || return 1
    bias_path=$RESOLVED_FILE
    resolve_existing_file "$sp3_argument" "SP3" || return 1
    sp3_path=$RESOLVED_FILE

    clock_basename=$(basename "$clock_path")
    bias_basename=$(basename "$bias_path")
    sp3_basename=$(basename "$sp3_path")

    product_directory=$(dirname "$clock_path")
    if [ "$(dirname "$bias_path")" != "$product_directory" ]; then
        die "target clock and bias products must be in the same directory"
    fi
    if [ "$(dirname "$sp3_path")" != "$product_directory" ]; then
        die "target SP3 product must be in the clock/bias product directory"
    fi

    extract_product_date "$clock_basename" "clock" || return 1
    TARGET_MJD=$PARSED_MJD
    TARGET_YEAR=$PARSED_YEAR
    TARGET_DOY=$PARSED_DOY
    clock_date_format=$PARSED_DATE_FORMAT
    clock_date_token=$PARSED_DATE_TOKEN
    clock_date_offset=$PARSED_DATE_OFFSET
    clock_date_length=$PARSED_DATE_LENGTH
    if ! gps_date=$(mjd2gpswd "$TARGET_MJD"); then
        die "target date cannot be represented as a four-digit GPS week/day"
    fi
    read -r TARGET_GPS_WEEK TARGET_GPS_DOW <<< "$gps_date"

    extract_product_date "$bias_basename" "bias" || return 1
    parsed_mjd=$PARSED_MJD
    parsed_year=$PARSED_YEAR
    parsed_doy=$PARSED_DOY
    bias_date_format=$PARSED_DATE_FORMAT
    bias_date_token=$PARSED_DATE_TOKEN
    bias_date_offset=$PARSED_DATE_OFFSET
    bias_date_length=$PARSED_DATE_LENGTH
    if [ "$bias_date_format" != "$clock_date_format" ]; then
        warning "clock and bias filename formats differ; use either all long product names or all short product names"
        return 1
    fi
    if [ "$parsed_mjd" -ne "$TARGET_MJD" ]; then
        warning "clock and bias products are not from the same day: $TARGET_YEAR/$TARGET_DOY and $parsed_year/$parsed_doy"
        return 1
    fi

    extract_product_date "$sp3_basename" "SP3" || return 1
    parsed_mjd=$PARSED_MJD
    parsed_year=$PARSED_YEAR
    parsed_doy=$PARSED_DOY
    sp3_date_format=$PARSED_DATE_FORMAT
    sp3_date_token=$PARSED_DATE_TOKEN
    sp3_date_offset=$PARSED_DATE_OFFSET
    sp3_date_length=$PARSED_DATE_LENGTH
    if [ "$sp3_date_format" != "$clock_date_format" ]; then
        warning "clock, bias and SP3 filename formats differ; use either all long product names or all short product names"
        return 1
    fi
    if [ "$parsed_mjd" -ne "$TARGET_MJD" ]; then
        warning "clock, bias and SP3 products are not from the same day: clock/bias=$TARGET_YEAR/$TARGET_DOY, SP3=$parsed_year/$parsed_doy"
        return 1
    fi

    calculate_previous_date "$TARGET_MJD" || return 1

    previous_product_name "$clock_basename" "$clock_date_format" "$clock_date_token" \
        "$clock_date_offset" "$clock_date_length" || return 1
    find_previous_product "$clock_path" "clock" || return 1
    previous_clock_path=$FOUND_PREVIOUS_PATH
    previous_clock_name=$FOUND_CONFIG_NAME

    previous_product_name "$bias_basename" "$bias_date_format" "$bias_date_token" \
        "$bias_date_offset" "$bias_date_length" || return 1
    find_previous_product "$bias_path" "bias" || return 1
    previous_bias_path=$FOUND_PREVIOUS_PATH
    previous_bias_name=$FOUND_CONFIG_NAME

    previous_product_name "$sp3_basename" "$sp3_date_format" "$sp3_date_token" \
        "$sp3_date_offset" "$sp3_date_length" || return 1
    find_previous_product "$sp3_path" "SP3" || return 1
    previous_sp3_path=$FOUND_PREVIOUS_PATH
    previous_sp3_name=$FOUND_CONFIG_NAME

    if [ "$config_seen" -eq 1 ]; then
        resolve_existing_file "$config_argument" "configuration" || return 1
        config_source=$RESOLVED_FILE
    else
        find_reference_erp "$previous_sp3_path" || return 1
        resolve_default_config || return 1
        config_source=$DEFAULT_CONFIG
    fi

    config_output="$product_directory/config_pdba_${TARGET_YEAR}${TARGET_DOY}"
    CONFIG_TMP="${config_output}.tmp.$$"
    if ! cp -f -- "$config_source" "$CONFIG_TMP"; then
        die "failed to copy base configuration: $config_source"
    fi
    if ! chmod 644 "$CONFIG_TMP"; then
        die "failed to set permissions on generated configuration"
    fi
    if ! mv -f -- "$CONFIG_TMP" "$config_output"; then
        die "failed to create generated configuration: $config_output"
    fi
    CONFIG_TMP=""

    set_config_value "$config_output" "Product directory" "$product_directory" || return 1
    set_config_value "$config_output" "Satellite clock" "$previous_clock_name $clock_basename" || return 1
    set_config_value "$config_output" "Code/phase bias" "$previous_bias_name $bias_basename" || return 1

    set_config_value "$config_output" "Satellite orbit" "$previous_sp3_name $sp3_basename" || return 1
    if [ "$config_seen" -eq 0 ]; then
        set_config_value "$config_output" "ERP file" "$FOUND_ERP_PATH" || return 1
    fi

    if [ "$wdocb_seen" -eq 1 ]; then
        set_config_value "$config_output" "Write DOCB" "$wdocb_argument" || return 1
    fi

    if [ "$ubd23_seen" -eq 1 ]; then
        effective_ubd23=$ubd23_argument
        set_config_value "$config_output" "Unify BDS-2/3" "$effective_ubd23" || return 1
    elif [ "$config_seen" -eq 1 ]; then
        get_config_logical "$config_output" "Unify BDS-2/3" || return 1
        effective_ubd23=$CONFIG_LOGICAL
    else
        effective_ubd23="Default"
        set_config_value "$config_output" "Unify BDS-2/3" "$effective_ubd23" || return 1
    fi

    if [ "$system_seen" -eq 1 ]; then
        filter_satellite_systems "$config_output" "$system_argument" || return 1
    elif [ "$config_seen" -eq 0 ]; then
        filter_satellite_systems "$config_output" "GEC" || return 1
    fi
    inspect_satellite_systems "$config_output" || return 1

    if ! algexe=$(command -v "$ALGFILE"); then
        die "$ALGFILE executable not found in PATH"
    fi

    # algirc runs in the product directory and reads its local leap-second table.
    # The script directory also supports custom installations after the installer
    # environment variable is no longer set.
    local leap_source="${PRIDE_DBALIGN_INSTALL_DIR:-$SCRIPT_DIR}/leap.sec"
    if [ ! -f "$leap_source" ]; then
        die "leap-second table not found: $leap_source"
    fi
    if [ ! "$leap_source" -ef "$product_directory/leap.sec" ]; then
        cp -f -- "$leap_source" "$product_directory/leap.sec" || die "failed to copy leap.sec to $product_directory"
    fi

    printf "[pdba] Target date       : %s/%s\n" "$TARGET_YEAR" "$TARGET_DOY"
    printf "[pdba] Reference date    : %s/%s\n" "$PREVIOUS_YEAR" "$PREVIOUS_DOY"
    printf "[pdba] GNSS systems      : %s\n" "$EFFECTIVE_SYSTEMS"
    printf "[pdba] Unify BDS-2/3     : %s\n" "$effective_ubd23"
    printf "[pdba] Clock products    : %s  %s\n" "$previous_clock_path" "$clock_path"
    printf "[pdba] Bias products     : %s  %s\n" "$previous_bias_path" "$bias_path"
    printf "[pdba] SP3 products      : %s  %s\n" "$previous_sp3_path" "$sp3_path"
    printf "[pdba] Configuration     : %s\n" "$config_output"

    if ! (cd "$product_directory" && "$algexe" "$config_output"); then
        die "algirc failed for target date $TARGET_YEAR/$TARGET_DOY"
    fi

    printf "[pdba] Alignment completed for %s/%s\n" "$TARGET_YEAR" "$TARGET_DOY"
}

main "$@"
