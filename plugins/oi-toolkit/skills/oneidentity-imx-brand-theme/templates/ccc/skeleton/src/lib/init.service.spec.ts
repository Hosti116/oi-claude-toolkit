import { InitService } from './init.service';
import { BrandThemeService } from './brand-theme/brand-theme.service';

describe('InitService', () => {
  it('starts the runtime support of the brand themes', () => {
    // Arrange
    const brandTheme = jasmine.createSpyObj<BrandThemeService>('BrandThemeService', ['start']);

    // Act
    new InitService(brandTheme).onInit();

    // Assert
    expect(brandTheme.start).toHaveBeenCalledTimes(1);
  });
});
