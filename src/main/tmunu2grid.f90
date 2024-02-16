!--------------------------------------------------------------------------!
! The Phantom Smoothed Particle Hydrodynamics code, by Daniel Price et al. !
! Copyright (c) 2007-2023 The Authors (see AUTHORS)                        !
! See LICENCE file for usage and distribution conditions                   !
! http://phantomsph.github.io/                                             !
!--------------------------------------------------------------------------!
module tmunu2grid
!
! tmunu2grid
!
! :References: None
!
! :Owner: Spencer Magnall
!
! :Runtime parameters: None
!
! :Dependencies: boundary, einsteintk_utils, interpolations3D, part
!
 implicit none

contains
subroutine get_tmunugrid_all(npart,xyzh,vxyzu,tmunus,calc_cfac)
 use einsteintk_utils, only: dxgrid, gridorigin,gridsize,tmunugrid,rhostargrid
 use interpolations3D, only: interpolate3D,interpolate3D_vecexact
 use boundary,         only: xmin,ymin,zmin,xmax,ymax,zmax
 use part, only: massoftype,igas,rhoh
 integer, intent(in) :: npart
 real, intent(in)    ::  vxyzu(:,:), tmunus(:,:,:)
 real, intent(inout) ::  xyzh(:,:)
 logical, intent(in), optional :: calc_cfac
 real                      :: weight,h,rho,pmass
 real                      :: weights(npart)
 real, save                :: cfac
 real                      :: xmininterp(3)
 integer                   :: ngrid(3)
 real,allocatable          :: datsmooth(:,:,:,:), dat(:,:)
 integer                   :: nnodes,i,k,j, ilower, iupper, jlower, jupper, klower, kupper
 logical                   :: normalise, vertexcen,periodicx,periodicy,periodicz
 real                      :: totalmass
 integer                   :: itype(npart),ilendat


 ! total mass of the particles
 totalmass = npart*massoftype(igas)

 !print*, "totalmass(part): ", totalmass

 ! Density interpolated to the grid
 rhostargrid = 0.
 if (.not. allocated(datsmooth)) allocate (datsmooth(16,gridsize(1),gridsize(2),gridsize(3)))
 if (.not. allocated(dat)) allocate (dat(npart,16))
 ! All particles have equal weighting in the interp
 ! Here we calculate the weight for the first particle
 ! Get the smoothing length
 h = xyzh(4,1)
 ! Get pmass
 pmass = massoftype(igas)
 ! Get density
 rho = rhoh(h,pmass)
 call get_weight(pmass,h,rho,weight)
 ! Correct for Kernel Bias, find correction factor
 ! Wrap this into it's own subroutine
 if (present(calc_cfac)) then
    if (calc_cfac) call get_cfac(cfac,rho)
 endif

 weights = weight
 itype = 1
 !call get_cfac(cfac,rho)
 !print*, "Weighting for particle smoothing is: ", weight
 !weight = 1.
 ! For now we can set this to the origin, but it might need to be
 ! set to the grid origin of the CCTK_grid since we have boundary points
 ! TODO This should also be the proper phantom values and not a magic number
 !xmin(:) = gridorigin(:) - 0.5*dxgrid(:) ! We move the origin back by 0.5*dx to make a pseudo cell-centered grid
 xmininterp(1) =  xmin -dxgrid(1) !- 0.5*dxgrid(1)
 xmininterp(2) =  ymin -dxgrid(2) !- 0.5*dxgrid(2)
 xmininterp(3) =  zmin-dxgrid(3) !- 0.5*dxgrid(3)

 call get_particle_domain(gridorigin(1),xmin,xmax,dxgrid(1),ilower,iupper)
 call get_particle_domain(gridorigin(2),ymin,ymax,dxgrid(2),jlower,jupper)
 call get_particle_domain(gridorigin(3),zmin,zmax,dxgrid(3),klower,kupper)
 ! nnodes is just the size of the mesh
 ! might not be needed
 ! We note that this is not actually the size of the einstein toolkit grid
 ! As we want our periodic boundary to be on the particle domain not the
 ! ET grid domain
 ngrid(1) = (iupper-ilower) + 1
 ngrid(2) = (jupper-jlower) + 1
 ngrid(3) = (kupper-klower) + 1
 nnodes   = (iupper-ilower)*(jupper-jlower)*(kupper-klower)
 ! Do we want to normalise interpolations?
 normalise = .true.
 ! Is our NR GRID vertex centered?
 vertexcen = .false.
 periodicx = .true.
 periodicy = .true.
 periodicz = .true.



 ! tt component

 tmunugrid = 0.
 datsmooth = 0.

 ! Vectorized tmunu calculation

 ! Put tmunu into an array of form
 ! tmunu(npart,16)
 do k=1, 4
    do j=1,4
       do i=1,npart
          ! Check that this is correct!!!
          ! print*,"i j is: ", k, j
          ! print*, "Index in array is: ", (k-1)*4 + j
          ! print*,tmunus(k,j,1)
          dat(i, (k-1)*4 + j) = tmunus(k,j,i)
       enddo
    enddo
 enddo
!stop
 ilendat = 16

 call interpolate3D_vecexact(xyzh,weights,dat,ilendat,itype,npart,&
                         xmininterp(1),xmininterp(2),xmininterp(3), &
                         datsmooth(:,ilower:iupper,jlower:jupper,klower:kupper),&
                         ngrid(1),ngrid(2),ngrid(3),dxgrid(1),dxgrid(2),dxgrid(3),&
                         normalise,periodicx,periodicy,periodicz)

! Put the smoothed array into tmunugrid
 do i=1,4
    do j=1,4
       ! Check this is correct too!
       !print*,"i j is: ", i, j
       !print*, "Index in array is: ", (i-1)*4 + j
       tmunugrid(i-1,j-1,:,:,:) = datsmooth((i-1)*4 + j, :,:,:)
       !print*, "tmunugrid: ", tmunugrid(i-1,j-1,10,10,10)
       !print*, datsmooth((i-1)*4 + j, 10,10,10)
    enddo
 enddo
!stop
! do k=1,4
!    do j=1,4
!       do i=1,4
!          print*, "Lock index is: ", (k-1)*16+ (j-1)*4 + i
!       enddo
!    enddo
! enddo

! tmunugrid(0,0,:,:,:) = datsmooth(1,:,:,:)

 ! TODO Unroll this loop for speed + using symmetries
 ! Possiblly cleanup the messy indexing
!  do k=1,4
!     do j=1,4
!        do i=1, npart
!           dat(i) = tmunus(k,j,i)
!        enddo

!        ! Get the position of the first grid cell x,y,z
!        ! Call to interpolate 3D
!        ! COMMENTED OUT AS NOT USED BY NEW INTERPOLATE ROUTINE
!        ! call interpolate3D(xyzh,weight,npart, &
!        !              xmininterp,tmunugrid(k-1,j-1,ilower:iupper,jlower:jupper,klower:kupper), &
!        !              nnodes,dxgrid,normalise,dat,ngrid,vertexcen)

!        !print*, "Interpolated grid values are: ", datsmooth(4:38,4:38,4:38)
!        !stop
!        ! NEW INTERPOLATION ROUTINE
!        call interpolate3D(xyzh,weights,dat,itype,npart,&
!                         xmininterp(1),xmininterp(2),xmininterp(3), &
!                         tmunugrid(k-1,j-1,ilower:iupper,jlower:jupper,klower:kupper),&
!                         ngrid(1),ngrid(2),ngrid(3),dxgrid(1),dxgrid(2),dxgrid(3),&
!                         normalise,periodicx,periodicy,periodicz)
!     enddo
!  enddo

 ! RHOSTARGRID CALCULATION IS NOW HANDLED BY AN EXTERNAL ROUTINE
 ! THIS IS COMMENTED OUT IN CASE I BREAK EVERYTHING AND NEED TO GO BACK
 ! Get the conserved density on the particles
 ! dat = 0.
 ! do i=1, npart
 !     ! Get the smoothing length
 !     h = xyzh(4,i)
 !     ! Get pmass
 !     pmass = massoftype(igas)
 !     rho = rhoh(h,pmass)
 !     dat(i) = rho
 ! enddo

 ! Commented out as not used by new interpolate routine
 ! call interpolate3D(xyzh,weight,npart, &
 !     xmininterp,rhostargrid(ilower:iupper,jlower:jupper,klower:kupper), &
 !     nnodes,dxgrid,.true.,dat,ngrid,vertexcen)


 ! Calculate the total mass on the grid
 !totalmassgrid = 0.
 ! do i=ilower,iupper
 !     do j=jlower,jupper
 !         do k=klower, kupper
 !             totalmassgrid = totalmassgrid + dxgrid(1)*dxgrid(2)*dxgrid(3)*rhostargrid(i,j,k)

 !         enddo
 !     enddo
 ! enddo
 ! Explicitly set pressure to be 0
 ! Need to do this in the phantom setup file later
 ! tmunugrid(1,0:3,:,:,:) = 0.
 ! tmunugrid(2,0:3,:,:,:) = 0.
 ! tmunugrid(3,0:3,:,:,:) = 0.
 !tmunugrid(0,0,:,:,:) = tmunus(1,1,1)
 ! Correction for kernel bias code
 ! Hardcoded values for the cubic spline computed using
 ! a constant density flrw universe.
 ! Ideally this should be in a more general form
 ! cfac = totalmass/totalmassgrid
 ! ! Output total mass on grid, total mass on particles
 ! ! and the residuals
 ! !cfac = 0.99917535781746514D0
 ! tmunugrid = tmunugrid*cfac
 ! if (iteration==0) then
 !     write(666,*) "iteration ", "Mass(Grid) ", "Mass(Particles) ", "Mass(Grid-Particles)"
 ! endif
 ! write(666,*) iteration, totalmassgrid, totalmass, abs(totalmassgrid-totalmass)
 ! close(unit=666)
 ! iteration = iteration + 1

 ! New rho/smoothing length calc based on correction??
 ! not sure that this is a valid thing to do
 ! do i=1, npart
 !     rho = rhoh(xyzh(i,4),pmass)
 !     rho = rho*cfac
 !     xyzh(i,4) = hfact*(pmass/rho)**(1./3.)

 ! enddo

 ! Correct rhostargrid using cfac
 !rhostargrid = cfac*rhostargrid

 ! Calculate rho(prim), P and e on the grid
 ! Apply kernel correction to primatives??
 ! Then calculate a stress energy tensor per grid and fill tmunu
 ! A good consistency check would be to do it both ways and compare values

 ! Primative density


end subroutine get_tmunugrid_all

subroutine get_weight(pmass,h,rhoi,weight)
 real, intent(in)  :: pmass,h,rhoi
 real, intent(out) :: weight

 weight = (pmass)/(rhoi*h**3)

end subroutine get_weight

subroutine get_dat(tmunus,dat)
 real, intent(in)  :: tmunus
 real, intent(out) :: dat

end subroutine get_dat

 ! subroutine get_primdens(dens,dat)
 !     real, intent(in) :: dens
 !     real, intent(out) :: dat
 !     integer :: i, npart

 !     ! Get the primative density on the particles
 !     dat = 0.
 !     do i=1, npart
 !         dat(i) = dens(i)
 !     enddo

 ! end subroutine get_primdens

 ! subroutine get_4velocity(vxyzu,dat)
 !     real, intent(in) :: vxyzu(:,:)
 !     real, intent(out) :: dat(:,:)
 !     integer :: i,npart

 !     ! Get the primative density on the particles
 !     dat = 0.
 !     do i=1, npart
 !         dat(:,i) = vxyzu(1:3,i)
 !     enddo

 ! end subroutine get_4velocity

subroutine get_particle_domain(gridorigin,xmin,xmax,dxgrid,ilower,iupper)
 real,    intent(in)  :: gridorigin, xmin,xmax, dxgrid
 integer, intent(out) :: ilower, iupper

 ! Changed from int to nint
 ! to fix a bug
 ilower = nint((xmin - gridorigin)/dxgrid) + 1  ! +1 since our arrays start at 1 not 0
 iupper = nint((xmax - gridorigin)/dxgrid) ! Removed the +1 as this was also a bug
 ! The lower boundary is in the physical
 ! domain but the upper is not; can't have both?
end subroutine get_particle_domain

subroutine get_cfac(cfac,rho)
 real, intent(in)  :: rho
 real, intent(out) :: cfac
 real              :: rhoexact
 rhoexact = 13.294563008157013D0
 cfac = rhoexact/rho

end subroutine get_cfac

subroutine interpolate_to_grid(gridarray,dat)
 use einsteintk_utils, only: dxgrid, gridorigin
 use interpolations3D, only: interpolate3D
 use boundary,         only: xmin,ymin,zmin,xmax,ymax,zmax
 use part, only:npart,xyzh,massoftype,igas,rhoh
 real                      :: weight,h,rho,pmass
 !real, save                :: cfac
 !integer, save             :: iteration = 0
 real                      :: xmininterp(3)
 integer                   :: ngrid(3)
 integer                   :: nnodes,i, ilower, iupper, jlower, jupper, klower, kupper
 logical                   :: normalise, vertexcen,periodicx, periodicy, periodicz
 real, dimension(npart)    :: weights
 integer, dimension(npart) :: itype
 real, intent(out) :: gridarray(:,:,:) ! Grid array to interpolate a quantity to
 ! GRID MUST BE RESTRICTED WITH UPPER AND LOWER INDICIES
 real, intent(in) :: dat(:)            ! The particle data to interpolate to grid
 real, allocatable :: interparray(:,:,:)


 xmininterp(1) =  xmin - dxgrid(1)!- 0.5*dxgrid(1)
 xmininterp(2) =  ymin - dxgrid(2) !- 0.5*dxgrid(2)
 xmininterp(3) =  zmin - dxgrid(3) !- 0.5*dxgrid(3)
 !print*, "xminiterp: ", xmininterp
 call get_particle_domain(gridorigin(1),xmin,xmax,dxgrid(1),ilower,iupper)
 call get_particle_domain(gridorigin(2),ymin,ymax,dxgrid(2),jlower,jupper)
 call get_particle_domain(gridorigin(3),zmin,zmax,dxgrid(3),klower,kupper)

 ! We note that this is not actually the size of the einstein toolkit grid
 ! As we want our periodic boundary to be on the particle domain not the
 ! ET grid domain
 ngrid(1) = (iupper-ilower) + 1
 ngrid(2) = (jupper-jlower) + 1
 ngrid(3) = (kupper-klower) + 1
 allocate(interparray(ngrid(1),ngrid(2),ngrid(3)))
 interparray = 0.
 nnodes   = (iupper-ilower)*(jupper-jlower)*(kupper-klower)
 ! Do we want to normalise interpolations?
 normalise = .true.
 ! Is our NR GRID vertex centered?
 vertexcen = .false.
 periodicx = .true.
 periodicy = .true.
 periodicz = .true.



 do i=1, npart
    h = xyzh(4,i)
    ! Get pmass
    pmass = massoftype(igas)
    ! Get density
    rho = rhoh(h,pmass)
    call get_weight(pmass,h,rho,weight)
    weights(i) = weight
 enddo
 itype   = igas
 ! call interpolate3D(xyzh,weight,npart, &
 ! xmininterp,gridarray(ilower:iupper,jlower:jupper,klower:kupper), &
 ! nnodes,dxgrid,normalise,dat,ngrid,vertexcen)
 call interpolate3D(xyzh,weights,dat,itype,npart,&
        xmininterp(1),xmininterp(2),xmininterp(3), &
 !interparray, &
        gridarray(ilower:iupper,jlower:jupper,klower:kupper),&
        ngrid(1),ngrid(2),ngrid(3),dxgrid(1),dxgrid(2),dxgrid(3),&
        normalise,periodicx,periodicy,periodicz)




end subroutine interpolate_to_grid

subroutine check_conserved_dens(rhostargrid,cfac)
 use part, only:npart,massoftype,igas
 use einsteintk_utils, only: dxgrid, gridorigin
 use boundary,         only:xmin,xmax,ymin,ymax,zmin,zmax
 real, intent(in) :: rhostargrid(:,:,:)
 real(kind=16), intent(out) :: cfac
 real :: totalmassgrid,totalmasspart
 integer :: i,j,k,ilower,iupper,jlower,jupper,klower,kupper


 call get_particle_domain(gridorigin(1),xmin,xmax,dxgrid(1),ilower,iupper)
 call get_particle_domain(gridorigin(2),ymin,ymax,dxgrid(2),jlower,jupper)
 call get_particle_domain(gridorigin(3),zmin,zmax,dxgrid(3),klower,kupper)

 totalmassgrid = 0.
 do i=ilower,iupper
    do j=jlower,jupper
       do k=klower, kupper
          totalmassgrid = totalmassgrid + dxgrid(1)*dxgrid(2)*dxgrid(3)*rhostargrid(i,j,k)

       enddo
    enddo
 enddo

 ! total mass of the particles
 totalmasspart = npart*massoftype(igas)

 !print*, "Total mass grid: ", totalmassgrid
 !print*, "Total mass part: ", totalmasspart
 ! Calculate cfac
 cfac = totalmasspart/totalmassgrid

 !print*, "cfac mass: ", cfac

end subroutine check_conserved_dens

subroutine check_conserved_p(pgrid,cfac)
 use part, only:npart,massoftype,igas
 use einsteintk_utils, only: dxgrid, gridorigin
 use boundary,         only:xmin,xmax,ymin,ymax,zmin,zmax
 real, intent(in) :: pgrid(:,:,:)
 real(kind=16), intent(out) :: cfac
 real :: totalmomentumgrid,totalmomentumpart
 integer :: i,j,k,ilower,iupper,jlower,jupper,klower,kupper

 call get_particle_domain(gridorigin(1),xmin,xmax,dxgrid(1),ilower,iupper)
 call get_particle_domain(gridorigin(2),ymin,ymax,dxgrid(2),jlower,jupper)
 call get_particle_domain(gridorigin(3),zmin,zmax,dxgrid(3),klower,kupper)

 ! I'm still a bit unsure what this conserved quantity is actually meant to be??
 totalmomentumgrid = 0.
 do i=ilower,iupper
    do j=jlower,jupper
       do k=klower, kupper
          !totalmomentumgrid = totalmomentumgrid + dxgrid(1)*dxgrid(2)*dxgrid(3)*rhostargrid(i,j,k)

       enddo
    enddo
 enddo

 ! total cons(momentum) of the particles
 totalmomentumpart = npart*massoftype(igas)

 ! Calculate cfac
 cfac = totalmomentumpart/totalmomentumgrid

 !print*, "cfac mass: ", cfac

end subroutine check_conserved_p

end module tmunu2grid
