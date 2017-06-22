MODULE ED_CHI2FIT
  USE SF_CONSTANTS
  USE SF_OPTIMIZE, only:fmin_cg,fmin_cgplus,fmin_cgminimize
  USE SF_LINALG,   only:eye,zeye,inv,inv_her
  USE SF_IOTOOLS,  only:reg,free_unit,txtfy
  USE SF_ARRAYS,   only:arange
  USE SF_MISC,     only:assert_shape 
  USE ED_INPUT_VARS
  USE ED_VARS_GLOBAL
  USE ED_AUX_FUNX
  USE ED_BATH
  USE ED_BATH_FUNCTIONS
#ifdef _MPI
  USE MPI
  USE SF_MPI
#endif


  implicit none
  private

  interface ed_chi2_fitgf
     !THese are strictly serial:
     module procedure chi2_fitgf_generic_normal
     module procedure chi2_fitgf_generic_normal_NOSPIN
     module procedure chi2_fitgf_generic_superc
     module procedure chi2_fitgf_generic_superc_NOSPIN

     module procedure ed_fit_bath_sites_normal
     module procedure ed_fit_bath_sites_normal_1b
     module procedure ed_fit_bath_sites_normal_mb
     module procedure ed_fit_bath_sites_superc
     module procedure ed_fit_bath_sites_superc_1b
     module procedure ed_fit_bath_sites_superc_mb

#ifdef _MPI
     module procedure chi2_fitgf_generic_normal_mpi
     module procedure chi2_fitgf_generic_normal_NOSPIN_mpi
     module procedure chi2_fitgf_generic_superc_mpi
     module procedure chi2_fitgf_generic_superc_NOSPIN_mpi

     module procedure ed_fit_bath_sites_normal_mpi
     module procedure ed_fit_bath_sites_normal_1b_mpi
     module procedure ed_fit_bath_sites_normal_mb_mpi
     module procedure ed_fit_bath_sites_superc_mpi
     module procedure ed_fit_bath_sites_superc_1b_mpi
     module procedure ed_fit_bath_sites_superc_mb_mpi
#endif
  end interface ed_chi2_fitgf


  public :: ed_chi2_fitgf


  integer                               :: Ldelta
  complex(8),dimension(:,:),allocatable :: Gdelta
  complex(8),dimension(:,:),allocatable :: Fdelta
  real(8),dimension(:),allocatable      :: Xdelta,Wdelta
  integer                               :: totNorb,totNspin,totNso
  integer,dimension(:),allocatable      :: getIorb,getJorb,getIspin,getJspin
  integer                               :: Orb_indx,Spin_indx,Spin_mask
  type(effective_bath)                  :: chi2_bath
  integer                               :: cg_iter_count=0

  integer                               :: MPI_RANK=0
  integer                               :: MPI_SIZE=1
  logical                               :: MPI_MASTER=.true.
  integer                               :: MPI_IERR



contains


  !+----------------------------------------------------------------------+
  !PURPOSE  : Chi^2 fit of the G0/Delta 
  !
  ! - CHI2_FITGF_GENERIC_NORMAL interface for the normal case 
  ! - CHI2_FITGF_GENERIC_SUPERC interface for the superconducting case 
  !   * CHI2_FITGF_GENERIC_NORMAL_NOSPIN interface to fixed spin input
  !   * CHI2_FITGF_GENERIC_SUPERC_NOSPIN interface to fixed spin input
  !+----------------------------------------------------------------------+
  !+----------------------------------------------------------------------+
  !                                NORMAL                                 !
  !+----------------------------------------------------------------------+
  subroutine chi2_fitgf_generic_normal(fg,bath,ispin)
    complex(8),dimension(:,:,:,:,:) :: fg ![Nspin][Nspin][Norb][Norb][Niw] 
    real(8),dimension(:)            :: bath
    integer,optional                :: ispin
    integer                         :: ispin_
    ispin_=1;if(present(ispin))ispin_=ispin
    call assert_shape(fg,[Nspin,Nspin,Norb,Norb,size(fg,5)],"chi2_fitgf_generic_normal","fg")
    !
    select case(cg_method)
    case default
       stop "ED Error: cg_method > 2"
    case (0)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"\Chi2 fit with CG-nr and CG-weight: ",cg_weight," on: ",cg_scheme
    case (1)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"\Chi2 fit with CG-minimize and CG-weight: ",cg_weight," on: ",cg_scheme
    case (2)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"\Chi2 fit with CG-plus and CG-weight: ",cg_weight," on: ",cg_scheme
    end select
    !
    select case(bath_type)
    case default
       select case(ed_mode)
       case ("normal")
          call chi2_fitgf_normal_normal(fg(ispin_,ispin_,:,:,:),bath,ispin_)
       case ("nonsu2")
          if(present(ispin))then
             write(LOGfile,"(A)")"chi2_fitgf_generic_normal WARNING: ed_mode=nonsu2 but only ONE spin orientation required. disregarded"
             call sleep(1)
          endif
          call chi2_fitgf_normal_nonsu2(fg(:,:,:,:,:),bath)
       case default
          stop "chi2_fitgf ERROR: ed_mode!=normal/nonsu2 but only NORMAL component is provided"
       end select
    case ("hybrid")
       select case(ed_mode)
       case ("normal")
          call chi2_fitgf_hybrid_normal(fg(ispin_,ispin_,:,:,:),bath,ispin_)
       case ("nonsu2")
          if(present(ispin))then
             write(LOGfile,"(A)")"chi2_fitgf_generic_normal WARNING: ed_mode=nonsu2 but only ONE spin orientation required. disregarded"
             call sleep(1)
          endif
          call chi2_fitgf_hybrid_nonsu2(fg(:,:,:,:,:),bath)
       case default
          stop "chi2_fitgf ERROR: ed_mode!=normal/nonsu2 but only NORMAL component is provided" 
       end select
    case ("replica")
       call chi2_fitgf_replica(fg,bath)
    end select
    !set trim_state_list to true after the first fit has been done: this 
    !marks the ends of the cycle of the 1st DMFT loop.
    trim_state_list=.true.
  end subroutine chi2_fitgf_generic_normal

  subroutine chi2_fitgf_generic_normal_NOSPIN(fg,bath,ispin)
    complex(8),dimension(:,:,:)                      :: fg ![Norb][Norb][Niw]
    complex(8),dimension(Nspin,Nspin,Norb,Norb,Lfit) :: fg_
    real(8),dimension(:),intent(inout)               :: bath
    integer,optional                                 :: ispin
    integer                                          :: ispin_
    ispin_=1;if(present(ispin))ispin_=ispin
    if(size(fg,3)<Lfit)stop "chi2_fitgf_generic_normal_NOSPIN error: size[fg,3] < Lfit" 
    fg_=zero
    fg_(ispin_,ispin_,:,:,1:Lfit) = fg(:,:,1:Lfit)
    call chi2_fitgf_generic_normal(fg_,bath,ispin_)
  end subroutine chi2_fitgf_generic_normal_NOSPIN



#ifdef _MPI
  subroutine chi2_fitgf_generic_normal_mpi(comm,fg,bath,ispin)
    integer                         :: comm
    complex(8),dimension(:,:,:,:,:) :: fg ![Nspin][Nspin][Norb][Norb][Niw] 
    real(8),dimension(:)            :: bath
    integer,optional                :: ispin
    integer                         :: ispin_
    !
    MPI_MASTER=get_Master_MPI(comm)
    !
    ispin_=1;if(present(ispin))ispin_=ispin
    call assert_shape(fg,[Nspin,Nspin,Norb,Norb,size(fg,5)],"chi2_fitgf_generic_normal","fg")
    select case(cg_method)
    case default
       stop "ED Error: cg_method > 2"
    case (0)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"master: Chi^2 fit with CG-nr and CG-weight: ",cg_weight," on: ",cg_scheme
    case (1)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"master: Chi^2 fit with CG-minimize and CG-weight: ",cg_weight," on: ",cg_scheme
    case (2)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"master: Chi^2 fit with CG-plus and CG-weight: ",cg_weight," on: ",cg_scheme
    end select
    !
    if(MPI_MASTER)then
       select case(bath_type)
       case default
          select case(ed_mode)
          case ("normal")
             call chi2_fitgf_normal_normal(fg(ispin_,ispin_,:,:,:),bath,ispin_)
          case ("nonsu2")
             if(present(ispin))then
                write(LOGfile,"(A)")"chi2_fitgf_generic_normal WARNING: ed_mode=nonsu2 but only ONE spin orientation required. disregarded"
                call sleep(1)
             endif
             call chi2_fitgf_normal_nonsu2(fg(:,:,:,:,:),bath)
          case default
             stop "chi2_fitgf ERROR: ed_mode!=normal/nonsu2 but only NORMAL component is provided"
          end select
       case ("hybrid")
          select case(ed_mode)
          case ("normal")
             call chi2_fitgf_hybrid_normal(fg(ispin_,ispin_,:,:,:),bath,ispin_)
          case ("nonsu2")
             if(present(ispin))then
                write(LOGfile,"(A)")"chi2_fitgf_generic_normal WARNING: ed_mode=nonsu2 but only ONE spin orientation required. disregarded"
                call sleep(1)
             endif
             call chi2_fitgf_hybrid_nonsu2(fg(:,:,:,:,:),bath)
          case default
             stop "chi2_fitgf ERROR: ed_mode!=normal/nonsu2 but only NORMAL component is provided" 
          end select
       case ("replica")
          call chi2_fitgf_replica(fg,bath)
       end select
    endif
    !
    call Bcast_MPI(comm,bath)
    if(.not.MPI_MASTER)write(LOGfile,"(A)")"Bath received from master node"
    !
    !set trim_state_list to true after the first fit has been done: this 
    !marks the ends of the cycle of the 1st DMFT loop.
    trim_state_list=.true.
  end subroutine chi2_fitgf_generic_normal_mpi

  subroutine chi2_fitgf_generic_normal_NOSPIN_mpi(comm,fg,bath,ispin)
    integer :: comm
    complex(8),dimension(:,:,:)                      :: fg ![Norb][Norb][Niw]
    complex(8),dimension(Nspin,Nspin,Norb,Norb,Lfit) :: fg_
    real(8),dimension(:),intent(inout)               :: bath
    integer,optional                                 :: ispin
    integer                                          :: ispin_
    ispin_=1;if(present(ispin))ispin_=ispin
    if(size(fg,3)<Lfit)stop "chi2_fitgf_generic_normal_NOSPIN error: size[fg,3] < Lfit" 
    fg_=zero
    fg_(ispin_,ispin_,:,:,1:Lfit) = fg(:,:,1:Lfit)
    call chi2_fitgf_generic_normal_mpi(comm,fg_,bath,ispin_)
  end subroutine chi2_fitgf_generic_normal_NOSPIN_mpi
#endif







  !+----------------------------------------------------------------------+
  !                                SUPERC                                 !
  !+----------------------------------------------------------------------+
  subroutine chi2_fitgf_generic_superc(fg,bath,ispin)
    complex(8),dimension(:,:,:,:,:,:) :: fg ![2][Nspin][Nspin][Norb][Norb][Niw]
    real(8),dimension(:)            :: bath
    integer,optional                :: ispin
    integer                         :: ispin_
    ispin_=1;if(present(ispin))ispin_=ispin
    call assert_shape(fg,[2,Nspin,Nspin,Norb,Norb,size(fg,6)],"chi2_fitgf_generic_superc","fg")
    !
    select case(cg_method)
    case default
       stop "ED Error: cg_method > 2"
    case (0)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"\Chi2 fit with CG-nr and CG-weight: ",cg_weight," on: ",cg_scheme
    case (1)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"\Chi2 fit with CG-minimize and CG-weight: ",cg_weight," on: ",cg_scheme
    case (2)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"\Chi2 fit with CG-plus and CG-weight: ",cg_weight," on: ",cg_scheme
    end select
    !
    select case(bath_type)
    case default
       select case(ed_mode)
       case ("superc")
          call chi2_fitgf_normal_superc(fg(:,ispin_,ispin_,:,:,:),bath,ispin_)
       case default
          write(LOGfile,"(A)") "chi2_fitgf WARNING: ed_mode=normal/nonsu2 but NORMAL & ANOMAL components provided."
          call sleep(1)
          call chi2_fitgf_normal_normal(fg(1,ispin_,ispin_,:,:,:),bath,ispin_)          
       end select
    case ("hybrid")
       select case(ed_mode)
       case ("superc")
          call chi2_fitgf_hybrid_superc(fg(:,ispin_,ispin_,:,:,:),bath,ispin_)
       case default
          write(LOGfile,"(A)") "chi2_fitgf WARNING: ed_mode=normal/nonsu2 but NORMAL & ANOMAL components provided."
          call sleep(1)
          call chi2_fitgf_hybrid_normal(fg(1,ispin_,ispin_,:,:,:),bath,ispin_)          
       end select
    end select
    !set trim_state_list to true after the first fit has been done: this 
    !marks the ends of the cycle of the 1st DMFT loop.
    trim_state_list=.true.
  end subroutine chi2_fitgf_generic_superc

  subroutine chi2_fitgf_generic_superc_NOSPIN(fg,bath,ispin)
    complex(8),dimension(:,:,:,:)                      :: fg ![2][Norb][Norb][Niw]
    complex(8),dimension(2,Nspin,Nspin,Norb,Norb,Lfit) :: fg_
    real(8),dimension(:),intent(inout)                 :: bath
    integer,optional                                   :: ispin
    integer                                            :: ispin_
    ispin_=1;if(present(ispin))ispin_=ispin
    if(size(fg,4)<Lfit)stop "chi2_fitgf_generic_superc_NOSPIN error: size[fg,4] < Lfit"
    fg_=zero
    fg_(:,ispin_,ispin_,:,:,1:Lfit) = fg(:,:,:,1:Lfit)
    call chi2_fitgf_generic_superc(fg_,bath,ispin_)
  end subroutine chi2_fitgf_generic_superc_NOSPIN


#ifdef _MPI
  subroutine chi2_fitgf_generic_superc_mpi(comm,fg,bath,ispin)
    integer                           :: comm
    complex(8),dimension(:,:,:,:,:,:) :: fg ![2][Nspin][Nspin][Norb][Norb][Niw]
    real(8),dimension(:)              :: bath
    integer,optional                  :: ispin
    integer                           :: ispin_
    !
    MPI_MASTER=get_Master_MPI(comm)
    !
    ispin_=1;if(present(ispin))ispin_=ispin
    call assert_shape(fg,[2,Nspin,Nspin,Norb,Norb,size(fg,6)],"chi2_fitgf_generic_superc","fg")
    select case(cg_method)
    case default
       stop "ED Error: cg_method > 2"
    case (0)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"master: Chi^2 fit with CG-nr and CG-weight: ",cg_weight," on: ",cg_scheme
    case (1)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"master: Chi^2 fit with CG-minimize and CG-weight: ",cg_weight," on: ",cg_scheme
    case (2)
       if(ed_verbose>2)write(LOGfile,"(A,I1,A,A)")"master: Chi^2 fit with CG-plus and CG-weight: ",cg_weight," on: ",cg_scheme
    end select
    !
    if(MPI_MASTER)then
       !
       select case(bath_type)
       case default
          select case(ed_mode)
          case ("superc")
             call chi2_fitgf_normal_superc(fg(:,ispin_,ispin_,:,:,:),bath,ispin_)
          case default
             write(LOGfile,"(A)") "chi2_fitgf WARNING: ed_mode=normal/nonsu2 but NORMAL & ANOMAL components provided."
             call sleep(1)
             call chi2_fitgf_normal_normal(fg(1,ispin_,ispin_,:,:,:),bath,ispin_)          
          end select
       case ("hybrid")
          select case(ed_mode)
          case ("superc")
             call chi2_fitgf_hybrid_superc(fg(:,ispin_,ispin_,:,:,:),bath,ispin_)
          case default
             write(LOGfile,"(A)") "chi2_fitgf WARNING: ed_mode=normal/nonsu2 but NORMAL & ANOMAL components provided."
             call sleep(1)
             call chi2_fitgf_hybrid_normal(fg(1,ispin_,ispin_,:,:,:),bath,ispin_)          
          end select
       end select
    endif
    !
    call Bcast_MPI(comm,bath)
    if(.not.MPI_MASTER)write(LOGfile,"(A)")"Bath received from master node"
    !
    !set trim_state_list to true after the first fit has been done: this 
    !marks the ends of the cycle of the 1st DMFT loop.
    trim_state_list=.true.
  end subroutine chi2_fitgf_generic_superc_mpi

  subroutine chi2_fitgf_generic_superc_NOSPIN_mpi(comm,fg,bath,ispin)
    integer                                            :: comm
    complex(8),dimension(:,:,:,:)                      :: fg ![2][Norb][Norb][Niw]
    complex(8),dimension(2,Nspin,Nspin,Norb,Norb,Lfit) :: fg_
    real(8),dimension(:),intent(inout)                 :: bath
    integer,optional                                   :: ispin
    integer                                            :: ispin_
    ispin_=1;if(present(ispin))ispin_=ispin
    if(size(fg,4)<Lfit)stop "chi2_fitgf_generic_superc_NOSPIN error: size[fg,4] < Lfit"
    fg_=zero
    fg_(:,ispin_,ispin_,:,:,1:Lfit) = fg(:,:,:,1:Lfit)
    call chi2_fitgf_generic_superc_mpi(comm,fg_,bath,ispin_)
  end subroutine chi2_fitgf_generic_superc_NOSPIN_mpi
#endif







  !*****************************************************************************
  !*****************************************************************************
  !*****************************************************************************
  !*****************************************************************************
  !normal ED_bath
  include "ED_CHI2FIT/fitgf_normal_normal.f90"
  include "ED_CHI2FIT/fitgf_normal_superc.f90"
  include "ED_CHI2FIT/fitgf_normal_nonsu2.f90"

  !hybrid ED_bath
  include "ED_CHI2FIT/fitgf_hybrid_normal.f90"  
  include "ED_CHI2FIT/fitgf_hybrid_superc.f90"  
  include "ED_CHI2FIT/fitgf_hybrid_nonsu2.f90"

  !replica ED_bath
  include "ED_CHI2FIT/fitgf_replica.f90"
  !*****************************************************************************
  !*****************************************************************************
  !*****************************************************************************
  !*****************************************************************************









  !+----------------------------------------------------------------------!
  ! PURPOSE: given a number of independent baths, evaluate N independent
  ! Delta/G0 functions and fit them to update the effective baths for ED.
  !+----------------------------------------------------------------------!
  !+----------------------------------------------------------------------+
  !                                NORMAL                                 !
  !+----------------------------------------------------------------------+
  subroutine ed_fit_bath_sites_normal(bath,Delta,Hloc,ispin)
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: ispin
    !MPI auxiliary vars
    real(8)                  :: bath_tmp(size(bath,1),size(bath,2))
    integer                  :: ilat,i,iorb,ispin_
    integer                  :: Nsites
    logical                  :: check_dim
    character(len=5)         :: tmp_suffix
    !
    ! Check dimensions !
    Nsites=size(bath,1)
    !
    do ilat=1,Nsites
       check_dim = check_bath_dimension(bath(ilat,:))
       if(.not.check_dim) stop "init_lattice_bath: wrong bath size dimension 1 or 2 "
    end do
    !
    bath_tmp=0d0
    do ilat = 1, Nsites
       bath_tmp(ilat,:)=bath(ilat,:)
       call set_Hloc(Hloc(ilat,:,:,:,:))
       !
       ed_file_suffix=ineq_site_suffix//str(ilat,site_indx_padding)
       !
       if(present(ispin))then
          ispin_=ispin
          if(ispin_>Nspin)stop "ed_fit_bath_sites error: required spin index > Nspin"
          call ed_chi2_fitgf(Delta(ilat,ispin_,ispin_,:,:,:),bath_tmp(ilat,:),ispin=ispin_)
       else
          call ed_chi2_fitgf(Delta(ilat,:,:,:,:,:),bath_tmp(ilat,:))
       end if
    end do
    !
    bath = bath_tmp
    !
    ed_file_suffix=""
  end subroutine ed_fit_bath_sites_normal

#ifdef _MPI
  subroutine ed_fit_bath_sites_normal_mpi(comm,bath,Delta,Hloc,ispin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: ispin
    !MPI auxiliary vars
    real(8)                  :: bath_tmp(size(bath,1),size(bath,2))
    integer                  :: ilat,i,iorb,ispin_
    integer                  :: Nsites
    logical                  :: check_dim
    character(len=5)         :: tmp_suffix
    !
    MPI_RANK = get_Rank_MPI(comm)
    MPI_SIZE = get_Size_MPI(comm)
    MPI_MASTER=get_Master_MPI(comm)
    !
    ! Check dimensions !
    Nsites=size(bath,1)
    !
    do ilat=1+MPI_RANK,Nsites,MPI_SIZE
       check_dim = check_bath_dimension(bath(ilat,:))
       if(.not.check_dim) stop "init_lattice_bath: wrong bath size dimension 1 or 2 "
    end do
    !
    bath_tmp=0d0
    do ilat = 1+MPI_RANK,Nsites,MPI_SIZE
       bath_tmp(ilat,:)=bath(ilat,:)
       call set_Hloc(Hloc(ilat,:,:,:,:))
       !
       ed_file_suffix=ineq_site_suffix//str(ilat,site_indx_padding)
       !
       if(present(ispin))then
          ispin_=ispin
          if(ispin_>Nspin)stop "ed_fit_bath_sites error: required spin index > Nspin"
          call ed_chi2_fitgf(Delta(ilat,ispin_,ispin_,:,:,:),bath_tmp(ilat,:),ispin=ispin_)
       else
          call ed_chi2_fitgf(Delta(ilat,:,:,:,:,:),bath_tmp(ilat,:))
       end if
    end do
    !
    bath=0d0
    call MPI_ALLREDUCE(bath_tmp(:,:),bath(:,:),size(bath),MPI_DOUBLE_PRECISION,MPI_SUM,comm,MPI_IERR)
    !
    ed_file_suffix=""
  end subroutine ed_fit_bath_sites_normal_mpi
#endif





  subroutine ed_fit_bath_sites_normal_1b(bath,Delta,Hloc,spin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(size(bath,1),Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: spin
    complex(8)               :: Delta_(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    if(Norb>1)stop "ed_fit_bath_sites_hloc_1b error: Norb > 1 in 1-band routine" 
    if(Nspin>1)stop "ed_fit_bath_sites_hloc_1b error: Nspin > 1 in 1-band routine" 
    Delta_(:,1,1,1,1,:) = Delta
    if(present(spin))then
       call ed_fit_bath_sites_normal(bath,Delta_,Hloc,spin)
    else
       call ed_fit_bath_sites_normal(bath,Delta_,Hloc)
    endif
  end subroutine ed_fit_bath_sites_normal_1b

#ifdef _MPI
  subroutine ed_fit_bath_sites_normal_1b_mpi(comm,bath,Delta,Hloc,spin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(size(bath,1),Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: spin
    complex(8)               :: Delta_(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    if(Norb>1)stop "ed_fit_bath_sites_hloc_1b error: Norb > 1 in 1-band routine" 
    if(Nspin>1)stop "ed_fit_bath_sites_hloc_1b error: Nspin > 1 in 1-band routine" 
    Delta_(:,1,1,1,1,:) = Delta
    if(present(spin))then
       call ed_fit_bath_sites_normal_mpi(comm,bath,Delta_,Hloc,spin)
    else
       call ed_fit_bath_sites_normal_mpi(comm,bath,Delta_,Hloc)
    endif
  end subroutine ed_fit_bath_sites_normal_1b_mpi
#endif





  subroutine ed_fit_bath_sites_normal_mb(bath,Delta,Hloc,spin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(size(bath,1),Norb,Norb,Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: spin
    complex(8)               :: Delta_(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    if(Nspin>1)stop "ed_fit_bath_sites_hloc_mb error: Nspin > 1 in M-band routine" 
    Delta_(:,1,1,:,:,:) = Delta
    if(present(spin))then
       call ed_fit_bath_sites_normal(bath,Delta_,Hloc,spin)
    else
       call ed_fit_bath_sites_normal(bath,Delta_,Hloc)
    endif
  end subroutine ed_fit_bath_sites_normal_mb

#ifdef _MPI
  subroutine ed_fit_bath_sites_normal_mb_mpi(comm,bath,Delta,Hloc,spin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(size(bath,1),Norb,Norb,Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: spin
    complex(8)               :: Delta_(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    if(Nspin>1)stop "ed_fit_bath_sites_hloc_mb error: Nspin > 1 in M-band routine" 
    Delta_(:,1,1,:,:,:) = Delta
    if(present(spin))then
       call ed_fit_bath_sites_normal_mpi(comm,bath,Delta_,Hloc,spin)
    else
       call ed_fit_bath_sites_normal_mpi(comm,bath,Delta_,Hloc)
    endif
  end subroutine ed_fit_bath_sites_normal_mb_mpi
#endif












  !+-----------------------------------------------------------------------------+!
  ! PURPOSE: given a number of independent baths, evaluate N independent Delta/G0
  ! functions and fit them to update the effective baths for ED.
  !+-----------------------------------------------------------------------------+!
  !+----------------------------------------------------------------------+
  !                                SUPERC                                 !
  !+----------------------------------------------------------------------+
  subroutine ed_fit_bath_sites_superc(bath,Delta,Hloc,ispin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(2,size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: ispin
    !MPI auxiliary
    real(8)                  :: bath_tmp(size(bath,1),size(bath,2))
    integer                  :: ilat,i,iorb,ispin_,Nsites
    logical                  :: check_dim
    character(len=5)         :: tmp_suffix
    !
    Nsites=size(bath,1)
    !
    do ilat = 1+MPI_RANK,Nsites,MPI_SIZE
       check_dim = check_bath_dimension(bath(ilat,:))
       if(.not.check_dim) stop "init_lattice_bath: wrong bath size dimension 1 or 2 "
    end do
    !
    bath_tmp=0.d0
    !
    do ilat=1, Nsites
       !
       bath_tmp(ilat,:) = bath(ilat,:)
       !
       call set_Hloc(Hloc(ilat,:,:,:,:))
       !
       ed_file_suffix=ineq_site_suffix//str(ilat,site_indx_padding)
       !
       if(present(ispin))then
          ispin_=ispin
          if(ispin_>Nspin)stop "ed_fit_bath_sites error: required spin index > Nspin"
          call ed_chi2_fitgf(Delta(:,ilat,ispin_,ispin_,:,:,:),bath_tmp(ilat,:),ispin_)
       else
          do ispin_=1,Nspin
             call ed_chi2_fitgf(Delta(:,ilat,ispin_,ispin_,:,:,:),bath_tmp(ilat,:),ispin_)
          enddo
       endif
    end do
    bath = bath_tmp
    ed_file_suffix=""
  end subroutine ed_fit_bath_sites_superc

#ifdef _MPI
  subroutine ed_fit_bath_sites_superc_mpi(comm,bath,Delta,Hloc,ispin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(2,size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: ispin
    !MPI auxiliary
    real(8)                  :: bath_tmp(size(bath,1),size(bath,2))
    integer                  :: ilat,i,iorb,ispin_,Nsites
    logical                  :: check_dim
    character(len=5)         :: tmp_suffix
    !
    MPI_RANK = get_Rank_MPI(comm)
    MPI_SIZE = get_Size_MPI(comm)
    MPI_MASTER=get_Master_MPI(comm)
    !
    Nsites=size(bath,1)
    !
    do ilat = 1 + MPI_RANK, Nsites, MPI_SIZE
       check_dim = check_bath_dimension(bath(ilat,:))
       if(.not.check_dim) stop "init_lattice_bath: wrong bath size dimension 1 or 2 "
    end do
    !
    bath_tmp=0.d0
    !
    do ilat= 1 + MPI_RANK, Nsites, MPI_SIZE
       !
       bath_tmp(ilat,:) = bath(ilat,:)
       !
       call set_Hloc(Hloc(ilat,:,:,:,:))
       !
       ed_file_suffix=ineq_site_suffix//str(ilat,site_indx_padding)
       !
       if(present(ispin))then
          ispin_=ispin
          if(ispin_>Nspin)stop "ed_fit_bath_sites error: required spin index > Nspin"
          call ed_chi2_fitgf(Delta(:,ilat,ispin_,ispin_,:,:,:),bath_tmp(ilat,:),ispin_)
       else
          do ispin_=1,Nspin
             call ed_chi2_fitgf(Delta(:,ilat,ispin_,ispin_,:,:,:),bath_tmp(ilat,:),ispin_)
          enddo
       endif
    end do
    !
    bath=0d0
    call MPI_ALLREDUCE(bath_tmp,bath,size(bath),MPI_DOUBLE_PRECISION,MPI_SUM,comm,MPI_IERR)
    !
    ed_file_suffix=""
  end subroutine ed_fit_bath_sites_superc_mpi
#endif






  subroutine ed_fit_bath_sites_superc_1b(bath,Delta,Hloc,ispin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(2,size(bath,1),Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: ispin
    complex(8)               :: Delta_(2,size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    if(Norb>1)stop "ed_fit_bath_sites_superc_1b error: Norb > 1 in 1-band routine" 
    if(Nspin>1)stop "ed_fit_bath_sites_superc_1b error: Nspin > 1 in 1-band routine" 
    Delta_(:,:,1,1,1,1,:) = Delta
    if(present(ispin))then
       call ed_fit_bath_sites_superc(bath,Delta_,Hloc,ispin)
    else
       call ed_fit_bath_sites_superc(bath,Delta_,Hloc)
    endif
  end subroutine ed_fit_bath_sites_superc_1b

#ifdef _MPI
  subroutine ed_fit_bath_sites_superc_1b_mpi(comm,bath,Delta,Hloc,ispin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(2,size(bath,1),Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: ispin
    complex(8)               :: Delta_(2,size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    if(Norb>1)stop "ed_fit_bath_sites_superc_1b error: Norb > 1 in 1-band routine" 
    if(Nspin>1)stop "ed_fit_bath_sites_superc_1b error: Nspin > 1 in 1-band routine" 
    Delta_(:,:,1,1,1,1,:) = Delta
    if(present(ispin))then
       call ed_fit_bath_sites_superc_mpi(comm,bath,Delta_,Hloc,ispin)
    else
       call ed_fit_bath_sites_superc_mpi(comm,bath,Delta_,Hloc)
    endif
  end subroutine ed_fit_bath_sites_superc_1b_mpi
#endif





  subroutine ed_fit_bath_sites_superc_mb(bath,Delta,Hloc,ispin)
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(2,size(bath,1),Norb,Norb,Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: ispin
    complex(8)               :: Delta_(2,size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    if(Nspin>1)stop "ed_fit_bath_sites_superc_mb error: Nspin > 1 in M-band routine" 
    Delta_(:,:,1,1,:,:,:) = Delta
    if(present(ispin))then
       call ed_fit_bath_sites_superc(bath,Delta_,Hloc,ispin)
    else
       call ed_fit_bath_sites_superc(bath,Delta_,Hloc)
    endif
  end subroutine ed_fit_bath_sites_superc_mb

#ifdef _MPI
  subroutine ed_fit_bath_sites_superc_mb_mpi(comm,bath,Delta,Hloc,ispin)
    integer                  :: comm
    real(8),intent(inout)    :: bath(:,:)
    complex(8),intent(inout) :: Delta(2,size(bath,1),Norb,Norb,Lmats)
    complex(8)               :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer,optional         :: ispin
    complex(8)               :: Delta_(2,size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    if(Nspin>1)stop "ed_fit_bath_sites_superc_mb error: Nspin > 1 in M-band routine" 
    Delta_(:,:,1,1,:,:,:) = Delta
    if(present(ispin))then
       call ed_fit_bath_sites_superc_mpi(comm,bath,Delta_,Hloc,ispin)
    else
       call ed_fit_bath_sites_superc_mpi(comm,bath,Delta_,Hloc)
    endif
  end subroutine ed_fit_bath_sites_superc_mb_mpi
#endif

end MODULE ED_CHI2FIT
