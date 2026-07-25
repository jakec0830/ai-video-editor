# 疊加卡片(Overlay Cards)— 下標 + 數字卡

> 給 AI:學員要「打名字下標」「秀一個數字」「跳一張重點卡」時,從這裡抄。
> 全部純 CSS + GSAP,直式原生,免下載任何 block。都在真影片上驗過(含毛玻璃)。

## 一句話:什麼是疊加卡片

就是**疊在影片上面的一張小卡**,影片照樣在下面播。同一個做法,兩種用途:

- **下標(lower-third)= 講「你是誰」。** 名字、頭銜、IG 帳號。放左下、停久一點、小。
  什麼時候用:自我介紹、一開場、換段落報身分。
- **數字卡 / 重點卡(callout)= 講「重點是什麼」。** 一個數字、一句成果、一句金句。跳出來、停短、大。
  什麼時候用:講到成果數字(業績翻倍、+300%)、想強調的那一句。

底層是同一塊積木:一個 `class="clip"` 的 `<div>`,GSAP 淡入淡出。差別只在**放哪、停多久、裡面裝什麼**。

## 共同規則(照做才不出錯)

- 每張卡:`class="clip"` + `data-start` + `data-duration` + `data-track-index`(比影片大,例如 10)+ 唯一 id。
- **一律待在安全區內**:用 `var(--safe-*)`(gen_captions 已定義:上 220 / 下 450 / 左 50 / 右 100 px)。下標放左下、別壓到 IG 帳號區;數字卡別進右邊按鈕欄。
- 進出用 GSAP:`fade + 些微位移或 scale`,0.3–0.4s。**節制**:一支通常 1–2 張,不疊在同一拍。
- 字型跟著影片:黑體 `"PingFang TC","Microsoft JhengHei"`;宋體 `"Source Han Serif TC VF"`。

---

## 下標 1 · Clean Bar(乾淨橫條)
這是什麼:黑底橫條 + 左邊一條彩色線,最穩、最專業。什麼時候用:預設下標,任何影片都安全。
```html
<div id="lt1" class="clip" data-start="0.5" data-duration="3" data-track-index="10"
     style="position:absolute; left:var(--safe-left); bottom:calc(var(--safe-bottom) + 40px); z-index:20;">
  <div style="background:#111; padding:16px 30px; border-left:8px solid #ff5e5e;">
    <div style="color:#fff; font:800 52px/1.1 'PingFang TC';">吳玫萱</div>
    <div style="color:#ffb3b3; font:600 30px 'PingFang TC';">女生的醫美整形顧問</div>
  </div>
</div>
```

## 下標 2 · Soft Pill(圓角膠囊)
這是什麼:白底圓角、左邊一個綠點,親切。什麼時候用:生活、親和、女性向。
```html
<div id="lt2" class="clip" data-start="0.5" data-duration="3" data-track-index="10"
     style="position:absolute; left:var(--safe-left); bottom:calc(var(--safe-bottom) + 40px); z-index:20;
            display:inline-flex; align-items:center; gap:18px; background:#fff; border-radius:60px;
            padding:16px 36px; box-shadow:0 10px 30px rgba(0,0,0,.35);">
  <span style="width:20px;height:20px;border-radius:50%;background:#22c55e;"></span>
  <span style="color:#111; font:800 46px 'PingFang TC';">吳玫萱</span>
  <span style="color:#666; font:600 30px 'PingFang TC';">醫美顧問</span>
</div>
```

## 下標 3 · Liquid Glass(毛玻璃)
這是什麼:半透明毛玻璃,質感、時髦(iOS 26 那種)。什麼時候用:精品、高質感定位。
注意:毛玻璃在畫面較亂時對比會下降,深色底效果最好。已驗過會 render。
```html
<div id="lt3" class="clip" data-start="0.5" data-duration="3" data-track-index="10"
     style="position:absolute; left:var(--safe-left); bottom:calc(var(--safe-bottom) + 40px); z-index:20;
            padding:20px 34px; border-radius:26px; background:rgba(255,255,255,.14);
            backdrop-filter:blur(22px) saturate(1.5); -webkit-backdrop-filter:blur(22px) saturate(1.5);
            border:1px solid rgba(255,255,255,.3); box-shadow:0 8px 30px rgba(0,0,0,.3);">
  <div style="color:#fff; font:800 50px 'PingFang TC'; text-shadow:0 2px 8px rgba(0,0,0,.4);">吳玫萱</div>
  <div style="color:rgba(255,255,255,.85); font:600 30px 'PingFang TC';">女生的醫美整形顧問</div>
</div>
```

## 數字卡 · 實心(Solid)
這是什麼:深色卡 + 大黃字,對比最強、最好讀。什麼時候用:成果數字、要一眼看懂的重點。
```html
<div id="co1" class="clip" data-start="2" data-duration="2.5" data-track-index="11"
     style="position:absolute; left:50%; top:38%; transform:translateX(-50%); text-align:center;
            width:440px; padding:34px 20px; border-radius:28px; z-index:21;
            background:rgba(10,12,18,.82); box-shadow:0 12px 34px rgba(0,0,0,.4);">
  <div style="color:#ffd400; font:900 96px/1 'PingFang TC';">3 個月</div>
  <div style="color:#fff; font:700 34px 'PingFang TC'; margin-top:8px;">業績翻倍</div>
</div>
```

## 數字卡 · 毛玻璃(Glass)
這是什麼:同上但毛玻璃,較時髦、對比較低。什麼時候用:想要質感、畫面底夠深時。
```html
<div id="co2" class="clip" data-start="2" data-duration="2.5" data-track-index="11"
     style="position:absolute; left:50%; top:38%; transform:translateX(-50%); text-align:center;
            width:440px; padding:34px 20px; border-radius:28px; z-index:21;
            background:rgba(255,255,255,.13); backdrop-filter:blur(22px) saturate(1.5);
            -webkit-backdrop-filter:blur(22px) saturate(1.5); border:1px solid rgba(255,255,255,.3);
            box-shadow:0 12px 34px rgba(0,0,0,.3);">
  <div style="color:#ffd400; font:900 96px/1 'PingFang TC';">+300%</div>
  <div style="color:#fff; font:700 34px 'PingFang TC'; text-shadow:0 2px 8px rgba(0,0,0,.4); margin-top:8px;">詢問度成長</div>
</div>
```

## 進出動畫(GSAP,加在 CREATIVE TIMELINE)
```js
// 下標:左邊滑入
tl.from("#lt1", { x:-40, opacity:0, duration:0.35, ease:"power2.out" }, 0.5)
  .to("#lt1", { opacity:0, duration:0.3 }, 3.2);
// 數字卡:彈一下進場
tl.from("#co1", { scale:0.8, opacity:0, duration:0.3, ease:"back.out(1.6)" }, 2.0)
  .to("#co1", { opacity:0, duration:0.25 }, 4.2);
```
數字用真的、學員講過的(對照事實核對表);沒有的別編。
