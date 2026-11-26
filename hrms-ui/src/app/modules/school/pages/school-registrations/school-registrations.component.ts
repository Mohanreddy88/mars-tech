import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { SchoolStudentsComponent } from '../school-students/school-students.component';
import { SchoolParentsComponent } from '../school-parents/school-parents.component';
import { SchoolFamiliesComponent } from '../school-families/school-families.component';
import { RegistrationWizardComponent } from '../../components/registration-wizard/registration-wizard.component';

export type RegistrationTab = 'children' | 'parents' | 'families';

/**
 * School → Registrations (admin): children, parents and families on one page as tabs, plus
 * "New registration" (child + mother + father in one go). The old /school/students, /parents and
 * /families addresses redirect here (Children stays reachable for teachers as "My Class").
 */
@Component({
  selector: 'app-school-registrations',
  standalone: true,
  imports: [CommonModule, SchoolStudentsComponent, SchoolParentsComponent, SchoolFamiliesComponent, RegistrationWizardComponent],
  templateUrl: './school-registrations.component.html',
  styleUrls: ['../../school-shared.scss', './school-registrations.component.scss']
})
export class SchoolRegistrationsComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private cdr = inject(ChangeDetectorRef);

  readonly tabs: { key: RegistrationTab; label: string; icon: string }[] = [
    { key: 'children', label: 'Children', icon: 'bi-emoji-smile' },
    { key: 'parents', label: 'Parents', icon: 'bi-people' },
    { key: 'families', label: 'Families', icon: 'bi-diagram-3' },
  ];

  tab: RegistrationTab = 'children';
  wizard = false;
  /** Bumped after a registration so the open tab reloads its list. */
  version = 0;

  ngOnInit(): void {
    this.route.paramMap.subscribe(p => {
      const t = p.get('tab') as RegistrationTab | null;
      this.tab = t && this.tabs.some(x => x.key === t) ? t : 'children';
      this.cdr.markForCheck();
    });
  }

  setTab(t: RegistrationTab): void {
    if (t !== this.tab) this.router.navigate(['/school/registrations', t]);
  }

  wizardClosed(saved: boolean): void {
    this.wizard = false;
    if (saved) this.version++;
  }
}
