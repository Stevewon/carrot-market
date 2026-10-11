/* ====================================================================
   Eggplant 🍆 Landing — main.js
   - 모바일 햄버거 메뉴 토글
   - 스크롤 시 nav 그림자/border 활성화
   - 앵커 링크 부드러운 스크롤 (Safari 보강)
   ==================================================================== */
(() => {
  'use strict';

  const nav     = document.getElementById('nav');
  const burger  = document.getElementById('burger');
  const drawer  = document.getElementById('drawer');

  // ---- 햄버거 메뉴 ----
  if (burger && drawer) {
    burger.addEventListener('click', () => {
      const open = burger.getAttribute('aria-expanded') === 'true';
      burger.setAttribute('aria-expanded', String(!open));
      if (open) {
        drawer.setAttribute('hidden', '');
      } else {
        drawer.removeAttribute('hidden');
      }
    });

    // 드로어 안의 링크 클릭 시 자동 닫기.
    drawer.querySelectorAll('a').forEach((a) => {
      a.addEventListener('click', () => {
        burger.setAttribute('aria-expanded', 'false');
        drawer.setAttribute('hidden', '');
      });
    });
  }

  // ---- 스크롤 시 nav scrolled 클래스 ----
  let ticking = false;
  const onScroll = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      if (nav) {
        if (window.scrollY > 8) nav.classList.add('scrolled');
        else nav.classList.remove('scrolled');
      }
      ticking = false;
    });
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // ---- 앵커 부드러운 스크롤 (Safari 구버전 fallback) ----
  document.querySelectorAll('a[href^="#"]').forEach((a) => {
    a.addEventListener('click', (e) => {
      const id = a.getAttribute('href');
      if (!id || id === '#') return;
      const tgt = document.querySelector(id);
      if (!tgt) return;
      e.preventDefault();
      const navH = nav ? nav.offsetHeight : 0;
      const top  = tgt.getBoundingClientRect().top + window.scrollY - navH - 8;
      window.scrollTo({ top, behavior: 'smooth' });
    });
  });

  // ---- IntersectionObserver: 섹션 페이드인 ----
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (en.isIntersecting) {
          en.target.classList.add('in-view');
          io.unobserve(en.target);
        }
      });
    }, { threshold: 0.12 });
    document.querySelectorAll('.feature, .trust-card, .steps li, .qta-card, .dl-card')
      .forEach((el) => io.observe(el));
  }
})();

/* ====================================================================
   한국어 / 日本語 전환
   - 한국어가 원문(HTML). 일본어는 아래 I18N_JA 사전을 data-i18n 키로 적용.
   - 결정 순서: ?lang= → 직접 고른 언어(localStorage) → 브라우저 언어(ja*)
                → api.eggplant.life/api/geo 의 market==='jp' (실패해도 무시)
   - 정책 숫자는 서버 코드(workers-server/src/qta.ts 등)와 같아야 한다.
   ==================================================================== */
(() => {
  'use strict';

  const I18N_JA = {
    title: 'Eggplant 🍆 — QRでつながる地域のフリマ',
    aria_home: 'Eggplant ホーム',
    aria_menu: 'メニューを開く',
    aria_stats: '主な数字',

    nav_features: '機能',
    nav_qta: 'QTAマイニング',
    nav_verify: '認証',
    nav_japan: '日本・韓国',
    nav_faq: 'よくある質問',
    nav_cta: 'アプリを入手',

    hero_badge: '🇯🇵 日本 · 🇰🇷 韓国の地域フリマ',
    hero_h1: '本名も電話番号もなしで<br/><span class="grad">QRひとつで取引</span>',
    hero_sub: 'Eggplantは<b>ニックネーム</b>で登録して、<b>QRコードを読み取るだけ</b>でチャットが始まる地域密着のフリマアプリです。チャットは<b>サーバーに保存されず</b>、出品すると<b>価格の10%がQTA</b>として貯まります。',
    hero_cta_apk: 'Android版APKをダウンロード',
    hero_cta_more: '機能を見る',
    stat_listing: '出品マイニング',
    stat_chat_num: '0件',
    stat_chat: 'チャットのサーバー保存',
    stat_market: '日本・韓国でサービス',
    mock_title: '🍆 Eggplant',
    mock_item: '東京 渋谷区 · 新品の本',
    mock_price: '1,500円',
    mock_mined: '出品マイニング完了',
    mock_mined_meta: '⛏️ 価格の10%',

    feat_h2: '<span class="grad">Eggplant 🍆</span> が選ばれる理由',
    feat_sub: 'ほかのフリマとはここが違う、6つのポイント',
    f1_h: 'ニックネームで登録',
    f1_p: 'ニックネームとパスワードだけで登録できます。本名・メールアドレス・電話番号は聞かず、<b>ほかのユーザーに見えるのはニックネームだけ</b>です。',
    f2_h: 'QRでかんたんにつながる',
    f2_p: '相手のQRを読み取ると<b>すぐにチャットルーム</b>が開きます。友だち追加も連絡先の交換もいりません。',
    f3_h: '消えるチャット',
    f3_p: 'メッセージはリアルタイムで届けるだけで、<b>サーバーのデータベースには保存しません</b>。暴言や差別的な表現は、相手に届く前に***で隠されます。',
    f4_h: '出品するとQTAをマイニング',
    f4_p: '出品価格の<b>10%をQTA</b>としてすぐに付与します。ログイン・閲覧・友だち招待でもQTAが貯まります。',
    f5_h: 'よく行く地域を最大10か所',
    f5_p: 'よく行く地域を<b>最大10か所</b>まで設定できます。GPSでの地域認証、2・4・6・10kmの距離フィルター、マナー温度(36.5℃)で安心して取引できます。',
    f6_h: '耐量子ウォレット認証',
    f6_p: '運営から送るQTAはすべて<b>SPHINCS+の耐量子署名</b>トランザクションです。scan.quantarium.io で誰でも確認できます。',

    qta_h2: '出品すると<span class="grad">QTA</span>が貯まる',
    qta_p: '使うほどQTAが貯まります。マイニングの記録は<b>マイページ → マイニング履歴</b>からいつでも確認できます。',
    q_listing_b: '出品マイニング',
    q_listing_i: '価格の10% · 1 QTA = 1円(1,000円 → 100 QTA)· 1商品あたり最大1,000 · 1日最大3,000 QTA',
    q_login_b: 'ログインボーナス',
    q_login_i: 'ログインするたびに+10 QTA · 1日最大3回',
    q_browse_b: '閲覧マイニング',
    q_browse_i: '1日にほかの人の商品を10件見ると+10 QTA(1日1回)',
    q_hold_b: '7日間の出品継続',
    q_hold_i: '販売中の商品が7日を過ぎると+10 QTA(1商品につき1回)',
    q_ref_b: '友だち招待',
    q_ref_i: '招待した友だち1人につき+200 QTA · 上限なし(友だちが退会すると回収)',
    q_verify_b: '認証完了ボーナス',
    q_verify_i: 'ウォレット認証と電話番号認証の両方を終えると+1,000 QTA(1人1回)· 電話番号認証はまもなく開始',
    q_trade_b: '取引完了ボーナス',
    q_trade_i: '出品者・購入者がともに電話番号認証を終えていれば各+10 QTA · まもなく開始',
    q_wd_b: 'ウォレットへの出金',
    q_wd_i: '5,000 QTAから5,000単位 · ウォレット+電話番号認証のあと · 準備中',
    qta_note: '※ 商品を削除した場合(本人・運営)や運営が非表示にした場合、その商品で受け取ったQTAは差し引かれます。値下げすると差額分が差し引かれ、値上げしても追加の付与はありません。以前の新規登録ボーナス(+500 QTA)は現在付与していません。',
    qta_bar: '今日の閲覧 7 / 10',
    qta_balance: '現在の残高',

    v_h2: '<span class="grad">2段階認証</span>で1人1アカウント',
    v_sub: '出金と取引完了ボーナスは、認証を終えた方だけが受け取れます。',
    v1_h: 'ステップ1 · ウォレット認証 <span class="tag">利用できます</span>',
    v1_p: '運営のウォレットから<b>耐量子SPHINCS+署名</b>(Quantarium type 0x7f)で、あなたのウォレットに少額(1 QTA未満)を送ります。<b>scan.quantarium.io</b> で受け取った数量(小数点以下6桁)を確認して入力すれば完了です。',
    v2_h: 'ステップ2 · 電話番号認証 <span class="tag soon">まもなく開始</span>',
    v2_p: '日本(+81、070/080/090)・韓国(+82、010など)の<b>携帯電話番号のみ</b>認証できます。1つの番号で認証できるのは1アカウントだけです。先にステップ1を終えてください。',
    v3_h: '電話番号は暗号化して別に保管',
    v3_p: '認証した番号は<b>AES-256で暗号化</b>して別に保管し、画面やほかのユーザーには<b>一切公開しません</b>。不正利用者の追跡や、捜査機関からの適法な要請に対応するときにだけ使います。退会すると番号はすぐに削除します。',
    v_note: '運営から送るQTA(ウォレット認証の少額送金・出金)は、すべて耐量子署名トランザクションだけで処理します。scan.quantarium.io で取引を開くと<b>SPHINCS+</b>と表示されます。',

    j_h2: '<span class="grad">日本・韓国</span>どちらでも',
    j_sub: 'アクセスした国に合わせて、言語・地域・通貨が決まります。',
    j1_h: '韓国',
    j1_p: '韓国語 · ウォン(₩) · 韓国の地域。<b>1 QTA = 10ウォン</b>固定なので、10,000ウォンの商品を出品すると100 QTAが貯まります。',
    j2_h: '日本',
    j2_p: '日本のIPからアクセスすると、日本語 · 円(¥) · 日本の地域(<b>47都道府県 · 1,892市区町村</b>)で使えます。<b>1 QTA = 1円</b>なので、1,000円の商品なら100 QTAです。',
    j3_h: '商品は国ごとに別々',
    j3_p: '日本の商品と韓国の商品が混ざることはありません。登録時に決まった国の商品だけが表示され、その国の地域で取引します。',

    how_h2: '3ステップで<span class="grad">取引スタート</span>',
    how_sub: '登録から最初のチャットまで、1分あれば十分です。',
    s1_h: 'ニックネームとパスワードで登録',
    s1_p: '本名・メールアドレス・電話番号の入力はなし。ニックネームとパスワード、地域を選ぶだけで始められます。',
    s2_h: '出品する or QRを読み取る',
    s2_p: '写真を撮って出品すると、価格の10%がQTAとして貯まります。相手のQRを読み取れば、すぐにチャットが始まります。',
    s3_h: '消えるチャット → 取引 → 評価',
    s3_p: '会話はサーバーに残りません。取引が終わったらお互いに評価を残して、マナー温度が上がっていきます。',

    t_h2: '安心の<span class="grad">技術基盤</span>',
    t_sub: 'グローバルなエッジ上で、速く安全に動きます。',
    t1_p: 'Workers + D1 + R2 のフルスタック・エッジ基盤で、近くの拠点からすばやく応答します。',
    t2_h: 'セキュリティ',
    t2_p: 'HTTPS · WebSocket TLS · JWT認証。電話番号はAES-256-GCMで暗号化して保管します。',
    t3_h: 'リアルタイムのチャット・通話',
    t3_p: 'Durable Objectsによるリアルタイムチャットと、Agoraによる音声通話に対応しています。',
    t4_h: '耐量子送金',
    t4_p: 'Quantariumチェーンの SPHINCS+ 署名トランザクション(type 0x7f)だけでQTAを送ります。',

    dl_h2: 'さっそく<span class="grad">Eggplant</span>をはじめよう',
    dl_p: 'Android版APKをインストールして最初の商品を出品すると、<b>価格の10%がQTA</b>として貯まります。',
    dl_cta: '📥 Android版APKをダウンロード',
    dl_help: 'インストールのヘルプ',
    dl_note: 'iOS版はまもなく公開予定です。🍎',

    faq_h2: 'よくある質問',
    faq_sub: 'インストール・使い方・QTAについて、よくいただく質問',
    fq1: '本当に電話番号なしで登録できますか?',
    fa1: 'はい。ニックネームとパスワードだけで登録できます。本名・メールアドレス・電話番号を入力する画面はありません。電話番号認証(ステップ2)はまもなく始まりますが、出金・取引完了ボーナス・QTA決済の取引・認証ボーナスを利用したい方だけが行えば大丈夫です。',
    fq2: '電話番号は何に使われますか?',
    fa2: '電話番号認証が始まると、認証した番号はAES-256で暗号化して別に保管します。画面やほかのユーザーには公開せず、1つの番号で複数のアカウントを作ることを防ぎ、不正利用者の追跡や捜査機関からの適法な要請に対応するときにだけ使います。退会すると番号はすぐに削除します。認証できるのは日本(070/080/090)・韓国(010など)の携帯電話番号だけです。',
    fq3: '出品マイニングはどう計算されますか?',
    fa3: '出品価格の10%をQTAとして付与します。日本は1 QTA = 1円なので1,000円の商品なら100 QTA、韓国は1 QTA = 10ウォン固定なので10,000ウォンの商品なら100 QTAです。1商品あたり最大1,000 QTA、1人1日最大3,000 QTAまでです。商品を削除した場合(本人・運営)や運営が非表示にした場合は受け取った分が、値下げした場合は差額分が差し引かれます。マイページ → マイニング履歴からいつでも確認できます。',
    fq4: '新規登録ボーナスの500 QTAはなくなったのですか?',
    fa4: 'はい。現在は登録だけではQTAを付与していません。そのかわり、出品マイニング(価格の10%)、ログイン・閲覧ボーナス、友だち招待(+200 QTA)、ウォレット・電話番号認証の完了ボーナス(+1,000 QTA、電話番号認証の開始後)でQTAを貯められます。',
    fq5: 'チャットのメッセージはどこに保存されますか?',
    fa5: 'サーバーには保存しません。メッセージはWebSocketで相手にリアルタイムで届けるだけで、サーバーのデータベースに会話の内容は残りません。',
    fq6: 'QTAはどうやって出金しますか?',
    fa6: '出金は現在準備中です。電話番号認証が始まったら、ウォレット認証(ステップ1)と電話番号認証(ステップ2)を終えたうえで、残高5,000 QTA以上から5,000単位で、認証したQuantariumウォレットへの出金を申請できます。送金は耐量子(SPHINCS+)署名トランザクションだけで行います。それまでに貯まったQTAはそのまま保管されます。',
    fq7: '日本で使えますか?',
    fa7: 'はい。日本のIPからアクセスすると、日本語・円・日本の地域(47都道府県、1,892市区町村)で開きます。日本の商品と韓国の商品は別々に表示されます。',
    fq8: 'APKのインストール時に「提供元不明のアプリ」の警告が出ます。',
    fa8: 'Androidの仕様で、Google Play以外からAPKをインストールするときは一度だけ許可が必要です。設定 → アプリ → ブラウザ(Chromeなど)→「不明なアプリのインストール」を許可してからインストールしてください。',
    fq9: '取引でトラブルや詐欺にあったら?',
    fa9: 'アプリから相手を通報・ブロックできます。運営が通報を確認し、商品の非表示・削除やアカウントの停止を行います。電話番号認証の開始後は、暗号化して保管した番号で不正利用者を追跡し、捜査機関の要請に協力します。',
    fq10: 'iOS版はいつ出ますか?',
    fa10: 'App Storeでの公開を準備しています。公開したら、このページでいち早くお知らせします。',

    foot_tag: 'QRでつながる地域のフリマアプリ',
    foot_product: 'サービス',
    foot_download: 'アプリをダウンロード',
    foot_support: 'サポート',
    foot_api: 'APIステータス',
    foot_mail: 'お問い合わせ',
    foot_legal: '法的情報',
    foot_terms: '利用規約(韓国語)',
    foot_privacy: 'プライバシーポリシー(韓国語)',
    foot_lbs: '位置情報サービス利用規約(韓国語)',
    foot_policy: '運営ポリシー(韓国語)',
    foot_biz: '事業者情報',
    foot_disclaimer: '株式会社Quantarium(주식회사 퀀타리움)が運営するEggplantは<b>通信販売の仲介者であり、通信販売の当事者ではありません。</b>ユーザー間の取引における商品・取引情報・取引に関する責任は取引の当事者にあり、当社は法令で求められる範囲を除き、直接の責任を負いません。',
    c_name: '商号',
    c_ceo: '代表取締役',
    c_brn: '事業者登録番号(韓国)',
    c_crn: '法人登録番号(韓国)',
    c_mail_order: '通信販売業申告(韓国)',
    c_cs: 'カスタマーセンター(韓国)',
    c_email: 'メール',
    c_youth: '青少年保護責任者',
    c_addr: '所在地',
  };

  const KEY = 'eg_lang';
  const original = new Map();     // element → 원문 innerHTML
  const originalAria = new Map(); // element → 원문 aria-label
  const originalTitle = document.title;
  let current = 'ko';

  function apply(lang) {
    if (lang !== 'ja') lang = 'ko';
    document.querySelectorAll('[data-i18n]').forEach((el) => {
      if (!original.has(el)) original.set(el, el.innerHTML);
      const ja = I18N_JA[el.getAttribute('data-i18n')];
      el.innerHTML = lang === 'ja' && ja != null ? ja : original.get(el);
    });
    document.querySelectorAll('[data-i18n-aria]').forEach((el) => {
      if (!originalAria.has(el)) originalAria.set(el, el.getAttribute('aria-label') || '');
      const ja = I18N_JA[el.getAttribute('data-i18n-aria')];
      el.setAttribute('aria-label', lang === 'ja' && ja != null ? ja : originalAria.get(el));
    });
    document.title = lang === 'ja' ? I18N_JA.title : originalTitle;
    document.documentElement.lang = lang;
    document.querySelectorAll('.lang-menu [data-lang]').forEach((b) => {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-lang') === lang));
    });
    const lbl = document.getElementById('langLabel');
    if (lbl) lbl.textContent = lang === 'ja' ? '日本語' : '한국어';
    current = lang;
  }

  function norm(v) {
    v = String(v || '').toLowerCase();
    if (v === 'ja' || v === 'jp') return 'ja';
    if (v === 'ko' || v === 'kr') return 'ko';
    return null;
  }

  function saved() {
    try { return norm(localStorage.getItem(KEY)); } catch (e) { return null; }
  }

  // 드롭다운 열기/닫기 (qrchat.io 방식)
  const langBtn = document.getElementById('langBtn');
  const langMenu = document.getElementById('langMenu');
  const closeMenu = () => {
    if (!langMenu) return;
    langMenu.classList.remove('open');
    if (langBtn) langBtn.setAttribute('aria-expanded', 'false');
  };
  if (langBtn && langMenu) {
    langBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const open = langMenu.classList.toggle('open');
      langBtn.setAttribute('aria-expanded', String(open));
    });
    document.addEventListener('click', closeMenu);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeMenu(); });
  }

  // 사용자가 직접 고른 언어
  document.querySelectorAll('.lang-menu [data-lang]').forEach((b) => {
    b.addEventListener('click', () => {
      const l = b.getAttribute('data-lang');
      try { localStorage.setItem(KEY, l); } catch (e) { /* 저장 못 해도 화면은 바뀜 */ }
      apply(l);
      closeMenu();
      try {
        const u = new URL(location.href);
        if (l === 'ja') u.searchParams.set('lang', 'ja'); else u.searchParams.delete('lang');
        history.replaceState(null, '', u.pathname + u.search + u.hash);
      } catch (e) { /* 무시 */ }
    });
  });

  let fromQuery = null;
  try { fromQuery = norm(new URLSearchParams(location.search).get('lang')); } catch (e) { /* 무시 */ }
  const chosen = fromQuery || saved();
  if (chosen) { apply(chosen); return; }

  const navLangs = (navigator.languages && navigator.languages.length) ? navigator.languages : [navigator.language || ''];
  if (String(navLangs[0] || '').toLowerCase().startsWith('ja')) { apply('ja'); return; }

  // 일본 IP 면 일본어 — 서버에 /api/geo 가 없거나 느려도 한국어로 그대로 둔다.
  if (!window.fetch) return;
  const ctrl = ('AbortController' in window) ? new AbortController() : null;
  const timer = setTimeout(() => { if (ctrl) ctrl.abort(); }, 3000);
  fetch('https://api.eggplant.life/api/geo', { cache: 'no-store', signal: ctrl ? ctrl.signal : undefined })
    .then((r) => (r.ok ? r.json() : null))
    .then((j) => {
      // 그사이 사용자가 직접 골랐으면 건드리지 않는다.
      if (j && j.market === 'jp' && !saved() && current === 'ko') apply('ja');
    })
    .catch(() => { /* 무시 — 한국어 유지 */ })
    .finally(() => clearTimeout(timer));
})();
