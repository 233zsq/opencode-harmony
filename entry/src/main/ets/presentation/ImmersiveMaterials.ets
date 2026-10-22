import deviceInfo from '@ohos.deviceInfo';

export interface ImmersiveSurfaces { popup?: SystemUiMaterial; sheet?: SystemUiMaterial; }

// A guarded dynamic import keeps the API26-only native module out of API24 startup.
export async function loadImmersiveMaterials(): Promise<ImmersiveSurfaces> {
  if (deviceInfo.sdkApiVersion < 26) { return {}; }
  if (!deviceInfo.apiAvailable('26.0.0')) { return {}; }
  try {
    const native = await import('@ohos.arkui.uiMaterial');

    return {
      popup: new native.default.ImmersiveMaterial({ style: native.default.ImmersiveStyle.THIN, lightEffect: { color: '#B3CBE5FF' } }),
      sheet: new native.default.ImmersiveMaterial({ style: native.default.ImmersiveStyle.REGULAR })
    };
  } catch (_) { return {}; }
}
