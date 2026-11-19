import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';
import { AuthService } from '../services/auth.service';

/** localStorage flags the login page reads to explain why the user was signed out. */
export const SIGNED_OUT_REASON = {
  replaced: 'session_replaced',   // the account signed in on another device or browser
  expired:  'session_expired',
} as const;

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth   = inject(AuthService);
  const router = inject(Router);
  const token  = auth.getToken();

  if (!token) return next(req);

  const cloned = req.clone({ setHeaders: { Authorization: `Bearer ${token}` } });
  return next(cloned).pipe(
    catchError((err: unknown) => {
      // The company login was refused: signed in elsewhere (one login at a time) or the token expired.
      if (err instanceof HttpErrorResponse && err.status === 401 && !req.url.includes('/auth/')) {
        const replaced = err.error?.code === 'session_replaced';
        try {
          localStorage.setItem(replaced ? SIGNED_OUT_REASON.replaced : SIGNED_OUT_REASON.expired, 'true');
        } catch { /* storage unavailable: the login page just shows no message */ }
        auth.clearSession();
        if (!router.url.startsWith('/login')) router.navigate(['/login']);
      }
      return throwError(() => err);
    })
  );
};
