package com.aluba.travelrecorder;
import java.util.*;
import org.json.*;

final class Models {
 static String id(){return UUID.randomUUID().toString();}
 static final class Trip {
  String id=id(),title="",features="",reflection="",reason="",from="",to="";long start,end,segmentStart,favorite;int status=0,segment=0;double distance;
  // 0 recording, 1 paused/recovered, 2 ended. Mutable only on the store worker.
  Trip(long now){start=now;segmentStart=now;title=new java.text.SimpleDateFormat("M月d日的旅程",Locale.CHINA).format(new Date(now));}
  Trip(JSONObject o){id=o.optString("id");title=o.optString("title");features=o.optString("features");reflection=o.optString("reflection");reason=o.optString("reason");from=o.optString("from");to=o.optString("to");start=o.optLong("start");end=o.optLong("end");segmentStart=o.optLong("segmentStart");favorite=o.optLong("favorite");status=o.optInt("status");segment=o.optInt("segment");distance=o.optDouble("distance",0);}
  JSONObject json() throws JSONException {return new JSONObject().put("id",id).put("title",title).put("features",features).put("reflection",reflection).put("reason",reason).put("from",from).put("to",to).put("start",start).put("end",end).put("segmentStart",segmentStart).put("favorite",favorite).put("status",status).put("segment",segment).put("distance",distance);}
 }
 static final class Photo {
  String id=id(),trip,uri,file,thumb;long time;Double lat,lon;boolean manual;
  Photo(){}
  Photo(JSONObject o){id=o.optString("id");trip=o.optString("trip");uri=o.optString("uri");file=o.optString("file");thumb=o.optString("thumb");time=o.optLong("time");manual=o.optBoolean("manual");if(!o.isNull("lat")){lat=o.optDouble("lat");lon=o.optDouble("lon");}}
  JSONObject json() throws JSONException{return new JSONObject().put("id",id).put("trip",trip).put("uri",uri).put("file",file).put("thumb",thumb).put("time",time).put("lat",lat).put("lon",lon).put("manual",manual);}
 }
 static final class Diary {
  String id=id(),trip,photo="",title="",text="";double lat,lon;long time;
  Diary(){}
  Diary(JSONObject o){id=o.optString("id");trip=o.optString("trip");photo=o.optString("photo");title=o.optString("title");text=o.optString("text");lat=o.optDouble("lat");lon=o.optDouble("lon");time=o.optLong("time");}
  JSONObject json() throws JSONException{return new JSONObject().put("id",id).put("trip",trip).put("photo",photo).put("title",title).put("text",text).put("lat",lat).put("lon",lon).put("time",time);}
 }
 static final class Snapshot {
  final List<Trip> trips;final Map<String,List<RouteMath.Point>> routes;final Map<String,List<Photo>> photos;final Map<String,List<Diary>> diaries;
  Snapshot(List<Trip> t,Map<String,List<RouteMath.Point>> r,Map<String,List<Photo>> p,Map<String,List<Diary>> d){trips=t;routes=r;photos=p;diaries=d;}
  static Snapshot empty(){return new Snapshot(Collections.emptyList(),new HashMap<>(),new HashMap<>(),new HashMap<>());}
  Trip trip(String id){for(Trip t:trips)if(t.id.equals(id))return t;return null;}
  Trip active(){for(Trip t:trips)if(t.status!=2)return t;return null;}
  List<RouteMath.Point> points(String id){return routes.getOrDefault(id,Collections.emptyList());}
  List<Photo> photos(String id){return photos.getOrDefault(id,Collections.emptyList());}
  List<Diary> diaries(String id){return diaries.getOrDefault(id,Collections.emptyList());}
 }
}
