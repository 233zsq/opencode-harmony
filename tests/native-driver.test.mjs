import assert from 'node:assert/strict';
import {keyboardVisible} from './native-driver.mjs';
const node=(id,type,bounds,extra={})=>({id,type,bounds,visible:'true',...extra});
assert.equal(keyboardVisible([node('keyboardPanel30','WindowScene','[0,0][1280,2832]',{bundleName:'com.ohos.sceneboard'}),node('keyboard145','WindowScene','[0,0][1280,2832]')]),true);console.log('PASS API26 keyboard windows are recognized even without an inputmethod bundle name');
assert.equal(keyboardVisible([node('session27','WindowScene','[0,0][1280,136]',{bundleName:'com.ohos.sceneboard'}),node('','root','[0,0][1280,2832]',{bundleName:'com.example.opencode_harmony'})]),false);console.log('PASS the status bar and app root are not mistaken for a keyboard');
assert.equal(keyboardVisible([node('keyboardPanel30','WindowScene','[0,0][1280,2832]',{visible:'false'})]),false);console.log('PASS hidden keyboard windows do not consume application-level Back tests');
assert.equal(keyboardVisible([node('legacy-ime','WindowScene','[0,1800][1280,2832]',{bundleName:'com.huawei.hmos.inputmethod'})]),true);console.log('PASS legacy inputmethod windows remain recognized');
console.log('4 native automation keyboard tests passed.');
