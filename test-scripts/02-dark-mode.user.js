// ==UserScript==
// @name         Test 2: Dark pages
// @version      1.0
// @description  Quick dark mode on every website (inverts colours, keeps pictures normal).
// @match        *://*/*
// @run-at       document-start
// ==/UserScript==
GM_addStyle('html { filter: invert(1) hue-rotate(180deg) !important; background: #fff; } img, video, picture, canvas, iframe { filter: invert(1) hue-rotate(180deg) !important; }');
