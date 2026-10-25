package com.aluba.travelrecorder;
import java.util.*;
public final class RouteMathTest {
 static int n;static void check(boolean b,String s){n++;if(!b)throw new AssertionError(s);System.out.println("PASS "+s);}
 public static void main(String[] args){long t=1800000000000L;RouteMath.Point a=new RouteMath.Point(30,120,t,5,0),b=new RouteMath.Point(30.001,120,t+10000,5,0),c=new RouteMath.Point(30.002,120,t+20000,5,1);
  check(RouteMath.accept(a,null,t,t),"first accurate point");check(!RouteMath.accept(a,null,t+40000,t),"reject stale point");check(!RouteMath.accept(new RouteMath.Point(30,120,t,101,0),null,t,t),"reject inaccurate");check(!RouteMath.accept(new RouteMath.Point(Double.NaN,120,t,5,0),null,t,t),"reject NaN");check(!RouteMath.accept(a,a,t,t),"reject duplicate timestamp");check(!RouteMath.accept(new RouteMath.Point(31,120,t+1000,5,0),a,t+1000,t),"reject teleport");check(RouteMath.accept(b,a,t+10000,t),"walking accepted");check(!RouteMath.accept(a,null,t,t+1),"pre-resume location rejected");check(RouteMath.distance(a,b)>110&&RouteMath.distance(a,b)<112,"distance in metres");
  List<RouteMath.Point> list=Arrays.asList(a,b,c);check(RouteMath.at(list,t+5000)!=null,"continuous segment interpolates");check(Math.abs(RouteMath.at(list,t+5000).lat-30.0005)<0.000001,"interpolation location");check(RouteMath.at(list,t+15000)==null,"pause gap never draws line");check(RouteMath.at(list,t+20000)==c,"resume endpoint visible");check(RouteMath.at(Collections.emptyList(),t)==null,"empty route");check(RouteMath.at(Collections.singletonList(a),t+999)==a,"single point");check(RouteMath.timeAtFraction(list,.5)==t+10000,"slider time range");check(RouteMath.timeAtFraction(list,2)==t+20000,"slider clamps");check(RouteMath.durationMillis(list)==20000,"moderate minimum duration");check(RouteMath.durationMillis(Collections.nCopies(500,a))==60000,"bounded duration");check(RouteMath.belongs(t,t,t),"photo endpoints inclusive");check(!RouteMath.belongs(t-1,t,t+1),"old photo not automatic");
  RouteMath.Point d=new RouteMath.Point(0,179,t,5,0),e=new RouteMath.Point(0,-179,t+10000,5,0);RouteMath.Point mid=RouteMath.at(Arrays.asList(d,e),t+5000);check(Math.abs(mid.lon)>179.9,"date line shortest route");
  for(double lat:new double[]{-85,-45,0,30,85})check(Math.abs(RouteMath.lat(RouteMath.y(lat))-lat)<1e-8,"projection roundtrip "+lat);
  check(RouteMath.at(Arrays.asList(a,b,c,new RouteMath.Point(30.003,120,t+30000,5,1)),t+30000).lat==30.003,"appended current point reachable");
  System.out.println("CHECKS="+n);
 }
}
