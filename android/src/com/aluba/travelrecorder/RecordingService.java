package com.aluba.travelrecorder;
import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.location.*;
import android.os.*;

public final class RecordingService extends Service implements LocationListener {
 static final String START="start",PAUSE="pause",FINISH="finish";static volatile boolean alive;
 TravelApplication app;LocationManager manager;boolean stopping=false;long epoch=0;
 public void onCreate(){super.onCreate();alive=true;app=(TravelApplication)getApplication();manager=(LocationManager)getSystemService(LOCATION_SERVICE);NotificationManager n=getSystemService(NotificationManager.class);n.createNotificationChannel(new NotificationChannel("record","旅程记录",NotificationManager.IMPORTANCE_LOW));}
 public int onStartCommand(Intent intent,int flags,int startId){
  String command=intent==null?PAUSE:intent.getAction();
  if(START.equals(command)){
   if(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED){app.report("请允许精确定位后再开始记录");stopSelf();return START_NOT_STICKY;}
   try{startForeground(14,notification());}catch(RuntimeException e){app.report("无法启动后台记录："+e.getMessage());stopSelf();return START_NOT_STICKY;}
   final long request=++epoch;stopping=false;
   app.work(()->{Models.Trip t=app.db.active();if(t==null)t=new Models.Trip(System.currentTimeMillis());else if(t.status!=0){t.segment++;t.segmentStart=System.currentTimeMillis();t.status=0;}app.db.save(t);app.publish();app.main.post(()->{if(stopping||epoch!=request)return;try{manager.requestLocationUpdates(LocationManager.GPS_PROVIDER,2000,3,this,Looper.getMainLooper());if(manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER))manager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER,5000,5,this,Looper.getMainLooper());app.report("正在记录 · 锁屏后继续");}catch(RuntimeException e){stopRecording(false,"定位无法启动："+e.getMessage());}});});
  }else stopRecording(FINISH.equals(command),FINISH.equals(command)?"旅程已保存在回忆中":"已暂停，继续后记录新的一段");
  return START_NOT_STICKY;
 }
 void stopRecording(boolean finish,String message){stopping=true;epoch++;manager.removeUpdates(this);app.work(()->{Models.Trip t=app.db.active();if(t!=null){t.status=finish?2:1;if(finish)t.end=System.currentTimeMillis();app.db.save(t);}app.publish();app.message=message;app.main.post(()->{stopForeground(true);stopSelf();app.photos.scan();});});}
 Notification notification(){Intent open=new Intent(this,MainActivity.class);PendingIntent pi=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);PendingIntent pause=PendingIntent.getService(this,1,new Intent(this,RecordingService.class).setAction(PAUSE),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);return new Notification.Builder(this,"record").setSmallIcon(android.R.drawable.ic_menu_mylocation).setContentTitle("旅迹 · 正在记录").setContentText("锁屏后继续记录，点击返回旅程").setContentIntent(pi).setOngoing(true).addAction(new Notification.Action.Builder(null,"暂停",pause).build()).build();}
 public void onLocationChanged(Location l){final long arrived=System.currentTimeMillis();app.work(()->{Models.Trip t=app.db.active();if(t==null||t.status!=0)return;RouteMath.Point previous=app.db.last(t.id);RouteMath.Point p=new RouteMath.Point(l.getLatitude(),l.getLongitude(),l.getTime(),l.hasAccuracy()?l.getAccuracy():1000,t.segment);if(!RouteMath.accept(p,previous,arrived,t.segmentStart))return;
   // A long outage starts a new segment instead of inventing the missing path.
   if(previous!=null&&previous.segment==p.segment&&p.time-previous.time>120000){t.segment++;p=new RouteMath.Point(p.lat,p.lon,p.time,p.accuracy,t.segment);}
   if(previous!=null&&previous.segment==p.segment)t.distance+=RouteMath.distance(previous,p);app.db.addPoint(t,p);app.message="正在记录 · 精度约 "+Math.round(p.accuracy)+" 米";app.publish();});}
 public void onProviderDisabled(String provider){app.report("定位服务已关闭，恢复后继续记录");}
 public void onProviderEnabled(String provider){}
 public void onStatusChanged(String p,int s,Bundle extras){}
 public IBinder onBind(Intent i){return null;}
 public void onDestroy(){alive=false;manager.removeUpdates(this);if(!stopping)app.work(()->{Models.Trip t=app.db.active();if(t!=null&&t.status==0){t.status=1;app.db.save(t);app.publish();}});super.onDestroy();}
}
