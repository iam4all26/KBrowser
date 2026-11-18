package com.kainuwa.kmultibrowser.profiles

/**
 * Starter list of advertising and tracking domains. A request is blocked when its host
 * is one of these domains or a sub-domain of one. Only sub-resources are blocked,
 * never the page you open yourself. First-party ads (for example YouTube video ads)
 * cannot be blocked this way.
 */
object AdBlockList {
    private val domains: Set<String> = hashSetOf(
        // Google advertising and measurement
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "adservice.google.com", "pagead2.googlesyndication.com", "2mdn.net", "admob.com", "adsense.com",
        "googletagservices.com", "analytics.google.com",
        // Large ad exchanges and networks
        "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "rubiconproject.com", "pubmatic.com",
        "openx.net", "openx.com", "casalemedia.com", "advertising.com", "yieldmo.com", "smartadserver.com",
        "adform.net", "bidswitch.net", "sharethrough.com", "teads.tv", "triplelift.com", "indexww.com",
        "contextweb.com", "lijit.com", "sovrn.com", "33across.com", "gumgum.com", "adcolony.com",
        "applovin.com", "unityads.unity3d.com", "vungle.com", "chartboost.com", "inmobi.com",
        "mopub.com", "adition.com", "serving-sys.com", "flashtalking.com", "mathtag.com", "turn.com",
        "demdex.net", "everesttech.net", "krxd.net", "bluekai.com", "exelator.com", "agkn.com",
        "rlcdn.com", "tapad.com", "crwdcntrl.net", "adsymptotic.com", "ml314.com", "bkrtx.com",
        // Native ads and content recommendation
        "taboola.com", "outbrain.com", "revcontent.com", "mgid.com", "zemanta.com", "content.ad",
        "criteo.com", "criteo.net", "media.net", "zedo.com", "adblade.com", "plista.com",
        // Pop-up and push ad networks
        "popads.net", "propellerads.com", "popcash.net", "exoclick.com", "juicyads.com", "adsterra.com",
        "clickadu.com", "trafficjunky.com", "trafficfactory.biz", "hilltopads.net", "richpush.co",
        // Social and marketing trackers
        "ads.linkedin.com", "px.ads.linkedin.com", "snap.licdn.com", "ads-twitter.com", "analytics.twitter.com",
        "ads.twitter.com", "analytics.tiktok.com", "ads.tiktok.com", "business-api.tiktok.com",
        "ads.pinterest.com", "ct.pinterest.com", "bat.bing.com", "clarity.ms", "an.facebook.com",
        "pixel.facebook.com", "ads.yahoo.com", "analytics.yahoo.com", "ads.reddit.com", "events.reddit.com",
        // Analytics and behaviour tracking
        "scorecardresearch.com", "quantserve.com", "quantcount.com", "moatads.com", "hotjar.com", "hotjar.io",
        "mixpanel.com", "segment.io", "segment.com", "fullstory.com", "crazyegg.com", "mouseflow.com",
        "chartbeat.com", "chartbeat.net", "nr-data.net", "optimizely.com", "adjust.com", "appsflyer.com",
        "kochava.com", "singular.net", "amplitude.com", "heap.io", "heapanalytics.com", "luckyorange.com",
        "inspectlet.com", "statcounter.com", "histats.com", "addthis.com", "sharethis.com", "disqus.com.ads",
        "comscore.com", "imrworldwide.com", "omtrdc.net", "2o7.net", "pardot.com", "marketo.net",
        // Regional networks and trackers
        "mc.yandex.ru", "an.yandex.ru", "yandexadexchange.net", "tns-counter.ru", "hm.baidu.com",
        "cnzz.com", "umeng.com", "gdt.qq.com", "adsmogo.com"
    )

    fun isBlocked(host: String?): Boolean {
        if (host.isNullOrEmpty()) return false
        var h = host.lowercase()
        while (true) {
            if (domains.contains(h)) return true
            val i = h.indexOf('.')
            if (i < 0 || i == h.length - 1) return false
            h = h.substring(i + 1)
        }
    }
}
