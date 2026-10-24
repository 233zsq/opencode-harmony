// The npm compiler makes logic fixtures portable; DevEco remains a local fallback.
import {createRequire} from 'node:module';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';
const require=createRequire(import.meta.url);
function compiler(){
 try{return require('typescript');}
 catch(error){
  if(error.code!=='MODULE_NOT_FOUND')throw error;
  const sdk=resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
  if(existsSync(sdk))return require(sdk);
  throw new Error('TypeScript test dependency is unavailable. Run npm ci with Node.js 24 or configure DEVECO_STUDIO_HOME.');
 }
}
export const ts=compiler();
