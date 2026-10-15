// Diagnostic only. Install beside permission-json in an isolated test instance.
import {normalizeMetadata} from '../permission-json/index.js';
export default {
  id:'harmony.permission-json-fixture',
  async setup(context) {
    await context.permission.hook('evaluate',event=>{
      if(event.action!=='harmony.fixture')return;
      Object.assign(event.metadata,{root:'.',path:undefined,hidden:undefined,limit:undefined,nested:{absent:undefined,keep:false},values:[undefined,0]});
    });
    await context.permission.hook('evaluate',event=>{
      if(event.action==='harmony.fixture'&&event.metadata.mode==='green')normalizeMetadata(event.metadata);
    });
  }
};
