!
!! get_config.f90
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
!! Configuration options.
module get_config
  use, intrinsic :: iso_fortran_env, only: iostat_end, error_unit
  implicit none
  private
  public :: read_logical_option
  character(*), parameter :: CPROGNAME = 'algirc'

contains

  subroutine read_logical_option(lfn, option, value, use_default)
    implicit none
    integer*4      lfn
    integer*4      i, j, k, ierr
    character(*)   option
    logical*1      value
    logical*1, optional :: use_default
    character*16   word
    character*256  optval
    character*1024 line
    character(len=256) :: io_message

    rewind lfn
    do while (.true.)
      read (lfn, '(a)', iostat=ierr, iomsg=io_message) line
      if (ierr .eq. iostat_end) then
        rewind lfn
        return
      end if
      if (ierr .ne. 0) then
        write (error_unit, '(a)') trim(io_message)
        error stop 1
      end if
      if (line(1:1) .eq. '#' .or. line(1:1) .eq. '*') cycle
      i = index(line, option(1:len_trim(option)))
      if (i .eq. 0) cycle
      j = index(line, '=')
      if (j .eq. 0 .or. i .gt. j) cycle
      k = index(line, '!')
      if (k .eq. 0) k = len_trim(line) + 1
      optval = line(j+1:k-1)
      exit
    end do

    if (present(use_default)) then
      if (len_trim(optval) .eq. 0) return
    end if
    read (optval, *, iostat=ierr) word
    if (ierr .ne. 0) call option_error()
    if (present(use_default)) then
      do i = 1, len_trim(word)
        j = iachar(word(i:i))
        if (j .ge. iachar('a') .and. j .le. iachar('z')) word(i:i) = achar(j-32)
      end do
      if (word .eq. 'DEFAULT') return
      use_default = .false.
    end if

    if (word(1:1) .eq. 'Y' .or. word(1:1) .eq. 'y' .or. &
        word(1:1) .eq. 'T' .or. word(1:1) .eq. 't' .or. &
        word(1:1) .eq. '1' .or. &
        word(1:1) .eq. '.' .and. (word(2:2) .eq. 'T' .or. word(2:2) .eq. 't') .or. &
        word(1:2) .eq. 'ON' .or. word(1:2) .eq. 'on') then
      value = .true.
    else if (word(1:1) .eq. 'N' .or. word(1:1) .eq. 'n' .or. &
             word(1:1) .eq. 'F' .or. word(1:1) .eq. 'f' .or. &
             word(1:1) .eq. '0' .or. &
             word(1:1) .eq. '.' .and. (word(2:2) .eq. 'F' .or. word(2:2) .eq. 'f') .or. &
             word(1:3) .eq. 'OFF' .or. word(1:3) .eq. 'off') then
      value = .false.
    else
      call option_error()
    end if

  contains

    subroutine option_error()
      write (*, '(a,2(1x,a))') '***ERROR('//CPROGNAME//'): read logical option', trim(option), trim(optval)
      call exit(1)
    end subroutine option_error
  end subroutine

end module get_config
