// Explicit offline suites: live service and device scripts are intentionally separate.
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const suites=['core','state','workspace-controls','agent-export','model-selection','attachments','permission-metadata','appearance','immersive-materials','native-driver','ui-palette','local-state','workspace-http','notifications','transcript-cache'];
for(const suite of suites){
 const result=spawnSync(process.execPath,[resolve(root,'tests',suite+'.test.mjs')],{cwd:root,stdio:'inherit'});
 if(result.error)throw result.error;
 if(result.status!==0)process.exit(result.status||1);
}
console.log(suites.length+' offline suites passed. Native ArkTS builds and device acceptance are separate.');
