!
!! trig_poly_extrap.f90
!!
!!    Copyright (C) 2023 by SKLPG, CAS
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
!! Contributor: Jianghui Geng, Yangyang Wang
!! 
!!
!! purpose  : extrapolate an inertial-frame orbit with a trigonometric
!!            polynomial
!!
!! parameter: npoint          -- number of orbit epochs used for fitting
!!            nharmonic       -- number of trigonometric harmonics
!!            history         -- inertial positions (km)
!!            sample_interval -- interval of the history epochs (s)
!!            extrap_interval -- interval from the last epoch to prediction (s)
!!            extrapolated    -- extrapolated inertial position (km)
!!            ierr            -- status, zero on success
!!
!
  subroutine trig_poly_extrapolate(npoint, nharmonic, history, sample_interval, &
                                   extrap_interval, extrapolated, ierr)
  implicit none

  integer*4 npoint, nharmonic
  real*8 history(3,npoint)
  real*8 sample_interval, extrap_interval
  real*8 extrapolated(3)
  integer*4 ierr

  integer*4 i,j,k,icoor,ipivot,nterm
  integer*4 permutation(2*nharmonic+1)
  real*8, parameter :: PI = 3.1415926535897932384626433832795d0
  real*8 period,omega,time,alpha,beta,column_norm,pivot_norm,factor
  real*8 design(npoint,2*nharmonic+1)
  real*8 rhs(npoint,3)
  real*8 householder(npoint)
  real*8 target_basis(2*nharmonic+1)
  real*8 solution(2*nharmonic+1,3)
  real*8 coefficients(2*nharmonic+1,3)
  real*8 temporary_column(npoint)

  ierr = 0
  extrapolated = 0.d0
  nterm = 2*nharmonic + 1

  if (nharmonic .lt. 1 .or. npoint .lt. max(7,nterm)) then
    ierr = 1
    return
  endif
  if (sample_interval .le. 0.d0 .or. extrap_interval .lt. 0.d0) then
    ierr = 2
    return
  endif
  do i = 1, npoint
    if (all(abs(history(:,i)) .le. 1.d-12) .or. &
        any(abs(history(:,i)) .gt. 1.d9)) then
      ierr = 3
      return
    endif
  enddo

  call estimate_orbit_period(history,npoint,sample_interval,period,ierr)
  if (ierr .ne. 0) return
  omega = 2.d0*PI/period

  do i = 1, npoint
    time = dble(i-npoint)*sample_interval
    call trigonometric_basis(time,omega,nharmonic,design(i,:))
    rhs(i,:) = history(:,i)
  enddo

  ! Column-pivoted Householder QR least-squares solution.  Pivoting is
  ! important here because a short orbit arc makes the trigonometric columns
  ! nearly dependent.
  do j = 1, nterm
    permutation(j) = j
  enddo
  do k = 1, nterm
    ipivot = k
    pivot_norm = -1.d0
    do j = k, nterm
      column_norm = sqrt(sum(design(k:npoint,j)**2))
      if (column_norm .gt. pivot_norm) then
        pivot_norm = column_norm
        ipivot = j
      endif
    enddo
    if (pivot_norm .le. 1.d-13) then
      ierr = 5
      return
    endif

    if (ipivot .ne. k) then
      temporary_column = design(:,k)
      design(:,k) = design(:,ipivot)
      design(:,ipivot) = temporary_column
      i = permutation(k)
      permutation(k) = permutation(ipivot)
      permutation(ipivot) = i
    endif

    column_norm = sqrt(sum(design(k:npoint,k)**2))
    if (design(k,k) .ge. 0.d0) then
      alpha = -column_norm
    else
      alpha = column_norm
    endif
    householder = 0.d0
    householder(k:npoint) = design(k:npoint,k)
    householder(k) = householder(k) - alpha
    beta = sum(householder(k:npoint)**2)
    if (beta .le. 1.d-26) then
      ierr = 5
      return
    endif
    beta = 2.d0/beta

    do j = k, nterm
      factor = beta*dot_product(householder(k:npoint),design(k:npoint,j))
      design(k:npoint,j) = design(k:npoint,j) - factor*householder(k:npoint)
    enddo
    do icoor = 1, 3
      factor = beta*dot_product(householder(k:npoint),rhs(k:npoint,icoor))
      rhs(k:npoint,icoor) = rhs(k:npoint,icoor) - factor*householder(k:npoint)
    enddo
    design(k,k) = alpha
    if (k .lt. npoint) design(k+1:npoint,k) = 0.d0
  enddo

  solution = 0.d0
  do icoor = 1, 3
    do i = nterm, 1, -1
      if (abs(design(i,i)) .le. 1.d-13) then
        ierr = 5
        return
      endif
      solution(i,icoor) = rhs(i,icoor)
      if (i .lt. nterm) solution(i,icoor) = solution(i,icoor) - &
        dot_product(design(i,i+1:nterm),solution(i+1:nterm,icoor))
      solution(i,icoor) = solution(i,icoor)/design(i,i)
    enddo
  enddo

  coefficients = 0.d0
  do i = 1, nterm
    coefficients(permutation(i),:) = solution(i,:)
  enddo
  call trigonometric_basis(extrap_interval,omega,nharmonic,target_basis)
  do icoor = 1, 3
    extrapolated(icoor) = dot_product(target_basis,coefficients(:,icoor))
  enddo

  return

  contains

  subroutine trigonometric_basis(time,omega,harmonic_count,basis)
  implicit none
  integer*4 harmonic_count,iharmonic
  real*8 time,omega,basis(2*harmonic_count+1)

  basis(1) = 1.d0
  do iharmonic = 1, harmonic_count
    basis(2*iharmonic) = cos(dble(iharmonic)*omega*time)
    basis(2*iharmonic+1) = sin(dble(iharmonic)*omega*time)
  enddo
  return
  end subroutine trigonometric_basis

  subroutine estimate_orbit_period(position,point_count,interval,estimated_period,status)
  implicit none
  integer*4 point_count,status
  real*8 position(3,point_count),interval,estimated_period

  integer*4 ii,jj,nvalid
  real*8, parameter :: EARTH_GM = 398600.4418d0
  real*8 radius,speed2,energy,semimajor,swap
  real*8 velocity(3),axes(point_count-4)

  status = 0
  nvalid = 0
  do ii = 3, point_count-2
    velocity = (position(:,ii-2)-8.d0*position(:,ii-1) + &
      8.d0*position(:,ii+1)-position(:,ii+2))/(12.d0*interval)
    radius = sqrt(sum(position(:,ii)**2))
    speed2 = sum(velocity**2)
    if (radius .le. 1.d-6) cycle
    energy = 0.5d0*speed2 - EARTH_GM/radius
    if (energy .ge. 0.d0) cycle
    semimajor = -EARTH_GM/(2.d0*energy)
    if (semimajor .le. 0.d0) cycle
    nvalid = nvalid + 1
    axes(nvalid) = semimajor
  enddo
  if (nvalid .eq. 0) then
    status = 4
    estimated_period = 0.d0
    return
  endif

  do ii = 2, nvalid
    swap = axes(ii)
    jj = ii - 1
    do while (jj .ge. 1)
      if (axes(jj) .le. swap) exit
      axes(jj+1) = axes(jj)
      jj = jj - 1
    enddo
    axes(jj+1) = swap
  enddo
  if (mod(nvalid,2) .eq. 1) then
    semimajor = axes((nvalid+1)/2)
  else
    semimajor = 0.5d0*(axes(nvalid/2)+axes(nvalid/2+1))
  endif
  estimated_period = 2.d0*PI*sqrt(semimajor**3/EARTH_GM)
  if (estimated_period .le. 0.d0 .or. estimated_period .gt. 2.d5) then
    status = 4
    estimated_period = 0.d0
  endif
  return
  end subroutine estimate_orbit_period

  end subroutine trig_poly_extrapolate
