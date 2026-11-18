/// Injected into every page (all frames) of a profile that uses a proxy.
/// WebRTC can reveal the real IP address outside the proxy, so it is switched off.
const String webRtcBlockScript = r'''(function(){
try{
var names=['RTCPeerConnection','webkitRTCPeerConnection','mozRTCPeerConnection','RTCSessionDescription','RTCIceCandidate','RTCDataChannel'];
for(var i=0;i<names.length;i++){
  try{Object.defineProperty(window,names[i],{value:undefined,configurable:false,writable:false});}
  catch(e){try{window[names[i]]=undefined;}catch(x){}}
}
}catch(x){}
})();''';
