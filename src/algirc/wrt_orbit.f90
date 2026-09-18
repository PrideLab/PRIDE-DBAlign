!
!! wrt_orbit.f90
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
!! Predicted orbit output.
module wrt_orbit
  use cp_file, only: copy_file_exact
  implicit none
  private
  public :: exporb
  include '../header/const.h'

contains

  subroutine exporb(orbfil, orb_nprn, orb_prnlst, ext_mjd, ext_sod, xyz, &
                    nprn, prnlst, clk_extp, l_extclk)
    implicit none
  !
  !! argument
    character(*)  orbfil
    integer*4, intent(in) :: nprn
    character*3, intent(in) :: prnlst(MAXSAT)
    real*8, intent(in) :: clk_extp(MAXSAT)
    logical*1, intent(in) :: l_extclk(MAXSAT)
    integer*4 :: get_valid_unit, pointer_string
    integer*4     orb_nprn, ext_mjd
    character*3   orb_prnlst(MAXSAT)
    real*8        ext_sod, xyz(6, MAXSAT)
  !
  !! local variable
    integer*4     oldlfn, newlfn, ierr_orb, iorb, iclk
    integer*4     year, doy, month, day, hour, minute
    integer*4     nbyte, ipos
    integer*8     file_size, scan_pos, scan_end, eof_pos
    real*8        second, sp3_clk
    character*1   clk_prediction_flag
    character*256 filnam
    character*1024 tail
  !
    filnam = trim(orbfil)//'_predicted'
    inquire (file=orbfil, size=file_size, iostat=ierr_orb)
    if (ierr_orb .ne. 0 .or. file_size .le. 0) call open_error()

    oldlfn = get_valid_unit(20)
    open (oldlfn, file=orbfil, status='old', access='stream', form='unformatted', &
          action='read', iostat=ierr_orb)
    if (ierr_orb .ne. 0) call open_error()

    eof_pos = 0_8
    scan_end = file_size
    do while (scan_end .gt. 0_8 .and. eof_pos .eq. 0_8)
      nbyte = int(min(int(len(tail), kind=8), scan_end))
      scan_pos = scan_end - int(nbyte, kind=8) + 1_8
      read (oldlfn, pos=scan_pos, iostat=ierr_orb) tail(1:nbyte)
      if (ierr_orb .ne. 0) exit
      ipos = index(tail(1:nbyte), 'EOF', back=.true.)
      if (ipos .gt. 0) then
        eof_pos = scan_pos + int(ipos, kind=8) - 1_8
      else if (scan_pos .eq. 1_8) then
        exit
      else
        ! Retain a two-byte overlap so an EOF token split across chunks is found.
        scan_end = scan_pos + 1_8
      end if
    end do
    close (oldlfn)
    if (ierr_orb .ne. 0) call read_error()
    if (eof_pos .eq. 0_8) call missing_eof_error()

    call copy_file_exact(trim(orbfil), trim(filnam), ierr_orb, eof_pos - 1_8)
    if (ierr_orb .ne. 0) call open_error()
    newlfn = get_valid_unit(20)
    open (newlfn, file=filnam, status='old', position='append', action='write', iostat=ierr_orb)
    if (ierr_orb .ne. 0) call open_error()

    call mjd2doy(ext_mjd, year, doy)
    call yeardoy2monthday(year, doy, month, day)
    hour = int(ext_sod/3600.d0)
    minute = int((ext_sod - dble(hour)*3600.d0)/60.d0)
    second = ext_sod - dble(hour)*3600.d0 - dble(minute)*60.d0
    write (newlfn, '(a3,i4,4i3,f12.8)') '*  ', year, month, day, hour, minute, second
    do iorb = 1, orb_nprn
      if (all(abs(xyz(1:3, iorb)) .le. 1.d-12) .or. any(abs(xyz(1:3, iorb)) .gt. 1.d9)) cycle
      sp3_clk = 999999.999999d0
      clk_prediction_flag = ' '
      iclk = pointer_string(nprn, prnlst, orb_prnlst(iorb))
      if (iclk .gt. 0) then
        if (abs(clk_extp(iclk)) .gt. 1.d-12) then
          sp3_clk = clk_extp(iclk)*1.d6
          if (l_extclk(iclk)) clk_prediction_flag = 'P'
        end if
      end if
      ! SP3 prediction flags: clock in column 76, orbit in column 80.
      write (newlfn, '(a1,a3,4f14.6,15x,a1,3x,a1)') &
        'P', orb_prnlst(iorb), xyz(1:3, iorb), sp3_clk, clk_prediction_flag, 'P'
    end do
    write (newlfn, '(a)') 'EOF'

    close (newlfn)

  contains

    subroutine open_error()
      write (*, '(2a)') '***ERROR(exporb): open file ', trim(filnam)
      call exit(1)
    end subroutine open_error

    subroutine read_error()
      write (*, '(2a)') '***ERROR(exporb): read file ', trim(orbfil)
      call exit(1)
    end subroutine read_error

    subroutine missing_eof_error()
      write (*, '(2a)') '***ERROR(exporb): EOF marker not found in file ', trim(orbfil)
      call exit(1)
    end subroutine missing_eof_error

  end subroutine

end module wrt_orbit
