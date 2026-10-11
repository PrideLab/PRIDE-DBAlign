#!/usr/bin/env python3

###############################################################################
##                                                                           ##
##  PURPOSE: Plot GNSS phase/code DOCB heatmaps                              ##
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

# Reference code channels used by algirc for each frequency.
CODE_CHANNELS = {
    "G": {1: "C1W", 2: "C2W"},
    "E": {1: "C1C", 5: "C5Q"},
    "C": {2: "C2I", 6: "C6I"},
}
BDS_MERGED_MJD = 61153


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
    return pylab.array(indices, dtype=int)


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
    """Read phase (4.1) and reference-channel code (4.2) DOCB statistics."""
    try:
        with open(filnam, "r", encoding="utf-8") as fil:
            record = fil.readlines()
    except OSError:
        print("***ERROR: open file '" + filnam.strip() + "'")
        sys.exit(1)

    nmjd = mjd1 - mjd0 + 1

    flglst = pylab.full((len(prnlst), nmjd), 0)
    datsec41 = pylab.full((len(prnlst), 9, 3, nmjd), pylab.nan)
    datsec42 = pylab.full((len(prnlst), 9, 3, nmjd), pylab.nan)

    section = ""
    in_docb = False
    for line in record:
        line = line.rstrip("\r\n")
        if line and line[0].isdigit():
            section = line.split()[0]
            if line == "4. CORRECTIONS AND RESIDUALS FOR CODE/PHASE BIASES":
                in_docb = True
            elif section not in ("4.1", "4.2"):
                in_docb = False
            continue
        if len(line) < 19 or line[0] != " ":
            continue

        # Keep deletion flags from earlier sections, but read DOCB values
        # only inside section 4 with the expected subsection record length.
        is_docb = in_docb and (
            (section == "4.1" and len(line) == 49)
            or (section == "4.2" and len(line) == 64)
        )
        if not is_docb and line[11] != "*":
            continue
        if not line[13:18].isdigit():
            continue
        try:
            iprn = prnlst.index(line[1:4])
        except ValueError:
            continue

        imjd = int(line[13:18]) - mjd0
        if imjd < 0 or imjd >= nmjd:
            continue
        if line[11] == "*":
            flglst[iprn, imjd] = 1

        if not is_docb:
            continue
        ifrq = int(line[7])
        fields = line.split("|")
        if section == "4.1":
            datsec41[iprn, ifrq, :, imjd] = [
                int(fields[2]), *map(int, fields[3].split())
            ]
        else:
            prn = prnlst[iprn]
            channel = CODE_CHANNELS[prn[0]].get(ifrq)
            if fields[2].strip() != channel:
                continue
            datsec42[iprn, ifrq, :, imjd] = [
                int(fields[3]), *map(int, fields[4].split()[1:])
            ]

    return flglst, datsec41, datsec42


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


def datum_groups(prnlst, mjd0, nday):
    """Return the datum group id of every satellite on every day.

    The result has shape (nsat, nday). Satellites sharing an id share one
    daily datum offset: GPS and Galileo always form their own group, while
    BDS-2 and BDS-3 form separate groups before BDS_MERGED_MJD and a
    common group from that MJD on, except C09/C10 share a separate group.
    """
    merged = mjd0 + pylab.arange(nday) >= BDS_MERGED_MJD

    groups = pylab.zeros((len(prnlst), nday), dtype=int)
    for index, prn in enumerate(prnlst):
        if prn[0] == "G":
            groups[index, :] = 1
        elif prn[0] == "E":
            groups[index, :] = 2
        elif prn[0] == "C":
            groups[index, :] = 3
            if int(prn[1:3]) >= 17:
                groups[index, ~merged] = 4
            if prn in ("C09", "C10"):
                groups[index, merged] = 4
    return groups


def remove_datum_shift(values, groups):
    """Subtract the per-day mean of each datum group from its values.

    ``values`` holds the day-boundary statistics of one signal for all
    satellites with shape (nsat, nday); missing values are NaN.
    """
    for group in pylab.unique(groups):
        member = groups == group
        valid = member & pylab.isfinite(values)
        count = valid.sum(axis=0)
        total = pylab.where(valid, values, 0.0).sum(axis=0)
        values = values - pylab.where(member, total / pylab.maximum(count, 1), 0.0)
    return values


def plot_phase_docb_out(fignam, satlst, flglst, datasec41, mjd, mjd0, mjd1):
    """Plot phase DOCB by GNSS signal."""
    doy = int(mjd_to_datetime(mjd).strftime("%j"))
    year = int(mjd_to_datetime(mjd0).strftime("%Y"))
    doy0 = int(mjd_to_datetime(mjd0).strftime("%j"))

    nday = datasec41.shape[3]
    prnlst = pylab.array([sat[0] for sat in satlst])
    namlst = pylab.array([sat[1] + " / " + sat[0] for sat in satlst])

    # Split satellites into constellation-specific frequency panels.
    sysidx = [
        (
            select_prns(prnlst, "G"),
            (1, "L1"),
            (2, "L2"),
        ),
        (
            select_prns(prnlst, "E"),
            (1, "E1"),
            (5, "E5a"),
        ),
        (
            select_prns(prnlst, "C", max_prn=16),
            (2, "B1I"),
            (6, "B3I"),
        ),
        (
            select_prns(prnlst, "C", min_prn=17),
            (2, "B1I"),
            (6, "B3I"),
        ),
    ]

    # Use the last plotted day to select the BDS panel layout.
    if mjd >= BDS_MERGED_MJD:
        sysidx = sysidx[:2] + [(select_prns(prnlst, "C"), *sysidx[3][1:])]

    # Configure plot layout.
    # pylab.rcParams['font.family'] = 'Helvetica'
    pylab.rcParams["font.size"] = 14
    height_ratios = [max(1, len(system[0])) for system in sysidx]
    first_system = next((i for i, system in enumerate(sysidx) if len(system[0])), None)
    fig, ax = pylab.subplots(
        len(sysidx),
        2,
        figsize=(20, 20),
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
    boundaries = pylab.linspace(0.0, 0.5, 11)
    norm = pylab.Normalize(vmin=boundaries[0], vmax=boundaries[-1])

    # Normalize data and mark deleted satellites with under-range values.
    data = abs(datasec41) / 1e3
    for k in range(flglst.shape[1]):
        data[flglst[:, k] != 0, :, 2, k] = -1

    # Draw heatmaps.
    for i in range(ax.shape[0]):
        for j in range(ax.shape[1]):
            if len(sysidx[i][0]) == 0 or len(sysidx[i]) < j + 2:
                ax[i, j].axis("off")
                continue

            sat_idx = sysidx[i][0]
            freq_idx = sysidx[i][j + 1][0]
            values = data[sat_idx, freq_idx, 2, :]

            heatmap = ax[i, j].imshow(
                values, aspect="auto", cmap=colormap, norm=norm
            )

            if i == first_system and j == 0:
                cbar_ax = fig.add_axes([0.130, 0.908, 0.360, 0.006])
                fig.colorbar(
                    heatmap, cax=cbar_ax, orientation="horizontal",
                    boundaries=boundaries, ticks=boundaries,
                )

                cbar_ax.set_xlabel(
                    "Phase DOCB at day-boundary (cycle)",
                    fontsize=16,
                    labelpad=12,
                )
                cbar_ax.xaxis.set_ticks_position("top")
                cbar_ax.xaxis.set_label_position("top")

                covb_ax = fig.add_axes([0.490, 0.908, 0.018, 0.006])
                covb_ax.set_xticks([])
                covb_ax.set_yticks([])
                covb_ax.patch.set(facecolor="red")

                cdel_ax = fig.add_axes([0.098, 0.908, 0.018, 0.006])
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
            day_values = data[sat_idx, freq_idx, 2, mjd - mjd0]
            avl_sat = day_values >= 0.0
            rms = pylab.sqrt(pylab.mean(day_values[avl_sat] ** 2)) if avl_sat.any() else pylab.nan
            ax[i, j].set_title(
                "Mean RMS (" + sysidx[i][j + 1][1] + ") on %d/%d: %5.2f cy"
                % (year, doy, rms),
                fontsize=16,
                pad=8,
            )

            # ax[i, j].xaxis.grid(color='black', linestyle='dotted')

    # Save figure.
    pylab.subplots_adjust(wspace=0.05)
    pylab.savefig(fignam, dpi=200, bbox_inches="tight", pad_inches=0.02)
    pylab.close(fig)
    # pylab.show()


def plot_code_docb_out(fignam, satlst, flglst, datasec42, mjd, mjd0, mjd1):
    """Plot code DOCB residuals by GNSS signal."""
    doy = int(mjd_to_datetime(mjd).strftime("%j"))
    year = int(mjd_to_datetime(mjd0).strftime("%Y"))
    doy0 = int(mjd_to_datetime(mjd0).strftime("%j"))

    nday = datasec42.shape[3]
    prnlst = pylab.array([sat[0] for sat in satlst])
    namlst = pylab.array([sat[1] + " / " + sat[0] for sat in satlst])

    # Split satellites into constellation-specific frequency panels.
    sysidx = [
        (
            select_prns(prnlst, "G"),
            (1, "L1"),
            (2, "L2"),
        ),
        (
            select_prns(prnlst, "E"),
            (1, "E1"),
            (5, "E5a"),
        ),
        (
            select_prns(prnlst, "C", max_prn=16),
            (2, "B1I"),
            (6, "B3I"),
        ),
        (
            select_prns(prnlst, "C", min_prn=17),
            (2, "B1I"),
            (6, "B3I"),
        ),
    ]

    # Use the last plotted day to select the BDS panel layout.
    if mjd >= BDS_MERGED_MJD:
        sysidx = sysidx[:2] + [(select_prns(prnlst, "C"), *sysidx[3][1:])]

    # Configure plot layout.
    # pylab.rcParams['font.family'] = 'Helvetica'
    pylab.rcParams["font.size"] = 14
    height_ratios = [max(1, len(system[0])) for system in sysidx]
    first_system = next((i for i, system in enumerate(sysidx) if len(system[0])), None)
    fig, ax = pylab.subplots(
        len(sysidx),
        2,
        figsize=(20, 20),
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
    boundaries = pylab.linspace(0.0, 1.0, 11)
    norm = pylab.Normalize(vmin=boundaries[0], vmax=boundaries[-1])

    # Normalize data and mark deleted satellites with under-range values.
    data = datasec42 / 1e3
    for k in range(flglst.shape[1]):
        data[flglst[:, k] != 0, :, 1, k] = pylab.nan

    # Log residuals precede DOCB mean removal; remove each daily system datum.
    groups = datum_groups(prnlst, mjd0, nday)
    for ifrq in range(data.shape[1]):
        data[:, ifrq, 1, :] = remove_datum_shift(data[:, ifrq, 1, :], groups)
    data = abs(data)
    for k in range(flglst.shape[1]):
        data[flglst[:, k] != 0, :, 1, k] = -1

    # Draw heatmaps.
    for i in range(ax.shape[0]):
        for j in range(ax.shape[1]):
            if len(sysidx[i][0]) == 0 or len(sysidx[i]) < j + 2:
                ax[i, j].axis("off")
                continue

            sat_idx = sysidx[i][0]
            freq_idx = sysidx[i][j + 1][0]
            values = data[sat_idx, freq_idx, 1, :]

            heatmap = ax[i, j].imshow(
                values, aspect="auto", cmap=colormap, norm=norm
            )

            if i == first_system and j == 0:
                cbar_ax = fig.add_axes([0.130, 0.908, 0.360, 0.006])
                fig.colorbar(
                    heatmap, cax=cbar_ax, orientation="horizontal",
                    boundaries=boundaries, ticks=boundaries,
                )

                cbar_ax.set_xlabel(
                    "Code DOCB at day-boundary (ns)",
                    fontsize=16,
                    labelpad=12,
                )
                cbar_ax.xaxis.set_ticks_position("top")
                cbar_ax.xaxis.set_label_position("top")

                covb_ax = fig.add_axes([0.490, 0.908, 0.018, 0.006])
                covb_ax.set_xticks([])
                covb_ax.set_yticks([])
                covb_ax.patch.set(facecolor="red")

                cdel_ax = fig.add_axes([0.098, 0.908, 0.018, 0.006])
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
            day_values = data[sat_idx, freq_idx, 1, mjd - mjd0]
            avl_sat = day_values >= 0.0
            rms = pylab.sqrt(pylab.mean(day_values[avl_sat] ** 2)) if avl_sat.any() else pylab.nan
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
    pylab.close(fig)
    # pylab.show()


def main(argv):
    """Read ALGIRC output and generate phase and code DOCB heatmaps."""
    if len(argv) <= 1:
        show_help()
        return 1

    filnam = argv[1]
    if not os.path.isfile(filnam):
        print("***ERROR: open file '" + filnam.strip() + "'")
        return 1

    # Extract MJD tags from ALGIRC output to define the plotting year span.
    tmpout = subprocess.run(
        ["awk", r'$1 ~ /^[A-Z][0-9][0-9]$/ && substr($0,14,5) ~ /^[0-9][0-9][0-9][0-9][0-9]$/ {print substr($0,14,5)}', filnam],
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

    flglst, datsec41, datsec42 = read_algirc_out(
        prnlst, filnam, mjd0, mjd1
    )

    plot_phase_docb_out(
        "fig-phase-docb.png", satlst, flglst, datsec41, mjd, mjd0, mjd1
    )
    plot_code_docb_out(
        "fig-code-docb.png", satlst, flglst, datsec42, mjd, mjd0, mjd1
    )

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
