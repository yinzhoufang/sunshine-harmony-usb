"""Publish this repository's reviewed 1.0.4 assets using GitHub Actions' token."""
import hashlib, json, os
from pathlib import Path
import urllib.error, urllib.parse, urllib.request

REPO=os.environ['GITHUB_REPOSITORY']
TOKEN=os.environ['GH_TOKEN']
BASE='https://api.github.com/repos/'+REPO
ASSETS=Path('release-assets')
TAG='v1.0.4'

def api(url, data=None, method=None, raw=None):
    if not (url.startswith(BASE+'/') or url.startswith('https://uploads.github.com/repos/'+REPO+'/')):
        raise ValueError('Unexpected API destination')
    body=raw
    headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','User-Agent':'channel-release-publisher'}
    if data is not None:
        body=json.dumps(data).encode('utf-8'); headers['Content-Type']='application/json'
    elif raw is not None:headers['Content-Type']='application/octet-stream'
    req=urllib.request.Request(url,data=body,headers=headers,method=method)
    with urllib.request.urlopen(req,timeout=120) as r:return json.load(r)

names=['Channel-1.0.4-device-test.hap','Sunshine-Harmony-USB-0.5.9-usb.3-Setup.exe','Sunshine-Harmony-USB-0.5.9-usb.3.zip','SHA256SUMS.txt']
body=Path('docs/RELEASE_1.0.4.md').read_text(encoding='utf-8')
body=body.replace('](docs/','](https://github.com/'+REPO+'/blob/main/docs/')
try:r=api(BASE+'/releases/tags/'+TAG)
except urllib.error.HTTPError as e:
    if e.code!=404:raise
    r=api(BASE+'/releases',{'tag_name':TAG,'target_commitish':os.environ['GITHUB_SHA'],'name':'Channel 1.0.4 · 鸿蒙 HAP 与 Windows 补丁安装器','body':body,'draft':True,'prerelease':True})
existing={a['name']:a for a in r.get('assets',[])}
# Published binaries are immutable. Re-running after a documentation change
# updates release notes without replacing a timestamp-dependent EXE build.
if not r['draft'] and set(names).issubset(existing):
    if existing[names[0]].get('digest')!='sha256:b44c8dccf914a5d256e2a28a9ea01d3f46bee4bd9fb25329c2ac36c1a09432ef':
        raise RuntimeError('Published HAP is not the tested version')
    r=api(BASE+'/releases/'+str(r['id']),{'body':body},method='PATCH')
    print('Updated notes; published binaries preserved:',r['html_url'])
    raise SystemExit(0)
sums=''.join(hashlib.sha256((ASSETS/n).read_bytes()).hexdigest()+'  '+n+'\n' for n in names if n!='SHA256SUMS.txt')
(ASSETS/'SHA256SUMS.txt').write_text(sums,encoding='ascii')
for name in names:
    payload=(ASSETS/name).read_bytes()
    expected='sha256:'+hashlib.sha256(payload).hexdigest()
    if name in existing:
        if existing[name].get('digest')!=expected:raise RuntimeError('Existing asset differs; refusing to overwrite: '+name)
        continue
    asset=api(r['upload_url'].split('{',1)[0]+'?name='+urllib.parse.quote(name),method='POST',raw=payload)
    if asset.get('size')!=len(payload) or asset.get('state')!='uploaded':raise RuntimeError('Incomplete asset: '+name)
    if asset.get('digest') and asset['digest']!=expected:raise RuntimeError('Remote digest mismatch: '+name)
    print('Uploaded',name,len(payload))
r=api(BASE+'/releases/'+str(r['id']),{'body':body,'draft':False,'prerelease':True},method='PATCH')
print('Published',r['html_url'])
