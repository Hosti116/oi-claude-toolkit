import { CommonModule } from '@angular/common';
import { NgModule } from '@angular/core';
import { ClassloggerService } from 'qbm';
import { InitService } from './init.service';

/** Entry module of the ccc plugin, loaded at runtime by qer-app-portal (see imx-plugin-config.json). */
@NgModule({
  imports: [CommonModule],
})
export class CccConfigModule {
  constructor(
    private readonly initializer: InitService,
    private readonly logger: ClassloggerService,
  ) {
    this.logger.info(this, 'CCC loaded');
    this.initializer.onInit();
    this.logger.info(this, 'CCC initialized');
  }
}
