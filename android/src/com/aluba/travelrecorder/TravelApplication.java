package com.aluba.travelrecorder;
import android.app.*;
import android.os.*;
import java.util.*;
import java.util.concurrent.*;

public final class TravelApplication extends Application {
 final ExecutorService worker=Executors.newSingleThreadExecutor();
 final Handler main=new Handler(Looper.getMainLooper());
 volatile Models.Snapshot state=Models.Snapshot.empty();volatile boolean ready;volatile String error;volatile String message="正在读取本机旅程…";
 TravelDb db;Photos photos;final List<Runnable> listeners=new ArrayList<>();
 interface Work{void run()throws Exception;}
 public void onCreate(){super.onCreate();photos=new Photos(this);work(()->{db=new TravelDb(this);for(Models.Trip t:db.trips())if(t.status==0){t.status=1;db.save(t);}publish();ready=true;message="点击开始记录新的旅程";});}
 void work(Work w){worker.execute(()->{try{w.run();}catch(Exception e){message="未完成："+(e.getMessage()==null?e.getClass().getSimpleName():e.getMessage());error=message;}main.post(this::notifyViews);});}
 void publish()throws Exception {state=db.snapshot();}
 void notifyViews(){for(Runnable r:new ArrayList<>(listeners))r.run();}
 void report(String s){message=s;main.post(this::notifyViews);}
 void saveTrip(String id,String title,String features,String reflection,String from,String to){work(()->{Models.Trip t=db.trip(id);if(t==null)return;t.title=title.trim().isEmpty()?t.title:title.trim();t.features=features;t.reflection=reflection;t.from=from;t.to=to;db.save(t);publish();});}
 void favorite(String id,String reason,boolean on){work(()->{Models.Trip t=db.trip(id);if(t==null)return;t.favorite=on?(t.favorite==0?System.currentTimeMillis():t.favorite):0;t.reason=on?reason:"";db.save(t);publish();});}
 void diary(Models.Diary d){work(()->{if(db.trip(d.trip)==null)throw new Exception("旅程已删除");db.save(d);publish();});}
 void deleteTrip(String id){work(()->{Models.Trip t=db.trip(id);if(t==null)return;if(t.status!=2)throw new Exception("请先结束旅程");List<Models.Photo> pictures=state.photos(id);db.deleteTrip(id);for(Models.Photo p:pictures){new java.io.File(getFilesDir(),p.file).delete();new java.io.File(getFilesDir(),p.thumb).delete();}publish();});}
 void deletePhoto(Models.Photo p){work(()->{db.deletePhoto(p);new java.io.File(getFilesDir(),p.file).delete();new java.io.File(getFilesDir(),p.thumb).delete();publish();});}
 void placePhoto(String id,String trip,double lat,double lon){work(()->{for(Models.Photo p:db.snapshot().photos(trip))if(p.id.equals(id)){p.lat=lat;p.lon=lon;p.manual=true;db.save(p);for(Models.Diary d:db.snapshot().diaries(trip))if(d.photo.equals(id)){d.lat=lat;d.lon=lon;db.save(d);}publish();break;}});}
}
