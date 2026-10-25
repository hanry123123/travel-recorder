package com.aluba.travelrecorder;
import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.*;
import android.provider.OpenableColumns;
import java.io.*;

/** Read-only grants for generated files, never for the database or original photos. */
public final class ShareProvider extends ContentProvider {
 public boolean onCreate(){return true;}
 static Uri uri(File file){return new Uri.Builder().scheme("content").authority("com.aluba.travelrecorder.share").appendPath(file.getName()).build();}
 File resolve(Uri uri)throws FileNotFoundException{try{File root=new File(getContext().getCacheDir(),"shares").getCanonicalFile();String name=uri.getLastPathSegment();if(name==null||uri.getPathSegments().size()!=1||!name.matches("TravelRecorder-[a-f0-9-]+\\.(jpg|mp4)"))throw new IOException();File f=new File(root,name).getCanonicalFile();if(!f.getParentFile().equals(root)||!f.isFile())throw new IOException();return f;}catch(IOException e){throw new FileNotFoundException("Unknown share file");}}
 public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException {if(!"r".equals(mode))throw new FileNotFoundException("Read only");return ParcelFileDescriptor.open(resolve(uri),ParcelFileDescriptor.MODE_READ_ONLY);}
 public String getType(Uri uri){return uri.toString().endsWith(".mp4")?"video/mp4":"image/jpeg";}
 public Cursor query(Uri uri,String[] projection,String selection,String[] args,String order){try{File f=resolve(uri);String[] cols=projection==null?new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE}:projection;MatrixCursor c=new MatrixCursor(cols);Object[] row=new Object[cols.length];for(int i=0;i<cols.length;i++)row[i]=cols[i].equals(OpenableColumns.DISPLAY_NAME)?f.getName():cols[i].equals(OpenableColumns.SIZE)?f.length():null;c.addRow(row);return c;}catch(FileNotFoundException e){return null;}}
 public Uri insert(Uri u,ContentValues v){throw new UnsupportedOperationException();}public int update(Uri u,ContentValues v,String s,String[] a){throw new UnsupportedOperationException();}public int delete(Uri u,String s,String[] a){throw new UnsupportedOperationException();}
}
