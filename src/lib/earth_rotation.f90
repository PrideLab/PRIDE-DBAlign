!
!! earth_rotation.f90
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
!! Contributor: Ran Zeng
!! 
!!
!!
subroutine getghar(jd, sod, ghar)
  implicit none
  include "../header/const.h"
  real*8 sod, ghar, D2R, tsecgps, tsecutc, fmjdutc, d, ghad, taiutc
  integer*4 i, jd
  
  D2R=PI/180.d0
  !/* need UT to get sidereal time */
  tsecgps = sod  !/* GPS time (sec of day)           */
  tsecutc = sod + 19.d0 - taiutc(jd)  !/* UTC time (sec of day)           */
  fmjdutc = tsecutc / 86400.0  !/* UTC time (fract. day)           */
  d = (jd - 51544) + (fmjdutc - 0.50)  !/* days since J2000                */
  ghad = 280.46061837504 + 360.9856473662862 * d  !/* corrn.   (+digits)         */
  i = int((ghad / 360.0))
  ghar = (ghad - i * 360.0) * D2R
  
  do while(ghar >= 2 * PI)
    ghar = ghar - 2 * PI
  enddo
  do while(ghar < 0.0)
    ghar = ghar + 2 * PI;
  enddo
end

subroutine rot3(theta, x, y, z, u, v, w)
  implicit none
  real*8 theta, x, y, z, u, v, w, s, c
  
  s = dsin(theta)
  c = dcos(theta)
  u = c * x + s * y
  v = c * y - s * x
  w = z
end
