// ==UserScript==
// @name         Test 1: Wikipedia pink
// @version      1.0
// @description  Turns Wikipedia pages pink. Proves a script runs only on the sites it names.
// @match        https://*.wikipedia.org/*
// @run-at       document-start
// ==/UserScript==
GM_addStyle('html, body { background: #ffd6e7 !important; }');
