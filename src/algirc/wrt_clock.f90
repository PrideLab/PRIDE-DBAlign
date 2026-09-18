!
!! wrt_clock.f90
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
!! Clock reading, extrapolation and output.
module wrt_clock
  use, intrinsic :: iso_fortran_env, only: iostat_end
  use cp_file, only: copy_file_exact
  implicit none
  private
  public :: rdclkh, lsq_fit, expclk
  include '../header/const.h'

contains

  subroutine rdclkh(clkfil, mjd, sod, intv, period)
    implicit none
  !
  !! argument
    character(*)  clkfil
    integer*4     mjd
    real*8        sod, intv, period
  !
  !! local variable
    integer*4     clklfn, ierr
    integer*4     mjd_tmp, year, month, day, hour, minute
    real*8        sod_tmp, second
    character*256 line
  !
  !! function used
    integer*4     get_valid_unit
    integer*4     modified_julday

    clklfn = get_valid_unit(12)
    open (clklfn, file=clkfil, iostat=ierr)
    if (ierr .ne. 0) then
      write (*, '(2a)') '***ERROR(rdclkh): open file ', trim(clkfil)
      call exit(1)
    endif

    mjd = 0
    sod = 0
    mjd_tmp = 0
    sod_tmp = 0
    intv = 0.d0
    do while(.true.)
      read (clklfn, '(a)', iostat=ierr) line
      if (ierr .eq. iostat_end) exit
      if (ierr .ne. 0) call read_error()
      if ('AS ' .eq. line(1:3)) then
        read (line(9:34), *) year, month, day, hour, minute, second
        mjd_tmp = modified_julday(day, month, year)
        sod_tmp = hour*3600 + minute*60 + second
        if (mjd .eq. 0) then
          mjd = mjd_tmp
          sod = sod_tmp
          continue
        end if
        sod_tmp = sod_tmp + (mjd_tmp - mjd)*86400
        if (intv .le. 0.d0) intv = sod_tmp - sod
      end if
    end do

    period = sod_tmp - sod
    close (clklfn)

  contains

    subroutine read_error()
      write (*, '(a,a/a)') '***ERROR(rdclkh): read file ', trim(clkfil), trim(line)
      call exit(1)
    end subroutine read_error

  end subroutine

  subroutine lsq_fit(length, array, extrapolation_steps, rms, extp)
    implicit none
    integer :: length
    real(8) :: array(length)
    real(8) :: extrapolation_steps, rms, extp
    real(8) :: slope, intercept
    real(8) :: sum_x, sum_y, sum_xy, sum_xx
    integer :: i

    sum_x = 0.d0
    sum_y = 0.d0
    sum_xy = 0.d0
    sum_xx = 0.d0

    do i = 1, length
      sum_x = sum_x + i
      sum_y = sum_y + array(i)
      sum_xy = sum_xy + i * array(i)
      sum_xx = sum_xx + i**2
    end do

    slope = (length * sum_xy - sum_x * sum_y) / (length * sum_xx - sum_x**2)
    intercept = (sum_y - slope * sum_x) / length

    rms = 0.0
    do i = 1, length
      rms = rms + (array(i) - slope * i - intercept)**2
    end do
    rms = sqrt(rms / length)

    extp = slope * (dble(length) + extrapolation_steps) + intercept
  end subroutine lsq_fit

  subroutine expclk(clkfil, nprn, prnlst, avlprn, clk_off, ext_mjd, ext_sod, &
                    l_extclk, clk_extp, l_apply_offset)
    implicit none
  !
  !! argument
    character(*)  clkfil
    integer*4     nprn
    integer*4     ext_mjd
    character*3   prnlst(MAXSAT)
    logical*1     avlprn(MAXSAT)
    logical*1     l_extclk(MAXSAT)
    logical       l_apply_offset
    real*8        clk_off(MAXSAT)
    real*8        ext_sod
    real*8        clk_extp(MAXSAT)
  !
  !! local variable
    integer*4     oldlfn, newlfn, ierr, ipt
    integer*4     iprn
    character*256 filnam, line, clk_template(MAXSAT)
    logical*1     l_extpresent(MAXSAT), l_clktpl(MAXSAT)
    real*8        val
  !
  !! function used
    integer*4     pointer_string
    integer*4     get_valid_unit

  ! Target-day epochs are never synthesized; only the reference-day copy is extended.
    l_extpresent = .true.
    if (.not. l_apply_offset) l_extpresent = .false.
    l_clktpl = .false.
    clk_template = ''

    filnam = trim(clkfil)
    inquire(file=filnam, number=oldlfn)
    if (oldlfn .eq. -1) then
      oldlfn = get_valid_unit(10)
      open (oldlfn, file=filnam, iostat=ierr)
      if (ierr .ne. 0) call open_error()
    else
      rewind (oldlfn)
    end if

    do while(.true.)
      read (oldlfn, '(a)', iostat=ierr) line
      if (ierr .eq. iostat_end) exit
      if (ierr .ne. 0) call read_error()
      if ('AS ' .ne. line(1:3)) cycle
      iprn = pointer_string(nprn, prnlst, line(4:6))
      if (iprn .le. 0) cycle
      clk_template(iprn) = line
      l_clktpl(iprn) = .true.
    end do
    rewind (oldlfn)

    filnam = trim(clkfil)//'_aligned'
    if (.not. l_apply_offset) then
      filnam = trim(clkfil)//'_predicted'
      close (oldlfn)
      call copy_file_exact(trim(clkfil), trim(filnam), ierr)
      if (ierr .ne. 0) call open_error()
      newlfn = get_valid_unit(20)
      open (newlfn, file=filnam, status='old', position='append', action='write', iostat=ierr)
      if (ierr .ne. 0) call open_error()
      call write_extclk(newlfn, nprn, prnlst, avlprn, clk_off, ext_mjd, ext_sod, &
                        l_extclk, clk_extp, l_extpresent, l_clktpl, clk_template)
      close (newlfn)
      return
    end if

    newlfn = get_valid_unit(20)
    open (newlfn, file=filnam, status='replace', action='write', iostat=ierr)
    if (ierr .ne. 0) call open_error()

    do while(.true.)
      read (oldlfn, '(a)', iostat=ierr) line
      if (ierr .eq. iostat_end) exit
      if (ierr .ne. 0) call read_error()
      if ('AS ' .eq. line(1:3)) then
        iprn = pointer_string(nprn, prnlst, line(4:6))
        if (iprn .gt. 0) then
          ipt = 40
          if (len_trim(line(9:12)) .eq. 0) ipt = ipt + 5
          read (line(ipt:ipt+19), *, iostat=ierr) val
          if (ierr .gt. 0) call read_error()
          ! Preserve the original runtime termination on an incomplete internal record.
          if (ierr .lt. 0) read (line(ipt:ipt+19), *) val
          val = val + clk_off(iprn)
          write (newlfn, '(a,e19.12,a)') line(1:ipt), val, trim(line(ipt+20:))
          cycle
        end if
      end if
      write (newlfn, '(a)') trim(line)
    end do

    close (oldlfn)
    close (newlfn)

  contains

    subroutine open_error()
      write (*, '(2a)') '***ERROR(expclk): open file ', trim(filnam)
      call exit(1)
    end subroutine open_error

    subroutine read_error()
      write (*, '(a,a/a)') '***ERROR(expclk): read file ', trim(clkfil), trim(line)
      call exit(1)
    end subroutine read_error

  end subroutine

  subroutine write_extclk(newlfn, nprn, prnlst, avlprn, clk_off, ext_mjd, ext_sod, &
                          l_extclk, clk_extp, l_extpresent, l_clktpl, clk_template)
    implicit none
  !
  !! argument
    integer*4     newlfn
    integer*4     nprn
    integer*4     ext_mjd
    character*3   prnlst(MAXSAT)
    logical*1     avlprn(MAXSAT)
    logical*1     l_extclk(MAXSAT)
    logical*1     l_extpresent(MAXSAT)
    logical*1     l_clktpl(MAXSAT)
    character*256 clk_template(MAXSAT)
    real*8        clk_off(MAXSAT)
    real*8        ext_sod
    real*8        clk_extp(MAXSAT)
  !
  !! local variable
    integer*4     iprn, year, doy, month, day, hour, minute, ipt, nval, ierr
    character*256 line
    logical*1     l_template
    real*8        second, val
    real*8, parameter :: PREDICTED_CLOCK_STDDEV = 9.999d99

    call mjd2doy(ext_mjd, year, doy)
    call yeardoy2monthday(year, doy, month, day)
    hour = int(ext_sod/3600.d0)
    minute = int((ext_sod - hour*3600.d0)/60.d0)
    second = ext_sod - hour*3600.d0 - minute*60.d0

    do iprn = 1, nprn
      if (.not. avlprn(iprn)) cycle
      if (.not. l_extclk(iprn)) cycle
      if (l_extpresent(iprn)) cycle
      val = clk_extp(iprn) + clk_off(iprn)

      l_template = l_clktpl(iprn)
      if (l_template) then
        line = clk_template(iprn)
        line(4:6) = prnlst(iprn)
        if (len_trim(line(9:12)) .eq. 0) then
          write (line(14:39), '(i4,4(1x,i2.2),f10.6)') year, month, day, hour, minute, second
          read (line(40:45), *, iostat=ierr) nval
          ipt = 45
        else
          write (line(9:34), '(i4,4(1x,i2.2),f10.6)') year, month, day, hour, minute, second
          read (line(35:40), *, iostat=ierr) nval
          ipt = 40
        end if
        if (ierr .ne. 0 .or. nval .gt. 2) l_template = .false.
      end if

      if (l_template) then
        write (line(ipt-5:ipt), '(2x,i1,3x)') 2
        ! Use ES with an explicit exponent width to retain E+99 in the standard deviation.
        write (newlfn, '(a,e19.12,1x,es19.12e2)') line(1:ipt), val, PREDICTED_CLOCK_STDDEV
      else
        write (newlfn, '(a3,a3,7x,i4,4(1x,i2.2),f10.6,2x,i1,3x,e19.12,1x,es19.12e2)') &
          'AS ', prnlst(iprn), year, month, day, hour, minute, second, 2, val, PREDICTED_CLOCK_STDDEV
      end if
    end do
  end subroutine

end module wrt_clock
