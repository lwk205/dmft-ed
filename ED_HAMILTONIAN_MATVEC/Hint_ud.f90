  do idw=1,dimdw
     mdw  = H%dw(idw)
     ndw  = bdecomp(mdw,Ns)
     impi_dw = idw - ishift_dw


     do iup=1,dimdw
        mup  = H%up(iup)
        nup  = bdecomp(mup,Ns)
        impi_up = iup - ishift_dw


        !MPI Shifts
        i    = iup + (idw-1)*dimUp
        impi = i - ishift


        !density-density interaction: same orbital, opposite spins:
        ! = \sum_\a U_\a*(n_{\a,up}*n_{\a,dw})
        htmp = zero
        do iorb=1,Norb
           htmp = htmp + Uloc(iorb)*nup(iorb)*ndw(iorb)
        enddo
        if(Norb>1)then
           !density-density interaction: different orbitals, opposite spins:
           ! =   U'   *     sum_{i/=j} [ n_{i,up}*n_{j,dw} + n_{j,up}*n_{i,dw} ]
           ! =  (Uloc-2*Jh)*sum_{i/=j} [ n_{i,up}*n_{j,dw} + n_{j,up}*n_{i,dw} ]
           do iorb=1,Norb
              do jorb=iorb+1,Norb
                 htmp = htmp + Ust*(nup(iorb)*ndw(jorb) + nup(jorb)*ndw(iorb))
              enddo
           enddo
           !density-density interaction: different orbitals, parallel spins
           ! = \sum_{i<j}    U''     *[ n_{i,up}*n_{j,up} + n_{i,dw}*n_{j,dw} ]
           ! = \sum_{i<j} (Uloc-3*Jh)*[ n_{i,up}*n_{j,up} + n_{i,dw}*n_{j,dw} ]
           do iorb=1,Norb
              do jorb=iorb+1,Norb
                 htmp = htmp + (Ust-Jh)*(nup(iorb)*nup(jorb) + ndw(iorb)*ndw(jorb))
              enddo
           enddo
        endif
        !if using the Hartree-shifted chemical potential: mu=0 for half-filling
        !sum up the contributions of hartree terms:
        if(hfmode)then
           do iorb=1,Norb
              htmp = htmp - 0.5d0*Uloc(iorb)*(nup(iorb)+ndw(iorb)) + 0.25d0*uloc(iorb)
           enddo
           if(Norb>1)then
              do iorb=1,Norb
                 do jorb=iorb+1,Norb
                    htmp=htmp-0.5d0*Ust*(nup(iorb)+ndw(iorb)+nup(jorb)+ndw(jorb))+0.25d0*Ust
                    htmp=htmp-0.5d0*(Ust-Jh)*(nup(iorb)+ndw(iorb)+nup(jorb)+ndw(jorb))+0.25d0*(Ust-Jh)
                 enddo
              enddo
           endif
        endif
        !
        call sp_insert_element(spH0,htmp,impi,i)


        ! SPIN-EXCHANGE (S-E)
        !    S-E: J c^+_iorb_up c^+_jorb_dw c_iorb_dw c_jorb_up  (i.ne.j) 
        !    S-E: J c^+_{iorb} c^+_{jorb+Ns} c_{iorb+Ns} c_{jorb}
        if(Norb>1.AND.Jhflag)then
           !
           do iorb=1,Norb
              do jorb=1,Norb
                 Jcondition=(&
                      (iorb/=jorb).AND.&
                      (nup(jorb)==1).AND.&
                      (ndw(iorb)==1).AND.&
                      (ndw(jorb)==0).AND.&
                      (nup(iorb)==0))
                 if(Jcondition)then
                    call c(iorb,mdw,k1,sg1) !DW
                    call cdg(jorb,k1,k2,sg2) !DW
                    jdw=binary_search(H%dw,k2)
                    call c(jorb,mup,k1,sg3) !UP
                    call cdg(iorb,k1,k2,sg4)    !UP
                    jup=binary_search(H%up,k2)
                    htmp = one*Jx*sg1*sg2*sg3*sg4
                    !
                    if(jup/=0.AND.jdw/=0)then
                       j = jup + (jdw-1)*dimup
                       call sp_insert_element(spH0,htmp,impi,j)
                    endif
                    !
                 endif
              enddo
           enddo
           !
        endif


        ! PAIR-HOPPING (P-H) TERMS
        !    P-H: J c^+_iorb_up c^+_iorb_dw   c_jorb_dw   c_jorb_up  (i.ne.j) 
        !    P-H: J c^+_{iorb}  c^+_{iorb+Ns} c_{jorb+Ns} c_{jorb}
        if(Norb>1.AND.Jhflag)then
           !
           do iorb=1,Norb
              do jorb=1,Norb
                 Jcondition=(&
                      (nup(jorb)==1).AND.&
                      (ndw(jorb)==1).AND.&
                      (ndw(iorb)==0).AND.&
                      (nup(iorb)==0))
                 if(Jcondition)then
                    call c(jorb,mdw,k1,sg1)       !c_jorb_dw
                    call cdg(iorb,k1,k2,sg2)       !c^+_iorb_dw
                    jdw = binary_search(H%dw,k2)
                    call c(jorb,mup,k1,sg1)       !c_jorb_up
                    call cdg(iorb,k1,k2,sg4)       !c^+_iorb_up
                    jup = binary_search(H%up,k2)
                    htmp = one*Jp*sg1*sg2*sg3*sg4
                    !
                    if(jup/=0.AND.jdw/=0)then
                       j = jup + (jdw-1)*dimup
                       call sp_insert_element(spH0,htmp,impi,j)
                    endif
                    !
                 endif
              enddo
           enddo
           !
        endif
        !
     enddo
  enddo
