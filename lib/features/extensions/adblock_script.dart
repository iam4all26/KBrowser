/// Cosmetic part of the built-in ad blocker: hides common empty ad containers.
/// (The network part runs natively and blocks ad and tracker requests.)
const String adBlockCosmeticScript = r'''(function(){
try{
if(window.top!==window)return;
var css='ins.adsbygoogle,.adsbygoogle,[id^="google_ads_"],[id^="div-gpt-ad"],.ad-slot,.ad-banner,.adbanner,iframe[src*="doubleclick.net"],iframe[src*="googlesyndication.com"],iframe[src*="amazon-adsystem.com"]{display:none!important}';
function add(){try{if(document.getElementById('__kmx_adblock'))return;var s=document.createElement('style');s.id='__kmx_adblock';s.textContent=css;(document.head||document.documentElement).appendChild(s);}catch(x){}}
add();
document.addEventListener('DOMContentLoaded',add,{once:true});
}catch(x){}
})();''';
