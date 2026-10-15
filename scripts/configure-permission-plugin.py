"""Operator-only plugin registration for this application's owned instance."""
import pathlib,json,os,pwd,grp,fcntl,tempfile,sys,time
root=pathlib.Path('/var/lib/opencode-harmony-root');app=root/'home/ubuntu/opencode-harmony-service';folder=app/'config/opencode';config=folder/'opencode.json'
assert(root/'.opencode-harmony-jail-owned').is_file()
name=sys.argv[2];assert name in ('permission-json','permission-json-fixture');assert sys.argv[1] in ('add','remove')
plugin='/home/ubuntu/opencode-harmony-service/plugins/'+name
assert(app/'plugins'/name/'index.js').is_file();assert not (app/'plugins'/name).is_symlink()
uid=pwd.getpwnam('oc-harmony-agent').pw_uid;gid=grp.getgrnam('oc-harmony-agent').gr_gid
folder.mkdir(parents=True,exist_ok=True)
assert not config.is_symlink()
for path in (root,app,folder,app/'plugins',app/'plugins'/name):
    assert not path.is_symlink() and path.resolve().is_relative_to(root.resolve())
assert config.exists() or not(folder/'opencode.jsonc').exists()
lock=folder/'.mobile-settings.lock'
lock_fd=os.open(lock,os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
os.fchmod(lock_fd,0o600);os.fchown(lock_fd,uid,gid)
with os.fdopen(lock_fd,'a') as handle:
    fcntl.flock(handle,fcntl.LOCK_EX)
    value=json.loads(config.read_text()) if config.exists() else {}
    plugins=value.get('plugins',[]);assert isinstance(plugins,list)
    if config.exists():
        backup=folder/('.permission-plugin-backup-'+str(time.time_ns())+'.json')
        with os.fdopen(os.open(backup,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600),'w') as output:
            output.write(config.read_text());output.flush();os.fsync(output.fileno())
    def target(item):return item if isinstance(item,str) else item.get('package') if isinstance(item,dict) else None
    plugins=[item for item in plugins if target(item)!=plugin]
    if sys.argv[1]=='add':plugins.append(plugin)
    value['plugins']=plugins
    fd,temporary=tempfile.mkstemp(prefix='.permission-plugin-',dir=folder)
    try:
        os.fchmod(fd,0o600);os.fchown(fd,uid,gid)
        with os.fdopen(fd,'w') as output:json.dump(value,output,ensure_ascii=False,indent=2);output.write('\n');output.flush();os.fsync(output.fileno())
        os.replace(temporary,config)
        directory_fd=os.open(folder,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(directory_fd)
        finally:os.close(directory_fd)
    finally:
        if os.path.exists(temporary):os.unlink(temporary)
print('Updated only owned instance plugin registration:',sys.argv[1],name)
