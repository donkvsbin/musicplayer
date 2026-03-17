import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { abilityAccessCtrl, PermissionRequestResult, Permissions } from '@kit.AbilityKit';

const DOMAIN = 0x0000;

// 需要的权限列表
const REQUIRED_PERMISSIONS: Array<Permissions> = [
  'ohos.permission.READ_MEDIA',
  'ohos.permission.WRITE_MEDIA',
  'ohos.permission.INTERNET'
];

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    
    // 申请必要权限
    this.requestPermissions();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 设置窗口沉浸式
    this.setWindowImmersive(windowStage);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  /**
   * 申请必要权限
   */
  private requestPermissions(): void {
    const atManager = abilityAccessCtrl.createAtManager();
    
    try {
      atManager.requestPermissionsFromUser(this.context, REQUIRED_PERMISSIONS)
        .then((data: PermissionRequestResult) => {
          const grantStatus: Array<number> = data.authResults;
          const length: number = grantStatus.length;
          
          for (let i = 0; i < length; i++) {
            if (grantStatus[i] === 0) {
              // 权限被授予
              hilog.info(DOMAIN, 'testTag', 'Permission %{public}s granted', REQUIRED_PERMISSIONS[i]);
            } else {
              // 权限被拒绝
              hilog.warn(DOMAIN, 'testTag', 'Permission %{public}s denied', REQUIRED_PERMISSIONS[i]);
            }
          }
        })
        .catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to request permissions. Cause: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to request permissions. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 设置窗口布局
   * 设置状态栏和导航栏背景色与 App 背景一致
   */
  private setWindowImmersive(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((err, window) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to get main window. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      
      // 设置布局为全屏，让应用绘制到状态栏和导航栏区域
      window.setLayoutFullScreen(true)
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'Set layout fullscreen success');
        })
        .catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to set layout fullscreen. Cause: %{public}s', JSON.stringify(err));
        });
      
      // 设置状态栏背景色（透明，让应用背景显示出来）
      window.setWindowSystemBarEnable(['status', 'navigation'])
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'Set system bar enable success');
        })
        .catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to set system bar enable. Cause: %{public}s', JSON.stringify(err));
        });
      
      // 设置系统栏背景颜色为透明
      const systemBarProperties: window.SystemBarProperties = {
        statusBarColor: '#00000000',  // 透明
        navigationBarColor: '#00000000',  // 透明
        statusBarContentColor: '#000000',  // 状态栏文字黑色
        navigationBarContentColor: '#000000'  // 导航栏文字黑色
      };
      
      window.setWindowSystemBarProperties(systemBarProperties)
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'Set system bar properties success');
        })
        .catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to set system bar properties. Cause: %{public}s', JSON.stringify(err));
        });
    });
  }
}