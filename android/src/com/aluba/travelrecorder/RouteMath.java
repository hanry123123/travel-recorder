package com.aluba.travelrecorder;
import java.util.*;

/** Pure coordinate/record/replay rules, also exercised by JVM fixtures. GPS stays WGS84. */
public final class RouteMath {
    public static final class Point {
        public final double lat, lon, accuracy; public final long time; public final int segment;
        public Point(double a,double o,long t,double e,int s){lat=a;lon=o;time=t;accuracy=e;segment=s;}
    }
    public static boolean valid(double lat,double lon){return Double.isFinite(lat)&&Double.isFinite(lon)&&Math.abs(lat)<=90&&Math.abs(lon)<=180;}
    public static double delta(double x){return x-Math.floor(x+0.5);}
    public static double x(double lon){return (lon+180)/360;}
    public static double y(double lat){double r=Math.toRadians(Math.max(-85.05112878,Math.min(85.05112878,lat)));return (1-Math.log(Math.tan(r)+1/Math.cos(r))/Math.PI)/2;}
    public static double lat(double y){return Math.toDegrees(Math.atan(Math.sinh(Math.PI*(1-2*y))));}
    public static double lon(double x){return (x-Math.floor(x))*360-180;}
    public static double distance(Point a,Point b){double la=Math.toRadians(b.lat-a.lat),lo=Math.toRadians(b.lon-a.lon);double h=Math.sin(la/2)*Math.sin(la/2)+Math.cos(Math.toRadians(a.lat))*Math.cos(Math.toRadians(b.lat))*Math.sin(lo/2)*Math.sin(lo/2);return 6371000*2*Math.asin(Math.sqrt(Math.min(1,h)));}
    public static boolean accept(Point p,Point previous,long now,long segmentStart){
        if(!valid(p.lat,p.lon)||!Double.isFinite(p.accuracy)||p.accuracy<0||p.accuracy>100||p.time<segmentStart||now-p.time>30000||p.time>now+5000)return false;
        if(previous!=null && p.segment==previous.segment){long dt=p.time-previous.time;if(dt<=0)return false;double d=distance(previous,p);if(d>Math.max(200,dt/1000.0*100)||d<Math.max(3,Math.min(10,p.accuracy/2))&&dt<15000)return false;}
        return true;
    }
    public static Point at(List<Point> points,long time){
        if(points.isEmpty())return null;
        if(time<=points.get(0).time)return points.get(0);
        int lo=0,hi=points.size()-1;
        while(lo<hi){int m=(lo+hi+1)/2;if(points.get(m).time<=time)lo=m;else hi=m-1;}
        Point a=points.get(lo);if(lo==points.size()-1||a.time==time)return a;Point b=points.get(lo+1);
        if(a.segment!=b.segment)return null;
        double f=(time-a.time)/(double)Math.max(1,b.time-a.time);double xx=x(a.lon)+delta(x(b.lon)-x(a.lon))*f;
        return new Point(lat(y(a.lat)+(y(b.lat)-y(a.lat))*f),lon(xx),time,a.accuracy,a.segment);
    }
    public static long durationMillis(List<Point> p){if(p.size()<2)return 2000;return Math.min(60000,Math.max(20000,p.size()*180L));}
    public static long timeAtFraction(List<Point> p,double f){if(p.isEmpty())return 0;return p.get(0).time+(long)((p.get(p.size()-1).time-p.get(0).time)*Math.max(0,Math.min(1,f)));}
    public static boolean belongs(long time,long start,long end){return time>=start&&time<=end;}
    private RouteMath(){}
}
