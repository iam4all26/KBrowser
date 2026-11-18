// ==UserScript==
// @name         Test 3: Visit counter
// @version      1.0
// @description  Shows how many times you opened each site in this profile. Tests GM_getValue and GM_setValue.
// @match        *://*/*
// @run-at       document-idle
// ==/UserScript==
var visits = GM_getValue('visits', 0) + 1;
GM_setValue('visits', visits);
var badge = document.createElement('div');
badge.textContent = 'Visits to this site: ' + visits;
badge.style.cssText = 'position:fixed;bottom:12px;left:12px;z-index:2147483647;background:#7351ff;color:#fff;padding:6px 10px;border-radius:12px;font:13px sans-serif;';
badge.onclick = function () { badge.remove(); };
document.documentElement.appendChild(badge);
