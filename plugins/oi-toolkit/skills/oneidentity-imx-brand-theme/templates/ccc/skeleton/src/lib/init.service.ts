import { Injectable } from '@angular/core';
import { BrandThemeService } from './brand-theme/brand-theme.service';

@Injectable({
  providedIn: 'root',
})
export class InitService {
  constructor(private readonly brandTheme: BrandThemeService) {}

  public onInit(): void {
    this.brandTheme.start();
  }
}
