MODULE ED_GF_CHIDENS
  USE ED_GF_SHARED
  implicit none
  private


  public :: build_chi_dens


contains





  !+------------------------------------------------------------------+
  !                            CHARGE
  !+------------------------------------------------------------------+
  !PURPOSE  : Evaluate Charge-Charge Susceptibility <n_a(tau)n_b(0)>
  !+------------------------------------------------------------------+
  subroutine build_chi_dens()
    integer :: iorb,jorb
    write(LOGfile,"(A)")"Get impurity dens Chi:"
    do iorb=1,Norb
       write(LOGfile,"(A)")"Get Chi_dens_diag_l"//reg(txtfy(iorb))
       if(MPIMASTER)call start_timer()
       call lanc_ed_build_densChi_diag_c(iorb)
       if(MPIMASTER)call stop_timer(unit=logfile)
    enddo
    !
    !
    if(Norb>1)then
       do iorb=1,Norb
          do jorb=iorb+1,Norb
             write(LOGfile,"(A)")"Get Chi_dens_offdiag_l"//reg(txtfy(iorb))//reg(txtfy(jorb))
             if(MPIMASTER)call start_timer()
             call lanc_ed_build_densChi_offdiag_c(iorb,jorb)
             if(MPIMASTER)call stop_timer(unit=logfile)
          end do
       end do
       do iorb=1,Norb
          do jorb=iorb+1,Norb
             denschi_w(iorb,jorb,:) = 0.5d0*( denschi_w(iorb,jorb,:) - (one+xi)*denschi_w(iorb,iorb,:) - (one+xi)*denschi_w(jorb,jorb,:))
          enddo
       enddo
       !
       do iorb=1,Norb
          do jorb=1,Norb
             write(LOGfile,"(A)")"Get Chi_dens_offdiag_l"//reg(txtfy(iorb))//reg(txtfy(jorb))
             if(MPIMASTER)call start_timer()
             call lanc_ed_build_densChi_mix_c(iorb,jorb)
             if(MPIMASTER)call stop_timer(unit=logfile)
          end do
       end do
       !
       write(LOGfile,"(A)")"Get Chi_dens_tot"
       if(MPIMASTER)call start_timer()
       call lanc_ed_build_densChi_tot_c()
       if(MPIMASTER)call stop_timer(unit=logfile)
    endif
    !
    denschi_tau = Denschi_tau/zeta_function
    denschi_w   = denschi_w/zeta_function
    denschi_iv  = denschi_iv/zeta_function
    !
  end subroutine build_chi_dens








  !################################################################
  !################################################################
  !################################################################
  !################################################################







  !+------------------------------------------------------------------+
  !PURPOSE  : Evaluate the Charge-Charge susceptibility \Chi_dens for  
  ! the orbital diagonal case: \chi_dens_aa = <N_a(\tau)N_a(0)>
  !+------------------------------------------------------------------+
  subroutine lanc_ed_build_densChi_diag_c(iorb)
    integer                :: iorb,isite,isector,istate
    integer                :: numstates
    integer                :: nlanc,idim,vecDim
    integer                :: iup0,idw0,isign
    integer                :: ib(Nlevels)
    integer                :: m,i,j,r
    real(8)                :: norm2,sgn
    complex(8)             :: cnorm2
    real(8),allocatable    :: alfa_(:),beta_(:)
    complex(8),allocatable :: vvinit(:),vvloc(:)
    integer                :: Nitermax
    type(sector_map)       :: HI    !map of the Sector S to Hilbert space H
    !
    !
    !
    do istate=1,state_list%size
       isector    =  es_return_sector(state_list,istate)
       state_e    =  es_return_energy(state_list,istate)
#ifdef _MPI
       if(MpiStatus)then
          state_cvec => es_return_cvector(MpiComm,state_list,istate)
       else
          state_cvec => es_return_cvector(state_list,istate)
       endif
#else
       state_cvec => es_return_cvector(state_list,istate)
#endif
       !
       idim       =  getdim(isector)
       !
       if(ed_verbose==3)write(LOGfile,"(A,2I3)")'Apply N:',getnup(isector),getndw(isector)
       !
       if(MpiMaster)then
          allocate(vvinit(idim)); vvinit=0.d0
          !
          call build_sector(isector,HI)
          do m=1,idim                     !loop over |gs> components m
             i=HI%map(m)
             ib = bdecomp(i,2*Ns)
             sgn = dble(ib(iorb))+dble(ib(iorb+Ns))
             vvinit(m) = sgn*state_cvec(m)   !build the cdg_up|gs> state
          enddo
          call delete_sector(isector,HI)
          norm2=dot_product(vvinit,vvinit)
          vvinit=vvinit/sqrt(norm2)
       endif
       !
       nlanc=min(idim,lanc_nGFiter)
       allocate(alfa_(nlanc),beta_(nlanc))
       !
       call build_Hv_sector(isector)
#ifdef _MP
       if(MpiStatus)then
          call Bcast_MPI(MpiComm,norm2)
          vecDim = vecDim_Hv_sector(isector)
          allocate(vvloc(vecDim))
          call scatter_vector_MPI(MpiComm,vvinit,vvloc)
          call sp_lanc_tridiag(MpiComm,spHtimesV_cc,vvloc,alfa_,beta_)
       else
          call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
       endif
#else
       call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
#endif
       cnorm2=one*norm2
       isign=1
       call add_to_lanczos_densChi(cnorm2,state_e,alfa_,beta_,isign,iorb,iorb)
       isign=-1
       call add_to_lanczos_densChi(cnorm2,state_e,alfa_,beta_,isign,iorb,iorb)
       !
       call delete_Hv_sector()
       !
       deallocate(alfa_,beta_)
       if(allocated(vvinit))deallocate(vvinit)          
       if(allocated(vvloc))deallocate(vvloc)
       nullify(state_cvec)
    enddo
    return
  end subroutine lanc_ed_build_densChi_diag_c







  !################################################################
  !################################################################
  !################################################################
  !################################################################






  !+------------------------------------------------------------------+
  !PURPOSE  : Evaluate the TOTAL Charge-Charge susceptibility \Chi_dens  
  ! \chi_dens_tot = <N(\tau)N(0)>, N=sum_a N_a
  !+------------------------------------------------------------------+
  subroutine lanc_ed_build_densChi_tot_c()
    integer                :: iorb,isite,isector,istate
    integer                :: numstates
    integer                :: nlanc,idim,vecDim
    integer                :: iup0,idw0,isign
    integer                :: ib(Nlevels)
    integer                :: m,i,j,r
    complex(8)             :: cnorm2
    real(8)                :: norm2,sgn
    real(8),allocatable    :: alfa_(:),beta_(:)
    complex(8),allocatable :: vvinit(:),vvloc(:)
    integer                :: Nitermax
    type(sector_map)       :: HI    !map of the Sector S to Hilbert space H
    !    
    !
    do istate=1,state_list%size
       isector    =  es_return_sector(state_list,istate)
       state_e    =  es_return_energy(state_list,istate)
#ifdef _MPI
       if(MpiStatus)then
          state_cvec => es_return_cvector(MpiComm,state_list,istate)
       else
          state_cvec => es_return_cvector(state_list,istate)
       endif
#else
       state_cvec => es_return_cvector(state_list,istate)
#endif
       !
       idim       =  getdim(isector)
       !
       if(ed_verbose==3)write(LOGfile,"(A,2I3)")'Apply N:',getnup(isector),getndw(isector)
       !
       if(MpiMaster)then
          allocate(vvinit(idim)); vvinit=0.d0
          !
          call build_sector(isector,HI)
          do m=1,idim
             i=HI%map(m)
             ib = bdecomp(i,2*Ns)
             sgn = sum(dble(ib(1:Norb)))+sum(dble(ib(Ns+1:Ns+Norb)))
             vvinit(m) = sgn*state_cvec(m) 
          enddo
          call delete_sector(isector,HI)
          norm2=dot_product(vvinit,vvinit)
          vvinit=vvinit/sqrt(norm2)
       endif
       !
       nlanc=min(idim,lanc_nGFiter)
       allocate(alfa_(nlanc),beta_(nlanc))
       !
       call build_Hv_sector(isector)
#ifdef _MP
       if(MpiStatus)then
          call Bcast_MPI(MpiComm,norm2)
          vecDim = vecDim_Hv_sector(isector)
          allocate(vvloc(vecDim))
          call scatter_vector_MPI(MpiComm,vvinit,vvloc)
          call sp_lanc_tridiag(MpiComm,spHtimesV_cc,vvloc,alfa_,beta_)
       else
          call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
       endif
#else
       call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
#endif
       cnorm2=one*norm2
       isign=1
       call add_to_lanczos_densChi_tot(cnorm2,state_e,alfa_,beta_,isign)
       isign=-1
       call add_to_lanczos_densChi_tot(cnorm2,state_e,alfa_,beta_,isign)
       !
       call delete_Hv_sector()
       !
       deallocate(alfa_,beta_)
       if(allocated(vvinit))deallocate(vvinit)          
       if(allocated(vvloc))deallocate(vvloc)
       nullify(state_cvec)
    enddo
    return
  end subroutine lanc_ed_build_densChi_tot_c







  !################################################################
  !################################################################
  !################################################################
  !################################################################






  !+------------------------------------------------------------------+
  !PURPOSE  : Evaluate the Charge-Charge susceptibility \Chi_dens for
  ! the orbital off-diagonal case: \chi_dens_ab = <N_a(\tau)N_b(0)>
  !+------------------------------------------------------------------+
  subroutine lanc_ed_build_densChi_offdiag_c(iorb,jorb)
    integer                :: iorb,jorb,isite,isector,istate,isign
    integer                :: numstates
    integer                :: nlanc,idim
    integer                :: iup0,idw0
    integer                :: ib(Nlevels)
    integer                :: m,i,j,r
    complex(8)             :: cnorm2
    real(8)                :: norm2,sgn
    real(8),allocatable    :: alfa_(:),beta_(:)
    complex(8),allocatable :: vvinit(:),vvloc(:)
    integer                :: Nitermax
    type(sector_map)       :: HI    !map of the Sector S to Hilbert space H
    !
    !
    do istate=1,state_list%size
       ! properties of the ground states
       isector     =  es_return_sector(state_list,istate)
       state_e     =  es_return_energy(state_list,istate)
#ifdef _MPI
       if(MpiStatus)then
          state_cvec => es_return_cvector(MpiComm,state_list,istate)
       else
          state_cvec => es_return_cvector(state_list,istate)
       endif
#else
       state_cvec => es_return_cvector(state_list,istate)
#endif
       !
       idim       =  getdim(isector)
       !
       if(ed_verbose==3)write(LOGfile,"(A)")'Apply N_iorb + N_jorb:'

       !build the (N_iorb+N_jorb)|gs> state
       if(MpiMaster)then
          allocate(vvinit(idim)); vvinit=zero
          !
          call build_sector(isector,HI)
          do m=1,idim                     !loop over |gs> components m
             i=HI%map(m)
             ib = bdecomp(i,2*Ns)
             sgn = dble(ib(iorb))+dble(ib(iorb+Ns))
             vvinit(m) = sgn*state_cvec(m)   
             !
             sgn = dble(ib(jorb))+dble(ib(jorb+Ns))
             vvinit(m) = vvinit(m) + sgn*state_cvec(m)   
             !
          enddo
          call delete_sector(isector,HI)
          norm2=dot_product(vvinit,vvinit)
          vvinit=vvinit/sqrt(norm2)
       endif
       !
       nlanc=min(idim,lanc_nGFiter)
       allocate(alfa_(nlanc),beta_(nlanc))
       !
       call build_Hv_sector(isector)
#ifdef _MP
       if(MpiStatus)then
          call Bcast_MPI(MpiComm,norm2)
          vecDim = vecDim_Hv_sector(isector)
          allocate(vvloc(vecDim))
          call scatter_vector_MPI(MpiComm,vvinit,vvloc)
          call sp_lanc_tridiag(MpiComm,spHtimesV_cc,vvloc,alfa_,beta_)
       else
          call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
       endif
#else
       call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
#endif
       cnorm2=one*norm2
       !particle and holes excitations all at once
       isign=1                    !<---
       call add_to_lanczos_densChi(cnorm2,state_e,alfa_,beta_,isign,iorb,jorb)
       isign=-1                   !<---
       call add_to_lanczos_densChi(cnorm2,state_e,alfa_,beta_,isign,iorb,jorb)
       !
       call delete_Hv_sector()
       !
       !
       !build the (N_iorb - xi*N_jorb)|gs> state
       if(ed_verbose==3)write(LOGfile,"(A)")'Apply N_iorb + xi*N_jorb:'
       !
       if(MpiMaster)then
          vvinit=zero
          !
          call build_sector(isector,HI)
          do m=1,idim
             i=HI%map(m)
             ib = bdecomp(i,2*Ns)
             sgn = dble(ib(iorb))+dble(ib(iorb+Ns))
             vvinit(m) = sgn*state_cvec(m)   
             !
             sgn = dble(ib(jorb))+dble(ib(jorb+Ns))
             vvinit(m) = vvinit(m) - xi*sgn*state_cvec(m)   
             !
          enddo
          call delete_sector(isector,HI)
          norm2=dot_product(vvinit,vvinit)
          vvinit=vvinit/sqrt(norm2)
       endif
       !
       nlanc=min(idim,lanc_nGFiter)
       allocate(alfa_(nlanc),beta_(nlanc))
       !
       call build_Hv_sector(isector)
#ifdef _MP
       if(MpiStatus)then
          call Bcast_MPI(MpiComm,norm2)
          vecDim = vecDim_Hv_sector(isector)
          allocate(vvloc(vecDim))
          call scatter_vector_MPI(MpiComm,vvinit,vvloc)
          call sp_lanc_tridiag(MpiComm,spHtimesV_cc,vvloc,alfa_,beta_)
       else
          call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
       endif
#else
       call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
#endif     
       cnorm2=xi*norm2
       isign=1
       call add_to_lanczos_densChi(cnorm2,state_e,alfa_,beta_,isign,iorb,jorb)
       !
       call delete_Hv_sector()
       !
       !
       !build the (N_iorb + xi*N_jorb)|gs> state
       if(ed_verbose==3)write(LOGfile,"(A)")'Apply N_iorb + xi*N_jorb:'
       !
       if(MpiMaster)then
          vvinit=zero
          !
          call build_sector(isector,HI)
          do m=1,idim
             i=HI%map(m)
             ib = bdecomp(i,2*Ns)
             sgn = dble(ib(iorb))+dble(ib(iorb+Ns))
             vvinit(m) = sgn*state_cvec(m)   
             !
             sgn = dble(ib(jorb))+dble(ib(jorb+Ns))
             vvinit(m) = vvinit(m) + xi*sgn*state_cvec(m)   
             !
          enddo
          call delete_sector(isector,HI)
          norm2=dot_product(vvinit,vvinit)
          vvinit=vvinit/sqrt(norm2)
       endif
       !
       nlanc=min(idim,lanc_nGFiter)
       allocate(alfa_(nlanc),beta_(nlanc))
       !
       call build_Hv_sector(isector)
#ifdef _MP
       if(MpiStatus)then
          call Bcast_MPI(MpiComm,norm2)
          vecDim = vecDim_Hv_sector(isector)
          allocate(vvloc(vecDim))
          call scatter_vector_MPI(MpiComm,vvinit,vvloc)
          call sp_lanc_tridiag(MpiComm,spHtimesV_cc,vvloc,alfa_,beta_)
       else
          call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
       endif
#else
       call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
#endif
       cnorm2=xi*norm2
       isign=-1
       call add_to_lanczos_densChi(cnorm2,state_e,alfa_,beta_,isign,iorb,jorb)
       !
       call delete_Hv_sector()
       !
       deallocate(alfa_,beta_)
       if(allocated(vvinit))deallocate(vvinit)          
       if(allocated(vvloc))deallocate(vvloc)
       nullify(state_cvec)
    enddo
    return
  end subroutine lanc_ed_build_densChi_offdiag_c







  !################################################################
  !################################################################
  !################################################################
  !################################################################






  !+------------------------------------------------------------------+
  !PURPOSE  : Evaluate the inter-orbital charge susceptibility \Chi_mix 
  ! \chi_mix = <C^+_a(\tau)N_a(0)>
  !+------------------------------------------------------------------+
  subroutine lanc_ed_build_densChi_mix_c(iorb,jorb)
    integer                :: iorb,jorb,ispin
    complex(8),allocatable :: vvinit(:),vvinit_tmp(:),vvloc(:)
    real(8),allocatable    :: alfa_(:),beta_(:)
    integer                :: isite,jsite,istate,vecDim
    integer                :: isector,jsector,ksector
    integer                :: idim,jdim,kdim
    type(sector_map)       :: HI,HJ,HK
    integer                :: ib(Nlevels)
    integer                :: m,i,j,r,numstates
    real(8)                :: sgn,norm2
    complex(8)             :: cnorm2
    integer                :: Nitermax,Nlanc
    !
    !   
    !
    do istate=1,state_list%size
       isector     =  es_return_sector(state_list,istate)
       state_e     =  es_return_energy(state_list,istate)
#ifdef _MPI
       if(MpiStatus)then
          state_cvec => es_return_cvector(MpiComm,state_list,istate)
       else
          state_cvec => es_return_cvector(state_list,istate)
       endif
#else
       state_cvec => es_return_cvector(state_list,istate)
#endif
       !
       idim       =  getdim(isector)
       !
       call build_sector(isector,HI)
       !
       !+- Apply Sum_ispin c^dg_{jorb,ispin} c_{iorb,ispin} -+!
       do ispin=1,Nspin
          !
          if(MpiMaster)then
             isite=impIndex(iorb,ispin)
             jsector = getCsector(ispin,isector)
             if(jsector/=0)then
                jdim  = getdim(jsector)
                allocate(vvinit_tmp(jdim)) ;  vvinit_tmp=zero
                call build_sector(jsector,HJ)
                do m=1,idim
                   i=HI%map(m)
                   ib = bdecomp(i,2*Ns)
                   if(ib(isite)==1)then
                      call c(isite,i,r,sgn)
                      j=binary_search(HJ%map,r)
                      vvinit_tmp(j) = sgn*state_cvec(m)
                   end if
                enddo
             endif
             !
             jsite = impIndex(jorb,ispin)
             ksector = getCDGsector(ispin,jsector)
             if(ksector/=0) then       
                kdim  = getdim(ksector)
                allocate(vvinit(kdim)) ;  vvinit=zero
                call build_sector(ksector,HK)
                do m=1,jdim
                   i=HJ%map(m)
                   ib = bdecomp(i,2*Ns)
                   if(ib(jsite)==0)then
                      call cdg(jsite,i,r,sgn)
                      j=binary_search(HK%map,r)
                      vvinit(j) = sgn*vvinit_tmp(m)
                   endif
                enddo
             end if
             deallocate(vvinit_tmp)
             !
             call delete_sector(jsector,HJ)
             call delete_sector(ksector,HK)
             norm2=dot_product(vvinit,vvinit)
             vvinit=vvinit/sqrt(norm2)
          endif
          !
          nlanc=min(kdim,lanc_nGFiter)
          allocate(alfa_(nlanc),beta_(nlanc))
          !
          call build_Hv_sector(ksector)
#ifdef _MPI
          if(MpiStatus)then
             call Bcast_MPI(MpiComm,norm2)
             vecDim = vecDim_Hv_sector(ksector)
             allocate(vvloc(vecDim))
             call scatter_vector_MPI(MpiComm,vvinit,vvloc)
             call sp_lanc_tridiag(MpiComm,spHtimesV_cc,vvloc,alfa_,beta_)
          else
             call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
          endif
#else
          call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
#endif
          cnorm2=one*norm2
          call add_to_lanczos_densChi_mix(cnorm2,state_e,alfa_,beta_,1,iorb,jorb)
          !
          call delete_Hv_sector()
          !
          deallocate(alfa_,beta_)
          if(allocated(vvinit))deallocate(vvinit)          
          if(allocated(vvloc))deallocate(vvloc)
       enddo
       !
       !
       !+- Apply Sum_ispin c^dg_{iorb,ispin} c_{jorb,ispin} -+!
       do ispin=1,Nspin
          !
          if(MpiMaster)then
             jsite=impIndex(jorb,ispin)
             jsector = getCsector(ispin,isector)
             if(jsector/=0)then
                jdim  = getdim(jsector)
                allocate(vvinit_tmp(jdim)) ; vvinit_tmp=zero
                call build_sector(jsector,HJ)             
                do m=1,idim
                   i=HI%map(m)
                   ib = bdecomp(i,2*Ns)
                   if(ib(jsite)==1)then
                      call c(jsite,i,r,sgn)
                      j=binary_search(HJ%map,r)
                      vvinit_tmp(j) = sgn*state_cvec(m)
                   endif
                enddo
             endif
             !
             isite = impIndex(iorb,ispin)
             ksector = getCDGsector(ispin,jsector)
             if(ksector/=0) then       
                kdim  = getdim(ksector)
                allocate(vvinit(kdim)) ; vvinit=zero
                call build_sector(ksector,HK)             
                do m=1,jdim
                   i=HJ%map(m)
                   ib = bdecomp(i,2*Ns)
                   if(ib(isite)==0)then
                      call cdg(isite,i,r,sgn)
                      j=binary_search(HK%map,r)
                      vvinit(j) = sgn*vvinit_tmp(m)
                   endif
                enddo
             end if
             deallocate(vvinit_tmp)
             !
             call delete_sector(jsector,HJ)
             call delete_sector(ksector,HK)
             norm2=dot_product(vvinit,vvinit)
             vvinit=vvinit/sqrt(norm2)
          endif
          !
          nlanc=min(kdim,lanc_nGFiter)
          allocate(alfa_(nlanc),beta_(nlanc))
          !
          call build_Hv_sector(ksector)
#ifdef _MPI
          if(MpiStatus)then
             call Bcast_MPI(MpiComm,norm2)
             vecDim = vecDim_Hv_sector(ksector)
             allocate(vvloc(vecDim))
             call scatter_vector_MPI(MpiComm,vvinit,vvloc)
             call sp_lanc_tridiag(MpiComm,spHtimesV_cc,vvloc,alfa_,beta_)
          else
             call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
          endif
#else
          call sp_lanc_tridiag(spHtimesV_cc,vvinit,alfa_,beta_)
#endif
          cnorm2=one*norm2
          call add_to_lanczos_densChi_mix(cnorm2,state_e,alfa_,beta_,-1,iorb,jorb)
          !
          call delete_Hv_sector()
          !
          deallocate(alfa_,beta_)
          if(allocated(vvinit))deallocate(vvinit)          
          if(allocated(vvloc))deallocate(vvloc)
       enddo
       !
       nullify(state_cvec)
       call delete_sector(isector,HI)
       !
    enddo
    return
  end subroutine lanc_ed_build_densChi_mix_c








  !################################################################
  !################################################################
  !################################################################
  !################################################################






  subroutine add_to_lanczos_densChi(vnorm2,Ei,alanc,blanc,isign,iorb,jorb)
    integer                                    :: iorb,jorb,isign
    complex(8)                                 :: pesoF,pesoAB,pesoBZ,peso,vnorm2  
    real(8)                                    :: Ei,Ej,Egs,de
    integer                                    :: nlanc
    real(8),dimension(:)                       :: alanc
    real(8),dimension(size(alanc))             :: blanc 
    real(8),dimension(size(alanc),size(alanc)) :: Z
    real(8),dimension(size(alanc))             :: diag,subdiag
    integer                                    :: i,j,ierr
    complex(8)                                 :: iw,chisp
    !
    Egs = state_list%emin       !get the gs energy
    !
    Nlanc = size(alanc)
    !
    pesoF  = vnorm2/zeta_function 
    pesoBZ = 1d0
    if(finiteT)pesoBZ = exp(-beta*(Ei-Egs))
    !
    diag             = 0.d0
    subdiag          = 0.d0
    Z                = eye(Nlanc)
    diag(1:Nlanc)    = alanc(1:Nlanc)
    subdiag(2:Nlanc) = blanc(2:Nlanc)
    call tql2(Nlanc,diag,subdiag,Z,ierr)
    !
    select case(isign)
    case (1)
       do j=1,nlanc
          Ej     = diag(j)
          dE     = Ej-Ei
          pesoAB = Z(1,j)*Z(1,j)
          peso   = pesoF*pesoAB*pesoBZ
          if(beta*dE < 1d-1)then     !abs(X - (1-exp(-X)) is about 5*10^-3 for X<10^-1 this is a satisfactory bound
             densChi_iv(iorb,jorb,0)=densChi_iv(iorb,jorb,0) - peso*beta
          else
             densChi_iv(iorb,jorb,0)=densChi_iv(iorb,jorb,0) + peso*(exp(-beta*dE)-1d0)/dE 
          endif
          do i=1,Lmats
             densChi_iv(iorb,jorb,i)=densChi_iv(iorb,jorb,i) + peso*(exp(-beta*dE)-1d0)/(dcmplx(0d0,vm(i)) - dE)
          enddo
          do i=0,Ltau
             densChi_tau(iorb,jorb,i)=densChi_tau(iorb,jorb,i) + peso*exp(-tau(i)*de)
          enddo
          do i=1,Lreal
             densChi_w(iorb,jorb,i)=densChi_w(iorb,jorb,i) + peso*(exp(-beta*dE)-1.d0)/(dcmplx(wr(i),eps) - dE)
          enddo
       enddo
    case (-1)
       do j=1,nlanc
          Ej     = diag(j)
          dE     = Ej-Ei
          pesoAB = Z(1,j)*Z(1,j)
          peso   = pesoF*pesoAB*pesoBZ
          if(beta*dE < 1d-1)then     !abs(X - (1-exp(-X)) is about 5*10^-3 for X<10^-1 this is a satisfactory bound
             densChi_iv(iorb,jorb,0)=densChi_iv(iorb,jorb,0) + peso*beta
          else
             densChi_iv(iorb,jorb,0)=densChi_iv(iorb,jorb,0) + peso*(1d0-exp(-beta*dE))/dE 
          endif
          do i=1,Lmats
             densChi_iv(iorb,jorb,i)=densChi_iv(iorb,jorb,i) + peso*(1d0-exp(-beta*dE))/(dcmplx(0d0,vm(i)) + dE)
          enddo
          do i=0,Ltau
             densChi_tau(iorb,jorb,i)=densChi_tau(iorb,jorb,i) + peso*exp(-(beta-tau(i))*dE)
          enddo
          do i=1,Lreal
             densChi_w(iorb,jorb,i)=densChi_w(iorb,jorb,i) + peso*(1d0-exp(-beta*dE))/(dcmplx(wr(i),eps) + dE)
          enddo
       enddo
    case default
       stop "add_to_lanczos_densChi: isign not in {-1,1}"
    end select
  end subroutine add_to_lanczos_densChi








  !################################################################
  !################################################################
  !################################################################
  !################################################################






  subroutine add_to_lanczos_densChi_mix(vnorm2,Ei,alanc,blanc,isign,iorb,jorb)
    integer                                    :: iorb,jorb,isign
    complex(8)                                 :: pesoF,pesoAB,pesoBZ,peso,vnorm2  
    real(8)                                    :: Ei,Ej,Egs,de
    integer                                    :: nlanc
    real(8),dimension(:)                       :: alanc
    real(8),dimension(size(alanc))             :: blanc 
    real(8),dimension(size(alanc),size(alanc)) :: Z
    real(8),dimension(size(alanc))             :: diag,subdiag
    integer                                    :: i,j,ierr
    complex(8)                                 :: iw,chisp
    !
    Egs = state_list%emin       !get the gs energy
    !
    Nlanc = size(alanc)
    !
    pesoF  = vnorm2/zeta_function 
    pesoBZ = 1d0
    if(finiteT)pesoBZ = exp(-beta*(Ei-Egs))
    !
    diag             = 0.d0
    subdiag          = 0.d0
    Z                = eye(Nlanc)
    diag(1:Nlanc)    = alanc(1:Nlanc)
    subdiag(2:Nlanc) = blanc(2:Nlanc)
    call tql2(Nlanc,diag,subdiag,Z,ierr)
    !
    select case(isign)
    case (1)
       do j=1,nlanc
          Ej     = diag(j)
          dE     = Ej-Ei
          pesoAB = Z(1,j)*Z(1,j)
          peso   = pesoF*pesoAB*pesoBZ
          if(beta*dE < 1d-1)then     !abs(X - (1-exp(-X)) is about 5*10^-3 for X<10^-1 this is a satisfactory bound
             densChi_mix_iv(iorb,jorb,0)=densChi_mix_iv(iorb,jorb,0) - peso*beta
          else
             densChi_mix_iv(iorb,jorb,0)=densChi_mix_iv(iorb,jorb,0) + peso*(exp(-beta*dE)-1d0)/dE 
          endif
          do i=1,Lmats
             densChi_mix_iv(iorb,jorb,i)=densChi_mix_iv(iorb,jorb,i) + peso*(exp(-beta*dE)-1d0)/(dcmplx(0d0,vm(i)) - dE)
          enddo
          do i=0,Ltau
             densChi_mix_tau(iorb,jorb,i)=densChi_mix_tau(iorb,jorb,i) + peso*exp(-tau(i)*de)
          enddo
          do i=1,Lreal
             densChi_mix_w(iorb,jorb,i)=densChi_mix_w(iorb,jorb,i) + peso*(exp(-beta*dE)-1.d0)/(dcmplx(wr(i),eps) - dE)
          enddo
       enddo
    case (-1)
       do j=1,nlanc
          Ej     = diag(j)
          dE     = Ej-Ei
          pesoAB = Z(1,j)*Z(1,j)
          peso   = pesoF*pesoAB*pesoBZ
          if(beta*dE < 1d-1)then     !abs(X - (1-exp(-X)) is about 5*10^-3 for X<10^-1 this is a satisfactory bound
             densChi_mix_iv(iorb,jorb,0)=densChi_mix_iv(iorb,jorb,0) + peso*beta
          else
             densChi_mix_iv(iorb,jorb,0)=densChi_mix_iv(iorb,jorb,0) + peso*(1d0-exp(-beta*dE))/dE 
          endif
          do i=1,Lmats
             densChi_mix_iv(iorb,jorb,i)=densChi_mix_iv(iorb,jorb,i) + peso*(1d0-exp(-beta*dE))/(dcmplx(0d0,vm(i)) + dE)
          enddo
          do i=0,Ltau
             densChi_mix_tau(iorb,jorb,i)=densChi_mix_tau(iorb,jorb,i) + peso*exp(-(beta-tau(i))*dE)
          enddo
          do i=1,Lreal
             densChi_mix_w(iorb,jorb,i)=densChi_mix_w(iorb,jorb,i) + peso*(1d0-exp(-beta*dE))/(dcmplx(wr(i),eps) + dE)
          enddo
       enddo
    case default
       stop "add_to_lanczos_densChi_mix: isign not in {-1,1}"
    end select
  end subroutine add_to_lanczos_densChi_mix








  !################################################################
  !################################################################
  !################################################################
  !################################################################






  subroutine add_to_lanczos_densChi_tot(vnorm2,Ei,alanc,blanc,isign)
    complex(8)                                 :: pesoF,pesoAB,pesoBZ,peso,vnorm2  
    real(8)                                    :: Ei,Ej,Egs,de
    integer                                    :: nlanc,isign
    real(8),dimension(:)                       :: alanc
    real(8),dimension(size(alanc))             :: blanc 
    real(8),dimension(size(alanc),size(alanc)) :: Z
    real(8),dimension(size(alanc))             :: diag,subdiag
    integer                                    :: i,j,ierr
    complex(8)                                 :: iw,chisp
    !
    Egs = state_list%emin       !get the gs energy
    !
    Nlanc = size(alanc)
    !
    pesoF  = vnorm2/zeta_function 
    pesoBZ = 1d0
    if(finiteT)pesoBZ = exp(-beta*(Ei-Egs))
    !
    diag             = 0.d0
    subdiag          = 0.d0
    Z                = eye(Nlanc)
    diag(1:Nlanc)    = alanc(1:Nlanc)
    subdiag(2:Nlanc) = blanc(2:Nlanc)
    call tql2(Nlanc,diag,subdiag,Z,ierr)
    !
    select case(isign)
    case (1)
       do j=1,nlanc
          Ej     = diag(j)
          dE     = Ej-Ei
          pesoAB = Z(1,j)*Z(1,j)
          peso   = pesoF*pesoAB*pesoBZ
          if(beta*dE < 1d-1)then     !abs(X - (1-exp(-X)) is about 5*10^-3 for X<10^-1 this is a satisfactory bound
             densChi_tot_iv(0)=densChi_tot_iv(0) - peso*beta
          else
             densChi_tot_iv(0)=densChi_tot_iv(0) + peso*(exp(-beta*dE)-1d0)/dE 
          endif
          do i=1,Lmats
             densChi_tot_iv(i)=densChi_tot_iv(i) + peso*(exp(-beta*dE)-1d0)/(dcmplx(0d0,vm(i)) - dE)
          enddo
          do i=0,Ltau
             densChi_tot_tau(i)=densChi_tot_tau(i) + peso*exp(-tau(i)*de)
          enddo
          do i=1,Lreal
             densChi_tot_w(i)=densChi_tot_w(i) + peso*(exp(-beta*dE)-1.d0)/(dcmplx(wr(i),eps) - dE)
          enddo
       enddo
    case (-1)
       do j=1,nlanc
          Ej     = diag(j)
          dE     = Ej-Ei
          pesoAB = Z(1,j)*Z(1,j)
          peso   = pesoF*pesoAB*pesoBZ
          if(beta*dE < 1d-1)then     !abs(X - (1-exp(-X)) is about 5*10^-3 for X<10^-1 this is a satisfactory bound
             densChi_tot_iv(0)=densChi_tot_iv(0) + peso*beta
          else
             densChi_tot_iv(0)=densChi_tot_iv(0) + peso*(1d0-exp(-beta*dE))/dE 
          endif
          do i=1,Lmats
             densChi_tot_iv(i)=densChi_tot_iv(i) + peso*(1d0-exp(-beta*dE))/(dcmplx(0d0,vm(i)) + dE)
          enddo
          do i=0,Ltau
             densChi_tot_tau(i)=densChi_tot_tau(i) + peso*exp(-(beta-tau(i))*dE)
          enddo
          do i=1,Lreal
             densChi_tot_w(i)=densChi_tot_w(i) + peso*(1d0-exp(-beta*dE))/(dcmplx(wr(i),eps) + dE)
          enddo
       enddo
    case default
       stop "add_to_lanczos_densChi_tot: isign not in {-1,1}"
    end select
  end subroutine add_to_lanczos_densChi_tot








  !################################################################
  !################################################################
  !################################################################
  !################################################################








END MODULE ED_GF_CHIDENS
