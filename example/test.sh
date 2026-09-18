#!/bin/bash

###############################################################################
##                                                                           ##
##  PURPOSE: Test PRIDE DBAlign                                              ##
##                                                                           ##
##  AUTHOR : PRIDE LAB      pride@apm.ac.cn                                  ##
##                                                                           ##
##  VERSION: ver 1.0                                                         ##
##                                                                           ##
##  DATE   : July-12, 2026                                                   ##
##                                                                           ##
##   @ State Key Laboratory of Precision Geodesy,                            ##
##   Chinese Academy of Sciences                                             ##
##                                                                           ##
##    Copyright (C) 2026 by SKLPG, CAS                                       ##
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

BLUE='\033[1;34m'
NC='\033[0m'

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
case_dir="$script_dir/wum0rap"

command -v pdba >/dev/null 2>&1 || { echo "error: pdba not found in PATH" >&2; exit 1; }

check_generated_config() {
    local config=$1

    # Keep this check compatible with Debian 10's mawk 1.3.3.
    awk '
        function trim(text) {
            sub(/^[ \t]+/, "", text)
            sub(/[ \t]+$/, "", text)
            return text
        }
        /^[ \t]*[+]GNSS satellites[ \t]*$/ {
            begin_count++
            next
        }
        /^[ \t]*-GNSS satellites[ \t]*$/ {
            end_count++
            after_satellites = 1
            next
        }
        {
            separator = index($0, "=")
            if (separator <= 0) next
            key = trim(substr($0, 1, separator - 1))
            key_count[key]++
            if (after_satellites) trailing_key = key
        }
        END {
            failed = 0
            if (begin_count != 1 || end_count != 1) {
                print "error: generated configuration has an invalid GNSS satellite block" > "/dev/stderr"
                failed = 1
            }
            if (trailing_key != "") {
                print "error: configuration item appears after the GNSS satellite block: " trailing_key > "/dev/stderr"
                failed = 1
            }
            expected[1] = "Product directory"
            expected[2] = "Satellite orbit"
            expected[3] = "Satellite clock"
            expected[4] = "Code/phase bias"
            expected[5] = "Write DOCB"
            expected[6] = "Unify BDS-2/3"
            for (i = 1; i <= 6; i++) {
                if (key_count[expected[i]] != 1) {
                    print "error: expected exactly one configuration item: " expected[i] > "/dev/stderr"
                    failed = 1
                }
            }
            exit failed
        }
    ' "$config"
}

check_sp3_required() {
    local output

    if output=$(pdba -clk missing.clk -bia missing.bia 2>&1); then
        echo "error: pdba accepted a command without the required -sp3 option" >&2
        return 1
    fi
    case "$output" in
        *"required option is missing: -sp3 <file>"*)
            ;;
        *)
            echo "error: pdba did not report the missing required -sp3 option" >&2
            printf "%s\n" "$output" >&2
            return 1
            ;;
    esac
}

printf "${BLUE}::${NC} verify that the SP3 orbit option is required\n"
check_sp3_required

printf "${BLUE}::${NC} run the 2025 PRIDE DBAlign example\n"
(
    cd "$case_dir/2025"
    pdba \
        -clk WUM0MGXRAP_20250020000_01D_30S_CLK.CLK \
        -bia WUM0MGXRAP_20250020000_01D_01D_OSB.BIA \
        -ubd23 no \
        -sp3 WUM0MGXRAP_20250020000_01D_05M_ORB.SP3
    check_generated_config config_pdba_2025002
)

printf "${BLUE}::${NC} run the 2026 PRIDE DBAlign example\n"
(
    cd "$case_dir/2026"
    pdba \
        -clk WUM0MGXRAP_20260020000_01D_30S_CLK.CLK \
        -bia WUM0MGXRAP_20260020000_01D_01D_OSB.BIA \
        -ubd23 no \
        -sp3 WUM0MGXRAP_20260020000_01D_05M_ORB.SP3
    check_generated_config config_pdba_2026002
)

printf "${BLUE}::${NC} results are put in %s, %s and %s\n" \
    "$case_dir/2025" "$case_dir/2026"
