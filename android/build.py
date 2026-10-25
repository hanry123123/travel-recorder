#!/usr/bin/env python3
"""Native Android SDK build: javac -> D8 -> AAPT2 -> zipalign -> apksigner."""
from pathlib import Path
import subprocess,os,zipfile,shutil,json,hashlib,secrets
root=Path(__file__).resolve().parent
sdk=Path(os.environ.get('TRAVEL_ANDROID_TOOLS',str(Path.home()/'.local/share/travel-android-tools')))
java=sdk/'jdk-17.0.16+8/Contents/Home';bt=sdk/'android-15';platform=sdk/'android-35/android.jar'
if not platform.exists():
 matches=list(sdk.glob('*/android.jar'));assert len(matches)==1,matches;platform=matches[0]
out=root/'build';out.mkdir(exist_ok=True)
env=dict(os.environ,JAVA_HOME=str(java),PATH=str(java/'bin')+os.pathsep+os.environ['PATH'])
log=(out/'build.log').open('w')
def run(args):
 log.write('RUN '+str(args)+'\n');log.flush();subprocess.run([str(x) for x in args],env=env,stdout=log,stderr=subprocess.STDOUT,check=True,cwd=root)
for name in ['classes','gen','dex']:
 p=out/name
 if p.exists():shutil.rmtree(p)
 p.mkdir()
try:
 run([bt/'aapt2','compile','--dir',root/'res','-o',out/'resources.zip'])
 run([bt/'aapt2','link','-o',out/'unsigned.apk','--manifest',root/'AndroidManifest.xml','-I',platform,'--java',out/'gen','-A',root/'assets',out/'resources.zip'])
 sources=sorted((root/'src').rglob('*.java'))+sorted((out/'gen').rglob('*.java'))
 run([java/'bin/javac','-encoding','UTF-8','--release','8','-classpath',platform,'-d',out/'classes']+sources)
 run([java/'bin/jar','cf',out/'classes.jar','-C',out/'classes','.'])
 run([bt/'d8','--release','--min-api','26','--lib',platform,'--output',out/'dex',out/'classes.jar'])
 with zipfile.ZipFile(out/'unsigned.apk','a',compression=zipfile.ZIP_DEFLATED) as z:
  for p in (out/'dex').glob('*.dex'):z.write(p,p.name)
 run([bt/'zipalign','-f','4',out/'unsigned.apk',out/'aligned.apk'])
 signing=Path.home()/'.local/share/travel-recorder-signing';signing.mkdir(exist_ok=True,mode=0o700)
 password=signing/'android-password';key=signing/'android-release.p12'
 if not password.exists():password.write_text(secrets.token_urlsafe(32));password.chmod(0o600)
 if not key.exists():run([java/'bin/keytool','-genkeypair','-keystore',key,'-storepass:file',password,'-keypass:file',password,'-alias','travel-recorder','-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=TravelRecorder']);key.chmod(0o600)
 apk=out/'TravelRecorder-1.4.1.apk'
 run([bt/'apksigner','sign','--ks',key,'--ks-pass','file:'+str(password),'--ks-key-alias','travel-recorder','--out',apk,out/'aligned.apk'])
 run([bt/'apksigner','verify','--verbose','--print-certs',apk])
 run([bt/'zipalign','-c','4',apk])
 run([bt/'aapt2','dump','badging',apk])
 (out/'receipt.json').write_text(json.dumps({'version':'1.4.1','min_sdk':26,'target_sdk':35,'apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'source_files':len(sources),'signed':True,'native_libraries':False},indent=2)+'\n')
 print('APK BUILT',apk,hashlib.sha256(apk.read_bytes()).hexdigest())
except Exception:
 log.flush();print((out/'build.log').read_text()[-12000:]);raise
