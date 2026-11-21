import { inject } from '@angular/core';
import { CanActivateChildFn, CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

/** Pages a parent login may open (everything else is HR and belongs to staff). */
const PARENT_PAGES = ['/parent', '/notifications', '/self-service/change-password'];

const isParent = () => inject(AuthService).getRole() === 'Parent';

/** On the main layout: keeps parent logins inside the parent portal. */
export const parentAreaGuard: CanActivateChildFn = (_route, state) => {
  if (!isParent()) return true;
  const url = state.url.split('?')[0];
  return PARENT_PAGES.some(p => url === p || url.startsWith(p + '/'))
    ? true
    : inject(Router).createUrlTree(['/parent']);
};

/** The parent portal pages are for parent logins only. */
export const parentOnlyGuard: CanActivateFn = () =>
  isParent() ? true : inject(Router).createUrlTree(['/']);
