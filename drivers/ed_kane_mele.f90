program ed_kanemele
  USE DMFT_ED
  USE SCIFOR
  USE DMFT_TOOLS
  implicit none

  integer                                       :: iloop,Lk,Nso,Nlso,Nlat,Nineq
  logical                                       :: converged
  integer                                       :: ispin,ilat!,i,j

  !Bath:
  integer                                       :: Nb
  real(8),allocatable,dimension(:,:)            :: Bath,Bath_prev

  !The local hybridization function:
  complex(8),allocatable,dimension(:,:,:,:,:,:) :: Weiss
  complex(8),allocatable,dimension(:,:,:,:,:,:) :: Smats,Sreal
  complex(8),allocatable,dimension(:,:,:,:,:,:) :: Gmats,Greal

  !hamiltonian input:
  complex(8),allocatable,dimension(:,:,:)       :: Hk
  complex(8),allocatable,dimension(:,:)         :: kmHloc
  complex(8),allocatable,dimension(:,:,:,:,:)   :: Hloc
  real(8),allocatable,dimension(:)              :: Wtk

  integer,allocatable,dimension(:)              :: ik2ix,ik2iy
  real(8),dimension(2)                          :: e1,e2   !real-space lattice basis
  real(8),dimension(2)                          :: bk1,bk2 !reciprocal space lattice basis
  real(8),dimension(2)                          :: d1,d2,d3
  real(8),dimension(2)                          :: a1,a2,a3
  real(8),dimension(2)                          :: pointK,pointKp,bklen

  !variables for the model:
  integer                                       :: Nk,Nkpath
  real(8)                                       :: t1,t2,phi,Mh,wmixing
  character(len=32)                             :: finput
  character(len=32)                             :: hkfile
  logical                                       :: spinsym,neelsym
  !
  real(8),allocatable,dimension(:)              :: dens
  !


  !Parse additional variables && read Input && read H(k)^2x2
  call parse_cmd_variable(finput,"FINPUT",default='inputKANEMELE.conf')
  call parse_input_variable(hkfile,"HKFILE",finput,default="hkfile.in")
  call parse_input_variable(nk,"NK",finput,default=100)
  call parse_input_variable(nkpath,"NKPATH",finput,default=500)
  call parse_input_variable(t1,"T1",finput,default=2d0)
  call parse_input_variable(t2,"T2",finput,default=0d0)
  call parse_input_variable(phi,"PHI",finput,default=pi/2d0)
  call parse_input_variable(mh,"MH",finput,default=0d0)
  call parse_input_variable(wmixing,"WMIXING",finput,default=0.75d0)
  call parse_input_variable(spinsym,"SPINSYM",finput,default=.true.)
  call parse_input_variable(neelsym,"NEELSYM",finput,default=.false.)
  !
  call ed_read_input(trim(finput))


  call add_ctrl_var(beta,"BETA")
  call add_ctrl_var(xmu,"xmu")
  call add_ctrl_var(wini,"wini")
  call add_ctrl_var(wfin,"wfin")
  call add_ctrl_var(eps,"eps")

  if(neelsym.AND.spinsym)stop "Wrong setup from input file: NEELSYM=T not with SPINSYM=T"

  if(Norb/=1.OR.Nspin/=2)stop "Wrong setup from input file: Norb!=1 OR Nspin!=2"
  Nlat=2
  Nso=Nspin*Norb
  Nlso=Nlat*Nso                 !=4 = 2(ineq sites)*2(spin)*1(orb)


  !Lattice basis (a=1; a0=sqrt3*a) is:
  !e_1 = a0 [ sqrt3/2 , 1/2 ] = 3/2a[1, 1/sqrt3]
  !e_2 = a0 [ sqrt3/2 ,-1/2 ] = 3/2a[1,-1/sqrt3]
  e1 = 3d0/2d0*[1d0, 1d0/sqrt(3d0)]
  e2 = 3d0/2d0*[1d0,-1d0/sqrt(3d0)]

  !LATTICE BASIS: nearest neighbor: A-->B, B-->A
  d1= [  1d0/2d0 , sqrt(3d0)/2d0 ]
  d2= [  1d0/2d0 ,-sqrt(3d0)/2d0 ]
  d3= [ -1d0     , 0d0           ]

  !next nearest-neighbor displacements: A-->A, B-->B, cell basis
  a1 = d1-d3                    !3/2*a[1,1/sqrt3]
  a2 = d2-d3                    !3/2*a[1,-1/sqrt3]
  a3 = d1-d2

  pointK = [2*pi/3, 2*pi/3/sqrt(3d0)]
  pointKp= [2*pi/3,-2*pi/3/sqrt(3d0)]



  !RECIPROCAL LATTICE VECTORS:
  bklen=2d0*pi/3d0
  bk1=bklen*[ 1d0, sqrt(3d0)] 
  bk2=bklen*[ 1d0,-sqrt(3d0)]
  call TB_set_bk(bkx=bk1,bky=bk2)


  !Build the Hamiltonian on a grid or on path
  call build_hk(trim(hkfile))
  allocate(Hloc(Nlat,Nspin,Nspin,Norb,Norb));Hloc=zero
  Hloc = lso2nnn_reshape(kmHloc,Nlat,Nspin,Norb)


  !Allocate Weiss Field:
  allocate(Weiss(Nlat,Nspin,Nspin,Norb,Norb,Lmats));Weiss=zero
  allocate(Smats(Nlat,Nspin,Nspin,Norb,Norb,Lmats));Smats=zero
  allocate(Gmats(Nlat,Nspin,Nspin,Norb,Norb,Lmats));Gmats=zero
  allocate(Sreal(Nlat,Nspin,Nspin,Norb,Norb,Lreal));Sreal=zero
  allocate(Greal(Nlat,Nspin,Nspin,Norb,Norb,Lreal));Greal=zero


  !Setup solver
  Nb=get_bath_dimension()
  allocate(Bath(Nlat,Nb))
  allocate(Bath_prev(Nlat,Nb))
  call ed_init_solver(Bath,Hloc)


  !DMFT loop
  iloop=0;converged=.false.
  do while(.not.converged.AND.iloop<nloop)
     iloop=iloop+1
     call start_loop(iloop,nloop,"DMFT-loop")
     !
     !Solve the EFFECTIVE IMPURITY PROBLEM (first w/ a guess for the bath)
     call ed_solve(Bath,Hloc)
     call ed_get_sigma_matsubara(Smats,Nlat)
     !
     ! Smats(2,2,2,:,:,:) = -Smats(1,1,1,:,:,:) !sub_B(dw,dw) = -sub_A(up,up)
     ! Smats(2,1,1,:,:,:) = -Smats(1,2,2,:,:,:) !sub_B(up,up) = -sub_A(dw,dw)
     !
     ! compute the local gf:
     call dmft_gloc_matsubara(Hk,Wtk,Gmats,Smats)
     !
     ! compute the Weiss field (only the Nineq ones)
     if(cg_scheme=='weiss')then
        call dmft_weiss(Gmats,Smats,Weiss,Hloc)
     else
        call dmft_delta(Gmats,Smats,Weiss,Hloc)
     endif
     !
     !Fit the new bath, starting from the old bath + the supplied Weiss
     call ed_chi2_fitgf(Bath,Weiss,Hloc,ispin=1)
     if(spinsym)then
        call spin_symmetrize_bath(bath,save=.true.)
     else
        call ed_chi2_fitgf(Bath,Weiss,Hloc,ispin=2)
     endif
     !
     !MIXING:
     if(iloop>1)Bath=wmixing*Bath + (1.d0-wmixing)*Bath_prev
     Bath_prev=Bath
     !
     converged = check_convergence(Weiss(:,1,1,1,1,:),dmft_error,nsuccess,nloop)
     !
     call end_loop
  enddo
  call dmft_print_gf_matsubara(Gmats,"Gmats",iprint=4)


  !Extract and print retarded self-energy and Green's function 
  call ed_get_sigma_real(Sreal,Nlat)
  call dmft_gloc_realaxis(Hk,Wtk,Greal,Sreal)
  call dmft_print_gf_realaxis(Greal,"Greal",iprint=4)



contains



  !---------------------------------------------------------------------
  !PURPOSE: Get Kane Mele Model Hamiltonian
  !---------------------------------------------------------------------
  subroutine build_hk(file)
    character(len=*),optional                              :: file
    integer                                                :: i,j,ik
    integer                                                :: ix,iy
    real(8)                                                :: kx,ky  
    integer                                                :: iorb,jorb
    integer                                                :: isporb,jsporb
    integer                                                :: ispin,jspin
    integer                                                :: unit
    complex(8),dimension(Nlat,Nspin,Nspin,Norb,Norb,Lmats) :: Gmats
    complex(8),dimension(Nlat,Nspin,Nspin,Norb,Norb,Lreal) :: Greal
    real(8),dimension(:,:),allocatable                     :: KPath
    !
    Lk= Nk*Nk
    write(LOGfile,*)"Build H(k) Kane-Mele:",Lk
    write(LOGfile,*)"# of SO-bands     :",Nlso
    !
    if(allocated(Hk))deallocate(Hk)
    if(allocated(wtk))deallocate(wtk)
    !
    allocate(Hk(Nlso,Nlso,Lk));Hk=zero
    allocate(wtk(Lk));Wtk=0d0
    !
    !
    call TB_build_model(Hk,hk_kanemele_model,Nlso,[Nk,Nk],wdos=.false.)
    Wtk = 1d0/Lk
    !
    !
    if(present(file))then
       call TB_write_hk(Hk,"Hkrfile_kanemele.data",&
            No=Nlso,&
            Nd=Norb,&
            Np=0,&
            Nineq=1,&
            Nkvec=[Nk,Nk])
    endif
    !
    allocate(kmHloc(Nlso,Nlso))
    kmHloc = sum(Hk(:,:,:),dim=3)/Lk
    where(abs(dreal(kmHloc))<1.d-4)kmHloc=0d0
    call TB_write_Hloc(kmHloc)
    call TB_write_Hloc(kmHloc,'Hloc.txt')
    !
    !
    allocate(Kpath(4,2))
    KPath(1,:)=[0,0]
    KPath(2,:)=pointK
    Kpath(3,:)=pointKp
    KPath(4,:)=[0d0,0d0]
    call TB_Solve_model(hk_kanemele_model,Nlso,KPath,Nkpath,&
         colors_name=[red1,blue1,red1,blue1],&
         points_name=[character(len=10) :: "G","K","K`","G"],&
         file="Eigenbands.nint")
    !
    !Build the local GF:
    call dmft_gloc_matsubara(Hk,Wtk,Gmats,zeros(Nlat,Nspin,Nspin,Norb,Norb,Lmats))    
    call dmft_print_gf_matsubara(Gmats,"LG0",iprint=4)
    call dmft_gloc_realaxis(Hk,Wtk,Greal,zeros(Nlat,Nspin,Nspin,Norb,Norb,Lreal))
    call dmft_print_gf_realaxis(Greal,"LG0",iprint=4)
    !
  end subroutine build_hk



  !--------------------------------------------------------------------!
  !Kane-Mele HAMILTONIAN:
  !--------------------------------------------------------------------!
  function hk_kanemele_model(kpoint,Nlso) result(hk)
    real(8),dimension(:)            :: kpoint
    integer                         :: Nlso
    complex(8),dimension(2,2)       :: hk11,hk22
    complex(8),dimension(Nlso,Nlso) :: hk
    real(8)                         :: h0,hx,hy,hz
    real(8)                         :: kdotd(3),kdota(3)
    !(k.d_j)
    kdotd(1) = dot_product(kpoint,d1)
    kdotd(2) = dot_product(kpoint,d2)
    kdotd(3) = dot_product(kpoint,d3)
    !(k.a_j)
    kdota(1) = dot_product(kpoint,a1)
    kdota(2) = dot_product(kpoint,a2)
    kdota(3) = dot_product(kpoint,a3)
    !
    h0 = 2*t2*cos(phi)*sum( cos(kdota(:)) )
    hx =-t1*sum( cos(kdotd(:)) )
    hy =-t1*sum( sin(kdotd(:)) )
    hz = 2*t2*sin(phi)*sum( sin(kdota(:)) )
    !
    hk11 = h0*pauli_0 + hx*pauli_x + hy*pauli_y + hz*pauli_z + Mh*pauli_z
    !
    hk22 = h0*pauli_0 + hx*pauli_x - hy*pauli_y - hz*pauli_z + Mh*pauli_z
    !
    hk          = zero
    hk(1:2,1:2) = hk11
    hk(3:4,3:4) = hk22
    !
  end function hk_kanemele_model














end program ed_kanemele



