/** System user (login) as returned by the API */
export interface AppUser {
  id: number;
  username: string;
  email: string;
  role: string;
  isActive: boolean;
  createdAt: string;
  /** Employee with the same email (that is how a login belongs to an employee), or null */
  employee: { id: number; name: string; employeeCode: string; isActive: boolean } | null;
  /** Something the admin should look at, e.g. "Employee is inactive but the login is active" */
  warning: string | null;
}

/** New login: Employee role → employeeId; Admin / User → username + email. A set-password email is sent. */
export interface UserRequest {
  role: string;
  employeeId?: number | null;
  username?: string;
  email?: string;
}

/** Payload for updating an existing user */
export interface UserUpdateRequest {
  username: string;
  email: string;
  role: string;
  isActive: boolean;
  password?: string;  // optional — omit to keep existing password
}

/** Active employee without a login (for the Employee-role dropdown) */
export interface AvailableEmployee {
  id: number;
  name: string;
  employeeCode: string;
  email: string;
}
