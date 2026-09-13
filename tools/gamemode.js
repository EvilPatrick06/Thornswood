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

function log() {
  const args = Array.prototype.slice.call(arguments);
  console.log('[thornswood] ' + args.join(' '));
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
    host: '127.0.0.1', port: 7778, path: '/say', method: 'POST', timeout: 2000,
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
  const low = site.desc.split(':')[0].toLowerCase();

  // 1. Solstheim, by worldspace. Must never reach a distance comparison.
  if (low === DATA.solstheim) {
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
// onReadBook(actorId, baseId). So the books are the interface. Each one says
// what it does in its own text, which the game renders in its own book UI, and
// reading it is the choice. Nothing here depends on a message arriving.
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
const CHARGEN_TICK_MS = 1000;

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
 * comes off the end of a wait that already has the settle in front of it. */
const MOVED_ENOUGH_MS = 4000;
/* How long after a teleport before the kit is handed over, and how often it is
 * checked afterwards. Both deliberately unhurried: nobody is doing anything in
 * the first few seconds of arriving in an inn, and an item that turns up a
 * moment late is invisible, while one that never turns up is a bard with no
 * shirt. */
const GEAR_DELAY_MS = 5000;
const GEAR_RECHECK_MS = 4000;

/* How long to wait for a choice from the launcher before falling back to the
 * books. Long enough that a slow post never loses the race. */
const CHOICE_WAIT_MS = 20000;

/* Where somebody ends up when no choice ever arrives. Not a setting: it is the
 * shape of a bug, and the log says as much when it is used. */
const DEFAULT_TRADE = 'warrior';
const DEFAULT_TOWN = 'whiterun';
/* Five minutes, not forty five seconds. This exists so nobody is stranded when
 * the race menu never opens, and it used to be short enough to fire on somebody
 * who was simply still making their face: it would give up and start them
 * mid-menu. Being stuck is the thing worth guarding against; taking a while
 * over a nose is not. */
const GIVEUP_MS = 300000;

const firstSeen = new Map();   // actorId -> when it first appeared online

/* Skyrim Unbound's own character generation room, which is where a new game
 * already puts everybody, and the marker it stands them on. Falling back to the
 * configured start point is deliberate: if Unbound is ever removed from the load
 * order the flow should still run, just in a less tidy place. */
const HALL = {
  desc: '19bad4:Skyrim Unbound.esp',
  pos: [3755.7, -495.7, -207.7],
  rot: [0, 0, 180],
};

const CHARGEN = {"welcome":"e80000:Thornswood-Content.esp","shift":[["1be1a:Skyrim.esm",1],["1be1b:Skyrim.esm",1]],"classes":{"e80010:Thornswood-Content.esp":{"key":"warrior","gear":[["12e49:Skyrim.esm",1],["12e4b:Skyrim.esm",1],["12e46:Skyrim.esm",1],["12e4d:Skyrim.esm",1],["12eb7:Skyrim.esm",1],["12eb6:Skyrim.esm",1],["3eadd:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e80011:Thornswood-Content.esp":{"key":"hunter","gear":[["13911:Skyrim.esm",1],["13910:Skyrim.esm",1],["13912:Skyrim.esm",1],["13913:Skyrim.esm",1],["13985:Skyrim.esm",1],["1397d:Skyrim.esm",60],["1397e:Skyrim.esm",1],["3eae5:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e80012:Thornswood-Content.esp":{"key":"mage","gear":[["10710a:Skyrim.esm",1],["d1921:Skyrim.esm",1],["9cd51:Skyrim.esm",1],["9e2af:Skyrim.esm",1],["2e4e2:Skyrim.esm",2],["3eae0:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e80013:Thornswood-Content.esp":{"key":"smith","gear":[["5b69f:Skyrim.esm",1],["5b69e:Skyrim.esm",1],["5ace4:Skyrim.esm",5],["5ace5:Skyrim.esm",2],["800e4:Skyrim.esm",10],["f:Skyrim.esm",100]]},"e80014:Thornswood-Content.esp":{"key":"miner","gear":[["80697:Skyrim.esm",1],["80699:Skyrim.esm",1],["e3c16:Skyrim.esm",1],["1d4ec:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e80015:Thornswood-Content.esp":{"key":"woodworker","gear":[["1be1a:Skyrim.esm",1],["1be1b:Skyrim.esm",1],["2f2f4:Skyrim.esm",1],["1d4ec:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e80016:Thornswood-Content.esp":{"key":"alchemist","gear":[["bacf3:Skyrim.esm",1],["bacd7:Skyrim.esm",1],["1397e:Skyrim.esm",1],["45c28:Skyrim.esm",3],["59b86:Skyrim.esm",2],["134aa:Skyrim.esm",3],["34d31:Skyrim.esm",3],["5076e:Skyrim.esm",3],["516c8:Skyrim.esm",2],["ae723:Skyrim.esm",1],["f:Skyrim.esm",75]]},"e80017:Thornswood-Content.esp":{"key":"bard","gear":[["5b6a1:Skyrim.esm",1],["5b6a0:Skyrim.esm",1],["1397e:Skyrim.esm",1],["dabab:Skyrim.esm",1],["daba7:Skyrim.esm",1],["daba9:Skyrim.esm",1],["65c97:Skyrim.esm",2],["64b31:Skyrim.esm",2],["f:Skyrim.esm",200]]},"e80018:Thornswood-Content.esp":{"key":"cook","gear":[["1bc82:Skyrim.esm",1],["1bca7:Skyrim.esm",1],["18801:Skyrim.esm",1],["721e8:Skyrim.esm",3],["e8947:Skyrim.esm",3],["722bd:Skyrim.esm",2],["64b43:Skyrim.esm",2],["f4314:Skyrim.esm",2],["64b41:Skyrim.esm",4],["64b3f:Skyrim.esm",3],["64b40:Skyrim.esm",3],["669a5:Skyrim.esm",3],["1397e:Skyrim.esm",1],["f:Skyrim.esm",75]]},"e80019:Thornswood-Content.esp":{"key":"enchanter","gear":[["10710a:Skyrim.esm",1],["d1921:Skyrim.esm",1],["2e4e2:Skyrim.esm",3],["2e4e4:Skyrim.esm",2],["2e4e6:Skyrim.esm",1],["1397e:Skyrim.esm",1],["3eae0:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e8001a:Thornswood-Content.esp":{"key":"farmer","gear":[["1be1a:Skyrim.esm",1],["1be1b:Skyrim.esm",1],["4b0ba:Skyrim.esm",5],["64b41:Skyrim.esm",4],["64b3f:Skyrim.esm",3],["64b40:Skyrim.esm",3],["669a5:Skyrim.esm",2],["1397e:Skyrim.esm",1],["2f2f4:Skyrim.esm",1],["f:Skyrim.esm",75]]},"e8001b:Thornswood-Content.esp":{"key":"fisher","gear":[["1be1a:Skyrim.esm",1],["1be1b:Skyrim.esm",1],["207e2:FishingInSkyrim.esp",1],["d68:FishingInSkyrim.esp",1],["25eb7:FishingInSkyrim.esp",1],["65c9f:Skyrim.esm",3],["64b3b:Skyrim.esm",2],["1397e:Skyrim.esm",1],["65c97:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e8001c:Thornswood-Content.esp":{"key":"merchant","gear":[["86991:Skyrim.esm",1],["86993:Skyrim.esm",1],["878bb:Skyrim.esm",1],["1397e:Skyrim.esm",1],["3eadd:Skyrim.esm",2],["3eae0:Skyrim.esm",1],["64b31:Skyrim.esm",3],["65c97:Skyrim.esm",3],["f:Skyrim.esm",400]]},"e8001d:Thornswood-Content.esp":{"key":"priest","gear":[["bacf3:Skyrim.esm",1],["bacd7:Skyrim.esm",1],["9e2af:Skyrim.esm",1],["cc848:Skyrim.esm",1],["c891b:Skyrim.esm",1],["ae723:Skyrim.esm",2],["3eadd:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e8001e:Thornswood-Content.esp":{"key":"scholar","gear":[["10710a:Skyrim.esm",1],["d1921:Skyrim.esm",1],["9e2a8:Skyrim.esm",1],["9cd53:Skyrim.esm",1],["1d4ec:Skyrim.esm",2],["3eae0:Skyrim.esm",2],["f:Skyrim.esm",75]]},"e8001f:Thornswood-Content.esp":{"key":"thief","gear":[["3619e:Skyrim.esm",1],["13920:Skyrim.esm",1],["13921:Skyrim.esm",1],["1397e:Skyrim.esm",1],["a:Skyrim.esm",15],["3eae5:Skyrim.esm",2],["f:Skyrim.esm",75]]}},"towns":{"e80030:Thornswood-Content.esp":{"key":"whiterun","town":"Whiterun","arrival":{"cell":"WhiterunBanneredMare","desc":"1605e:Skyrim.esm","pos":[-18.0,-1152.0,120.2],"rot":[0,0,90.0]}},"e80031:Thornswood-Content.esp":{"key":"riften","town":"Riften","arrival":{"cell":"RiftenBeeandBarb","desc":"16bdf:Skyrim.esm","pos":[-150.2,-598.2,68.0],"rot":[0,0,45.0]}},"e80032:Thornswood-Content.esp":{"key":"solitude","town":"Solitude","arrival":{"cell":"SolitudeWinkingSkeever","desc":"16a0e:Skyrim.esm","pos":[-178.0,-1504.0,128.0],"rot":[0,0,90.0]}},"e80033:Thornswood-Content.esp":{"key":"windhelm","town":"Windhelm","arrival":{"cell":"WindhelmCandlehearthHall","desc":"16789:Skyrim.esm","pos":[881.0,-3660.5,158.3],"rot":[0,0,180.0]}},"e80034:Thornswood-Content.esp":{"key":"markarth","town":"Markarth","arrival":{"cell":"MarkarthSilverBloodInn","desc":"16dfe:Skyrim.esm","pos":[-5588.5,-1925.8,-16.0],"rot":[0,0,180.0]}},"e80035:Thornswood-Content.esp":{"key":"falkreath","town":"Falkreath","arrival":{"cell":"FalkreathDeadMansDrink","desc":"3a184:Skyrim.esm","pos":[673.1,-620.3,0.0],"rot":[0,0,180.0]}},"e80036:Thornswood-Content.esp":{"key":"morthal","town":"Morthal","arrival":{"cell":"MorthalMoorsideInn","desc":"138ce:Skyrim.esm","pos":[1824.1,-685.8,0.5],"rot":[0,0,180.0]}},"e80037:Thornswood-Content.esp":{"key":"dawnstar","town":"Dawnstar","arrival":{"cell":"DawnstarWindpeakInn","desc":"13a7f:Skyrim.esm","pos":[1824.3,-683.7,0.0],"rot":[0,0,180.0]}},"e80038:Thornswood-Content.esp":{"key":"winterhold","town":"Winterhold","arrival":{"cell":"WinterholdTheFrozenHearth","desc":"13814:Skyrim.esm","pos":[2528.6,-524.4,0.5],"rot":[0,0,180.0]}}},"tradeMenus":["e80050:Thornswood-Content.esp","e80051:Thornswood-Content.esp"],"townMenus":["e80052:Thornswood-Content.esp","e80053:Thornswood-Content.esp"],"tradePages":[["e80010:Thornswood-Content.esp","e80011:Thornswood-Content.esp","e80012:Thornswood-Content.esp","e80013:Thornswood-Content.esp","e80014:Thornswood-Content.esp","e80015:Thornswood-Content.esp","e80016:Thornswood-Content.esp","e80017:Thornswood-Content.esp"],["e80018:Thornswood-Content.esp","e80019:Thornswood-Content.esp","e8001a:Thornswood-Content.esp","e8001b:Thornswood-Content.esp","e8001c:Thornswood-Content.esp","e8001d:Thornswood-Content.esp","e8001e:Thornswood-Content.esp","e8001f:Thornswood-Content.esp"]],"townPages":[["e80030:Thornswood-Content.esp","e80031:Thornswood-Content.esp","e80032:Thornswood-Content.esp","e80033:Thornswood-Content.esp","e80034:Thornswood-Content.esp"],["e80035:Thornswood-Content.esp","e80036:Thornswood-Content.esp","e80037:Thornswood-Content.esp","e80038:Thornswood-Content.esp"]]};

const WELCOME_BOOK = CHARGEN.welcome;

/* Something to wear while choosing. The appearance menu hands you back with an
 * empty inventory, and picking a trade naked in a stone room is nobody's idea
 * of a first morning. */
const SHIFT = CHARGEN.shift;

/* Sixteen trades and ten towns, generated from the same table the plugin and
 * the message box records came from, so the three cannot drift apart. */
const CLASSES = CHARGEN.classes;
const PASSAGES = CHARGEN.towns;

/* The launcher sends a trade and a town as their short keys, 'warrior' and
 * 'whiterun', because those are stable. The records are keyed by descriptor,
 * which is not: it carries the plugin name and moves whenever the content is
 * rebuilt. So the lookup goes through the key. */
const CLASS_BY_KEY = (function () {
  const m = {};
  for (const desc in CLASSES) { m[CLASSES[desc].key] = desc; }
  return m;
})();
const TOWN_BY_KEY = (function () {
  const m = {};
  for (const desc in PASSAGES) { m[PASSAGES[desc].key] = desc; }
  return m;
})();

/* What people picked in the launcher, fetched from the voice service, which is
 * the one thing both the launcher and this can reach. Refreshed on a timer
 * rather than asked for on demand, because the tick must never wait on a
 * socket: a slow answer there would stall everybody's creation, not just the
 * person it was for. */
let launcherChoices = {};
let choiceFetchFailed = false;

function refreshChoices() {
  let http;
  try { http = require('http'); } catch (e) { return; }
  const req = http.request({
    host: '127.0.0.1', port: 7778, path: '/choices', method: 'GET', timeout: 2000
  }, (res) => {
    let body = '';
    res.on('data', (d) => { body += d; });
    res.on('end', () => {
      try {
        const got = JSON.parse(body) || {};
        const before = Object.keys(launcherChoices).length;
        const after = Object.keys(got).length;
        launcherChoices = got;
        // Only when it changes, or this writes a line every two seconds
        // forever and the log becomes useless for anything else.
        if (before !== after) {
          log('chargen: the launcher has', after, 'choice(s) waiting:',
              Object.keys(got).join(', '));
        }
      } catch (e) {
        log('chargen: could not read the choices list:', e);
      }
    });
  });
  req.on('error', function (e) {
    if (!choiceFetchFailed) {
      choiceFetchFailed = true;
      log('chargen: cannot reach the voice service for launcher choices:',
          e && e.message ? e.message : e);
    }
  });
  req.on('timeout', function () { req.destroy(); });
  req.end();
}

function claimChoice(profileId) {
  let http;
  try { http = require('http'); } catch (e) { return; }
  const payload = JSON.stringify({ profileId: profileId });
  const req = http.request({
    host: '127.0.0.1', port: 7778, path: '/claimed', method: 'POST', timeout: 2000,
    headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(payload) }
  }, function () { });
  req.on('error', function () { });
  req.on('timeout', function () { req.destroy(); });
  req.end(payload);
  delete launcherChoices[String(profileId)];
}

/**
 * Everything the books used to do, done at once, from a choice already made.
 *
 * Returns true when it applied. The books remain the fallback for anybody whose
 * launcher did not send one, so nothing is lost if the two ever disagree.
 */
function applyLauncherChoice(actorId, state, choice) {
  const classDesc = CLASS_BY_KEY[choice.trade];
  const townDesc = TOWN_BY_KEY[choice.town];
  if (!classDesc || !townDesc) {
    log('chargen', actorId.toString(16), 'launcher sent an unknown choice:',
        choice.trade, '/', choice.town, '- falling back to the books');
    return false;
  }

  const cls = CLASSES[classDesc];
  const entry = PASSAGES[townDesc];
  const arrival = entry.arrival;
  if (!arrival) {
    log('chargen', actorId.toString(16), 'no arrival for', entry.key, '- falling back to the books');
    return false;
  }

  // Deliberately no items here. See the 'arriving' stage below.
  //
  // They used to be handed over in this breath, immediately before the two
  // lines that teleport somebody across Skyrim, and a bard turned up in
  // Windhelm with his lute, his flute, his drum, his dagger, his bread, his
  // cheese and his two hundred gold, and no shirt. One entry out of nine, gone.
  //
  // An inventory write and a teleport composed in the same server tick reach
  // the client as a load and a set of item changes racing each other, and the
  // client rebuilds the actor around whichever it finishes first. So the
  // teleport goes now and the kit follows once they have landed, and then it is
  // read back and checked rather than assumed.
  mp.set(actorId, 'spawnPoint', {
    cellOrWorldDesc: arrival.desc, pos: arrival.pos, rot: arrival.rot,
  });
  mp.set(actorId, 'locationalData', {
    cellOrWorldDesc: arrival.desc, pos: arrival.pos, rot: arrival.rot,
  });

  state.stage = 'arriving';
  state.class = cls.key;
  state.destination = entry.key;
  state.fromLauncher = true;
  state.at = Date.now();
  state.gearAt = Date.now() + GEAR_DELAY_MS;
  state.gearTries = 0;
  state.clean = 0;
  setChargen(actorId, state);

  log('chargen', actorId.toString(16), 'launcher choice applied:',
      cls.key, 'in', entry.key, '(' + arrival.cell + '), kit to follow');
  return true;
}

/**
 * Put whatever is missing from somebody's trade kit into their pack.
 *
 * Returns the number of entries it had to add. Zero means the kit is all there,
 * which is the only thing worth trusting: the point of this function is that
 * setting an inventory is not the same as somebody having the items.
 */
function ensureGear(actorId, gear) {
  let have = { entries: [] };
  try { have = mp.get(actorId, 'inventory') || { entries: [] }; } catch (e) { return -1; }
  const entries = have.entries || [];

  const missing = [];
  for (const pair of gear) {
    const baseId = idOf(pair[0]);
    if (!baseId) { continue; }
    let count = 0;
    for (const e of entries) {
      if (e.baseId === baseId) { count = e.count || 0; break; }
    }
    if (count < pair[1]) { missing.push([pair[0], pair[1] - count]); }
  }

  if (missing.length) { giveItems(actorId, missing, +1); }
  return missing.length;
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

/** Every writ, or every passage, as [descriptor, 1] pairs. */
function oneOfEach(table) {
  const out = [];
  for (const d in table) out.push([d, 1]);
  return out;
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

function beginClass(actorId, state) {
  giveItems(actorId, SHIFT.concat([[WELCOME_BOOK, 1]]).concat(oneOfEach(CLASSES)), +1);
  state.stage = 'class';
  state.at = Date.now();
  setChargen(actorId, state);
  log('chargen', actorId.toString(16), '-> class');
}

function chooseClass(actorId, state, desc) {
  const cls = CLASSES[desc];
  giveItems(actorId, oneOfEach(CLASSES), -1);
  giveItems(actorId, cls.gear.concat(oneOfEach(PASSAGES)), +1);
  state.stage = 'destination';
  state.class = cls.key;
  state.at = Date.now();
  setChargen(actorId, state);
  log('chargen', actorId.toString(16), 'class =', cls.key, '-> destination');
}

function chooseDestination(actorId, state, desc) {
  const entry = PASSAGES[desc];
  const town = entry.key;
  const arrival = entry.arrival;
  giveItems(actorId, oneOfEach(PASSAGES).concat([[WELCOME_BOOK, 1]]), -1);

  if (!arrival) {
    log('chargen', actorId.toString(16), 'no arrival for', town, '- staying in the hall');
    return;
  }
  mp.set(actorId, 'spawnPoint', {
    cellOrWorldDesc: arrival.desc,
    pos: arrival.pos,
    rot: arrival.rot,
  });
  mp.set(actorId, 'locationalData', {
    cellOrWorldDesc: arrival.desc,
    pos: arrival.pos,
    rot: arrival.rot,
  });
  state.stage = 'done';
  state.destination = town;
  state.at = Date.now();
  setChargen(actorId, state);
  log('chargen', actorId.toString(16), 'destination =', town,
      '(' + arrival.cell + ') -> done');
}

/**
 * One pass over everybody online.
 *
 * The only transition the timer owns is appearance -> class, because the race
 * menu closing is not an event either: the appearance simply turns up on the
 * change form, and this notices. The rest is driven by onReadBook.
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
      // A choice waiting from the launcher is proof this character was made
      // seconds ago, and it beats anything the face suggests.
      let pidNew = 0;
      try { pidNew = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { pidNew = 0; }
      if (pidNew && launcherChoices[String(pidNew)]) {
        log('chargen', actorId.toString(16), 'profile', pidNew,
            'is new, the launcher has a choice waiting for them');
        beginAppearance(actorId);
        continue;
      }

      // Otherwise: somebody who was already playing before this existed keeps
      // their character. Only a blank appearance means a genuinely new one.
      if (appearance) {
        // Said out loud. This branch is the whole reason creation could look
        // broken while nothing was wrong: it is correct, it is silent, and it
        // is what happens to anybody whose profile id already has a character
        // on this server. Two launchers handing out the same id put two people
        // on the same character and both landed here, and the log had nothing
        // in it to say so.
        let pidWas = 0;
        try { pidWas = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { pidWas = 0; }
        log('chargen', actorId.toString(16), 'profile', pidWas,
            'already has a character, so creation is skipped for them');
        setChargen(actorId, { stage: 'done', at: now, legacy: true });
        continue;
      }
      beginAppearance(actorId);
      continue;
    }

    // Landed, or landing. The kit goes in here rather than alongside the
    // teleport, and then it is checked. Three clean passes and we stop looking.
    if (state.stage === 'arriving') {
      if (now < (state.gearAt || 0)) { continue; }

      const classDesc = CLASS_BY_KEY[state.class];
      const cls = classDesc ? CLASSES[classDesc] : null;
      if (!cls) {
        log('chargen', actorId.toString(16), 'no kit for', state.class, '- nothing to hand over');
        state.stage = 'done';
        setChargen(actorId, state);
        continue;
      }

      const added = ensureGear(actorId, cls.gear);
      state.gearAt = now + GEAR_RECHECK_MS;
      state.gearTries = (state.gearTries || 0) + 1;

      if (added > 0) {
        state.clean = 0;
        log('chargen', actorId.toString(16), 'put', added,
            added === 1 ? 'missing item' : 'missing items', 'into the', state.class, 'kit',
            '(pass ' + state.gearTries + ')');
      } else if (added === 0) {
        state.clean = (state.clean || 0) + 1;
      }

      if ((state.clean || 0) >= 3 || state.gearTries > 12) {
        state.stage = 'done';
        setChargen(actorId, state);
        log('chargen', actorId.toString(16), 'kit confirmed:', state.class, 'in', state.destination);
        continue;
      }

      setChargen(actorId, state);
      continue;
    }

    if (state.stage === 'appearance') {
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
        if (state.where && state.where !== here) { live = true; }
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
        // Straight from the launcher if they chose there, which is the path
        // everybody takes now. The books below are what happens when they did
        // not, which is an old launcher or a choice that did not arrive.
        let pid = 0;
        try { pid = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { pid = 0; }
        const choice = pid ? launcherChoices[String(pid)] : null;

        if (choice && applyLauncherChoice(actorId, state, choice)) {
          claimChoice(pid);
          continue;
        }

        // No books. The trade and the town are chosen in the launcher and
        // nowhere else, so nothing here ever puts a writ or a passage in
        // anybody's pack.
        //
        // What is left is the case where the choice never arrives: the voice
        // service is down, or the post failed, or they are on an old launcher.
        // Standing in an empty room forever is the worst possible answer to
        // that, so after a wait they start as a warrior in Whiterun and the log
        // says so loudly. Somebody in the wrong trade can be fixed in a minute.
        // Somebody stuck in a room cannot do anything at all.
        if (!state.waitedForChoice) {
          state.waitedForChoice = Date.now();
          setChargen(actorId, state);
          log('chargen', actorId.toString(16), 'has a face, profile', pid,
              '- no launcher choice for that id yet.',
              'Known ids:', Object.keys(launcherChoices).join(', ') || '(none)');
          continue;
        }
        if (now - state.waitedForChoice < CHOICE_WAIT_MS) {
          continue;
        }

        log('chargen', actorId.toString(16), 'NO LAUNCHER CHOICE after',
            Math.round((now - state.waitedForChoice) / 1000) + 's for profile', pid + '.',
            'Starting them as', DEFAULT_TRADE, 'in', DEFAULT_TOWN,
            'so they are not stuck. This should not happen.');
        if (!applyLauncherChoice(actorId, state, { trade: DEFAULT_TRADE, town: DEFAULT_TOWN })) {
          log('chargen', actorId.toString(16), 'could not even apply the default. Something is very wrong.');
        }
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
      // So: on your feet for eight seconds, with a trade and a town already
      // waiting from the launcher, and we get on with it. The appearance can
      // arrive whenever it likes.
      const onFeetFor = state.liveSince ? (now - state.liveSince) : 0;

      if (onFeetFor > MOVED_ENOUGH_MS) {
        let pidM = 0;
        try { pidM = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { pidM = 0; }
        const choiceM = pidM ? launcherChoices[String(pidM)] : null;

        if (choiceM) {
          // Said in full because the appearance not arriving is still a bug
          // and this is the only place it can be seen from.
          log('chargen', actorId.toString(16), 'walking after',
              Math.round(onFeetFor / 1000) + 's and the face never arrived.',
              'appearance is', appearance ? 'present' : 'MISSING,',
              'mark now', JSON.stringify(faceNow) + ',',
              'mark at the start', JSON.stringify(state.faceWas || '') + '.',
              'Going on the movement instead.');

          if (applyLauncherChoice(actorId, state, choiceM)) {
            claimChoice(pidM);
            continue;
          }
          log('chargen', actorId.toString(16),
              'could not apply the launcher choice on the movement path.');
        }
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
        let pid2 = 0;
        try { pid2 = Number(mp.get(actorId, 'profileId')) || 0; } catch (e) { pid2 = 0; }
        const c2 = pid2 ? launcherChoices[String(pid2)] : null;

        log('chargen', actorId.toString(16),
            'appearance never arrived after', Math.round(waited / 1000) + 's,',
            'starting them anyway');

        if (c2 && applyLauncherChoice(actorId, state, c2)) {
          claimChoice(pid2);
        } else {
          applyLauncherChoice(actorId, state, { trade: DEFAULT_TRADE, town: DEFAULT_TOWN });
        }
      }
    }
  }
}

function startChargenTimer() {
  if (!CHARGEN_ENABLED) {
    log('character creation is Skyrim Unbound\'s. The server is staying out of it.');
    return;
  }

  // Every two seconds is often enough: somebody presses Play, then sits through
  // a loading screen and the race menu before any of this is needed.
  const g2 = globalThis;
  if (g2.__thornswoodChoiceTimer) { clearInterval(g2.__thornswoodChoiceTimer); }
  g2.__thornswoodChoiceTimer = setInterval(guard('refreshChoices', refreshChoices), 2000);
  refreshChoices();
  // Hot reload runs this file again in a fresh module, but the Node process and
  // its timers survive. Without this the ticks stack up one per save.
  const g = globalThis;
  if (g.__thornswoodChargenTimer) {
    clearInterval(g.__thornswoodChargenTimer);
  }
  g.__thornswoodChargenTimer = setInterval(guard('chargenTick', chargenTick),
                                           CHARGEN_TICK_MS);
}

/** Returns true if the book was a chargen book and has been dealt with. */
function chargenReadBook(actorId, baseId) {
  if (!CHARGEN_ENABLED) {
    return false;
  }
  const state = chargenOf(actorId);

  for (const desc in CLASSES) {
    if (idOf(desc) !== baseId) continue;
    if (!state || state.stage !== 'class') {
      log('chargen', actorId.toString(16), 'read a writ out of turn, ignoring');
      return true;
    }
    chooseClass(actorId, state, desc);
    return true;
  }

  for (const desc in PASSAGES) {
    if (idOf(desc) !== baseId) continue;
    if (!state || state.stage !== 'destination') {
      log('chargen', actorId.toString(16), 'read a passage out of turn, ignoring');
      return true;
    }
    chooseDestination(actorId, state, desc);
    return true;
  }

  return false;
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
  if (chargenReadBook(actorId, baseId)) return;

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

log('gamemode loaded:',
    Object.keys(DATA.cellToHold).length + ' cells mapped,',
    Object.keys(MANUALS).length + ' manuals,',
    Object.keys(STATIONS).length + ' station types,',
    Object.keys(CLASSES).length + ' trades,',
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
  var VOICE_PORT = 7778;
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

  setInterval(function () {
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

    setInterval(function () {
      var n = 0;
      try { n = (mp.get(0, 'onlinePlayers') || []).length; } catch (e) { return; }
      // Only when it moves. This file sits in a folder the server serves, and
      // rewriting it twice a second for no reason is churn nobody asked for.
      if (n === lastWritten) return;
      lastWritten = n;
      try {
        fs.writeFileSync(onlineFile, JSON.stringify({ now: n, at: Date.now() }));
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
  try {
    var cfg = JSON.parse(fs.readFileSync('server-settings.json', 'utf8'));
    if (cfg && cfg.dataDir) dataDir = String(cfg.dataDir);
  } catch (e) { }

  var FILE = path.join(dataDir, 'characters.json');

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

  function write() {
    try {
      fs.writeFileSync(FILE, JSON.stringify({ at: Date.now(), who: book }));
    } catch (e) { }
  }

  var dirty = false;

  setInterval(function () {
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

        var row = {
          name: String((look && look.name) || ''),
          race: look ? raceName(look.raceId) : '',
          female: !!(look && look.isFemale),
          trade: String((state && state.class) || ''),
          town: String((state && state.destination) || ''),
          at: Date.now()
        };

        var was = book[String(pid)];
        // Compared field by field rather than by timestamp, because the
        // timestamp moves every four seconds and this file sits in a folder
        // the server serves. Rewriting it fifteen times a minute for nothing
        // is churn nobody asked for.
        if (!was || was.name !== row.name || was.race !== row.race ||
            was.female !== row.female || was.trade !== row.trade ||
            was.town !== row.town) {
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
    return true;
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

// ==== thornswood gear check ====
// ------------------------------------------------------------ gear check ---
// Reads back every form id the trade kits hand out and says what it is.
//
// Not a formality. These ids come from lists and wikis, and a wrong one does
// not fail: mp.getIdFromDesc resolves a descriptor against the load order and
// hands back a number whether or not a record of the expected kind is sitting
// at it. So a bard can be given three of something silently, or nothing, and
// the only evidence is somebody opening their pack and finding no lute.
//
// So the server reads each one out of the espm it actually loaded and prints
// the editor id. That is the ground truth on this machine rather than a claim
// about Skyrim in general, and it costs one pass at startup.
(function () {
  var EVERY = 'e80017';   // only the bard is checked loudly; see below

  function textOf(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
      if (!bytes[i]) break;
      out += String.fromCharCode(bytes[i]);
    }
    return out;
  }

  /** The editor id of a record, or '' when it cannot be read. */
  function edidOf(id) {
    try {
      var found = mp.lookupEspmRecordById(id);
      var rec = found && found.record;
      if (!rec) return '';
      var fields = rec.fields || [];
      for (var i = 0; i < fields.length; i++) {
        if (String(fields[i].type) === 'EDID') {
          return textOf(fields[i].data || []);
        }
      }
      return '(' + String(rec.type || '????') + ', no editor id)';
    } catch (e) {
      return '';
    }
  }

  setTimeout(function () {
    var bad = 0;
    var lines = [];

    for (var desc in CLASSES) {
      var cls = CLASSES[desc];
      var gear = cls.gear || [];
      for (var i = 0; i < gear.length; i++) {
        var d = gear[i][0];
        var id = idOf(d);
        if (!id) {
          bad++;
          lines.push('  ' + cls.key + ': ' + d + ' does not resolve at all');
          continue;
        }
        var name = edidOf(id);
        if (!name) {
          bad++;
          lines.push('  ' + cls.key + ': ' + d + ' resolves to ' +
                     id.toString(16) + ' but there is no record there');
        }
      }
    }

    if (bad) {
      log('gear check: ' + bad + ' entr' + (bad === 1 ? 'y' : 'ies') + ' in the trade kits is wrong');
      for (var j = 0; j < lines.length; j++) { log(lines[j]); }
    } else {
      log('gear check: every item in every trade kit resolves');
    }

    // And then the whole thing, by name, class by class.
    //
    // Sixteen kits were written from lists, and "several of the classes are
    // wrong" is not a thing anybody can check by reading hex. A resolved id
    // proves a record exists at that number; only the editor id proves it is
    // the record that was meant. This is the one place that can say so, because
    // it is reading the espm this server actually loaded.
    log('--- trade kits, as they resolve on this machine ---');
    for (var d2 in CLASSES) {
      var c2 = CLASSES[d2];
      var parts = [];
      var g2 = c2.gear || [];
      for (var q = 0; q < g2.length; q++) {
        var gid = idOf(g2[q][0]);
        var nm = gid ? (edidOf(gid) || '???') : 'UNRESOLVED';
        parts.push(g2[q][0].split(':')[0] + ' ' + nm + (g2[q][1] > 1 ? ' x' + g2[q][1] : ''));
      }
      log('  ' + c2.key + ': ' + parts.join(' | '));
    }
    log('--- end trade kits ---');

    // Where a new character lands, which is a raw form id in server-settings
    // and therefore rots the moment the load order moves.
    //
    // It had. startPoints said 0x3919BAD4, which is index 57, which by then was
    // RaceMenuMorphsCBBE.esp; Skyrim Unbound had drifted to 59. So everybody
    // spawned at whatever record happened to sit at 0x19BAD4 in a body morph
    // plugin, the gamemode noticed they were not in the hall and teleported
    // them, and that is the tavern, then the hall, then the wait, then the
    // teleport. Deploy-Gamemode.ps1 computes this correctly; Publish-Server
    // does not run it, so nothing recomputed it and nothing said so.
    try {
      var fs2 = require('fs');
      var cfg2 = JSON.parse(fs2.readFileSync('server-settings.json', 'utf8'));
      var sp2 = (cfg2.startPoints || [])[0];
      var want = idOf(HALL.desc);
      var have = sp2 ? Number(sp2.worldOrCell) : 0;
      if (!want) {
        log('start point: cannot resolve ' + HALL.desc + ', so it cannot be checked');
      } else if (have === want) {
        log('start point: correct, 0x' + want.toString(16) + ' ' + (edidOf(want) || HALL.desc));
      } else {
        log('START POINT IS WRONG. server-settings.json says 0x' + have.toString(16) +
            ' (' + (edidOf(have) || 'nothing there') + ') and ' + HALL.desc +
            ' is 0x' + want.toString(16) + '.');
        log('  Everybody spawns in the wrong cell and gets teleported out of it.');
        log('  Run Deploy-Gamemode.ps1, then Publish-Server.ps1.');
      }
    } catch (e) { }
  }, 8000);
})();
// ==== end thornswood gear check ====


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

  var g = globalThis;
  if (g.__thornswoodCommands) { return; }
  g.__thornswoodCommands = true;

  var VOICE_PORT = 7778;

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
  function toProfile(profileId, text) {
    post('/say', { profileId: profileId, text: text });
  }

  /** actorId for a connected profile, or 0. */
  function actorOf(profileId) {
    var online = [];
    try { online = mp.get(0, 'onlinePlayers') || []; } catch (e) { return 0; }
    for (var i = 0; i < online.length; i++) {
      var id = online[i];
      var pid = 0;
      try { pid = Number(mp.get(id, 'profileId')) || 0; } catch (e) { pid = 0; }
      if (pid === profileId) { return id; }
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

    var actorId = actorOf(profileId);
    if (!actorId) {
      toProfile(profileId, 'The server cannot find your character right now.');
      return;
    }

    if (word === '/where') {
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

    if (word === '/help' || word === '/commands') {
      toProfile(profileId,
        '/where prints your cell, position and facing. ' +
        '/tp <place> moves you. /roll is in the chat itself.');
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
              'There is /where, /tp <place> and /help.');
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
  }, 1500);

  console.log('[thornswood] chat commands running: /where, /tp, /help');
})();
// ==== end thornswood chat commands ====
