!
!! orbit.h
!!
!!    Copyright (C) 2023 by Wuhan University
!!
!!    This program belongs to PRIDE PPP-AR which is an open source software:
!!    you can redistribute it and/or modify it under the terms of the GNU
!!    General Public License (version 3) as published by the Free Software Foundation.
!!
!!    This program is distributed in the hope that it will be useful,
!!    but WITHOUT ANY WARRANTY; without even the implied warranty of
!!    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
!!    GNU General Public License (version 3) for more details.
!!
!!    You should have received a copy of the GNU General Public License
!!    along with this program. If not, see <https://www.gnu.org/licenses/>.
!!
!!    Binary orbit header
!
type orbhdr
!
!! satelilte 
  character*10 :: sattyp = ''   ! satellite type  
  integer*4 nprn                ! # of satellites
  character*3 prn(MAXSAT)       ! satellite PRN
!
!! system tag
  character*80 :: iers = ''     ! IERS Conventions
!
!! time tag
  integer*4 jd0,jd1             !
  real*8 sod0,sod1              ! start & end time
!
!! sp3 interval (second)
  real*8 dintv
end type
!
!! orbit block
!
type sp3block
    integer*4 jd
    real*8    sod
    real*8    x(6,MAXSAT)  ! x, y, z, vx, vy, vz
    logical*1 flag(MAXSAT) ! lost sat : false ; have sat :true; 
end type

