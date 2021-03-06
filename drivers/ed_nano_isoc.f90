program ed_nano_isoc
  USE DMFT_ED
  USE SCIFOR
  USE DMFT_TOOLS
  implicit none

  integer                                         :: iloop
  logical                                         :: converged
  integer                                         :: ilat,ineq,ispin,iorb
  !bath:
  integer                                         :: Nb
  real(8),allocatable                             :: Bath_prev(:,:),Bath_ineq(:,:)
  !local hybridization function:
  complex(8),allocatable,dimension(:,:,:,:,:,:)   :: Weiss_ineq
  complex(8),allocatable,dimension(:,:,:,:,:,:)   :: Smats,Smats_ineq
  complex(8),allocatable,dimension(:,:,:,:,:,:)   :: Sreal,Sreal_ineq ![Nlat*(Nspin*Norb)**2*Lreal]
  complex(8),allocatable,dimension(:,:,:,:,:,:)   :: Gmats,Gmats_ineq
  complex(8),allocatable,dimension(:,:,:,:,:,:)   :: Greal,Greal_ineq
  real(8), allocatable,dimension(:)               :: dens,dens_ineq
  real(8), allocatable,dimension(:)               :: docc,docc_ineq
  !hamiltonian input:
  complex(8),allocatable                          :: Hij(:,:,:) ![Nlat*Nspin*Norb][Nlat*Nspin*Norb][Nk==1]
  complex(8),allocatable                          :: nanoHloc(:,:),Hloc(:,:,:,:,:),Hloc_ineq(:,:,:,:,:)
  integer                                         :: Nk,Nlso,Nineq,Nlat
  integer,dimension(:),allocatable                :: lat2ineq,ineq2lat
  integer,dimension(:),allocatable                :: sb_field_sign
  !
  real(8)                                         :: wmixing,Eout(2)
  !input files:
  character(len=32)                               :: finput
  character(len=32)                               :: nfile,hijfile,hisocfile
  !
  logical                                         :: phsym
  logical                                         :: leads
  logical                                         :: kinetic,trans,jbias,jrkky,chi0ij
  logical                                         :: para
  !non-local Green's function:
  complex(8),allocatable,dimension(:,:,:,:,:,:,:) :: Gijmats,Gijreal
  !hybridization function to environment
  complex(8),dimension(:,:,:),allocatable         :: Hyb_mats,Hyb_real ![Nlat*Nspin*Norb][Nlat*Nspin*Norb][Lmats/Lreal]


  call parse_cmd_variable(finput,"FINPUT",default='inputED_NANO.conf')
  call parse_input_variable(nfile,"NFILE",finput,default="nano.in")
  call parse_input_variable(hijfile,"HIJFILE",finput,default="hij.in")
  call parse_input_variable(hisocfile,"HISOCFILE",finput,default="hisoc.in")
  call parse_input_variable(wmixing,"WMIXING",finput,default=0.5d0)
  call parse_input_variable(phsym,"phsym",finput,default=.false.)
  ! parse environment & transport flags
  call parse_input_variable(leads,"leads",finput,default=.false.)
  call parse_input_variable(trans,"trans",finput,default=.false.)
  call parse_input_variable(jbias,"jbias",finput,default=.false.)
  call parse_input_variable(jrkky,"jrkky",finput,default=.false.)
  call parse_input_variable(chi0ij,"chi0ij",finput,default=.false.)
  call parse_input_variable(kinetic,"kinetic",finput,default=.false.)
  call parse_input_variable(para,"para",finput,default=.false.)
  ! read input
  call ed_read_input(trim(finput))


  call add_ctrl_var(Norb,"Norb")
  call add_ctrl_var(Nspin,"Nspin")
  call add_ctrl_var(beta,"beta")
  call add_ctrl_var(xmu,"xmu")
  call add_ctrl_var(wini,"wini")
  call add_ctrl_var(wfin,"wfin")
  call add_ctrl_var(eps,"eps")

  ! set input structure hamiltonian
  call build_Hij([nfile,hijfile,hisocfile])

  ! allocate weiss field:
  allocate(Weiss_ineq(Nineq,Nspin,Nspin,Norb,Norb,Lmats))
  ! allocate self-energy
  allocate(Smats(Nlat,Nspin,Nspin,Norb,Norb,Lmats))
  allocate(Smats_ineq(Nineq,Nspin,Nspin,Norb,Norb,Lmats))
  allocate(Sreal(Nlat,Nspin,Nspin,Norb,Norb,Lreal))
  allocate(Sreal_ineq(Nineq,Nspin,Nspin,Norb,Norb,Lreal))
  ! allocate Green's function
  allocate(Gmats(Nlat,Nspin,Nspin,Norb,Norb,Lmats))
  allocate(Gmats_ineq(Nineq,Nspin,Nspin,Norb,Norb,Lmats))
  allocate(Greal(Nlat,Nspin,Nspin,Norb,Norb,Lreal))
  allocate(Greal_ineq(Nineq,Nspin,Nspin,Norb,Norb,Lreal))
  ! allocate Hloc
  allocate(Hloc(Nlat,Nspin,Nspin,Norb,Norb))
  allocate(Hloc_ineq(Nineq,Nspin,Nspin,Norb,Norb))
  ! allocate density
  allocate(dens(Nlat))
  allocate(dens_ineq(Nineq))
  ! allocate double occupations
  allocate(docc(Nlat))
  allocate(docc_ineq(Nineq))

  !Hloc = reshape_Hloc(nanoHloc,Nlat,Nspin,Norb)
  Hloc = lso2nnn_reshape(nanoHloc,Nlat,Nspin,Norb)



  ! postprocessing options

  ! evaluates the kinetic energy
  if(kinetic)then
     !
     ! allocate hybridization matrix
     if(leads)then
        call set_hyb()
        call dmft_set_Gamma_matsubara(hyb_mats) !needed for dmft_kinetic_energy (change!)
     endif
     !
     ! read converged self-energy
     call read_sigma_mats(Smats_ineq)
     do ilat=1,Nlat
        ineq = lat2ineq(ilat)
        Smats(ilat,:,:,:,:,:) = Smats_ineq(ineq,:,:,:,:,:)
     enddo
     !
     print*,size(Smats,1)
     print*,size(Smats,4),size(Smats,5)
     print*,size(Smats,6)
     Eout = dmft_kinetic_energy(Hij,[1d0],Smats)
     print*,Eout
     stop
  endif


  ! computes conductance on the real-axis
  if(trans)then
     !
     ! allocate hybridization matrix
     if(leads)then
        call set_hyb()
        call dmft_set_Gamma_realaxis(hyb_real) !needed for dmft_gij_realaxis
     endif
     !
     ! read converged self-energy
     call read_sigma_real(Sreal_ineq)
     do ilat=1,Nlat
        ineq = lat2ineq(ilat)
        Sreal(ilat,:,:,:,:,:) = Sreal_ineq(ineq,:,:,:,:,:)
     enddo
     !
     allocate(Gijreal(Nlat,Nlat,Nspin,Nspin,Norb,Norb,Lreal))
     call dmft_gloc_realaxis(Hij,[1d0],Greal,Sreal,iprint=1)
     call dmft_gij_realaxis(Hij,[1d0],Gijreal,Sreal,iprint=0)
     !
     ! extract the linear response (zero-bias) transmission function
     ! i.e. the conductance in units of the quantum G0 [e^2/h]
     ! and the corresponding bias-driven current (if jbias=T)
     call ed_transport(Gijreal)
     !
     deallocate(Gijreal)
     stop
  endif



  ! compute effective non-local exchange
  if(jrkky)then
     !
     ! allocate hybridization matrix
     if(leads)then
        call set_hyb()
        call dmft_set_Gamma_realaxis(hyb_real) !needed for dmft_gij_realaxis
     endif
     !
     ! read converged self-energy
     call read_sigma_real(Sreal_ineq)
     do ilat=1,Nlat
        ineq = lat2ineq(ilat)
        Sreal(ilat,:,:,:,:,:) = Sreal_ineq(ineq,:,:,:,:,:)
     enddo
     !
     allocate(Gijreal(Nlat,Nlat,Nspin,Nspin,Norb,Norb,Lreal))
     call dmft_gloc_realaxis(Hij,[1d0],Greal,Sreal,iprint=1)
     call dmft_gij_realaxis(Hij,[1d0],Gijreal,Sreal,iprint=0)
     !
     ! compute effective exchange
     call ed_get_jeff(Gijreal,Sreal)
     !
     deallocate(Gijreal,Sreal)
     stop
  endif



  ! compute effective non-local exchange
  if(chi0ij)then
     !
     ! allocate hybridization matrix
     if(leads)then
        call set_hyb()
        call dmft_set_Gamma_realaxis(hyb_real) !needed for dmft_gij_realaxis
     endif
     !
     ! read converged self-energy
     call read_sigma_real(Sreal_ineq)
     do ilat=1,Nlat
        ineq = lat2ineq(ilat)
        Sreal(ilat,:,:,:,:,:) = Sreal_ineq(ineq,:,:,:,:,:)
     enddo
     !
     allocate(Gijreal(Nlat,Nlat,Nspin,Nspin,Norb,Norb,Lreal))
     call dmft_gloc_realaxis(Hij,[1d0],Greal,Sreal,iprint=1)
     call dmft_gij_realaxis(Hij,[1d0],Gijreal,Sreal,iprint=0)
     !
     ! compute bare static non-local susceptibility
     call ed_get_chi0ij(Gijreal)
     !
     deallocate(Gijreal,Sreal)
     stop
  endif


  !###################################################################################################


  ! allocate hybridization matrix
  if(leads)then
     call set_hyb()
  endif


  ! setup solver
  Nb=get_bath_dimension()

  allocate(Bath_ineq(Nineq,Nb))
  allocate(Bath_prev(Nineq,Nb))
  call ed_init_solver(Bath_ineq)

  do ineq=1,Nineq
     ilat = ineq2lat(ineq)
     ! break SU(2) symmetry for magnetic solutions
     if(Nspin>1) call break_symmetry_bath(Bath_ineq(ineq,:),sb_field,dble(sb_field_sign(ineq)))
     Hloc_ineq(ineq,:,:,:,:) = Hloc(ilat,:,:,:,:)
  enddo

  iloop=0 ; converged=.false.
  do while(.not.converged.AND.iloop<nloop) 
     iloop=iloop+1
     call start_loop(iloop,nloop,"DMFT-loop")   
     bath_prev=bath_ineq

     ! solve impurities on each inequivalent site:
     call ed_solve(bath_ineq,Hloc_ineq,iprint=0)

     ! retrieve self-energies and occupations(Nineq,Norb=1)
     call ed_get_sigma_matsubara(Smats_ineq,Nineq)
     call ed_get_sigma_real(Sreal_ineq,Nineq)
     call ed_get_dens(dens_ineq,Nineq,iorb=1)
     call ed_get_docc(docc_ineq,Nineq,iorb=1)

     ! spin-symmetrization to enforce paramagnetic solution
     if(para)then
        if(Nspin/=2)stop "cannot spin-symmetrize for Nspin!=2"
        ! average inequivalent self-energy over spin
        Smats_ineq(:,1,1,:,:,:) = 0.5d0*(Smats_ineq(:,1,1,:,:,:)+Smats_ineq(:,2,2,:,:,:))
        Smats_ineq(:,2,2,:,:,:) = Smats_ineq(:,1,1,:,:,:)
        Sreal_ineq(:,1,1,:,:,:) = 0.5d0*(Sreal_ineq(:,1,1,:,:,:)+Sreal_ineq(:,2,2,:,:,:))
        Sreal_ineq(:,2,2,:,:,:) = Sreal_ineq(:,1,1,:,:,:)
     endif

     ! spread self-energies and occupation to all lattice sites
     do ilat=1,Nlat
        ineq = lat2ineq(ilat)
        dens(ilat) = dens_ineq(ineq)
        docc(ilat) = docc_ineq(ineq)
        Smats(ilat,:,:,:,:,:) = Smats_ineq(ineq,:,:,:,:,:)
        Sreal(ilat,:,:,:,:,:) = Sreal_ineq(ineq,:,:,:,:,:)
     enddo

     ! compute the local gf:
     !
     if(leads)then
        call dmft_set_Gamma_matsubara(hyb_mats)
     endif
     call dmft_gloc_matsubara(Hij,[1d0],Gmats,Smats,iprint=1)
     do ineq=1,Nineq
        ilat = ineq2lat(ineq)
        Gmats_ineq(ineq,:,:,:,:,:) = Gmats(ilat,:,:,:,:,:)
     enddo
     !
     if(leads)then
        call dmft_set_Gamma_realaxis(hyb_mats)
     endif
     call dmft_gloc_realaxis(Hij,[1d0],Greal,Sreal,iprint=1)
     do ineq=1,Nineq
        ilat = ineq2lat(ineq)
        Greal_ineq(ineq,:,:,:,:,:) = Greal(ilat,:,:,:,:,:)
     enddo

     ! compute the Weiss field
     if(cg_scheme=="weiss")then
        call dmft_weiss(Gmats_ineq,Smats_ineq,Weiss_ineq,Hloc_ineq,iprint=0)
     else
        call dmft_delta(Gmats_ineq,Smats_ineq,Weiss_ineq,Hloc_ineq,iprint=0)
     endif

     ! fit baths and mix result with old baths
     do ispin=1,Nspin
        call ed_chi2_fitgf(bath_ineq,Weiss_ineq,Hloc_ineq,ispin)
     enddo

     if(phsym)then
        do ineq=1,Nineq
           call ph_symmetrize_bath(bath_ineq(ineq,:),save=.true.)
        enddo
     endif
     Bath_ineq=wmixing*Bath_ineq + (1.d0-wmixing)*Bath_prev

     converged = check_convergence(Weiss_ineq(1,1,1,1,1,:),dmft_error,nsuccess,nloop)
     ! alternative convergency criteria
     !converged = check_convergence_local(docc_ineq,dmft_error,nsuccess,nloop)
     if(NREAD/=0.d0) call search_chemical_potential(xmu,sum(dens)/Nlat,converged)

     call end_loop()
  end do

  ! save self-energy on disk
  call save_sigma_mats(Smats_ineq)
  call save_sigma_real(Sreal_ineq)

  ! compute kinetic energy at convergence
  Eout = dmft_kinetic_energy(Hij,[1d0],Smats)
  print*,Eout




contains



  !----------------------------------------------------------------------------------------!
  ! purpose: build real-space Hamiltonian for a nanostructure of size [Nlat*Nspin*Norb]**2
  !----------------------------------------------------------------------------------------!
  subroutine build_Hij(file)
    character(len=*)     :: file(3)
    integer              :: ilat,jlat,iorb,jorb,is,js,ispin,ie
    integer              :: i,isite,iineq,iineq0,isign
    integer              :: EOF
    character, parameter :: tab = achar ( 9 )
    integer              :: unit,ineq_count
    integer              :: Ns,Ne,Nb,Nk         ! #atoms, #inequivalent, #bands
    real(8)              :: ret,imt
    logical              :: blank_at_right
    character(len=1)     :: next,prev
    character(len=6)     :: site,sign
    write(LOGfile,*)"Build H(R_i,R_j) for a NANO object:"
    ! readin generic input
    ! allocate & fill inequivalent list
    unit = free_unit()
    open(unit,file=trim(file(1)),status='old')
    read(unit,*)Ns,Ne,Nb
    !Checks:
    if(Nb/=Norb)stop "build_Hij error: Nb read from file != Norb in input.conf"
    Nk   = 1
    Nb   = Norb
    Nlat = Ns
    Nineq= Ne
    Nlso = Nlat*Nspin*Norb
    allocate(lat2ineq(Nlat),ineq2lat(Nineq))
    read(unit,"(A1)",advance='no',IOSTAT=EOF)next
    site  = next
    isite = 0
    i     = 0
    do 
       prev=next
       read(unit,"(A1)",advance='no',IOSTAT=EOF)next
       blank_at_right = ((prev/=' '.AND.prev/=tab).AND.(next==' '.OR.next==tab))
       if(.not.blank_at_right)then
          site=trim(site)//next
       else
          read(site,"(I6)")isite
          site=""
          i=i+1
          if(i>Nlat)stop "build_Hij error: lattice index > Nlat read from file"
          lat2ineq(i)=isite+1
       endif
       if(EOF<0)exit
    enddo
    if(i<Nlat)stop "build_Hij error: lattice index < Nlat read from file"
    write(*,*)"# of sites      :",Nlat
    write(*,*)"# of ineq sites :",Nineq
    write(*,*)"# of bands      :",Norb
    !
    ineq_count=1
    iineq=lat2ineq(Nlat)
    do i=Nlat,2,-1
       iineq0=lat2ineq(i-1)!iineq
       iineq =lat2ineq(i)
       if(iineq/=iineq0)then
          ineq2lat(iineq)=i
          ineq_count=ineq_count+1
       endif
       !if(ineq_count==Nineq)exit
    enddo
    iineq=lat2ineq(1)
    ineq2lat(1)=iineq
    !close(unit) ! do not close unit if readin info below
    !
    ! allocate & fill sign list of symmetry-breaking field
    allocate(sb_field_sign(Nineq))
    sign  = next
    isign = 0
    i     = 0
    do 
       prev=next
       read(unit,"(A1)",advance='no',IOSTAT=EOF)next
       blank_at_right = ((prev/=' '.AND.prev/=tab).AND.(next==' '.OR.next==tab))
       if(.not.blank_at_right)then
          sign=trim(sign)//next
       else
          read(sign,"(I6)")isign
          sign=""
          i=i+1
          if(i>Nineq)stop "build_Hij error: lattice index > Nineq read from file"
          sb_field_sign(i)=isign
       endif
       if(EOF<0)exit
    enddo
    close(unit)
    !
    ! allocate and initialize H(r_i,r_j)
    allocate(Hij(Nlso,Nlso,Nk))
    Hij = zero 
    unit = free_unit()
    open(unit,file=trim(file(2)),status='old')
    do !while(EOF>=0)
       read(unit,*,IOSTAT=EOF)ilat,iorb,jlat,jorb,ret,imt
       ilat=ilat+1
       iorb=iorb+1
       jlat=jlat+1
       jorb=jorb+1
       if(EOF<0)exit
       do ispin=1,Nspin
          is = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
          js = jorb + (ispin-1)*Norb + (jlat-1)*Nspin*Norb
          ! hermitian hopping
          Hij(is,js,1)=dcmplx(ret, imt)
          Hij(js,is,1)=dcmplx(ret,-imt)
       enddo
    enddo
    close(unit)
    !
    ! if Nspin!=2 raise error
    if(Nspin/=2)stop "build_Hij error: cannot implement intrinsic SOC with Nspin/=2"
    unit = free_unit()
    open(unit,file=trim(file(3)),status='old')
    do !while(EOF>=0)
       read(unit,*,IOSTAT=EOF)ilat,iorb,jlat,jorb,ret,imt
       ilat=ilat+1
       iorb=iorb+1
       jlat=jlat+1
       jorb=jorb+1
       if(EOF<0)exit
       do ispin=1,Nspin
          is = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
          js = jorb + (ispin-1)*Norb + (jlat-1)*Nspin*Norb
          ! hermitian (imaginary) hopping w/ spin-antisymmetric intrinsic SOC
          Hij(is,js,1)=dcmplx(ret, imt)*(1-2*(ispin-1))
          Hij(js,is,1)=dcmplx(ret,-imt)*(1-2*(ispin-1))
       enddo
    enddo
    close(unit)
    !
    ! basis vectors must be defined
    call TB_set_bk([1d0,0d0,0d0],[0d0,1d0,0d0],[0d0,0d0,1d0])
    call TB_write_hk(Hk=Hij,file="Hij_nano.data",&
         No=Nlso,&
         Nd=Norb,&
         Np=0,&
         Nineq=Nineq,&
         Nkvec=[1,1,1])
    !
    allocate(nanoHloc(Nlso,Nlso))
    nanoHloc = extract_Hloc(Hij,Nlat,Nspin,Norb)
    !
    !save lat2ineq,ineq2lat arrays
    unit=free_unit()
    open(unit,file="lat2ineq.ed")
    do ilat=1,Nlat
       write(unit,*)ilat,lat2ineq(ilat)
    enddo
    close(unit)
    unit=free_unit()
    open(unit,file="ineq2lat.ed")
    do i=1,Nineq
       write(unit,*)i,ineq2lat(i)
    enddo
    close(unit)
  end subroutine build_Hij


  !----------------------------------------------------------------------------------------!
  ! purpose: save the matsubare local self-energy on disk
  !----------------------------------------------------------------------------------------!
  subroutine save_sigma_mats(Smats)
    complex(8),intent(inout)         :: Smats(:,:,:,:,:,:)
    character(len=30)                :: suffix
    integer                          :: ilat,ispin,iorb
    real(8),dimension(:),allocatable :: wm

    if(size(Smats,2)/=Nspin) stop "save_sigma: error in dim 2. Nspin"
    if(size(Smats,3)/=Nspin) stop "save_sigma: error in dim 3. Nspin"
    if(size(Smats,4)/=Norb) stop "save_sigma: error in dim 4. Norb"
    if(size(Smats,5)/=Norb) stop "save_sigma: error in dim 5. Norb"

    allocate(wm(Lmats))

    wm = pi/beta*(2*arange(1,Lmats)-1)
    write(LOGfile,*)"write spin-orbital diagonal elements:"
    do ispin=1,Nspin
       do iorb=1,Norb
          suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
          call store_data("LSigma"//trim(suffix),Smats(:,ispin,ispin,iorb,iorb,:),wm)
       enddo
    enddo

  end subroutine save_sigma_mats


  !----------------------------------------------------------------------------------------!
  ! purpose: save the real local self-energy on disk
  !----------------------------------------------------------------------------------------!
  subroutine save_sigma_real(Sreal)
    complex(8),intent(inout)         :: Sreal(:,:,:,:,:,:)
    character(len=30)                :: suffix
    integer                          :: ilat,ispin,iorb
    real(8),dimension(:),allocatable :: wm,wr

    if(size(Sreal,2)/=Nspin) stop "save_sigma: error in dim 2. Nspin"
    if(size(Sreal,3)/=Nspin) stop "save_sigma: error in dim 3. Nspin"
    if(size(Sreal,4)/=Norb) stop "save_sigma: error in dim 4. Norb"
    if(size(Sreal,5)/=Norb) stop "save_sigma: error in dim 5. Norb"

    allocate(wr(Lreal))

    wr = linspace(wini,wfin,Lreal)
    do ispin=1,Nspin
       do iorb=1,Norb
          suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
          call store_data("LSigma"//trim(suffix),Sreal(:,ispin,ispin,iorb,iorb,:),wr)
       enddo
    enddo

  end subroutine save_sigma_real


  !----------------------------------------------------------------------------------------!
  ! purpose: save the local self-energy on disk
  !----------------------------------------------------------------------------------------!
  subroutine save_sigma(Smats,Sreal)
    complex(8),intent(inout)         :: Smats(:,:,:,:,:,:)
    complex(8),intent(inout)         :: Sreal(:,:,:,:,:,:)
    character(len=30)                :: suffix
    integer                          :: ilat,ispin,iorb
    real(8),dimension(:),allocatable :: wm,wr

    if(size(Smats,2)/=Nspin) stop "save_sigma: error in dim 2. Nspin"
    if(size(Smats,3)/=Nspin) stop "save_sigma: error in dim 3. Nspin"
    if(size(Smats,4)/=Norb) stop "save_sigma: error in dim 4. Norb"
    if(size(Smats,5)/=Norb) stop "save_sigma: error in dim 5. Norb"

    if(size(Sreal,2)/=Nspin) stop "save_sigma: error in dim 2. Nspin"
    if(size(Sreal,3)/=Nspin) stop "save_sigma: error in dim 3. Nspin"
    if(size(Sreal,4)/=Norb) stop "save_sigma: error in dim 4. Norb"
    if(size(Sreal,5)/=Norb) stop "save_sigma: error in dim 5. Norb"

    allocate(wm(Lmats))
    allocate(wr(Lreal))

    wm = pi/beta*(2*arange(1,Lmats)-1)
    wr = linspace(wini,wfin,Lreal)
    write(LOGfile,*)"write spin-orbital diagonal elements:"
    do ispin=1,Nspin
       do iorb=1,Norb
          suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
          call store_data("LSigma"//trim(suffix),Smats(:,ispin,ispin,iorb,iorb,:),wm)
       enddo
    enddo
    do ispin=1,Nspin
       do iorb=1,Norb
          suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
          call store_data("LSigma"//trim(suffix),Sreal(:,ispin,ispin,iorb,iorb,:),wr)
       enddo
    enddo

  end subroutine save_sigma



  !----------------------------------------------------------------------------------------!
  ! purpose: read the matsubara local self-energy from disk
  !----------------------------------------------------------------------------------------!
  subroutine read_sigma_mats(Smats)
    complex(8),intent(inout)         :: Smats(:,:,:,:,:,:)
    character(len=30)                :: suffix
    integer                          :: ilat,ispin,iorb
    real(8),dimension(:),allocatable :: wm,wr

    if(size(Smats,2)/=Nspin) stop "save_sigma: error in dim 2. Nspin"
    if(size(Smats,3)/=Nspin) stop "save_sigma: error in dim 3. Nspin"
    if(size(Smats,4)/=Norb) stop "save_sigma: error in dim 4. Norb"
    if(size(Smats,5)/=Norb) stop "save_sigma: error in dim 5. Norb"

    allocate(wm(Lmats))

    wm = pi/beta*(2*arange(1,Lmats)-1)
    write(LOGfile,*)"write spin-orbital diagonal elements:"
    do ispin=1,Nspin
       do iorb=1,Norb
          suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
          call read_data("LSigma"//trim(suffix),Smats(:,ispin,ispin,iorb,iorb,:),wm)
       enddo
    enddo

  end subroutine read_sigma_mats


  !----------------------------------------------------------------------------------------!
  ! purpose: read the real local self-energy from disk
  !----------------------------------------------------------------------------------------!
  subroutine read_sigma_real(Sreal)
    complex(8),intent(inout)         :: Sreal(:,:,:,:,:,:)
    character(len=30)                :: suffix
    integer                          :: ilat,ispin,iorb
    real(8),dimension(:),allocatable :: wm,wr

    if(size(Sreal,2)/=Nspin) stop "save_sigma: error in dim 2. Nspin"
    if(size(Sreal,3)/=Nspin) stop "save_sigma: error in dim 3. Nspin"
    if(size(Sreal,4)/=Norb) stop "save_sigma: error in dim 4. Norb"
    if(size(Sreal,5)/=Norb) stop "save_sigma: error in dim 5. Norb"

    allocate(wr(Lreal))

    wr = linspace(wini,wfin,Lreal)
    write(LOGfile,*)"write spin-orbital diagonal elements:"
    do ispin=1,Nspin
       do iorb=1,Norb
          suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
          call read_data("LSigma"//trim(suffix),Sreal(:,ispin,ispin,iorb,iorb,:),wr)
       enddo
    enddo

  end subroutine read_sigma_real


  !----------------------------------------------------------------------------------------!
  ! purpose: read the local self-energy from disk
  !----------------------------------------------------------------------------------------!
  subroutine read_sigma(Smats,Sreal)
    complex(8),intent(inout)         :: Smats(:,:,:,:,:,:)
    complex(8),intent(inout)         :: Sreal(:,:,:,:,:,:)
    character(len=30)                :: suffix
    integer                          :: ilat,ispin,iorb
    real(8),dimension(:),allocatable :: wm,wr

    if(size(Smats,2)/=Nspin) stop "save_sigma: error in dim 2. Nspin"
    if(size(Smats,3)/=Nspin) stop "save_sigma: error in dim 3. Nspin"
    if(size(Smats,4)/=Norb) stop "save_sigma: error in dim 4. Norb"
    if(size(Smats,5)/=Norb) stop "save_sigma: error in dim 5. Norb"

    if(size(Sreal,2)/=Nspin) stop "save_sigma: error in dim 2. Nspin"
    if(size(Sreal,3)/=Nspin) stop "save_sigma: error in dim 3. Nspin"
    if(size(Sreal,4)/=Norb) stop "save_sigma: error in dim 4. Norb"
    if(size(Sreal,5)/=Norb) stop "save_sigma: error in dim 5. Norb"

    allocate(wm(Lmats))
    allocate(wr(Lreal))

    wm = pi/beta*(2*arange(1,Lmats)-1)
    wr = linspace(wini,wfin,Lreal)
    write(LOGfile,*)"write spin-orbital diagonal elements:"
    do ispin=1,Nspin
       do iorb=1,Norb
          suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
          call read_data("LSigma"//trim(suffix),Smats(:,ispin,ispin,iorb,iorb,:),wm)
       enddo
    enddo
    do ispin=1,Nspin
       do iorb=1,Norb
          suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
          call read_data("LSigma"//trim(suffix),Sreal(:,ispin,ispin,iorb,iorb,:),wr)
       enddo
    enddo

  end subroutine read_sigma



  !----------------------------------------------------------------------------------------!
  ! purpose: evaluate 
  !  - conductance (without vertex corrections) 
  !  - bias-driven current
  ! for a nanostructure on the real axis, given the non-local Green's function 
  ! and the L/R hybridization matrix, of size [Nlat*Nspin*Norb**2*Lreal]
  !----------------------------------------------------------------------------------------!
  subroutine ed_transport(Gret)
    complex(8),intent(inout)              :: Gret(:,:,:,:,:,:,:)  ![Nlat][Nlat][Nspin][Nspin][Norb][Norb][Lreal]
    ! auxiliary variables for matmul        
    complex(8),dimension(:,:),allocatable :: GR,HR,GA,HL,Re,Le,Te ![Nlat*Norb]**2
    complex(8),dimension(:,:),allocatable :: transe               ![Nspin][Lreal]
    !
    integer,dimension(:,:),allocatable    :: rmask,lmask          ![Nlat]**2
    !
    real(8),dimension(:),allocatable      :: wr
    !
    real(8),dimension(:),allocatable      :: jcurr                ![Nspin]
    real(8)                               :: lbias,rbias,dE
    !
    integer                               :: ilat,jlat,ispin,jspin,iorb,jorb,io,jo,is,js,i,Nlso,Nlo
    integer                               :: unit,unit_in,unit_out,eof,lfile
    character(len=30)                     :: suffix
    !
    Nlso = Nlat*Nspin*Norb
    Nlo  = Nlat*Norb
    !
    allocate(wr(Lreal))
    wr = linspace(wini,wfin,Lreal)

    ! allocate variables for matrix-matrix multiplication
    allocate(GR(Nlo,Nlo));GR=zero
    allocate(HR(Nlo,Nlo));HR=zero
    allocate(GA(Nlo,Nlo));GA=zero
    allocate(HL(Nlo,Nlo));HL=zero
    allocate(Re(Nlo,Nlo));Re=zero
    allocate(Le(Nlo,Nlo));Le=zero
    allocate(Te(Nlo,Nlo));Te=zero

    ! set masks
    allocate(lmask(Nlat,Nlat),rmask(Nlat,Nlat))
    lmask(:,:)=0
    rmask(:,:)=0
    lfile = file_length("lmask.in")
    unit = free_unit()
    open(unit,file='lmask.in',status='old')
    do i=1,lfile
       read(unit,*) ilat, jlat
       ilat=ilat+1
       jlat=jlat+1
       lmask(ilat,jlat)=1
       write(6,*) ilat,jlat,lmask(ilat,jlat)
    enddo
    lfile = file_length("rmask.in")
    unit = free_unit()
    open(unit,file='rmask.in',status='old')
    do i=1,lfile
       read(unit,*) ilat, jlat
       ilat=ilat+1
       jlat=jlat+1
       rmask(ilat,jlat)=1
       write(6,*) ilat,jlat,rmask(ilat,jlat)
    enddo

    ! allocate spin-resolved transmission coefficient
    allocate(transe(Nspin,Lreal))

    do ispin=1,Nspin
       do i=1,Lreal
          ! fill auxiliary matrix [Nlso]**2
          do ilat=1,Nlat
             do jlat=1,Nlat
                do iorb=1,Norb
                   do jorb=1,Norb
                      io = iorb +  (ilat-1)*Norb
                      jo = jorb +  (jlat-1)*Norb
                      is = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb !== ilat
                      js = jorb + (ispin-1)*Norb + (jlat-1)*Nspin*Norb !== jlat
                      !
                      ! retarded Green's function
                      GR(io,jo)=Gret(ilat,jlat,ispin,ispin,iorb,jorb,i)
                      !
                      ! set \Gamma matrix for L/R according to masks to select L-subset OR R-subset
                      ! R-subset
                      HR(io,jo)=zero
                      if(rmask(ilat,jlat)==1) HR(io,jo) = cmplx(2.d0*dimag(Hyb_real(is,js,i)),0d0)
                      ! L-subset
                      HL(io,jo)=zero
                      if(lmask(ilat,jlat)==1) HL(io,jo) = cmplx(2.d0*dimag(Hyb_real(is,js,i)),0d0)
                   enddo
                enddo
             enddo
          enddo
          ! advanced Green's function
          GA=conjg(transpose(GR))
          !
          ! get transmission function as T(ispin,i)=Tr[Gadvc*Hybl*Gret*Hybr]
          Re = matmul(GR,HR)
          Le = matmul(GA,HL)
          Te = matmul(Le,Re)
          transe(ispin,i) = trace_matrix(Te,Nlo)
       enddo
       suffix="_s"//reg(txtfy(ispin))//"_realw.ed"
       call store_data("Te"//trim(suffix),transe(ispin,:),wr)
    enddo
    
    deallocate(GR,HR,GA,HL)
    deallocate(rmask,lmask)
    deallocate(Re,Le)



    if(jbias)then
       !
       ! evaluate spin-resolved current as:
       ! J = \int_{-\infty}^{\infty} de T(e)*(f_L(e)-f_R(e))
       ! actually this formula is wrong, because in the zero-bias limit the current should be zero 
       ! what matters is the integral over the eenrgy window included 
       ! between the chemical potentials of the L/R leads: i.e., the formula should be 
       ! allocate spin-resolved current (transmission coefficient integrated)
       allocate(jcurr(Nspin));jcurr=0.d0
     
       unit_in = free_unit()
       open(unit_in,file='jbias.in',status='old')
       unit_out= free_unit()
       open(unit_out,file="jbias.ed")
       do
          read(unit_in,*,IOSTAT=EOF)lbias,rbias
          if(EOF<0)exit
          !
          ! write L/R bias voltages
          write(unit_out,'(2f16.9)',advance='no')lbias,rbias
          !
          dE=abs(wfin-wini)/Lreal
          jcurr=0.d0
          do ispin=1,Nspin
              do i=1,Lreal
                 jcurr(ispin) = jcurr(ispin) + transe(ispin,i)*dE* &
                                (fermi(wr(i)-lbias,beta)-fermi(wr(i)-rbias,beta))
              enddo
              !
              ! write spin-resolved current
              write(unit_out,'(1f16.9)',advance='no')jcurr(ispin)
          enddo
          write(unit_out,*) ! newline
       enddo
       close(unit_in)
       close(unit_out)

       deallocate(jcurr)

    endif



    deallocate(Te)

  end subroutine ed_transport


  !----------------------------------------------------------------------------------------!
  ! purpose: define the hybridization matrix of size [Nlat][Nlat][Nspin][Norb][Norb][Lreal] 
  ! reading the parameters from an input file
  !----------------------------------------------------------------------------------------!
  subroutine set_hyb()
    integer                                 :: ilat,jlat,ispin,jspin,iorb,jorb,io,jo,i,Nlso
    integer                                 :: k,kmax
    integer                                 :: unit,l,lfile
    ! leads
    integer                                 :: ikind,ilead,Nlead
    real(8)                                 :: D,mu,V,epsk
    complex(8)                              :: ksum
    complex(8),dimension(:,:,:),allocatable :: lead_real,lead_mats ![Nlead][Nspin][Lreal/Lmats]
    real(8),dimension(:),allocatable        :: wr,wm
    character(50)                           :: suffix
    !
    Nlso = Nlat*Nspin*Norb
    !
    kmax=10000
    !
    allocate(wm(Lmats),wr(Lreal))
    wm = pi/beta*(2*arange(1,Lmats)-1)
    wr = linspace(wini,wfin,Lreal)

    ! initialize embedding hybridization function
    allocate(Hyb_mats(Nlso,Nlso,Lmats))
    allocate(Hyb_real(Nlso,Nlso,Lreal))
    Hyb_mats=zero
    Hyb_real=zero

    ! determine Nleads & allocate lead matrix
    lfile = file_length("lead.in")
    unit = free_unit()
    open(unit,file='lead.in',status='old')
    read(unit,*)Nlead
    allocate(lead_real(Nlead,Nspin,Lreal))
    allocate(lead_mats(Nlead,Nspin,Lmats))
    lead_real(:,:,:)=zero
    ! lead file setup lead by kind, half-bandwitdh (D) and chemical potential (mu)
    do l=1,lfile-1 ! because Nlead was read separately above
       read(unit,*) ilead, ispin, D, mu, ikind
       ilead=ilead+1
       ispin=ispin+1
       if(ilead>Nlead)stop "set_hyb error: in input file 'lead.in' ilead > Nlead"
       if(ispin>Nspin)stop "set_hyb error: non-spin degenerate leads for Nspin=1 calculation"
       suffix="_ilead"//reg(txtfy(ilead))//"_s"//reg(txtfy(ispin))
       !
       ! set the lead's Green's function, depending on ikind
       if(ikind==0)then
          ! flat DOS (analytic)
          write(*,*) "flat DOS (analytic)"
          lead_real(ilead,ispin,:)=dcmplx( log(abs((D+wr(:)+mu)/(D-wr(:)-mu))) , -pi*heaviside(D-abs(wr(:)+mu)) )/(2d0*D)
       elseif(ikind==1)then
          ! flat DOS (k-sum)
          write(*,*) "flat DOS (k-sum)"
          do i=1,Lreal
             ksum=zero
             do k=1,kmax
                epsk = -D + 2*D/kmax*(k-1)
                ksum = ksum + 1d0/( wr(i)+xi*eps+mu - epsk)
             enddo
             lead_real(ilead,ispin,i)=ksum/kmax
          enddo
       elseif(ikind==2)then
          ! broad-band limit
          write(*,*) "broad-band limit (analytic)" 
          lead_real(ilead,ispin,:)=dcmplx(0d0,-1.d0*pi) ! to ensure DOS normalization
       elseif(ikind==3)then
          ! semicircular DOS (k-sum) 
          write(*,*) "semicircular DOS (k-sum)"
          do i=1,Lreal
             ksum=zero
             do k=1,kmax
                epsk = -D + 2*D/kmax*(k-1)
                ksum = ksum + (4d0/(pi*kmax))*sqrt(1d0-(epsk/D)**2)/( wr(i)+xi*eps+mu - epsk)
             enddo
             lead_real(ilead,ispin,i)=ksum
          enddo
       elseif(ikind==4)then
          ! readin hk DOS
          write(*,*) "readin hk DOS to be implemented and benchmarked w/ w2dynamics"
          stop
       else
          write(*,*) "set_hyb error: in input file 'lead.in' invalid ikind"
          stop
       endif
       ! store lead(s) DOS on disk
       suffix="_ilead"//reg(txtfy(ilead))//"_s"//reg(txtfy(ispin))//"_realw.ed"
       call store_data("lead"//trim(suffix),lead_real(ilead,ispin,:),wr)
       call get_matsubara_gf_from_dos(wr,lead_real(ilead,ispin,:),lead_mats(ilead,ispin,:),beta)
       suffix="_ilead"//reg(txtfy(ilead))//"_s"//reg(txtfy(ispin))//"_iw.ed"
       call store_data("lead"//trim(suffix),lead_mats(ilead,ispin,:),wm)
    enddo
    close(unit)
    !
    ! hybridization file determine lead-site connections 
    lfile = file_length("vij.in")
    unit = free_unit()
    open(unit,file='vij.in',status='old')
    do i=1,lfile
       read(unit,*) ilat, iorb, jlat, jorb, ilead, V
       ilat=ilat+1
       iorb=iorb+1
       jlat=jlat+1
       jorb=jorb+1
       ilead=ilead+1
       if((iorb>Norb).or.(jorb>Norb))stop "set_hyb error: in input file 'vij.in' i/jorb > Norb"
       if((ilat>Nlat).or.(jlat>Nlat))stop "set_hyb error: in input file 'vij.in' i/jlat > Nlat"
       if(ilead>Nlead)stop "set_hyb error: in input file 'vij.in' ilead > Nlead"
       do ispin=1,Nspin
          ! get stride and set matrix element: no symmetrization
          io = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb !== ilat
          jo = jorb + (ispin-1)*Norb + (jlat-1)*Nspin*Norb !== jlat
          Hyb_real(io,jo,:)=Hyb_real(io,jo,:)+lead_real(ilead,ispin,:)*V**2
          Hyb_mats(io,jo,:)=Hyb_mats(io,jo,:)+lead_mats(ilead,ispin,:)*V**2
          suffix="_i"//reg(txtfy(ilat))//"_j"//reg(txtfy(jlat))//"_s"//reg(txtfy(ispin))//"_realw.ed"
          call store_data("Hyb"//trim(suffix),Hyb_real(io,jo,:),wr)
       enddo
    enddo
    close(unit)
    deallocate(lead_real,lead_mats,wr,wm)
    
  end subroutine set_hyb


  function trace_matrix(M,dim) result(tr)
    integer                       :: dim
    complex(8),dimension(dim,dim) :: M
    complex(8) :: tr
    integer                       :: i
    tr=dcmplx(0d0,0d0)
    do i=1,dim
       tr=tr+M(i,i)
    enddo
  end function trace_matrix


  !----------------------------------------------------------------------------------------!
  ! purpose: evaluate the effective exchange as in Katsnelson PRB 61, 8906 (2000), eq. (21)
  ! given the non-local Green's function, the local (auxiliary) self-energy S_i = (S_iup-S_ido)/2 
  ! and the fermi distribution on the real axis. 
  ! Jeff_ij = 1/pi Im \int_{-infty}^{infty} S_i(w) G_ijup(w) S_j(w) G_ijdo(w) f(w) dw
  !----------------------------------------------------------------------------------------!
  subroutine ed_get_jeff(Gret,Sret)
    complex(8),intent(inout)                  :: Gret(:,:,:,:,:,:,:) ![Nlat][Nlat][Nspin][Nspin][Norb][Norb][Lreal]
    complex(8),intent(inout)                  :: Sret(:,:,:,:,:,:)   ![Nlat][Nspin][Nspin][Norb][Norb][Lreal]
    complex(8),dimension(:,:,:,:),allocatable :: Saux(:,:,:,:)       ![Nlat][Norb][Norb][Lreal]
    complex(8)                                :: kernel
    real(8),dimension(:,:),allocatable        :: jeff(:,:)           ![Nlat][Nlat]
    real(8),dimension(:),allocatable          :: wr
    integer                                   :: ilat,jlat,iorb,jorb,i
    !
    !I/O
    integer                                   :: unit
    character(len=30)                         :: suffix
    !

    ! check inouts dimensions
    call assert_shape(Gret,[Nlat,Nlat,Nspin,Nspin,Norb,Norb,Lreal],"ed_get_jeff","Gret")
    call assert_shape(Sret,[Nlat,Nspin,Nspin,Norb,Norb,Lreal],"ed_get_jeff","Sret")

    allocate(Saux(Nlat,Norb,Norb,Lreal))
    Saux(:,:,:,:)=zero
    !
    allocate(jeff(Nlat,Nlat))
    jeff(:,:)=zero
    !
    allocate(wr(Lreal))
    wr = linspace(wini,wfin,Lreal)
    !
    write(*,*) "computing effective non-local exchange"
    !
    ! sanity checks
    if(Nspin/=2)stop "ed_get_jeff error: Nspin /= 2"
    if(Norb>1)stop "ed_get_jeff error: Norb > 1 (mutli-orbital case no timplmented yet)"
    !
    ! define auxiliary local spin-less self-energy
    do ilat=1,Nlat
       Saux(ilat,1,1,:) = (Sret(ilat,1,1,1,1,:)-Sret(ilat,2,2,1,1,:))/2.d0
       !Saux(ilat,1,1,:) = one
    enddo
    !unit = free_unit()
    !open(unit,file="Saux.ed")
    !do ilat=1,Nlat
    !   do i=1,Lreal
    !      write(unit,'(i5,7f16.9)')ilat,wr(i),Saux(ilat,1,1,i),Sret(ilat,1,1,1,1,i),Sret(ilat,2,2,1,1,i)
    !   enddo
    !enddo
    !close(unit)
    !
    ! compute effective exchange
    do ilat=1,Nlat
       do jlat=1,Nlat
          ! perform integral over frequency
          kernel=0.d0
          do i=1,Lreal
             ! jeff kernel: non-local Green's function and fermi function convolution
             !              in the multi-orbital case: trace over the orbitals required
             kernel = kernel + Saux(ilat,1,1,i)*Gret(ilat,jlat,1,1,1,1,i)*Saux(jlat,1,1,i)*Gret(jlat,ilat,2,2,1,1,i)*fermi(wr(i),beta)
          enddo
          jeff(ilat,jlat) = 1.d0*dimag(kernel)/pi
       enddo
    enddo
    !
    ! write effective exchange on disk
    unit = free_unit()
    open(unit,file="jeff_ij.ed")
    do ilat=1,Nlat
       do jlat=1,Nlat
          write(unit,*)ilat,jlat,jeff(ilat,jlat)
       enddo
    enddo
    close(unit)

    deallocate(Saux,jeff,wr) 

  end subroutine ed_get_jeff


  !----------------------------------------------------------------------------------------!
  ! purpose: evaluate the non-local bare static spin susceptibility
  ! given the non-local Green's function and the fermi distribution on the real axis. 
  ! chi0_ij = 1/pi Im \int_{-infty}^{infty} G_ij(w) G_ji(w) f(w) dw
  !----------------------------------------------------------------------------------------!
  subroutine ed_get_chi0ij(Gret)
    complex(8),intent(inout)                  :: Gret(:,:,:,:,:,:,:) ![Nlat][Nlat][Nspin][Nspin][Norb][Norb][Lreal]
    complex(8)                                :: kernel
    real(8),dimension(:,:),allocatable        :: jeff(:,:)           ![Nlat][Nlat]
    real(8),dimension(:),allocatable          :: wr
    integer                                   :: ilat,jlat,iorb,jorb,i
    !
    !I/O
    integer                                   :: unit
    character(len=30)                         :: suffix
    !

    ! check inouts dimensions
    call assert_shape(Gret,[Nlat,Nlat,Nspin,Nspin,Norb,Norb,Lreal],"ed_get_jeff","Gret")

    allocate(jeff(Nlat,Nlat))
    jeff(:,:)=zero
    !
    allocate(wr(Lreal))
    wr = linspace(wini,wfin,Lreal)
    !
    write(*,*) "computing bare static non-local susceptibility"
    !
    ! sanity checks
    if(Nspin/=1)stop "ed_get_chi0ij error: Nspin /= 1"
    if(Norb>1)stop "ed_get_chi0ij error: Norb > 1 (mutli-orbital case no timplmented yet)"
    !
    ! compute bare static non-local susceptibility
    do ilat=1,Nlat
       do jlat=1,Nlat
          ! perform integral over frequency
          kernel=0.d0
          do i=1,Lreal
             ! jeff kernel: non-local Green's function and fermi function convolution
             !              in the multi-orbital case: trace over the orbitals required
             kernel = kernel + Gret(ilat,jlat,1,1,1,1,i)*Gret(jlat,ilat,1,1,1,1,i)*fermi(wr(i),beta)
          enddo
          jeff(ilat,jlat) = 1.d0*dimag(kernel)/pi
       enddo
    enddo
    !
    ! write bare static non-local susceptibility on disk
    unit = free_unit()
    open(unit,file="jeff_ij.ed")
    do ilat=1,Nlat
       do jlat=1,Nlat
          write(unit,*)ilat,jlat,jeff(ilat,jlat)
       enddo
    enddo
    close(unit)

    deallocate(jeff,wr) 

  end subroutine ed_get_chi0ij





  function extract_Hloc(Hk,Nlat,Nspin,Norb) result(Hloc)
    complex(8),dimension(:,:,:)                 :: Hk
    integer                                     :: Nlat,Nspin,Norb
    complex(8),dimension(size(Hk,1),size(Hk,2)) :: Hloc
    !
    integer                                     :: iorb,ispin,ilat,is
    integer                                     :: jorb,jspin,js
    Hloc = zero
    do ilat=1,Nlat
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   is = iorb + (ispin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   js = jorb + (jspin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   Hloc(is,js) = sum(Hk(is,js,:))/size(Hk,3)
                enddo
             enddo
          enddo
       enddo
    enddo
    where(abs(dreal(Hloc))<1.d-9)Hloc=0d0
  end function extract_Hloc




end program ed_nano_isoc
