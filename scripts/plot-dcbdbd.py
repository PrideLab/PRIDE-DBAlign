#!/usr/bin/env python3

###############################################################################
##                                                                           ##
##  PURPOSE: Plot GNSS code bias day-boundary discontinuity heatmap          ##
##                                                                           ##
##  AUTHOR : Jihang Lin, Yangyang Wang                                       ##
##                                                                           ##
##  VERSION: ver 1.1                                                         ##
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

import datetime
import itertools
import os
import subprocess
import sys

import pylab

# Basic constants and satellite selections used by the heatmap products.
ZMJDAY = datetime.datetime(1858, 11, 17, 0, 0, 0)
GNSS_SYSTEMS = "GEC"
EXCLUDED_PRNS = {
    "E20", "E22",
    "C01", "C02", "C03", "C04", "C05", "C31", "C48", "C50",
    "C56", "C57", "C58", "C59", "C60", "C61", "C62",
}
SATELLITE_BLOCK_ORDER = [
    "BLOCK IIR-A", "BLOCK IIR-B", "BLOCK IIR-M", "BLOCK IIF",
    "BLOCK IIIA", "GALILEO-1", "GALILEO-2",
]


# Function definitions.
def show_help():
    """Print command-line usage."""
    script = os.path.basename(__file__)
    print(f"usage: {script} filnam")


def mjd_to_datetime(mjd):
    """Convert Modified Julian Date (MJD) to ``datetime``."""
    return ZMJDAY + datetime.timedelta(days=mjd)


def select_prns(prnlst, system, min_prn=None, max_prn=None):
    """Return PRN indices for one GNSS constellation and PRN range."""
    indices = []
    for index, prn in enumerate(prnlst):
        if prn[0:1] != system:
            continue
        if min_prn is not None or max_prn is not None:
            prn_number = int(prn[1:3])
            if min_prn is not None and prn_number < min_prn:
                continue
            if max_prn is not None and prn_number > max_prn:
                continue
        indices.append(index)
    return pylab.array(indices)


def read_sat_para(filnam, mjday):
    """Read PRN, SVN, and block information valid at the target MJD."""
    try:
        with open(filnam, "r", encoding="utf-8") as fil:
            record = fil.readlines()
    except OSError:
        print("***ERROR: open file '" + filnam.strip() + "'")
        sys.exit(1)

    satlst = []
    for line in record:
        if not line or line[0] != " ":
            continue

        if line[12:19] != "0000000":
            date_beg = datetime.datetime.strptime(line[12:19], "%Y%j")
            if mjday < (date_beg - ZMJDAY).days:
                continue
        if line[26:33] != "0000000":
            date_end = datetime.datetime.strptime(line[26:33], "%Y%j")
            if mjday > (date_end - ZMJDAY).days:
                continue

        svn = line[6:10]
        if svn[0] not in GNSS_SYSTEMS or svn in itertools.chain(*satlst):
            continue

        prn = line[1:4]
        if prn in EXCLUDED_PRNS:
            continue

        blk = line[71:].strip()
        satlst.append([prn, svn, blk])

    return pylab.array(satlst)


def read_algirc_out(prnlst, filnam, mjd0, mjd1):
    """Read fixed-width day-boundary statistics from ALGIRC output."""
    try:
        with open(filnam, "r", encoding="utf-8") as fil:
            record = fil.readlines()
    except OSError:
        print("***ERROR: open file '" + filnam.strip() + "'")
        sys.exit(1)

    nmjd = mjd1 - mjd0 + 1

    flglst = pylab.full((len(prnlst), nmjd), 0)
    datsec1 = pylab.full((len(prnlst), 6, nmjd), pylab.nan)
    datsec2 = pylab.full((len(prnlst), 7, nmjd), pylab.nan)
    datsec3 = pylab.full((len(prnlst), 9, 8, nmjd), pylab.nan)
    datsec4 = pylab.full((len(prnlst), 9, 6, nmjd), pylab.nan)
    datsec6 = pylab.full((len(prnlst), 9, 2, nmjd), pylab.nan)

    for line in record:
        if not line or line[0] != " ":
            continue

        record_len = len(line)
        if record_len < 39:
            continue

        try:
            iprn = prnlst.index(line[1:4])
        except ValueError:
            # print("***WARNING: PRN not found in prnlst: " + line[1:4])
            iprn = -1

        if iprn < 0:
            continue

        imjd = int(line[13:18]) - mjd0
        if imjd < 0 or imjd >= nmjd:
            continue

        # ALGIRC sections are identified by their fixed-width record length.
        if record_len == 39:
            ifrq = int(line[7])
            datsec6[iprn, ifrq, 0, imjd] = int(line[20:29])
            datsec6[iprn, ifrq, 1, imjd] = int(line[29:38])
            continue

        if record_len == 79:
            if line[11] == "*":
                flglst[iprn, imjd] = 1
            datsec1[iprn, 0, imjd] = int(line[20:29])
            datsec1[iprn, 1, imjd] = int(line[29:38])
            datsec1[iprn, 2, imjd] = int(line[40:49])
            datsec1[iprn, 3, imjd] = int(line[49:58])
            datsec1[iprn, 4, imjd] = int(line[60:69])
            datsec1[iprn, 5, imjd] = int(line[69:78])
            continue

        if record_len == 81:
            ifrq = int(line[7])
            datsec4[iprn, ifrq, 0, imjd] = int(line[20:29])
            datsec4[iprn, ifrq, 1, imjd] = int(line[31:40])
            datsec4[iprn, ifrq, 2, imjd] = int(line[40:49])
            datsec4[iprn, ifrq, 3, imjd] = int(line[51:60])
            datsec4[iprn, ifrq, 4, imjd] = int(line[62:71])
            datsec4[iprn, ifrq, 5, imjd] = int(line[71:80])
            continue

        if record_len == 90:
            datsec2[iprn, 0, imjd] = int(line[20:29])
            datsec2[iprn, 1, imjd] = int(line[29:38])
            datsec2[iprn, 2, imjd] = int(line[40:49])
            datsec2[iprn, 3, imjd] = int(line[49:58])
            datsec2[iprn, 4, imjd] = int(line[60:69])
            datsec2[iprn, 5, imjd] = int(line[71:80])
            datsec2[iprn, 6, imjd] = int(line[80:89])
            continue

        if record_len == 99:
            ifrq = int(line[7])
            datsec3[iprn, ifrq, 0, imjd] = int(line[20:29])
            datsec3[iprn, ifrq, 1, imjd] = int(line[29:38])
            datsec3[iprn, ifrq, 2, imjd] = int(line[40:49])
            datsec3[iprn, ifrq, 3, imjd] = int(line[49:58])
            datsec3[iprn, ifrq, 4, imjd] = int(line[60:69])
            datsec3[iprn, ifrq, 5, imjd] = int(line[69:78])
            datsec3[iprn, ifrq, 6, imjd] = int(line[80:89])
            datsec3[iprn, ifrq, 7, imjd] = int(line[89:98])
            continue

    return flglst, datsec1, datsec2, datsec3, datsec4, datsec6


def sort_sat(satlst):
    """Return satellite indices sorted by GNSS block and SVN."""
    blklst = pylab.array([sat[2] for sat in satlst])
    svnlst = pylab.array([sat[1] for sat in satlst])

    sort_index = []
    for name in SATELLITE_BLOCK_ORDER:
        blk_sort_index = pylab.array(
            [index for index, block in enumerate(blklst) if name == block]
        )
        svn_sort_index = pylab.argsort(svnlst[blk_sort_index])
        sort_index.extend(blk_sort_index[svn_sort_index])

    return sort_index


def plot_dcbdbd_out(fignam, satlst, flglst, datasec2, datasec4, mjd, mjd0, mjd1):
    """Plot code bias day-boundary discontinuities by GNSS signal."""
    doy = int(mjd_to_datetime(mjd).strftime("%j"))
    year = int(mjd_to_datetime(mjd0).strftime("%Y"))
    doy0 = int(mjd_to_datetime(mjd0).strftime("%j"))

    nday = datasec2.shape[2]
    prnlst = pylab.array([sat[0] for sat in satlst])
    namlst = pylab.array([sat[1] + " / " + sat[0] for sat in satlst])

    # Split satellites into constellation-specific frequency panels.
    sysidx = [
        (
            select_prns(prnlst, "G"),
            (0, "L1-L2"),
            (5, "L5"),
        ),
        (
            select_prns(prnlst, "E"),
            (0, "E1-E5a"),
            (6, "E6"),
            (7, "E5b"),
            (8, "E5"),
        ),
        (
            select_prns(prnlst, "C", max_prn=16),
            (0, "B1I-B3I"),
            (7, "B2I"),
        ),
        (
            select_prns(prnlst, "C", min_prn=17),
            (0, "B1I-B3I"),
            (1, "B1C"),
            (5, "B2a"),
            (7, "B2b"),
        ),
    ]

    # Configure plot layout.
    # pylab.rcParams['font.family'] = 'Helvetica'
    pylab.rcParams["font.size"] = 14
    height_ratios = [len(system[0]) for system in sysidx]
    fig, ax = pylab.subplots(
        4,
        1,
        figsize=(10, 20),
        squeeze=False,
        gridspec_kw={"height_ratios": height_ratios},
    )

    xlim = (-0.5, nday - 0.5)
    if nday >= 210:
        xticks = pylab.arange(-doy0, 600, 60)
    elif nday > 70:
        xticks = pylab.arange(-doy0, 600, 30)
    elif nday > 35:
        xticks = pylab.arange(-doy0, 600, 10)
    elif nday > 7:
        xticks = pylab.arange(-doy0, 600, 5)
    else:
        xticks = pylab.arange(-doy0, 600, 1)
    xticklabels = (xticks + doy0).astype(int)

    # Configure color bar; red marks coverage breaks and blue marks deletions.
    colormap = pylab.cm.summer
    colormap = pylab.matplotlib.colors.ListedColormap(
        colormap(pylab.linspace(0.0, 1.0, 10))
    )
    colormap.set_over("red")
    colormap.set_under("blue")
    colormap.set_bad("white")
    norm = pylab.Normalize(vmin=0, vmax=1.0)

    # Normalize data and mark deleted satellites with under-range values.
    data2 = abs(datasec2) / 1e3
    data4 = abs(datasec4) / 1e3
    for k in range(flglst.shape[1]):
        data2[flglst[:, k] != 0, 3, k] = -1
        data4[flglst[:, k] != 0, :, 2, k] = -1

    # Draw heatmaps.
    for i in range(ax.shape[0]):
        for j in range(ax.shape[1]):
            if len(sysidx[i]) < j + 2:
                ax[i, j].axis("off")
                continue

            sat_idx = sysidx[i][0]
            if j == 0:
                values = data2[sat_idx, 3, :]
            else:
                freq_idx = sysidx[i][j + 1][0]
                values = data4[sat_idx, freq_idx, 2, :]

            heatmap = ax[i, j].imshow(
                values, aspect="auto", cmap=colormap, norm=norm
            )

            if i == 0 and j == 0:
                cbar_ax = fig.add_axes([0.089, 0.908, 0.772, 0.006])
                fig.colorbar(heatmap, cax=cbar_ax, orientation="horizontal")

                cbar_ax.set_xticks(pylab.arange(0, 1.02, 0.10))
                cbar_ax.set_xlabel(
                    "Code bias discontinuities at day-boundary (ns)",
                    fontsize=16,
                    labelpad=12,
                )
                cbar_ax.xaxis.set_ticks_position("top")
                cbar_ax.xaxis.set_label_position("top")

                covb_ax = fig.add_axes([0.861, 0.908, 0.039, 0.006])
                covb_ax.set_xticks([])
                covb_ax.set_yticks([])
                covb_ax.patch.set(facecolor="red")

                cdel_ax = fig.add_axes([0.020, 0.908, 0.039, 0.006])
                cdel_ax.set_yticks([])
                cdel_ax.set_xlim((0, 1))
                cdel_ax.set_xticks([0.5])
                cdel_ax.set_xticklabels(["Del"])
                cdel_ax.xaxis.set_ticks_position("top")
                cdel_ax.patch.set(facecolor="blue")

            # Configure axes.
            msat = len(sat_idx)
            ylim = (msat - 0.5, -0.5)
            yticks = pylab.arange(0, msat)
            yticklabels = namlst[sat_idx]

            ax[i, j].set_xticks(xticks)
            ax[i, j].set_xticklabels(xticklabels)
            ax[i, j].set_xlim(xlim)

            if j == 0:
                ax[i, j].set_yticks(yticks)
                ax[i, j].set_yticklabels(yticklabels)
            else:
                ax[i, j].set_yticks([])

            ax[i, j].set_ylim(ylim)

            if i == len(sysidx) - 1:
                ax[i, j].set_xlabel(
                    "DOY in %4d" % year, fontsize=16, labelpad=12
                )

            # Annotate daily RMS for the selected day-boundary.
            if j == 0:
                day_values = data2[sat_idx, 3, mjd - mjd0]
            else:
                freq_idx = sysidx[i][j + 1][0]
                day_values = data4[sat_idx, freq_idx, 2, mjd - mjd0]
            avl_sat = day_values >= 0.0
            rms = pylab.sqrt(pylab.nanmean(day_values[avl_sat] ** 2, axis=0))
            ax[i, j].set_title(
                "Mean RMS (" + sysidx[i][j + 1][1] + ") on %d/%d: %5.2f ns"
                % (year, doy, rms),
                fontsize=16,
                pad=8,
            )

            # ax[i, j].xaxis.grid(color='black', linestyle='dotted')

    # Save figure.
    pylab.subplots_adjust(wspace=0.05)
    pylab.savefig(fignam, dpi=200, bbox_inches="tight", pad_inches=0.02)
    # pylab.show()


def main(argv):
    """Read ALGIRC output and generate the heatmap figure."""
    if len(argv) <= 1:
        show_help()
        return 1

    filnam = argv[1]
    if not os.path.isfile(filnam):
        print("***ERROR: open file '" + filnam.strip() + "'")
        return 1

    # Extract MJD tags from ALGIRC output to define the plotting year span.
    tmpout = subprocess.run(
        ["grep", "-o", r" [0-9]\{5\} ", filnam],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )
    tmpout = tmpout.stdout.split()

    mjd0 = int(tmpout[0])
    year = mjd_to_datetime(mjd0).strftime("%Y")
    mjd0 = (datetime.datetime.strptime(year + "001", "%Y%j") - ZMJDAY).days

    mjd = int(tmpout[-1])
    year = mjd_to_datetime(mjd).strftime("%Y")
    mjd1 = (
        datetime.datetime.strptime(str(int(year) + 1) + "001", "%Y%j")
        - ZMJDAY
    ).days - 1

    satlst = read_sat_para("sat_parameters", mjd0)
    prnlst = [sat[0] for sat in satlst]

    flglst, datsec1, datsec2, datsec3, datsec4, datsec6 = read_algirc_out(
        prnlst, filnam, mjd0, mjd1
    )

    fignam = "fig-dcbdbd.png"
    plot_dcbdbd_out(
        fignam, satlst, flglst, datsec2, datsec4, mjd, mjd0, mjd1
    )

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
