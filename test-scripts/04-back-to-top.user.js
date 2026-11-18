// ==UserScript==
// @name         Test 4: Back to top button
// @version      1.0
// @description  Adds a round button that scrolls to the top of the page.
// @match        *://*/*
// @run-at       document-idle
// ==/UserScript==
var b = document.createElement('div');
b.textContent = 'TOP';
b.style.cssText = 'position:fixed;bottom:16px;right:16px;z-index:2147483647;width:48px;height:48px;border-radius:24px;background:#f6c101;color:#17151f;font:bold 12px sans-serif;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,.4);';
b.onclick = function () { window.scrollTo({ top: 0, behavior: 'smooth' }); };
document.documentElement.appendChild(b);
