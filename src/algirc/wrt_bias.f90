!
!! wrt_bias.f90
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
!! Aligned bias and DOCB output.
module wrt_bias
  use, intrinsic :: iso_fortran_env, only: iostat_end
  implicit none
  private
  public :: expbia
  include '../header/const.h'

contains

  subroutine expbia(biafil, nprn, prnlst, avlprn, clk_rms, &
                    ocb_dbd, ocb_off, opb_dbd, opb_off, ocb_itf_dbd, &
                    MAXCMB, IDXFRQ_MUL, l_wrt_docb)
    implicit none
  !
  !! argument
    integer*4, intent(in) :: MAXCMB
    integer*4, intent(in) :: IDXFRQ_MUL(4, MAXSYS, 2)
    logical*1, intent(in) :: l_wrt_docb
    character(*)  biafil
    integer*4     nprn
    character*3   prnlst(MAXSAT)
    logical*1     avlprn(0:MAXCMB, MAXSAT, 0:MAXTYP/4)
    real*8        clk_rms(MAXSAT)
    real*8        ocb_dbd(0:MAXCMB, MAXSAT)
    real*8        ocb_off(0:MAXCMB, MAXSAT)
    real*8        opb_dbd(0:MAXCMB, MAXSAT)
    real*8        opb_off(0:MAXCMB, MAXSAT)
    real*8        ocb_itf_dbd(0:MAXCMB, MAXSAT, MAXTYP/4)
  !
  !! local variable
    integer*4     oldlfn, newlfn, ierr
    integer*4     i0, iprn, ic, ifrq, it, k
    integer*4     year0, doy0
    character*4   svnlst(MAXSAT)
    character*256 filnam, line
    character*16  rcdfmt
    character*21  strbia
    real*8        val, off
  !
  !! function used
    integer*4     get_valid_unit
    integer*4     pointer_string

    filnam = trim(biafil)
    inquire(file=filnam, number=oldlfn)
    if (oldlfn .eq. -1) then
      oldlfn = get_valid_unit(10)
      open (oldlfn, file=filnam, iostat=ierr)
      if (ierr .ne. 0) call open_error()
    else
      rewind (oldlfn)
    end if

    filnam = trim(biafil)//'_aligned'
    newlfn = get_valid_unit(20)
    open (newlfn, file=filnam, iostat=ierr)
    if (ierr .ne. 0) call open_error()

    svnlst = ""

!
!! read SVN list for writing DOCB records
    do while (.true.)
      read (oldlfn, '(a)', iostat=ierr) line
      if (ierr .eq. iostat_end) exit
      if (ierr .ne. 0) call read_error()
      if ('OSB ' .ne. line(2:4)) continue 
      if ('' .ne. line(16:19)) continue 
      iprn = pointer_string(nprn, prnlst, line(12:14))
      if (iprn .gt. 0) svnlst(iprn) = line(7:10)
    end do

    rewind (oldlfn)

    do while (.true.)
      read (oldlfn, '(a)', iostat=ierr) line
      if (ierr .eq. iostat_end) exit
      if (ierr .ne. 0) call read_error()
      adjust_bias_record: do
        if ('OSB ' .ne. line(2:4)) exit adjust_bias_record
        if ('' .ne. line(16:19)) exit adjust_bias_record
        iprn = pointer_string(nprn, prnlst, line(12:14))
        if (iprn .le. 0) exit adjust_bias_record
        i0 = index(GNSS_PRIO, prnlst(iprn)(1:1))
        read (line(27:27), *, iostat=ierr) ifrq
        if (ierr .gt. 0) call read_error()
        ! Preserve the original runtime termination on an incomplete internal record.
        if (ierr .lt. 0) read (line(27:27), *) ifrq
        read (line(71:91), *, iostat=ierr) val
        if (ierr .gt. 0) call read_error()
        ! Preserve the original runtime termination on an incomplete internal record.
        if (ierr .lt. 0) read (line(71:91), *) val
        svnlst(iprn) = line(7:10)
        if (line(26:26) .eq. 'L') then
          if (ifrq .eq. IDXFRQ_MUL(1, i0, 1)) then
            off = opb_off(0, iprn)
          else if (ifrq .eq. IDXFRQ_MUL(1, i0, 2)) then
            off = opb_off(1, iprn)
          else
            off = 0.d0
            do ic = 1, MAXCMB
              if (ifrq .eq. IDXFRQ_MUL(1,  i0, 1) .or. ifrq .eq. IDXFRQ_MUL(1,  i0, 2)) cycle
              if (ifrq .ne. IDXFRQ_MUL(ic, i0, 2)) cycle
              off = opb_off(ic, iprn)
              exit
            end do
            if (off .eq. 0.d0) exit adjust_bias_record
          end if
        else if (line(26:26) .eq. 'C') then
          off = 0.d0
          exit adjust_bias_record
        else
          exit adjust_bias_record
        end if
        k = index(line(71:91), '.')
        select case (k)
        case (2)
          rcdfmt = '(E21.15)'       !< WHU record format
        case (3)
          rcdfmt = '(1P E21.14)'    !< WHU record format
        case (16)
          rcdfmt = '(F21.5)'        !< COD record format (phase bias)
        case (17)
          rcdfmt = '(F21.4)'        !< COD record format (code bias)
        case (18)
          rcdfmt = '(F21.3)'        !< GRG record format
        case default
          rcdfmt = '(E21.15)'
        end select
        write (strbia, rcdfmt) val + off * 1E9
        line(71:91) = strbia(1:21)
        exit adjust_bias_record
      end do adjust_bias_record
      write (newlfn, '(a)') trim(line)
      if (line(1:5)  .eq. "%=BIA") then
        read (line, '(49x,i4,1x,i3)') year0, doy0 
      else if (line(1:17) .eq. "-BIAS/DESCRIPTION") then
        if (l_wrt_docb) then
          write (newlfn, '(a)') "*-------------------------------------------------------------------------------" 
          write (newlfn, '(a)') "+SOLUTION/DAY_BOUNDARY_DISCONTINUITY"
          write (newlfn, '(a)') "*DBD  SVN_ PRN STATION__ OBS1 OBS2 MIDNIGHT_AT___ UNIT"//&
                                " __ESTIMATED_VALUE____ _STD_DEV___"
          do iprn = 1, nprn
            if (svnlst(iprn) .eq. "") cycle
            i0 = index(GNSS_PRIO, prnlst(iprn)(1:1))
            do ifrq = 0, 1
              do it = 1, MAXTYP/4
                if (.not. avlprn(ifrq, iprn, it)) cycle
                if (OBS_PRIO_SYS(i0)(it:it) .eq. '' .or. abs(ocb_itf_dbd(ifrq, iprn, it)) .ge. 1.d9/VLIGHT) cycle
                write (newlfn, '(1x,a4,1x,a4,1x,a3,11x,a1,i1,a1,7x,i0.4,a1,i0.3,a1,i0.5,1x,a2,3x,f21.5,1x,f11.5)') &
                  "DOCB", svnlst(iprn), prnlst(iprn), "C", IDXFRQ_MUL(1, i0, ifrq+1), OBS_PRIO_SYS(i0)(it:it), &
                          year0, ':', doy0, ':', 0, "ns", &
                         (ocb_itf_dbd(ifrq, iprn, it))*1E9, clk_rms(iprn)*1E9
              end do
            end do
            do ic = 2, MAXCMB 
              do it = 1, MAXTYP/4
                if (.not. avlprn(ic, iprn, it)) cycle
                if (OBS_PRIO_SYS(i0)(it:it) .eq. '' .or. abs(ocb_itf_dbd(ic, iprn, it)) .ge. 1.d9/VLIGHT) cycle
                write (newlfn, '(1x,a4,1x,a4,1x,a3,11x,a1,i1,a1,7x,i0.4,a1,i0.3,a1,i0.5,1x,a2,3x,f21.5,1x,f11.5)') &
                  "DOCB", svnlst(iprn), prnlst(iprn), "C", IDXFRQ_MUL(ic, i0, 2), OBS_PRIO_SYS(i0)(it:it), &
                          year0, ':', doy0, ':', 0, "ns", &
                         (ocb_itf_dbd(ic, iprn, it))*1E9, clk_rms(iprn)*1E9
              end do
            end do
            do ifrq = 0, 1
              if (.not. avlprn(ifrq, iprn, 0)) cycle
              do it = 1, MAXTYP/4
                if (OBS_PRIO_SYS(i0)(it:it) .eq. '' .or. abs(ocb_itf_dbd(ifrq, iprn, it)) .ge. 1.d9/VLIGHT) cycle
                write (newlfn, '(1x,a4,1x,a4,1x,a3,11x,a1,i1,a1,7x,i0.4,a1,i0.3,a1,i0.5,1x,a2,3x,f21.5,1x,f11.5)') &
                  "DOCB", svnlst(iprn), prnlst(iprn), "L", IDXFRQ_MUL(1, i0, ifrq+1), OBS_PRIO_SYS(i0)(it:it), &
                          year0, ':', doy0, ':', 0, "ns", &
                         (opb_dbd(ifrq, iprn) + opb_off(ifrq, iprn))*1E9, clk_rms(iprn)*1E9
              end do
            end do
            do ic = 2, MAXCMB 
              if (.not. avlprn(ic, iprn, 0)) cycle
              do it = 1, MAXTYP/4
                if (OBS_PRIO_SYS(i0)(it:it) .eq. '' .or. abs(ocb_itf_dbd(ic, iprn, it)) .ge. 1.d9/VLIGHT) cycle
                write (newlfn, '(1x,a4,1x,a4,1x,a3,11x,a1,i1,a1,7x,i0.4,a1,i0.3,a1,i0.5,1x,a2,3x,f21.5,1x,f11.5)') &
                  "DOCB", svnlst(iprn), prnlst(iprn), "L", IDXFRQ_MUL(ic, i0, 2), OBS_PRIO_SYS(i0)(it:it), &
                          year0, ':', doy0, ':', 0, "ns", &
                         (opb_dbd(ic, iprn) + opb_off(ic, iprn))*1E9, clk_rms(iprn)*1E9
              end do
            end do
          end do
          write (newlfn, '(a)') "-SOLUTION/DAY_BOUNDARY_DISCONTINUITY"
        end if
      end if
   end do

    close (oldlfn)
    close (newlfn)

  contains

    subroutine open_error()
      write (*, '(2a)') '***ERROR(expbia): open file ', trim(filnam)
      call exit(1)
    end subroutine open_error

    subroutine read_error()
      write (*, '(a,a/a)') '***ERROR(expbia): read file ', trim(biafil), trim(line)
      call exit(1)
    end subroutine read_error

  end subroutine

end module wrt_bias
