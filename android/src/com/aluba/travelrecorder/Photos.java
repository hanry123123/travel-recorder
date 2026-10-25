package com.aluba.travelrecorder;
import android.Manifest;
import android.content.*;
import android.content.pm.*;
import android.database.*;
import android.graphics.*;
import android.media.ExifInterface;
import android.net.Uri;
import android.os.*;
import android.provider.MediaStore;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;

final class Photos {
 final Map<String,List<Runnable>> imageCallbacks=new HashMap<>();
 final TravelApplication app;final ExecutorService io=Executors.newSingleThreadExecutor();final Set<String> pending=ConcurrentHashMap.newKeySet();final java.util.concurrent.atomic.AtomicBoolean scanning=new java.util.concurrent.atomic.AtomicBoolean();
 final android.util.LruCache<String,Bitmap> cache=new android.util.LruCache<String,Bitmap>(16*1024*1024){protected int sizeOf(String k,Bitmap b){return b.getAllocationByteCount();}};
 private boolean observing;
 Photos(TravelApplication a){app=a;}
 void observe(){if(observing||!permitted())return;try{app.getContentResolver().registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,true,new ContentObserver(app.main){public void onChange(boolean self){app.main.postDelayed(()->scan(),1000);}});observing=true;}catch(SecurityException ignored){}}
 static String assetKey(Uri uri){if("com.android.providers.media.documents".equals(uri.getAuthority()))try{String doc=android.provider.DocumentsContract.getDocumentId(uri);if(doc.matches("image:[0-9]+"))return ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,Long.parseLong(doc.substring(6))).toString();}catch(Exception ignored){}return uri.toString();}

 boolean permitted(){return app.checkSelfPermission(Build.VERSION.SDK_INT>=33?Manifest.permission.READ_MEDIA_IMAGES:Manifest.permission.READ_EXTERNAL_STORAGE)==PackageManager.PERMISSION_GRANTED || Build.VERSION.SDK_INT>=34&&app.checkSelfPermission("android.permission.READ_MEDIA_VISUAL_USER_SELECTED")==PackageManager.PERMISSION_GRANTED;}
 boolean automatic(){return app.getSharedPreferences("prefs",0).getBoolean("autoPhotos",false);}
 void scan(){observe();if(!app.ready||!automatic()||!permitted()||!scanning.compareAndSet(false,true))return;final Models.Snapshot snapshot=app.state;io.execute(()->{try{
  long now=System.currentTimeMillis();for(Models.Trip t:snapshot.trips){if(t.status==2&&now-t.end>172800000)continue;
   String[] projection={MediaStore.Images.Media._ID,MediaStore.Images.Media.DATE_TAKEN,MediaStore.Images.Media.DATE_ADDED,MediaStore.Images.Media.DISPLAY_NAME};
   String selection=MediaStore.Images.Media.DATE_ADDED+">=?";String[] args={String.valueOf(t.start/1000-86400)};
   try(Cursor c=app.getContentResolver().query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,projection,selection,args,MediaStore.Images.Media.DATE_ADDED+" DESC")){if(c==null)continue;while(c.moveToNext()){
    long time=c.getLong(1);if(time<=0)time=c.getLong(2)*1000;if(!RouteMath.belongs(time,t.start,t.status==2?t.end:now)||c.getString(3)!=null&&c.getString(3).startsWith("TravelRecorder-"))continue;
    Uri uri=ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,c.getLong(0));importPhoto(uri,t.id,time,true);
   }}
  }
 }catch(Exception e){app.report("相册暂不可读取，可手动添加照片："+e.getMessage());}finally{scanning.set(false);}});}
 void importPhoto(Uri uri,String trip,long knownDate,boolean auto){String key=assetKey(uri);String token=trip+":"+key;if(!pending.add(token))return;
  app.work(()->{if(app.db.trip(trip)==null||app.db.excluded(trip,key)&&auto){pending.remove(token);return;}if(!auto)app.db.allow(trip,key);boolean existing=app.db.hasPhoto(trip,key);if(existing){
    Models.Photo existingPhoto=null;for(Models.Photo photo:app.state.photos(trip))if(photo.uri.equals(key)){existingPhoto=photo;break;}
    if(existingPhoto!=null&&existingPhoto.lat==null&&!existingPhoto.manual){final String photoId=existingPhoto.id;io.execute(()->{try{Uri source=uri;if(Build.VERSION.SDK_INT>=29&&"media".equals(source.getAuthority())&&app.checkSelfPermission(Manifest.permission.ACCESS_MEDIA_LOCATION)==PackageManager.PERMISSION_GRANTED)source=MediaStore.setRequireOriginal(source);float[] gps=new float[2];try(InputStream in=app.getContentResolver().openInputStream(source)){if(in!=null&&new ExifInterface(in).getLatLong(gps)&&RouteMath.valid(gps[0],gps[1]))app.work(()->{for(Models.Photo photo:app.db.snapshot().photos(trip))if(photo.id.equals(photoId)&&photo.lat==null&&!photo.manual){photo.lat=(double)gps[0];photo.lon=(double)gps[1];app.db.save(photo);app.publish();break;}});}}catch(Exception ignored){}finally{pending.remove(token);}});}else pending.remove(token);return;}

   io.execute(()->{Models.Photo photo=null;try{photo=prepare(uri,trip,knownDate,auto);final Models.Photo ready=photo;app.work(()->{try{if(app.db.trip(trip)==null||app.db.excluded(trip,key)||app.db.hasPhoto(trip,key)){remove(ready);return;}app.db.save(ready);app.publish();app.message="照片已保存在本机";}catch(Exception e){remove(ready);throw e;}finally{pending.remove(token);}});}catch(Exception e){if(photo!=null)remove(photo);pending.remove(token);app.report("照片暂未导入："+e.getMessage()+"，可稍后重试");}});
  });
 }
 void remove(Models.Photo p){new File(app.getFilesDir(),p.file).delete();new File(app.getFilesDir(),p.thumb).delete();}
 Models.Photo prepare(Uri input,String trip,long knownDate,boolean auto)throws Exception{
  Uri uri=input;if(Build.VERSION.SDK_INT>=29&&"media".equals(uri.getAuthority())&&app.checkSelfPermission(Manifest.permission.ACCESS_MEDIA_LOCATION)==PackageManager.PERMISSION_GRANTED)uri=MediaStore.setRequireOriginal(uri);
  File tmp=File.createTempFile("import-",".image",app.getCacheDir());Models.Photo p=new Models.Photo();p.trip=trip;p.uri=assetKey(input);p.time=knownDate>0?knownDate:System.currentTimeMillis();p.file="photos/"+p.id+".jpg";p.thumb="photos/"+p.id+"-thumb.jpg";new File(app.getFilesDir(),"photos").mkdirs();
  try{
   try(InputStream in=app.getContentResolver().openInputStream(uri);OutputStream out=new FileOutputStream(tmp)){if(in==null)throw new IOException("照片不可读取");byte[] b=new byte[32768];int n;long total=0;while((n=in.read(b))!=-1){total+=n;if(total>100L*1024*1024)throw new IOException("照片超过100MB");out.write(b,0,n);}}
   int orientation=1;try{ExifInterface exif=new ExifInterface(tmp.getPath());if(auto&&"TravelRecorder Share".equals(exif.getAttribute(ExifInterface.TAG_SOFTWARE)))throw new SharedImage();float[] gps=new float[2];if(exif.getLatLong(gps)&&RouteMath.valid(gps[0],gps[1])){p.lat=(double)gps[0];p.lon=(double)gps[1];}orientation=exif.getAttributeInt(ExifInterface.TAG_ORIENTATION,1);String date=exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL);if(date!=null){java.text.SimpleDateFormat f=new java.text.SimpleDateFormat("yyyy:MM:dd HH:mm:ss",Locale.US);f.setLenient(false);p.time=f.parse(date).getTime();}}catch(SharedImage e){throw new IOException("分享作品不会自动导入");}catch(IOException|java.text.ParseException ignored){}
   BitmapFactory.Options opts=new BitmapFactory.Options();opts.inJustDecodeBounds=true;BitmapFactory.decodeFile(tmp.getPath(),opts);if(opts.outWidth<=0||opts.outHeight<=0)throw new IOException("格式无法读取");opts.inSampleSize=1;while(Math.max(opts.outWidth,opts.outHeight)/opts.inSampleSize>2560)opts.inSampleSize*=2;opts.inJustDecodeBounds=false;Bitmap raw=BitmapFactory.decodeFile(tmp.getPath(),opts);if(raw==null)throw new IOException("图片解码失败");Matrix m=new Matrix();switch(orientation){case 2:m.setScale(-1,1);break;case 3:m.setRotate(180);break;case 4:m.setScale(1,-1);break;case 5:m.setRotate(90);m.postScale(-1,1);break;case 6:m.setRotate(90);break;case 7:m.setRotate(-90);m.postScale(-1,1);break;case 8:m.setRotate(-90);break;}
   Bitmap image=Bitmap.createBitmap(raw,0,0,raw.getWidth(),raw.getHeight(),m,true);write(image,new File(app.getFilesDir(),p.file));float factor=Math.min(1,320f/Math.max(image.getWidth(),image.getHeight()));Bitmap thumb=Bitmap.createScaledBitmap(image,Math.max(1,Math.round(image.getWidth()*factor)),Math.max(1,Math.round(image.getHeight()*factor)),true);write(thumb,new File(app.getFilesDir(),p.thumb));if(thumb!=image)thumb.recycle();if(image!=raw)image.recycle();raw.recycle();return p;
  }catch(Exception e){remove(p);throw e;}finally{tmp.delete();}
 }
 static final class SharedImage extends Exception{}
 static void write(Bitmap b,File f)throws IOException {File temp=new File(f.getPath()+".tmp");try(FileOutputStream out=new FileOutputStream(temp)){if(!b.compress(Bitmap.CompressFormat.JPEG,90,out))throw new IOException("图片保存失败");out.getFD().sync();}if(!temp.renameTo(f)){temp.delete();throw new IOException("图片提交失败");}}
 Bitmap cached(String file){return cache.get(file);}
 void load(String file,Runnable done){
  if(file==null)return;
  synchronized(imageCallbacks){if(cache.get(file)!=null){app.main.post(done);return;}List<Runnable> callbacks=imageCallbacks.get(file);if(callbacks!=null){callbacks.add(done);return;}callbacks=new ArrayList<>();callbacks.add(done);imageCallbacks.put(file,callbacks);}
  io.execute(()->{try{BitmapFactory.Options o=new BitmapFactory.Options();o.inSampleSize=file.endsWith("-thumb.jpg")?1:2;Bitmap b=BitmapFactory.decodeFile(new File(app.getFilesDir(),file).getPath(),o);if(b!=null)cache.put(file,b);}finally{List<Runnable> callbacks;synchronized(imageCallbacks){callbacks=imageCallbacks.remove(file);}if(callbacks!=null)for(Runnable callback:callbacks)app.main.post(callback);}});
 }
}
