'use strict';
/*
 * Thornswood gamemode
 * ===================
 *
 * Loaded by skymp5-server through requireTemp(), which copies this file to a
 * temp directory and requires it there. Relative requires would break, so
 * everything lives in this one file and all data is inlined. The server watches
 * the file and hot-reloads on change; mp.clear() runs first, so re-registering
 * handlers at load time is correct and expected.
 *
 * The event contract, read out of ScampServerListener::OnMpApiEvent:
 * the server looks up a function by name on the global `mp` object, calls it
 * with the event's arguments, and treats a returned `false` as "block this".
 * Returning undefined lets the event through. A handler that throws is logged
 * and the event proceeds, but do not rely on that: every handler here is
 * wrapped, because an exception on a hot path is a bad way to find a typo.
 *
 * Form ids cross the boundary as descriptors, "<low 24 bits in hex>:<plugin>",
 * so nothing here is baked to a load order position.
 */

const DATA = {"holds":{"WhiterunHoldLocation":{"crimeFaction":"0x0267EA"},"HaafingarHoldLocation":{"crimeFaction":"0x029DB0"},"FalkreathHoldLocation":{"crimeFaction":"0x028170"},"HjaalmarchHoldLocation":{"crimeFaction":"0x02816D"},"PaleHoldLocation":{"crimeFaction":"0x02816E"},"RiftHoldLocation":{"crimeFaction":"0x02816B"},"WinterholdHoldLocation":{"crimeFaction":"0x02816F"},"EastmarchHoldLocation":{"crimeFaction":"0x0267E3"},"ReachHoldLocation":{"crimeFaction":"0x02816C"},"DLC2SolstheimLocation":{"crimeFaction":null}},"holdToDestination":{"PaleHoldLocation":null,"WinterholdHoldLocation":null,"HjaalmarchHoldLocation":null,"FalkreathHoldLocation":null,"WhiterunHoldLocation":"whiterun","HaafingarHoldLocation":"solitude","EastmarchHoldLocation":"windhelm","ReachHoldLocation":"markarth","RiftHoldLocation":"riften","DLC2SolstheimLocation":"ravenrock"},"cellToHold":{"27d1c:Skyrim.esm":"HaafingarHoldLocation","13a7e:Skyrim.esm":"HaafingarHoldLocation","1ce8a:Skyrim.esm":"FalkreathHoldLocation","27f1a:Skyrim.esm":"HaafingarHoldLocation","580a2:Skyrim.esm":"WhiterunHoldLocation","94322:Skyrim.esm":"PaleHoldLocation","13a88:Skyrim.esm":"PaleHoldLocation","1525c:Skyrim.esm":"RiftHoldLocation","152c0:Skyrim.esm":"EastmarchHoldLocation","161fc:Skyrim.esm":"EastmarchHoldLocation","16774:Skyrim.esm":"EastmarchHoldLocation","2d3e8:Skyrim.esm":"RiftHoldLocation","1383a:Skyrim.esm":"RiftHoldLocation","1677e:Skyrim.esm":"EastmarchHoldLocation","16788:Skyrim.esm":"EastmarchHoldLocation","16bd4:Skyrim.esm":"RiftHoldLocation","275d8:Skyrim.esm":"RiftHoldLocation","34864:Skyrim.esm":"ReachHoldLocation","58b4c:Skyrim.esm":"ReachHoldLocation","7bef8:Skyrim.esm":"WinterholdHoldLocation","16bde:Skyrim.esm":"RiftHoldLocation","1fc66:Skyrim.esm":"WhiterunHoldLocation","3486e:Skyrim.esm":"ReachHoldLocation","37cc6:Skyrim.esm":"RiftHoldLocation","3b696:Skyrim.esm":"RiftHoldLocation","3f516:Skyrim.esm":"EastmarchHoldLocation","50f1e:Skyrim.esm":"HjaalmarchHoldLocation","563e2:Skyrim.esm":"HjaalmarchHoldLocation","dd216:Skyrim.esm":"HaafingarHoldLocation","15220:Skyrim.esm":"WinterholdHoldLocation","15284:Skyrim.esm":"WinterholdHoldLocation","165a8:Skyrim.esm":"WhiterunHoldLocation","7614c:Skyrim.esm":"PaleHoldLocation","97298:Skyrim.esm":"EastmarchHoldLocation","1522a:Skyrim.esm":"ReachHoldLocation","165b2:Skyrim.esm":"WhiterunHoldLocation","169fe:Skyrim.esm":"HaafingarHoldLocation","198de:Skyrim.esm":"ReachHoldLocation","3016a:Skyrim.esm":"HaafingarHoldLocation","67f2a:Skyrim.esm":"EastmarchHoldLocation","7284e:Skyrim.esm":"ReachHoldLocation","9ccde:Skyrim.esm":"RiftHoldLocation","be46a:Skyrim.esm":"HjaalmarchHoldLocation","1386c:Skyrim.esm":"WhiterunHoldLocation","138d0:Skyrim.esm":"HjaalmarchHoldLocation","16a08:Skyrim.esm":"HaafingarHoldLocation","a8b24:Skyrim.esm":"RiftHoldLocation","ddf7c:Skyrim.esm":"FalkreathHoldLocation","133c6:Skyrim.esm":"WhiterunHoldLocation","13812:Skyrim.esm":"WinterholdHoldLocation","152a2:Skyrim.esm":"RiftHoldLocation","16dfa:Skyrim.esm":"ReachHoldLocation","2a03a:Skyrim.esm":"ReachHoldLocation","361fa:Skyrim.esm":"ReachHoldLocation","4a376:Skyrim.esm":"WhiterunHoldLocation","152ad:Skyrim.esm":"ReachHoldLocation","161e9:Skyrim.esm":"HaafingarHoldLocation","13a7f:Skyrim.esm":"PaleHoldLocation","15253:Skyrim.esm":"FalkreathHoldLocation","152b7:Skyrim.esm":"ReachHoldLocation","161f3:Skyrim.esm":"RiftHoldLocation","4624f:Skyrim.esm":"HaafingarHoldLocation","7e00f:Skyrim.esm":"FalkreathHoldLocation","961ff:Skyrim.esm":"WinterholdHoldLocation","13a89:Skyrim.esm":"PaleHoldLocation","151f9:Skyrim.esm":"WhiterunHoldLocation","1525d:Skyrim.esm":"RiftHoldLocation","152c1:Skyrim.esm":"RiftHoldLocation","16775:Skyrim.esm":"EastmarchHoldLocation","2f83d:Skyrim.esm":"PaleHoldLocation","15267:Skyrim.esm":"ReachHoldLocation","16207:Skyrim.esm":"WhiterunHoldLocation","1677f:Skyrim.esm":"EastmarchHoldLocation","16789:Skyrim.esm":"EastmarchHoldLocation","16bd5:Skyrim.esm":"RiftHoldLocation","227b9:Skyrim.esm":"WinterholdHoldLocation","275d9:Skyrim.esm":"RiftHoldLocation","58b4d:Skyrim.esm":"ReachHoldLocation","1527b:Skyrim.esm":"RiftHoldLocation","16bdf:Skyrim.esm":"RiftHoldLocation","41777:Skyrim.esm":"WhiterunHoldLocation","7d033:Skyrim.esm":"EastmarchHoldLocation","af227:Skyrim.esm":"EastmarchHoldLocation","24771:Skyrim.esm":"WinterholdHoldLocation","681dd:Skyrim.esm":"RiftHoldLocation","89d51:Skyrim.esm":"RiftHoldLocation","97299:Skyrim.esm":"EastmarchHoldLocation","165b3:Skyrim.esm":"WhiterunHoldLocation","198df:Skyrim.esm":"ReachHoldLocation","2d4e3:Skyrim.esm":"WinterholdHoldLocation","7b7ab:Skyrim.esm":"HaafingarHoldLocation","9ccdf:Skyrim.esm":"RiftHoldLocation","15235:Skyrim.esm":"HaafingarHoldLocation","16a09:Skyrim.esm":"HaafingarHoldLocation","34955:Skyrim.esm":"EastmarchHoldLocation","36ed5:Skyrim.esm":"WhiterunHoldLocation","70469:Skyrim.esm":"HaafingarHoldLocation","133c7:Skyrim.esm":"WhiterunHoldLocation","13813:Skyrim.esm":"WinterholdHoldLocation","1523f:Skyrim.esm":"EastmarchHoldLocation","16dfb:Skyrim.esm":"ReachHoldLocation","216bb:Skyrim.esm":"FalkreathHoldLocation","54b6f:Skyrim.esm":"EastmarchHoldLocation","13a76:Skyrim.esm":"FalkreathHoldLocation","152ae:Skyrim.esm":"HjaalmarchHoldLocation","161ea:Skyrim.esm":"RiftHoldLocation","261c6:Skyrim.esm":"HaafingarHoldLocation","81972:Skyrim.esm":"WinterholdHoldLocation","ac5d2:Skyrim.esm":"HaafingarHoldLocation","13a80:Skyrim.esm":"PaleHoldLocation","15254:Skyrim.esm":"WinterholdHoldLocation","161f4:Skyrim.esm":"PaleHoldLocation","23fd4:Skyrim.esm":"ReachHoldLocation","362d8:Skyrim.esm":"HaafingarHoldLocation","78124:Skyrim.esm":"PaleHoldLocation","13a8a:Skyrim.esm":"EastmarchHoldLocation","151fa:Skyrim.esm":"WhiterunHoldLocation","161fe:Skyrim.esm":"RiftHoldLocation","16776:Skyrim.esm":"EastmarchHoldLocation","2f83e:Skyrim.esm":"PaleHoldLocation","15268:Skyrim.esm":"FalkreathHoldLocation","16780:Skyrim.esm":"EastmarchHoldLocation","1f358:Skyrim.esm":"EastmarchHoldLocation","c5aa0:Skyrim.esm":"WhiterunHoldLocation","16bd6:Skyrim.esm":"RiftHoldLocation","71ffe:Skyrim.esm":"HaafingarHoldLocation","8e906:Skyrim.esm":"ReachHoldLocation","13850:Skyrim.esm":"RiftHoldLocation","1527c:Skyrim.esm":"WhiterunHoldLocation","165a0:Skyrim.esm":"WhiterunHoldLocation","3b698:Skyrim.esm":"RiftHoldLocation","87764:Skyrim.esm":"WhiterunHoldLocation","138be:Skyrim.esm":"ReachHoldLocation","15286:Skyrim.esm":"RiftHoldLocation","165aa:Skyrim.esm":"WhiterunHoldLocation","7947a:Skyrim.esm":"WhiterunHoldLocation","1522c:Skyrim.esm":"ReachHoldLocation","15290:Skyrim.esm":"PaleHoldLocation","16a00:Skyrim.esm":"HaafingarHoldLocation","198e0:Skyrim.esm":"ReachHoldLocation","25e24:Skyrim.esm":"WinterholdHoldLocation","2d4e4:Skyrim.esm":"WinterholdHoldLocation","16df2:Skyrim.esm":"ReachHoldLocation","36ed6:Skyrim.esm":"WhiterunHoldLocation","91872:Skyrim.esm":"HjaalmarchHoldLocation","dbf12:Skyrim.esm":"EastmarchHoldLocation","133c8:Skyrim.esm":"WhiterunHoldLocation","13814:Skyrim.esm":"WinterholdHoldLocation","16dfc:Skyrim.esm":"ReachHoldLocation","2954c:Skyrim.esm":"PaleHoldLocation","471dc:Skyrim.esm":"WinterholdHoldLocation","5258c:Skyrim.esm":"PaleHoldLocation","54b70:Skyrim.esm":"EastmarchHoldLocation","152af:Skyrim.esm":"ReachHoldLocation","161eb:Skyrim.esm":"ReachHoldLocation","eec53:Skyrim.esm":"WinterholdHoldLocation","13a81:Skyrim.esm":"PaleHoldLocation","15255:Skyrim.esm":"HaafingarHoldLocation","161f5:Skyrim.esm":"ReachHoldLocation","45a1d:Skyrim.esm":"RiftHoldLocation","778f1:Skyrim.esm":"HjaalmarchHoldLocation","a1a61:Skyrim.esm":"FalkreathHoldLocation","a5a71:Skyrim.esm":"RiftHoldLocation","151fb:Skyrim.esm":"PaleHoldLocation","1525f:Skyrim.esm":"WinterholdHoldLocation","152c3:Skyrim.esm":"WinterholdHoldLocation","161ff:Skyrim.esm":"RiftHoldLocation","16777:Skyrim.esm":"EastmarchHoldLocation","5b88b:Skyrim.esm":"RiftHoldLocation","15269:Skyrim.esm":"WhiterunHoldLocation","16209:Skyrim.esm":"PaleHoldLocation","16781:Skyrim.esm":"EastmarchHoldLocation","1f359:Skyrim.esm":"FalkreathHoldLocation","78715:Skyrim.esm":"HjaalmarchHoldLocation","debcd:Skyrim.esm":"WhiterunHoldLocation","15273:Skyrim.esm":"EastmarchHoldLocation","1678b:Skyrim.esm":"EastmarchHoldLocation","16bd7:Skyrim.esm":"RiftHoldLocation","43fab:Skyrim.esm":"WhiterunHoldLocation","1527d:Skyrim.esm":"EastmarchHoldLocation","18be9:Skyrim.esm":"ReachHoldLocation","35299:Skyrim.esm":"WinterholdHoldLocation","4c6dd:Skyrim.esm":"RiftHoldLocation","68b99:Skyrim.esm":"HaafingarHoldLocation","cab91:Skyrim.esm":"WinterholdHoldLocation","15223:Skyrim.esm":"HaafingarHoldLocation","165ab:Skyrim.esm":"WhiterunHoldLocation","3fc8f:Skyrim.esm":"FalkreathHoldLocation","165b5:Skyrim.esm":"WhiterunHoldLocation","2fd85:Skyrim.esm":"PaleHoldLocation","75669:Skyrim.esm":"FalkreathHoldLocation","77289:Skyrim.esm":"HaafingarHoldLocation","15237:Skyrim.esm":"ReachHoldLocation","16a0b:Skyrim.esm":"HaafingarHoldLocation","16df3:Skyrim.esm":"ReachHoldLocation","336fb:Skyrim.esm":"ReachHoldLocation","58663:Skyrim.esm":"HjaalmarchHoldLocation","133c9:Skyrim.esm":"WhiterunHoldLocation","152a5:Skyrim.esm":"EastmarchHoldLocation","16dfd:Skyrim.esm":"ReachHoldLocation","2954d:Skyrim.esm":"PaleHoldLocation","55215:Skyrim.esm":"ReachHoldLocation","abd31:Skyrim.esm":"PaleHoldLocation","13a78:Skyrim.esm":"FalkreathHoldLocation","152b0:Skyrim.esm":"RiftHoldLocation","161ec:Skyrim.esm":"RiftHoldLocation","2e760:Skyrim.esm":"HjaalmarchHoldLocation","3ff10:Skyrim.esm":"WhiterunHoldLocation","b29d4:Skyrim.esm":"WinterholdHoldLocation","151f2:Skyrim.esm":"HaafingarHoldLocation","152ba:Skyrim.esm":"WinterholdHoldLocation","161f6:Skyrim.esm":"ReachHoldLocation","37b76:Skyrim.esm":"RiftHoldLocation","3d35a:Skyrim.esm":"WhiterunHoldLocation","54226:Skyrim.esm":"PaleHoldLocation","5554a:Skyrim.esm":"RiftHoldLocation","13a8c:Skyrim.esm":"EastmarchHoldLocation","151fc:Skyrim.esm":"HaafingarHoldLocation","16200:Skyrim.esm":"EastmarchHoldLocation","16778:Skyrim.esm":"EastmarchHoldLocation","18460:Skyrim.esm":"RiftHoldLocation","7dcfc:Skyrim.esm":"HaafingarHoldLocation","ed8e0:Skyrim.esm":"WinterholdHoldLocation","f5edc:Skyrim.esm":"FalkreathHoldLocation","15206:Skyrim.esm":"WinterholdHoldLocation","1526a:Skyrim.esm":"FalkreathHoldLocation","16782:Skyrim.esm":"EastmarchHoldLocation","16bce:Skyrim.esm":"RiftHoldLocation","15210:Skyrim.esm":"PaleHoldLocation","15274:Skyrim.esm":"WinterholdHoldLocation","1678c:Skyrim.esm":"EastmarchHoldLocation","16bd8:Skyrim.esm":"RiftHoldLocation","18be0:Skyrim.esm":"RiftHoldLocation","5d010:Skyrim.esm":"HjaalmarchHoldLocation","6e2ac:Skyrim.esm":"ReachHoldLocation","a73f4:Skyrim.esm":"EastmarchHoldLocation","aa20c:Skyrim.esm":"ReachHoldLocation","c7348:Skyrim.esm":"PaleHoldLocation","1527e:Skyrim.esm":"PaleHoldLocation","16d72:Skyrim.esm":"ReachHoldLocation","5f536:Skyrim.esm":"ReachHoldLocation","cab92:Skyrim.esm":"WinterholdHoldLocation","15224:Skyrim.esm":"WhiterunHoldLocation","15288:Skyrim.esm":"WinterholdHoldLocation","165ac:Skyrim.esm":"WhiterunHoldLocation","3e908:Skyrim.esm":"HjaalmarchHoldLocation","59398:Skyrim.esm":"ReachHoldLocation","138ca:Skyrim.esm":"HjaalmarchHoldLocation","165b6:Skyrim.esm":"WhiterunHoldLocation","16a02:Skyrim.esm":"HaafingarHoldLocation","198e2:Skyrim.esm":"ReachHoldLocation","2471a:Skyrim.esm":"HaafingarHoldLocation","5a856:Skyrim.esm":"ReachHoldLocation","13870:Skyrim.esm":"WhiterunHoldLocation","15238:Skyrim.esm":"EastmarchHoldLocation","1529c:Skyrim.esm":"ReachHoldLocation","16a0c:Skyrim.esm":"HaafingarHoldLocation","16df4:Skyrim.esm":"ReachHoldLocation","52390:Skyrim.esm":"PaleHoldLocation","6daa0:Skyrim.esm":"HaafingarHoldLocation","133ca:Skyrim.esm":"WhiterunHoldLocation","16dfe:Skyrim.esm":"ReachHoldLocation","13a79:Skyrim.esm":"FalkreathHoldLocation","152b1:Skyrim.esm":"WhiterunHoldLocation","161ed:Skyrim.esm":"ReachHoldLocation","b29d5:Skyrim.esm":"WinterholdHoldLocation","eec55:Skyrim.esm":"WinterholdHoldLocation","13a83:Skyrim.esm":"PaleHoldLocation","151f3:Skyrim.esm":"ReachHoldLocation","15257:Skyrim.esm":"PaleHoldLocation","152bb:Skyrim.esm":"WinterholdHoldLocation","161f7:Skyrim.esm":"HaafingarHoldLocation","270ab:Skyrim.esm":"HjaalmarchHoldLocation","2bcd7:Skyrim.esm":"WinterholdHoldLocation","79f9f:Skyrim.esm":"FalkreathHoldLocation","bbb2f:Skyrim.esm":"HaafingarHoldLocation","15261:Skyrim.esm":"PaleHoldLocation","16779:Skyrim.esm":"EastmarchHoldLocation","52cb5:Skyrim.esm":"PaleHoldLocation","a1bfd:Skyrim.esm":"RiftHoldLocation","13907:Skyrim.esm":"EastmarchHoldLocation","15207:Skyrim.esm":"WhiterunHoldLocation","1526b:Skyrim.esm":"FalkreathHoldLocation","1620b:Skyrim.esm":"PaleHoldLocation","16bcf:Skyrim.esm":"RiftHoldLocation","15211:Skyrim.esm":"WhiterunHoldLocation","15275:Skyrim.esm":"ReachHoldLocation","16bd9:Skyrim.esm":"RiftHoldLocation","5912d:Skyrim.esm":"ReachHoldLocation","83559:Skyrim.esm":"HjaalmarchHoldLocation","ab531:Skyrim.esm":"HjaalmarchHoldLocation","1521b:Skyrim.esm":"HjaalmarchHoldLocation","1527f:Skyrim.esm":"RiftHoldLocation","165a3:Skyrim.esm":"WhiterunHoldLocation","263ef:Skyrim.esm":"HaafingarHoldLocation","3a183:Skyrim.esm":"FalkreathHoldLocation","4401b:Skyrim.esm":"ReachHoldLocation","446bf:Skyrim.esm":"WinterholdHoldLocation","56c1b:Skyrim.esm":"WinterholdHoldLocation","165ad:Skyrim.esm":"WhiterunHoldLocation","13867:Skyrim.esm":"WhiterunHoldLocation","138cb:Skyrim.esm":"HjaalmarchHoldLocation","1522f:Skyrim.esm":"FalkreathHoldLocation","165b7:Skyrim.esm":"WhiterunHoldLocation","16a03:Skyrim.esm":"HaafingarHoldLocation","1aec3:Skyrim.esm":"WinterholdHoldLocation","5a857:Skyrim.esm":"ReachHoldLocation","a013b:Skyrim.esm":"RiftHoldLocation","f2cab:Skyrim.esm":"HjaalmarchHoldLocation","13871:Skyrim.esm":"WhiterunHoldLocation","15239:Skyrim.esm":"EastmarchHoldLocation","1529d:Skyrim.esm":"HjaalmarchHoldLocation","16a0d:Skyrim.esm":"HaafingarHoldLocation","16df5:Skyrim.esm":"ReachHoldLocation","399d1:Skyrim.esm":"ReachHoldLocation","414dd:Skyrim.esm":"WinterholdHoldLocation","7fcdd:Skyrim.esm":"WinterholdHoldLocation","152a7:Skyrim.esm":"EastmarchHoldLocation","16dff:Skyrim.esm":"ReachHoldLocation","30313:Skyrim.esm":"ReachHoldLocation","94bab:Skyrim.esm":"WhiterunHoldLocation","a1793:Skyrim.esm":"HaafingarHoldLocation","c9dab:Skyrim.esm":"WhiterunHoldLocation","13a7a:Skyrim.esm":"HaafingarHoldLocation","1605e:Skyrim.esm":"WhiterunHoldLocation","161ee:Skyrim.esm":"WhiterunHoldLocation","193ee:Skyrim.esm":"PaleHoldLocation","27552:Skyrim.esm":"PaleHoldLocation","527f2:Skyrim.esm":"PaleHoldLocation","54d0e:Skyrim.esm":"WhiterunHoldLocation","8cdee:Skyrim.esm":"ReachHoldLocation","a6d8e:Skyrim.esm":"RiftHoldLocation","b29d6:Skyrim.esm":"WinterholdHoldLocation","13a84:Skyrim.esm":"PaleHoldLocation","151f4:Skyrim.esm":"WinterholdHoldLocation","15258:Skyrim.esm":"FalkreathHoldLocation","69858:Skyrim.esm":"WinterholdHoldLocation","15262:Skyrim.esm":"PaleHoldLocation","1677a:Skyrim.esm":"EastmarchHoldLocation","15208:Skyrim.esm":"WinterholdHoldLocation","1526c:Skyrim.esm":"WhiterunHoldLocation","16784:Skyrim.esm":"EastmarchHoldLocation","16bd0:Skyrim.esm":"RiftHoldLocation","1cb84:Skyrim.esm":"WhiterunHoldLocation","2c778:Skyrim.esm":"PaleHoldLocation","2d524:Skyrim.esm":"RiftHoldLocation","3dd34:Skyrim.esm":"WinterholdHoldLocation","db070:Skyrim.esm":"WhiterunHoldLocation","15276:Skyrim.esm":"HjaalmarchHoldLocation","16bda:Skyrim.esm":"RiftHoldLocation","10ceea:Skyrim.esm":"HjaalmarchHoldLocation","13a48:Skyrim.esm":"RiftHoldLocation","1521c:Skyrim.esm":"WhiterunHoldLocation","15280:Skyrim.esm":"HjaalmarchHoldLocation","3a184:Skyrim.esm":"FalkreathHoldLocation","15226:Skyrim.esm":"ReachHoldLocation","1528a:Skyrim.esm":"ReachHoldLocation","165ae:Skyrim.esm":"WhiterunHoldLocation","1e11e:Skyrim.esm":"EastmarchHoldLocation","2031a:Skyrim.esm":"PaleHoldLocation","5a01a:Skyrim.esm":"ReachHoldLocation","80c6a:Skyrim.esm":"WhiterunHoldLocation","138cc:Skyrim.esm":"HjaalmarchHoldLocation","13a5c:Skyrim.esm":"RiftHoldLocation","15230:Skyrim.esm":"RiftHoldLocation","15294:Skyrim.esm":"RiftHoldLocation","16a04:Skyrim.esm":"HaafingarHoldLocation","1b7c0:Skyrim.esm":"ReachHoldLocation","56e88:Skyrim.esm":"HaafingarHoldLocation","b64b4:Skyrim.esm":"HaafingarHoldLocation","1380e:Skyrim.esm":"WinterholdHoldLocation","13a66:Skyrim.esm":"FalkreathHoldLocation","16a0e:Skyrim.esm":"HaafingarHoldLocation","16df6:Skyrim.esm":"ReachHoldLocation","22f52:Skyrim.esm":"RiftHoldLocation","13818:Skyrim.esm":"WinterholdHoldLocation","152a8:Skyrim.esm":"EastmarchHoldLocation","16e00:Skyrim.esm":"ReachHoldLocation","213a0:Skyrim.esm":"HaafingarHoldLocation","21594:Skyrim.esm":"EastmarchHoldLocation","547f0:Skyrim.esm":"ReachHoldLocation","13a7b:Skyrim.esm":"HaafingarHoldLocation","161ef:Skyrim.esm":"FalkreathHoldLocation","1ab5f:Skyrim.esm":"ReachHoldLocation","1382d:Skyrim.esm":"HjaalmarchHoldLocation","13a85:Skyrim.esm":"PaleHoldLocation","151f5:Skyrim.esm":"WinterholdHoldLocation","a87c5:Skyrim.esm":"HaafingarHoldLocation","16203:Skyrim.esm":"ReachHoldLocation","317e7:Skyrim.esm":"EastmarchHoldLocation","6ccbb:Skyrim.esm":"RiftHoldLocation","a0877:Skyrim.esm":"EastmarchHoldLocation","ae783:Skyrim.esm":"WinterholdHoldLocation","13909:Skyrim.esm":"ReachHoldLocation","139d1:Skyrim.esm":"ReachHoldLocation","1526d:Skyrim.esm":"ReachHoldLocation","16785:Skyrim.esm":"EastmarchHoldLocation","16bd1:Skyrim.esm":"RiftHoldLocation","2c779:Skyrim.esm":"PaleHoldLocation","2d525:Skyrim.esm":"RiftHoldLocation","3b87d:Skyrim.esm":"RiftHoldLocation","5b5dd:Skyrim.esm":"ReachHoldLocation","65ab5:Skyrim.esm":"ReachHoldLocation","15277:Skyrim.esm":"FalkreathHoldLocation","16bdb:Skyrim.esm":"RiftHoldLocation","1f7b3:Skyrim.esm":"ReachHoldLocation","243df:Skyrim.esm":"FalkreathHoldLocation","28edf:Skyrim.esm":"EastmarchHoldLocation","52feb:Skyrim.esm":"EastmarchHoldLocation","7c98b:Skyrim.esm":"HaafingarHoldLocation","15281:Skyrim.esm":"WinterholdHoldLocation","16ea1:Skyrim.esm":"FalkreathHoldLocation","25195:Skyrim.esm":"WinterholdHoldLocation","371dd:Skyrim.esm":"FalkreathHoldLocation","5d01d:Skyrim.esm":"WinterholdHoldLocation","15227:Skyrim.esm":"ReachHoldLocation","165af:Skyrim.esm":"WhiterunHoldLocation","5b91b:Skyrim.esm":"FalkreathHoldLocation","138cd:Skyrim.esm":"HjaalmarchHoldLocation","13a5d:Skyrim.esm":"PaleHoldLocation","15231:Skyrim.esm":"HaafingarHoldLocation","15295:Skyrim.esm":"ReachHoldLocation","16a05:Skyrim.esm":"HaafingarHoldLocation","1380f:Skyrim.esm":"WinterholdHoldLocation","13a67:Skyrim.esm":"FalkreathHoldLocation","1529f:Skyrim.esm":"RiftHoldLocation","16a0f:Skyrim.esm":"HaafingarHoldLocation","16df7:Skyrim.esm":"ReachHoldLocation","22f53:Skyrim.esm":"RiftHoldLocation","47817:Skyrim.esm":"FalkreathHoldLocation","5c483:Skyrim.esm":"RiftHoldLocation","138e1:Skyrim.esm":"HjaalmarchHoldLocation","13a71:Skyrim.esm":"FalkreathHoldLocation","3538d:Skyrim.esm":"FalkreathHoldLocation","529dd:Skyrim.esm":"RiftHoldLocation","53081:Skyrim.esm":"RiftHoldLocation","13a7c:Skyrim.esm":"HaafingarHoldLocation","152b4:Skyrim.esm":"HaafingarHoldLocation","161f0:Skyrim.esm":"EastmarchHoldLocation","19454:Skyrim.esm":"HaafingarHoldLocation","1ab60:Skyrim.esm":"ReachHoldLocation","1382e:Skyrim.esm":"RiftHoldLocation","13a86:Skyrim.esm":"PaleHoldLocation","151f6:Skyrim.esm":"HaafingarHoldLocation","152be:Skyrim.esm":"RiftHoldLocation","9aa4a:Skyrim.esm":"PaleHoldLocation","b6be6:Skyrim.esm":"FalkreathHoldLocation","15200:Skyrim.esm":"RiftHoldLocation","16204:Skyrim.esm":"WhiterunHoldLocation","1677c:Skyrim.esm":"EastmarchHoldLocation","33d68:Skyrim.esm":"ReachHoldLocation","5015c:Skyrim.esm":"RiftHoldLocation","a9194:Skyrim.esm":"ReachHoldLocation","139d2:Skyrim.esm":"ReachHoldLocation","1520a:Skyrim.esm":"WhiterunHoldLocation","1526e:Skyrim.esm":"FalkreathHoldLocation","16786:Skyrim.esm":"EastmarchHoldLocation","16bd2:Skyrim.esm":"RiftHoldLocation","1d09a:Skyrim.esm":"ReachHoldLocation","65ab6:Skyrim.esm":"FalkreathHoldLocation","13978:Skyrim.esm":"ReachHoldLocation","16bdc:Skyrim.esm":"RiftHoldLocation","597d4:Skyrim.esm":"ReachHoldLocation","5de24:Skyrim.esm":"FalkreathHoldLocation","7144c:Skyrim.esm":"PaleHoldLocation","81dec:Skyrim.esm":"FalkreathHoldLocation","9b238:Skyrim.esm":"HaafingarHoldLocation","eb440:Skyrim.esm":"PaleHoldLocation","ef324:Skyrim.esm":"FalkreathHoldLocation","13856:Skyrim.esm":"RiftHoldLocation","15282:Skyrim.esm":"PaleHoldLocation","165a6:Skyrim.esm":"WhiterunHoldLocation","36a72:Skyrim.esm":"ReachHoldLocation","371de:Skyrim.esm":"FalkreathHoldLocation","1528c:Skyrim.esm":"ReachHoldLocation","138ce:Skyrim.esm":"HjaalmarchHoldLocation","15296:Skyrim.esm":"FalkreathHoldLocation","16a06:Skyrim.esm":"HaafingarHoldLocation","1db4e:Skyrim.esm":"WhiterunHoldLocation","13810:Skyrim.esm":"WinterholdHoldLocation","13a68:Skyrim.esm":"FalkreathHoldLocation","1523c:Skyrim.esm":"ReachHoldLocation","152a0:Skyrim.esm":"RiftHoldLocation","16a10:Skyrim.esm":"HaafingarHoldLocation","37ee0:Skyrim.esm":"HaafingarHoldLocation","42bec:Skyrim.esm":"EastmarchHoldLocation","571b4:Skyrim.esm":"ReachHoldLocation","13a72:Skyrim.esm":"FalkreathHoldLocation","152aa:Skyrim.esm":"HjaalmarchHoldLocation","30442:Skyrim.esm":"ReachHoldLocation","13a7d:Skyrim.esm":"HaafingarHoldLocation","15251:Skyrim.esm":"EastmarchHoldLocation","161f1:Skyrim.esm":"EastmarchHoldLocation","2d5d1:Skyrim.esm":"EastmarchHoldLocation","33779:Skyrim.esm":"ReachHoldLocation","13a87:Skyrim.esm":"PaleHoldLocation","161fb:Skyrim.esm":"EastmarchHoldLocation","1a337:Skyrim.esm":"EastmarchHoldLocation","1b147:Skyrim.esm":"FalkreathHoldLocation","2d3e7:Skyrim.esm":"RiftHoldLocation","7bc27:Skyrim.esm":"EastmarchHoldLocation","13901:Skyrim.esm":"EastmarchHoldLocation","15201:Skyrim.esm":"RiftHoldLocation","15265:Skyrim.esm":"FalkreathHoldLocation","16205:Skyrim.esm":"EastmarchHoldLocation","1677d:Skyrim.esm":"EastmarchHoldLocation","2e521:Skyrim.esm":"FalkreathHoldLocation","5015d:Skyrim.esm":"EastmarchHoldLocation","1526f:Skyrim.esm":"HjaalmarchHoldLocation","16787:Skyrim.esm":"EastmarchHoldLocation","16bd3:Skyrim.esm":"RiftHoldLocation","240b7:Skyrim.esm":"PaleHoldLocation","7bef7:Skyrim.esm":"WinterholdHoldLocation","13979:Skyrim.esm":"ReachHoldLocation","15215:Skyrim.esm":"PaleHoldLocation","15279:Skyrim.esm":"WinterholdHoldLocation","16bdd:Skyrim.esm":"RiftHoldLocation","ad5a1:Skyrim.esm":"FalkreathHoldLocation","ef325:Skyrim.esm":"FalkreathHoldLocation","139e7:Skyrim.esm":"RiftHoldLocation","15283:Skyrim.esm":"WhiterunHoldLocation","165a7:Skyrim.esm":"WhiterunHoldLocation","466cb:Skyrim.esm":"PaleHoldLocation","965b3:Skyrim.esm":"EastmarchHoldLocation","d9dc7:Skyrim.esm":"RiftHoldLocation","15229:Skyrim.esm":"WhiterunHoldLocation","165b1:Skyrim.esm":"WhiterunHoldLocation","198dd:Skyrim.esm":"ReachHoldLocation","3ea9d:Skyrim.esm":"ReachHoldLocation","8b84d:Skyrim.esm":"FalkreathHoldLocation","9ccdd:Skyrim.esm":"RiftHoldLocation","138cf:Skyrim.esm":"HjaalmarchHoldLocation","15233:Skyrim.esm":"HjaalmarchHoldLocation","16a07:Skyrim.esm":"HaafingarHoldLocation","3cbcb:Skyrim.esm":"RiftHoldLocation","4761b:Skyrim.esm":"RiftHoldLocation","918d3:Skyrim.esm":"WhiterunHoldLocation","a8b23:Skyrim.esm":"RiftHoldLocation","1523d:Skyrim.esm":"HjaalmarchHoldLocation","152a1:Skyrim.esm":"PaleHoldLocation","16a11:Skyrim.esm":"HaafingarHoldLocation","361f9:Skyrim.esm":"ReachHoldLocation","42bed:Skyrim.esm":"EastmarchHoldLocation","ba599:Skyrim.esm":"HaafingarHoldLocation","13a73:Skyrim.esm":"FalkreathHoldLocation","161e7:Skyrim.esm":"WinterholdHoldLocation","352c7:Skyrim.esm":"WhiterunHoldLocation","4b8fb:Skyrim.esm":"EastmarchHoldLocation","90e8:Skyrim.esm":"PaleHoldLocation","9102:Skyrim.esm":"PaleHoldLocation","9105:Skyrim.esm":"WhiterunHoldLocation","9143:Skyrim.esm":"WhiterunHoldLocation","9144:Skyrim.esm":"WhiterunHoldLocation","9146:Skyrim.esm":"WhiterunHoldLocation","915f:Skyrim.esm":"WhiterunHoldLocation","951f:Skyrim.esm":"WhiterunHoldLocation","9540:Skyrim.esm":"WhiterunHoldLocation","95bb:Skyrim.esm":"WhiterunHoldLocation","95bc:Skyrim.esm":"WhiterunHoldLocation","99a2:Skyrim.esm":"WhiterunHoldLocation","8feb:Skyrim.esm":"PaleHoldLocation","8fec:Skyrim.esm":"PaleHoldLocation","900a:Skyrim.esm":"PaleHoldLocation","900b:Skyrim.esm":"PaleHoldLocation","902f:Skyrim.esm":"HjaalmarchHoldLocation","9068:Skyrim.esm":"HjaalmarchHoldLocation","906a:Skyrim.esm":"HjaalmarchHoldLocation","9089:Skyrim.esm":"HjaalmarchHoldLocation","908a:Skyrim.esm":"HjaalmarchHoldLocation","8ef4:Skyrim.esm":"PaleHoldLocation","8f15:Skyrim.esm":"PaleHoldLocation","8f56:Skyrim.esm":"HjaalmarchHoldLocation","8f71:Skyrim.esm":"PaleHoldLocation","8f75:Skyrim.esm":"HjaalmarchHoldLocation","8fb2:Skyrim.esm":"PaleHoldLocation","8fce:Skyrim.esm":"PaleHoldLocation","8fcf:Skyrim.esm":"PaleHoldLocation","92ac:Skyrim.esm":"PaleHoldLocation","8e77:Skyrim.esm":"PaleHoldLocation","8e96:Skyrim.esm":"PaleHoldLocation","8e97:Skyrim.esm":"PaleHoldLocation","8eb5:Skyrim.esm":"PaleHoldLocation","8eb6:Skyrim.esm":"PaleHoldLocation","8ed4:Skyrim.esm":"PaleHoldLocation","8ed5:Skyrim.esm":"PaleHoldLocation","926a:Skyrim.esm":"PaleHoldLocation","928b:Skyrim.esm":"PaleHoldLocation","90dd:Skyrim.esm":"PaleHoldLocation","9100:Skyrim.esm":"PaleHoldLocation","9101:Skyrim.esm":"PaleHoldLocation","9119:Skyrim.esm":"PaleHoldLocation","9120:Skyrim.esm":"PaleHoldLocation","9138:Skyrim.esm":"PaleHoldLocation","9176:Skyrim.esm":"WhiterunHoldLocation","917a:Skyrim.esm":"WhiterunHoldLocation","9195:Skyrim.esm":"WhiterunHoldLocation","9006:Skyrim.esm":"PaleHoldLocation","9022:Skyrim.esm":"PaleHoldLocation","9028:Skyrim.esm":"PaleHoldLocation","9063:Skyrim.esm":"PaleHoldLocation","9064:Skyrim.esm":"PaleHoldLocation","907f:Skyrim.esm":"PaleHoldLocation","9084:Skyrim.esm":"PaleHoldLocation","909f:Skyrim.esm":"PaleHoldLocation","90a2:Skyrim.esm":"PaleHoldLocation","90a3:Skyrim.esm":"PaleHoldLocation","90be:Skyrim.esm":"PaleHoldLocation","90bf:Skyrim.esm":"PaleHoldLocation","8eed:Skyrim.esm":"WinterholdHoldLocation","8eee:Skyrim.esm":"WinterholdHoldLocation","8f0c:Skyrim.esm":"WinterholdHoldLocation","8f29:Skyrim.esm":"WinterholdHoldLocation","8f69:Skyrim.esm":"WinterholdHoldLocation","8fa7:Skyrim.esm":"WinterholdHoldLocation","8fa8:Skyrim.esm":"WinterholdHoldLocation","8faa:Skyrim.esm":"WinterholdHoldLocation","8fcb:Skyrim.esm":"PaleHoldLocation","8e14:Skyrim.esm":"WinterholdHoldLocation","8e15:Skyrim.esm":"WinterholdHoldLocation","8e34:Skyrim.esm":"WinterholdHoldLocation","8e51:Skyrim.esm":"WinterholdHoldLocation","8e76:Skyrim.esm":"PaleHoldLocation","8e95:Skyrim.esm":"PaleHoldLocation","8eb4:Skyrim.esm":"PaleHoldLocation","8ed1:Skyrim.esm":"PaleHoldLocation","8ed2:Skyrim.esm":"PaleHoldLocation","8ed3:Skyrim.esm":"PaleHoldLocation","90d7:Skyrim.esm":"PaleHoldLocation","90d8:Skyrim.esm":"PaleHoldLocation","90da:Skyrim.esm":"PaleHoldLocation","90f4:Skyrim.esm":"PaleHoldLocation","90f6:Skyrim.esm":"PaleHoldLocation","90f7:Skyrim.esm":"PaleHoldLocation","9113:Skyrim.esm":"PaleHoldLocation","9117:Skyrim.esm":"PaleHoldLocation","9118:Skyrim.esm":"PaleHoldLocation","9132:Skyrim.esm":"PaleHoldLocation","9136:Skyrim.esm":"PaleHoldLocation","9137:Skyrim.esm":"PaleHoldLocation","9151:Skyrim.esm":"PaleHoldLocation","95b0:Skyrim.esm":"WhiterunHoldLocation","8fdb:Skyrim.esm":"WinterholdHoldLocation","8fdc:Skyrim.esm":"WinterholdHoldLocation","8fe0:Skyrim.esm":"WinterholdHoldLocation","9019:Skyrim.esm":"PaleHoldLocation","901a:Skyrim.esm":"PaleHoldLocation","901d:Skyrim.esm":"PaleHoldLocation","9038:Skyrim.esm":"PaleHoldLocation","9039:Skyrim.esm":"PaleHoldLocation","903a:Skyrim.esm":"PaleHoldLocation","905c:Skyrim.esm":"PaleHoldLocation","905d:Skyrim.esm":"PaleHoldLocation","9079:Skyrim.esm":"PaleHoldLocation","907c:Skyrim.esm":"PaleHoldLocation","90b6:Skyrim.esm":"PaleHoldLocation","90b7:Skyrim.esm":"PaleHoldLocation","8eea:Skyrim.esm":"WinterholdHoldLocation","8f03:Skyrim.esm":"WinterholdHoldLocation","8f63:Skyrim.esm":"WinterholdHoldLocation","8f82:Skyrim.esm":"WinterholdHoldLocation","8f83:Skyrim.esm":"WinterholdHoldLocation","8f9d:Skyrim.esm":"WinterholdHoldLocation","8fbc:Skyrim.esm":"WinterholdHoldLocation","8fbd:Skyrim.esm":"WinterholdHoldLocation","8e29:Skyrim.esm":"WinterholdHoldLocation","8e4b:Skyrim.esm":"WinterholdHoldLocation","8e89:Skyrim.esm":"WinterholdHoldLocation","8eab:Skyrim.esm":"WinterholdHoldLocation","90cf:Skyrim.esm":"PaleHoldLocation","90d0:Skyrim.esm":"PaleHoldLocation","90d1:Skyrim.esm":"PaleHoldLocation","910b:Skyrim.esm":"EastmarchHoldLocation","910c:Skyrim.esm":"EastmarchHoldLocation","910f:Skyrim.esm":"EastmarchHoldLocation","912a:Skyrim.esm":"EastmarchHoldLocation","912b:Skyrim.esm":"EastmarchHoldLocation","912e:Skyrim.esm":"EastmarchHoldLocation","9149:Skyrim.esm":"EastmarchHoldLocation","914a:Skyrim.esm":"EastmarchHoldLocation","916b:Skyrim.esm":"EastmarchHoldLocation","9187:Skyrim.esm":"EastmarchHoldLocation","918c:Skyrim.esm":"EastmarchHoldLocation","8fd3:Skyrim.esm":"WinterholdHoldLocation","8ff3:Skyrim.esm":"WinterholdHoldLocation","9014:Skyrim.esm":"WinterholdHoldLocation","9015:Skyrim.esm":"WinterholdHoldLocation","9016:Skyrim.esm":"WinterholdHoldLocation","9034:Skyrim.esm":"WinterholdHoldLocation","9035:Skyrim.esm":"WinterholdHoldLocation","9036:Skyrim.esm":"WinterholdHoldLocation","9092:Skyrim.esm":"PaleHoldLocation","90b1:Skyrim.esm":"PaleHoldLocation","8ede:Skyrim.esm":"WinterholdHoldLocation","8edf:Skyrim.esm":"WinterholdHoldLocation","8ee0:Skyrim.esm":"WinterholdHoldLocation","8f39:Skyrim.esm":"WinterholdHoldLocation","8f3a:Skyrim.esm":"WinterholdHoldLocation","8f58:Skyrim.esm":"WinterholdHoldLocation","8f5e:Skyrim.esm":"WinterholdHoldLocation","8f76:Skyrim.esm":"WinterholdHoldLocation","8f77:Skyrim.esm":"WinterholdHoldLocation","8f9c:Skyrim.esm":"WinterholdHoldLocation","8fbb:Skyrim.esm":"WinterholdHoldLocation","8e04:Skyrim.esm":"WinterholdHoldLocation","8e23:Skyrim.esm":"WinterholdHoldLocation","8e24:Skyrim.esm":"WinterholdHoldLocation","8e61:Skyrim.esm":"WinterholdHoldLocation","8e62:Skyrim.esm":"WinterholdHoldLocation","8e63:Skyrim.esm":"WinterholdHoldLocation","8e81:Skyrim.esm":"WinterholdHoldLocation","8e82:Skyrim.esm":"WinterholdHoldLocation","8e83:Skyrim.esm":"WinterholdHoldLocation","8ea1:Skyrim.esm":"WinterholdHoldLocation","8ea2:Skyrim.esm":"WinterholdHoldLocation","8ec0:Skyrim.esm":"WinterholdHoldLocation","8ec1:Skyrim.esm":"WinterholdHoldLocation","3934:Skyrim.esm":"WinterholdHoldLocation","98e1:Skyrim.esm":"FalkreathHoldLocation","9d1d:Skyrim.esm":"FalkreathHoldLocation","9d3e:Skyrim.esm":"FalkreathHoldLocation","97cc:Skyrim.esm":"FalkreathHoldLocation","97eb:Skyrim.esm":"FalkreathHoldLocation","97ed:Skyrim.esm":"FalkreathHoldLocation","97ee:Skyrim.esm":"FalkreathHoldLocation","980b:Skyrim.esm":"FalkreathHoldLocation","980c:Skyrim.esm":"FalkreathHoldLocation","982a:Skyrim.esm":"FalkreathHoldLocation","982b:Skyrim.esm":"FalkreathHoldLocation","9849:Skyrim.esm":"FalkreathHoldLocation","984a:Skyrim.esm":"FalkreathHoldLocation","9865:Skyrim.esm":"FalkreathHoldLocation","9884:Skyrim.esm":"FalkreathHoldLocation","9888:Skyrim.esm":"FalkreathHoldLocation","98a4:Skyrim.esm":"FalkreathHoldLocation","9c78:Skyrim.esm":"FalkreathHoldLocation","9c99:Skyrim.esm":"FalkreathHoldLocation","9cba:Skyrim.esm":"FalkreathHoldLocation","96f2:Skyrim.esm":"WhiterunHoldLocation","96f3:Skyrim.esm":"WhiterunHoldLocation","9711:Skyrim.esm":"WhiterunHoldLocation","9712:Skyrim.esm":"WhiterunHoldLocation","9713:Skyrim.esm":"WhiterunHoldLocation","9730:Skyrim.esm":"WhiterunHoldLocation","9731:Skyrim.esm":"WhiterunHoldLocation","9732:Skyrim.esm":"WhiterunHoldLocation","9733:Skyrim.esm":"WhiterunHoldLocation","9771:Skyrim.esm":"FalkreathHoldLocation","9773:Skyrim.esm":"FalkreathHoldLocation","978c:Skyrim.esm":"FalkreathHoldLocation","9791:Skyrim.esm":"FalkreathHoldLocation","9792:Skyrim.esm":"ReachHoldLocation","9aec:Skyrim.esm":"FalkreathHoldLocation","9b0d:Skyrim.esm":"FalkreathHoldLocation","9b4f:Skyrim.esm":"FalkreathHoldLocation","9b91:Skyrim.esm":"FalkreathHoldLocation","95da:Skyrim.esm":"WhiterunHoldLocation","95db:Skyrim.esm":"WhiterunHoldLocation","95dc:Skyrim.esm":"WhiterunHoldLocation","95dd:Skyrim.esm":"WhiterunHoldLocation","95de:Skyrim.esm":"WhiterunHoldLocation","95fa:Skyrim.esm":"WhiterunHoldLocation","95fb:Skyrim.esm":"WhiterunHoldLocation","95fc:Skyrim.esm":"WhiterunHoldLocation","95fd:Skyrim.esm":"WhiterunHoldLocation","9618:Skyrim.esm":"WhiterunHoldLocation","9619:Skyrim.esm":"WhiterunHoldLocation","961a:Skyrim.esm":"WhiterunHoldLocation","961b:Skyrim.esm":"WhiterunHoldLocation","961c:Skyrim.esm":"WhiterunHoldLocation","9637:Skyrim.esm":"WhiterunHoldLocation","9639:Skyrim.esm":"WhiterunHoldLocation","963a:Skyrim.esm":"WhiterunHoldLocation","963b:Skyrim.esm":"WhiterunHoldLocation","963d:Skyrim.esm":"WhiterunHoldLocation","9656:Skyrim.esm":"WhiterunHoldLocation","9657:Skyrim.esm":"WhiterunHoldLocation","9658:Skyrim.esm":"WhiterunHoldLocation","9659:Skyrim.esm":"WhiterunHoldLocation","9676:Skyrim.esm":"WhiterunHoldLocation","9677:Skyrim.esm":"WhiterunHoldLocation","9678:Skyrim.esm":"WhiterunHoldLocation","9a26:Skyrim.esm":"WhiterunHoldLocation","98ba:Skyrim.esm":"RiftHoldLocation","97c8:Skyrim.esm":"FalkreathHoldLocation","97c9:Skyrim.esm":"FalkreathHoldLocation","97e7:Skyrim.esm":"FalkreathHoldLocation","97e8:Skyrim.esm":"FalkreathHoldLocation","9805:Skyrim.esm":"FalkreathHoldLocation","9806:Skyrim.esm":"FalkreathHoldLocation","9821:Skyrim.esm":"FalkreathHoldLocation","9822:Skyrim.esm":"FalkreathHoldLocation","9824:Skyrim.esm":"FalkreathHoldLocation","9840:Skyrim.esm":"FalkreathHoldLocation","9841:Skyrim.esm":"FalkreathHoldLocation","9864:Skyrim.esm":"FalkreathHoldLocation","987c:Skyrim.esm":"RiftHoldLocation","9882:Skyrim.esm":"FalkreathHoldLocation","9883:Skyrim.esm":"FalkreathHoldLocation","989b:Skyrim.esm":"RiftHoldLocation","98a2:Skyrim.esm":"FalkreathHoldLocation","96cc:Skyrim.esm":"WhiterunHoldLocation","96cd:Skyrim.esm":"WhiterunHoldLocation","96ea:Skyrim.esm":"WhiterunHoldLocation","96eb:Skyrim.esm":"WhiterunHoldLocation","9708:Skyrim.esm":"WhiterunHoldLocation","9709:Skyrim.esm":"WhiterunHoldLocation","970a:Skyrim.esm":"WhiterunHoldLocation","9728:Skyrim.esm":"WhiterunHoldLocation","9729:Skyrim.esm":"WhiterunHoldLocation","972a:Skyrim.esm":"WhiterunHoldLocation","9746:Skyrim.esm":"WhiterunHoldLocation","9747:Skyrim.esm":"WhiterunHoldLocation","9748:Skyrim.esm":"WhiterunHoldLocation","9749:Skyrim.esm":"WhiterunHoldLocation","9765:Skyrim.esm":"WhiterunHoldLocation","9766:Skyrim.esm":"WhiterunHoldLocation","9767:Skyrim.esm":"WhiterunHoldLocation","9785:Skyrim.esm":"WhiterunHoldLocation","9786:Skyrim.esm":"WhiterunHoldLocation","978b:Skyrim.esm":"FalkreathHoldLocation","97aa:Skyrim.esm":"FalkreathHoldLocation","95d5:Skyrim.esm":"WhiterunHoldLocation","95f4:Skyrim.esm":"WhiterunHoldLocation","95f8:Skyrim.esm":"WhiterunHoldLocation","9632:Skyrim.esm":"WhiterunHoldLocation","9634:Skyrim.esm":"WhiterunHoldLocation","9635:Skyrim.esm":"WhiterunHoldLocation","9651:Skyrim.esm":"WhiterunHoldLocation","9653:Skyrim.esm":"WhiterunHoldLocation","9655:Skyrim.esm":"WhiterunHoldLocation","98b2:Skyrim.esm":"RiftHoldLocation","98b4:Skyrim.esm":"RiftHoldLocation","98b5:Skyrim.esm":"RiftHoldLocation","98b6:Skyrim.esm":"RiftHoldLocation","98b8:Skyrim.esm":"RiftHoldLocation","98b9:Skyrim.esm":"RiftHoldLocation","98d4:Skyrim.esm":"RiftHoldLocation","98d5:Skyrim.esm":"RiftHoldLocation","98d6:Skyrim.esm":"RiftHoldLocation","98d7:Skyrim.esm":"RiftHoldLocation","98d8:Skyrim.esm":"RiftHoldLocation","98f3:Skyrim.esm":"RiftHoldLocation","97be:Skyrim.esm":"RiftHoldLocation","97bf:Skyrim.esm":"RiftHoldLocation","97dd:Skyrim.esm":"RiftHoldLocation","97fc:Skyrim.esm":"RiftHoldLocation","9839:Skyrim.esm":"RiftHoldLocation","983a:Skyrim.esm":"RiftHoldLocation","983c:Skyrim.esm":"RiftHoldLocation","9857:Skyrim.esm":"RiftHoldLocation","9858:Skyrim.esm":"RiftHoldLocation","9859:Skyrim.esm":"RiftHoldLocation","987b:Skyrim.esm":"RiftHoldLocation","9895:Skyrim.esm":"RiftHoldLocation","9896:Skyrim.esm":"RiftHoldLocation","9899:Skyrim.esm":"RiftHoldLocation","989a:Skyrim.esm":"RiftHoldLocation","9726:Skyrim.esm":"WhiterunHoldLocation","9762:Skyrim.esm":"RiftHoldLocation","9781:Skyrim.esm":"RiftHoldLocation","979d:Skyrim.esm":"RiftHoldLocation","979f:Skyrim.esm":"RiftHoldLocation","97a0:Skyrim.esm":"RiftHoldLocation","97a1:Skyrim.esm":"RiftHoldLocation","95cd:Skyrim.esm":"FalkreathHoldLocation","95ce:Skyrim.esm":"FalkreathHoldLocation","95cf:Skyrim.esm":"WhiterunHoldLocation","95d0:Skyrim.esm":"WhiterunHoldLocation","95ea:Skyrim.esm":"EastmarchHoldLocation","960d:Skyrim.esm":"WhiterunHoldLocation","960e:Skyrim.esm":"WhiterunHoldLocation","960f:Skyrim.esm":"WhiterunHoldLocation","9627:Skyrim.esm":"EastmarchHoldLocation","9646:Skyrim.esm":"EastmarchHoldLocation","9647:Skyrim.esm":"EastmarchHoldLocation","964a:Skyrim.esm":"PaleHoldLocation","9665:Skyrim.esm":"EastmarchHoldLocation","9666:Skyrim.esm":"EastmarchHoldLocation","9684:Skyrim.esm":"EastmarchHoldLocation","96a3:Skyrim.esm":"EastmarchHoldLocation","98ca:Skyrim.esm":"RiftHoldLocation","98e9:Skyrim.esm":"RiftHoldLocation","98ea:Skyrim.esm":"RiftHoldLocation","97b3:Skyrim.esm":"RiftHoldLocation","97b4:Skyrim.esm":"RiftHoldLocation","97b5:Skyrim.esm":"RiftHoldLocation","97b6:Skyrim.esm":"RiftHoldLocation","97d5:Skyrim.esm":"RiftHoldLocation","9812:Skyrim.esm":"RiftHoldLocation","9813:Skyrim.esm":"RiftHoldLocation","9831:Skyrim.esm":"RiftHoldLocation","9832:Skyrim.esm":"RiftHoldLocation","9851:Skyrim.esm":"RiftHoldLocation","988e:Skyrim.esm":"RiftHoldLocation","988f:Skyrim.esm":"RiftHoldLocation","96bb:Skyrim.esm":"EastmarchHoldLocation","96bc:Skyrim.esm":"EastmarchHoldLocation","96bd:Skyrim.esm":"EastmarchHoldLocation","96fe:Skyrim.esm":"RiftHoldLocation","971b:Skyrim.esm":"RiftHoldLocation","971c:Skyrim.esm":"RiftHoldLocation","9758:Skyrim.esm":"EastmarchHoldLocation","975c:Skyrim.esm":"RiftHoldLocation","9779:Skyrim.esm":"RiftHoldLocation","977a:Skyrim.esm":"RiftHoldLocation","977b:Skyrim.esm":"RiftHoldLocation","9794:Skyrim.esm":"RiftHoldLocation","9795:Skyrim.esm":"RiftHoldLocation","9796:Skyrim.esm":"RiftHoldLocation","9797:Skyrim.esm":"RiftHoldLocation","95e3:Skyrim.esm":"EastmarchHoldLocation","95e6:Skyrim.esm":"EastmarchHoldLocation","961f:Skyrim.esm":"EastmarchHoldLocation","9623:Skyrim.esm":"EastmarchHoldLocation","963e:Skyrim.esm":"EastmarchHoldLocation","9645:Skyrim.esm":"EastmarchHoldLocation","965f:Skyrim.esm":"EastmarchHoldLocation","9663:Skyrim.esm":"EastmarchHoldLocation","9664:Skyrim.esm":"EastmarchHoldLocation","9683:Skyrim.esm":"EastmarchHoldLocation","969b:Skyrim.esm":"EastmarchHoldLocation","969d:Skyrim.esm":"EastmarchHoldLocation","969e:Skyrim.esm":"EastmarchHoldLocation","b4db:Skyrim.esm":"EastmarchHoldLocation","b4dc:Skyrim.esm":"EastmarchHoldLocation","b4f6:Skyrim.esm":"EastmarchHoldLocation","b4f9:Skyrim.esm":"EastmarchHoldLocation","b4fa:Skyrim.esm":"EastmarchHoldLocation","b4fb:Skyrim.esm":"EastmarchHoldLocation","b4fc:Skyrim.esm":"EastmarchHoldLocation","b4fd:Skyrim.esm":"EastmarchHoldLocation","b51a:Skyrim.esm":"EastmarchHoldLocation","b51b:Skyrim.esm":"EastmarchHoldLocation","b51d:Skyrim.esm":"EastmarchHoldLocation","b53b:Skyrim.esm":"EastmarchHoldLocation","b53c:Skyrim.esm":"EastmarchHoldLocation","b53d:Skyrim.esm":"EastmarchHoldLocation","b53f:Skyrim.esm":"EastmarchHoldLocation","b55c:Skyrim.esm":"EastmarchHoldLocation","b55d:Skyrim.esm":"EastmarchHoldLocation","b55e:Skyrim.esm":"EastmarchHoldLocation","b55f:Skyrim.esm":"EastmarchHoldLocation","b560:Skyrim.esm":"EastmarchHoldLocation","b57b:Skyrim.esm":"EastmarchHoldLocation","b57d:Skyrim.esm":"EastmarchHoldLocation","b57e:Skyrim.esm":"EastmarchHoldLocation","b57f:Skyrim.esm":"EastmarchHoldLocation","b580:Skyrim.esm":"EastmarchHoldLocation","b581:Skyrim.esm":"EastmarchHoldLocation","b59b:Skyrim.esm":"EastmarchHoldLocation","b59c:Skyrim.esm":"EastmarchHoldLocation","b5a0:Skyrim.esm":"EastmarchHoldLocation","b5a1:Skyrim.esm":"EastmarchHoldLocation","b412:Skyrim.esm":"WinterholdHoldLocation","b413:Skyrim.esm":"WinterholdHoldLocation","b434:Skyrim.esm":"WinterholdHoldLocation","b452:Skyrim.esm":"WinterholdHoldLocation","b493:Skyrim.esm":"EastmarchHoldLocation","b4b4:Skyrim.esm":"EastmarchHoldLocation","b4b7:Skyrim.esm":"EastmarchHoldLocation","b4b8:Skyrim.esm":"EastmarchHoldLocation","b4b9:Skyrim.esm":"EastmarchHoldLocation","b4ba:Skyrim.esm":"EastmarchHoldLocation","b4bb:Skyrim.esm":"EastmarchHoldLocation","b2ea:Skyrim.esm":"WinterholdHoldLocation","b350:Skyrim.esm":"WinterholdHoldLocation","b370:Skyrim.esm":"WinterholdHoldLocation","b38f:Skyrim.esm":"WinterholdHoldLocation","b201:Skyrim.esm":"WinterholdHoldLocation","b202:Skyrim.esm":"WinterholdHoldLocation","b222:Skyrim.esm":"WinterholdHoldLocation","b223:Skyrim.esm":"WinterholdHoldLocation","b267:Skyrim.esm":"WinterholdHoldLocation","b268:Skyrim.esm":"WinterholdHoldLocation","b289:Skyrim.esm":"WinterholdHoldLocation","b2aa:Skyrim.esm":"WinterholdHoldLocation","b4f5:Skyrim.esm":"EastmarchHoldLocation","b9b9:Skyrim.esm":"EastmarchHoldLocation","b3ca:Skyrim.esm":"WinterholdHoldLocation","b3cb:Skyrim.esm":"WinterholdHoldLocation","b491:Skyrim.esm":"EastmarchHoldLocation","b3a9:Skyrim.esm":"WinterholdHoldLocation","b3aa:Skyrim.esm":"WinterholdHoldLocation","bcf5:Skyrim.esm":"RiftHoldLocation","bcf6:Skyrim.esm":"RiftHoldLocation","bcf7:Skyrim.esm":"RiftHoldLocation","bd16:Skyrim.esm":"RiftHoldLocation","bd3c:Skyrim.esm":"RiftHoldLocation","bd3d:Skyrim.esm":"RiftHoldLocation","bd5d:Skyrim.esm":"RiftHoldLocation","bd5e:Skyrim.esm":"RiftHoldLocation","bd7b:Skyrim.esm":"RiftHoldLocation","bd7c:Skyrim.esm":"RiftHoldLocation","bd99:Skyrim.esm":"RiftHoldLocation","bdd7:Skyrim.esm":"RiftHoldLocation","bbf0:Skyrim.esm":"RiftHoldLocation","bc51:Skyrim.esm":"RiftHoldLocation","bcb2:Skyrim.esm":"RiftHoldLocation","bcb5:Skyrim.esm":"RiftHoldLocation","bcb6:Skyrim.esm":"RiftHoldLocation","bcd4:Skyrim.esm":"RiftHoldLocation","bcd5:Skyrim.esm":"RiftHoldLocation","bcda:Skyrim.esm":"RiftHoldLocation","bae9:Skyrim.esm":"EastmarchHoldLocation","baea:Skyrim.esm":"EastmarchHoldLocation","baeb:Skyrim.esm":"EastmarchHoldLocation","bb29:Skyrim.esm":"RiftHoldLocation","bb4a:Skyrim.esm":"RiftHoldLocation","bb6a:Skyrim.esm":"RiftHoldLocation","bb6b:Skyrim.esm":"RiftHoldLocation","bb8b:Skyrim.esm":"RiftHoldLocation","bb8c:Skyrim.esm":"RiftHoldLocation","bb90:Skyrim.esm":"RiftHoldLocation","bbaa:Skyrim.esm":"RiftHoldLocation","bbcb:Skyrim.esm":"RiftHoldLocation","b9dd:Skyrim.esm":"EastmarchHoldLocation","b9e3:Skyrim.esm":"EastmarchHoldLocation","ba22:Skyrim.esm":"EastmarchHoldLocation","ba23:Skyrim.esm":"EastmarchHoldLocation","ba25:Skyrim.esm":"EastmarchHoldLocation","ba45:Skyrim.esm":"EastmarchHoldLocation","ba46:Skyrim.esm":"EastmarchHoldLocation","ba66:Skyrim.esm":"EastmarchHoldLocation","ba67:Skyrim.esm":"EastmarchHoldLocation","bd2e:Skyrim.esm":"RiftHoldLocation","bd2f:Skyrim.esm":"RiftHoldLocation","bd32:Skyrim.esm":"RiftHoldLocation","bd34:Skyrim.esm":"RiftHoldLocation","bd35:Skyrim.esm":"RiftHoldLocation","bd51:Skyrim.esm":"RiftHoldLocation","bd52:Skyrim.esm":"RiftHoldLocation","bd53:Skyrim.esm":"RiftHoldLocation","bd70:Skyrim.esm":"RiftHoldLocation","bd73:Skyrim.esm":"RiftHoldLocation","bd96:Skyrim.esm":"RiftHoldLocation","bd97:Skyrim.esm":"RiftHoldLocation","bdcd:Skyrim.esm":"RiftHoldLocation","bdcf:Skyrim.esm":"RiftHoldLocation","bbeb:Skyrim.esm":"RiftHoldLocation","bc0b:Skyrim.esm":"RiftHoldLocation","bc0c:Skyrim.esm":"RiftHoldLocation","bc2c:Skyrim.esm":"RiftHoldLocation","bc2d:Skyrim.esm":"RiftHoldLocation","bc4b:Skyrim.esm":"RiftHoldLocation","bc4c:Skyrim.esm":"RiftHoldLocation","bc68:Skyrim.esm":"RiftHoldLocation","bc69:Skyrim.esm":"RiftHoldLocation","bc6c:Skyrim.esm":"RiftHoldLocation","bc6d:Skyrim.esm":"RiftHoldLocation","bc8e:Skyrim.esm":"RiftHoldLocation","bc90:Skyrim.esm":"RiftHoldLocation","bcae:Skyrim.esm":"RiftHoldLocation","bcaf:Skyrim.esm":"RiftHoldLocation","bcb0:Skyrim.esm":"RiftHoldLocation","bcd1:Skyrim.esm":"RiftHoldLocation","bade:Skyrim.esm":"EastmarchHoldLocation","bae1:Skyrim.esm":"EastmarchHoldLocation","bae2:Skyrim.esm":"EastmarchHoldLocation","bae3:Skyrim.esm":"EastmarchHoldLocation","bb43:Skyrim.esm":"RiftHoldLocation","bb66:Skyrim.esm":"RiftHoldLocation","bba9:Skyrim.esm":"RiftHoldLocation","bbca:Skyrim.esm":"RiftHoldLocation","b9da:Skyrim.esm":"EastmarchHoldLocation","ba3d:Skyrim.esm":"EastmarchHoldLocation","ba3e:Skyrim.esm":"EastmarchHoldLocation","ba5d:Skyrim.esm":"EastmarchHoldLocation","ba7e:Skyrim.esm":"EastmarchHoldLocation","ba7f:Skyrim.esm":"EastmarchHoldLocation","ba9b:Skyrim.esm":"EastmarchHoldLocation","ba9c:Skyrim.esm":"EastmarchHoldLocation","ba9f:Skyrim.esm":"EastmarchHoldLocation","babc:Skyrim.esm":"EastmarchHoldLocation","babd:Skyrim.esm":"EastmarchHoldLocation","bceb:Skyrim.esm":"RiftHoldLocation","bd6f:Skyrim.esm":"RiftHoldLocation","bc88:Skyrim.esm":"RiftHoldLocation","bca9:Skyrim.esm":"RiftHoldLocation","bcca:Skyrim.esm":"RiftHoldLocation","70c1:Skyrim.esm":"ReachHoldLocation","70c2:Skyrim.esm":"ReachHoldLocation","70df:Skyrim.esm":"ReachHoldLocation","70e0:Skyrim.esm":"ReachHoldLocation","70e1:Skyrim.esm":"ReachHoldLocation","7179:Skyrim.esm":"ReachHoldLocation","717a:Skyrim.esm":"ReachHoldLocation","717b:Skyrim.esm":"ReachHoldLocation","75ab:Skyrim.esm":"ReachHoldLocation","75ac:Skyrim.esm":"ReachHoldLocation","75ad:Skyrim.esm":"ReachHoldLocation","6fc8:Skyrim.esm":"ReachHoldLocation","6fe7:Skyrim.esm":"ReachHoldLocation","7043:Skyrim.esm":"ReachHoldLocation","7062:Skyrim.esm":"ReachHoldLocation","7063:Skyrim.esm":"ReachHoldLocation","70d8:Skyrim.esm":"ReachHoldLocation","70d9:Skyrim.esm":"ReachHoldLocation","70f5:Skyrim.esm":"ReachHoldLocation","70f7:Skyrim.esm":"ReachHoldLocation","7118:Skyrim.esm":"ReachHoldLocation","7136:Skyrim.esm":"ReachHoldLocation","7137:Skyrim.esm":"ReachHoldLocation","7152:Skyrim.esm":"ReachHoldLocation","7153:Skyrim.esm":"ReachHoldLocation","7156:Skyrim.esm":"ReachHoldLocation","7158:Skyrim.esm":"ReachHoldLocation","7171:Skyrim.esm":"ReachHoldLocation","7173:Skyrim.esm":"ReachHoldLocation","7178:Skyrim.esm":"ReachHoldLocation","75a3:Skyrim.esm":"ReachHoldLocation","75a9:Skyrim.esm":"ReachHoldLocation","75aa:Skyrim.esm":"ReachHoldLocation","6fc4:Skyrim.esm":"ReachHoldLocation","6fe3:Skyrim.esm":"ReachHoldLocation","6ffe:Skyrim.esm":"ReachHoldLocation","7003:Skyrim.esm":"ReachHoldLocation","701e:Skyrim.esm":"ReachHoldLocation","701f:Skyrim.esm":"ReachHoldLocation","703d:Skyrim.esm":"ReachHoldLocation","7042:Skyrim.esm":"ReachHoldLocation","705a:Skyrim.esm":"ReachHoldLocation","7079:Skyrim.esm":"ReachHoldLocation","707a:Skyrim.esm":"ReachHoldLocation","707c:Skyrim.esm":"ReachHoldLocation","707f:Skyrim.esm":"ReachHoldLocation","7080:Skyrim.esm":"ReachHoldLocation","709f:Skyrim.esm":"ReachHoldLocation","6ec9:Skyrim.esm":"HaafingarHoldLocation","6eca:Skyrim.esm":"HaafingarHoldLocation","6ee6:Skyrim.esm":"HaafingarHoldLocation","6ee7:Skyrim.esm":"HaafingarHoldLocation","6f24:Skyrim.esm":"ReachHoldLocation","6f28:Skyrim.esm":"ReachHoldLocation","6f29:Skyrim.esm":"ReachHoldLocation","6f43:Skyrim.esm":"ReachHoldLocation","6f47:Skyrim.esm":"ReachHoldLocation","6f48:Skyrim.esm":"ReachHoldLocation","6fa4:Skyrim.esm":"ReachHoldLocation","6e0f:Skyrim.esm":"HaafingarHoldLocation","6e10:Skyrim.esm":"HaafingarHoldLocation","6e2d:Skyrim.esm":"HaafingarHoldLocation","6e2e:Skyrim.esm":"HaafingarHoldLocation","6e2f:Skyrim.esm":"HaafingarHoldLocation","6e8b:Skyrim.esm":"HaafingarHoldLocation","6e8c:Skyrim.esm":"HaafingarHoldLocation","6eaa:Skyrim.esm":"HaafingarHoldLocation","6eab:Skyrim.esm":"HaafingarHoldLocation","75ca:Skyrim.esm":"ReachHoldLocation","7628:Skyrim.esm":"ReachHoldLocation","7629:Skyrim.esm":"ReachHoldLocation","762a:Skyrim.esm":"ReachHoldLocation","7648:Skyrim.esm":"ReachHoldLocation","7649:Skyrim.esm":"ReachHoldLocation","764a:Skyrim.esm":"ReachHoldLocation","75c4:Skyrim.esm":"ReachHoldLocation","7600:Skyrim.esm":"ReachHoldLocation","7621:Skyrim.esm":"ReachHoldLocation","7623:Skyrim.esm":"ReachHoldLocation","7644:Skyrim.esm":"ReachHoldLocation","7645:Skyrim.esm":"ReachHoldLocation","765f:Skyrim.esm":"ReachHoldLocation","7660:Skyrim.esm":"ReachHoldLocation","767f:Skyrim.esm":"ReachHoldLocation","94f6:Skyrim.esm":"ReachHoldLocation","94fa:Skyrim.esm":"ReachHoldLocation","94fb:Skyrim.esm":"ReachHoldLocation","94fc:Skyrim.esm":"ReachHoldLocation","9519:Skyrim.esm":"ReachHoldLocation","951c:Skyrim.esm":"ReachHoldLocation","951d:Skyrim.esm":"ReachHoldLocation","953c:Skyrim.esm":"ReachHoldLocation","953d:Skyrim.esm":"ReachHoldLocation","953e:Skyrim.esm":"ReachHoldLocation","955a:Skyrim.esm":"ReachHoldLocation","955f:Skyrim.esm":"ReachHoldLocation","9580:Skyrim.esm":"ReachHoldLocation","9581:Skyrim.esm":"ReachHoldLocation","959f:Skyrim.esm":"ReachHoldLocation","95a2:Skyrim.esm":"ReachHoldLocation","99c2:Skyrim.esm":"ReachHoldLocation","93d3:Skyrim.esm":"ReachHoldLocation","93ee:Skyrim.esm":"HjaalmarchHoldLocation","940f:Skyrim.esm":"HjaalmarchHoldLocation","9411:Skyrim.esm":"ReachHoldLocation","9433:Skyrim.esm":"ReachHoldLocation","9434:Skyrim.esm":"ReachHoldLocation","9435:Skyrim.esm":"ReachHoldLocation","9454:Skyrim.esm":"ReachHoldLocation","9455:Skyrim.esm":"ReachHoldLocation","9456:Skyrim.esm":"ReachHoldLocation","9474:Skyrim.esm":"ReachHoldLocation","9475:Skyrim.esm":"ReachHoldLocation","9494:Skyrim.esm":"ReachHoldLocation","9495:Skyrim.esm":"ReachHoldLocation","9499:Skyrim.esm":"ReachHoldLocation","949a:Skyrim.esm":"ReachHoldLocation","92c6:Skyrim.esm":"HaafingarHoldLocation","92c7:Skyrim.esm":"HaafingarHoldLocation","92e8:Skyrim.esm":"HaafingarHoldLocation","92ea:Skyrim.esm":"HaafingarHoldLocation","92ec:Skyrim.esm":"HaafingarHoldLocation","92ed:Skyrim.esm":"HaafingarHoldLocation","9328:Skyrim.esm":"HaafingarHoldLocation","9329:Skyrim.esm":"HaafingarHoldLocation","9349:Skyrim.esm":"HaafingarHoldLocation","934a:Skyrim.esm":"HaafingarHoldLocation","938c:Skyrim.esm":"ReachHoldLocation","93ad:Skyrim.esm":"ReachHoldLocation","91c2:Skyrim.esm":"HaafingarHoldLocation","91df:Skyrim.esm":"HaafingarHoldLocation","9200:Skyrim.esm":"HaafingarHoldLocation","9206:Skyrim.esm":"HaafingarHoldLocation","9223:Skyrim.esm":"HaafingarHoldLocation","9227:Skyrim.esm":"HaafingarHoldLocation","9242:Skyrim.esm":"HaafingarHoldLocation","9243:Skyrim.esm":"HaafingarHoldLocation","9244:Skyrim.esm":"HaafingarHoldLocation","9245:Skyrim.esm":"HaafingarHoldLocation","9264:Skyrim.esm":"HaafingarHoldLocation","928a:Skyrim.esm":"HaafingarHoldLocation","92ab:Skyrim.esm":"FalkreathHoldLocation","950f:Skyrim.esm":"HjaalmarchHoldLocation","9510:Skyrim.esm":"HjaalmarchHoldLocation","9536:Skyrim.esm":"WhiterunHoldLocation","9576:Skyrim.esm":"WhiterunHoldLocation","9577:Skyrim.esm":"WhiterunHoldLocation","9596:Skyrim.esm":"WhiterunHoldLocation","9597:Skyrim.esm":"WhiterunHoldLocation","99b3:Skyrim.esm":"WhiterunHoldLocation","93ed:Skyrim.esm":"HjaalmarchHoldLocation","9407:Skyrim.esm":"HjaalmarchHoldLocation","9428:Skyrim.esm":"HjaalmarchHoldLocation","942b:Skyrim.esm":"HjaalmarchHoldLocation","944c:Skyrim.esm":"HjaalmarchHoldLocation","944d:Skyrim.esm":"HjaalmarchHoldLocation","946b:Skyrim.esm":"WhiterunHoldLocation","946d:Skyrim.esm":"HjaalmarchHoldLocation","946e:Skyrim.esm":"HjaalmarchHoldLocation","948b:Skyrim.esm":"HjaalmarchHoldLocation","94ac:Skyrim.esm":"HjaalmarchHoldLocation","92bd:Skyrim.esm":"HaafingarHoldLocation","92be:Skyrim.esm":"HaafingarHoldLocation","92bf:Skyrim.esm":"HaafingarHoldLocation","92c0:Skyrim.esm":"HaafingarHoldLocation","92c1:Skyrim.esm":"HaafingarHoldLocation","92c4:Skyrim.esm":"HaafingarHoldLocation","92e0:Skyrim.esm":"HaafingarHoldLocation","92e1:Skyrim.esm":"HaafingarHoldLocation","92e2:Skyrim.esm":"HaafingarHoldLocation","92e3:Skyrim.esm":"HaafingarHoldLocation","92e4:Skyrim.esm":"HaafingarHoldLocation","9305:Skyrim.esm":"HaafingarHoldLocation","9344:Skyrim.esm":"HjaalmarchHoldLocation","9363:Skyrim.esm":"HjaalmarchHoldLocation","91bb:Skyrim.esm":"HaafingarHoldLocation","91d8:Skyrim.esm":"HaafingarHoldLocation","91dc:Skyrim.esm":"HaafingarHoldLocation","921b:Skyrim.esm":"HaafingarHoldLocation","921c:Skyrim.esm":"HaafingarHoldLocation","921f:Skyrim.esm":"HaafingarHoldLocation","923c:Skyrim.esm":"HaafingarHoldLocation","923d:Skyrim.esm":"HaafingarHoldLocation","923f:Skyrim.esm":"HaafingarHoldLocation","9261:Skyrim.esm":"HaafingarHoldLocation","927b:Skyrim.esm":"HaafingarHoldLocation","927c:Skyrim.esm":"HaafingarHoldLocation","9281:Skyrim.esm":"HaafingarHoldLocation","929c:Skyrim.esm":"HaafingarHoldLocation","929d:Skyrim.esm":"HaafingarHoldLocation","929e:Skyrim.esm":"HaafingarHoldLocation","929f:Skyrim.esm":"HaafingarHoldLocation","92a1:Skyrim.esm":"HaafingarHoldLocation","92a2:Skyrim.esm":"HaafingarHoldLocation","92a3:Skyrim.esm":"HaafingarHoldLocation","94c8:Skyrim.esm":"WhiterunHoldLocation","94e9:Skyrim.esm":"WhiterunHoldLocation","94ea:Skyrim.esm":"WhiterunHoldLocation","950b:Skyrim.esm":"WhiterunHoldLocation","9592:Skyrim.esm":"WhiterunHoldLocation","99ae:Skyrim.esm":"WhiterunHoldLocation","99b1:Skyrim.esm":"WhiterunHoldLocation","99b2:Skyrim.esm":"WhiterunHoldLocation","93bd:Skyrim.esm":"HjaalmarchHoldLocation","93be:Skyrim.esm":"HjaalmarchHoldLocation","93bf:Skyrim.esm":"HjaalmarchHoldLocation","93c3:Skyrim.esm":"HjaalmarchHoldLocation","9467:Skyrim.esm":"HjaalmarchHoldLocation","9484:Skyrim.esm":"HjaalmarchHoldLocation","9485:Skyrim.esm":"HjaalmarchHoldLocation","9486:Skyrim.esm":"WhiterunHoldLocation","94a5:Skyrim.esm":"HjaalmarchHoldLocation","94a6:Skyrim.esm":"HjaalmarchHoldLocation","92bc:Skyrim.esm":"HaafingarHoldLocation","92d6:Skyrim.esm":"HjaalmarchHoldLocation","92d9:Skyrim.esm":"HjaalmarchHoldLocation","92da:Skyrim.esm":"HjaalmarchHoldLocation","92fa:Skyrim.esm":"HjaalmarchHoldLocation","92fb:Skyrim.esm":"HjaalmarchHoldLocation","933e:Skyrim.esm":"HjaalmarchHoldLocation","935b:Skyrim.esm":"HjaalmarchHoldLocation","937c:Skyrim.esm":"HjaalmarchHoldLocation","9380:Skyrim.esm":"HjaalmarchHoldLocation","9381:Skyrim.esm":"HjaalmarchHoldLocation","939c:Skyrim.esm":"HjaalmarchHoldLocation","939d:Skyrim.esm":"HjaalmarchHoldLocation","939e:Skyrim.esm":"HjaalmarchHoldLocation","93a1:Skyrim.esm":"HjaalmarchHoldLocation","93a2:Skyrim.esm":"HjaalmarchHoldLocation","91b0:Skyrim.esm":"HaafingarHoldLocation","91d2:Skyrim.esm":"HaafingarHoldLocation","91f3:Skyrim.esm":"HaafingarHoldLocation","9237:Skyrim.esm":"HaafingarHoldLocation","9252:Skyrim.esm":"HjaalmarchHoldLocation","9255:Skyrim.esm":"HaafingarHoldLocation","9256:Skyrim.esm":"HaafingarHoldLocation","9276:Skyrim.esm":"HaafingarHoldLocation","9277:Skyrim.esm":"HaafingarHoldLocation","9279:Skyrim.esm":"HaafingarHoldLocation","927a:Skyrim.esm":"HaafingarHoldLocation","929b:Skyrim.esm":"HaafingarHoldLocation","94e5:Skyrim.esm":"WhiterunHoldLocation","9503:Skyrim.esm":"WhiterunHoldLocation","9524:Skyrim.esm":"ReachHoldLocation","9547:Skyrim.esm":"WhiterunHoldLocation","9586:Skyrim.esm":"WhiterunHoldLocation","93b6:Skyrim.esm":"HjaalmarchHoldLocation","93b7:Skyrim.esm":"HjaalmarchHoldLocation","93bc:Skyrim.esm":"HjaalmarchHoldLocation","9418:Skyrim.esm":"PaleHoldLocation","9419:Skyrim.esm":"HjaalmarchHoldLocation","943a:Skyrim.esm":"HjaalmarchHoldLocation","943b:Skyrim.esm":"HjaalmarchHoldLocation","943c:Skyrim.esm":"HjaalmarchHoldLocation","945b:Skyrim.esm":"HjaalmarchHoldLocation","945d:Skyrim.esm":"HjaalmarchHoldLocation","945e:Skyrim.esm":"HjaalmarchHoldLocation","945f:Skyrim.esm":"HjaalmarchHoldLocation","92ad:Skyrim.esm":"PaleHoldLocation","92ae:Skyrim.esm":"PaleHoldLocation","92d3:Skyrim.esm":"HjaalmarchHoldLocation","92f1:Skyrim.esm":"HjaalmarchHoldLocation","92f4:Skyrim.esm":"HjaalmarchHoldLocation","9312:Skyrim.esm":"HjaalmarchHoldLocation","9313:Skyrim.esm":"HjaalmarchHoldLocation","9335:Skyrim.esm":"HjaalmarchHoldLocation","9336:Skyrim.esm":"HjaalmarchHoldLocation","9356:Skyrim.esm":"HjaalmarchHoldLocation","9359:Skyrim.esm":"HjaalmarchHoldLocation","9377:Skyrim.esm":"HjaalmarchHoldLocation","9395:Skyrim.esm":"HjaalmarchHoldLocation","91e7:Skyrim.esm":"PaleHoldLocation","9208:Skyrim.esm":"PaleHoldLocation","9251:Skyrim.esm":"HjaalmarchHoldLocation","926b:Skyrim.esm":"PaleHoldLocation","926c:Skyrim.esm":"PaleHoldLocation","926f:Skyrim.esm":"PaleHoldLocation","928c:Skyrim.esm":"PaleHoldLocation","928d:Skyrim.esm":"PaleHoldLocation","3d7d:Skyrim.esm":"HaafingarHoldLocation","9ae4:Skyrim.esm":"ReachHoldLocation","99fd:Skyrim.esm":"WhiterunHoldLocation","9a00:Skyrim.esm":"ReachHoldLocation","9a01:Skyrim.esm":"ReachHoldLocation","9a1e:Skyrim.esm":"WhiterunHoldLocation","9a21:Skyrim.esm":"ReachHoldLocation","9a22:Skyrim.esm":"ReachHoldLocation","9a64:Skyrim.esm":"ReachHoldLocation","9aa2:Skyrim.esm":"ReachHoldLocation","9aa9:Skyrim.esm":"ReachHoldLocation","9ac7:Skyrim.esm":"ReachHoldLocation","9be4:Skyrim.esm":"FalkreathHoldLocation","9be5:Skyrim.esm":"FalkreathHoldLocation","9c48:Skyrim.esm":"FalkreathHoldLocation","9ae0:Skyrim.esm":"ReachHoldLocation","9ae1:Skyrim.esm":"ReachHoldLocation","9ae2:Skyrim.esm":"ReachHoldLocation","9aff:Skyrim.esm":"FalkreathHoldLocation","9b00:Skyrim.esm":"FalkreathHoldLocation","9b01:Skyrim.esm":"ReachHoldLocation","9b02:Skyrim.esm":"ReachHoldLocation","9b03:Skyrim.esm":"ReachHoldLocation","9b20:Skyrim.esm":"FalkreathHoldLocation","9b21:Skyrim.esm":"FalkreathHoldLocation","9b24:Skyrim.esm":"ReachHoldLocation","9b60:Skyrim.esm":"FalkreathHoldLocation","9b81:Skyrim.esm":"FalkreathHoldLocation","9b84:Skyrim.esm":"FalkreathHoldLocation","9bc3:Skyrim.esm":"FalkreathHoldLocation","9bc4:Skyrim.esm":"FalkreathHoldLocation","99fb:Skyrim.esm":"WhiterunHoldLocation","99fc:Skyrim.esm":"WhiterunHoldLocation","9a59:Skyrim.esm":"ReachHoldLocation","9a79:Skyrim.esm":"ReachHoldLocation","9a7a:Skyrim.esm":"ReachHoldLocation","9a7b:Skyrim.esm":"ReachHoldLocation","9a9a:Skyrim.esm":"ReachHoldLocation","9a9b:Skyrim.esm":"ReachHoldLocation","9a9c:Skyrim.esm":"ReachHoldLocation","9ac0:Skyrim.esm":"ReachHoldLocation","9ac1:Skyrim.esm":"ReachHoldLocation","9be0:Skyrim.esm":"FalkreathHoldLocation","9bfd:Skyrim.esm":"FalkreathHoldLocation","9c41:Skyrim.esm":"FalkreathHoldLocation","9c60:Skyrim.esm":"FalkreathHoldLocation","9c62:Skyrim.esm":"FalkreathHoldLocation","9c65:Skyrim.esm":"FalkreathHoldLocation","9c81:Skyrim.esm":"FalkreathHoldLocation","9c86:Skyrim.esm":"FalkreathHoldLocation","9ca2:Skyrim.esm":"FalkreathHoldLocation","9ca3:Skyrim.esm":"FalkreathHoldLocation","9cc5:Skyrim.esm":"FalkreathHoldLocation","9ad5:Skyrim.esm":"FalkreathHoldLocation","9ad8:Skyrim.esm":"FalkreathHoldLocation","9ad9:Skyrim.esm":"FalkreathHoldLocation","9af6:Skyrim.esm":"FalkreathHoldLocation","9afb:Skyrim.esm":"FalkreathHoldLocation","9b5d:Skyrim.esm":"FalkreathHoldLocation","9b5f:Skyrim.esm":"FalkreathHoldLocation","9b7e:Skyrim.esm":"FalkreathHoldLocation","9b80:Skyrim.esm":"FalkreathHoldLocation","9b9c:Skyrim.esm":"FalkreathHoldLocation","9bc0:Skyrim.esm":"FalkreathHoldLocation","9bc1:Skyrim.esm":"FalkreathHoldLocation","99d3:Skyrim.esm":"WhiterunHoldLocation","9a30:Skyrim.esm":"WhiterunHoldLocation","9a31:Skyrim.esm":"WhiterunHoldLocation","9a33:Skyrim.esm":"WhiterunHoldLocation","9a51:Skyrim.esm":"WhiterunHoldLocation","9a52:Skyrim.esm":"WhiterunHoldLocation","9ab7:Skyrim.esm":"FalkreathHoldLocation","9ab8:Skyrim.esm":"FalkreathHoldLocation","9cdc:Skyrim.esm":"FalkreathHoldLocation","9d03:Skyrim.esm":"FalkreathHoldLocation","9d1e:Skyrim.esm":"FalkreathHoldLocation","9d3f:Skyrim.esm":"FalkreathHoldLocation","9bfb:Skyrim.esm":"FalkreathHoldLocation","9bfc:Skyrim.esm":"FalkreathHoldLocation","9c18:Skyrim.esm":"FalkreathHoldLocation","9c1b:Skyrim.esm":"FalkreathHoldLocation","9c1c:Skyrim.esm":"FalkreathHoldLocation","9c3c:Skyrim.esm":"FalkreathHoldLocation","9c3d:Skyrim.esm":"FalkreathHoldLocation","9c5d:Skyrim.esm":"FalkreathHoldLocation","9c5e:Skyrim.esm":"FalkreathHoldLocation","9c5f:Skyrim.esm":"FalkreathHoldLocation","9c7d:Skyrim.esm":"FalkreathHoldLocation","9c7f:Skyrim.esm":"FalkreathHoldLocation","9c80:Skyrim.esm":"FalkreathHoldLocation","9ca1:Skyrim.esm":"FalkreathHoldLocation","9cbb:Skyrim.esm":"FalkreathHoldLocation","9ad1:Skyrim.esm":"FalkreathHoldLocation","9b0e:Skyrim.esm":"FalkreathHoldLocation","9b31:Skyrim.esm":"FalkreathHoldLocation","9b32:Skyrim.esm":"FalkreathHoldLocation","9b35:Skyrim.esm":"FalkreathHoldLocation","9b36:Skyrim.esm":"FalkreathHoldLocation","9b52:Skyrim.esm":"FalkreathHoldLocation","9b53:Skyrim.esm":"FalkreathHoldLocation","9b54:Skyrim.esm":"FalkreathHoldLocation","9b56:Skyrim.esm":"FalkreathHoldLocation","9b57:Skyrim.esm":"FalkreathHoldLocation","9b78:Skyrim.esm":"FalkreathHoldLocation","99e7:Skyrim.esm":"WhiterunHoldLocation","99e8:Skyrim.esm":"WhiterunHoldLocation","99e9:Skyrim.esm":"WhiterunHoldLocation","9a07:Skyrim.esm":"WhiterunHoldLocation","9a08:Skyrim.esm":"WhiterunHoldLocation","9a09:Skyrim.esm":"WhiterunHoldLocation","9a4a:Skyrim.esm":"WhiterunHoldLocation","9a8a:Skyrim.esm":"FalkreathHoldLocation","9a90:Skyrim.esm":"WhiterunHoldLocation","9a91:Skyrim.esm":"WhiterunHoldLocation","9aac:Skyrim.esm":"FalkreathHoldLocation","3837d:Skyrim.esm":"EastmarchHoldLocation","1b4d5:Skyrim.esm":"WhiterunHoldLocation","1b4d6:Skyrim.esm":"WhiterunHoldLocation","1b4f1:Skyrim.esm":"WhiterunHoldLocation","1b512:Skyrim.esm":"WhiterunHoldLocation","1b4d7:Skyrim.esm":"WhiterunHoldLocation","1b507:Skyrim.esm":"WhiterunHoldLocation","1b4ce:Skyrim.esm":"WhiterunHoldLocation","1b500:Skyrim.esm":"WhiterunHoldLocation","1ce87:Skyrim.esm":"HjaalmarchHoldLocation","1ceb1:Skyrim.esm":"HjaalmarchHoldLocation","1cec4:Skyrim.esm":"HjaalmarchHoldLocation","1cf11:Skyrim.esm":"HjaalmarchHoldLocation","20a34:Skyrim.esm":"FalkreathHoldLocation","20a40:Skyrim.esm":"FalkreathHoldLocation","20a3c:Skyrim.esm":"FalkreathHoldLocation","20a37:Skyrim.esm":"FalkreathHoldLocation","20a38:Skyrim.esm":"FalkreathHoldLocation","20a3d:Skyrim.esm":"FalkreathHoldLocation","20a3e:Skyrim.esm":"FalkreathHoldLocation","20a39:Skyrim.esm":"FalkreathHoldLocation","20a3f:Skyrim.esm":"FalkreathHoldLocation","204ee:Skyrim.esm":"RiftHoldLocation","29ae6:Skyrim.esm":"ReachHoldLocation","29af2:Skyrim.esm":"ReachHoldLocation","98296:Skyrim.esm":"ReachHoldLocation","9829b:Skyrim.esm":"ReachHoldLocation","9829c:Skyrim.esm":"ReachHoldLocation","9829d:Skyrim.esm":"ReachHoldLocation","9829f:Skyrim.esm":"ReachHoldLocation","982a0:Skyrim.esm":"ReachHoldLocation","982a1:Skyrim.esm":"ReachHoldLocation","3a9e0:Skyrim.esm":"EastmarchHoldLocation","3a9ec:Skyrim.esm":"EastmarchHoldLocation","4f83a:Skyrim.esm":"HaafingarHoldLocation","4f83d:Skyrim.esm":"HaafingarHoldLocation","4f841:Skyrim.esm":"HaafingarHoldLocation","4fc0b:Skyrim.esm":"HaafingarHoldLocation","4fc0d:Skyrim.esm":"HaafingarHoldLocation","108ea7:Skyrim.esm":"HaafingarHoldLocation","108ea8:Skyrim.esm":"HaafingarHoldLocation","108ea6:Skyrim.esm":"HaafingarHoldLocation","c97ee:Skyrim.esm":"PaleHoldLocation","c97f2:Skyrim.esm":"PaleHoldLocation","c97fb:Skyrim.esm":"PaleHoldLocation","c97ef:Skyrim.esm":"PaleHoldLocation","c97f0:Skyrim.esm":"PaleHoldLocation","c97f3:Skyrim.esm":"PaleHoldLocation","c97f4:Skyrim.esm":"PaleHoldLocation","c97f6:Skyrim.esm":"PaleHoldLocation","c97f7:Skyrim.esm":"PaleHoldLocation","c97f8:Skyrim.esm":"PaleHoldLocation","17b6a:Dragonborn.esm":"DLC2SolstheimLocation","17728:Dragonborn.esm":"DLC2SolstheimLocation","142ee:Dragonborn.esm":"DLC2SolstheimLocation","18682:Dragonborn.esm":"DLC2SolstheimLocation","142f8:Dragonborn.esm":"DLC2SolstheimLocation","24cad:Dragonborn.esm":"DLC2SolstheimLocation","3377b:Dragonborn.esm":"DLC2SolstheimLocation","1be37:Dragonborn.esm":"DLC2SolstheimLocation","17729:Dragonborn.esm":"DLC2SolstheimLocation","24d9d:Dragonborn.esm":"DLC2SolstheimLocation","142ef:Dragonborn.esm":"DLC2SolstheimLocation","142f9:Dragonborn.esm":"DLC2SolstheimLocation","1e8cc:Dragonborn.esm":"DLC2SolstheimLocation","1772a:Dragonborn.esm":"DLC2SolstheimLocation","34fd2:Dragonborn.esm":"DLC2SolstheimLocation","3929e:Dragonborn.esm":"DLC2SolstheimLocation","142f0:Dragonborn.esm":"DLC2SolstheimLocation","142fa:Dragonborn.esm":"DLC2SolstheimLocation","17ebe:Dragonborn.esm":"DLC2SolstheimLocation","35a22:Dragonborn.esm":"DLC2SolstheimLocation","18f45:Dragonborn.esm":"DLC2SolstheimLocation","142f1:Dragonborn.esm":"DLC2SolstheimLocation","142fb:Dragonborn.esm":"DLC2SolstheimLocation","17ebf:Dragonborn.esm":"DLC2SolstheimLocation","18f46:Dragonborn.esm":"DLC2SolstheimLocation","18276:Dragonborn.esm":"DLC2SolstheimLocation","173b2:Dragonborn.esm":"DLC2SolstheimLocation","142fc:Dragonborn.esm":"DLC2SolstheimLocation","17ec0:Dragonborn.esm":"DLC2SolstheimLocation","21074:Dragonborn.esm":"DLC2SolstheimLocation","18f47:Dragonborn.esm":"DLC2SolstheimLocation","1dd03:Dragonborn.esm":"DLC2SolstheimLocation","17787:Dragonborn.esm":"DLC2SolstheimLocation","18277:Dragonborn.esm":"DLC2SolstheimLocation","173b3:Dragonborn.esm":"DLC2SolstheimLocation","29eeb:Dragonborn.esm":"DLC2SolstheimLocation","17ec1:Dragonborn.esm":"DLC2SolstheimLocation","18f48:Dragonborn.esm":"DLC2SolstheimLocation","1c080:Dragonborn.esm":"DLC2SolstheimLocation","1dd04:Dragonborn.esm":"DLC2SolstheimLocation","1ee98:Dragonborn.esm":"DLC2SolstheimLocation","1a7a8:Dragonborn.esm":"DLC2SolstheimLocation","1d502:Dragonborn.esm":"DLC2SolstheimLocation","19ad8:Dragonborn.esm":"DLC2SolstheimLocation","17ec2:Dragonborn.esm":"DLC2SolstheimLocation","1844f:Dragonborn.esm":"DLC2SolstheimLocation","18f49:Dragonborn.esm":"DLC2SolstheimLocation","1da5d:Dragonborn.esm":"DLC2SolstheimLocation","16feb:Dragonborn.esm":"DLC2SolstheimLocation","17ec3:Dragonborn.esm":"DLC2SolstheimLocation","19cd7:Dragonborn.esm":"DLC2SolstheimLocation","3c7f5:Dragonborn.esm":"DLC2SolstheimLocation","18f4a:Dragonborn.esm":"DLC2SolstheimLocation","36798:Dragonborn.esm":"DLC2SolstheimLocation","39eac:Dragonborn.esm":"DLC2SolstheimLocation","142e2:Dragonborn.esm":"DLC2SolstheimLocation","17a00:Dragonborn.esm":"DLC2SolstheimLocation","184f0:Dragonborn.esm":"DLC2SolstheimLocation","142f6:Dragonborn.esm":"DLC2SolstheimLocation","17ec4:Dragonborn.esm":"DLC2SolstheimLocation","18f4b:Dragonborn.esm":"DLC2SolstheimLocation","1bbfb:Dragonborn.esm":"DLC2SolstheimLocation","142ed:Dragonborn.esm":"DLC2SolstheimLocation","142f7:Dragonborn.esm":"DLC2SolstheimLocation","26e93:Dragonborn.esm":"DLC2SolstheimLocation","eef7:Dragonborn.esm":"DLC2SolstheimLocation","eef8:Dragonborn.esm":"DLC2SolstheimLocation","eef9:Dragonborn.esm":"DLC2SolstheimLocation","ef1a:Dragonborn.esm":"DLC2SolstheimLocation","edef:Dragonborn.esm":"DLC2SolstheimLocation","edf1:Dragonborn.esm":"DLC2SolstheimLocation","edf2:Dragonborn.esm":"DLC2SolstheimLocation","ee32:Dragonborn.esm":"DLC2SolstheimLocation","ee74:Dragonborn.esm":"DLC2SolstheimLocation","eeb5:Dragonborn.esm":"DLC2SolstheimLocation","eeb6:Dragonborn.esm":"DLC2SolstheimLocation","eeb8:Dragonborn.esm":"DLC2SolstheimLocation","eed6:Dragonborn.esm":"DLC2SolstheimLocation","eed7:Dragonborn.esm":"DLC2SolstheimLocation","eed8:Dragonborn.esm":"DLC2SolstheimLocation","ed08:Dragonborn.esm":"DLC2SolstheimLocation","ed09:Dragonborn.esm":"DLC2SolstheimLocation","ed0a:Dragonborn.esm":"DLC2SolstheimLocation","ed29:Dragonborn.esm":"DLC2SolstheimLocation","ed4d:Dragonborn.esm":"DLC2SolstheimLocation","ed6d:Dragonborn.esm":"DLC2SolstheimLocation","edce:Dragonborn.esm":"DLC2SolstheimLocation","edd0:Dragonborn.esm":"DLC2SolstheimLocation","eef6:Dragonborn.esm":"DLC2SolstheimLocation","ef12:Dragonborn.esm":"DLC2SolstheimLocation","ef13:Dragonborn.esm":"DLC2SolstheimLocation","ef16:Dragonborn.esm":"DLC2SolstheimLocation","ef17:Dragonborn.esm":"DLC2SolstheimLocation","ef33:Dragonborn.esm":"DLC2SolstheimLocation","ef34:Dragonborn.esm":"DLC2SolstheimLocation","ef38:Dragonborn.esm":"DLC2SolstheimLocation","ef57:Dragonborn.esm":"DLC2SolstheimLocation","ef79:Dragonborn.esm":"DLC2SolstheimLocation","ef9a:Dragonborn.esm":"DLC2SolstheimLocation","ef9b:Dragonborn.esm":"DLC2SolstheimLocation","ede9:Dragonborn.esm":"DLC2SolstheimLocation","ee08:Dragonborn.esm":"DLC2SolstheimLocation","ee0a:Dragonborn.esm":"DLC2SolstheimLocation","ee0c:Dragonborn.esm":"DLC2SolstheimLocation","ee2b:Dragonborn.esm":"DLC2SolstheimLocation","ee2e:Dragonborn.esm":"DLC2SolstheimLocation","ee30:Dragonborn.esm":"DLC2SolstheimLocation","ee4c:Dragonborn.esm":"DLC2SolstheimLocation","ee51:Dragonborn.esm":"DLC2SolstheimLocation","ee8d:Dragonborn.esm":"DLC2SolstheimLocation","ee91:Dragonborn.esm":"DLC2SolstheimLocation","eeb0:Dragonborn.esm":"DLC2SolstheimLocation","eeb4:Dragonborn.esm":"DLC2SolstheimLocation","eed1:Dragonborn.esm":"DLC2SolstheimLocation","ed04:Dragonborn.esm":"DLC2SolstheimLocation","ed07:Dragonborn.esm":"DLC2SolstheimLocation","ed26:Dragonborn.esm":"DLC2SolstheimLocation","ed27:Dragonborn.esm":"DLC2SolstheimLocation","ed28:Dragonborn.esm":"DLC2SolstheimLocation","ed46:Dragonborn.esm":"DLC2SolstheimLocation","ed47:Dragonborn.esm":"DLC2SolstheimLocation","ed65:Dragonborn.esm":"DLC2SolstheimLocation","ed67:Dragonborn.esm":"DLC2SolstheimLocation","ed84:Dragonborn.esm":"DLC2SolstheimLocation","ed86:Dragonborn.esm":"DLC2SolstheimLocation","ed89:Dragonborn.esm":"DLC2SolstheimLocation","ed8b:Dragonborn.esm":"DLC2SolstheimLocation","eda8:Dragonborn.esm":"DLC2SolstheimLocation","edaa:Dragonborn.esm":"DLC2SolstheimLocation","edc9:Dragonborn.esm":"DLC2SolstheimLocation","edcb:Dragonborn.esm":"DLC2SolstheimLocation","ef0d:Dragonborn.esm":"DLC2SolstheimLocation","ef2e:Dragonborn.esm":"DLC2SolstheimLocation","ee04:Dragonborn.esm":"DLC2SolstheimLocation","ee07:Dragonborn.esm":"DLC2SolstheimLocation","ee28:Dragonborn.esm":"DLC2SolstheimLocation","ee48:Dragonborn.esm":"DLC2SolstheimLocation","ee86:Dragonborn.esm":"DLC2SolstheimLocation","ee87:Dragonborn.esm":"DLC2SolstheimLocation","ee88:Dragonborn.esm":"DLC2SolstheimLocation","ee8b:Dragonborn.esm":"DLC2SolstheimLocation","eea7:Dragonborn.esm":"DLC2SolstheimLocation","eea8:Dragonborn.esm":"DLC2SolstheimLocation","eeac:Dragonborn.esm":"DLC2SolstheimLocation","eecc:Dragonborn.esm":"DLC2SolstheimLocation","ed3f:Dragonborn.esm":"DLC2SolstheimLocation","ed40:Dragonborn.esm":"DLC2SolstheimLocation","ed41:Dragonborn.esm":"DLC2SolstheimLocation","ed82:Dragonborn.esm":"DLC2SolstheimLocation","ed9f:Dragonborn.esm":"DLC2SolstheimLocation","eda0:Dragonborn.esm":"DLC2SolstheimLocation","eda2:Dragonborn.esm":"DLC2SolstheimLocation","eda3:Dragonborn.esm":"DLC2SolstheimLocation","edc0:Dragonborn.esm":"DLC2SolstheimLocation"},"capitals":{"PaleHoldLocation":{"town":"Dawnstar","pos":[32901.1,102643.2]},"HjaalmarchHoldLocation":{"town":"Morthal","pos":[-38741.4,63380.9]},"FalkreathHoldLocation":{"town":"Falkreath","pos":[-29417.5,-87534.1]},"WinterholdHoldLocation":{"town":"Winterhold","pos":[109719.4,101002.1]},"WhiterunHoldLocation":{"town":"Whiterun","pos":[23280,-3368]},"HaafingarHoldLocation":{"town":"Solitude","pos":[-58079.7,110488.4]},"EastmarchHoldLocation":{"town":"Windhelm","pos":[133910.9,38718.9]},"ReachHoldLocation":{"town":"Markarth","pos":[-176816,4500]},"RiftHoldLocation":{"town":"Riften","pos":[176376,-97022]}},"destinations":{"whiterun":{"temple":{"cell":"WhiterunTempleofKynareth","desc":"165a7:Skyrim.esm","pos":[1056.2,254.9,63],"rot":[0.0,0.0,-90.0],"entrancePos":[23280,-3368],"entranceWorld":"0x0001A26F"},"hallOfTheDead":{"cell":"WhiterunHalloftheDead","desc":"165aa:Skyrim.esm","pos":[-126.6,315.7,-225],"rot":[0.0,0.0,-180.0],"entrancePos":[22741.3,-1956.3],"entranceWorld":"0x0001A26F"}},"solitude":{"temple":{"cell":"SolitudeTempleoftheDivines","desc":"16a02:Skyrim.esm","pos":[2769.2,921.3,288],"rot":[0.0,0.0,-90.0],"entrancePos":[-58079.7,110488.4],"entranceWorld":"0x00037EDF"},"hallOfTheDead":{"cell":"SolitudeHalloftheDead","desc":"16a03:Skyrim.esm","pos":[-448,-976,8],"rot":[0.0,0.0,90.0],"entrancePos":[-57810.1,105218.8],"entranceWorld":"0x00037EDF"}},"windhelm":{"temple":{"cell":"WindhelmTempleofTalos","desc":"16785:Skyrim.esm","pos":[-1,-1510,149.8],"rot":[0.0,0.0,-180.0],"entrancePos":[133910.9,38718.9],"entranceWorld":"0x0001691D"},"hallOfTheDead":{"cell":"WindhelmHalloftheDead","desc":"16786:Skyrim.esm","pos":[-405.6,-1536.1,213.8],"rot":[0.0,0.0,90.0],"entrancePos":[131511.9,38458.9],"entranceWorld":"0x0001691D"}},"markarth":{"temple":{"cell":"MarkarthTempleofDibella","desc":"16df3:Skyrim.esm","pos":[-1872,-1456,64],"rot":[0.0,0.0,0.0],"entrancePos":[-176816,4500],"entranceWorld":"0x00016D71"},"hallOfTheDead":{"cell":"MarkarthHalloftheDead","desc":"23fd4:Skyrim.esm","pos":[696.7,3424.3,352],"rot":[0.0,0.0,90.0],"entrancePos":[-177776.5,1580.8],"entranceWorld":"0x00016D71"}},"riften":{"temple":{"cell":"RiftenTempleofMara","desc":"16bd7:Skyrim.esm","pos":[-1408,-384,68],"rot":[0.0,0.0,0.0],"entrancePos":[176376,-97022],"entranceWorld":"0x00016BB4"}},"ravenrock":{"temple":{"cell":"DLC2RRTemple","desc":"17ec3:Dragonborn.esm","pos":[1.4,-542.8,0],"rot":[0.0,0.0,-1.28],"entrancePos":[32848.4,35142],"entranceWorld":"0x02000800"}}},"worldspaces":["104217:Skyrim.esm","1691d:Dragonborn.esm","1691d:Skyrim.esm","16bb4:Skyrim.esm","16d71:Skyrim.esm","1a26f:Skyrim.esm","1b44a:Dragonborn.esm","1b44a:Skyrim.esm","1c0b2:Dragonborn.esm","1cdd3:Skyrim.esm","1cdd9:Skyrim.esm","1e49d:Skyrim.esm","1ee62:Skyrim.esm","1fae2:Skyrim.esm","204c7:Skyrim.esm","20bfe:Skyrim.esm","20dcb:Skyrim.esm","21edb:Skyrim.esm","243de:Skyrim.esm","278dd:Skyrim.esm","29ab7:Skyrim.esm","2a9d8:Skyrim.esm","2b101:Skyrim.esm","2c965:Skyrim.esm","2ee41:Skyrim.esm","34240:Skyrim.esm","35699:Skyrim.esm","37edf:Skyrim.esm","3a9d6:Skyrim.esm","3c:Dragonborn.esm","3c:Skyrim.esm","419e1:Skyrim.esm","46033:Skyrim.esm","4f838:Skyrim.esm","50015:Skyrim.esm","69857:Skyrim.esm","6ed38:Skyrim.esm","800:Dragonborn.esm","94b35:Skyrim.esm","c350d:Skyrim.esm","c97eb:Skyrim.esm","d45f0:Skyrim.esm"],"solstheim":"2000800"};
const STATIONS = {"saltQuarry":"dde4ef:Thornswood-Content.esp","charcoalKiln":"1547e:Thornswood-Content.esp","beehive":"dbf8b3:Thornswood-Content.esp"};
const MANUALS = {"b276:Thornswood-Content.esp":{"track":"mining","tier":1},"b277:Thornswood-Content.esp":{"track":"mining","tier":2},"b278:Thornswood-Content.esp":{"track":"mining","tier":3},"b279:Thornswood-Content.esp":{"track":"mining","tier":4},"b27b:Thornswood-Content.esp":{"track":"smithing","tier":1},"b27a:Thornswood-Content.esp":{"track":"smithing","tier":2},"b27c:Thornswood-Content.esp":{"track":"smithing","tier":3},"b27d:Thornswood-Content.esp":{"track":"smithing","tier":4},"15489:Thornswood-Content.esp":{"track":"woodcutter","tier":1},"1548a:Thornswood-Content.esp":{"track":"woodcutter","tier":2},"1548b:Thornswood-Content.esp":{"track":"woodcutter","tier":3},"1548c:Thornswood-Content.esp":{"track":"woodcutter","tier":4},"47f6c:Thornswood-Content.esp":{"track":"alchemy","tier":2},"47f6d:Thornswood-Content.esp":{"track":"alchemy","tier":3},"47f6e:Thornswood-Content.esp":{"track":"alchemy","tier":4},"e80001:Thornswood-Content.esp":{"track":"alchemy","tier":1}};
const ITEMS = {"saltPile":"34cdf:Skyrim.esm","fireSalts":"3ad5e:Skyrim.esm","frostSalts":"3ad5f:Skyrim.esm","voidSalts":"3ad60:Skyrim.esm","firewood":"6f993:Skyrim.esm","charcoal":"33760:Skyrim.esm","charcoalT1":"15481:Thornswood-Content.esp","charcoalT2":"15482:Thornswood-Content.esp","charcoalT3":"15484:Thornswood-Content.esp","charcoalT4":"15485:Thornswood-Content.esp"};

const PREFER_SLOT = 'temple';
const FALLBACK_DESTINATION = 'whiterun';

const WORLDSPACES = new Set(DATA.worldspaces);

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

/*
  Thornswood's own lines, in a file of their own.

  Of 6,617 lines in one day's server.log, 951 were "Script not found in the
  script storage", 785 were "GetBaseActorValues Negative Magicka/Health/
  Stamina" for eight NPC base forms, and 3,412 were "Skipping non-Sweet
  scripts". That is 78 percent of the log, none of it ours and none of it
  actionable, and every real finding had to be dug out from under it.

  So every line this file writes goes to the console as before, and also to
  thornswood.log, which holds nothing else. Nothing is filtered out of
  server.log: the engine's noise is still there for anybody who wants it, it
  is just no longer the only place our own lines live.

  Beside server.log in the server's own folder, deliberately NOT under data.
  The resources server hands out anything under data over plain HTTP to
  anybody who asks, which is right for online.json and the plugin files and
  wrong for a log of who was standing where.

  Opened lazily and given up on for good the first time a write fails, because
  a log that throws once a tick is worse than no log.
*/
let logFile = null;
let logBroken = false;

function logPath() {
  if (logFile !== null || logBroken) { return logFile; }
  // The working directory is the server's own folder: it is where
  // server-settings.json is read from and where server.log is written.
  logFile = 'thornswood.log';
  return logFile;
}

function stamp() {
  const d = new Date();
  const two = (n) => (n < 10 ? '0' + n : String(n));
  return d.getFullYear() + '-' + two(d.getMonth() + 1) + '-' + two(d.getDate()) +
         ' ' + two(d.getHours()) + ':' + two(d.getMinutes()) + ':' + two(d.getSeconds());
}

function log() {
  const args = Array.prototype.slice.call(arguments);
  const line = '[thornswood] ' + args.join(' ');
  console.log(line);
  if (logBroken) { return; }
  const where = logPath();
  if (!where) { return; }
  try {
    require('fs').appendFileSync(where, stamp() + ' ' + line + '\n');
  } catch (e) {
    // Once. A log that throws every tick is worse than no log.
    logBroken = true;
    console.log('[thornswood] could not write thornswood.log, carrying on ' +
                'with the console only: ' + e);
  }
}

/*
  Which voice service this server talks to.

  It used to be the number 7778 written out in five places, which was fine
  while there was one server and became wrong the day there were two: the dev
  server shipped the same file, so it pushed its positions over the live ones
  and its GET /commands and GET /choices drained the live queues. A live
  person's slash command could be collected and run by the dev server, and
  their character creation choice could be eaten before the live server asked
  for it.

  It stays out of the client's reach. The comment on the voice feed below says
  nobody can move their own voice by editing a file and that is still true:
  this is server-settings.json in the server's own folder on the VPS, which
  only whoever runs the server can write, not anything a person has on their
  machine.

  Read once and kept. The file does not change under a running server, and a
  readFileSync five times a second for a number that cannot move is a waste.
*/
let voicePortCached = 0;
function voicePort() {
  if (voicePortCached) { return voicePortCached; }
  let n = 0;
  try {
    n = Number(JSON.parse(require('fs').readFileSync('server-settings.json', 'utf8')).thornswoodVoicePort) || 0;
  } catch (e) {
    n = 0;
  }
  // Anything absent or nonsensical falls back to the live port, which is what
  // every deployment did before this existed.
  voicePortCached = (n > 0 && n < 65536) ? n : 7778;
  if (voicePortCached !== 7778) {
    log('voice service port is ' + voicePortCached + ', from server-settings.json');
  }
  return voicePortCached;
}

/** Run fn, swallow and report anything it throws. Handlers must never escape. */
function guard(name, fn) {
  return function () {
    try {
      return fn.apply(null, arguments);
    } catch (e) {
      console.error('[thornswood] ' + name + ' threw: ' + (e && e.stack ? e.stack : e));
      return undefined;
    }
  };
}

/** Runtime form id for a descriptor, or 0 if the plugin is not loaded. */
function idOf(descriptor) {
  try {
    return mp.getIdFromDesc(descriptor);
  } catch (e) {
    return 0;
  }
}

/**
 * Try to put a line on somebody's screen. Debug.Notification is implemented on
 * the server, but it finds its target actor through the Papyrus stack, which is
 * empty when the call starts here rather than in a game event. So this may well
 * do nothing, and nothing is allowed to depend on it: the log line below is the
 * one that is guaranteed.
 */
function notify(actorId, text) {
  log('say', actorId.toString(16), text);
  try {
    mp.callPapyrusFunction('global', 'Debug', 'Notification', null, [text]);
  } catch (e) {
    // no stack actor, or the class is not registered. expected; ignore.
  }
}

/**
 * A line in somebody's chat.
 *
 * notify() above goes through Debug.Notification, which resolves its target
 * through the Papyrus stack and therefore does nothing when the call starts
 * here. This is the one that works: the voice service is holding everybody's
 * chat socket already, so the line is posted to it over loopback and it puts
 * it on the right screen.
 */
function say(actorId, text) {
  var pid = 0;
  try { pid = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { return; }
  if (!pid) { return; }
  var http;
  try { http = require('http'); } catch (e) { return; }
  var body = JSON.stringify({ profileId: pid, text: text });
  var req = http.request({
    host: '127.0.0.1', port: voicePort(), path: '/say', method: 'POST', timeout: 2000,
    headers: { 'content-type': 'application/json',
               'content-length': Buffer.byteLength(body) }
  }, function () { });
  req.on('error', function () { });
  req.on('timeout', function () { req.destroy(); });
  req.end(body);
}

function dist2(ax, ay, bx, by) {
  const dx = ax - bx;
  const dy = ay - by;
  return dx * dx + dy * dy;
}

// ---------------------------------------------------------------------------
// respawn resolution
//
// Port of respawnResolver.ts. Same five branches, same order. See
// respawn-holds.json for where the numbers come from; never hand-edit them.
// ---------------------------------------------------------------------------

function holdOfCell(cellDesc) {
  const h = DATA.cellToHold[cellDesc];
  return h || null;
}

function capitalPos(hold) {
  const c = DATA.capitals[hold];
  return c ? { x: c.pos[0], y: c.pos[1] } : null;
}

function nearestCapital(pos) {
  let best = null;
  let bestD = Infinity;
  for (const hold in DATA.capitals) {
    const c = DATA.capitals[hold];
    const d = dist2(c.pos[0], c.pos[1], pos.x, pos.y);
    if (d < bestD) { bestD = d; best = hold; }
  }
  return best;
}

/**
 * Nearest single consecrated entrance, weighing every temple and every Hall of
 * the Dead separately rather than picking a city first. Solstheim is excluded:
 * its coordinates are not in Tamriel's frame, so a distance to it is noise.
 */
function nearestEntrance(pos) {
  let best = null;
  let bestD = Infinity;
  for (const key in DATA.destinations) {
    const d = DATA.destinations[key];
    for (const slot in d) {
      const s = d[slot];
      if (!s.entrancePos) continue;
      if (s.entranceWorld && parseInt(s.entranceWorld, 16) === 0x02000800) continue;
      const dd = dist2(s.entrancePos[0], s.entrancePos[1], pos.x, pos.y);
      if (dd < bestD) { bestD = dd; best = { destination: key, slot: slot }; }
    }
  }
  return best;
}

/**
 * `via` is how the hold was decided, `reason` is which destination branch fired.
 * Keep both: "Hjaalmarch, found from the cell, then borrowed Solitude's hall"
 * is a different story from "Hjaalmarch, guessed from coordinates". The first
 * time someone dies in Morthal and wakes somewhere surprising, this is the line
 * you will read.
 */
function arrive(dest, hold, reason, slotOverride, via) {
  const d = DATA.destinations[dest];
  if (!d) return null;
  let slot = slotOverride;
  if (!slot) slot = d[PREFER_SLOT] ? PREFER_SLOT : Object.keys(d)[0];
  const s = d[slot];
  if (!s) return null;
  return {
    destination: dest,
    slot: slot,
    cell: s.cell,
    desc: s.desc,
    pos: s.pos,
    rot: s.rot,
    hold: hold,
    crimeFaction: hold && DATA.holds[hold] ? DATA.holds[hold].crimeFaction : null,
    reason: reason,
    via: via,
  };
}

/**
 * site: { desc: worldOrCellDesc string, pos: [x,y,z] }
 */
function resolveArrival(site) {
  // 1. Solstheim, by worldspace. Must never reach a distance comparison.
  //
  // Compared whole, not by the low bits. DATA.solstheim is 2000800, which is
  // the runtime form id with the plugin's load order index on the front, and
  // "low" is only the part before the colon in the descriptor, which for
  // Solstheim is 800. Those two are never equal, so this branch had never
  // fired once: an outdoor death anywhere on Solstheim fell through to the
  // distance comparison below and respawned in Whiterun's temple, which is on
  // another land mass.
  if (site.desc.toLowerCase() === '800:dragonborn.esm') {
    return arrive('ravenrock', 'DLC2SolstheimLocation', 'own-ground', null, 'solstheim');
  }

  const outdoors = WORLDSPACES.has(site.desc);
  const pos = { x: site.pos[0], y: site.pos[1] };

  // 2. Died indoors: the cell names the hold outright.
  let hold = outdoors ? null : holdOfCell(site.desc);
  let via = hold ? 'cell' : null;
  let reason = 'own-ground';

  // 3. Died outdoors: nearest of the nine hold capitals. Resolving the HOLD
  //    first is what keeps the mapping in charge. Dawnstar proves it: Solitude
  //    is closer as the crow flies, but the Pale answers to Windhelm.
  if (!hold) {
    hold = nearestCapital(pos);
    via = outdoors ? 'nearest-capital' : 'unmapped-interior';
  }

  if (hold) {
    const dest = DATA.holdToDestination[hold];
    if (dest) {
      const a = arrive(dest, hold, reason, null, via);
      if (a) return a;
    }
    // 4. Hold has no consecrated ground of its own: the Pale, Hjaalmarch,
    //    Winterhold, Falkreath. Measure from a position genuinely in Tamriel's
    //    frame. An interior's coordinates are local to that cell, so measuring
    //    from them would compare against the origin and pick whatever sits
    //    nearest [0,0]; use the hold's capital instead.
    const from = outdoors ? pos : (capitalPos(hold) || pos);
    const near = nearestEntrance(from);
    if (near) {
      const a = arrive(near.destination, hold, 'borrowed', near.slot, via);
      if (a) return a;
    }
  }

  return arrive(FALLBACK_DESTINATION, hold, 'fallback', null, via);
}

// ---------------------------------------------------------------------------
// skill tracks
//
// The manuals are plain BOOK records with no script attached, so reading one is
// only a signal. The tier it grants is stored per person and gates yields.
// ---------------------------------------------------------------------------

const SKILL_PROPERTY = 'thornswoodSkills';

function ensureProperties() {
  try {
    mp.makeProperty(SKILL_PROPERTY, {
      isVisibleByOwner: true,
      isVisibleByNeighbors: false,
      updateOwner: '',
      updateNeighbor: '',
    });
    mp.makeProperty(CHARGEN_PROPERTY, {
      isVisibleByOwner: false,
      isVisibleByNeighbors: false,
      updateOwner: '',
      updateNeighbor: '',
    });
  } catch (e) {
    // already made, or made by a previous load. harmless.
  }
}

function getSkills(actorId) {
  let s = null;
  try {
    s = mp.get(actorId, SKILL_PROPERTY);
  } catch (e) {
    s = null;
  }
  if (!s || typeof s !== 'object') s = {};
  return s;
}

function setSkill(actorId, track, tier) {
  const s = getSkills(actorId);
  if ((s[track] || 0) >= tier) return false;
  s[track] = tier;
  mp.set(actorId, SKILL_PROPERTY, s);
  return true;
}

function tierOf(actorId, track) {
  const s = getSkills(actorId);
  return s[track] || 0;
}

// ---------------------------------------------------------------------------
// gathering stations
// ---------------------------------------------------------------------------

const COOLDOWN_MS = 20000;
const lastUse = new Map();   // "actorId:refrId" -> timestamp

/** Seconds still to wait, 0 if ready. Read only: a refused action must not
 *  start a cooldown, or walking up to a kiln without firewood locks you out. */
function cooldownLeft(actorId, refrId) {
  const prev = lastUse.get(actorId + ':' + refrId) || 0;
  const left = COOLDOWN_MS - (Date.now() - prev);
  return left > 0 ? Math.ceil(left / 1000) : 0;
}

/** Start the cooldown. Call this only once the yield has actually been given. */
function stampCooldown(actorId, refrId) {
  lastUse.set(actorId + ':' + refrId, Date.now());
}

function addItem(actorId, itemDesc, count) {
  const baseId = idOf(itemDesc);
  if (!baseId) return false;
  const inv = mp.get(actorId, 'inventory') || { entries: [] };
  const entries = inv.entries || [];
  let found = false;
  for (const e of entries) {
    if (e.baseId === baseId) { e.count += count; found = true; break; }
  }
  if (!found) entries.push({ baseId: baseId, count: count });
  mp.set(actorId, 'inventory', { entries: entries });
  return true;
}

function takeItem(actorId, itemDesc, count) {
  const baseId = idOf(itemDesc);
  if (!baseId) return false;
  const inv = mp.get(actorId, 'inventory') || { entries: [] };
  const entries = inv.entries || [];
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].baseId !== baseId) continue;
    if (entries[i].count < count) return false;
    entries[i].count -= count;
    if (entries[i].count <= 0) entries.splice(i, 1);
    mp.set(actorId, 'inventory', { entries: entries });
    return true;
  }
  return false;
}

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/** Salt quarry: tier gates the yield and the chance of the rarer salts. */
function mineSalt(actorId, refrId) {
  const tier = tierOf(actorId, 'mining');
  if (tier < 1) return 'You need the Novice mining manual before you can work a quarry.';

  const wait = cooldownLeft(actorId, refrId);
  if (wait > 0) return 'The seam needs ' + wait + ' more seconds to be worth striking.';

  const yielded = randInt(1, 1 + tier);
  if (!addItem(actorId, ITEMS.saltPile, yielded)) return 'The seam yields nothing you can carry.';
  stampCooldown(actorId, refrId);
  let extra = '';
  if (tier >= 3 && Math.random() < 0.12 * (tier - 2)) {
    const rare = [ITEMS.fireSalts, ITEMS.frostSalts, ITEMS.voidSalts][randInt(0, 2)];
    addItem(actorId, rare, 1);
    extra = ' Something rarer came away with it.';
  }
  return 'You work ' + yielded + ' salt from the seam.' + extra;
}

/** Charcoal kiln: firewood in, graded charcoal out. Tier sets the grade. */
function burnCharcoal(actorId, refrId) {
  const tier = tierOf(actorId, 'woodcutter');
  if (tier < 1) return 'You need the Novice woodcutting manual before you can run a kiln.';

  const wait = cooldownLeft(actorId, refrId);
  if (wait > 0) return 'The kiln is still burning. ' + wait + ' seconds.';

  const cost = 3;
  if (!takeItem(actorId, ITEMS.firewood, cost)) {
    return 'The kiln needs ' + cost + ' firewood.';
  }
  const grade = ['charcoalT1', 'charcoalT1', 'charcoalT2', 'charcoalT3', 'charcoalT4'][tier] || 'charcoalT1';
  addItem(actorId, ITEMS[grade], 1);
  stampCooldown(actorId, refrId);
  return 'The kiln yields ' + grade.replace('charcoalT', 'grade ') + ' charcoal.';
}

// ---------------------------------------------------------------------------
// character creation
//
// SkyMP has no connect event for the gamemode, and callPapyrusFunction runs on
// the server's own VM: Debug.Notification and Message.Show both resolve their
// target actor from the Papyrus stack, which is empty when the call comes from
// here. So there is no reliable way to put words on somebody's screen from this
// file, and a menu that asks a question and waits for the answer is out of the
// question entirely.
//
// What does work, on mechanisms already proven in this build: the inventory can
// be set from the server, and reading a book from the inventory comes back as
// onReadBook(actorId, baseId). The books were the interface once, and then the
// launcher was, and since 20 September the choice is made in the game, on K,
// in the panel the character block owns. This block runs the hall: the face,
// the wait, the reminder, and the trip to the town when the choices are in.
//
// The state machine is driven by a timer rather than an event, because there is
// no event. It is cheap: a property read per online person every few seconds.
// ---------------------------------------------------------------------------

/**
 * On, because Skyrim Unbound cannot do this job under SkyMP.
 *
 * Unbound ships the room, the appearance menu, the trade list and the location
 * list, and all of it works in single player. It does not survive here: the
 * client calls loadGame() when the server sends CreateActor, which reloads the
 * whole session from a synthetic save, and Unbound's start quest goes with it.
 * The room and the appearance menu run before that reload and so they work. The
 * two menus run after it and so they never appear.
 *
 * Nothing below depends on a quest surviving anything. The writs and passages
 * are inventory items, and the client plugin's message boxes sit on top of them
 * rather than replacing them.
 *
 * Set "thornswoodChargen": false in server-settings.json to switch it off.
 */
function chargenWanted() {
  try {
    const s = mp.getServerSettings();
    if (s && s.thornswoodChargen === false) {
      return false;
    }
  } catch (e) {
    // no settings object. on is the right default.
  }
  return true;
}

const CHARGEN_ENABLED = chargenWanted();

const CHARGEN_PROPERTY = 'thornswoodChargen';
/*
 * Three seconds was costing far more than three seconds.
 *
 * Creation walks a state machine one step per tick, and with the appearance
 * never arriving the path out of the hall is five of them: the state is made,
 * the face is marked, a position baseline is taken, movement is noticed against
 * that baseline, and then the wait below runs out. At three seconds a step that
 * is twelve seconds of pure tick overhead on top of every real wait.
 *
 * The work in a tick is a couple of property reads for at most five people, so
 * the rate was never about cost. One second.
 */
const CHARGEN_TICK_MS = 500;

/**
 * How long to leave a client completely alone after it turns up online.
 *
 * A joining client is mid save-load: SkyrimPlatform writes a TESMODPLATFORM
 * save, loads it, and the game rebuilds the player's facegen from the TESNPC
 * record on the way through. Anything the server does to that actor lands in
 * the middle of it. SkyMP's own SpSnippetService already treats this as
 * dangerous, wrapping ShowRaceMenu in a one second delay and switching off form
 * view updates around it.
 */
const SETTLE_MS = 10000;

/* How long to wait for an appearance before opening the race menu, and how long
 * before giving up on it entirely and moving on. Both measured from the moment
 * the creation stage opened, not from the nudge. */

const NUDGE_MS = 120000;   // two minutes; see the nudge below

/* How long somebody has to be walking about before their creation counts as
 * finished, whatever the appearance says.
 *
 * Was eight seconds. Since the appearance stopped arriving this is not a
 * fallback any more, it is the only way anybody leaves the hall, so every
 * second of it is a second spent standing in an empty room waiting for nothing.
 * Four: still far more movement than a stray camera nudge produces, and it
 * comes off the end of a wait that already has the settle in front of it.
 *
 * Down again to two. The settle in front of it is measured from when somebody
 * comes online, not from when creation ends, and creation takes far longer
 * than the settle does, so by the time this matters the settle is long spent
 * and this wait is the entire delay anybody actually feels. At a one second
 * tick, two seconds is still two separate confirmations that a person is on
 * their feet rather than nudging a camera.
 *
 * And down again to one. The check it gates is not "did the camera twitch", it
 * is "is this person's position or facing different from the last sample",
 * which a menu does not produce at all. A second confirmation was insurance
 * against a thing that was never happening, paid for by everybody standing in
 * an empty room. */
const MOVED_ENOUGH_MS = 500;

/* How far counts as having moved, between two consecutive samples.
 *
 * The test used to be any difference at all between two pose samples, with no
 * minimum, so the first report after the baseline counted: the ground snap
 * that lands somebody on the floor of the hall, and the angle normalisation
 * that follows a teleport, both move the numbers by a hair without anybody
 * touching anything. That read as "on their feet" while the race menu was
 * still up, and the teleport could fire under it.
 *
 * 32 units is about half a pace, and well under what a person turning on the
 * spot with the mouse produces. 10 degrees is a glance. */
const MOVED_UNITS = 32;
const MOVED_DEGREES = 10;
/* How often somebody standing in the hall with the panel still to fill in is
 * reminded, in chat, that K opens it. The panel opens itself the moment
 * creation begins; this is for the person who closed it, or whose page had
 * not mounted it yet when the server first asked. */
const CHOOSE_REMIND_MS = 30000;
/* Five minutes, not forty five seconds. This exists so nobody is stranded when
 * the race menu never opens, and it used to be short enough to fire on somebody
 * who was simply still making their face: it would give up and start them
 * mid-menu. Being stuck is the thing worth guarding against; taking a while
 * over a nose is not. */
const GIVEUP_MS = 300000;

const firstSeen = new Map();

// Bards already handed the ability to play, this run of the server.
const armed = new Set();   // actorId -> when it first appeared online

/* Skyrim Unbound's own character generation room, which is where a new game
 * already puts everybody, and the marker it stands them on. Falling back to the
 * configured start point is deliberate: if Unbound is ever removed from the load
 * order the flow should still run, just in a less tidy place. */
const HALL = {
  desc: '19bad4:Skyrim Unbound.esp',
  pos: [3755.7, -495.7, -207.7],
  rot: [0, 0, 180],
};

const CHARGEN = {"shift":[["1be1a:Skyrim.esm",1],["1be1b:Skyrim.esm",1]],"towns":{"e80030:Thornswood-Content.esp":{"key":"whiterun","town":"Whiterun","arrival":{"cell":"WhiterunBanneredMare","desc":"1605e:Skyrim.esm","pos":[-113.6,-810,69.3],"rot":[0,0,3.7]}},"e80031:Thornswood-Content.esp":{"key":"riften","town":"Riften","arrival":{"cell":"RiftenBeeandBarb","desc":"16bdf:Skyrim.esm","pos":[-150.2,-598.2,64],"rot":[0,0,36.3]}},"e80032:Thornswood-Content.esp":{"key":"solitude","town":"Solitude","arrival":{"cell":"SolitudeWinkingSkeever","desc":"16a0e:Skyrim.esm","pos":[-178.0,-1504.0,128.0],"rot":[0,0,90.0]}},"e80033:Thornswood-Content.esp":{"key":"windhelm","town":"Windhelm","arrival":{"cell":"WindhelmCandlehearthHall","desc":"16789:Skyrim.esm","pos":[554.3,-3766.2,64],"rot":[0,0,91.9]}},"e80034:Thornswood-Content.esp":{"key":"markarth","town":"Markarth","arrival":{"cell":"MarkarthSilverBloodInn","desc":"16dfe:Skyrim.esm","pos":[-5588.5,-1925.8,-16.0],"rot":[0,0,180.0]}},"e80035:Thornswood-Content.esp":{"key":"falkreath","town":"Falkreath","arrival":{"cell":"FalkreathDeadMansDrink","desc":"3a184:Skyrim.esm","pos":[673.1,-620.3,0.0],"rot":[0,0,180.0]}},"e80036:Thornswood-Content.esp":{"key":"morthal","town":"Morthal","arrival":{"cell":"MorthalMoorsideInn","desc":"138ce:Skyrim.esm","pos":[1970.6,-160.2,0],"rot":[0,0,270.9]}},"e80037:Thornswood-Content.esp":{"key":"dawnstar","town":"Dawnstar","arrival":{"cell":"DawnstarWindpeakInn","desc":"13a7f:Skyrim.esm","pos":[1824.3,-683.7,0.0],"rot":[0,0,180.0]}},"e80038:Thornswood-Content.esp":{"key":"winterhold","town":"Winterhold","arrival":{"cell":"WinterholdTheFrozenHearth","desc":"13814:Skyrim.esm","pos":[1791.6,7.3,0],"rot":[0,0,88]}}}};

/* Something to wear while choosing. The appearance menu hands you back with an
 * empty inventory, and choosing a life naked in a stone room is nobody's idea
 * of a first morning. */
const SHIFT = CHARGEN.shift;

/* Nine towns, each with the inn a new arrival wakes up in. The one table left
 * of the sixteen trades and their kits. The class, the profession and the
 * half are the character block's (progression, further down), and nothing is
 * handed out for any of them: decided by Patrick on 20 September, the starter
 * kits are gone, and everybody begins with the shift and what they earn. */
const PASSAGES = CHARGEN.towns;

/* The panel sends a town as its short key, 'whiterun', because that is
 * stable. The records are keyed by descriptor, which is not: it carries the
 * plugin name and moves whenever the content is rebuilt. */
const TOWN_BY_KEY = (function () {
  const m = {};
  for (const desc in PASSAGES) { m[PASSAGES[desc].key] = desc; }
  return m;
})();

/** The town list as the panel shows it: key and name, in the table's order. */
function townsForPanel() {
  const out = [];
  for (const desc in PASSAGES) {
    const t = PASSAGES[desc];
    if (t && t.arrival) { out.push({ key: t.key, name: t.town }); }
  }
  return out;
}

/**
 * The shift, worn. Given the moment the face is made, which is the moment the
 * race menu has emptied the pack, and well before the teleport: an inventory
 * write and a teleport composed in the same tick reach the client as a load
 * and a set of item changes racing each other, which is how a bard once
 * arrived in Windhelm with everything but a shirt.
 */
function giveShift(actorId) {
  let inv = { entries: [] };
  try { inv = mp.get(actorId, 'inventory') || { entries: [] }; } catch (e) { return; }
  const entries = (inv.entries || []).slice();
  let added = 0;
  for (const pair of SHIFT) {
    const baseId = idOf(pair[0]);
    if (!baseId) { continue; }
    let have = false;
    for (const e of entries) { if (e.baseId === baseId) { have = true; break; } }
    if (have) { continue; }
    entries.push({ baseId: baseId, count: pair[1], worn: true });
    added++;
  }
  if (added) { mp.set(actorId, 'inventory', { entries: entries }); }
}

/**
 * The face is made. Now the panel.
 *
 * A home town is chosen in the game, on K, checked by the character block,
 * and that one choice brings them back here to arriveAt. Class and
 * profession are chosen on the same panel, in the hall or later in the
 * world. Nothing is chosen anywhere else. The launcher used to send a
 * choice ahead through the voice service and this waited on it, which is what
 * left people standing in this room when the choice went to the wrong service
 * (the dev server asks the dev voice service; the launcher told the live one,
 * 20 September) or never came at all.
 */
function beginChoosing(actorId, state, why) {
  giveShift(actorId);
  state.stage = 'choosing';
  state.at = Date.now();
  state.remindAt = Date.now() + CHOOSE_REMIND_MS;
  setChargen(actorId, state);
  closeRaceMenu(actorId);
  const opened = openCreation(actorId);
  say(actorId, 'Welcome to Thornswood. Press K to choose where you will start. ' +
               'Your class and profession can be chosen there too, or later in the world.');
  log('chargen', actorId.toString(16), '-> choosing (' + why + ')' +
      (opened ? ', panel opened' : ', panel NOT opened'));
}

/** Ask the character block to push the panel open on this person's screen. */
function openCreation(actorId) {
  try {
    const c = globalThis.__thornswoodCharacter;
    if (c && c.beginCreation) { c.beginCreation(actorId); return true; }
  } catch (e) {
    log('chargen', actorId.toString(16), 'could not open creation:', e);
  }
  return false;
}

/**
 * The home is chosen. Off to the town.
 *
 * Called by the character block when a home is set on somebody whose stage
 * is choosing; class and profession may still be empty, and are picked in
 * the world. Returns true when they were sent.
 */
function arriveAt(actorId, townKey) {
  const state = chargenOf(actorId);
  if (!state || state.stage !== 'choosing') { return false; }
  const desc = TOWN_BY_KEY[String(townKey || '').toLowerCase()];
  const entry = desc ? PASSAGES[desc] : null;
  if (!entry || !entry.arrival) {
    log('chargen', actorId.toString(16), 'no such town', townKey, '- staying in the hall');
    return false;
  }
  const arrival = entry.arrival;
  mp.set(actorId, 'spawnPoint', {
    cellOrWorldDesc: arrival.desc, pos: arrival.pos, rot: arrival.rot,
  });
  mp.set(actorId, 'locationalData', {
    cellOrWorldDesc: arrival.desc, pos: arrival.pos, rot: arrival.rot,
  });
  state.stage = 'done';
  state.destination = entry.key;
  state.at = Date.now();
  setChargen(actorId, state);
  closeRaceMenu(actorId);
  log('chargen', actorId.toString(16), 'home =', entry.key, '(' + arrival.cell + ') -> done');
  return true;
}

/* What the character block, further down the file, needs from here. Through
 * the global rather than the scope, the same way it reaches the rules, so the
 * sections stay separable. */
globalThis.__thornswoodChargen = {
  towns: townsForPanel,
  hasTown: function (key) { return !!TOWN_BY_KEY[String(key || '').toLowerCase()]; },
  isChoosing: function (actorId) {
    const st = chargenOf(actorId);
    return !!(st && st.stage === 'choosing');
  },
  arrive: arriveAt
};

/**
 * The race menu is finished with, whatever route got us here.
 *
 * Spawn opens it, and only the appearance arriving closes it. Somebody who
 * left the hall on the movement path or on the give up path still has it set
 * open, CreateActor sends that flag on every later login, and the client dutifully
 * reopens the race menu on a character who has had a face for a week.
 */
function closeRaceMenu(actorId) {
  try {
    mp.setRaceMenuOpen(actorId, false);
  } catch (e) {
    log('chargen', actorId.toString(16), 'could not close the race menu:', e);
  }
}

/**
 * A short signature of a face, enough to tell one from another.
 *
 * "Has this character got an appearance yet" turned out to be the wrong
 * question. A client carries the last face it made and uploads it the moment it
 * connects, so somebody making their second character arrived already wearing
 * their first one's face: the server saw a finished character, skipped creation
 * and left them standing there. What matters is whether the face CHANGED since
 * the race menu was opened, which needs something to compare against.
 */
function faceMark(a) {
  if (!a || typeof a !== 'object') return '';
  try {
    return [a.raceId, a.isFemale, a.weight, a.hairColor, a.skinColor,
            a.headTextureSetId, a.name,
            (a.headpartIds || []).join('.'),
            (a.tints || []).length].join('|');
  } catch (e) {
    return '';
  }
}

function chargenOf(actorId) {
  let s = null;
  try {
    s = mp.get(actorId, CHARGEN_PROPERTY);
  } catch (e) {
    s = null;
  }
  if (!s || typeof s !== 'object') return null;
  return s;
}

function setChargen(actorId, state) {
  mp.set(actorId, CHARGEN_PROPERTY, state);
}

/** Add or remove a set of [descriptor, count] pairs in one inventory write. */
function giveItems(actorId, pairs, sign) {
  const inv = mp.get(actorId, 'inventory') || { entries: [] };
  const entries = (inv.entries || []).slice();
  for (const pair of pairs) {
    const baseId = idOf(pair[0]);
    if (!baseId) {
      log('chargen: no form for', pair[0], '- skipped');
      continue;
    }
    const want = pair[1] * sign;
    let at = -1;
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].baseId === baseId) { at = i; break; }
    }
    if (at === -1) {
      if (want > 0) entries.push({ baseId: baseId, count: want });
      continue;
    }
    entries[at].count += want;
    if (entries[at].count <= 0) entries.splice(at, 1);
  }
  mp.set(actorId, 'inventory', { entries: entries });
}

/** Put somebody in the creation hall. Once, at the moment the stage opens. */
function sendToHall(actorId) {
  const cell = idOf(HALL.desc);
  if (!cell) {
    log('chargen: the creation hall is not in this load order, staying put');
    return false;
  }
  mp.set(actorId, 'locationalData', {
    cellOrWorldDesc: HALL.desc,
    pos: HALL.pos,
    rot: HALL.rot,
  });
  return true;
}

/**
 * Open the creation stage. Deliberately does NOT touch the race menu.
 *
 * The Spawn system already calls setRaceMenuOpen, in both of its branches: on
 * the create path for a brand new character, and on the load path for one whose
 * appearance has been cleared. Calling it again from here was a second
 * ShowRaceMenu landing across the client's save load, on top of a teleport, and
 * it is the only new thing in the neighbourhood of the crash we saw. Watching
 * for the appearance to arrive is all this needs to do.
 */
function beginAppearance(actorId) {
  // The face they turned up with, so the one they make can be told from it.
  let was = '';
  try { was = faceMark(mp.get(actorId, 'appearance')); } catch (e) { was = ''; }

  const state = { stage: 'appearance', at: Date.now(), faceWas: was };

  // Moved first, asked second, and the asking happens on a later tick.
  //
  // Both used to happen here, in that order, and the order was wrong: the menu
  // opened wherever the client had finished loading, then the teleport landed
  // underneath it and dragged the whole scene through a load screen while
  // somebody was already picking a nose. Which is exactly what it looked like
  // from the chair: creation in a tavern, then the hall, then a wait, then
  // another teleport.
  //
  // startPoints already puts a new character in the hall, so the common case
  // moves nobody and the menu opens on the next pass a second or two later.
  let where = null;
  try {
    where = mp.get(actorId, 'worldOrCellDesc');
  } catch (e) {
    where = null;
  }
  if (where && where !== HALL.desc) {
    if (sendToHall(actorId)) {
      state.moved = true;
      // Long enough for the load screen the teleport just started. Asking for
      // the race menu during one is asking for nothing: showRaceMenu on a game
      // that is mid load does nothing at all and the request is gone.
      state.askAt = Date.now() + 4000;
    }
  }

  setChargen(actorId, state);
  log('chargen', actorId.toString(16), '-> appearance',
      state.moved ? '(moving to the hall, menu to follow)' : '(already in the hall)');
}

/**
 * One pass over everybody online.
 *
 * The timer owns two transitions: appearance -> choosing, because the race
 * menu closing is not an event, the appearance simply turns up on the change
 * form and this notices; and the reminder while somebody is choosing. The
 * exit from choosing is the character block's, when the last pick lands.
 */
function chargenTick() {
  if (!CHARGEN_ENABLED) {
    return;
  }
  let online;
  try {
    online = mp.get(0, 'onlinePlayers');
  } catch (e) {
    return;
  }
  if (!Array.isArray(online)) return;

  const now = Date.now();

  // Anyone who has gone offline should not keep a slot in the settle table.
  const here = new Set(online);
  for (const id of Array.from(firstSeen.keys())) {
    if (!here.has(id)) {
      firstSeen.delete(id);
    }
  }

  for (const actorId of online) {
    if (!firstSeen.has(actorId)) {
      firstSeen.set(actorId, now);

      /*
        Somebody who arrives inside a restart window is probably standing in an
        empty world, and until now nothing said so.

        A kick with no process restart behind it leaves the actor in a state
        where the reconnecting client is never sent the world. That is written
        out in full down in clearTheServer(), from 17 September: one character,
        13 reconnects, every one of them dead with no hits and no deaths and
        all the NPCs gone, and the same character fine after the 01:00 process
        restart. It was reported again on 20 September, and that session's log
        has the server says it is restarting, staying put immediately after
        ready, so the person had joined during the countdown. The site reported
        the server up with nobody online while he was standing in it.

        Joining during the window is a second way into the same state and the
        comment down there does not cover it. The server cannot refuse the
        connection from here, because there is no login hook to refuse it in,
        and it must not kick: a kick is the thing that causes this. So it says
        so, which is the difference between a broken evening and a known one.

        The same test the online writer uses, deliberately, so the two cannot
        disagree about whether a restart is happening. at covers the countdown
        and the tick after it, went covers the rest.
      */
      try {
        const r = globalThis.__thornswoodRestart;
        const inWindow = !!(r && ((r.at && now - r.at < 180000) ||
                                  (r.went && now - r.went < 180000)));
        if (inWindow) {
          log('login', actorId.toString(16),
              'arrived inside a restart window: if the world is empty this is why');
          say(actorId,
              'The server was restarting as you arrived. If nobody is about and ' +
              'the world looks empty, quit to the launcher and come back in a ' +
              'minute. It is not your game.');
        }
      } catch (e) { }

      /*
        Somebody who arrives already dead still gets a temple.

        spawnPoint is only ever written in onDeath, at the moment the body
        falls, so a death that happened while the client was disconnected, or
        during a kick window, leaves the character dead with whatever spawn
        point they had before. The SkyMP server does respawn a dead actor when
        it re-attaches, so they come back, and they come back at the default
        point rather than at the nearest consecrated ground.

        Written here, once, on the tick that first sees them. Nothing is moved
        and nothing is resurrected: this only decides where the respawn the
        server is already going to do puts them.
      */
      let dead = false;
      try { dead = !!mp.get(actorId, 'isDead'); } catch (e) { dead = false; }
      if (dead) {
        try {
          const where = {
            desc: mp.get(actorId, 'worldOrCellDesc'),
            pos: mp.get(actorId, 'pos'),
          };
          const back = resolveArrival(where);
          if (back) {
            mp.set(actorId, 'spawnPoint', {
              cellOrWorldDesc: back.desc, pos: back.pos, rot: back.rot,
            });
            log('login', actorId.toString(16), 'came back dead in', where.desc,
                '-> ' + back.cell + ' (' + back.slot + ')');
          }
        } catch (e) {
          log('login', actorId.toString(16), 'could not set a spawn point:', e);
        }
      }
    }
    if (now - firstSeen.get(actorId) < SETTLE_MS) {
      continue;
    }

    let state, appearance;
    try {
      state = chargenOf(actorId);
      appearance = mp.get(actorId, 'appearance');
    } catch (e) {
      continue;
    }

    if (!state) {
      let pidNew = 0;
      try { pidNew = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { pidNew = 0; }

      /*
        Somebody who already exists, decided by what they own.

        The check below this used to come first, on the stated grounds that a
        choice waiting from the launcher is proof the character was made
        seconds ago. It is not. The launcher posts a choice whenever it has a
        trade and a town recorded for a slot, and it has those for every
        character it has ever made, so a character who has been played for
        hours arrives here looking brand new. What follows is creation run a
        second time on somebody who already finished it: another full starter
        kit tipped into a pack that already had one, every piece of it equipped
        over what they were already wearing, and a trip back to the town they
        started in.

        A pack with things in it is proof in the other direction and it cannot
        be wrong, because nothing hands anybody anything before this point.
        Nobody arrives owning something unless they have played.
      */
      let owns = 0;
      try {
        const inv = mp.get(actorId, 'inventory');
        owns = (inv && inv.entries) ? inv.entries.length : 0;
      } catch (e) { owns = 0; }

      /*
        New or returning is decided by two physical facts, in this order, and
        by nothing inferred.

        FIRST, THINGS IN THE PACK MEAN RETURNING, wherever they are standing.
        Nothing hands anybody anything before this point, so nobody arrives
        owning something unless they have played. This is the proof that
        cannot be wrong and it goes first. 7ffe41a demoted it and that was a
        mistake, below.

        SECOND, WITH AN EMPTY PACK, STANDING IN UNBOUND'S HALL MEANS NEW. The
        hall is where the server's start point puts a brand new actor and
        nowhere else; nobody logs out there and nobody wakes up there twice.
        Anywhere else with an empty pack is somebody returning, most often a
        legacy character from before creation existed.

        WHY NOT THE APPEARANCE. 7ffe41a made "has a face" mean "returning", to
        stop played characters being re-created in whatever inn they had last
        chosen. That fixed the inn and broke the hall: on 20 September at
        11:52:26 profile 1043928337, brand new, was logged as already having a
        character and stamped done in the hall with no teleport and no way
        out. SkyMP opens the race menu on spawn, before this tick ever sees
        the actor, and confirming a face takes less than the ten second settle,
        so a new character has an appearance by the time anyone asks. A face
        is not evidence of anything either. Neither is a launcher choice: the
        launcher posts one for every slot it has ever made and the voice
        service keeps them a week, sixty five were waiting that morning.

        A location read that throws counts as not in the hall. Re-creating a
        person is the worse of the two mistakes, so the doubt goes that way.
      */
      let inHall = false;
      try {
        inHall = mp.get(actorId, 'worldOrCellDesc') === HALL.desc;
      } catch (e) { inHall = false; }

      const returning = owns > 0 || !inHall;
      if (returning) {
        log('chargen', actorId.toString(16), 'profile', pidNew,
            'already has a character' +
            (owns > 0 ? ' carrying ' + owns + (owns === 1 ? ' thing' : ' things')
                      : ' and is carrying nothing') +
            (inHall ? ', in the hall' : ', not in the hall') +
            (appearance ? ', face on' : ', no face') +
            ', so creation is skipped for them');
        setChargen(actorId, { stage: 'done', at: now, legacy: true });
        closeRaceMenu(actorId);
        continue;
      }

      // Genuinely new: an empty pack, standing in the hall.
      log('chargen', actorId.toString(16), 'profile', pidNew,
          'is new, in the hall with nothing' +
          (appearance ? ', face already on' : ''));
      beginAppearance(actorId);
      continue;
    }

    /*
      A bard who finished creation before any of this existed.

      The ability that turns holding an instrument into playing one was only
      ever handed out at the moment a kit was confirmed. That is once, ever, and
      only for somebody created after it was written. Every bard who finished
      before it, and every bard whose session ended before the kit read back
      complete, has been carrying three instruments and no way to use them.

      AddSpell on a spell an actor already has does nothing, so this costs a
      call per bard per session and nothing else.
    */
    if (state.class === 'bard' && !armed.has(actorId)) {
      armed.add(actorId);
      try { armBard(actorId); } catch (e) { }
    }

    // 'arriving' was the kit top-up after the teleport. There are no kits, so
    // anybody still marked arriving from before 20 September is simply done.
    if (state.stage === 'arriving') {
      state.stage = 'done';
      setChargen(actorId, state);
      closeRaceMenu(actorId);
      if (state.class === 'bard') { try { armBard(actorId); } catch (e) { } }
      log('chargen', actorId.toString(16), 'was marked arriving from before the kits went; closed');
      continue;
    }

    /*
      Standing in the hall with the panel to fill in.

      The exit is not here: the character block sends them the moment the
      home is picked (arriveAt). This is the reminder, and the reopen after
      a reconnect, because the page that had the panel is gone with the old
      session and the property does not fire again on its own.
    */
    if (state.stage === 'choosing') {
      const cameOnC = firstSeen.get(actorId) || 0;
      if (state.seenAt !== cameOnC) {
        state.seenAt = cameOnC;
        state.remindAt = now;
        setChargen(actorId, state);
      }
      if (now < (state.remindAt || 0)) { continue; }
      state.remindAt = now + CHOOSE_REMIND_MS;
      setChargen(actorId, state);
      openCreation(actorId);
      say(actorId, 'Press K to choose where you will start. Your class and profession can wait until you are there.');
      continue;
    }

    if (state.stage === 'appearance') {
      /*
        A reconnect starts the wait again from nothing.

        None of the fields below are cleared when somebody drops out of the
        hall and comes back, so a character who walked about for a few seconds
        and then quit returns with liveSince already set, where holding a
        position from the last session, and askedAt already past. The very
        first settled tick then reads that as somebody who has been on their
        feet for as long as they were away, and teleports them to the inn
        while their client is still loading the hall.

        firstSeen is set the moment somebody comes online, so comparing it
        against what the state remembers is what tells a reconnect from the
        session that made it.
      */
      const cameOn = firstSeen.get(actorId) || 0;
      if (state.seenAt !== cameOn) {
        state.seenAt = cameOn;
        delete state.liveSince;
        delete state.where;
        delete state.askedAt;
        delete state.nudged;
        // Long enough for the arrival to settle before a baseline is taken,
        // the same grace a fresh arrival gets.
        state.askAt = now + 4000;
        setChargen(actorId, state);
        log('chargen', actorId.toString(16),
            'came back mid creation, so the wait starts again');
        continue;
      }

      // The baseline, once whatever load screen we started has had time to
      // finish. No menu is opened here, deliberately. See below.
      if (!state.askedAt) {
        if (now < (state.askAt || 0)) { continue; }
        state.askedAt = now;
        // The face they are standing in right now, which after a teleport is
        // the one the client re-sent on arrival. Taken here rather than before
        // the move so that arrival is not mistaken for a finished face.
        state.faceWas = faceMark(appearance);
        setChargen(actorId, state);
        continue;
      }

      // Whether they are on their feet or in a menu, which is the one thing
      // that decides whether opening the race menu would be a rescue or a
      // wrecking ball. The server cannot ask the client what is on screen, but
      // it can see that somebody is turning on the spot: the angle moves every
      // frame while a person has the mouse, and not at all while a menu has it.
      let live = false;
      try {
        const pos = mp.get(actorId, 'pos') || [0, 0, 0];
        const ang = mp.get(actorId, 'angle') || [0, 0, 0];
        const here = [pos[0], pos[1], pos[2], ang[2]].join(',');
        if (state.where && state.where !== here) {
          // Far enough to be a person, not a settle. See MOVED_UNITS.
          const was = String(state.where).split(',');
          const dx = pos[0] - Number(was[0]);
          const dy = pos[1] - Number(was[1]);
          const dz = pos[2] - Number(was[2]);
          let turned = Math.abs(ang[2] - Number(was[3]));
          if (turned > 180) { turned = 360 - turned; }
          const moved = Math.sqrt(dx * dx + dy * dy + dz * dz);
          if (moved >= MOVED_UNITS || turned >= MOVED_DEGREES) { live = true; }
        }
        if (state.where !== here) {
          state.where = here;
          // Saved, not just assigned.
          //
          // This is the whole bug. `state` is read back off the actor at the
          // top of every tick, so a field written to the local copy and not
          // passed to setChargen is gone three seconds later. state.where was
          // therefore undefined on every single tick, the comparison above it
          // never had a baseline to compare against, live was never true, and
          // liveSince was never set.
          //
          // Everything after this point is gated on liveSince: the movement
          // path, the two minute nudge that reopens the race menu, and the
          // five minute give up that starts you anyway. All three were dead.
          // Nobody was ever going to leave that room, on any timescale, and
          // the log could not say so because the code that would have logged
          // it was behind the same gate.
          setChargen(actorId, state);
        }
      } catch (e) { }
      if (live && !state.liveSince) {
        state.liveSince = now;
        setChargen(actorId, state);
        log('chargen', actorId.toString(16), 'is on their feet');
      }

      // Changed, not merely present. See faceMark above.
      //
      // And a change here is exact, not a guess. SendInputsService.sendAppearance
      // is the only thing in the client that ever sends one:
      //
      //     var shown = this.sp.Ui.isMenuOpen('RaceSex Menu');
      //     if (shown != this.isRaceSexMenuShown) {
      //       this.isRaceSexMenuShown = shown;
      //       if (!shown) { ...send... }
      //     }
      //
      // One transition, open to closed, nothing else anywhere. So once the menu
      // has been asked for, the next appearance to arrive IS the finished face,
      // whether it took eight seconds or eight minutes.
      //
      // There was a twelve second window here that ignored early changes,
      // added because creation once flashed up and teleported instantly. That
      // was the wrong cure for the right symptom: the real cause was this
      // function teleporting somebody while their race menu was open, which
      // closed the menu, which made the client send the unfinished face. The
      // teleport happens before the menu is asked for now, so there is nothing
      // left to ignore, and ignoring things cost somebody who finished quickly
      // their exit from the hall: the window kept moving the mark forward, so
      // the face they had just made became the face they started with.
      const faceNow = faceMark(appearance);
      const faceIsNew = !!appearance && faceNow !== (state.faceWas || '');

      if (faceIsNew) {
        beginChoosing(actorId, state, 'the face arrived');
        continue;
      }

      // Walking around the hall is the end of character creation.
      //
      // Everything above waits on one signal: the appearance property changing
      // on the change form, which is what arrives when the race menu closes.
      // When that signal does not come, the whole flow stops, and the log says
      // exactly that and nothing else: "-> appearance (already in the hall)"
      // and then silence while somebody stands in a stone room wondering what
      // they did wrong.
      //
      // The rescue below existed for that, and it is far too patient: two
      // minutes before it reopens the race menu, five before it gives up and
      // starts them anyway. Nobody waits two minutes in an empty room. They
      // alt-F4, which is what happened three times tonight.
      //
      // But the evidence was there the whole time. The race menu is paused, so
      // a character in one does not move; a character who IS moving is a
      // character whose menu has closed. That is not a guess about the
      // appearance, it is a stronger fact than the appearance, and this file
      // was already measuring it a dozen lines up in order to decide whether
      // nudging was safe.
      //
      // So: on your feet, and we get on with it. The appearance can arrive
      // whenever it likes.
      const onFeetFor = state.liveSince ? (now - state.liveSince) : 0;

      if (onFeetFor > MOVED_ENOUGH_MS) {
        // Said in full because the appearance not arriving is still a bug
        // and this is the only place it can be seen from.
        log('chargen', actorId.toString(16), 'walking after',
            Math.round(onFeetFor / 1000) + 's and the face never arrived.',
            'appearance is', appearance ? 'present' : 'MISSING,',
            'mark now', JSON.stringify(faceNow) + ',',
            'mark at the start', JSON.stringify(state.faceWas || '') + '.',
            'Going on the movement instead.');
        beginChoosing(actorId, state, 'on their feet');
        continue;
      }

      // Nobody is ever left standing in the hall with nothing to do.
      //
      // This step waits for an appearance to turn up on the change form,
      // because the race menu closing is not an event. That is fine right up
      // until the race menu never opens, and then it waits forever: no menu,
      // no writs, no way forward, and a room with a person in it. Spawn is
      // supposed to open it on both of its branches, and when it does not the
      // reason is somewhere in a client mid save-load, which is not somewhere
      // this can reach.
      //
      // So: ask once, then stop waiting. A character who never saw the race
      // menu can open it later. One who cannot leave the room cannot do
      // anything at all.
      //
      // But only once it is clear that nobody is standing in a menu already.
      //
      // Spawn opens the race menu itself for every character it creates:
      //
      //     actorId = ctx.svr.createActor(...);
      //     ctx.svr.setRaceMenuOpen(actorId, true);
      //
      // so asking for it here as a matter of course was asking for a second
      // one. Which is what it did: a face was made, done was pressed, and the
      // menu opened again. Then the game went down with an access violation
      // trying to execute freed memory inside
      // NativeFunction1<TESNPC, BGSHeadPart*, unsigned long>, which is a head
      // part call on a character whose last race menu had already been torn
      // down. The second menu and the crash were the same thing.
      //
      // So this is a rescue and nothing else, and it only fires for somebody
      // who is demonstrably on their feet with no face, which is exactly the
      // case it was written for.
      const waited = now - (state.liveSince || state.askedAt || state.at || now);

      if (!state.liveSince) { continue; }

      if (!state.nudged && waited > NUDGE_MS) {
        state.nudged = now;
        setChargen(actorId, state);
        try {
          mp.setRaceMenuOpen(actorId, true);
          log('chargen', actorId.toString(16),
              'walking around with no face after', Math.round(waited / 1000) +
              's, so the race menu never opened. Asking for it.');
        } catch (e) {
          log('chargen', actorId.toString(16), 'could not open the race menu:', e);
        }
        continue;
      }

      if (waited > GIVEUP_MS) {
        // Still no face. Go on without one rather than leave them standing
        // here: a character who never saw the race menu can change their face
        // later, a character who cannot leave the room can do nothing at all.
        log('chargen', actorId.toString(16),
            'appearance never arrived after', Math.round(waited / 1000) + 's,',
            'going on to the choices anyway');
        beginChoosing(actorId, state, 'no face after ' + Math.round(waited / 1000) + 's');
      }
    }
  }
}

function startChargenTimer() {
  if (!CHARGEN_ENABLED) {
    log('character creation is Skyrim Unbound\'s. The server is staying out of it.');
    return;
  }

  // Hot reload runs this file again in a fresh module, but the Node process and
  // its timers survive. Without this the ticks stack up one per save.
  const g = globalThis;
  if (g.__thornswoodChargenTimer) {
    clearInterval(g.__thornswoodChargenTimer);
  }
  g.__thornswoodChargenTimer = setInterval(guard('chargenTick', chargenTick),
                                           CHARGEN_TICK_MS);
}

// ---------------------------------------------------------------------------
// event handlers
// ---------------------------------------------------------------------------

ensureProperties();
startChargenTimer();

/**
 * Set the arrival point at the moment of death, while we still know where the
 * body fell. The engine reads spawnPoint when the respawn timer expires.
 */
mp.onDeath = guard('onDeath', function (actorId, killerId) {
  /*
    People only.

    This fires for every MpActor the server owns, which is every bandit, wolf
    and chicken anybody kills. Each one was having a temple spawnPoint written
    onto it, which is meaningless at best and, if SkyMP ever honours it on an
    NPC respawn, puts dead bandits back on their feet inside temples.

    A profileId is what tells a person from the rest of Skyrim. Nothing else
    on the server has one.
  */
  let pid = 0;
  try { pid = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { pid = 0; }
  if (!pid) { return; }

  const site = {
    desc: mp.get(actorId, 'worldOrCellDesc'),
    pos: mp.get(actorId, 'pos'),
  };
  const arrival = resolveArrival(site);
  if (!arrival) {
    log('onDeath', actorId, 'no arrival resolved for', site.desc, '- leaving default spawn point');
    return;
  }
  mp.set(actorId, 'spawnPoint', {
    cellOrWorldDesc: arrival.desc,
    pos: arrival.pos,
    rot: arrival.rot,
  });
  log('death', actorId, 'in', site.desc,
      '-> ' + arrival.cell + ' (' + arrival.slot + ')',
      'hold=' + arrival.hold + '(' + arrival.via + ')',
      'ground=' + arrival.reason,
      killerId ? 'killer=' + killerId : '');
});

mp.onRespawn = guard('onRespawn', function (actorId) {
  const sp = mp.get(actorId, 'spawnPoint');
  log('respawn', actorId, 'at', sp && sp.cellOrWorldDesc);
});

/**
 * Reading a manual raises the track. Books are not consumed, so re-reading is
 * harmless and grants nothing twice.
 */
mp.onReadBook = guard('onReadBook', function (actorId, baseId) {
  for (const d in MANUALS) {
    if (idOf(d) !== baseId) continue;
    const m = MANUALS[d];
    if (setSkill(actorId, m.track, m.tier)) {
      log('skill', actorId, m.track, '-> tier', m.tier);
    }
    return;
  }
});


// ---------------------------------------------------------------------------
// scripted activators
//
// A shrine, a lever, a chain, a notice board and a nirnroot are the same kind
// of record: ACTI, an activator whose whole behaviour lives in an attached
// Papyrus script. On this server not one of those scripts runs, for two
// reasons that stack.
//
//   1. The server has no scripts. Its script storage is data/scripts plus any
//      archive named in the "archives" setting, and data/scripts holds exactly
//      one file: ActiveMagicEffect.pex. "archives" is not set at all, so
//      Skyrim's own script archive is never opened. Nothing vanilla is
//      attached to anything, anywhere.
//
//   2. Even with scripts present, the client is told not to run them. SkyMP
//      answers an activator with a bare OpenContainer message and the client
//      replies to that with refr.activate(player, true). The second argument
//      is abDefaultProcessingOnly: default behaviour only, no OnActivate. So
//      the script does not fire locally either.
//
// Which is why pressing E on a shrine does nothing at all, and why nirnroot
// cannot be picked: nirnroot is ACTI 0xE1FB2, not a FLOR, so it never reaches
// the branch of the server that hands out a harvested plant.
//
// The two below are done by hand because both effects are server side and
// therefore reliable: an ingredient into the pack, which is an ordinary
// inventory write, and an ability onto the character, which Actor.AddSpell
// records server side and re-sends on every spawn. Levers, chains and notice
// boards are not done here. They need the real script and there is no way to
// fake what they do; the way back for those is putting Skyrim's .pex files in
// the server's data/scripts.
// ---------------------------------------------------------------------------

/* Activator -> what it should have given you, and how long before it gives
 * again. Read out of Skyrim.esm rather than from a wiki: nirnroot is ACTI
 * 0xE1FB2 yielding INGR 0x59B86, and the red one is 0xB6FB9 yielding 0xB701A. */
const HARVESTS = {
  'e1fb2:Skyrim.esm': { item: '59b86:Skyrim.esm', name: 'Nirnroot' },
  'b6fb9:Skyrim.esm': { item: 'b701a:Skyrim.esm', name: 'Red Nirnroot' },
};

/* Shrine -> the ability it grants. These are the Altar*Spell records, which
 * are what the vanilla shrine script adds; the blessing is one ability at a
 * time, so the other eight come off when a new one goes on. */
const SHRINES = {
  'd9883:Skyrim.esm': { spell: 'fb988:Skyrim.esm', who: 'Akatosh' },
  '71854:Skyrim.esm': { spell: 'fb994:Skyrim.esm', who: 'Arkay' },
  'd9881:Skyrim.esm': { spell: 'fb995:Skyrim.esm', who: 'Dibella' },
  'd9885:Skyrim.esm': { spell: 'fb996:Skyrim.esm', who: 'Julianos' },
  'd987f:Skyrim.esm': { spell: 'fb997:Skyrim.esm', who: 'Kynareth' },
  'd9887:Skyrim.esm': { spell: 'fb998:Skyrim.esm', who: 'Mara' },
  'd987d:Skyrim.esm': { spell: 'fb999:Skyrim.esm', who: 'Stendarr' },
  '100780:Skyrim.esm': { spell: 'fb99a:Skyrim.esm', who: 'Talos' },
  'd987b:Skyrim.esm': { spell: 'fb99b:Skyrim.esm', who: 'Zenithar' },
  '10e8b0:Skyrim.esm': { spell: '10e8ae:Skyrim.esm', who: 'Nocturnal' },
};

const HARVEST_COOLDOWN_MS = 600000;   // ten minutes, roughly a vanilla reloot

/**
 * Add or remove an ability on somebody's character.
 *
 * This is the one Papyrus call from here that is known to reach a client.
 * Debug.Notification and Message.Show find their actor through the Papyrus
 * stack, which is empty when the call starts in this file, so they do nothing.
 * Actor.AddSpell takes its target from `self` instead: the native records the
 * spell on the server and sends the client a snippet to match, and the list
 * comes back on every spawn as learnedSpells. So a blessing survives logging
 * out, which the vanilla one does not.
 */
function spellOn(actorId, spellDesc, on) {
  try {
    mp.callPapyrusFunction(
      'method', 'Actor', on ? 'AddSpell' : 'RemoveSpell',
      { type: 'form', desc: mp.getDescFromId(actorId) },
      [{ type: 'espm', desc: spellDesc }, false]
    );
    return true;
  } catch (e) {
    log('shrine: could not', on ? 'add' : 'remove', spellDesc, '-', e);
    return false;
  }
}

/*
 * The bard's instruments, and why they needed two fixes rather than one.
 *
 * The kit used to hand out Skyrim's own lute, drum and flute: 0xDABAB, 0xDABA7
 * and 0xDABA9. Those are MISC records. Vanilla has no way to hold one, so they
 * cannot be equipped and Use does nothing, which is exactly what a bard found
 * when they looked in their pack.
 *
 * PlayFluteLuteDrum.esp, which is already in the load order, does not override
 * those. It adds three WEAP records of its own, FluteWeapon, LuteWeapon and
 * DrumWeapon, and those are the ones you can actually hold. The kit now hands
 * out those instead.
 *
 * It also ships PlayInstrumentSpell, the ability that turns holding one into
 * playing one, and that ability is handed out by a start-game-enabled quest.
 * A quest is exactly the kind of thing not to rely on here: the character is a
 * change form the server hands back rather than a game somebody started, so
 * whether that quest ever ran for them is not something this can know. Adding
 * it directly costs nothing when it is already there, because AddSpell on a
 * spell an actor already has does nothing at all.
 */
const INSTRUMENT_SPELL = '9456:PlayFluteLuteDrum.esp';

function armBard(actorId) {
  if (spellOn(actorId, INSTRUMENT_SPELL, true)) {
    log('bard', actorId.toString(16), 'can play their instruments');
  }
}

/** One blessing at a time, the way the shrines themselves work. */
function bless(actorId, baseDesc) {
  const shrine = SHRINES[baseDesc];
  if (!shrine) return null;
  for (const d in SHRINES) {
    if (d === baseDesc) continue;
    spellOn(actorId, SHRINES[d].spell, false);
  }
  if (!spellOn(actorId, shrine.spell, true)) {
    return 'The shrine of ' + shrine.who + ' does not answer.';
  }
  return 'You take the blessing of ' + shrine.who + '.';
}

function harvest(actorId, refrId, baseDesc) {
  const plant = HARVESTS[baseDesc];
  if (!plant) return null;
  const prev = lastUse.get(actorId + ':' + refrId) || 0;
  if (Date.now() - prev < HARVEST_COOLDOWN_MS) {
    return 'This one has already been picked.';
  }
  if (!addItem(actorId, plant.item, 1)) return null;
  lastUse.set(actorId + ':' + refrId, Date.now());
  return 'You pick the ' + plant.name + '.';
}

/**
 * Everything anybody presses E on.
 *
 * Returning false blocks the default activation, which is what keeps the
 * furniture from playing its own idle while the server hands out the yield.
 * Returning undefined lets it through: the native reads the result and only an
 * explicit false counts as a block, so falling off the end of this function is
 * the safe answer and is what every ordinary door, chest and item gets.
 */
mp.onActivate = guard('onActivate', function (refrId, casterRefrId) {
  if (!casterRefrId) return;
  let baseDesc;
  try {
    baseDesc = mp.get(refrId, 'baseDesc');
  } catch (e) {
    return;
  }

  let message = null;
  if (baseDesc === STATIONS.saltQuarry) message = mineSalt(casterRefrId, refrId);
  else if (baseDesc === STATIONS.charcoalKiln) message = burnCharcoal(casterRefrId, refrId);
  else if (SHRINES[baseDesc]) message = bless(casterRefrId, baseDesc);
  else if (HARVESTS[baseDesc]) message = harvest(casterRefrId, refrId, baseDesc);
  else return;

  if (message) {
    notify(casterRefrId, message);
    say(casterRefrId, message);
  }
  return false;
});

/*
  The bases this server answers for, published where the client can read them.

  thornswood-front.js re-activates every ACTI it sees, because a handful of
  vanilla handle and lever scripts never start under SkyMP. The client forwards
  that second activation as well, so onActivate below ran twice for every press
  on anything the server already handles: a quarry strike and then "the seam
  needs 20 more seconds", a blessing removed and re-added.

  The client cannot know which bases those are without being told, so it is
  told. This goes into the same folder the client already fetches online.json
  and the manifest from, as runtime form ids, which is exactly what the
  client's getBaseObject().getFormID() hands back.
*/
(function publishServerBases() {
  var ids = [];
  var seen = {};
  function add(desc) {
    var id = idOf(desc);
    // 0 means the plugin that owns it is not loaded, which is a different
    // problem and not one this list should carry. Deduped because two keys
    // resolving to one record would otherwise be sent twice.
    if (id && !seen[id]) { seen[id] = true; ids.push(id); }
  }
  try {
    add(STATIONS.saltQuarry);
    add(STATIONS.charcoalKiln);
    for (var shrine in SHRINES) { add(shrine); }
    for (var crop in HARVESTS) { add(crop); }

    var fsb = require('fs');
    var pathb = require('path');
    var dataDirB = 'data';
    try {
      var cfgB = JSON.parse(fsb.readFileSync('server-settings.json', 'utf8'));
      if (cfgB && cfgB.dataDir) { dataDirB = String(cfgB.dataDir); }
    } catch (e) { }
    fsb.writeFileSync(pathb.join(dataDirB, 'server-bases.json'),
                      JSON.stringify({ at: Date.now(), bases: ids }));
    log('published', ids.length, 'server handled bases for the client');
  } catch (e) {
    log('could not publish the server handled bases, the client will keep ' +
        're-activating them:', e);
  }
})();

log('gamemode loaded:',
    Object.keys(DATA.cellToHold).length + ' cells mapped,',
    Object.keys(MANUALS).length + ' manuals,',
    Object.keys(STATIONS).length + ' station types,',
    Object.keys(PASSAGES).length + ' starting towns');

// ==== thornswood voice feed, added by Add-VoiceFeed.ps1 ====
// ----------------------------------------------------------------- voice ---
// Proximity voice, server side.
//
// The voice service runs beside this server and needs one thing from it:
// where everybody is, five times a second. It gets it from here rather than
// from anybody's game, which means voice does not care which client build a
// person runs, and nobody can move their own voice by editing a file.
//
// Everything below is deliberately best effort. A voice service that is down,
// slow or not installed must never be able to take the game server with it, so
// every call is wrapped and failures are counted rather than thrown.
(function () {
  var VOICE_PORT = voicePort();
  var EVERY_MS = 200;
  var http = null;

  try { http = require('http'); } catch (e) { return; }
  if (!http) return;

  var failures = 0;
  var complained = false;
  var inFlight = false;

  function send(payload) {
    if (inFlight) return;           // never queue: a late position is worthless
    inFlight = true;

    var body = JSON.stringify(payload);
    var req = http.request({
      host: '127.0.0.1', port: VOICE_PORT, path: '/positions', method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) }
    }, function (res) {
      res.resume();
      res.on('end', function () { inFlight = false; failures = 0; complained = false; });
    });

    req.on('error', function () {
      inFlight = false;
      failures++;
      // Once, then quiet. Nobody needs this five times a second for an hour.
      if (failures === 25 && !complained) {
        complained = true;
        console.log('[thornswood] voice service is not answering on ' + VOICE_PORT +
                    '. Proximity voice is off; everything else is unaffected.');
      }
    });
    req.setTimeout(1000, function () { try { req.destroy(); } catch (e) { } });
    req.end(body);
  }

  // Stored and cleared like the chargen timers, so a hot reload replaces
  // this feed rather than adding a second one that never stops.
  if (globalThis.__thornswoodVoiceFeed) {
    try { clearInterval(globalThis.__thornswoodVoiceFeed); } catch (e) { }
  }
  globalThis.__thornswoodVoiceFeed = setInterval(function () {
    var who = [];
    try {
      var online = mp.get(0, 'onlinePlayers') || [];
      for (var i = 0; i < online.length; i++) {
        var id = online[i];
        try {
          var pos = mp.get(id, 'pos');
          if (!pos) continue;
          var angle = mp.get(id, 'angle') || [0, 0, 0];
          who.push({
            profileId: mp.get(id, 'profileId'),
            pos: pos,
            angleZ: angle[2],
            // Two people in the same room share this string. Two people either
            // side of a loading door do not, which is exactly the line voice
            // should stop at.
            cell: String(mp.get(id, 'worldOrCellDesc') || ''),
            name: String(mp.get(id, 'appearance') && mp.get(id, 'appearance').name || '')
          });
        } catch (e) { }
      }
    } catch (e) { return; }

    if (who.length === 0) return;
    try { send({ who: who }); } catch (e) { }
  }, EVERY_MS);

  // ------------------------------------------------------------- online ---
  // How many people are awake, written where the launcher can read it.
  //
  // There is no way to ask a SkyMP server how busy it is: its networking has
  // no status packet, and the public list the old build used belongs to Skyrim
  // Together and this server never reports to it. But the server already
  // serves its resources folder over HTTP, so a small file dropped in there is
  // readable by every launcher without opening anything new or inventing a
  // protocol.
  try {
    var fs = require('fs');
    var path = require('path');
    var dataDir = 'data';
    try {
      var cfg = JSON.parse(fs.readFileSync('server-settings.json', 'utf8'));
      if (cfg && cfg.dataDir) dataDir = String(cfg.dataDir);
    } catch (e) { }

    var onlineFile = path.join(dataDir, 'online.json');
    var lastWritten = -1;

    // Cleared on a hot reload, so reloading does not leave two writers
    // racing each other over the same file.
    if (globalThis.__thornswoodOnlineWriter) {
      try { clearInterval(globalThis.__thornswoodOnlineWriter); } catch (e) { }
    }
    var lastRestarting = false;

    globalThis.__thornswoodOnlineWriter = setInterval(function () {
      var n = 0;
      try { n = (mp.get(0, 'onlinePlayers') || []).length; } catch (e) { return; }

      /*
        Whether a countdown is running, for the client's own probe.

        thornswood-front.js watches this folder to decide the server is still
        there, and quits to the main menu after a run of misses. A restart
        people were told to sit through looks identical to the server being
        gone, so everybody who did as they were told got thrown out anyway.
        The countdown state lives on globalThis so this writer can see it from
        another block.
      */
      var restarting = false;
      try {
        var r = globalThis.__thornswoodRestart;
        var nowR = Date.now();
        /*
          Counting down, or stopped counting down within the last three
          minutes. Three is longer than the stop, copy and start in
          Deploy-Server, and being wrong this way only ever delays a quit.
          After the restart this process is fresh, the record is empty again,
          and the next pass writes false.

          Both halves are needed and neither is enough on its own. restartTick
          runs every 1500 ms and this every 2000 ms, so for up to a tick after
          the deadline passes the countdown is over and nothing has recorded
          that yet: at is in the past and went is not set. Asking how long ago
          at was, rather than whether it is still ahead, covers that gap, and
          went covers the rest once the tick has zeroed at.
        */
        restarting = !!(r && ((r.at && nowR - r.at < 180000) ||
                             (r.went && nowR - r.went < 180000)));
      } catch (e) { restarting = false; }

      // Only when something moves. This file sits in a folder the server
      // serves, and rewriting it twice a second for no reason is churn nobody
      // asked for.
      if (n === lastWritten && restarting === lastRestarting) return;
      lastWritten = n;
      lastRestarting = restarting;
      try {
        fs.writeFileSync(onlineFile, JSON.stringify({
          now: n, at: Date.now(), restarting: restarting
        }));
      } catch (e) { }
    }, 2000);

    console.log('[thornswood] online count published at ' + onlineFile);
  } catch (e) { }

  console.log('[thornswood] voice position feed running, pushing to 127.0.0.1:' + VOICE_PORT);
})();
// ==== end thornswood voice feed ====
// ==== thornswood character roster ====
// ---------------------------------------------------------------- roster ---
// Who each profile id actually is, written where the launcher can read it.
//
// The launcher knows a profile id and nothing else. That is by design: the id
// is the only thing that decides which character the server hands back, and it
// is the only thing the launcher has any business choosing. But it makes for a
// poor card. "profile 1964204031" tells nobody anything.
//
// Everything worth showing lives here instead. The race and the sex are in the
// appearance the client uploaded, the trade and the town are in the chargen
// state this gamemode wrote when the launcher's choice was applied, and none of
// it is on anybody's disk.
//
// It goes out the same way the online count does: a small file in the folder
// the server already serves over HTTP on 3000. Nothing new is opened and no
// protocol is invented.
//
// Kept, not rebuilt. onlinePlayers only lists people who are connected, and
// somebody looking at the launcher is by definition not connected, so a file
// built fresh from who is online would be empty exactly when it is read. Each
// profile's row is written while they are on and left there afterwards.
(function () {
  var fs = null, path = null;
  try { fs = require('fs'); path = require('path'); } catch (e) { return; }
  if (!fs || !path) return;

  var EVERY_MS = 4000;

  var dataDir = 'data';
  var privDir = 'private';
  try {
    var cfg = JSON.parse(fs.readFileSync('server-settings.json', 'utf8'));
    if (cfg && cfg.dataDir) dataDir = String(cfg.dataDir);
    if (cfg && cfg.privDir) privDir = String(cfg.privDir);
  } catch (e) { }


  /*
    Make the folder before writing into it.

    privDir held door.json, allowed.json and characters.json on 18 September
    and on 20 September the whole folder was gone. Every write into it is
    wrapped in a try, so a missing folder is not an error anybody sees: the
    character register silently stops being saved, the door silently never
    fetches a roster, and /tp silently refuses everybody because the list it
    reads was never written. That is three separate reports with one cause and
    no log line between them.

    One mkdir at load costs nothing and there is no case where the right answer
    is to carry on writing into a folder that is not there.
  */
  function ensureDir(d) {
    try {
      if (d && !fs.existsSync(d)) {
        fs.mkdirSync(d, { recursive: true });
        console.log('[thornswood] made the missing folder ' + d);
      }
    } catch (e) {
      console.log('[thornswood] could not make ' + d + ': ' + e);
    }
  }
  ensureDir(privDir);

  var FILE = path.join(privDir, 'characters.json');

  var book = {};
  try {
    var had = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    if (had && had.who && typeof had.who === 'object') book = had.who;
  } catch (e) { book = {}; }

  // The ten playable races, by the low three bytes of their form id. Skyrim.esm
  // is always file index zero so the top byte is zero anyway, but masking makes
  // that an assumption the code states rather than one it relies on.
  var RACES = {
    0x013740: 'Argonian',
    0x013741: 'Breton',
    0x013742: 'Dark Elf',
    0x013743: 'High Elf',
    0x013744: 'Imperial',
    0x013745: 'Khajiit',
    0x013746: 'Nord',
    0x013747: 'Orc',
    0x013748: 'Redguard',
    0x013749: 'Wood Elf'
  };

  // Anything else, including vampire variants and whatever a mod adds, is
  // looked up properly and turned into words. Deliberately not a second hand
  // written table: a list of ids for mod added races would be wrong the first
  // time somebody changed the mod list.
  var looked = {};

  function spaced(editorId) {
    var s = String(editorId || '');
    if (/Race$/i.test(s)) s = s.slice(0, -4);
    var out = '';
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (i > 0 && c >= 'A' && c <= 'Z' && !(s.charAt(i - 1) >= 'A' && s.charAt(i - 1) <= 'Z')) out += ' ';
      out += c;
    }
    return out.trim();
  }

  function raceName(id) {
    id = Number(id) || 0;
    if (!id) return '';
    var known = RACES[id & 0xFFFFFF];
    if (known) return known;
    if (looked[id] !== undefined) return looked[id];

    var name = '';
    try {
      var found = mp.lookupEspmRecordById(id);
      var rec = found && found.record;
      var fields = (rec && rec.fields) || [];
      for (var i = 0; i < fields.length; i++) {
        if (String(fields[i].type) !== 'EDID') continue;
        var bytes = fields[i].data || [];
        var text = '';
        for (var b = 0; b < bytes.length; b++) {
          if (!bytes[b]) break;
          text += String.fromCharCode(bytes[b]);
        }
        name = spaced(text);
        break;
      }
    } catch (e) { name = ''; }

    looked[id] = name;
    return name;
  }

  /*
   * Where somebody is, in words.
   *
   * worldOrCellDesc is a form descriptor, "16789:Skyrim.esm", which is the
   * right thing to store and the wrong thing to show anybody. The cell record
   * usually carries a FULL name written for players, so that is asked for
   * first: "Candlehearth Hall", "Whiterun". Falling back to the editor id and
   * spacing it out gives something readable rather than nothing, and a cell
   * with neither is left alone rather than guessed at.
   *
   * Cached because a cell's name never changes and this runs every four
   * seconds for everybody online.
   */
  var places = {};

  function placeName(desc) {
    desc = String(desc || '');
    if (!desc) return '';
    if (places[desc] !== undefined) return places[desc];

    var out = '';
    try {
      var id = mp.getIdFromDesc(desc);
      var found = id ? mp.lookupEspmRecordById(id) : null;
      var rec = found && found.record;
      var fields = (rec && rec.fields) || [];

      /*
        EDID first, FULL only when it is really text.

        Skyrim.esm and the DLCs are localized, which means a FULL field does
        not hold a name at all: it holds a four byte index into the strings
        file beside the plugin. Reading those bytes as characters wrote four
        bytes of binary into characters.json as somebody's location, for every
        vanilla cell in the game.

        The editor id is always plain ASCII and always present, so it is the
        one to trust. A FULL is taken only when every byte of it is printable
        ASCII, which a real name in an unlocalized plugin is and a string index
        almost never is.
      */
      var edid = '';
      var full = '';
      for (var i = 0; i < fields.length; i++) {
        var t = String(fields[i].type);
        if (t === 'FULL' && !full) {
          var bytes = fields[i].data || [];
          var text = '';
          var printable = bytes.length > 0;
          for (var b = 0; b < bytes.length; b++) {
            if (!bytes[b]) break;
            if (bytes[b] < 32 || bytes[b] > 126) { printable = false; break; }
            text += String.fromCharCode(bytes[b]);
          }
          if (printable && text) { full = text; }
        } else if (t === 'EDID' && !edid) {
          var eb = fields[i].data || [];
          for (var e2 = 0; e2 < eb.length; e2++) {
            if (!eb[e2]) break;
            edid += String.fromCharCode(eb[e2]);
          }
        }
      }
      if (edid) { out = spaced(edid); }
      else if (full) { out = full; }
    } catch (e) { out = ''; }

    places[desc] = out;
    return out;
  }

  function write() {
    try {
      fs.writeFileSync(FILE, JSON.stringify({ at: Date.now(), who: book }));
    } catch (e) { }
    push();
  }

  /*
    The same book, to the site.

    The launcher used to read characters.json straight off the resource port.
    On 18 September the file moved into the private folder (it names people
    and where they stand), the port has answered 404 since, and every card in
    the launcher, and now the game's own menu, has been nameless. The site is
    the one thing the launcher can prove itself to, so the book goes there
    with the door's key, and the site hands each person their own rows and
    nobody else's (POST /api/play/roster with the Discord ticket). Sent when
    the book changes, and once after a start so a restart is not a blank.
  */
  var pushSaid = false;
  function push() {
    var conf;
    try {
      conf = JSON.parse(fs.readFileSync(path.join(privDir, 'door.json'), 'utf8').replace(/^﻿/, ''));
    } catch (e) { return; }
    if (!conf || !conf.site || !conf.key) return;
    var https;
    try { https = require('https'); } catch (e) { return; }
    var u;
    try { u = new URL(String(conf.site).replace(/\/+$/, '') + '/api/roster'); } catch (e) { return; }
    var body = JSON.stringify({ key: String(conf.key), who: book });
    try {
      var req = https.request({
        host: u.hostname, port: u.port || 443, path: u.pathname, method: 'POST', timeout: 5000,
        headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) }
      }, function (resp) {
        resp.resume();
        if (resp.statusCode !== 200 && !pushSaid) {
          pushSaid = true;
          console.log('[thornswood] the site answered ' + resp.statusCode + ' to the roster; names will be missing from the menu');
        }
      });
      req.on('error', function (e) {
        if (!pushSaid) {
          pushSaid = true;
          console.log('[thornswood] could not send the roster to the site: ' + (e && e.message ? e.message : e));
        }
      });
      req.on('timeout', function () { req.destroy(); });
      req.end(body);
    } catch (e) { }
  }
  setTimeout(push, 15000);

  var dirty = false;

  // Cleared on a hot reload. Three of these ran unstored, so every reload
  // added another copy of each and none of them ever stopped.
  if (globalThis.__thornswoodRoster) {
    try { clearInterval(globalThis.__thornswoodRoster); } catch (e) { }
  }
  globalThis.__thornswoodRoster = setInterval(function () {
    var online = [];
    try { online = mp.get(0, 'onlinePlayers') || []; } catch (e) { return; }

    for (var i = 0; i < online.length; i++) {
      var id = online[i];
      try {
        var pid = Number(mp.get(id, 'profileId')) || 0;
        if (!pid) continue;

        var look = mp.get(id, 'appearance') || null;
        var state = null;
        try { state = chargenOf(id); } catch (e) { state = null; }
        // The profession lives on the character property since 20 September;
        // the old trade key is read for anybody made before it.
        var ch = null;
        try { ch = mp.get(id, 'thornswoodCharacter'); } catch (e) { ch = null; }

        var where = '';
        try { where = placeName(mp.get(id, 'worldOrCellDesc')); } catch (e) { where = ''; }

        var row = {
          name: String((look && look.name) || ''),
          race: look ? raceName(look.raceId) : '',
          female: !!(look && look.isFemale),
          trade: String((ch && ch.prof) || (state && state.class) || ''),
          town: String((state && state.destination) || ''),
          // Where they were standing the last time the server looked. Kept on
          // the row rather than thrown away when they log out, because the
          // only person who ever reads this is looking at a launcher with the
          // game shut, and "last seen in" is the whole point of it.
          where: where,
          at: Date.now()
        };

        var was = book[String(pid)];
        // Compared field by field rather than by timestamp, because the
        // timestamp moves every four seconds and this file sits in a folder
        // the server serves. Rewriting it fifteen times a minute for nothing
        // is churn nobody asked for.
        if (!was || was.name !== row.name || was.race !== row.race ||
            was.female !== row.female || was.trade !== row.trade ||
            was.town !== row.town || was.where !== row.where) {
          book[String(pid)] = row;
          dirty = true;
        }
      } catch (e) { }
    }

    if (dirty) { dirty = false; write(); }
  }, EVERY_MS);

  console.log('[thornswood] character roster published at ' + FILE);
})();
// ==== end thornswood character roster ====

// ==== thornswood door ====
// ---------------------------------------------------------------- the door ---
//
// The server has had no access control of any kind. Anyone who knows the
// address connects, and the address is about to be on a public website.
//
// This watches who turns up and compares them against an allow list. It starts
// in WATCH mode and kicks nobody, because it was written without a way to test
// it against a live server, and a door that wrongly turns everybody away is a
// worse outage than the hole it closes. Run it for a day, read the log, and
// only then set "enforce": true.
//
// The allow list lives at <dataDir>/allowed.json:
//
//     { "enforce": false, "profiles": [123, 456], "devProfiles": [123], "note": "..." }
//
// enforce      false logs and lets everyone in. true kicks anybody not listed.
// profiles     the profileId of each person allowed in. The launcher shows a
//              person's profile id on the Diagnostics page.
// devProfiles  the subset who also hold the dev or admin role. Read by
//              __thornswoodIsDev below, for gating a command rather than a
//              connection.
//
// No file means the door is off entirely and this costs one failed stat per
// thirty seconds.
(function () {
  var fs = null, path = null;
  try { fs = require('fs'); path = require('path'); } catch (e) { return; }
  if (!fs || !path) return;

  var dataDir = 'data';
  var privDir = 'private';
  try {
    var cfg = JSON.parse(fs.readFileSync('server-settings.json', 'utf8'));
    if (cfg && cfg.dataDir) dataDir = String(cfg.dataDir);
    if (cfg && cfg.privDir) privDir = String(cfg.privDir);
  } catch (e) { }


  /*
    Make the folder before writing into it.

    privDir held door.json, allowed.json and characters.json on 18 September
    and on 20 September the whole folder was gone. Every write into it is
    wrapped in a try, so a missing folder is not an error anybody sees: the
    character register silently stops being saved, the door silently never
    fetches a roster, and /tp silently refuses everybody because the list it
    reads was never written. That is three separate reports with one cause and
    no log line between them.

    One mkdir at load costs nothing and there is no case where the right answer
    is to carry on writing into a folder that is not there.
  */
  function ensureDir(d) {
    try {
      if (d && !fs.existsSync(d)) {
        fs.mkdirSync(d, { recursive: true });
        console.log('[thornswood] made the missing folder ' + d);
      }
    } catch (e) {
      console.log('[thornswood] could not make ' + d + ': ' + e);
    }
  }
  ensureDir(privDir);

  var FILE = path.join(privDir, 'allowed.json');
  var LOG  = path.join(privDir, 'door.log');

  var list = null;       // null means no file, door off
  var readAt = 0;

  function load() {
    var now = Date.now();
    if (now - readAt < 30000) return list;
    readAt = now;
    try {
      var doc = JSON.parse(fs.readFileSync(FILE, 'utf8').replace(/^﻿/, ''));
      var ids = {};
      if (Array.isArray(doc.profiles)) {
        for (var i = 0; i < doc.profiles.length; i++) {
          var n = Number(doc.profiles[i]);
          if (n) ids[n] = true;
        }
      }
      // Who among them also holds the dev or admin role, from the same
      // answer, so a command gate elsewhere in this file can ask without a
      // second trip anywhere.
      var devIds = {};
      if (Array.isArray(doc.devProfiles)) {
        for (var j = 0; j < doc.devProfiles.length; j++) {
          var dn = Number(doc.devProfiles[j]);
          if (dn) devIds[dn] = true;
        }
      }
      // The site's admins (the Owner and Dev roles, unless its config says
      // otherwise), so an Owner's new character is an admin in here too and
      // not only the one profile number written into server-settings.json.
      var adminIds = {};
      if (Array.isArray(doc.adminProfiles)) {
        for (var a = 0; a < doc.adminProfiles.length; a++) {
          var an = Number(doc.adminProfiles[a]);
          if (an) adminIds[an] = true;
        }
      }
      list = { enforce: doc.enforce === true, ids: ids, devIds: devIds, adminIds: adminIds, count: Object.keys(ids).length };
    } catch (e) {
      list = null;
    }
    return list;
  }

  /*
    Whether this profile's Discord account holds the dev or playtest role,
    right now, as of the last five minute refresh from the site.

    On globalThis because this whole module is one closed IIFE and the command
    handler that wants this lives in a different one further down the file.
    False whenever there is nothing to ask, which is a door that is off
    entirely (no door.json) rather than a reason to trust nobody: it is a
    ceiling raised for people who already hold a role, never a floor.
  */
  (typeof globalThis !== 'undefined' ? globalThis : this).__thornswoodIsDev = function (profileId) {
    var l = load();
    return !!(l && l.devIds && l.devIds[Number(profileId)]);
  };
  (typeof globalThis !== 'undefined' ? globalThis : this).__thornswoodIsAdmin = function (profileId) {
    var l = load();
    return !!(l && l.adminIds && l.adminIds[Number(profileId)]);
  };

  /*
    And the playtest roster, which is the same list the door already keeps.

    A profile is only in allowed.json at all because the site asked Discord and
    got back somebody who may play, so being on it IS holding the play role.
    That is what makes this worth reading for a command gate: it is the same
    fact, already fetched, already five minutes fresh, and nobody has to
    maintain a second copy of it by hand.
  */
  (typeof globalThis !== 'undefined' ? globalThis : this).__thornswoodIsAllowed = function (profileId) {
    var l = load();
    return !!(l && l.ids && l.ids[Number(profileId)]);
  };

  /*
    Whether the role lists are actually answering, for the startup line.

    A door that was never configured returns false to every question above,
    silently, and that is exactly how /tp came to refuse everybody on 19 and 20
    September: the code was right and there was no list anywhere for it to
    read. Saying so once at startup is the difference between a bug somebody
    reports and a line somebody notices.
  */
  (typeof globalThis !== 'undefined' ? globalThis : this).__thornswoodRoleSource = function () {
    var l = load();
    if (!l) { return 'none'; }
    return Object.keys(l.ids).length + ' allowed, ' + Object.keys(l.devIds || {}).length + ' dev';
  };

  function note(line) {
    var stamp = new Date().toISOString();
    console.log('[thornswood door] ' + line);
    try { fs.appendFileSync(LOG, stamp + '  ' + line + '\n'); } catch (e) { }
  }

  // Everybody this pass has already decided about, so a person is judged once
  // per visit rather than every two seconds for as long as they are standing
  // there.
  var judged = {};

  // When the list last came down from the site, when the site was last asked
  // for an unknown profile, and when each connection was first seen. A
  // character made a minute ago is on the site (the launcher checks the
  // chosen profile in at the main menu) and not on a list that is up to five
  // minutes old; on 20 September that refused /tp to Patrick's new character
  // for the rest of the refresh window, and with the door enforcing it would
  // have turned them away. So an unknown profile makes the door ask the site
  // again, at most once in twenty seconds, and hold its judgement until the
  // answer is in or thirty seconds have gone.
  var listAt = 0;
  var askedAt = 0;
  var seenAt = {};

  function tick() {
    var conf = load();
    if (!conf) return;                       // no allowed.json, door is off

    var online;
    try { online = mp.get(0, 'onlinePlayers'); } catch (e) { return; }
    if (!Array.isArray(online)) return;

    var here = {};
    var now = Date.now();
    for (var i = 0; i < online.length; i++) here[online[i]] = true;
    for (var k in judged) { if (!here[k]) delete judged[k]; }
    for (var k2 in seenAt) { if (!here[k2]) delete seenAt[k2]; }

    for (var j = 0; j < online.length; j++) {
      var actorId = online[j];
      if (judged[actorId]) continue;
      if (!seenAt[actorId]) seenAt[actorId] = now;

      var pid = 0;
      try { pid = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { pid = 0; }

      var ok = pid && conf.ids[pid];
      if (!ok && listAt < seenAt[actorId] && now - seenAt[actorId] < 30000) {
        if (now - askedAt > 20000) {
          askedAt = now;
          note('profile ' + (pid || 'unknown') + ' is not on the list yet, asking the site again');
          try { refresh(); } catch (e) { note('refresh threw: ' + e); }
        }
        continue;
      }
      judged[actorId] = true;
      if (ok) {
        note('let in profile ' + pid + ' (actor ' + actorId.toString(16) + ')');
        continue;
      }

      if (!conf.enforce) {
        note('WOULD TURN AWAY profile ' + (pid || 'unknown') +
             ' (actor ' + actorId.toString(16) + '). Watching only, they stayed. ' +
             conf.count + ' profiles on the list.');
        continue;
      }

      var userId = -1;
      try { userId = mp.getUserByActor(actorId); } catch (e) { userId = -1; }
      if (userId < 0) {
        note('turning away profile ' + (pid || 'unknown') +
             ' but could not find their connection, so they stayed');
        continue;
      }
      try {
        mp.kick(userId);
        note('turned away profile ' + (pid || 'unknown') + ' (actor ' + actorId.toString(16) + ')');
      } catch (e) {
        note('could not turn away profile ' + (pid || 'unknown') + ': ' + e);
      }
    }
  }

  // ------------------------------------------------------------ refresh ---
  //
  // The list comes from the site, which is the only thing that knows Discord
  // roles. <dataDir>/door.json holds where to ask and the key to ask with:
  //
  //     { "site": "https://thornswood.net", "key": "<the bot key>" }
  //
  // No file means no refreshing, and the door uses whatever allowed.json
  // already says. "enforce" is never touched by this: turning the door on is a
  // decision, not something a web request gets to make.
  function refresh() {
    var conf;
    try {
      conf = JSON.parse(fs.readFileSync(path.join(privDir, 'door.json'), 'utf8')
                          .replace(/^\uFEFF/, ''));
    } catch (e) { return; }
    if (!conf || !conf.site || !conf.key) return;

    var https;
    try { https = require('https'); } catch (e) { return; }

    var url = String(conf.site).replace(/\/+$/, '') +
              '/api/allowed?key=' + encodeURIComponent(String(conf.key));
    var req;
    try {
      req = https.get(url, function (resp) {
        var buf = '';
        resp.on('data', function (d) { buf += d; });
        resp.on('end', function () {
          var doc;
          try { doc = JSON.parse(buf); } catch (e) {
            note('the site sent something that is not a list: ' + buf.slice(0, 120));
            return;
          }
          if (resp.statusCode !== 200) {
            note('the site refused the list, ' + resp.statusCode +
                 (doc && doc.error ? ' (' + doc.error + ')' : ''));
            return;
          }
          // Keeping the old list is the safe failure. Writing a short one built
          // while Discord was unreachable would turn away everybody missing
          // from it.
          if (doc.lookupFailed) {
            note('the site could not reach Discord, keeping the list as it was');
            return;
          }
          if (!Array.isArray(doc.profiles)) return;

          var enforce = false;
          try {
            var had = JSON.parse(fs.readFileSync(FILE, 'utf8').replace(/^\uFEFF/, ''));
            enforce = had.enforce === true;
          } catch (e) { }

          try {
            fs.writeFileSync(FILE, JSON.stringify({
              enforce: enforce,
              profiles: doc.profiles,
              devProfiles: Array.isArray(doc.devProfiles) ? doc.devProfiles : [],
              adminProfiles: Array.isArray(doc.adminProfiles) ? doc.adminProfiles : [],
              people: doc.people || [],
              at: new Date().toISOString(),
              note: 'Written by the gamemode from the site. Set enforce true to turn the door on.'
            }, null, 2));
            readAt = 0;                       // make the next tick re-read it
            listAt = Date.now();
            note('list refreshed from the site, ' + doc.profiles.length + ' profiles, ' +
                 (Array.isArray(doc.devProfiles) ? doc.devProfiles.length : 0) + ' dev, ' +
                 (Array.isArray(doc.adminProfiles) ? doc.adminProfiles.length : 0) + ' admin');
          } catch (e) {
            note('could not write ' + FILE + ': ' + e);
          }
        });
      });
      req.setTimeout(10000, function () { try { req.destroy(); } catch (e) { } });
      req.on('error', function (e) { note('could not reach the site: ' + e.message); });
    } catch (e) { note('refresh failed: ' + e); }
  }

  var g = (typeof globalThis !== 'undefined') ? globalThis : this;
  if (g.__thornswoodDoorRefresh) { try { clearInterval(g.__thornswoodDoorRefresh); } catch (e) { } }
  g.__thornswoodDoorRefresh = setInterval(function () {
    try { refresh(); } catch (e) { note('refresh threw: ' + e); }
  }, 300000);
  try { refresh(); } catch (e) { }

  if (g.__thornswoodDoorTimer) { try { clearInterval(g.__thornswoodDoorTimer); } catch (e) { } }
  g.__thornswoodDoorTimer = setInterval(function () {
    try { tick(); } catch (e) { note('tick failed: ' + e); }
  }, 2000);

  var first = load();
  if (first) {
    console.log('[thornswood door] ' + (first.enforce ? 'ENFORCING' : 'watching only') +
                ', ' + first.count + ' profiles allowed');
  } else {
    console.log('[thornswood door] no ' + FILE + ', the door is off and anybody can connect');
  }
})();
// ==== end thornswood door ====

// ==== thornswood server manifest ====
// -------------------------------------------------------------- manifest ---
// Where the client looks for the load order it is supposed to match.
//
// loadOrderVerificationService asks for
//
//     <master>/api/servers/<masterKey>/manifest.json
//
// and getMasterUrl falls back to https://gateway.skymp.net when the client's
// "master" setting is empty, while getServerMasterKey falls back to
// "<server-ip>:<port>". So an unregistered private server sends every person
// who presses Play to skymp.net asking about an address skymp.net has never
// heard of. Five attempts, five 404s, and an empty list comes back.
//
// An empty list is not treated as an error. The count check sees 61 against 0,
// prints the yellow "you have more mods than server" message for five seconds,
// and then the comparison loop runs over zero entries and passes. The load
// order has therefore never actually been checked on this server: the warning
// everybody has been ignoring was a failed lookup, and the check it belongs to
// was doing nothing at all.
//
// The server already writes the real thing. manifestGen.generateManifest runs
// at startup and puts filename, size and crc32 for every plugin in the load
// order into data/manifest.json, which koa-static serves. It is simply not at
// the path the client asks for. So it is published there as well.
//
// Filtered to plugins on the way past. The client compares this array
// POSITIONALLY against Game.getModName, which is plugins only, so a single bsa
// entry shifts everything after it and turns a healthy install into a red load
// order error. manifestGen only adds a bsa when one sits in dataDir, which is
// not where this setup keeps them, but the cost of being sure is one test.
(function () {
  var fs = null, path = null;
  try { fs = require('fs'); path = require('path'); } catch (e) { return; }
  if (!fs || !path) return;

  // Matches what the launcher writes into skymp5-client-settings.txt as
  // "server-master-key". A name rather than an address: this path ends up on
  // disk, and a colon is not allowed in a Windows file name.
  var KEY = 'thornswood';

  var dataDir = 'data';
  try {
    var cfg = JSON.parse(fs.readFileSync('server-settings.json', 'utf8'));
    if (cfg && cfg.dataDir) dataDir = String(cfg.dataDir);
  } catch (e) { }

  var SRC = path.join(dataDir, 'manifest.json');
  var DIR = path.join(dataDir, 'api', 'servers', KEY);
  var DST = path.join(DIR, 'manifest.json');

  var PLUGIN = /\.(esp|esm|esl)$/i;

  function publish() {
    var doc;
    try {
      doc = JSON.parse(fs.readFileSync(SRC, 'utf8'));
    } catch (e) {
      return false;   // not written yet, or not readable
    }
    if (!doc || !Array.isArray(doc.mods)) return false;

    var mods = doc.mods.filter(function (m) {
      return m && typeof m.filename === 'string' && PLUGIN.test(m.filename);
    });

    var out = {
      versionMajor: doc.versionMajor || 1,
      mods: mods,
      loadOrder: Array.isArray(doc.loadOrder) ? doc.loadOrder : mods.map(function (m) { return m.filename; })
    };

    try {
      fs.mkdirSync(DIR, { recursive: true });
      fs.writeFileSync(DST, JSON.stringify(out));
    } catch (e) {
      console.log('[thornswood] could not publish the manifest: ' + e.message);
      return false;
    }

    var dropped = doc.mods.length - mods.length;
    console.log('[thornswood] load order manifest published at /api/servers/' + KEY +
                '/manifest.json, ' + mods.length + ' plugins' +
                (dropped > 0 ? ' (' + dropped + ' archive entries left out)' : ''));
    try { publishFiles(mods); } catch (e) { console.log('[thornswood] could not publish the plugin files: ' + e.message); }
    return true;
  }

  // The files themselves, beside the manifest, for the launcher's Fix.
  //
  // A plugin with the right name in the right place and the wrong bytes paints
  // LOAD ORDER ERROR over somebody's screen for the whole session (17 Sep), and
  // nothing on that machine can put the right bytes there: the collection gave
  // it the build it had. This box has the exact files the manifest describes,
  // so they are served under
  //
  //     /api/servers/thornswood/plugins/<file>
  //
  // as hard links into the plugins folder, so there is no second copy on disk
  // (a copy when a link is refused). Relinked at every start, because a deploy
  // may have replaced the file behind the link. The five Bethesda masters stay
  // out: the client never compares their bytes and Steam owns them.
  var STOREFRONT = { 'skyrim.esm': 1, 'update.esm': 1, 'dawnguard.esm': 1, 'hearthfires.esm': 1, 'dragonborn.esm': 1 };

  function publishFiles(mods) {
    var order = [];
    try { order = JSON.parse(fs.readFileSync('server-settings.json', 'utf8')).loadOrder || []; } catch (e) { return; }
    var byName = {};
    for (var i = 0; i < order.length; i++) {
      byName[path.basename(String(order[i])).toLowerCase()] = String(order[i]);
    }
    var PLUG = path.join(DIR, 'plugins');
    try { fs.mkdirSync(PLUG, { recursive: true }); } catch (e) { }
    // Clear what a previous start left here. 1.1.43 published these under their
    // real names, and the resources server refuses any file whose name contains
    // .esp, .esm or .esl (a 403), so those never served. The name is gone now:
    // each file is served as its position in the manifest with a .bin
    // extension, which the resources server does hand over. The launcher
    // fetches /plugins/<index>.bin for the manifest entry at that index.
    try {
      var stale = fs.readdirSync(PLUG);
      for (var s = 0; s < stale.length; s++) { try { fs.unlinkSync(path.join(PLUG, stale[s])); } catch (e) { } }
    } catch (e) { }
    var linked = 0, copied = 0, missing = 0, bytes = 0;
    for (var j = 0; j < mods.length; j++) {
      var name = mods[j].filename;
      if (STOREFRONT[name.toLowerCase()]) continue;
      var src = byName[name.toLowerCase()];
      if (!src || !fs.existsSync(src)) { missing++; continue; }
      var dst = path.join(PLUG, j + '.bin');
      try {
        fs.linkSync(src, dst);
        linked++;
      } catch (e) {
        try { fs.copyFileSync(src, dst); copied++; }
        catch (e2) { missing++; console.log('[thornswood] could not publish ' + name + ': ' + e2.message); continue; }
      }
      bytes += Number(mods[j].size) || 0;
    }
    console.log('[thornswood] ' + (linked + copied) + ' plugin files published at /api/servers/' + KEY +
                '/plugins/ for the launcher, ' + Math.round(bytes / 1048576) + ' MB' +
                (copied ? ', ' + copied + ' copied rather than linked' : '') +
                (missing ? ', ' + missing + ' not found on this box' : ''));
  }

  if (publish()) return;

  // generateManifest runs before the gamemode is loaded, so this should not be
  // needed. It costs nothing to be wrong about that.
  var tries = 0;
  var again = setInterval(function () {
    if (publish() || ++tries > 20) clearInterval(again);
  }, 1000);
})();
// ==== end thornswood server manifest ====


// ==== thornswood progression ====
/*
  The rulebook, as data and as rules. Patrick, 20 September.

  This block owns what a character IS: their class, their profession and the
  half of it they work, their rank in each thing they know, their spell points,
  and their attribute tree. Nothing else in the gamemode decides any of that,
  and nothing on the client does either. The client draws the table this block
  sends it and sends back what was picked; every yes and every no is decided
  here, because a client that decided any of it would be a client anybody
  could edit.

  Two halves. TABLE is the rulebook transcribed, and it is the one copy: the
  client's panel carries a default of the same shape only so it draws
  something before the server has spoken, and setData replaces it wholesale.
  RULES is a set of pure functions over a character's state. They take a state
  and an action and hand back either a new state or a reason, and they touch
  nothing else, which is what makes them testable by lifting them out.

  ON THE FLAT SIXTEEN. The old CHARGEN table has sixteen trades with a kit
  each, and five of them, bard, merchant, priest, scholar and thief, have no
  home in the rulebook. Characters exist carrying them. Nothing here deletes
  that: the old class key stays on the actor untouched, and in THIS system
  such a character simply has nothing chosen yet and is asked, the same as a
  new one. What those five become is a decision for the list, entry 6, and
  this block does not make it.
*/
(function () {
  'use strict';
  var g = (typeof globalThis !== 'undefined') ? globalThis : this;

  // ------------------------------------------------------------ the table --
  var RANKS = ['novice', 'advanced', 'expert', 'master'];

  var CLASSES = {
    hunter:   { name: 'Hunter',   only: 'loot an animal body' },
    fisher:   { name: 'Fisher',   only: 'catch fish' },
    gatherer: { name: 'Gatherer', only: 'harvest flora and materials out of the world' },
    miner:    { name: 'Miner',    only: 'mine ore veins' },
    farmer:   { name: 'Farmer',   only: 'plant and harvest crops' }
  };

  var SCHOOLS = ['destruction', 'restoration', 'alteration', 'conjuration', 'illusion'];

  var PROFESSIONS = {
    warrior:    { name: 'Warrior',    halves: { bulwark: 'Bulwark', berserker: 'Berserker' },
                  perk: { key: 'warlord', name: 'Warlord' } },
    mage:       { name: 'Mage',       halves: null, schools: 2, mastered: 3,
                  perk: { key: 'archmage', name: 'Archmage' } },
    alchemist:  { name: 'Alchemist',  halves: { blightbrewer: 'Blightbrewer', physicker: 'Physicker' },
                  perk: { key: 'masterchemist', name: 'Master Chemist' } },
    cook:       { name: 'Cook',       halves: { hearthcook: 'Hearthcook', confectioner: 'Confectioner' },
                  perk: { key: 'grandchef', name: 'Grand Chef' } },
    smith:      { name: 'Smith',      halves: { platewright: 'Platewright', edgewright: 'Edgewright' },
                  perk: { key: 'mastercraft', name: 'Mastercraft' } },
    enchanter:  { name: 'Enchanter',  halves: { bladebinder: 'Bladebinder', wardweaver: 'Wardweaver' },
                  perk: { key: 'twinsouls', name: 'Twin Souls' } },
    tailor:     { name: 'Tailor',     halves: { liverywright: 'Liverywright', haberdasher: 'Haberdasher' },
                  perk: { key: 'masterweaver', name: 'Master Weaver' } },
    woodworker: { name: 'Woodworker', halves: { charburner: 'Charburner', woodwright: 'Woodwright' },
                  perk: { key: 'mastercarver', name: 'Master Carver' } }
  };

  var TREE = {
    health:  { name: 'Health',  skills: {
      vitality:   { name: 'Vitality',   perk: 'cheatdeath' },
      fortitude:  { name: 'Fortitude',  perk: 'trollsblood' },
      might:      { name: 'Might',      perk: 'devastatingblow' },
      resilience: { name: 'Resilience', perk: 'unshakeable' },
      toughness:  { name: 'Toughness',  perk: 'purifiedblood' } } },
    magicka: { name: 'Magicka', skills: {
      capacity:   { name: 'Capacity',   perk: 'archmagesvessel' },
      clarity:    { name: 'Clarity',    perk: 'leylineattunement' },
      potency:    { name: 'Potency',    perk: 'overcharge' },
      ward:       { name: 'Ward',       perk: 'spellbreaker' },
      efficiency: { name: 'Efficiency', perk: 'fontofmagic' } } },
    stamina: { name: 'Stamina', skills: {
      endurance:  { name: 'Endurance',  perk: 'tireless' },
      vigor:      { name: 'Vigor',      perk: 'secondwind' },
      agility:    { name: 'Agility',    perk: 'windwalker' },
      burden:     { name: 'Burden',     perk: 'packmule' },
      precision:  { name: 'Precision',  perk: 'lethalaim' } } }
  };

  /*
    Numbers the rulebook gives, and one it does not.

    SKILL_CAP is how many points fill a sub-skill and grant its perk. The
    rulebook says "maxing out" and no number, so this is a placeholder to be
    set by Patrick; every rule below reads it from here and nowhere else.
  */
  var LIMITS = {
    secondaries: 2,       // novice in at most two other professions' halves
    mageStartSpells: 2,   // spell points a mage begins with
    mageMasterSpells: 2,  // more at Master, alongside the third school
    collegeSemester: 2,   // points a mage earns per semester at the College
    outsiderSemester: 1,  // points a non-mage earns per semester, novice only
    outsiderSpells: 2,    // the most spells a non-mage can ever hold
    skillCap: 5           // NOT IN THE RULEBOOK. Placeholder, see above.
  };

  var TABLE = { ranks: RANKS, classes: CLASSES, schools: SCHOOLS,
                professions: PROFESSIONS, tree: TREE, limits: LIMITS };

  // ------------------------------------------------------------ the state --
  /*
    What is stored on the actor. Every field optional; a missing one means
    "not yet". Kept flat and JSON-plain because it goes through mp.set.

      cls        'hunter' | ...                 set once
      prof       'smith' | ...                  set once
      half       'platewright' | ...            set once; a mage has none
      schools    ['destruction','restoration']  a mage's chosen schools
      ranks      { platewright: 'advanced', edgewright: 'novice', ... }
                 every half this character has any standing in, own or taught.
                 The sister half is added at novice the moment half is chosen.
      taught     ['hearthcook']                 halves learned from a Master
                 of another profession, novice only, at most LIMITS.secondaries
      spells     { points: 2, known: [...] }    a mage's spell points and spells
      tree       { vitality: 3, ... }           points spent per sub-skill
      points     4                              unspent tree points
  */
  function fresh() {
    return { cls: null, prof: null, half: null, schools: [],
             ranks: {}, taught: [], spells: null, tree: {}, points: 0 };
  }

  function clone(s) { return JSON.parse(JSON.stringify(s || fresh())); }

  function no(why) { return { ok: false, why: why }; }
  function yes(state) { return { ok: true, state: state }; }

  function halvesOf(prof) {
    var p = PROFESSIONS[prof];
    if (!p) { return []; }
    if (p.halves) { return Object.keys(p.halves); }
    return SCHOOLS.slice();
  }

  function sisterOf(prof, half) {
    var hs = halvesOf(prof);
    if (hs.length !== 2) { return null; }
    return hs[0] === half ? hs[1] : hs[0];
  }

  function rankIndex(r) { return RANKS.indexOf(r); }

  // ------------------------------------------------------------ the rules --

  /** One class, from the five, and it is never changed. */
  function pickClass(state, cls) {
    var s = clone(state);
    if (!CLASSES[cls]) { return no('no such class'); }
    if (s.cls) { return no('you already have a class, and nobody has two'); }
    s.cls = cls;
    return yes(s);
  }

  /**
    One profession and one half of it, in one step, because the half is not
    a flavour. A mage picks schools instead of a half, exactly two of them.
    The sister half arrives at novice for nothing; the chosen half starts at
    novice too, because everybody does.
  */
  function pickProfession(state, prof, halfOrSchools) {
    var s = clone(state);
    var p = PROFESSIONS[prof];
    if (!p) { return no('no such profession'); }
    if (s.prof) { return no('you already have a profession, and nobody has two'); }

    if (prof === 'mage') {
      var sch = Array.isArray(halfOrSchools) ? halfOrSchools.slice() : [];
      if (sch.length !== p.schools) { return no('a mage picks ' + p.schools + ' schools'); }
      for (var i = 0; i < sch.length; i++) {
        if (SCHOOLS.indexOf(sch[i]) === -1) { return no('no such school: ' + sch[i]); }
        if (sch.indexOf(sch[i]) !== i) { return no('the same school twice'); }
      }
      s.prof = 'mage';
      s.half = null;
      s.schools = sch;
      for (var j = 0; j < sch.length; j++) { s.ranks[sch[j]] = 'novice'; }
      s.spells = { points: LIMITS.mageStartSpells, known: [] };
      return yes(s);
    }

    var half = String(halfOrSchools || '');
    if (!p.halves[half]) { return no('no such half of ' + p.name); }
    s.prof = prof;
    s.half = half;
    s.ranks[half] = 'novice';
    var sister = sisterOf(prof, half);
    if (sister) { s.ranks[sister] = 'novice'; }
    return yes(s);
  }

  /**
    A Master of a half teaches somebody from ANOTHER profession that half, at
    novice, and never further. At most LIMITS.secondaries times. The sister
    half does not count and cannot be taught this way, because it is already
    known; going past novice in it is rankUp under a Master of it, below.
  */
  function teach(state, teacherState, half) {
    var s = clone(state);
    if (!s.prof) { return no('choose your own profession before learning anybody else’s'); }
    var tp = teacherState && teacherState.prof;
    if (!tp || halvesOf(tp).indexOf(half) === -1) { return no('the teacher does not work that half'); }
    if (teacherState.ranks[half] !== 'master') { return no('only a Master can teach, and they are not one in that half'); }
    if (halvesOf(s.prof).indexOf(half) !== -1) {
      return no('that is your own profession; a Master of it can raise your rank, not teach you the basics');
    }
    if (s.taught.indexOf(half) !== -1) { return no('you already know that'); }
    if (s.taught.length >= LIMITS.secondaries) {
      return no('you may only learn ' + LIMITS.secondaries + ' other trades, and you have');
    }
    s.taught.push(half);
    s.ranks[half] = 'novice';
    return yes(s);
  }

  /**
    Rank goes up one step in a half. Only ever one step, only in a half the
    character has standing in. Three ceilings: a taught half never leaves
    novice; the sister half needs a Master of it to go past novice; and a
    mage's third school and extra points arrive with Master.

    Who is allowed to CALL this is the server's business, when the work has
    been done. This only says whether the step itself is legal.
  */
  function rankUp(state, half, masterState) {
    var s = clone(state);
    var cur = s.ranks[half];
    if (!cur) { return no('no standing in that'); }
    if (cur === 'master') { return no('already a Master'); }
    if (s.taught.indexOf(half) !== -1) { return no('a trade learned from another profession never goes past novice'); }

    var own = s.half === half || s.schools.indexOf(half) !== -1;
    var sister = s.prof && sisterOf(s.prof, s.half) === half;
    if (sister && !own) {
      var ok = masterState && masterState.ranks && masterState.ranks[half] === 'master';
      if (!ok) { return no('past novice in your sister half needs a Master of it to take you on'); }
    }

    var next = RANKS[rankIndex(cur) + 1];
    s.ranks[half] = next;

    if (s.prof === 'mage' && own && next === 'master') {
      s.spells.points += LIMITS.mageMasterSpells;
    } else if (s.prof === 'mage' && own) {
      s.spells.points += 1;   // one more spell point with every rank
    }
    return yes(s);
  }

  /** A mage at Master picks the third school. Once. */
  function pickThirdSchool(state, school) {
    var s = clone(state);
    if (s.prof !== 'mage') { return no('not a mage'); }
    if (SCHOOLS.indexOf(school) === -1) { return no('no such school'); }
    if (s.schools.indexOf(school) !== -1) { return no('already one of yours'); }
    if (s.schools.length >= PROFESSIONS.mage.mastered) { return no('a mage holds ' + PROFESSIONS.mage.mastered + ' schools at most'); }
    var isMaster = false;
    for (var i = 0; i < s.schools.length; i++) { if (s.ranks[s.schools[i]] === 'master') { isMaster = true; } }
    if (!isMaster) { return no('the third school comes with Master'); }
    s.schools.push(school);
    s.ranks[school] = 'novice';
    return yes(s);
  }

  /** One point into one sub-skill. The perk is derived, not stored. */
  function spendPoint(state, skill) {
    var s = clone(state);
    var found = null;
    for (var attr in TREE) { if (TREE[attr].skills[skill]) { found = TREE[attr].skills[skill]; } }
    if (!found) { return no('no such sub-skill'); }
    if (s.points <= 0) { return no('no points to spend'); }
    var have = s.tree[skill] || 0;
    if (have >= LIMITS.skillCap) { return no('that one is full'); }
    s.tree[skill] = have + 1;
    s.points -= 1;
    return yes(s);
  }

  /** Every perk this character holds right now, from state alone. */
  function perks(state) {
    var out = [];
    var s = state || fresh();
    if (s.prof && s.ranks) {
      var p = PROFESSIONS[s.prof];
      var own = s.half ? [s.half] : (s.schools || []);
      for (var i = 0; i < own.length; i++) {
        if (s.ranks[own[i]] === 'master' && p && p.perk) { out.push(p.perk.key); break; }
      }
    }
    for (var attr in TREE) {
      for (var k in TREE[attr].skills) {
        if ((s.tree && s.tree[k]) >= LIMITS.skillCap) { out.push(TREE[attr].skills[k].perk); }
      }
    }
    return out;
  }

  /**
    Can this character do this half's work at this rank. The one question
    every crafting and gathering gate asks. A taught half answers yes only at
    novice; anything they have no standing in answers no.
  */
  function canWork(state, half, rank) {
    var s = state || fresh();
    var have = s.ranks && s.ranks[half];
    if (!have) { return false; }
    return rankIndex(have) >= rankIndex(rank || 'novice');
  }

  /** The class verbs. The only question the five gates ask. */
  function canDo(state, verb) {
    var s = state || fresh();
    var by = { loot: 'hunter', fish: 'fisher', harvest: 'gatherer', mine: 'miner', farm: 'farmer' };
    return !!s.cls && s.cls === by[verb];
  }

  g.__thornswoodProgression = {
    TABLE: TABLE, fresh: fresh, clone: clone,
    pickClass: pickClass, pickProfession: pickProfession, teach: teach,
    rankUp: rankUp, pickThirdSchool: pickThirdSchool, spendPoint: spendPoint,
    perks: perks, canWork: canWork, canDo: canDo,
    halvesOf: halvesOf, sisterOf: sisterOf
  };
})();
// ==== end thornswood progression ====

// ==== thornswood character ====
/*
  What a character IS, held in one place and pushed to the one screen that
  shows it.

  The rules above decide every yes and no. This block decides nothing; it
  stores the answer on the actor as 'thornswoodCharacter', turns a /pick or a
  /spend into a call on the rules, and tells the person why when the answer
  is no. It is the only writer of that property.

  THE CHANNEL TO THE PANEL is the property's updateOwner script, and it is the
  only one there is. A visible custom property reaches the client solely
  through that script, run inside skymp5-client with ctx.sp, ctx.value and
  ctx.state; there is no other reader. Until 20 September no property here
  had one, which is why the K panel could draw the rulebook and never learn a
  thing about the person in front of it. The script here hands ctx.value to
  window.thornswoodSkills.setData through executeJavaScript, and a panel that
  mounts after the first write asks for it again with /pick refresh.

  THE OLD KEYS. Characters made through the launcher carry state.class (the
  trade), state.half and state.gathering on thornswoodChargen, in the
  launcher's own names: tank, brawler, harm, mend, dinner, dessert, armour,
  weapons, weapon, apparel, robes, common. The rulebook's names are the ones
  on the public page and the ones the rules use, so the launcher's are mapped
  on first sight and never written back. Five old trades have no home in the
  rulebook, bard, merchant, priest, scholar, thief: a character carrying one
  keeps it on the old property untouched and starts this system with no
  profession, the same as somebody new. That is entry 6's decision to make
  and this block does not make it.
*/
(function () {
  'use strict';
  var g = (typeof globalThis !== 'undefined') ? globalThis : this;
  var P = g.__thornswoodProgression;
  if (!P) { console.log('[thornswood character] the rules block is missing, nothing registered'); return; }

  var CHAR_PROPERTY = 'thornswoodCharacter';

  function clog() {
    var a = Array.prototype.slice.call(arguments);
    console.log('[thornswood character] ' + a.join(' '));
  }

  // The launcher's half names, and the trades that map straight across.
  var HALF_MAP = {
    tank: 'bulwark', brawler: 'berserker',
    harm: 'blightbrewer', mend: 'physicker',
    dinner: 'hearthcook', dessert: 'confectioner',
    armour: 'platewright', weapons: 'edgewright',
    weapon: 'bladebinder', apparel: 'wardweaver',
    robes: 'liverywright', common: 'haberdasher'
  };

  function mapHalf(h) {
    h = String(h || '').toLowerCase();
    if (!h) { return ''; }
    if (HALF_MAP[h]) { return HALF_MAP[h]; }
    return h;   // already a rulebook name, or unknown and refused below
  }

  /*
    What the panel is told. Not the whole state: the panel marks what is
    yours and shows rank and points, and nothing on the client needs more.
  */
  function forPanel(s, creating) {
    if (!s) { return null; }
    var chargen = g.__thornswoodChargen;
    return {
      profession: s.prof || null,
      'class': s.cls || null,
      half: s.half || null,
      schools: s.schools || [],
      ranks: s.ranks || {},
      tree: s.tree || {},
      points: s.points || 0,
      perks: P.perks(s),
      home: s.home || null,
      // The last refusal, so the panel can say why under itself. The chat
      // line says the same; the panel cannot read the chat.
      note: s.note || null,
      // While creating, the panel opens itself and shows the town list; the
      // moment the home is chosen this flips and the panel closes.
      creating: !!creating,
      towns: (creating && chargen) ? chargen.towns() : []
    };
  }

  /*
    The client side script. It runs inside skymp5-client every time the
    property changes for its owner, with ctx.value the new value. While the
    server says creating, it also opens the panel, which is how creation
    lands on somebody's screen without them pressing anything. Everything
    it does is guarded, because a page that has not mounted the panel yet is
    the normal case for the first second of a session.
  */
  function updateOwnerScript() {
    return [
      '(function(){',
      '  try {',
      '    var v = ctx.value;',
      '    if (!v || typeof v !== "object") { return; }',
      '    var open = (v.panel && v.panel.creating) ? "window.thornswoodSkills.open();" : "";',
      '    var src = "try{if(window.thornswoodSkills){window.thornswoodSkills.setData(null," + JSON.stringify(v) + ");" + open + "}}catch(e){}";',
      '    ctx.sp.browser.executeJavaScript(src);',
      '  } catch (e) { }',
      '})();'
    ].join('\n');
  }

  try {
    mp.makeProperty(CHAR_PROPERTY, {
      isVisibleByOwner: true,
      isVisibleByNeighbors: false,
      updateOwner: updateOwnerScript(),
      updateNeighbor: ''
    });
    clog('property registered with an updateOwner script,', updateOwnerScript().length, 'chars');
  } catch (e) {
    // already made by a previous load; the script cannot be changed after
    // the fact, so a changed script needs a server restart, which a deploy is.
  }

  function readState(actorId) {
    var v = null;
    try { v = mp.get(actorId, CHAR_PROPERTY); } catch (e) { v = null; }
    if (v && typeof v === 'object' && v.v === 1) { return v; }
    return null;
  }

  function writeState(actorId, s) {
    s.v = 1;
    // forPanel is what the client sees; the rules state is what is stored.
    // Both travel in the one property so the panel never sees a half state.
    var chargen = g.__thornswoodChargen;
    s.panel = forPanel(s, !!(chargen && chargen.isChoosing(actorId)));
    try { mp.set(actorId, CHAR_PROPERTY, s); } catch (e) { clog('could not write', actorId.toString(16), e); }
    return s;
  }

  /*
    First sight of an actor with no character state: build one from the old
    chargen fields if they are there. Each old key is applied through the
    rules, so an old value the rules refuse is simply not carried, and the
    log says which.
  */
  function migrate(actorId) {
    var s = P.fresh();
    var old = null;
    try { old = mp.get(actorId, 'thornswoodChargen'); } catch (e) { old = null; }
    if (old && typeof old === 'object') {
      var trade = String(old['class'] || '').toLowerCase();
      var half = mapHalf(old.half);
      var gathering = String(old.gathering || '').toLowerCase();
      var r;
      if (gathering) {
        r = P.pickClass(s, gathering);
        if (r.ok) { s = r.state; } else { clog('migrate', actorId.toString(16), 'old class', gathering, 'refused:', r.why); }
      }
      if (trade && P.TABLE.professions[trade]) {
        if (trade === 'mage') {
          clog('migrate', actorId.toString(16), 'was a mage under the old keys; schools were never recorded, so they will be asked for');
        } else if (half) {
          r = P.pickProfession(s, trade, half);
          if (r.ok) { s = r.state; } else { clog('migrate', actorId.toString(16), 'old trade', trade, half, 'refused:', r.why); }
        } else {
          clog('migrate', actorId.toString(16), 'old trade', trade, 'had no half recorded, so it will be asked for');
        }
      } else if (trade) {
        clog('migrate', actorId.toString(16), 'old trade', trade, 'has no home in the rulebook; left on the old property, nothing chosen here');
      }
    }
    return writeState(actorId, s);
  }

  function stateOf(actorId) {
    return readState(actorId) || migrate(actorId);
  }

  /*
    The commands. Called from handle() in the chat block with the same
    arguments it has, so the profile id is the one the voice service stamped
    from the connection and not a number in the text.

      /pick refresh                      send the panel what it already is
      /pick class hunter
      /pick profession smith platewright
      /pick profession mage destruction,restoration
      /pick town riften                  while creating, and never after
      /pick spend vitality               the panel's spelling of /spend
      /spend vitality

    Returns true when the word was one of these, so handle() stops.

    Creation is these same picks. Somebody whose chargen stage is choosing is
    standing in the hall with the panel open; the moment a home is set, arrive
    sends them to the town and the panel closes on the next property write.
    Class and profession can be set there too, or later in the world, since
    only a second pick of either is refused. Nothing else moves anybody.
  */
  function command(word, parts, actorId, profileId, toProfile) {
    if (word !== '/pick' && word !== '/spend') { return false; }
    if (!actorId) {
      toProfile(profileId, 'The server cannot find your character right now. Give it a moment and try again.');
      return true;
    }
    var s = stateOf(actorId);
    var chargen = g.__thornswoodChargen;
    var creating = !!(chargen && chargen.isChoosing(actorId));
    var r = null;

    if (word === '/pick') {
      var what = String(parts[1] || '').toLowerCase();
      if (what === 'refresh') {
        writeState(actorId, s);   // the write is what fires updateOwner
        return true;
      }
      if (what === 'class') {
        r = P.pickClass(s, String(parts[2] || '').toLowerCase());
      } else if (what === 'profession') {
        var prof = String(parts[2] || '').toLowerCase();
        var rest = String(parts[3] || '').toLowerCase();
        r = (prof === 'mage')
          ? P.pickProfession(s, prof, rest ? rest.split(',') : [])
          : P.pickProfession(s, prof, mapHalf(rest));
      } else if (what === 'town') {
        var town = String(parts[2] || '').toLowerCase();
        if (!creating) {
          r = { ok: false, why: 'your home is already chosen' };
        } else if (!chargen.hasTown(town)) {
          r = { ok: false, why: 'no such town' };
        } else {
          var s2 = P.clone(s);
          s2.home = town;
          r = { ok: true, state: s2 };
        }
      } else if (what === 'spend') {
        r = P.spendPoint(s, String(parts[2] || '').toLowerCase());
      } else {
        toProfile(profileId, 'Pick what? class, profession or town.');
        return true;
      }
    } else {
      r = P.spendPoint(s, String(parts[1] || '').toLowerCase());
    }

    if (!r.ok) {
      toProfile(profileId, 'No: ' + r.why + '.');
      // The same word to the panel, through the property, since a refusal
      // changes nothing else and the panel would otherwise sit on 'Sent'.
      s.note = { text: r.why, at: Date.now() };
      writeState(actorId, s);
      clog(word, parts.slice(1).join(' '), 'for', actorId.toString(16), 'refused:', r.why);
      return true;
    }
    r.state.note = null;
    var st = writeState(actorId, r.state);
    clog(word, parts.slice(1).join(' '), 'for', actorId.toString(16), 'accepted');

    // The home is the one pick that ends creation. Class and profession may
    // still be unset: they are picked in the world, from the same panel, and
    // the rules (pickClass, pickProfession) refuse only a second one.
    if (creating && st.home) {
      if (chargen.arrive(actorId, st.home)) {
        // Written again so the panel hears creating is over and closes.
        writeState(actorId, st);
        clog('creation finished for', actorId.toString(16) + ':', (st.cls || 'no class yet') + ',',
             (st.prof ? st.prof + (st.half ? '/' + st.half : '') + (st.schools && st.schools.length ? '/' + st.schools.join('+') : '') : 'no profession yet') +
             ', home', st.home);
      }
    }
    return true;
  }

  /*
    The hall calls this when the face is made and on every reminder: one
    property write with creating on, which the client script turns into the
    panel opening. Nothing to decide here; the state is whatever it was.
  */
  function beginCreation(actorId) {
    writeState(actorId, stateOf(actorId));
  }

  g.__thornswoodCharacter = {
    PROPERTY: CHAR_PROPERTY, stateOf: stateOf, writeState: writeState,
    forPanel: forPanel, mapHalf: mapHalf, migrate: migrate, command: command,
    beginCreation: beginCreation, updateOwnerScript: updateOwnerScript
  };
  clog('ready');
})();
// ==== end thornswood character ====

// ==== thornswood chat commands ====
// ---------------------------------------------------------------------------
// A teleport that actually teleports.
//
// coc does nothing on this server and never did. SkyMP's client forwards
// exactly five console commands to the server, in
// consoleCommandsService.ts: additem, equipitem, placeatme, disable and mp.
// Everything else, coc and tcl and setstage included, runs in your own game
// and is never sent anywhere, so the server carries on believing you are where
// it put you and moves you back on the next position update. There is no
// setting for this and no way to add a sixth command without recompiling the
// client.
//
// So the teleport is a chat command instead. Chat rides the voice service's
// socket, the voice service now holds any line starting with a slash in a
// queue, and this collects that queue over the loopback trip it was already
// making for the launcher's choices.
//
// /where is the other half. It prints the cell, the position and the angle you
// are standing at, which is what the console was being used for.
// ---------------------------------------------------------------------------
(function () {
  'use strict';

  /*
    A hot reload replaces this block rather than being turned away by it.

    This used to return early when it had already run, which kept an in flight
    countdown alive but meant every edit to a command sat in the file doing
    nothing until somebody restarted the server. The countdown is the only
    thing here worth keeping across a reload, so it lives on globalThis and
    survives on its own, and the timer at the bottom clears the old one before
    arming a new one. Everything else is functions, and replacing those is the
    point of a reload.
  */
  var g = globalThis;

  var VOICE_PORT = voicePort();

  function post(path, payload) {
    var http;
    try { http = require('http'); } catch (e) { return; }
    var body = JSON.stringify(payload);
    var req = http.request({
      host: '127.0.0.1', port: VOICE_PORT, path: path, method: 'POST', timeout: 2000,
      headers: { 'content-type': 'application/json',
                 'content-length': Buffer.byteLength(body) }
    }, function () { });
    req.on('error', function () { });
    req.on('timeout', function () { req.destroy(); });
    req.end(body);
  }

  /** A line in the chat, to one person. */
  // How far out of character talk carries. About the length of a longhouse,
  // which is roughly the group a scene has in it.
  var OOC_RANGE = 4000;

  function toProfile(profileId, text) {
    post('/say', { profileId: profileId, text: text });
  }

  /*
    actorId for a connected profile, or 0.

    "The server cannot find your character right now" was reported often
    enough to be the normal answer rather than the rare one, and this is why.
    The sweep is the only lookup, it runs on the tick the line arrives, and
    three separate things make it come back empty for somebody who is plainly
    standing in the world:

      - onlinePlayers is read inside a try that returns 0 on a throw, so one
        bad read loses the whole list rather than one entry;
      - mp.get(id, 'profileId') has its own try that turns a throw into 0, and
        an actor part way through spawning throws there;
      - a chat line composed while the character is being moved or re-created
        arrives in the gap where the actor exists but is not yet listed.

    So the answer is remembered. Every successful sweep records it, and a
    sweep that finds nothing falls back to the last actor seen for that
    profile, confirmed by asking that actor who it belongs to. If the actor is
    gone the confirm throws and the fallback is dropped, so this cannot hand
    back a stale character: it only covers the gap where the sweep is blind and
    the actor is still there.
  */
  // On globalThis, so a hot reload does not forget who everybody was and put
  // the gap straight back.
  if (!globalThis.__thornswoodLastActor) { globalThis.__thornswoodLastActor = {}; }
  var lastActor = globalThis.__thornswoodLastActor;

  function actorOf(profileId) {
    var online = [];
    try { online = mp.get(0, 'onlinePlayers') || []; } catch (e) { online = []; }
    for (var i = 0; i < online.length; i++) {
      var id = online[i];
      var pid = 0;
      try { pid = Number(mp.get(id, 'profileId')) || 0; } catch (e) { pid = 0; }
      if (pid === profileId) { lastActor[profileId] = id; return id; }
    }

    var had = lastActor[profileId];
    if (had) {
      var still = 0;
      try { still = Number(mp.get(had, 'profileId')) || 0; } catch (e) { still = 0; }
      if (still === profileId) { return had; }
      delete lastActor[profileId];
    }
    return 0;
  }

  /** key -> the arrival point the launcher would have used. */
  function places() {
    var out = {};
    for (var d in PASSAGES) {
      var t = PASSAGES[d];
      if (!t || !t.arrival) { continue; }
      out[t.key] = { desc: t.arrival.desc, pos: t.arrival.pos, rot: t.arrival.rot,
                     town: t.town };
    }
    out.hall = { desc: HALL.desc, pos: HALL.pos, rot: HALL.rot, town: 'the creation hall' };
    return out;
  }

  function round1(v) { return Math.round(Number(v) * 10) / 10; }

  function handle(cmd) {
    var profileId = Number(cmd.profileId) || 0;
    if (!profileId) { return; }

    var parts = String(cmd.text || '').trim().split(/\s+/);
    var word = parts[0].toLowerCase();
    var arg = (parts[1] || '').toLowerCase();

    /*
      A missing character no longer refuses every command.

      This used to stop the dispatcher before it had read the word, so a lookup
      that came back empty answered "The server cannot find your character
      right now" to /help and to /tp with no argument, neither of which needs a
      character at all. Now the commands that need one say so where they need
      it, and the message says what to do about it.
    */
    var actorId = actorOf(profileId);
    function needCharacter() {
      if (actorId) { return true; }
      toProfile(profileId,
        'The server cannot find your character right now. Give it a moment and ' +
        'try again; if it keeps saying that, say so and what you were doing.');
      return false;
    }

    // A lockpick that broke in somebody's game.
    //
    // Not a human command. The plugin sends it, so it answers nothing, says
    // nothing back, and is deliberately absent from the help text.
    //
    // The server owns the pack. Skyrim destroys the pick in the person's own
    // game and the server never hears about it, so the next inventory re-apply
    // hands it straight back. That is why picks were endless and why a lock
    // could be worked forever. There is no message for this: all 34 types in
    // the protocol were read and none of them say an item was destroyed, so
    // the only route a fact has from a person's game to here is this queue.
    //
    // The profile id is the one the voice service stamped from the connection
    // rather than a number in the text, so the worst a modified client can do
    // with this is throw away its own lockpicks. It is capped anyway, and
    // takeItem refuses when the pack does not hold that many.
    // Profession, class and the tree. The character block owns these
    // words; it gets the same actor and profile id this function has.
    try {
      var charCmd = (typeof globalThis !== 'undefined' ? globalThis : this).__thornswoodCharacter;
      if (charCmd && charCmd.command(word, parts, actorId, profileId, toProfile)) { return; }
    } catch (eChar) { log('character command failed:', eChar); }

    if (word === '/tspicks') {
      if (!needCharacter()) { return; }
      var picks = Math.max(1, Math.min(20, Number(parts[1]) || 1));
      if (takeItem(actorId, 'a:Skyrim.esm', picks)) {
        log('spent ' + picks + ' lockpick(s) for ' + actorId.toString(16));
      }
      return;
    }

    if (word === '/where') {
      if (!needCharacter()) { return; }
      var pos = [0, 0, 0], ang = [0, 0, 0], cell = '';
      try {
        pos = mp.get(actorId, 'pos') || [0, 0, 0];
        ang = mp.get(actorId, 'angle') || [0, 0, 0];
        cell = String(mp.get(actorId, 'worldOrCellDesc') || '');
      } catch (e) { }
      toProfile(profileId,
        cell + '  pos ' + round1(pos[0]) + ', ' + round1(pos[1]) + ', ' + round1(pos[2]) +
        '  facing ' + round1(ang[2]));
      log('command: /where', actorId.toString(16), cell,
          round1(pos[0]), round1(pos[1]), round1(pos[2]), round1(ang[2]));
      return;
    }

    if (word === '/tp' || word === '/goto') {
      /*
        Admin only, because the profile id this arrives under is a claim and
        not a fact.

        The chat page joins the voice socket with whatever profile id is in the
        settings file on that machine, the voice service queues the line under
        it, and handle() takes it at its word. So anybody who opens a socket to
        the voice port with somebody else's id could move that person's
        character across Skyrim. It stays until a login hands out a token the
        page has to present.
      */
      if (!isPlaytester(profileId)) {
        /*
          Which list they are not on, because "not yours to run" told nobody
          anything and the answer was always the same whoever asked.

          And whether there is a list at all, because on 19 and 20 September
          there was not: no door.json, so no roster, and none of the three
          written lists set either. Every tier answered no to everybody and the
          refusal read as a decision about that person. A refusal from a server
          that has nothing to check against should say so, or the next person
          to hit this spends the evening looking at their own Discord roles.
        */
        var src = 'none';
        try {
          var g3 = (typeof globalThis !== 'undefined') ? globalThis : this;
          if (typeof g3.__thornswoodRoleSource === 'function') { src = g3.__thornswoodRoleSource(); }
        } catch (e) { }
        var written = rolelist('thornswoodDevs').length + rolelist('thornswoodPlaytesters').length;

        if (src === 'none' && !written) {
          toProfile(profileId,
            'This server has no playtester list to check, so /tp refuses everybody. ' +
            'That is a server fault rather than anything about you: private\door.json ' +
            'is missing, so the roles never arrive. Profile ' + profileId + '.');
          log('/tp refused profile ' + profileId + ' and there is NO ROLE SOURCE AT ALL: ' +
              'no door.json roster and no written lists in server-settings.json');
          return;
        }
        toProfile(profileId,
          'You are not on the playtester or dev list, so /tp is not yours to run. ' +
          'Ask Patrick to add profile ' + profileId + '.');
        log('/tp refused profile ' + profileId + ' (roster: ' + src + ', written: ' + written + ')');
        return;
      }
      var table = places();
      if (!arg) {
        toProfile(profileId, 'Where to: ' + Object.keys(table).sort().join(', '));
        return;
      }
      var where = table[arg];
      if (!where) {
        toProfile(profileId, 'No such place. Try: ' + Object.keys(table).sort().join(', '));
        return;
      }
      // The listing above answers whether or not the sweep found anybody. The
      // move is the part that needs a character to move.
      if (!needCharacter()) { return; }
      try {
        mp.set(actorId, 'locationalData', {
          cellOrWorldDesc: where.desc, pos: where.pos, rot: where.rot
        });
      } catch (e) {
        toProfile(profileId, 'That did not work: ' + e);
        return;
      }
      toProfile(profileId, 'Sent to ' + where.town + '.');
      log('command: /tp', actorId.toString(16), '->', arg, where.desc);
      return;
    }

    /*
      /restart is not a chat command any more.

      The profile id a command arrives under is a claim the page makes about
      itself, not something the server checked: the chat page joins the voice
      socket with whatever id is in the settings file on that machine, and
      handle() keyed isAdmin off that. So anybody who opened a socket to the
      voice port carrying an admin's profile id could take the server down.

      The file path is untouched and is how it is actually used: Ship.ps1 and
      Request-Restart.ps1 drop restart.json over ssh, checkRequest below picks
      it up, and the same countdown runs. That path needs the box, not a
      number anybody can type.

      It comes back as a chat command when a login hands each person a token
      the page has to present.
    */
    if (word === '/restart' || word === '/shutdown') {
      toProfile(profileId, 'Restarts are not run from chat. Use Request-Restart.ps1.');
      return;
    }

    // ------------------------------------------------------------- ooc ---
    //
    // Brackets worked, but only if everybody remembered them, and a line of
    // out of character talk typed without them lands in the middle of a scene
    // as though somebody's character said it.
    //
    // This is deliberately LOCAL. Out of character talk belongs to the scene
    // it interrupts, not to everybody in Skyrim, and a server wide one would
    // be a second general chat inside the game.
    if (word === '/ooc' || word === '/o') {
      var said = parts.slice(1).join(' ').trim();
      if (!said) {
        toProfile(profileId, 'Say /ooc and then whatever you meant to say.');
        return;
      }
      // Needs a character: who hears it is worked out from where that
      // character is standing.
      if (!needCharacter()) { return; }
      if (said.length > 300) { said = said.slice(0, 300); }

      var myPos = [0, 0, 0], myCell = '';
      try {
        myPos = mp.get(actorId, 'pos') || [0, 0, 0];
        myCell = String(mp.get(actorId, 'worldOrCellDesc') || '');
      } catch (e) { }

      var who = '';
      try {
        var ap = mp.get(actorId, 'appearance');
        who = String((ap && ap.name) || '');
      } catch (e) { }
      if (!who) { who = 'Somebody'; }

      var line = '(( ' + who + ': ' + said + ' ))';

      var near = [];
      try { near = mp.get(0, 'onlinePlayers') || []; } catch (e) { near = []; }

      var heard = 0;
      for (var oi = 0; oi < near.length; oi++) {
        var oid = near[oi], opid = 0;
        try { opid = Number(mp.get(oid, 'profileId')) || 0; } catch (e) { continue; }
        if (!opid) { continue; }

        if (oid !== actorId) {
          var oCell = '', oPos = [0, 0, 0];
          try {
            oCell = String(mp.get(oid, 'worldOrCellDesc') || '');
            oPos = mp.get(oid, 'pos') || [0, 0, 0];
          } catch (e) { continue; }
          // Same room first. Two people at the same coordinates in different
          // cells are not in earshot of each other.
          if (oCell !== myCell) { continue; }
          var dx = oPos[0] - myPos[0], dy = oPos[1] - myPos[1], dz = oPos[2] - myPos[2];
          if ((dx * dx + dy * dy + dz * dz) > (OOC_RANGE * OOC_RANGE)) { continue; }
        }

        toProfile(opid, line);
        heard++;
      }

      if (heard <= 1) {
        toProfile(profileId, 'Nobody near enough to hear that.');
      }
      log('command: /ooc', actorId.toString(16), 'heard by', heard);
      return;
    }

    if (word === '/help' || word === '/commands') {
      toProfile(profileId,
        '/ooc <what you meant> talks out of character to whoever is near you. ' +
        '/where prints your cell, position and facing. ' +
        '/roll is in the chat itself.' +
        (isPlaytester(profileId)
          ? ' /tp <place> moves you, and /tp on its own lists the places (' +
            roleOf(profileId) + ').'
          : ''));
      return;
    }

    // Anything else beginning with a slash is answered privately, and never
    // put back into the room.
    //
    // It used to be broadcast, on the theory that a slash might be somebody
    // talking rather than a typo. Two things wrong with that. It publishes
    // everybody's mistyped commands to the whole server, and worse, it makes a
    // command that ran and a command that never arrived look identical from
    // the chair: in both cases your line appears in the room and nothing else
    // happens. A screenshot of six commands echoing back could not tell us
    // whether this handler was even running.
    //
    // Now it can. An echo in the room means the line never reached the game
    // server at all, which means the voice service in front of it is not
    // holding slash lines back, which means the copy running up there is old.
    toProfile(profileId, 'No command called ' + word + '. ' +
              'There is /ooc, /where, /tp <place> and /help.');
  }

  /*
    Restarts, announced rather than sprung.

    Publishing an update means the server comes down, and up to now that landed
    on whoever was playing as a disconnect with no warning: mid dungeon, mid
    fight, with whatever the server had not yet written still unwritten. This
    gives the room notice, repeats it as the time gets shorter, and then puts
    everybody out deliberately so nobody is holding an open session when the
    process dies.

    Kicking at the end is the point, not a courtesy. A client still connected
    when the server stops sits there believing it is in a world nobody is
    keeping any more, and the reconnect that follows is messier than a clean
    exit. mp.kick ends it on our terms.
  */
  // On globalThis, so a hot reload in the middle of a countdown does not lose
  // it and start announcing from ten minutes again. The online.json writer
  // reads the same object to tell the client probe the server is on its way
  // back rather than gone.
  if (!g.__thornswoodRestart) {
    g.__thornswoodRestart = { at: 0, said: {}, why: '', mode: 'update' };
  }
  var restart = g.__thornswoodRestart;

  // Marks at which the room is told again. Anything longer than the notice
  // given is skipped, so /restart 2 does not shout about ten minutes.
  var MARKS = [600, 300, 120, 60, 30, 10];

  function admins() {
    try {
      var cfg = mp.getServerSettings() || {};
      var list = cfg.thornswoodAdmins;
      if (Array.isArray(list) && list.length) { return list.map(Number); }
    } catch (e) { }
    return [816507994];
  }

  function isAdmin(profileId) {
    if (admins().indexOf(Number(profileId)) !== -1) { return true; }
    // The site's admins, the Owner and Dev roles, by every profile they have
    // checked in with; see the door block. The written list stays for the
    // day the site is down.
    return roleFromDoor('Admin', profileId);
  }

  /*
    Who may run what, in three tiers.

    There was one tier and one name in it, so /tp answered "That one is not
    yours to run" to every developer and every playtester on the server, which
    is what was reported. Asked for by Djinn on 19 Sep: the people running the
    playtest need to move themselves around without asking Patrick to do it.

    The lists live in server-settings.json on the VPS beside thornswoodAdmins,
    as thornswoodDevs and thornswoodPlaytesters, both arrays of profile ids.
    Neither is a secret and neither has a default: a server that names nobody
    has no devs and no playtesters, which is the same as today.

    An admin is a dev is a playtester, so nobody has to be listed twice.

    WHAT THIS WIDENS, said plainly rather than buried. The profile id a chat
    line arrives under is a claim, not a fact: the page joins the voice socket
    with whatever id is in the settings file on that machine, and the service
    queues the line under it. /tp only ever moves the character belonging to
    the id it arrived under, so the worst anybody can do is move a character
    they can already claim to be. Going from one id to a handful widens that by
    a handful, and it is the same hole either way. It closes when a login hands
    the page a token it has to present, which is where this was always going.
  */
  function rolelist(name) {
    try {
      var cfg = mp.getServerSettings() || {};
      var list = cfg[name];
      if (Array.isArray(list) && list.length) { return list.map(Number); }
    } catch (e) { }
    return [];
  }

  /*
    The same question, asked of Discord instead of a hand written list.

    Added 20 September, because the three lists above were the whole answer and
    on the live server not one of them was set. Every tier fell through to the
    single hard coded admin id, which is not an id anybody currently plays, so
    /tp refused every single person including Patrick. The code shipped on 19
    September was right and there was nothing anywhere for it to read.

    The door already fetches this every five minutes and writes it beside
    itself: allowed.json holds everyone the site says may play, and the
    devProfiles inside it are the ones who also hold the dev or admin role. So
    the roles people already have in Discord answer this on their own, and a
    new playtester is a playtester the moment their role lands rather than when
    somebody remembers to add a number to a file.

    The written lists stay and win first. They cost nothing, they work on a
    server with no door configured at all, and they are the way to give
    somebody a tier that their Discord role does not.
  */
  function roleFromDoor(which, profileId) {
    try {
      var g2 = (typeof globalThis !== 'undefined') ? globalThis : this;
      var fn = g2['__thornswoodIs' + which];
      if (typeof fn === 'function') { return !!fn(profileId); }
    } catch (e) { }
    return false;
  }

  function isDev(profileId) {
    if (isAdmin(profileId)) { return true; }
    if (rolelist('thornswoodDevs').indexOf(Number(profileId)) !== -1) { return true; }
    return roleFromDoor('Dev', profileId);
  }

  function isPlaytester(profileId) {
    if (isDev(profileId)) { return true; }
    if (rolelist('thornswoodPlaytesters').indexOf(Number(profileId)) !== -1) { return true; }
    return roleFromDoor('Allowed', profileId);
  }

  /** What to call somebody in a refusal, so they know which list to be on. */
  function roleOf(profileId) {
    if (isAdmin(profileId)) { return 'admin'; }
    if (isDev(profileId)) { return 'dev'; }
    if (isPlaytester(profileId)) { return 'playtester'; }
    return 'none';
  }

  /** Everybody connected, by profile, so the message goes through the chat. */
  function broadcast(text) {
    var online = [];
    try { online = mp.get(0, 'onlinePlayers') || []; } catch (e) { return; }
    for (var i = 0; i < online.length; i++) {
      var pid = 0;
      try { pid = Number(mp.get(online[i], 'profileId')) || 0; } catch (e) { pid = 0; }
      if (pid) { toProfile(pid, text); }
    }
  }

  function clearTheServer() {
    var online = [];
    try { online = mp.get(0, 'onlinePlayers') || []; } catch (e) { return; }

    // A notice ends with a word, not a disconnect.
    if (restart.mode === 'notice') {
      broadcast(parting());
      log('notice: told', online.length, 'people, nobody disconnected');
      return;
    }

    // So does an update. The server stays up through a launcher update, and
    // a kick with no process restart behind it leaves the kicked character's
    // actor in a state where the reconnecting client is never sent the world:
    // 17 Sep, one existing character, 13 reconnects after two such kicks,
    // every one of them dead (no hits, no deaths, no hoster changes, "all the
    // NPCs are gone"), while the same character reconnected fine after the
    // 01:00 process restart and fresh characters always worked. The kick
    // gained nothing anyway: the client reconnects on its own in three
    // seconds, and since 1.1.41 the launcher closes the game itself five
    // minutes after it sees the update. The 'restart' mode still kicks, a
    // process restart follows it and that reconnect works.
    if (restart.mode === 'update') {
      broadcast(parting());
      log('update: told', online.length, 'people, nobody disconnected; the launcher closes the game for the update');
      return;
    }

    var gone = 0;
    for (var i = 0; i < online.length; i++) {
      var actorId = online[i];
      try {
        var pid = Number(mp.get(actorId, 'profileId')) || 0;
        if (pid) { toProfile(pid, parting()); }
      } catch (e) { }
      try {
        var userId = mp.getUserByActor(actorId);
        if (userId !== undefined && userId !== null && userId >= 0) {
          mp.kick(userId);
          gone++;
        }
      } catch (e) { log('could not kick', actorId, e); }
    }
    log('restart: cleared the server,', gone, 'disconnected');
  }

  /*
    Arming from one place, because there are two ways in.

    Typing /restart only works if he is standing in the world, and the moment
    that matters most is the one right after Ship.ps1 has published, when he is
    at a terminal and not in the game at all. So the server also watches for a
    file, and the ship script drops that file over ssh. Same countdown either
    way.

    mode decides the wording, not the behaviour. An update needs everybody to
    quit so their launcher can patch; a restart means the server itself is
    going down. Both end in the same kick, because a client left connected to a
    server that has stopped, or running files the rest of the room has moved
    past, is the thing this exists to prevent.
  */
  function arm(seconds, why, mode) {
    restart.at = Date.now() + Math.round(seconds * 1000);
    restart.said = {};
    /*
      Every mark at or above the time asked for is already said.

      restartTick walks MARKS from the largest down and announces the first one
      it has not said yet, one per tick. With said empty, "/restart 1" matched
      600 on the first tick, 300 on the second, 120 on the third and 60 on the
      fourth, so a one minute warning arrived as "10 minutes", "5 minutes",
      "2 minutes" and "1 minute" on four consecutive ticks, in that order.

      Marking them here means the countdown starts at the first one that is
      actually in the future.
    */
    for (var mi = 0; mi < MARKS.length; mi++) {
      if (MARKS[mi] >= seconds) { restart.said[MARKS[mi]] = true; }
    }
    restart.why = why || 'an update';
    restart.mode = (mode === 'restart' || mode === 'notice') ? mode : 'update';
    broadcast(opening(Math.round(seconds / 60)));
  }

  function opening(mins) {
    var when = mins >= 1
      ? mins + (mins === 1 ? ' minute' : ' minutes')
      : 'under a minute';
    /*
      Three modes, and only two of them end with anybody put out.

      notice is the common one and the reason this exists. Pushing a server
      build stops and starts the process, which from a chair looks like a
      freeze and then everything carries on: the client holds its session and
      picks back up, so throwing people out for it is a bigger interruption
      than the thing being warned about. They just want to know why the world
      went still for a moment, and not to be mid swing when it does.
    */
    if (restart.mode === 'notice') {
      return 'Pushing a server update in ' + when + '. Expect a freeze of a ' +
             'few seconds when it lands. You do not need to log out, but do ' +
             'not be mid fight.';
    }
    if (restart.mode === 'restart') {
      return 'The server is going down in ' + when + ' for ' + restart.why +
             '. Get somewhere safe and log out before then.';
    }
    return 'An update is out. Everyone has ' + when + ' to finish up, then you ' +
           'will be put back to the launcher to install it. ' +
           'Get somewhere safe.';
  }

  function reminder(when) {
    if (restart.mode === 'notice') {
      return 'Server update in ' + when + '. Brief freeze, nothing to do.';
    }
    if (restart.mode === 'restart') {
      return 'Server going down in ' + when + '. Log out somewhere safe.';
    }
    return when + ' until the update. Finish up and get somewhere safe.';
  }

  function parting() {
    if (restart.mode === 'notice') {
      return 'Going in now. Hold tight.';
    }
    if (restart.mode === 'restart') {
      return 'Going down now. See you in a few minutes.';
    }
    return 'Update time. Let the launcher patch, then come straight back.';
  }

  /*
    The drop box. Ship.ps1 writes it over ssh, we act on it and delete it, so a
    file left behind by a crash cannot fire a second time on the next boot.
  */
  var REQUEST = 'data/restart.json';

  function checkRequest() {
    var fs;
    try { fs = require('fs'); } catch (e) { return; }
    var raw;
    try {
      if (!fs.existsSync(REQUEST)) { return; }
      raw = fs.readFileSync(REQUEST, 'utf8');
    } catch (e) { return; }

    try { fs.unlinkSync(REQUEST); } catch (e) { }

    var req;
    try { req = JSON.parse(raw); } catch (e) {
      log('restart request was not readable:', raw);
      return;
    }
    if (!req) { return; }

    if (req.cancel) {
      if (restart.at) {
        restart.at = 0;
        restart.said = {};
        broadcast('That is called off. Carry on.');
        log('restart request: cancelled');
      }
      return;
    }

    var secs = Number(req.seconds);
    if (!(secs > 0)) { secs = 300; }
    if (secs > 7200) { secs = 7200; }

    arm(secs, String(req.why || 'an update'), String(req.mode || 'update'));
    log('restart request:', secs, 'seconds,', restart.mode, ',', restart.why);
  }

  function restartTick() {
    checkRequest();
    if (!restart.at) { return; }
    var left = Math.round((restart.at - Date.now()) / 1000);

    if (left <= 0) {
      restart.at = 0;
      /*
        When it ran out, kept so the probe stays patient across the stop.

        The countdown reaching zero is not the moment the server goes away.
        Deploy-Server waits the countdown plus twenty seconds and then copies
        files up before it starts anything, and in notice and update mode
        clearTheServer does not disconnect anybody, so the server carries on
        answering with restarting already false. The client would read one of
        those answers, forget it had been warned, and quit to the menu when
        the process finally stopped. Which is the exact thing the warning
        exists to prevent.
      */
      restart.went = Date.now();
      restart.said = {};
      clearTheServer();
      return;
    }

    for (var i = 0; i < MARKS.length; i++) {
      var m = MARKS[i];
      if (left <= m && !restart.said[m]) {
        restart.said[m] = true;
        var when = m >= 60
          ? (m / 60) + (m === 60 ? ' minute' : ' minutes')
          : m + ' seconds';
        broadcast(reminder(when));
        break;
      }
    }
  }

  function poll() {
    var http;
    try { http = require('http'); } catch (e) { return; }
    var req = http.request({
      host: '127.0.0.1', port: VOICE_PORT, path: '/commands', method: 'GET', timeout: 2000
    }, function (res) {
      var body = '';
      res.on('data', function (d) { body += d; });
      res.on('end', function () {
        var list = [];
        try { list = (JSON.parse(body) || {}).commands || []; } catch (e) { return; }
        for (var i = 0; i < list.length; i++) {
          try { handle(list[i]); }
          catch (e) { log('command threw:', e && e.stack ? e.stack : e); }
        }
      });
    });
    req.on('error', function () { });
    req.on('timeout', function () { req.destroy(); });
    req.end();
  }

  if (g.__thornswoodCommandTimer) { clearInterval(g.__thornswoodCommandTimer); }
  g.__thornswoodCommandTimer = setInterval(function () {
    try { poll(); } catch (e) { }
    try { restartTick(); } catch (e) { log('restart tick threw:', e); }
  }, 1500);

  console.log('[thornswood] chat commands running: /ooc, /where, /tp, /help, /restart, /pick, /spend');
})();
// ==== end thornswood chat commands ====
