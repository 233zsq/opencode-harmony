import assert from 'node:assert/strict';
import{api,scope}from'./live-api.mjs';
const root=process.env.OPENCODE_PERMISSION_TEST_ROOT;
if(!root?.startsWith('/'))throw new Error('Set OPENCODE_PERMISSION_TEST_ROOT to the dedicated fixture workspaces root');
const requests=[];
try{
 for(const mode of ['red','green']){
  const directory=root+'/approval-json-'+mode;await api('/api/location?'+scope(directory));
  const session=(await api('/api/session','POST',{title:'权限JSON隔离回归-'+mode,location:{directory}})).data;
  await api('/api/session/'+session.id,'PATCH',{permissions:[{action:'*',resource:'*',effect:'ask'}]});
  const requestID='per_harmony_fixture_'+mode+'_'+Date.now().toString(36);requests.push({sessionID:session.id,requestID,mode,directory});
  const creation=(await api('/api/session/'+session.id+'/permission?'+scope(directory),'POST',{id:requestID,action:'harmony.fixture',resources:['**/*.ts'],metadata:{mode}})).data;assert.equal(creation.effect,'ask');
  const path='/api/session/'+session.id+'/permission';
  if(mode==='red'){await assert.rejects(api(path),/HTTP 400$/);console.log('PASS unpatched real permission codec reproduces HTTP400 for undefined optional metadata.');}
  else{const list=(await api(path)).data;assert.equal(list.length,1);assert.equal(list[0].id,requestID);assert.deepEqual(list[0].metadata,{mode:'green',root:'.',nested:{keep:false},values:[null,0]});assert.equal(list[0].action,'harmony.fixture');assert.deepEqual(list[0].resources,['**/*.ts']);console.log('PASS official hook fixes real HTTP encoding while preserving scope and ask decision.');}
 }
 const red=requests[0];await assert.rejects(api('/api/session/'+red.sessionID+'/permission'),/HTTP 400$/);console.log('PASS test workspaces remain isolated; enabling green did not alter red.');
}finally{
 for(const r of requests)await api('/api/session/'+r.sessionID+'/permission/'+r.requestID+'/reply?'+scope(r.directory),'POST',{decision:'reject'}).catch(()=>{});
}
