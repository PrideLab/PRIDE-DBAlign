!
!! form_combination.f90
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
!! GNSS observation combinations.
module form_combination
  implicit none
  private
  public :: MWCMB, IFCMB

contains

  function MWCMB(WALP, NALP, ic, i0, l1, l2, c1, c2)
    implicit none
    integer*4     ic, i0
    real*8, intent(in) :: WALP(:,:), NALP(:,:)
    real*8        MWCMB, l1, l2, c1, c2
  !
  !! Melbourne-Wübbena combination
    MWCMB = WALP(ic, i0) * l1 + (1 - WALP(ic, i0)) * l2 - NALP(ic, i0) * c1 - (1 - NALP(1, i0)) * c2
  end function

  function IFCMB(IALP, ic, i0, l1, l2)
    implicit none
    integer*4     ic, i0
    real*8, intent(in) :: IALP(:,:)
    real*8        IFCMB, l1, l2
  !
  !! Ionosphere-free combination
    IFCMB = IALP(ic, i0) * l1 + (1 - IALP(ic, i0)) * l2
  end function

end module form_combination
