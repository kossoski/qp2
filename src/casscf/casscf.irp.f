program casscf
  implicit none
  BEGIN_DOC
! TODO : Put the documentation of the program here
  END_DOC
  no_vvvv_integrals = .True.
  pt2_max = 0.02
  SOFT_TOUCH no_vvvv_integrals pt2_max
  call run_stochastic_cipsi
  call run
end

subroutine run
  implicit none
  double precision               :: energy_old, energy
  logical                        :: converged,state_following_casscf_save
  integer                        :: iteration
  converged = .False.

  energy = 0.d0
  mo_label = "MCSCF"
  iteration = 1
  state_following_casscf_save = state_following_casscf
  state_following_casscf = .True.
  touch state_following_casscf
  do while (.not.converged)
    call run_stochastic_cipsi
    energy_old = energy
    energy = eone+etwo+ecore

    call write_time(6)
    call write_int(6,iteration,'CAS-SCF iteration')
    call write_double(6,energy,'CAS-SCF energy')
    call write_double(6,energy_improvement, 'Predicted energy improvement')

    converged = dabs(energy_improvement) < thresh_scf
    pt2_max = dabs(energy_improvement / pt2_relative_error)

    mo_coef = NewOrbs
    call save_mos
    iteration += 1
    N_det = N_det/2 
    psi_det = psi_det_sorted
    psi_coef = psi_coef_sorted
    read_wf = .True.
    call clear_mo_map
    SOFT_TOUCH mo_coef N_det pt2_max  psi_det psi_coef 
    if(iteration .gt. 3)then
     state_following_casscf = state_following_casscf_save 
     touch state_following_casscf
    endif

  enddo

end
