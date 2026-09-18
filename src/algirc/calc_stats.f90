!
!! calc_stats.f90
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
!! Satellite grouping and system averages.
module calc_stats
  implicit none
  private
  public :: AVERAGE, AVEFRAC, prn2idx
  include '../header/const.h'

contains

  function AVERAGE(nprn, l_unify_bd23, prnlst, avlprn, array)
    implicit none
    integer*4, intent(in) :: nprn
    logical*1, intent(in) :: l_unify_bd23
    character*3   prnlst(MAXSAT)
    logical*1     avlprn(MAXSAT)
    real*8        AVERAGE(MAXSYS+1)
    real*8        array(MAXSAT)
    integer*4     nval(MAXSYS+1), iprn, i0, i1

    AVERAGE = 0.d0 
    nval = 0
    do iprn = 1, nprn
      if (.not. avlprn(iprn)) cycle
      call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
      nval(i1) = nval(i1) + 1
      AVERAGE(i1) = 1.d0/nval(i1) * (AVERAGE(i1) * (nval(i1) - 1) + array(iprn))
    end do
  end function

  function AVEFRAC(nprn, l_unify_bd23, prnlst, avlprn, lambda, array)
    implicit none
    integer*4, intent(in) :: nprn
    logical*1, intent(in) :: l_unify_bd23
    character*3   prnlst(MAXSAT)
    logical*1     avlprn(MAXSAT)
    real*8        AVEFRAC(MAXSYS+1)
    real*8        lambda(MAXSYS)
    real*8        array(MAXSAT), var
    integer*4     nval(MAXSYS+1), iprn, i0, i1

    AVEFRAC = 0.d0 
    nval = 0
    do iprn = 1, nprn
      if (.not. avlprn(iprn)) cycle
      call prn2idx(prnlst(iprn), i0, i1, l_unify_bd23)
      nval(i1) = nval(i1) + 1
      var = VLIGHT/lambda(i0) * array(iprn)
      var = lambda(i0)/VLIGHT * (var - nint(var))
      AVEFRAC(i1) = 1.d0/nval(i1) * (AVEFRAC(i1) * (nval(i1) - 1) + var)
    end do
  end function 

  subroutine prn2idx(prn, i0, i1, l_unify_bd23)
    implicit none
    character*3     prn
    integer*4       i0, i1, j
    logical*1, intent(in) :: l_unify_bd23

    i0 = index(GNSS_PRIO, prn(1:1))
    read (prn(2:3), '(i2)') j

    i1 = i0
    if (.not. l_unify_bd23) then
      if (prn(1:1) .eq. 'C' .and. j .le. 16) i1 = MAXSYS + 1
    end if
  end subroutine

end module calc_stats
