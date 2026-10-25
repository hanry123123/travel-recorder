package com.aluba.travelrecorder;
import android.graphics.*;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.*;

/** Visible tiles only; attribution is drawn last by MapCanvas. No prefetch/offline packs. */
final class TileCache {
 final TravelApplication app;final File root;final ExecutorService io=Executors.newFixedThreadPool(2);
 final android.util.LruCache<String,Bitmap> memory=new android.util.LruCache<String,Bitmap>(24*1024*1024){protected int sizeOf(String k,Bitmap b){return b.getAllocationByteCount();}};
 final Set<String> pending=ConcurrentHashMap.newKeySet();final Map<String,Long> retry=new ConcurrentHashMap<>();volatile boolean unavailable;
 TileCache(TravelApplication a){app=a;root=new File(a.getCacheDir(),"tiles");root.mkdirs();}
 Bitmap tile(int z,int x,int y,Runnable done){int n=1<<z;if(y<0||y>=n)return null;x=(x%n+n)%n;String key=z+"-"+x+"-"+y;Bitmap b=memory.get(key);if(b!=null)return b;
  if(System.currentTimeMillis()<retry.getOrDefault(key,0L)||!pending.add(key))return null;final int xx=x;
  io.execute(()->{File f=new File(root,key+".png"),meta=new File(root,key+".meta");try{
   Properties props=new Properties();if(meta.isFile())try(InputStream in=new FileInputStream(meta)){props.load(in);}
   long now=System.currentTimeMillis(),expires=Long.parseLong(props.getProperty("expires","0"));
   if(f.isFile()){Bitmap disk=BitmapFactory.decodeFile(f.getPath());if(disk!=null){memory.put(key,disk);app.main.post(done);}}
   if(!f.isFile()||now>=expires){
    URL url=new URL("https://tile.openstreetmap.org/"+z+"/"+xx+"/"+y+".png");HttpURLConnection c=(HttpURLConnection)url.openConnection();c.setConnectTimeout(10000);c.setReadTimeout(10000);c.setRequestProperty("User-Agent","TravelRecorder/1.4.0 Android (+https://github.com/hanry123123/travel-recorder)");
    if(f.exists()&&props.getProperty("etag")!=null)c.setRequestProperty("If-None-Match",props.getProperty("etag"));if(f.exists()&&props.getProperty("modified")!=null)c.setRequestProperty("If-Modified-Since",props.getProperty("modified"));
    try{int status=c.getResponseCode();if(status==200){File temp=new File(root,key+".tmp");try(InputStream in=c.getInputStream();OutputStream out=new FileOutputStream(temp)){byte[] buf=new byte[8192];int count;int total=0;while((count=in.read(buf))!=-1){total+=count;if(total>1024*1024)throw new IOException("Tile too large");out.write(buf,0,count);}}Bitmap image=BitmapFactory.decodeFile(temp.getPath());if(image==null){temp.delete();throw new IOException("Invalid tile");}if(!temp.renameTo(f)){temp.delete();throw new IOException("Cache write failed");}memory.put(key,image);}else if(status!=304)throw new IOException("HTTP "+status);
     String control=c.getHeaderField("Cache-Control");long ttl=7L*86400000; // At least seven days when max-age is absent.
     if(control!=null){java.util.regex.Matcher matcher=java.util.regex.Pattern.compile("max-age=(\\d+)").matcher(control);if(matcher.find())ttl=Long.parseLong(matcher.group(1))*1000;}
     props.setProperty("expires",String.valueOf(now+ttl));if(c.getHeaderField("ETag")!=null)props.setProperty("etag",c.getHeaderField("ETag"));if(c.getHeaderField("Last-Modified")!=null)props.setProperty("modified",c.getHeaderField("Last-Modified"));try(OutputStream out=new FileOutputStream(meta)){props.store(out,"HTTP cache metadata");}unavailable=false;
    }finally{c.disconnect();}
   }
  }catch(Exception e){unavailable=true;retry.put(key,System.currentTimeMillis()+60000);}finally{pending.remove(key);app.main.post(done);}});return null;
 }
}
