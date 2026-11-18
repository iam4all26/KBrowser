# Extension test scripts

How to test: open the main Home > Extensions tab > Add extension > Paste code. Paste one script below, tap Next, check the details, tap Add. Then open a profile, Menu > Extensions, switch it on, and visit the sites named. Each script is also saved as a .user.js file in this folder.

Isolation test: switch a script on in Profile 1 only. Profile 2 must show no change.

Optional link test: if your repository is public, the files can be added with Add extension > From a link, using the raw GitHub address, for example https://raw.githubusercontent.com/iam4all26/KBrowser/main/test-scripts/01-wikipedia-pink.user.js

## 0*.user.js

```
```

## Ad blocker test

The ad blocker is built in. On the main Home, Extensions tab, it is the first card (Available to profiles). In a profile, Menu > Extensions, switch on Ad and tracker blocker. Open a news or sports site with many ads, then open the menu: the Extensions line shows how many requests were blocked on that page. Compare the same site in another profile where it is off.
