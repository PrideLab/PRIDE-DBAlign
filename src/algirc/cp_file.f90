!
!! cp_file.f90
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
!! Exact file copying.
module cp_file
  implicit none
  private
  public :: copy_file_exact

contains

  subroutine copy_file_exact(source, destination, ierr, copy_size)
    implicit none
  !
  !! argument
    character(*) source
    character(*) destination
    integer*4    ierr
    integer*8, optional :: copy_size
  !
  !! local variable
    integer*4       source_lfn, destination_lfn, ios, nbyte
    integer*8       file_size, position
    character*65536 buffer
  !
  !! function used
    integer*4 get_valid_unit

    ierr = 0
    inquire (file=source, size=file_size, iostat=ios)
    if (ios .ne. 0) then
      ierr = ios
      return
    end if
    if (present(copy_size)) file_size = min(file_size, max(0_8, copy_size))

    source_lfn = get_valid_unit(20)
    open (source_lfn, file=source, status='old', access='stream', form='unformatted', &
          action='read', iostat=ios)
    if (ios .ne. 0) then
      ierr = ios
      return
    end if

    destination_lfn = get_valid_unit(source_lfn + 1)
    open (destination_lfn, file=destination, status='replace', access='stream', &
          form='unformatted', action='write', iostat=ios)
    if (ios .ne. 0) then
      close (source_lfn)
      ierr = ios
      return
    end if

    position = 1
    do while (position .le. file_size)
      nbyte = int(min(int(len(buffer), kind=8), file_size - position + 1))
      read (source_lfn, pos=position, iostat=ios) buffer(1:nbyte)
      if (ios .ne. 0) exit
      write (destination_lfn, iostat=ios) buffer(1:nbyte)
      if (ios .ne. 0) exit
      position = position + nbyte
    end do

    close (source_lfn)
    close (destination_lfn)
    if (ios .ne. 0) ierr = ios
  end subroutine

end module cp_file
