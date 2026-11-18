import 'dart:convert';

import '../../models/user_extension.dart';

class ExtensionError implements Exception {
  const ExtensionError(this.message);
  final String message;
  @override
  String toString() => message;
}

class ParsedUserscript {
  const ParsedUserscript({
    required this.name,
    required this.version,
    required this.description,
    required this.matches,
    required this.excludes,
    required this.runAt,
    required this.code,
  });
  final String name;
  final String version;
  final String description;
  final List<String> matches;
  final List<String> excludes;
  final String runAt;
  final String code;

  bool get runsEverywhere => matches.isEmpty;
}

const int maxScriptBytes = 300000;

/// Reads the standard userscript header block (// ==UserScript== ... // ==/UserScript==).
ParsedUserscript parseUserscript(String source, {String? fallbackName}) {
  final code = source.replaceAll('\r\n', '\n').trim();
  if (code.isEmpty) throw const ExtensionError('The script is empty.');
  if (utf8.encode(code).length > maxScriptBytes) {
    throw const ExtensionError('The script is too large (limit 300 KB).');
  }
  var name = '';
  var version = '';
  var description = '';
  var runAt = 'document-idle';
  final matches = <String>[];
  final excludes = <String>[];
  final header = RegExp(r'//\s*==UserScript==([\s\S]*?)//\s*==/UserScript==').firstMatch(code);
  if (header != null) {
    final line = RegExp(r'^\s*//\s*@([\w\-]+)[ \t]*(.*)$');
    for (final raw in header.group(1)!.split('\n')) {
      final m = line.firstMatch(raw);
      if (m == null) continue;
      final key = m.group(1)!.toLowerCase();
      final value = (m.group(2) ?? '').trim();
      switch (key) {
        case 'name':
          if (name.isEmpty) name = value;
        case 'version':
          version = value;
        case 'description':
          if (description.isEmpty) description = value;
        case 'match':
        case 'include':
          if (value.isNotEmpty) matches.add(value);
        case 'exclude':
        case 'exclude-match':
          if (value.isNotEmpty) excludes.add(value);
        case 'run-at':
          if (value == 'document-start') {
            runAt = 'document-start';
          } else if (value == 'document-end' || value == 'document-body') {
            runAt = 'document-end';
          } else {
            runAt = 'document-idle';
          }
      }
    }
  }
  if (name.isEmpty) name = (fallbackName == null || fallbackName.isEmpty) ? 'Untitled extension' : fallbackName;
  return ParsedUserscript(
    name: name,
    version: version,
    description: description,
    matches: matches,
    excludes: excludes,
    runAt: runAt,
    code: code,
  );
}

String _glob(String text) => text.split('*').map(RegExp.escape).join('.*');

/// Converts an @match / @include / @exclude pattern to a JavaScript regex source.
String? patternToRegex(String raw) {
  final p = raw.trim();
  if (p.isEmpty) return null;
  if (p == '<all_urls>' || p == '*') return r'^https?://.*$';
  if (p.length > 2 && p.startsWith('/') && p.endsWith('/')) return p.substring(1, p.length - 1);
  final m = RegExp(r'^(\*|https?)://([^/]*)(/.*)?$').firstMatch(p);
  if (m == null) return '^${_glob(p)}\$';
  final scheme = m.group(1) == '*' ? 'https?' : m.group(1)!;
  final host = m.group(2)!;
  final path = m.group(3) ?? '/*';
  String hostRe;
  if (host == '*') {
    hostRe = '[^/]+';
  } else if (host.startsWith('*.')) {
    hostRe = '(?:[^/]+\\.)?${RegExp.escape(host.substring(2))}';
  } else {
    hostRe = _glob(host);
  }
  return '^$scheme://$hostRe${_glob(path)}\$';
}

/// Builds the script given to the WebView. It runs in the top page only,
/// checks the address itself, and offers a small GM_* helper set.
String buildInjectedScript(UserExtension e) {
  var inc = e.matches.map(patternToRegex).whereType<String>().toList();
  if (inc.isEmpty) inc = [r'^https?://.*$'];
  final exc = e.excludes.map(patternToRegex).whereType<String>().toList();
  final meta = {'name': e.name, 'version': e.version, 'description': e.description};
  return '''(function(){
try{
if(window.top!==window)return;
var inc=${jsonEncode(inc)},exc=${jsonEncode(exc)},href=location.href;
function t(l){for(var i=0;i<l.length;i++){try{if(new RegExp(l[i]).test(href))return true;}catch(x){}}return false;}
if(!t(inc)||t(exc))return;
var NAME=${jsonEncode(e.name)},KEY='__kmx_${e.id}_',GM_info={script:${jsonEncode(meta)}};
function GM_log(){try{console.log.apply(console,arguments);}catch(x){}}
function GM_addStyle(css){var s=document.createElement('style');s.textContent=css;(document.head||document.documentElement).appendChild(s);return s;}
function GM_getValue(k,d){try{var v=localStorage.getItem(KEY+k);return v===null?d:JSON.parse(v);}catch(x){return d;}}
function GM_setValue(k,v){try{localStorage.setItem(KEY+k,JSON.stringify(v));}catch(x){}}
function GM_deleteValue(k){try{localStorage.removeItem(KEY+k);}catch(x){}}
var unsafeWindow=window;
function main(){try{
${e.code}
}catch(err){try{console.error('[K-Multi extension] '+NAME,err);}catch(x){}}}
var when=${jsonEncode(e.runAt)};
if(when==='document-start'){main();}
else if(when==='document-end'){if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',main,{once:true});}else{main();}}
else{if(document.readyState==='complete'){setTimeout(main,0);}else{window.addEventListener('load',function(){setTimeout(main,0);},{once:true});}}
}catch(x){}
})();''';
}
