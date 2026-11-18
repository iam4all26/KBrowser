// ==UserScript==
// @name         Test 5: Profile marker
// @version      1.0
// @description  Shows a green bar on every page. Switch it on in one profile only to check isolation.
// @match        *://*/*
// @run-at       document-end
// ==/UserScript==
var bar = document.createElement('div');
bar.textContent = 'Marker extension is ON in this profile (tap to hide)';
bar.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:2147483647;background:#30a46c;color:#fff;padding:6px;text-align:center;font:13px sans-serif;';
bar.onclick = function () { bar.remove(); };
document.documentElement.appendChild(bar);
