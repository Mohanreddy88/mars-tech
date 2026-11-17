import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

/** Super Admin portal pages: logged in with the SuperAdmin role. */
export const superAdminGuard: CanActivateFn = () => {
  const auth   = inject(AuthService);
  const router = inject(Router);
  return auth.isAuthenticated() && auth.getRole() === 'SuperAdmin' ? true : router.createUrlTree(['/login']);
};
