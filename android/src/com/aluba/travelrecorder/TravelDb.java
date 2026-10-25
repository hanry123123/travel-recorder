package com.aluba.travelrecorder;
import android.content.*;
import android.database.*;
import android.database.sqlite.*;
import java.util.*;
import org.json.*;

/** All access belongs to TravelApplication.worker. Each UI snapshot is detached. */
final class TravelDb extends SQLiteOpenHelper {
 TravelDb(Context c){super(c,"travel.sqlite",null,1);setWriteAheadLoggingEnabled(true);}
 public void onCreate(SQLiteDatabase d){d.execSQL("CREATE TABLE records(kind TEXT NOT NULL,id TEXT PRIMARY KEY,trip TEXT NOT NULL,time INTEGER NOT NULL,data TEXT NOT NULL)");d.execSQL("CREATE INDEX by_trip ON records(trip,kind,time)");d.execSQL("CREATE TABLE points(id INTEGER PRIMARY KEY,trip TEXT NOT NULL,lat REAL,lon REAL,time INTEGER,accuracy REAL,segment INTEGER)");d.execSQL("CREATE INDEX route ON points(trip,time,id)");d.execSQL("CREATE TABLE exclusions(trip TEXT,uri TEXT,PRIMARY KEY(trip,uri))");}
 public void onUpgrade(SQLiteDatabase d,int old,int next){throw new IllegalStateException("未知数据库版本，保留原始数据");}
 void put(String kind,String id,String trip,long time,JSONObject o){ContentValues v=new ContentValues();v.put("kind",kind);v.put("id",id);v.put("trip",trip);v.put("time",time);v.put("data",o.toString());if(getWritableDatabase().insertWithOnConflict("records",null,v,SQLiteDatabase.CONFLICT_REPLACE)<0)throw new SQLiteException("保存失败");}
 void save(Models.Trip t)throws Exception{put("trip",t.id,t.id,t.start,t.json());}
 void save(Models.Photo p)throws Exception{put("photo",p.id,p.trip,p.time,p.json());}
 void save(Models.Diary d)throws Exception{put("diary",d.id,d.trip,d.time,d.json());}
 Models.Trip active()throws Exception{for(Models.Trip t:trips())if(t.status!=2)return t;return null;}
 List<Models.Trip> trips()throws Exception{List<Models.Trip> a=new ArrayList<>();try(Cursor c=getReadableDatabase().rawQuery("SELECT data FROM records WHERE kind='trip' ORDER BY time DESC",null)){while(c.moveToNext())a.add(new Models.Trip(new JSONObject(c.getString(0))));}return a;}
 Models.Trip trip(String id)throws Exception{try(Cursor c=getReadableDatabase().rawQuery("SELECT data FROM records WHERE kind='trip' AND id=?",new String[]{id})){return c.moveToFirst()?new Models.Trip(new JSONObject(c.getString(0))):null;}}
 RouteMath.Point last(String id){try(Cursor c=getReadableDatabase().rawQuery("SELECT lat,lon,time,accuracy,segment FROM points WHERE trip=? ORDER BY time DESC,id DESC LIMIT 1",new String[]{id})){return c.moveToFirst()?new RouteMath.Point(c.getDouble(0),c.getDouble(1),c.getLong(2),c.getDouble(3),c.getInt(4)):null;}}
 void addPoint(Models.Trip t,RouteMath.Point p)throws Exception{
  SQLiteDatabase d=getWritableDatabase();d.beginTransaction();try{ContentValues v=new ContentValues();v.put("trip",t.id);v.put("lat",p.lat);v.put("lon",p.lon);v.put("time",p.time);v.put("accuracy",p.accuracy);v.put("segment",p.segment);d.insertOrThrow("points",null,v);save(t);d.setTransactionSuccessful();}finally{d.endTransaction();}
 }
 boolean hasPhoto(String trip,String uri){try(Cursor c=getReadableDatabase().rawQuery("SELECT data FROM records WHERE kind='photo' AND trip=?",new String[]{trip})){while(c.moveToNext()){try{if(uri.equals(new JSONObject(c.getString(0)).optString("uri")))return true;}catch(JSONException e){throw new IllegalStateException(e);}}}return false;}
 boolean excluded(String trip,String uri){try(Cursor c=getReadableDatabase().rawQuery("SELECT 1 FROM exclusions WHERE trip=? AND uri=?",new String[]{trip,uri})){return c.moveToFirst();}}
 void exclude(String trip,String uri){ContentValues v=new ContentValues();v.put("trip",trip);v.put("uri",uri);getWritableDatabase().insertWithOnConflict("exclusions",null,v,SQLiteDatabase.CONFLICT_IGNORE);}
 void allow(String trip,String uri){getWritableDatabase().delete("exclusions","trip=? AND uri=?",new String[]{trip,uri});}
 void deletePhoto(Models.Photo p)throws Exception{SQLiteDatabase d=getWritableDatabase();d.beginTransaction();try{exclude(p.trip,p.uri);d.delete("records","kind='photo' AND id=?",new String[]{p.id});for(Models.Diary note:snapshot().diaries(p.trip))if(note.photo.equals(p.id)){note.photo="";save(note);}d.setTransactionSuccessful();}finally{d.endTransaction();}}
 void deleteDiary(String id){getWritableDatabase().delete("records","kind='diary' AND id=?",new String[]{id});}
 void deleteTrip(String id){SQLiteDatabase d=getWritableDatabase();d.beginTransaction();try{d.delete("records","trip=?",new String[]{id});d.delete("points","trip=?",new String[]{id});d.delete("exclusions","trip=?",new String[]{id});d.setTransactionSuccessful();}finally{d.endTransaction();}}
 Models.Snapshot snapshot()throws Exception{
  Map<String,List<RouteMath.Point>> r=new HashMap<>();Map<String,List<Models.Photo>> p=new HashMap<>();Map<String,List<Models.Diary>> n=new HashMap<>();
  try(Cursor c=getReadableDatabase().rawQuery("SELECT trip,lat,lon,time,accuracy,segment FROM points ORDER BY time,id",null)){while(c.moveToNext())r.computeIfAbsent(c.getString(0),k->new ArrayList<>()).add(new RouteMath.Point(c.getDouble(1),c.getDouble(2),c.getLong(3),c.getDouble(4),c.getInt(5)));}
  try(Cursor c=getReadableDatabase().rawQuery("SELECT kind,trip,data FROM records WHERE kind!='trip' ORDER BY time,id",null)){while(c.moveToNext()){JSONObject o=new JSONObject(c.getString(2));if(c.getString(0).equals("photo"))p.computeIfAbsent(c.getString(1),k->new ArrayList<>()).add(new Models.Photo(o));else n.computeIfAbsent(c.getString(1),k->new ArrayList<>()).add(new Models.Diary(o));}}
  return new Models.Snapshot(trips(),r,p,n);
 }
}
