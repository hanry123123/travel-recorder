from pathlib import Path
import os,subprocess,zipfile,shutil
r=Path(__file__).resolve().parent;t=Path.home()/'.local/share/travel-android-tools';j=t/'jdk-17.0.16+8/Contents/Home';b=t/'android-15';a=t/'android-35/android.jar';out=r/'build/device-tests';out.mkdir(exist_ok=True);classes=out/'classes';classes.mkdir(exist_ok=True);dex=out/'dex';dex.mkdir(exist_ok=True)
env=dict(os.environ,JAVA_HOME=str(j),PATH=str(j/'bin')+os.pathsep+os.environ['PATH'])
def run(args):subprocess.run([str(x) for x in args],check=True,env=env)
run([j/'bin/javac','-encoding','UTF-8','--release','8','-classpath',str(a)+os.pathsep+str(r/'build/classes.jar'),'-d',classes,r/'tests/DeviceChecks.java'])
run([j/'bin/jar','cf',out/'classes.jar','-C',classes,'.'])
run([b/'d8','--min-api','26','--lib',a,'--classpath',r/'build/classes.jar','--output',dex,out/'classes.jar'])
run([b/'aapt2','link','--manifest',r/'tests/AndroidManifest.xml','-I',a,'-o',out/'unsigned.apk'])
with zipfile.ZipFile(out/'unsigned.apk','a',compression=zipfile.ZIP_DEFLATED) as z:
 for p in dex.glob('*.dex'):z.write(p,p.name)
run([b/'zipalign','-f','4',out/'unsigned.apk',out/'aligned.apk'])
s=Path.home()/'.local/share/travel-recorder-signing'
run([b/'apksigner','sign','--ks',s/'android-release.p12','--ks-pass','file:'+str(s/'android-password'),'--out',out/'tests.apk',out/'aligned.apk'])
