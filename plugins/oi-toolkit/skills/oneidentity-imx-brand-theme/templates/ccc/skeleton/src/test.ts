// This file is required by karma.conf.js and loads recursively all the .spec and framework files

// Zone must be imported first. Be careful with prettier import organizing
import 'zone.js';
import 'zone.js/testing';

import { getTestBed } from '@angular/core/testing';
import { BrowserDynamicTestingModule, platformBrowserDynamicTesting } from '@angular/platform-browser-dynamic/testing';
import 'core-js/es/reflect';
import { TestHelperModule } from 'qbm';

// First, initialize the Angular testing environment.
getTestBed().initTestEnvironment([BrowserDynamicTestingModule, TestHelperModule], platformBrowserDynamicTesting());
