#!/bin/bash

###############################################################################
##                                                                           ##
##  PURPOSE: Install PRIDE DBAlign                                           ##
##                                                                           ##
##  AUTHOR : PRIDE LAB      pride@apm.ac.cn                                  ##
##                                                                           ##
##  VERSION: ver 1.0                                                         ##
##                                                                           ##
##  DATE   : September-18, 2026                                              ##
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

PROJECT_NAME="PRIDE DBAlign"
VERSION_NUM="1.0"
INSTALL_DIR="${PRIDE_DBALIGN_INSTALL_DIR:-${HOME}/.PRIDE_DBAlign_BIN}"
RUN_SCRIPT="scripts/pdba.sh"
PLOT_RUN_SCRIPT="scripts/pdba_plot.sh"
CONFIG_TEMPLATE="table/config_template"
SAT_PARAMETERS="table/sat_parameters"
LEAP_SECONDS="table/leap.sec"
LEAP_SECONDS_URL="ftp://igs.gnsswhu.cn/pub/whu/phasebias/table/leap.sec"
LOGO_FILE="doc/logo"
SYS="$(uname)"
RED='\033[0;31m'
LOGO_RED='\033[1;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command not found: $1" >&2
        exit 1
    fi
}

install_leap_seconds() {
    local temporary_file

    temporary_file=$(mktemp "${TMPDIR:-/tmp}/pride-dbalign-leap.XXXXXX")
    if { command -v wget >/dev/null 2>&1 && wget -q -t 3 --timeout=60 -O "$temporary_file" "$LEAP_SECONDS_URL"; } || \
       { command -v curl >/dev/null 2>&1 && curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 -o "$temporary_file" "$LEAP_SECONDS_URL"; }; then
        if grep -Fq '+leap sec' "$temporary_file" && grep -Fq -- '-leap sec' "$temporary_file"; then
            install -m 644 "$temporary_file" "$INSTALL_DIR/leap.sec"
            rm -f -- "$temporary_file"
            return
        fi
    fi

    printf "${YELLOW}warning:${NC} failed to update leap.sec; use the bundled file\n" >&2
    install -m 644 "$LEAP_SECONDS" "$INSTALL_DIR/leap.sec"
    rm -f -- "$temporary_file"
}

check_plot_dependencies() {
    local python_command=""

    if command -v python3 >/dev/null 2>&1; then
        python_command=$(command -v python3)
    elif command -v python >/dev/null 2>&1; then
        python_command=$(command -v python)
    fi

    if [ -z "$python_command" ]; then
        printf "${YELLOW}warning:${NC} pdba_plot requires Python and matplotlib, but Python was not found\n" >&2
        return
    fi

    if ! "$python_command" -c 'import matplotlib, pylab' >/dev/null 2>&1; then
        printf "${YELLOW}warning:${NC} matplotlib is not installed or cannot be imported by %s; pdba_plot will not work\n" \
            "$python_command" >&2
    fi
}

run_example_tests() {
    local reply

    if [ ! -t 0 ]; then
        return
    fi

    if [ -f "$PROFILE_FILE" ]; then
        source "$PROFILE_FILE"
    fi

    printf "\n"
    read -r -p $'Run bundled clock/bias/SP3 tests or not (\e[31mstrongly recommended for the first installation !!!\e[0m) [Y/N]: ' reply || return
    case "$reply" in
        [Yy]*)
            if [ ! -f example/test.sh ]; then
                printf "${YELLOW}warning:${NC} example/test.sh not found; skip tests\n"
                return
            fi
            if compgen -G "example/*.sh" >/dev/null; then
                chmod 755 example/*.sh
            fi
            PATH="$INSTALL_DIR:$PATH" bash example/test.sh
            ;;
    esac
}

require_command gfortran
require_command make

if [[ "$HOME" == /root* ]]; then
    printf "${RED}error:${NC} unable to install %s in /root\n" "$PROJECT_NAME" >&2
    exit 1
fi

make -C src clean
make -C src
make -C src install

mkdir -p "$INSTALL_DIR"
install_leap_seconds
cp -f bin/algirc* "$INSTALL_DIR"/
rm -f "$INSTALL_DIR/pdba.sh" "$INSTALL_DIR/pdba_plot.sh"
install -m 755 "$RUN_SCRIPT" "$INSTALL_DIR/pdba"
install -m 755 "$PLOT_RUN_SCRIPT" "$INSTALL_DIR/pdba_plot"
install -m 755 scripts/plot-orbdbd.py "$INSTALL_DIR"/
install -m 755 scripts/plot-wlpdbd.py "$INSTALL_DIR"/
install -m 755 scripts/plot-dcbdbd.py "$INSTALL_DIR"/
install -m 755 scripts/plot-ircdbd.py "$INSTALL_DIR"/
install -m 644 "$CONFIG_TEMPLATE" "$INSTALL_DIR/config_template"
install -m 644 "$SAT_PARAMETERS" "$INSTALL_DIR/sat_parameters"
chmod 755 "$INSTALL_DIR"/algirc* "$INSTALL_DIR"/pdba "$INSTALL_DIR"/pdba_plot "$INSTALL_DIR"/plot-*.py

# Output
if [ -x "$INSTALL_DIR/algirc" ] && [ -x "$INSTALL_DIR/pdba" ] && [ -x "$INSTALL_DIR/pdba_plot" ] && [ -f "$INSTALL_DIR/config_template" ] && [ -f "$INSTALL_DIR/sat_parameters" ] && [ -f "$INSTALL_DIR/leap.sec" ]; then
    if [ "$SYS" = "Darwin" ]; then
        case "${SHELL##*/}" in
            zsh)
                PROFILE_FILE="${HOME}/.zprofile"
                ;;
            bash)
                PROFILE_FILE="${HOME}/.bash_profile"
                ;;
            *)
                PROFILE_FILE="${HOME}/.profile"
                ;;
        esac
    else
        PROFILE_FILE="${HOME}/.bashrc"
    fi
    # Preserve the literal installation path when the profile is sourced.
    PROFILE_INSTALL_DIR=${INSTALL_DIR//\\/\\\\}
    PROFILE_INSTALL_DIR=${PROFILE_INSTALL_DIR//\"/\\\"}
    PROFILE_INSTALL_DIR=${PROFILE_INSTALL_DIR//\$/\\\$}
    PROFILE_INSTALL_DIR=${PROFILE_INSTALL_DIR//\`/\\\`}
    PATH_LINE="export PATH=\"$PROFILE_INSTALL_DIR:\$PATH\""
    touch "$PROFILE_FILE"
    grep -Fx "$PATH_LINE" "$PROFILE_FILE" >/dev/null 2>&1 || printf '%s\n' "$PATH_LINE" >> "$PROFILE_FILE"

    if [ -f "$LOGO_FILE" ]; then
        printf "${LOGO_RED}"
        cat "$LOGO_FILE"
        printf "${NC}\n"
    fi

    printf "${BLUE}::${NC} %s (v%s) installation successfully completed!\n" "$PROJECT_NAME" "$VERSION_NUM"
    printf "${BLUE}::${NC} executable binaries are copied to %s\n" "$INSTALL_DIR"
    printf "${BLUE}::${NC} %s added to PATH in %s\n" "$INSTALL_DIR" "$PROFILE_FILE"
    check_plot_dependencies
    run_example_tests
else
    printf "${RED}error:${NC} %s installation failed!\n" "$PROJECT_NAME" >&2
    exit 1
fi
