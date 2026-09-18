!
!! algirc.f90
!!
!!    Copyright (C) 2026 by SKLPG, CAS and Wuhan University
!!
!!    This program is part of PRIDE DBAlign, an open source software package:
!!    you can redistribute it and/or modify it under the terms of the GNU
!!    General Public License (version 3) as published by the Free Software Foundation.
!!
!!    This program is distributed in the hope that it will be useful,
!!    but WITHOUT ANY WARRANTY; without even the implied warranty of
!!    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!!    GNU General Public License (version 3) for more details.
!!
!!    You should have received a copy of the GNU General Public License
!!    along with this program.  If not, see <https://www.gnu.org/licenses/>.
!!
!! Contributor: Jianghui Geng, Jihang Lin, Yangyang Wang, Qiang Wen
!!
!!
!! Abbreviation List
!!
!! ATT          Obeservation Attribute (tracking mode or channel)
!! ALG          Alignment at day-boundary
!! ALP          The Alpha/First Coefficient (of linear combination)
!! AVL          Available/Usable
!! BIA          Code/Phase Bias
!! CFG          Configuration
!! CMB          Linear Combination
!! DINTV/INTV   Interval
!! DBD          Day Boundary Discontinuity 
!! DCB          Differential Code Bias (geometry-free code bias)
!! DOCB         Differences of Orbit, Clock, and Bias (CLK - ORB - NLP), = IRC
!! EWL          Extra-Wide-Lane Phase Bias
!! FIL          File
!! FRC          Fractional Part (of)
!! FRQ          Frequency
!! FRTO         Frequency Ratio
!! GFB          Geometry-Free Phase Bias
!! IDX          Index (of)
!! IRC          Integer Recover Clock (CLK - ORB - NLP), = DOCB
!! LAM          Lambda/Wavelenth
!! LST          List
!! MSG          Message
!! NLP          Narrow-Lane Phase Bias
!! OFF          Offset/Adjustment/Correction at day-boundary
!! OCB          Observable-Specific Code Bias (Code OSB)
!! OPB          Observable-Specific Phase Bias (Phase OSB)
!! ORB          Orbit (radial correction)
!! PRIO         Priority
!! PRN          Pseudo-Random Noise code for satellite
!! RMS          Root Mean Square (error/residual)
!! RTO          Ratio
!! SVN          Space Vehicle Number for satellite
!! SYS          GNSS Satellite System 
!! UIC          Uncombined IRC
!! WLP          Wide-Lane Phase Bias
!!
program algirc
  use, intrinsic :: iso_fortran_env, only: iostat_end, error_unit
  use get_config, only: read_logical_option
  use form_combination, only: MWCMB, IFCMB
  use calc_stats, only: AVERAGE, AVEFRAC, prn2idx
  use wrt_clock, only: rdclkh, lsq_fit, expclk
  use wrt_orbit, only: exporb
  use wrt_bias, only: expbia

  implicit none
  include '../header/absbia.h'
  include '../header/const.h'
  include '../header/orbit.h'

!! ----------------------------------------- !!
!!                                           !!
!! I. Variable Definition and Initialization !!
!!                                           !!
!! ----------------------------------------- !!

  !! constant
  character(*), parameter :: CPROGNAME = 'algirc'
  integer*4,    parameter :: CLOCK_HISTORY_POINTS = 10
  real*8,       parameter :: MAX_CLOCK_EXTRAPOLATION = 300.d0
  integer*4,    parameter :: MAXCMB = 2
  integer*4,    parameter :: TRIG_HISTORY_POINTS = 13 ! 13 5-minute epochs span a 60-minute fitting arc
  integer*4,    parameter :: TRIG_HARMONICS = 3
  integer*4,    parameter :: TRIG_TERMS = 2*TRIG_HARMONICS + 1
  real*8,       parameter :: ORB_EXTRAPOLATION_INTERVAL = 300.d0
  real*8,       parameter :: MAX_ORB_EXTRAPOLATION = 300.d0
  integer*4,    parameter :: IDXFRQ_MUL(4, MAXSYS, 2) = reshape(     &
!--|---- GPS ----|-- GLONASS --|-- Galileo --|---- BDS ----|--- QZSS ---|--! 
    [1, 1, 1, 1,   1, 1, 1, 1,   1, 1, 1, 1,   2, 2, 2, 2,   1, 1, 1, 1,  &
     2, 5, 5, 5,   2, 2, 2, 2,   5, 6, 7, 8,   6, 7, 5, 1,   2, 2, 2, 2], &
    [4, MAXSYS, 2])

  !! global
  integer*4     ierr
  integer*4     nprn
  character*3   prnlst(MAXSAT)
  logical*1     avlprn(0:MAXCMB, MAXSAT, 0:MAXTYP/4)
  logical*1     l_wrt_docb
  logical*1     l_backward
  logical*1     l_rmv_gf
  logical*1     l_unify_bd23
  logical*1     l_unify_default
  logical*1     l_orb_dbd
  logical*1     l_extorb

  !! argument
  integer*4     narg
  character*256 msg, key, line
  character(len=256) :: io_message

  !! file
  integer*4     cfglfn, outlfn
  character*256 cfgfil, outfil
  character*256 prddir
  character*256 sp3fil(2), clkfil(2), biafil(2)

  !! data
  type(orbhdr)  HORB
  type(absbia)  BIAS0(MAXSAT, MAXTYP), BIAS1(MAXSAT, MAXTYP)
  character*1   ATT_PRIO_E
  character*1   ATT_PRIO_C

  !! clock
  integer*4     mjd0, mjd1, mjd_ref
  real*8        sod0, sod1, sod_ref, intv, period
  real*8        clk_end_sod, clk_intv0, clk_period0, clk_gap, clk_gap_limit
  real*8        clock_extrapolation_steps
  real*8        clk_rms(MAXSAT)
  real*8        clk_dbd(MAXSAT)
  real*8        clk_extp(MAXSAT)
  real*8        clk_off(MAXSAT)
  real*8        avg_clk_dbd(MAXSYS+1)
  logical*1     l_extclk(MAXSAT)

  real*8, pointer :: cache(:, :)

  !! orbit
  real*8        xyz0(6, MAXSAT)
  real*8        xyz1(6, MAXSAT)
  real*8        xyz_trig_ext(6, MAXSAT, TRIG_HISTORY_POINTS)
  real*8        xyz_orb_ext(6, MAXSAT)
  real*8        orb_dbd(MAXSAT)
  integer*4     orb_ext_nprn
  character*3   orb_ext_prn(MAXSAT)

  !! bias (baseline frequencies)
  real*8        irc_dbd(MAXSAT)
  real*8        gfb_dbd(MAXSAT)
  real*8        dcb_dbd(MAXSAT), wlp_dbd(MAXSAT), nlp_dbd(MAXSAT)
  real*8        dcb_off(MAXSAT), wlp_off(MAXSAT), nlp_off(MAXSAT)
  real*8        avg_dcb_dbd(MAXSYS+1)
  real*8        avg_frc_dbd(MAXSYS+1)

  !! bias (non-baseline frequencies)
  real*8        ocb_dbd(0:MAXCMB, MAXSAT), ewl_dbd(2:MAXCMB, MAXSAT), opb_dbd(0:MAXCMB, MAXSAT)
  real*8        ocb_off(0:MAXCMB, MAXSAT), ewl_off(2:MAXCMB, MAXSAT), opb_off(0:MAXCMB, MAXSAT)

  !! bias (all channels)
  real*8        ocb_itf_dbd(0:MAXCMB,MAXSAT,MAXTYP/4)

  !! coeff
  real*8        FRQ1(MAXCMB, MAXSYS), FRQ2(MAXCMB, MAXSYS), FRTO(MAXCMB, MAXSYS)
  real*8        WALP(MAXCMB, MAXSYS), NALP(MAXCMB, MAXSYS), IALP(MAXCMB, MAXSYS)
  real*8        WLAM(MAXCMB, MAXSYS), NLAM(MAXCMB, MAXSYS)

  !! local
  logical*1     shift_half_cycle(MAXSYS+1), l_orb_corr
  integer*4     ic, i0, i1, iprn, it, j, k, orb_jd0, orb_jd1, orb_ext_jd
  character*3   prn
  real*8        var, dummy, l1, l2, c1, c2, tmp_off(MAXSAT)
  real*8        orb_sod0, orb_sod1, orb_gap, orb_intv0, orb_ext_sod
  real*8        ghar, xrot, yrot, zrot
  character*256 orb_erpfile
  real*8        mate2j(3,3), rmte2j(3,3), xpole, ypole
  logical       use_orb_erp

  !! output
  integer*4     time_tag(8)

!
!! function list
  integer*4     get_valid_unit
  integer*4     modified_julday
  integer*4     pointer_string
  real*8        dot
  character*256 findkey

!
!! common parameter
  integer*4     IDXFRQ(MAXSYS, 2)
  common IDXFRQ

!
!! initialize setting
  l_wrt_docb = .true.
  l_backward = .false.
  l_rmv_gf = .true.   ! remove gf datum
  l_unify_bd23 = .false.
  l_unify_default = .true. ! resolve from the target-day MJD
  l_orb_dbd = .true. ! do not apply orbit day-boundary correction by default
  l_extorb = .false.

!
!! initialize coeff
  do ic = 1, MAXCMB
    IDXFRQ = IDXFRQ_MUL(ic, :, :)
    do i0 = 1, MAXSYS
      if (any(IDXFRQ(i0, :) .eq. 0)) cycle
      FRQ1(ic, i0) = FREQ_SYS(IDXFRQ(i0, 1), i0)
      FRQ2(ic, i0) = FREQ_SYS(IDXFRQ(i0, 2), i0)
      FRTO(ic, i0) = FRQ1(ic, i0)/FRQ2(ic, i0)
    end do
    IALP(ic, :) = 1/(1 - 1/FRTO(ic, :)**2)
    NALP(ic, :) = 1/(1 + 1/FRTO(ic, :))
    WALP(ic, :) = 1/(1 - 1/FRTO(ic, :))
    NLAM(ic, :) = VLIGHT/(FRQ1(ic, :) + FRQ2(ic, :))
    WLAM(ic, :) = VLIGHT/(FRQ1(ic, :) - FRQ2(ic, :))
  end do

!
!! initialize variable
  IDXFRQ = IDXFRQ_MUL(1, :, :)
  nprn = 0
  prnlst = ''
  avlprn = .false.
  clk_rms = 0.d0
  clk_dbd = 0.d0
  clk_extp = 0.d0
  orb_dbd = 0.d0
  xyz_orb_ext = 0.d0
  orb_ext_nprn = 0
  orb_ext_prn = ''
  irc_dbd = 0.d0
  gfb_dbd = 0.d0
  dcb_dbd = 0.d0
  wlp_dbd = 0.d0
  nlp_dbd = 0.d0
  ewl_dbd = 0.d0
  ocb_dbd = 0.d0
  ocb_itf_dbd = 1.d9
  opb_dbd = 0.d0
  avg_clk_dbd = 0.d0
  avg_frc_dbd = 0.d0
  avg_dcb_dbd = 0.d0
  l_extclk = .false.
  clk_off = 0.d0
  dcb_off = 0.d0
  wlp_off = 0.d0
  nlp_off = 0.d0
  ocb_off = 0.d0
  opb_off = 0.d0

!! ----------------------------------------- !!
!!                                           !!
!! II. Argument and Data Retrieving          !!
!!                                           !!
!! ----------------------------------------- !!

!
!! read argument
  narg = iargc()
  if (narg .lt. 1) then
    write (*, '(a)') 'usage: '//CPROGNAME//' cfgfil [-b]'
    write (*, '(a)') ''
    write (*, '(a)') '  Align all-frequency GNSS phase clock/bias products at day-boundaries'
    write (*, '(a)') ''
    write (*, '(a)') '    created on Mar-07, 2023, last modified on September-18, 2026'
    write (*, '(a)') ''
    write (*, '(a)') 'notice:'
    write (*, '(a)') ''
    write (*, '(a)') '  * Make sure the following settings have been specified in the cfgfil:'
    write (*, '(a)') ''
    write (*, '(a)') '    1. Product directory'
    write (*, '(a)') '    2. Satellite orbit'
    write (*, '(a)') '    3. Satellite clock'
    write (*, '(a)') '    4. Code/phase bias'
    write (*, '(a)') ''
    write (*, '(a)') '  * Use option ‘-b’ to align backward'
    write (*, '(a)') ''
    write (*, '(a)') '  * The output phase clock/bias products will be suffixed with “_aligned”'
    write (*, '(a)') '  * Reference-day orbit/clock copies extended only by extrapolation will be suffixed with “_predicted”'
    call exit(1)
  end if

!
!! open config file
  call getarg(1, cfgfil)
  cfglfn = get_valid_unit(10)
  open (cfglfn, file=cfgfil, status='old', iostat=ierr)
  if (ierr .ne. 0) then
    write (*, '(2a)') '***ERROR('//CPROGNAME//'): open file ', trim(cfgfil)
    call exit(1)
  end if

!
!! read config file
  msg = 'Product directory'
  key = findkey(cfglfn, msg, '')
  if (key(1:5) .eq. 'EMPTY') call config_error('find')
  prddir = trim(key)//'/'

  ! Optional ERP path supplied by pdba. Relative paths use Product directory.
  orb_erpfile = ''
  key = findkey(cfglfn, 'ERP file', '')
  key = adjustl(key)
  if (key .ne. 'EMPTY' .and. key .ne. 'NONE' .and. len_trim(key) .gt. 0) then
    if (key(1:1) .eq. '/') then
      orb_erpfile = trim(key)
    else
      orb_erpfile = trim(prddir)//trim(key)
    end if
  end if

  msg = 'Satellite orbit'
  key = findkey(cfglfn, msg, '')
  if (key(1:5) .eq. 'EMPTY') call config_error('find')
  if (key(1:4) .ne. 'NONE') then
    read (key, *, iostat=ierr, iomsg=io_message) sp3fil
    if (ierr .gt. 0) call config_error('read')
    if (ierr .lt. 0) then
      write (error_unit, '(a)') trim(io_message)
      error stop 1
    end if
  else
    sp3fil(1:2) = ''
    write (*, '(a)') '###WARNING('//CPROGNAME//'): no SP3 ephemeris product, no orbit correction applied'
  end if

  msg = 'Satellite clock'
  key = findkey(cfglfn, msg, '')
  if (key(1:5) .eq. 'EMPTY') call config_error('find')
  if (key(1:4) .ne. 'NONE') then
    read (key, *, iostat=ierr, iomsg=io_message) clkfil
    if (ierr .gt. 0) call config_error('read')
    if (ierr .lt. 0) then
      write (error_unit, '(a)') trim(io_message)
      error stop 1
    end if
  else
    write (*, '(a)') '***ERROR('//CPROGNAME//'): no clock product'
    call exit(1)
  end if

  msg = 'Code/phase bias'
  key = findkey(cfglfn, msg, '')
  if (key(1:5) .eq. 'EMPTY') call config_error('find')
  if (key(1:4) .ne. 'NONE') then
    read (key, *, iostat=ierr, iomsg=io_message) biafil
    if (ierr .gt. 0) call config_error('read')
    if (ierr .lt. 0) then
      write (error_unit, '(a)') trim(io_message)
      error stop 1
    end if
  else
    biafil(1:2) = ''
    write (*, '(a)') '###WARNING('//CPROGNAME//'): no phase bias product, no integer ambiguity correction applied'
  end if

  call read_logical_option(cfglfn, 'Write DOCB', l_wrt_docb)
  call read_logical_option(cfglfn, 'Backward alignment', l_backward)
  call read_logical_option(cfglfn, 'Unify BDS-2/3', l_unify_bd23, l_unify_default)
  if (.not. l_orb_dbd) sp3fil(1:2) = ''

!
!! read the product satellite list from both clock headers
  nprn = 0
  prnlst = ''
  do k = 1, 2
    i0 = 0
    outlfn = get_valid_unit(10)
    open (outlfn, file=trim(prddir)//trim(clkfil(k)), status='old', action='read', iostat=ierr)
    if (ierr .ne. 0) then
      write (*, '(2a)') '***ERROR('//CPROGNAME//'): open file ', trim(prddir)//trim(clkfil(k))
      call exit(1)
    end if
    do while (.true.)
      read (outlfn, '(a)', iostat=ierr) line
      if (ierr .ne. 0) then
        write (*, '(2a)') '***ERROR('//CPROGNAME//'): read clock header ', trim(prddir)//trim(clkfil(k))
        call exit(1)
      end if
      if (line(61:68) .eq. 'PRN LIST') then
        i0 = i0 + 1
        do j = 1, 15
          prn = line((j - 1)*4 + 1:(j - 1)*4 + 3)
          if (len_trim(prn) .eq. 0) cycle
          if (index(GNSS_PRIO, prn(1:1)) .le. 0) cycle
          if (nprn .gt. 0) then
            iprn = pointer_string(nprn, prnlst, prn)
            if (iprn .gt. 0) cycle
          end if
          if (nprn .ge. MAXSAT) then
            write (*, '(a,i0)') '***ERROR('//CPROGNAME//'): too many clock satellites; MAXSAT = ', MAXSAT
            call exit(1)
          end if
          nprn = nprn + 1
          prnlst(nprn) = prn
        end do
      else if (line(61:73) .eq. 'END OF HEADER') then
        exit
      end if
    end do
    close (outlfn)
    if (i0 .eq. 0) then
      write (*, '(2a)') '***ERROR('//CPROGNAME//'): no PRN LIST in clock header ', &
        trim(prddir)//trim(clkfil(k))
      call exit(1)
    end if
  end do
  if (nprn .le. 0) then
    write (*, '(a)') '***ERROR('//CPROGNAME//'): no satellites found in clock PRN LIST'
    call exit(1)
  end if
  avlprn = .false.

  msg = '+GNSS satellites'
  key = ''
  do while (key(1:16) .ne. msg(1:16))
    read (cfglfn, '(a)', iostat=ierr, iomsg=io_message) key
    if (ierr .eq. iostat_end) call config_error('find')
    if (ierr .ne. 0) then
      write (error_unit, '(a)') trim(io_message)
      error stop 1
    end if
  end do

  do while (key(1:16) .ne. '-GNSS satellites')
    read (cfglfn, '(a)', iostat=ierr, iomsg=io_message) key
    if (ierr .eq. iostat_end) call config_error('find')
    if (ierr .ne. 0) then
      write (error_unit, '(a)') trim(io_message)
      error stop 1
    end if
    if (key(1:1) .ne. '') cycle
    read (key, *, iostat=ierr) prn
    if (ierr .ne. 0) call config_error('read')
    if (index(GNSS_PRIO, prn(1:1)) .le. 0) cycle
    iprn = pointer_string(nprn, prnlst, prn)
    if (iprn .le. 0) then
      ! write (*, '(a)') '###WARNING('//CPROGNAME//'): configured satellite not found in clock PRN LIST '//prn
    else
      avlprn(:, iprn, :) = .true.
    end if
  end do

  close (cfglfn)

!
!! read options 
  call getarg(2, key)
  if (key(1:2) .eq. '-b') then
    l_backward = .true.
  end if

!
!! read clock (unit: s)
  if (len_trim(clkfil(1)) .gt. 0 .and. len_trim(clkfil(2)) .gt. 0) then
    call rdclkh(trim(prddir)//trim(clkfil(1)), mjd0, sod0, intv, period)
    clk_end_sod = sod0 + period
    clk_intv0 = intv
    clk_period0 = period

    call rdclkh(trim(prddir)//trim(clkfil(2)), mjd1, sod1, intv, period)
    if (l_unify_default) l_unify_bd23 = mjd1 .ge. 61152
    if (abs(sod1) .gt. MAXWND) then
      write (*, '(a,a,a,f10.3)') '***ERROR('//CPROGNAME//'): target-day clock does not start at 00:00:00 <', &
        trim(clkfil(2)), '>, first epoch SOD = ', sod1
      call exit(1)
    end if
    if (mjd1 - mjd0 .ne. 1) then
      write (*, '(a,2i7)') '***ERROR('//CPROGNAME//'): not adjacent dates ', mjd0, mjd1
      call exit(1)
    end if
    clk_gap = abs((mjd1 - mjd0)*86400.d0 + sod1 - clk_end_sod)
    clk_gap_limit = MAX_CLOCK_EXTRAPOLATION
    if (clk_gap .gt. clk_gap_limit) then
      write (*, '(a,f10.3,a,f10.3,a)') '***ERROR('//CPROGNAME//'): clock epoch gap ', &
        clk_gap, ' s exceeds the allowed extrapolation limit (', clk_gap_limit, ' s)'
      call exit(1)
    end if

    it = CLOCK_HISTORY_POINTS
    clock_extrapolation_steps = clk_gap/clk_intv0

    allocate (cache(MAXSAT, it))
    cache = 0.d0
    do j = 1, it 
      do iprn = 1, nprn
        if (.not. avlprn(0, iprn, 0)) cycle
        call read_satclk(trim(prddir)//trim(clkfil(1)), prnlst(iprn), &
                         mjd0, clk_end_sod - clk_intv0*dble(it - j), &
                         mjd_ref, sod_ref, cache(iprn, j), var, ierr)
        if (abs(cache(iprn, j)) .le. 1.d-12 .or. ierr .ne. 0) then
          write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE NO_CLK '//prnlst(iprn)//' <'//trim(clkfil(1))//'>'
          avlprn(:, iprn, :) = .false.
          clk_dbd(iprn) = 0.d0
        end if
      end do
    end do
  
    if (abs(clk_period0 - 86400.d0) .gt. 1.d-3) then
      write (*, '(a,i5,f9.2)') '###WARNING('//CPROGNAME//'): no overlapped clocks at midnight, extrapolate from ', &
        mjd0, aint(clk_end_sod)
      write (*, '(a,f8.1,a,i0,a)') '%%%MESSAGE('//CPROGNAME//'): extrapolate clock ', clk_gap, &
        ' s to 24:00 using a linear fit to the last ', it, ' epochs'
    !
    !! extrapolate by least-squares fitting (unit: s)
      do iprn = 1, nprn
        if (.not. avlprn(0, iprn, 0)) cycle
        call lsq_fit(it, cache(iprn, 1:it), clock_extrapolation_steps, &
                     clk_rms(iprn), clk_dbd(iprn))
        call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
        if (abs(clk_rms(iprn)) .le. 1.d-12 .or. abs(clk_rms(iprn)) .gt. 2.d-10) then
          write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE EXPCLK '//prnlst(iprn)//' <'//trim(clkfil(1))//'>'
          avlprn(:, iprn, :) = .false.
          clk_dbd(iprn) = 0.d0
          l_extclk(iprn) = .false.
        else
          clk_extp(iprn) = clk_dbd(iprn)
          l_extclk(iprn) = .true.
        end if
      end do
    else
      do iprn = 1, nprn
        if (.not. avlprn(0, iprn, 0)) cycle
        call read_satclk(trim(prddir)//trim(clkfil(1)), prnlst(iprn), &
                         mjd0, sod0 + clk_period0,                    &
                         mjd_ref, sod_ref, clk_dbd(iprn), dummy, ierr)
        if (abs(clk_dbd(iprn)) .le. 1.d-12 .or. ierr .ne. 0) then
          write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE NO_CLK '//prnlst(iprn)//' <'//trim(clkfil(1))//'>'
          avlprn(:, iprn, :) = .false.
          clk_dbd(iprn) = 0.d0 
        else
          clk_extp(iprn) = clk_dbd(iprn)
        end if
      end do
    end if
  
    do iprn = 1, nprn
      if (.not. avlprn(0, iprn, 0)) cycle
      call read_satclk(trim(prddir)//trim(clkfil(2)), prnlst(iprn), &
                       mjd1, sod1,                                  &
                       mjd_ref, sod_ref, var, dummy, ierr)
      if (abs(var) .le. 1.d-12 .or. ierr .ne. 0) then
        write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE NO_CLK '//prnlst(iprn)//' <'//trim(clkfil(2))//'>'
        avlprn(:, iprn, :) = .false.
        clk_dbd(iprn) = 0.d0 
      else
        clk_dbd(iprn) = var - clk_dbd(iprn)
      end if
    end do
  else
    write (*, '(a)') '***ERROR('//CPROGNAME//'): clock product not found' 
  end if

!
!! read orbit (unit: km -> s)
  if (l_orb_dbd .and. len_trim(sp3fil(1)) .gt. 0 .and. len_trim(sp3fil(2)) .gt. 0) then
    l_orb_corr = .true.
    xyz0 = 0.d0
    xyz1 = 0.d0

    HORB%nprn = 0
    HORB%prn = ''
    call rdsp3h(trim(prddir)//trim(sp3fil(1)), HORB%jd0, HORB%sod0, HORB%jd1, HORB%sod1, HORB%dintv, HORB%nprn, HORB%prn)
    orb_jd0 = HORB%jd1
    orb_sod0 = HORB%sod1
    orb_intv0 = HORB%dintv
    call rdsp3c()

    HORB%nprn = 0
    HORB%prn = ''
    call rdsp3h(trim(prddir)//trim(sp3fil(2)), HORB%jd0, HORB%sod0, HORB%jd1, HORB%sod1, HORB%dintv, HORB%nprn, HORB%prn)
    orb_jd1 = HORB%jd0
    orb_sod1 = HORB%sod0
    call rdsp3c()

    orb_gap = dble(orb_jd1 - orb_jd0)*86400.d0 + orb_sod1 - orb_sod0
    if (orb_gap .gt. MAXWND .and. &
        abs(orb_intv0 - ORB_EXTRAPOLATION_INTERVAL) .gt. MAXWND) then
      if (orb_intv0 .gt. ORB_EXTRAPOLATION_INTERVAL) then
        write (*, '(a,f8.1,a,f8.1,a)') '###WARNING('//CPROGNAME//'): reference-day orbit is missing 24:00 (gap ', &
          orb_gap, ' s) and its sampling interval is ', orb_intv0, ' s (> 300 s); abort'
      else
        write (*, '(a,f8.1,a,f8.1,a)') '###WARNING('//CPROGNAME//'): reference-day orbit is missing 24:00 (gap ', &
          orb_gap, ' s) and its sampling interval is ', orb_intv0, ' s (expected 300 s); abort'
      end if
      call exit(1)
    end if
    if (abs(orb_gap) .lt. MAXWND) then
      HORB%nprn = 0
      HORB%prn = ''
      call rdsp3h(trim(prddir)//trim(sp3fil(1)), HORB%jd0, HORB%sod0, HORB%jd1, HORB%sod1, HORB%dintv, HORB%nprn, HORB%prn)
      call rdsp3i(orb_jd1, orb_sod1, nprn, prnlst, xyz0, ierr)
      call rdsp3c()
    else if (orb_gap .gt. MAXWND .and. orb_gap .le. MAX_ORB_EXTRAPOLATION) then
      write (*, '(a,f8.1,a,i0,a,i0,a,i0,a)') '%%%MESSAGE('//CPROGNAME//'): extrapolate orbit ', &
        orb_gap, ' s to 24:00 in the inertial frame using an order-', TRIG_HARMONICS, &
        ' (', TRIG_TERMS, '-term) trigonometric fit to the last ', TRIG_HISTORY_POINTS, ' epochs'
      use_orb_erp = len_trim(orb_erpfile) .gt. 0
      if (use_orb_erp) inquire(file=trim(orb_erpfile), exist=use_orb_erp)
      if (use_orb_erp) then
        write (*, '(2a)') '%%%MESSAGE('//CPROGNAME//'): orbit frame conversion uses ERP ', trim(orb_erpfile)
      else
        write (*, '(a)') '%%%MESSAGE('//CPROGNAME//'): no available ERP configured; use getghar/rot3 orbit conversion'
      end if
      xyz_trig_ext = 0.d0
      HORB%nprn = 0
      HORB%prn = ''
      call rdsp3h(trim(prddir)//trim(sp3fil(1)), HORB%jd0, HORB%sod0, HORB%jd1, HORB%sod1, &
        HORB%dintv, HORB%nprn, HORB%prn)
      do j = 1, TRIG_HISTORY_POINTS
        orb_ext_jd = orb_jd0
        orb_ext_sod = orb_sod0 - dble(TRIG_HISTORY_POINTS - j)*orb_intv0
        do while (orb_ext_sod .lt. 0.d0)
          orb_ext_jd = orb_ext_jd - 1
          orb_ext_sod = orb_ext_sod + 86400.d0
        end do
        call rdsp3i(orb_ext_jd, orb_ext_sod, HORB%nprn, HORB%prn, &
          xyz_trig_ext(:, :, j), ierr)
        if (ierr .ne. 0) then
          l_orb_corr = .false.
          exit
        end if
        if (use_orb_erp) then
          call ef2int(orb_erpfile, orb_ext_jd, orb_ext_sod, mate2j, rmte2j, ghar, xpole, ypole)
        else
          call getghar(orb_ext_jd, orb_ext_sod, ghar)
        end if
        do iprn = 1, HORB%nprn
          if (all(abs(xyz_trig_ext(1:3, iprn, j)) .le. 1.d-12) .or. &
              any(abs(xyz_trig_ext(1:3, iprn, j)) .gt. 1.d9)) cycle
          if (use_orb_erp) then
            xyz_trig_ext(1:3, iprn, j) = matmul(mate2j, xyz_trig_ext(1:3, iprn, j))
          else
            call rot3(-ghar, xyz_trig_ext(1, iprn, j), xyz_trig_ext(2, iprn, j), &
              xyz_trig_ext(3, iprn, j), xrot, yrot, zrot)
            xyz_trig_ext(1:3, iprn, j) = [xrot, yrot, zrot]
          end if
        end do
      end do
      call rdsp3c()

      if (l_orb_corr) then
        xyz_orb_ext = 0.d0
        do iprn = 1, HORB%nprn
          call trig_poly_extrapolate(TRIG_HISTORY_POINTS, TRIG_HARMONICS, &
            xyz_trig_ext(1:3, iprn, :), orb_intv0, orb_gap, xyz_orb_ext(1:3, iprn), ierr)
          if (ierr .ne. 0) xyz_orb_ext(1:3, iprn) = 1.d15
        end do
        if (use_orb_erp) then
          call ef2int(orb_erpfile, orb_jd1, orb_sod1, mate2j, rmte2j, ghar, xpole, ypole)
        else
          call getghar(orb_jd1, orb_sod1, ghar)
        end if
        do iprn = 1, HORB%nprn
          if (all(abs(xyz_orb_ext(1:3, iprn)) .le. 1.d-12) .or. &
              any(abs(xyz_orb_ext(1:3, iprn)) .gt. 1.d9)) cycle
          if (use_orb_erp) then
            xyz_orb_ext(1:3, iprn) = matmul(transpose(mate2j), xyz_orb_ext(1:3, iprn))
          else
            call rot3(ghar, xyz_orb_ext(1, iprn), xyz_orb_ext(2, iprn), &
              xyz_orb_ext(3, iprn), xrot, yrot, zrot)
            xyz_orb_ext(1:3, iprn) = [xrot, yrot, zrot]
          end if
        end do
        xyz0 = 1.d15
        do iprn = 1, nprn
          k = pointer_string(HORB%nprn, HORB%prn, prnlst(iprn))
          if (k .gt. 0) xyz0(1:3, iprn) = xyz_orb_ext(1:3, k)
        end do
        l_extorb = .true.
        orb_ext_nprn = HORB%nprn
        orb_ext_prn(1:orb_ext_nprn) = HORB%prn(1:orb_ext_nprn)
      else
        write (*, '(a,i0,a)') '###WARNING('//CPROGNAME//'): fewer than ', TRIG_HISTORY_POINTS, &
          ' usable orbit epochs, no orbit correction applied'
      end if
      if (use_orb_erp) call igserp_reset()
    else
      l_orb_corr = .false.
      if (orb_gap .gt. MAX_ORB_EXTRAPOLATION) then
        write (*, '(a,f8.1,a)') '###WARNING('//CPROGNAME//'): last orbit epoch is ', orb_gap, &
          ' s before 24:00 (> 300 s), no orbit extrapolation applied'
      else
        write (*, '(a)') '###WARNING('//CPROGNAME//'): no overlapped orbits at midnight, no orbit correction applied'
      end if
    end if

    if (l_orb_corr) then
      HORB%nprn = 0
      HORB%prn = ''
      call rdsp3h(trim(prddir)//trim(sp3fil(2)), HORB%jd0, HORB%sod0, HORB%jd1, HORB%sod1, HORB%dintv, HORB%nprn, HORB%prn)
      call rdsp3i(orb_jd1, orb_sod1, nprn, prnlst, xyz1, ierr)
      call rdsp3c()
    end if

    if (l_orb_corr) then
      do iprn = 1, nprn
        if (.not. avlprn(0, iprn, 0)) cycle
        if (all(xyz0(1:3, iprn) .eq. 0.d0) .or. any(abs(xyz0(1:3, iprn)) .gt. 1.d9)) then
          write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE NO_ORB '//prnlst(iprn)//' <'//trim(sp3fil(1))//'>'
          avlprn(:, iprn, :) = .false.
          cycle
        end if
        if (all(xyz1(1:3, iprn) .eq. 0.d0) .or. any(abs(xyz1(1:3, iprn)) .gt. 1.d9)) then
          avlprn(:, iprn, :) = .false.
          write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE NO_ORB '//prnlst(iprn)//' <'//trim(sp3fil(2))//'>'
          cycle
        end if
      !
      !! radial orbit DBD (unit: s)
        orb_dbd(iprn) = dot(3, (xyz1(1:3, iprn) - xyz0(1:3, iprn)), &
          xyz1(1:3, iprn)/dsqrt(dot(3, xyz1(1:3, iprn), xyz1(1:3, iprn)))) * 1E3/VLIGHT 
      end do
    end if
  end if

!
!! read bias (unit: m -> s)
  if (len_trim(biafil(1)) .gt. 0 .and. len_trim(biafil(2)) .gt. 0) then
  !
  !! read code/phase bias (unit: m)
    call read_bias(trim(prddir)//trim(biafil(1)), nprn, prnlst, BIAS0, mjd0*1.d0, (mjd0 + 1)*1.d0)
    call read_bias(trim(prddir)//trim(biafil(2)), nprn, prnlst, BIAS1, mjd1*1.d0, (mjd1 + 1)*1.d0)
    do iprn = 1, nprn
      if (.not. avlprn(0, iprn, 0)) cycle
      i0 = index(GNSS_PRIO, prnlst(iprn)(1:1))

      if (prnlst(iprn)(1:1) .eq. 'G') then
        j = index(OBS_PRIO_G, 'W')
        k = index(OBS_PRIO_G, 'W') + 9
      else if (prnlst(iprn)(1:1) .eq. 'E') then
        j = index(OBS_PRIO_E, 'C')
        k = index(OBS_PRIO_E, 'Q') + 9
      else if (prnlst(iprn)(1:1) .eq. 'C') then
        j = index(OBS_PRIO_C, 'I')
        k = index(OBS_PRIO_C, 'I') + 9
      else
        write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE NO_SYS '//prnlst(iprn)
        avlprn(:, iprn, :) = .false.
        cycle
      end if

      if (BIAS0(iprn, j)%length .le. 0 .or. BIAS0(iprn, j+18)%length .le. 0 .or. &
          BIAS0(iprn, k)%length .le. 0 .or. BIAS0(iprn, k+18)%length .le. 0) then
        write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE NO_BIA '//prnlst(iprn)//' <'//trim(biafil(1))//'>'
        avlprn(:, iprn, :) = .false.
        cycle
      else
        l1 = BIAS0(iprn, j)%val(BIAS0(iprn, j)%length)
        l2 = BIAS0(iprn, k)%val(BIAS0(iprn, k)%length)
        c1 = BIAS0(iprn, j+18)%val(BIAS0(iprn, j+18)%length)
        c2 = BIAS0(iprn, k+18)%val(BIAS0(iprn, k+18)%length)
      end if

      ocb_dbd(0, iprn) = ocb_dbd(0, iprn) - c1
      ocb_dbd(1, iprn) = ocb_dbd(1, iprn) - c2
      opb_dbd(0, iprn) = opb_dbd(0, iprn) - l1
      opb_dbd(1, iprn) = opb_dbd(1, iprn) - l2

      dcb_dbd(iprn) = dcb_dbd(iprn) - (c1 - c2)
      gfb_dbd(iprn) = gfb_dbd(iprn) - (l1 - l2)
      wlp_dbd(iprn) = wlp_dbd(iprn) - MWCMB(WALP, NALP, 1, i0, l1, l2, c1, c2)
      nlp_dbd(iprn) = nlp_dbd(iprn) - IFCMB(IALP, 1, i0, l1, l2)

      if (BIAS1(iprn, j)%length .le. 0 .or. BIAS1(iprn, j+18)%length .le. 0 .or. &
          BIAS1(iprn, k)%length .le. 0 .or. BIAS1(iprn, k+18)%length .le. 0) then
        write (*, '(a)') '###WARNING('//CPROGNAME//'): DELETE NO_BIA '//prnlst(iprn)//' <'//trim(biafil(2))//'>'
        avlprn(:, iprn, :) = .false.
        cycle
      else
        l1 = BIAS1(iprn, j)%val(1)
        l2 = BIAS1(iprn, k)%val(1)
        c1 = BIAS1(iprn, j+18)%val(1)
        c2 = BIAS1(iprn, k+18)%val(1)
      end if

      ocb_dbd(0, iprn) = ocb_dbd(0, iprn) + c1
      ocb_dbd(1, iprn) = ocb_dbd(1, iprn) + c2
      opb_dbd(0, iprn) = opb_dbd(0, iprn) + l1
      opb_dbd(1, iprn) = opb_dbd(1, iprn) + l2

      dcb_dbd(iprn) = dcb_dbd(iprn) + (c1 - c2)
      gfb_dbd(iprn) = gfb_dbd(iprn) + (l1 - l2)
      wlp_dbd(iprn) = wlp_dbd(iprn) + MWCMB(WALP, NALP, 1, i0, l1, l2, c1, c2)
      nlp_dbd(iprn) = nlp_dbd(iprn) + IFCMB(IALP, 1, i0, l1, l2)

      do it = 1, MAXTYP/4
        if (BIAS0(iprn, it+18)%length .gt. 0 .and. BIAS1(iprn, it+18)%length .gt. 0) then
          ocb_itf_dbd(0, iprn, it) = BIAS1(iprn, it+18)%val(BIAS1(iprn, it+18)%length) &
                                   - BIAS0(iprn, it+18)%val(BIAS0(iprn, it+18)%length)
        else
          avlprn(0, iprn, it) = .false.
        end if
        if (BIAS0(iprn, it+27)%length .gt. 0 .and. BIAS1(iprn, it+27)%length .gt. 0) then
          ocb_itf_dbd(1, iprn, it) = BIAS1(iprn, it+27)%val(BIAS1(iprn, it+27)%length) &
                                   - BIAS0(iprn, it+27)%val(BIAS0(iprn, it+27)%length)
        else
          avlprn(1, iprn, it) = .false.
        end if
      end do
    end do
  !
  !! unit conversion (unit: m -> s)
    ocb_dbd(0:1, :) = ocb_dbd(0:1, :) / VLIGHT
    opb_dbd(0:1, :) = opb_dbd(0:1, :) / VLIGHT
    dcb_dbd(:) = dcb_dbd(:) / VLIGHT
    gfb_dbd(:) = gfb_dbd(:) / VLIGHT
    wlp_dbd(:) = wlp_dbd(:) / VLIGHT
    nlp_dbd(:) = nlp_dbd(:) / VLIGHT
    ocb_itf_dbd(0:1, :, :) = ocb_itf_dbd(0:1, :, :) / VLIGHT
  end if

!! ----------------------------------------- !!
!!                                           !!
!! III. Dual-Frequency IRC Alignment         !!
!!                                           !!
!! ----------------------------------------- !!

  !! --------------------------------------------------------------------------------------------------- !!
  !!
  !! IIIa. Dual-Frequency WL Phase Biases
  !!
  !! --------------------------------------------------------------------------------------------------- !!

!
!! in case of misalignment to p/m 0.5 cycle
  shift_half_cycle = .false.
  tmp_off = wlp_off
  wl_half_cycle_adjust: do
    wlp_off = tmp_off
    do iprn = 1, nprn
      call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
      if (shift_half_cycle(i1)) then
        wlp_off(iprn) = wlp_off(iprn) + 0.50 * WLAM(1, i0)/VLIGHT
      end if
    end do

  !
  !! calculate the datum misclosures of WL phase biases
    it = 0
    do while (.true.)
      avg_frc_dbd(:) = AVEFRAC(nprn, l_unify_bd23, prnlst, avlprn(0, :, 0), WLAM(1, :), - wlp_dbd(:) - wlp_off(:))
      do iprn = 1, nprn
        call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
        wlp_off(iprn) = wlp_off(iprn) + avg_frc_dbd(i1)
      end do
      if (all(abs(avg_frc_dbd) .lt. 1.d-12)) exit
      if (it .ge. 16) then
        write (*, '(a)') '###WARNING('//CPROGNAME//'): forced cutoff when iteratively calucate WL phase bias datum'
        exit
      end if
      it = it + 1
    end do

  !
  !! remove the integer part of WL phase bias discontinuities
    do iprn = 1, nprn
      call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
      if (.not. avlprn(0, iprn, 0)) cycle
    !
    !! remove WLC for each satellite
      var = VLIGHT/WLAM(1, i0) * (- wlp_dbd(iprn) - wlp_off(iprn))  ! WL_cycle
      wlp_off(iprn) = wlp_off(iprn) + WLAM(1, i0)/VLIGHT * nint(var) ! off_ns
    !
    !! remove concomitant NLC change
      var = WLAM(1, i0)/NLAM(1, i0) * (1 - NALP(1, i0)) * nint(var)
      nlp_off(iprn) = NLAM(1, i0)/VLIGHT * (var - nint(var))
    end do

  !
  !! in case of misalignment to p/m 0.5 cycle
    if (.not. any(shift_half_cycle)) then
      avg_frc_dbd(:) = AVERAGE(nprn, l_unify_bd23, prnlst, avlprn(0, :, 0), abs(- wlp_dbd(:) - wlp_off(:)))
      do iprn = 1, nprn
        call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
        if (avg_frc_dbd(i1) * VLIGHT/WLAM(1, i0) > 0.30) then
          shift_half_cycle(i1) = .true.
        end if
      end do
      if (any(shift_half_cycle)) cycle wl_half_cycle_adjust
    end if
    exit wl_half_cycle_adjust
  end do wl_half_cycle_adjust

  !! --------------------------------------------------------------------------------------------------- !!
  !!
  !! IIIb. Dual-Frequency IRC & NL Phase Biases
  !!
  !! --------------------------------------------------------------------------------------------------- !!

!
!! calculate the datum misclosures of clocks
  avg_clk_dbd(:) = AVERAGE(nprn, l_unify_bd23, prnlst, avlprn(0, :, 0), clk_dbd(:) - orb_dbd(:))
  do iprn = 1, nprn
    call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
    clk_off(iprn) = - avg_clk_dbd(i1)
  end do

!
!! combine phase clock/bias and radial orbit correction to IRC
  irc_dbd = (clk_dbd + clk_off) - orb_dbd - nlp_dbd

!
!! in case of misalignment to p/m 0.5 cycle
  shift_half_cycle = .false.
  tmp_off = nlp_off
  nl_half_cycle_adjust: do
    nlp_off = tmp_off
    do iprn = 1, nprn
      call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
      if (shift_half_cycle(i1)) then
        nlp_off(iprn) = nlp_off(iprn) + 0.50 * NLAM(1, i0)/VLIGHT
      end if
    end do

  !
  !! calculate the datum misclosures of NL phase biases
    it = 0
    do while (.true.)
      avg_frc_dbd(:) = AVEFRAC(nprn, l_unify_bd23, prnlst, avlprn(0, :, 0), NLAM(1, :), irc_dbd(:) - nlp_off(:))
      do iprn = 1, nprn
        call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
        nlp_off(iprn) = nlp_off(iprn) + avg_frc_dbd(i1)
      end do
      if (all(abs(avg_frc_dbd) .lt. 1.d-12)) exit
      if (it .ge. 16) then
        write (*, '(a)') '###WARNING('//CPROGNAME//'): forced cutoff when iteratively calucate NL phase bias datum'
        exit
      end if
      it = it + 1
    end do

  !
  !! remove the integer part of IRC & NL phase bias discontinuities
    do iprn = 1, nprn
      call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
      if (.not. avlprn(0, iprn, 0)) cycle
    !
    !! remove NLC for each satellite
      var = VLIGHT/NLAM(1, i0) * (irc_dbd(iprn) - nlp_off(iprn))
      nlp_off(iprn) = nlp_off(iprn) + NLAM(1, i0)/VLIGHT * nint(var)
    end do

  !
  !! in case of misalignment to p/m 0.5 cycle
    if (.not. any(shift_half_cycle)) then
      avg_frc_dbd(:) = AVERAGE(nprn, l_unify_bd23, prnlst, avlprn(0, :, 0), abs(irc_dbd(:) - nlp_off(:)))
      do iprn = 1, nprn
        call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
        if (avg_frc_dbd(i1) * VLIGHT/NLAM(1, i0) > 0.30) then
          shift_half_cycle(i1) = .true.
        end if
      end do
      if (any(shift_half_cycle)) cycle nl_half_cycle_adjust
    end if
    exit nl_half_cycle_adjust
  end do nl_half_cycle_adjust

  !! --------------------------------------------------------------------------------------------------- !!
  !!
  !! IIIc. Dual-Frequency GF Phase Biases
  !!
  !! --------------------------------------------------------------------------------------------------- !!

!
!! calculate the GF phase biases 
  do iprn = 1, nprn
    call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
    gfb_dbd(iprn) = gfb_dbd(iprn) - (nlp_off(iprn) - wlp_off(iprn)) * (FRTO(1, i0) - 1/FRTO(1, i0))
  end do

  !! --------------------------------------------------------------------------------------------------- !!
  !!
  !! IIId. Dual-Frequency Linear Transformation
  !!
  !! --------------------------------------------------------------------------------------------------- !!

  do iprn = 1, nprn
    call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
  !
  ! corrections
    opb_off(0, iprn) = - wlp_off(iprn) / FRTO(1, i0) + nlp_off(iprn) / NALP(1, i0)
    opb_off(1, iprn) = - wlp_off(iprn) * FRTO(1, i0) + nlp_off(iprn) / (1 - NALP(1, i0))
  end do

!! ----------------------------------------- !!
!!                                           !!
!! IV. Log Output and Product Update         !!
!!                                           !!
!! ----------------------------------------- !!

  call date_and_time(values=time_tag)
  call getcwd(line)

  write (outfil, '(a,i5,a)') CPROGNAME//'-', mjd1, '.out'

  outlfn = get_valid_unit(10)
  open (outlfn, file=outfil, status='replace', iostat=ierr)
  if (ierr .ne. 0) then
    write (*, '(2a)') '***ERROR('//CPROGNAME//'): open file ', trim(outfil)
    call exit(1)
  end if

  write (outlfn, '(a)')       '%%% INTEGER-RECOVERED CLOCK DAY-BOUNDARY DISCONTINUITY ANALYSIS FILE'
  write (outlfn, '(a)')       '%%% Executor:                     '//CPROGNAME
  write (outlfn, '(a,i4,5(a1,i0.2))') '%%% Execute Time:                 ', &
    time_tag(1), '-', time_tag(2), '-', time_tag(3), ' ',                   &
    time_tag(5), ':', time_tag(6), ':', time_tag(7)
  write (outlfn, '(a)')       '%%% Working Directory:            '//trim(line)
  write (outlfn, '(a)')       '%%% Input:                        '//trim(cfgfil)
  write (outlfn, '(2a,1x,a)') '%%% SP3 Files:                    ', trim(sp3fil(1)), trim(sp3fil(2))
  write (outlfn, '(2a,1x,a)') '%%% CLK Files:                    ', trim(clkfil(1)), trim(clkfil(2))
  write (outlfn, '(2a,1x,a)') '%%% OSB Files:                    ', trim(biafil(1)), trim(biafil(2))

  ic = 0

  write (outlfn, '(a)') ''
  write (outlfn, '(a)') '1. RESULTS OF RADIAL ORBIT CORRECTION AND CLOCK'
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+------------------'
  write (outlfn, '(a)') ' PRN FRQ | A MJDAY |   RADORB    CLOCK |   RADORB    CLOCK |  CLK_RMS CLK_CORR'
  write (outlfn, '(a)') '         |         |     (mm)     (mm) |     (ps)     (ps) |     (ps)     (ps)'
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+------------------'
  do iprn = 1, nprn
    key = ''
    if (.not. avlprn(0, iprn, 0)) then
      key = '*'
      if (abs(clk_dbd(iprn)) .le. 1.d-12) cycle
    end if
    i0 = index(GNSS_PRIO, prnlst(iprn)(1:1))
    write (outlfn, '(a4,i4,2(1x,a1),i6,3(1x,a1,2i9))') &
      prnlst(iprn), ic, '|', key, mjd1,                &
      '|', nint(VLIGHT * 1E3  * orb_dbd(iprn)), &
           nint(VLIGHT * 1E3  * clk_dbd(iprn)), &
      '|', nint(         1E12 * orb_dbd(iprn)), &
           nint(         1E12 * clk_dbd(iprn)), &
      '|', nint(         1E12 * clk_rms(iprn)), &
           nint(         1E12 * clk_off(iprn))
  end do
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+------------------'

  write (outlfn, '(a)') ''
  write (outlfn, '(a)') '2. RESULTS OF DUAL-FREQUENCY GEOMETRY-FREE BIAS ALIGNMENT'
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+----------+------------------'
  write (outlfn, '(a)') ' PRN FRQ | A MJDAY |   PH_GFB   CD_GFB |  CD_CORR  CD_RESI |   WL_UPD |  WL_CORR  WL_RESI'
  write (outlfn, '(a)') '         |         |     (ps)     (ps) |     (ps)     (ps) |    (mcy) |    (mcy)    (mcy)'
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+----------+------------------'
  do iprn = 1, nprn
    key = ''
    if (.not. avlprn(0, iprn, 0)) then
      cycle
    end if
    i0 = index(GNSS_PRIO, prnlst(iprn)(1:1))
    write (outlfn, '(a4,i4,2(1x,a1),i6,2(1x,a1,2i9),(1x,a1,i9),(1x,a1,2i9))') &
      prnlst(iprn), ic, '|', key, mjd1,                                       &
      '|', nint(                     1E12 * gfb_dbd(iprn)),                   &
           nint(                     1E12 * dcb_dbd(iprn)),                   &
      '|', nint(                     1E12 * dcb_off(iprn)),                   &
           nint(                     1E12 * (dcb_dbd(iprn) + dcb_off(iprn))), &
      '|', nint(VLIGHT/WLAM(1, i0) * 1E3  * wlp_dbd(iprn)),                   &
      '|', nint(VLIGHT/WLAM(1, i0) * 1E3  * wlp_off(iprn)),                   &
           nint(VLIGHT/WLAM(1, i0) * 1E3  * (wlp_dbd(iprn) + wlp_off(iprn)))
  end do
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+----------+------------------'

  write (outlfn, '(a)') ''
  write (outlfn, '(a)') '3. RESULTS OF DUAL-FREQUENCY IRC ALIGNMENT'
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+-------------------+------------------'
  write (outlfn, '(a)') ' PRN FRQ | A MJDAY |   NL_UPD      IRC |  NL_CORR IRC_RESI |   NL_UPD      IRC |  NL_CORR IRC_RESI'
  write (outlfn, '(a)') '         |         |     (ps)     (ps) |     (ps)     (ps) |    (mcy)    (mcy) |    (mcy)    (mcy)'
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+-------------------+------------------'
  do iprn = 1, nprn
    key = ''
    if (.not. avlprn(0, iprn, 0)) then
      cycle
    end if
    i0 = index(GNSS_PRIO, prnlst(iprn)(1:1))
    write (outlfn, '(a4,i4,2(1x,a1),i6,4(1x,a1,2i9))') &
      prnlst(iprn), ic, '|', key, mjd1,                &
      '|', nint(                     1E12 * nlp_dbd(iprn)),                   & 
           nint(                     1E12 * irc_dbd(iprn)),                   &
      '|', nint(                     1E12 * nlp_off(iprn)),                   &
           nint(                     1E12 * (irc_dbd(iprn) - nlp_off(iprn))), &
      '|', nint(VLIGHT/NLAM(1, i0) * 1E3  * nlp_dbd(iprn)),                   &
           nint(VLIGHT/NLAM(1, i0) * 1E3  * irc_dbd(iprn)),                   &
      '|', nint(VLIGHT/NLAM(1, i0) * 1E3  * nlp_off(iprn)),                   &
           nint(VLIGHT/NLAM(1, i0) * 1E3  * (irc_dbd(iprn) - nlp_off(iprn)))
  end do
  write (outlfn, '(a)') '---------+---------+-------------------+-------------------+-------------------+------------------'

  write (outlfn, '(a)') ''
  write (outlfn, '(a)') '4. CORRECTIONS FOR CODE/PHASE BIASES'
  write (outlfn, '(a)') '---------+---------+-------------------'
  write (outlfn, '(a)') ' PRN FRQ | A MJDAY | OCB_CORR OPB_CORR '
  write (outlfn, '(a)') '         |         |     (ps)     (ps) '
  write (outlfn, '(a)') '---------+---------+-------------------'
  do ic = 0, MAXCMB
    k = ic
    if (k .le. 1) k = 1
    do iprn = 1, nprn
      key = ''
      if (.not. avlprn(k, iprn, 0)) then
        cycle
      end if
      i0 = index(GNSS_PRIO, prnlst(iprn)(1:1))
      if (ic .ge. 1) then
        j = IDXFRQ_MUL(k, i0, 2)
        if (ic .ge. 2) then
          if (all(IDXFRQ_MUL(ic, i0, :) .eq. IDXFRQ_MUL(ic - 1, i0, :))) cycle
        end if
      else
        j = IDXFRQ_MUL(k, i0, 1)
      end if
      write (outlfn, '(a4,i4,2(1x,a1),i6,4(1x,a1,2i9))') &
        prnlst(iprn), j, '|', key, mjd1,                 &
        '|', nint(1E12 * ocb_off(ic, iprn)), & 
             nint(1E12 * opb_off(ic, iprn))
    end do
  end do
  write (outlfn, '(a)') '---------+---------+-------------------'
!
!! output orbit, clock & bias
  if (l_extorb) then
    call exporb(trim(prddir)//trim(sp3fil(1)), orb_ext_nprn, orb_ext_prn, &
                orb_jd1, orb_sod1, xyz_orb_ext, nprn, prnlst, clk_extp, l_extclk)
  end if

  if (any(clk_off .ne. 0.d0) .or. any(l_extclk .and. avlprn(0, :, 0))) then
    if (l_backward) then
      call expclk(trim(prddir)//trim(clkfil(1)), nprn, prnlst, avlprn(0, :, 0), -clk_off, &
                  mjd1, 0.d0, l_extclk, clk_extp, .true.)
    else
      call expclk(trim(prddir)//trim(clkfil(2)), nprn, prnlst, avlprn(0, :, 0),  clk_off, &
                  mjd1, 0.d0, l_extclk, clk_extp, .true.)
      if (any(l_extclk .and. avlprn(0, :, 0))) then
        tmp_off = 0.d0
        call expclk(trim(prddir)//trim(clkfil(1)), nprn, prnlst, avlprn(0, :, 0), tmp_off, &
                    mjd1, 0.d0, l_extclk, clk_extp, .false.)
      end if
    end if
  end if

  do ic = 0, MAXCMB
    ocb_dbd(ic, :) = ocb_dbd(ic, :) - ((clk_dbd + clk_off) - orb_dbd)
    opb_dbd(ic, :) = opb_dbd(ic, :) - ((clk_dbd + clk_off) - orb_dbd)
    ! remove GF datum in docb
    if (l_rmv_gf) then
      do iprn = 1, nprn
        call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
        if (ic .ge. 1) then
          ocb_dbd(ic, iprn) = ocb_dbd(ic, iprn) + FRTO(ic, i0)**2/(1 - FRTO(1, i0)**2) * gfb_dbd(iprn)
          opb_dbd(ic, iprn) = opb_dbd(ic, iprn) - FRTO(ic, i0)**2/(1 - FRTO(1, i0)**2) * gfb_dbd(iprn)
        else
          ocb_dbd(ic, iprn) = ocb_dbd(ic, iprn) + 1/(1 - FRTO(1, i0)**2) * gfb_dbd(iprn)
          opb_dbd(ic, iprn) = opb_dbd(ic, iprn) - 1/(1 - FRTO(1, i0)**2) * gfb_dbd(iprn)
        end if
      end do
    end if
  end do

  do iprn = 1, nprn
    call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
    do ic = 0, MAXCMB
      do it = 1, MAXTYP/4
        if (OBS_PRIO_SYS(i0)(it:it) .eq. '' .or. abs(ocb_itf_dbd(ic, iprn, it)) .ge.  1.d9/VLIGHT) cycle
        ocb_itf_dbd(ic, iprn, it) = ocb_itf_dbd(ic, iprn, it) - ((clk_dbd(iprn) + clk_off(iprn)) - orb_dbd(iprn))
        ! remove GF datum in docb
        if (l_rmv_gf) then
          if (ic .ge. 1) then
            ocb_itf_dbd(ic, iprn, it) = ocb_itf_dbd(ic, iprn, it) + FRTO(ic, i0)**2/(1 - FRTO(1, i0)**2) * gfb_dbd(iprn)
          else
            ocb_itf_dbd(ic, iprn, it) = ocb_itf_dbd(ic, iprn, it) + 1/(1 - FRTO(1, i0)**2) * gfb_dbd(iprn)
          end if
        end if
      end do
    end do
  end do

  if (any(opb_off .ne. 0.d0)) then
    if (l_backward) then
      l_wrt_docb = .false.
      call expbia(trim(prddir)//trim(biafil(1)), nprn, prnlst, avlprn(:, :, :), clk_rms, &
                  ocb_dbd, -ocb_off, opb_dbd, -opb_off, ocb_itf_dbd, MAXCMB, IDXFRQ_MUL, l_wrt_docb)
    else
      call expbia(trim(prddir)//trim(biafil(2)), nprn, prnlst, avlprn(:, :, :), clk_rms, &
                  ocb_dbd,  ocb_off, opb_dbd,  opb_off, ocb_itf_dbd, MAXCMB, IDXFRQ_MUL, l_wrt_docb)
    end if
  end if

contains

  subroutine config_error(action)
    character(len=*), intent(in) :: action

    write (*, '(a,2(1x,a))') '***ERROR('//CPROGNAME//'): '//action//' option', trim(msg), trim(key)
    call exit(1)
  end subroutine config_error

end program algirc