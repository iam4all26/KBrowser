/// Injected into the top frame of every page of a profile that has
/// "Save and fill passwords" on. It never sends anything on its own: it only tells
/// the app (through the KMultiPw bridge) that a login form was submitted or seen.
/// Saved passwords are put into the page only after the user taps Fill.
const String passwordCaptureScript = r'''(function(){
try{
if(window.top!==window)return;
function B(){return window.KMultiPw;}
function vis(e){try{var r=e.getBoundingClientRect();var s=getComputedStyle(e);return r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none';}catch(x){return false;}}
function pair(root){
  var scope=root||document;
  var pws=[].slice.call(scope.querySelectorAll('input[type=password]')).filter(function(e){return e.value;});
  if(!pws.length)return null;
  var pw=pws[0];var form=pw.form||document;
  var user=null;
  [].slice.call(form.querySelectorAll('input')).forEach(function(e){
    var t=(e.type||'text').toLowerCase();
    if(e!==pw&&(t==='text'||t==='email'||t==='tel')&&e.value&&(e.compareDocumentPosition(pw)&Node.DOCUMENT_POSITION_FOLLOWING))user=e;
  });
  return {u:user?user.value:'',p:pw.value};
}
var last='';
function send(root){
  try{
    var x=pair(root);if(!x||!B())return;
    var k=x.u+'\n'+x.p;if(k===last)return;last=k;
    B().save(x.u,x.p);
  }catch(e){}
}
document.addEventListener('submit',function(e){send(e.target&&e.target.querySelectorAll?e.target:document);},true);
document.addEventListener('click',function(e){
  try{
    var t=e.target&&e.target.closest?e.target.closest('button,input[type=submit],input[type=button],[role=button],a'):null;
    if(!t)return;
    var txt=((t.innerText||'')+' '+(t.value||'')+' '+(t.getAttribute('aria-label')||'')+' '+(t.type||'')).toLowerCase();
    if(/log.?in|sign.?in|submit|continue|next|enter|verify|register|sign.?up|create/.test(txt))send(t.form||document);
  }catch(x){}
},true);
document.addEventListener('keydown',function(e){
  try{if(e.key==='Enter'&&e.target&&e.target.tagName==='INPUT')send(e.target.form||document);}catch(x){}
},true);
var seen=false,mo=null;
function scan(){
  if(seen)return;
  var p=document.querySelector('input[type=password]');
  if(p&&vis(p)&&B()){seen=true;try{if(mo)mo.disconnect();}catch(x){}B().formSeen();}
}
scan();
document.addEventListener('DOMContentLoaded',scan,{once:true});
if(document.documentElement){
  mo=new MutationObserver(function(){scan();});
  mo.observe(document.documentElement,{childList:true,subtree:true});
}
}catch(x){}
})();''';
