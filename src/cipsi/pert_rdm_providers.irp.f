
use bitmasks
use omp_lib

BEGIN_PROVIDER [ integer(omp_lock_kind), pert_2rdm_lock]
  use f77_zmq
  implicit none
  call omp_init_lock(pert_2rdm_lock)
END_PROVIDER

BEGIN_PROVIDER [integer, n_orb_pert_rdm]
 implicit none
 n_orb_pert_rdm = n_act_orb
END_PROVIDER 

BEGIN_PROVIDER [integer, list_orb_reverse_pert_rdm, (mo_num)]
 implicit none
 list_orb_reverse_pert_rdm = list_act_reverse

END_PROVIDER 

BEGIN_PROVIDER [integer, list_orb_pert_rdm, (n_orb_pert_rdm)]
 implicit none
 list_orb_pert_rdm = list_act

END_PROVIDER

BEGIN_PROVIDER [double precision, pert_2rdm_provider, (n_orb_pert_rdm,n_orb_pert_rdm,n_orb_pert_rdm,n_orb_pert_rdm)]
 implicit none
 pert_2rdm_provider = 0.d0

END_PROVIDER

subroutine fill_buffer_double_rdm(i_generator, sp, h1, h2, bannedOrb, banned, fock_diag_tmp, E0, pt2, variance, norm, mat, buf, psi_det_connection, psi_coef_connection_reverse, n_det_connection)
  use bitmasks
  use selection_types
  implicit none
  
  integer, intent(in)           :: n_det_connection
  double precision, intent(in)  :: psi_coef_connection_reverse(N_states,n_det_connection)
  integer(bit_kind), intent(in) :: psi_det_connection(N_int,2,n_det_connection)
  integer, intent(in) :: i_generator, sp, h1, h2
  double precision, intent(in) :: mat(N_states, mo_num, mo_num)
  logical, intent(in) :: bannedOrb(mo_num, 2), banned(mo_num, mo_num)
  double precision, intent(in)           :: fock_diag_tmp(mo_num)
  double precision, intent(in)    :: E0(N_states)
  double precision, intent(inout) :: pt2(N_states)
  double precision, intent(inout) :: variance(N_states)
  double precision, intent(inout) :: norm(N_states)
  type(selection_buffer), intent(inout) :: buf
  logical :: ok
  integer :: s1, s2, p1, p2, ib, j, istate
  integer(bit_kind) :: mask(N_int, 2), det(N_int, 2)
  double precision :: e_pert, delta_E, val, Hii, sum_e_pert, tmp, alpha_h_psi, coef(N_states)
  double precision, external :: diag_H_mat_elem_fock
  double precision :: E_shift

  logical, external :: detEq
  double precision, allocatable :: values(:)
  integer, allocatable          :: keys(:,:)
  integer                       :: nkeys
  integer :: sze_buff
  sze_buff = 5 * mo_num ** 2 
  allocate(keys(4,sze_buff),values(sze_buff))
  nkeys = 0
  if(sp == 3) then
    s1 = 1
    s2 = 2
  else
    s1 = sp
    s2 = sp
  end if
  call apply_holes(psi_det_generators(1,1,i_generator), s1, h1, s2, h2, mask, ok, N_int)
  E_shift = 0.d0

  if (h0_type == 'SOP') then
    j = det_to_occ_pattern(i_generator)
    E_shift = psi_det_Hii(i_generator) - psi_occ_pattern_Hii(j)
  endif

  do p1=1,mo_num
    if(bannedOrb(p1, s1)) cycle
    ib = 1
    if(sp /= 3) ib = p1+1

    do p2=ib,mo_num

! -----
! /!\ Generating only single excited determinants doesn't work because a
! determinant generated by a single excitation may be doubly excited wrt
! to a determinant of the future. In that case, the determinant will be
! detected as already generated when generating in the future with a
! double excitation.
!     
!      if (.not.do_singles) then
!        if ((h1 == p1) .or. (h2 == p2)) then
!          cycle
!        endif
!      endif
!
!      if (.not.do_doubles) then
!        if ((h1 /= p1).and.(h2 /= p2)) then
!          cycle
!        endif
!      endif
! -----

      if(bannedOrb(p2, s2)) cycle
      if(banned(p1,p2)) cycle


      if( sum(abs(mat(1:N_states, p1, p2))) == 0d0) cycle
      call apply_particles(mask, s1, p1, s2, p2, det, ok, N_int)

      if (do_only_cas) then
        integer, external :: number_of_holes, number_of_particles
        if (number_of_particles(det)>0) then
          cycle
        endif
        if (number_of_holes(det)>0) then
          cycle
        endif
      endif

      if (do_ddci) then
        logical, external  :: is_a_two_holes_two_particles
        if (is_a_two_holes_two_particles(det)) then
          cycle
        endif
      endif

      if (do_only_1h1p) then
        logical, external :: is_a_1h1p
        if (.not.is_a_1h1p(det)) cycle
      endif


      Hii = diag_H_mat_elem_fock(psi_det_generators(1,1,i_generator),det,fock_diag_tmp,N_int)

      sum_e_pert = 0d0
      integer :: degree
      call get_excitation_degree(det,HF_bitmask,degree,N_int)
      if(degree == 2)cycle
      do istate=1,N_states
        delta_E = E0(istate) - Hii + E_shift
        alpha_h_psi = mat(istate, p1, p2)
        val = alpha_h_psi + alpha_h_psi
        tmp = dsqrt(delta_E * delta_E + val * val)
        if (delta_E < 0.d0) then
            tmp = -tmp
        endif
        e_pert = 0.5d0 * (tmp - delta_E)
        coef(istate) = e_pert / alpha_h_psi
        print*,e_pert,coef,alpha_h_psi
        pt2(istate) = pt2(istate) + e_pert
        variance(istate) = variance(istate) + alpha_h_psi * alpha_h_psi
        norm(istate) = norm(istate) + coef(istate) * coef(istate)

        if (weight_selection /= 5) then
          ! Energy selection
          sum_e_pert = sum_e_pert + e_pert * selection_weight(istate)

        else
          ! Variance selection
          sum_e_pert = sum_e_pert - alpha_h_psi * alpha_h_psi * selection_weight(istate)
        endif
      end do
      call give_2rdm_pert_contrib(det,coef,psi_det_connection,psi_coef_connection_reverse,n_det_connection,nkeys,keys,values,sze_buff)

      if(sum_e_pert <= buf%mini) then
        call add_to_selection_buffer(buf, det, sum_e_pert)
      end if
    end do
  end do
  call update_keys_values(keys,values,nkeys,n_orb_pert_rdm,pert_2rdm_provider,pert_2rdm_lock)
end


