// Injected into the signed-in offscreen x.com web view. Exposes
// window.__pfbTransactionId(path, method), which calls the web client's own
// transaction-id generator; path is client-internal, e.g. /graphql/<queryId>/<Operation>.
(function(){
 if(window.__pfbTransactionId)return;

 // Webpack's require, through a pushed chunk entry: the chunk array is created if it
 // does not exist yet, and the runtime processes the entry, calling back with require,
 // once it installs.
 async function getWreq(){
  if(window.__pfbWreq)return window.__pfbWreq;
  var name="webpackChunk_twitter_responsive_web";
  window[name]=window[name]||[];
  var arr=window[name];
  var req=await new Promise(function(resolve,reject){
   var done=false;
   var finish=function(r){ if(!done){ done=true; resolve(r); } };
   try{ arr.push([["__pfb_"+Date.now()],{},finish]); }
   catch(e){ reject(e); return; }
   setTimeout(function(){ if(!done){ done=true; reject(new Error("webpack not ready (timeout)")); } },15000);
  });
  window.__pfbWreq=req;
  return req;
 }

 // The client's transaction-id generator: the module is found by two strings of its
 // source, then each function export is called with (host, path, method) until one
 // returns a valid token; that export is cached on window.__pfbGen.
 async function realGen(host,path,method){
  if(window.__pfbGen){ return await window.__pfbGen(host,path,method); }
  var req=await getWreq();
  if(!req||!req.m)throw new Error("no req.m");
  var keys=Object.keys(req.m);
  var cands=[];
  for(var i=0;i<keys.length;i++){
   var src;
   try{src=req.m[keys[i]].toString();}catch(e){continue;}
   if(src.indexOf("x-client-transaction-id")!==-1&&src.indexOf("rweb_client_transaction_id_enabled")!==-1){cands.push(keys[i]);}
  }
  if(cands.length===0)throw new Error("txn module not found ("+keys.length+" mods)");
  var lastErr=null;
  for(var c=0;c<cands.length;c++){
   var exp;
   try{exp=req(cands[c]);}catch(e){continue;}
   for(var k in exp){
    var f;
    try{f=exp[k];}catch(e){continue;}
    if(typeof f!=="function")continue;
    try{
     var out=await f(host,path,method);
     if(typeof out==="string"&&out.length>10){
      var dec="";try{dec=atob(out);}catch(e){}
      if(dec.slice(0,2)!=="e:"){ window.__pfbGen=f; return out; }
      lastErr="client:"+dec.slice(0,80);
     }
    }catch(e){}
   }
  }
  throw new Error(lastErr||("generator export not found (cands="+cands.length+")"));
 }

 window.__pfbTransactionId=async function(path,method){
  try{
   var t=await realGen("https://x.com",path,method);
   if(typeof t==="string"&&t.length>10){
    var dec="";try{dec=atob(t);}catch(e){}
    if(dec.slice(0,2)!=="e:")return t; // the client returns btoa("e:"+err) on failure
    return "ERR:client-returned-error";
   }
   return "ERR:gen-returned:"+String(t).slice(0,60);
  }catch(e){
   return "ERR:"+(((e&&e.message)?e.message:String(e))||"unknown").slice(0,120);
  }
 };
})();
