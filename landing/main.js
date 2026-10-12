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
   한국어 / 日本語 / English 전환
   - 한국어가 원문(HTML). 일본어·영어는 아래 I18N_JA / I18N_EN 사전을 data-i18n 키로 적용.
   - 결정 순서: ?lang=(ko|ja|en) → 직접 고른 언어(localStorage 'eg_lang')
                → 브라우저 첫 언어(ja* → 日本語, en*·fil*·tl* → English)
                → api.eggplant.life/api/geo 의 market ('jp' → 日本語, 'ph' → English, 실패해도 무시)
                → 한국어
   - 정책 숫자는 서버 코드(workers-server/src/qta.ts 등)와 같아야 한다.
   ==================================================================== */
(() => {
  'use strict';

  const I18N_JA = {
    title: 'Eggplant 🍆 — QRでつながる地域のフリマ',
    aria_home: 'Eggplant ホーム',
    aria_menu: 'メニューを開く',
    aria_stats: '主な数字',
    aria_nav: 'メインメニュー',
    aria_mascot: 'Eggplant マスコット',
    meta_desc: 'Eggplant 🍆 — 本名・電話番号なしでニックネームから始める地域のフリマ。出品すると価格の10%をQTAでマイニング。日本・韓国・フィリピンでサービス。',
    og_title: 'Eggplant 🍆 — QRでつながる地域のフリマ',
    og_desc: 'ニックネームで登録し、出品すると価格の10%をQTAでマイニング。消えるチャット+地域の取引+耐量子ウォレット認証。',

    nav_features: '機能',
    nav_qta: 'QTAマイニング',
    nav_verify: '認証',
    nav_japan: '日本・韓国・フィリピン',
    nav_faq: 'よくある質問',
    nav_cta: 'アプリを入手',

    hero_badge: '🇯🇵 日本 · 🇰🇷 韓国 · 🇵🇭 フィリピンの地域フリマ',
    hero_h1: '本名も電話番号もなしで<br/><span class="grad">QRひとつで取引</span>',
    hero_sub: 'Eggplantは<b>ニックネーム</b>で登録して、<b>QRコードを読み取るだけ</b>でチャットが始まる地域密着のフリマアプリです。チャットは<b>サーバーに保存されず</b>、出品すると<b>価格の10%がQTA</b>として貯まります。',
    hero_cta_apk: 'Android版APKをダウンロード',
    hero_cta_more: '機能を見る',
    stat_listing: '出品マイニング',
    stat_chat_num: '0件',
    stat_chat: 'チャットのサーバー保存',
    stat_market: '3か国でサービス',
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
    v1_p: '運営のウォレットから<b>耐量子SPHINCS+署名</b>(Quantarium type 0x7f)で、あなたのウォレットに<b>5.xxxxxx QTA</b>を送ります。次に、アプリに表示された<b>1.xxxxxx QTA</b>をあなたのウォレットから運営のウォレットへ送り返せば完了です。送金できるのはウォレットの持ち主だけなので、あなたのウォレットであることが証明されます。数量は1回限りで、再利用はできません。',
    v2_h: 'ステップ2 · 電話番号認証 <span class="tag soon">まもなく開始</span>',
    v2_p: '日本(+81、070/080/090)・韓国(+82、010など)・フィリピン(+63、09xx)の<b>携帯電話番号のみ</b>認証できます。1つの番号で認証できるのは1アカウントだけです。先にステップ1を終えてください。',
    v3_h: '電話番号は暗号化して別に保管',
    v3_p: '認証した番号は<b>AES-256で暗号化</b>して別に保管し、画面やほかのユーザーには<b>一切公開しません</b>。不正利用者の追跡や、捜査機関からの適法な要請に対応するときにだけ使います。退会すると番号はすぐに削除します。',
    v_note: '運営から送るQTA(ウォレット認証の5.xxxxxx送金・出金)は、すべて耐量子署名トランザクションだけで処理します。scan.quantarium.io で取引を開くと<b>SPHINCS+</b>と表示されます。',

    j_h2: '<span class="grad">日本・韓国・フィリピン</span>どこでも',
    j_sub: 'アプリで言語(한국어 / 日本語 / English)を選ぶと、登録時にそれに合った地域・通貨が決まります。',
    j1_h: '韓国',
    j1_p: '韓国語 · ウォン(₩) · 韓国の地域。<b>1 QTA = 10ウォン</b>固定なので、10,000ウォンの商品を出品すると100 QTAが貯まります。',
    j2_h: '日本',
    j2_p: '日本語を選んで登録すると、日本語 · 円(¥) · 日本の地域(<b>47都道府県 · 1,892市区町村</b>)で使えます。<b>1 QTA = 1円</b>なので、1,000円の商品なら100 QTAです。',
    j4_h: 'フィリピン',
    j4_p: 'Englishを選んで登録すると、英語 · ペソ(₱) · フィリピンの地域。<b>1 QTA = 1ペソ</b>なので、₱1,000の商品なら100 QTAです。',
    j3_h: '商品は国ごとに別々',
    j3_p: '日本・韓国・フィリピンの商品が混ざることはありません。登録時に決まった国の商品だけが表示され、その国の地域で取引します。',

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
    fa2: '電話番号認証が始まると、認証した番号はAES-256で暗号化して別に保管します。画面やほかのユーザーには公開せず、1つの番号で複数のアカウントを作ることを防ぎ、不正利用者の追跡や捜査機関からの適法な要請に対応するときにだけ使います。退会すると番号はすぐに削除します。認証できるのは日本(070/080/090)・韓国(010など)・フィリピン(09xx)の携帯電話番号だけです。',
    fq3: '出品マイニングはどう計算されますか?',
    fa3: '出品価格の10%をQTAとして付与します。日本は1 QTA = 1円なので1,000円の商品なら100 QTA、韓国は1 QTA = 10ウォン固定なので10,000ウォンの商品なら100 QTA、フィリピンは1 QTA = 1ペソなので₱1,000の商品なら100 QTAです。1商品あたり最大1,000 QTA、1人1日最大3,000 QTAまでです。商品を削除した場合(本人・運営)や運営が非表示にした場合は受け取った分が、値下げした場合は差額分が差し引かれます。マイページ → マイニング履歴からいつでも確認できます。',
    fq4: '新規登録ボーナスの500 QTAはなくなったのですか?',
    fa4: 'はい。現在は登録だけではQTAを付与していません。そのかわり、出品マイニング(価格の10%)、ログイン・閲覧ボーナス、友だち招待(+200 QTA)、ウォレット・電話番号認証の完了ボーナス(+1,000 QTA、電話番号認証の開始後)でQTAを貯められます。',
    fq5: 'チャットのメッセージはどこに保存されますか?',
    fa5: 'サーバーには保存しません。メッセージはWebSocketで相手にリアルタイムで届けるだけで、サーバーのデータベースに会話の内容は残りません。',
    fq6: 'QTAはどうやって出金しますか?',
    fa6: '出金は現在準備中です。電話番号認証が始まったら、ウォレット認証(ステップ1)と電話番号認証(ステップ2)を終えたうえで、残高5,000 QTA以上から5,000単位で、認証したQuantariumウォレットへの出金を申請できます。送金は耐量子(SPHINCS+)署名トランザクションだけで行います。それまでに貯まったQTAはそのまま保管されます。',
    fq7: '日本やフィリピンで使えますか?',
    fa7: 'はい。アプリで日本語を選んで登録すると日本語・円・日本の地域(47都道府県、1,892市区町村)、Englishを選んで登録すると英語・ペソ(₱)・フィリピンの地域で使えます。最初は接続した国に合った言語があらかじめ選ばれています。商品は国ごとに別々に表示されます。',
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
    foot_terms: '利用規約',
    foot_privacy: 'プライバシーポリシー',
    foot_lbs: '位置情報サービス利用規約',
    foot_policy: '運営ポリシー',
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

  // English — 필리핀 출시용. 화폐 예시는 페소(₱), 1 QTA = 1페소 (workers-server/src/market.ts).
  const I18N_EN = {
    title: `Eggplant 🍆 — Buy & sell in your neighborhood with one QR`,
    meta_desc: `Eggplant 🍆 — a neighborhood buy-and-sell app you join with just a nickname. No real name, no phone number. List an item and mine 10% of its price in QTA. Available in the Philippines, Korea and Japan.`,
    og_title: `Eggplant 🍆 — Buy & sell in your neighborhood with one QR`,
    og_desc: `Sign up with a nickname, list items and mine 10% of the price in QTA. Disappearing chat + local trading + quantum-resistant wallet verification.`,
    aria_home: `Eggplant home`,
    aria_menu: `Open menu`,
    aria_stats: `Key numbers`,
    aria_nav: `Main menu`,
    aria_mascot: `Eggplant mascot`,

    nav_features: `Features`,
    nav_qta: `QTA Mining`,
    nav_verify: `Verification`,
    nav_japan: `Philippines · Korea · Japan`,
    nav_faq: `FAQ`,
    nav_cta: `Get the app`,

    hero_badge: `🇵🇭 Philippines · 🇰🇷 Korea · 🇯🇵 Japan`,
    hero_h1: `No real name. No phone number.<br/><span class="grad">Just one QR code to deal.</span>`,
    hero_sub: `Eggplant is a neighborhood marketplace where you sign up with a <b>nickname</b> and start chatting with <b>a single QR scan</b>. Chats are <b>never stored on our servers</b>, and every item you list earns you <b>10% of its price in QTA</b>.`,
    hero_cta_apk: `Download the Android APK`,
    hero_cta_more: `See features`,
    stat_listing: `Listing mining`,
    stat_chat_num: `0`,
    stat_chat: `Chats stored on servers`,
    stat_market: `Available in 3 countries`,
    mock_title: `🍆 Eggplant`,
    mock_item: `Quezon City · Brand-new book`,
    mock_price: `₱1,500`,
    mock_mined: `Listing mined`,
    mock_mined_meta: `⛏️ 10% of price`,

    feat_h2: `Why <span class="grad">Eggplant 🍆</span>?`,
    feat_sub: `6 things that set us apart from other marketplaces`,
    f1_h: `Sign up with a nickname`,
    f1_p: `All you need is a nickname and a password. We never ask for your real name, email or phone number, and <b>other members only see your nickname</b>.`,
    f2_h: `Connect with one QR scan`,
    f2_p: `Scan the other person's QR code and <b>a chat room opens instantly</b>. No friend requests, no swapping contact details.`,
    f3_h: `Disappearing chat`,
    f3_p: `Messages are only delivered in real time and are <b>never saved in our server database</b>. Profanity and hate speech are masked with *** before they're delivered.`,
    f4_h: `List items, mine QTA`,
    f4_p: `You instantly earn <b>10% of the listing price in QTA</b>. Check-ins, browsing and inviting friends earn you QTA too.`,
    f5_h: `Up to 10 neighborhoods`,
    f5_p: `Set <b>up to 10</b> neighborhoods you visit often. GPS neighborhood verification, 2/4/6/10 km distance filters and a manner temperature (36.5℃) help you trade with confidence.`,
    f6_h: `Quantum-resistant wallet verification`,
    f6_p: `Every QTA transfer we send is a <b>SPHINCS+ quantum-resistant signed</b> transaction. Anyone can check it on scan.quantarium.io.`,

    qta_h2: `List items and watch your <span class="grad">QTA</span> grow`,
    qta_p: `The more active you are, the more QTA you collect. Check your mining history anytime under <b>My Page → Mining history</b>.`,
    q_listing_b: `Listing mining`,
    q_listing_i: `10% of the price · 1 QTA = ₱1 (₱1,000 → 100 QTA) · up to 1,000 per item · up to 3,000 QTA a day`,
    q_login_b: `Check-in bonus`,
    q_login_i: `+10 QTA when you log in · up to 3 times a day`,
    q_browse_b: `Browsing mining`,
    q_browse_i: `View 10 other people's items in a day for +10 QTA (once a day)`,
    q_hold_b: `Listed for 7 days`,
    q_hold_i: `+10 QTA when an item on sale stays listed past 7 days (once per item)`,
    q_ref_b: `Invite friends`,
    q_ref_i: `+200 QTA per friend you invite · no limit (taken back if the friend deletes their account)`,
    q_verify_b: `Verification bonus`,
    q_verify_i: `+1,000 QTA when you finish both wallet and phone verification (once per person) · phone verification opens soon`,
    q_trade_b: `Trade completion reward`,
    q_trade_i: `+10 QTA each for seller and buyer when both have verified their phones · coming soon`,
    q_wd_b: `Withdraw to your wallet`,
    q_wd_i: `From 5,000 QTA, in units of 5,000 · after wallet + phone verification · in preparation`,
    qta_note: `※ If an item is deleted (by you or an admin) or hidden by an admin, the QTA earned from it is deducted. Lowering the price deducts the difference; raising it doesn't add more. The old sign-up bonus (+500 QTA) is no longer given.`,
    qta_bar: `Browsed today 7 / 10`,
    qta_balance: `Current balance`,

    v_h2: `<span class="grad">Two-step verification</span> — one person, one account`,
    v_sub: `Only verified members can withdraw and receive trade rewards.`,
    v1_h: `Step 1 · Wallet verification <span class="tag">Available now</span>`,
    v1_p: `The Eggplant HQ wallet sends <b>5.xxxxxx QTA</b> to your wallet with a <b>quantum-resistant SPHINCS+ signature</b> (Quantarium type 0x7f). Then send the <b>1.xxxxxx QTA</b> amount shown in the app from your wallet back to the HQ wallet — that's it. Only the wallet's owner can send from it, so this proves the wallet is yours. Each amount can be used only once.`,
    v2_h: `Step 2 · Phone verification <span class="tag soon">Coming soon</span>`,
    v2_p: `Only <b>mobile numbers</b> from the Philippines (+63, 09xx), Korea (+82, 010 etc.) and Japan (+81, 070/080/090) can be verified. One number can verify only one account. You need to finish step 1 first.`,
    v3_h: `Your number is encrypted and stored separately`,
    v3_p: `Verified numbers are stored separately with <b>AES-256 encryption</b> and are <b>never shown</b> on screen or to other members. We use them only to track illegal or fraudulent users and to respond to lawful requests from law enforcement. When you delete your account, your number is deleted immediately.`,
    v_note: `Every QTA transfer we send (the 5.xxxxxx wallet verification transfer and withdrawals) is made only as a quantum-resistant signed transaction. Open it on scan.quantarium.io and it shows <b>SPHINCS+</b>.`,

    j_h2: `<span class="grad">Philippines, Korea or Japan</span> — wherever you are`,
    j_sub: `Pick your language in the app — 한국어 / 日本語 / English — and the matching region and currency are set when you sign up.`,
    j1_h: `Korea`,
    j1_p: `Korean · won (₩) · Korean neighborhoods. <b>1 QTA = ₩10</b> fixed, so listing a ₩10,000 item earns 100 QTA.`,
    j2_h: `Japan`,
    j2_p: `Sign up in 日本語 for Japanese · yen (¥) · Japanese regions (<b>47 prefectures · 1,892 municipalities</b>). <b>1 QTA = ¥1</b>, so a ¥1,000 item earns 100 QTA.`,
    j4_h: `Philippines`,
    j4_p: `Sign up in English for English · peso (₱) · Philippine neighborhoods. <b>1 QTA = ₱1</b>, so a ₱1,000 item earns 100 QTA.`,
    j3_h: `Separate listings for each country`,
    j3_p: `Listings from the Philippines, Korea and Japan never mix. You only see items from the country set when you signed up, and you trade in that country's neighborhoods.`,

    how_h2: `Start trading in <span class="grad">3 easy steps</span>`,
    how_sub: `From sign-up to your first chat in about a minute.`,
    s1_h: `Sign up with a nickname & password`,
    s1_p: `No real name, email or phone number. Just pick a nickname, a password and your neighborhood.`,
    s2_h: `List an item or scan a QR`,
    s2_p: `Post photos to list an item and earn 10% of its price in QTA. Scan someone's QR code and a chat opens right away.`,
    s3_h: `Disappearing chat → deal → review`,
    s3_p: `Conversations don't stay on the server. After a deal, you leave each other a review and build up your manner temperature.`,

    t_h2: `Built on <span class="grad">trusted infrastructure</span>`,
    t_sub: `Fast and secure, running on a global edge network.`,
    t1_p: `A full-stack edge setup with Workers + D1 + R2 responds quickly from a location near you.`,
    t2_h: `Security`,
    t2_p: `HTTPS · WebSocket TLS · JWT authentication. Phone numbers are stored with AES-256-GCM encryption.`,
    t3_h: `Real-time chat & calls`,
    t3_p: `Real-time chat on Durable Objects and voice calls powered by Agora.`,
    t4_h: `Quantum-resistant transfers`,
    t4_p: `QTA is sent only as SPHINCS+ signed transactions (type 0x7f) on the Quantarium chain.`,

    dl_h2: `Start using <span class="grad">Eggplant</span> today`,
    dl_p: `Install the Android APK and list your first item to earn <b>10% of its price in QTA</b>.`,
    dl_cta: `📥 Download the Android APK`,
    dl_help: `Installation help`,
    dl_note: `iOS version coming soon. 🍎`,

    faq_h2: `Frequently asked questions`,
    faq_sub: `Our most common questions about installing, using the app and QTA`,
    fq1: `Can I really sign up without a phone number?`,
    fa1: `Yes. You sign up with just a nickname and a password — there's no screen asking for your real name, email or phone number. Phone verification (step 2) opens soon, and you only need it if you want to withdraw, get trade rewards, trade with QTA payments or receive the verification bonus.`,
    fq2: `What is my phone number used for?`,
    fa2: `Once phone verification opens, verified numbers are stored separately with AES-256 encryption. They're never shown on screen or to other members, and are used only to stop one number from creating multiple accounts, to track illegal or fraudulent users, and to respond to lawful requests from law enforcement. When you delete your account, your number is deleted immediately. Only mobile numbers from the Philippines (09xx), Korea (010 etc.) and Japan (070/080/090) can be verified.`,
    fq3: `How is listing mining calculated?`,
    fa3: `You get 10% of the listing price in QTA. In the Philippines 1 QTA = ₱1, so a ₱1,000 item earns 100 QTA. In Japan 1 QTA = ¥1 (¥1,000 → 100 QTA), and in Korea 1 QTA = ₩10 fixed (₩10,000 → 100 QTA). The limit is 1,000 QTA per item and 3,000 QTA per person per day. If an item is deleted (by you or an admin) or hidden by an admin, the QTA you received for it is deducted; if you lower the price, the difference is deducted. You can check anytime under My Page → Mining history.`,
    fq4: `Is the 500 QTA sign-up bonus gone?`,
    fa4: `Yes — signing up alone no longer earns QTA. Instead, you can collect QTA through listing mining (10% of the price), check-in and browsing bonuses, inviting friends (+200 QTA), and the wallet + phone verification bonus (+1,000 QTA, once phone verification opens).`,
    fq5: `Where are chat messages stored?`,
    fa5: `They aren't stored on our servers. Messages are only delivered to the other person in real time over WebSocket, and no conversation content is left in our server database.`,
    fq6: `How do I withdraw QTA?`,
    fa6: `Withdrawals are being prepared. Once phone verification opens, after completing wallet verification (step 1) and phone verification (step 2), you can request a withdrawal to your verified Quantarium wallet in units of 5,000 QTA once your balance reaches 5,000 QTA. Transfers go out only as quantum-resistant (SPHINCS+) signed transactions. Any QTA you collect in the meantime is kept as is.`,
    fq7: `Can I use it in the Philippines?`,
    fa7: `Yes. Choose English in the app and sign up to use it in English with pesos (₱) and Philippine neighborhoods. On first launch, the language for the country you're connecting from is pre-selected. Listings are shown separately for each country.`,
    fq8: `I get an "unknown sources" warning when installing the APK.`,
    fa8: `Android requires a one-time permission to install APKs from outside Google Play. Go to Settings → Apps → your browser (e.g. Chrome) → turn on "Install unknown apps", then install.`,
    fq9: `What happens if someone scams me?`,
    fa9: `You can report and block the other person in the app. Our team reviews reports, hides or deletes listings and suspends accounts. Once phone verification opens, we use the encrypted stored numbers to track illegal users and cooperate with law enforcement requests.`,
    fq10: `When is the iOS version coming?`,
    fa10: `We're preparing to launch on the App Store. We'll announce it here first as soon as it's out.`,

    foot_tag: `The neighborhood marketplace that connects you with one QR`,
    foot_product: `Product`,
    foot_download: `Download the app`,
    foot_support: `Support`,
    foot_api: `API status`,
    foot_mail: `Contact us`,
    foot_legal: `Legal`,
    foot_terms: `Terms of Service`,
    foot_privacy: `Privacy Policy`,
    foot_lbs: `Location-Based Services Terms`,
    foot_policy: `Community Policy`,
    foot_biz: `Business information`,
    foot_disclaimer: `Eggplant, operated by Quantarium Co., Ltd. (주식회사 퀀타리움), is <b>a mail-order sales intermediary and is not a party to mail-order sales.</b> Responsibility for the items, transaction information and transactions between users lies with the parties to the transaction, and the Company bears no direct responsibility except to the extent required by law.`,
    c_name: `Company name`,
    c_ceo: `CEO`,
    c_brn: `Business registration no. (Korea)`,
    c_crn: `Corporate registration no. (Korea)`,
    c_mail_order: `Mail-order business registration (Korea)`,
    c_cs: `Customer center (Korea)`,
    c_email: `Email`,
    c_youth: `Youth protection officer`,
    c_addr: `Address`,
  };

  const I18N = { ja: I18N_JA, en: I18N_EN };
  const LABEL = { ko: '한국어', ja: '日本語', en: 'English' };

  const KEY = 'eg_lang';
  const original = new Map();     // element → 원문 innerHTML
  const originalAria = new Map(); // element → 원문 aria-label
  const originalTitle = document.title;
  // 언어별 meta (description / og:title / og:description) — 한국어 원문은 HTML 에서.
  const META = [
    ['meta[name="description"]', 'meta_desc'],
    ['meta[property="og:title"]', 'og_title'],
    ['meta[property="og:description"]', 'og_desc'],
  ].map(([sel, key]) => {
    const el = document.querySelector(sel);
    return el ? { el, key, ko: el.getAttribute('content') || '' } : null;
  }).filter(Boolean);
  let current = 'ko';

  function apply(lang) {
    if (!I18N[lang]) lang = 'ko';
    const dict = lang === 'ko' ? null : I18N[lang];
    const pick = (key, fallback) => (dict && dict[key] != null ? dict[key] : fallback);
    document.querySelectorAll('[data-i18n]').forEach((el) => {
      if (!original.has(el)) original.set(el, el.innerHTML);
      el.innerHTML = pick(el.getAttribute('data-i18n'), original.get(el));
    });
    document.querySelectorAll('[data-i18n-aria]').forEach((el) => {
      if (!originalAria.has(el)) originalAria.set(el, el.getAttribute('aria-label') || '');
      el.setAttribute('aria-label', pick(el.getAttribute('data-i18n-aria'), originalAria.get(el)));
    });
    // 하단 법적 고지 링크 — 일본어·영어면 /ja/… · /en/… 번역본으로.
    document.querySelectorAll('a[data-legal]').forEach((a) => {
      const page = a.getAttribute('data-legal');
      a.setAttribute('href', lang === 'ko' ? '/' + page : '/' + lang + '/' + page);
    });
    META.forEach((m) => m.el.setAttribute('content', pick(m.key, m.ko)));
    document.title = pick('title', originalTitle);
    document.documentElement.lang = lang;
    document.querySelectorAll('.lang-menu [data-lang]').forEach((b) => {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-lang') === lang));
    });
    const lbl = document.getElementById('langLabel');
    if (lbl) lbl.textContent = LABEL[lang];
    current = lang;
  }

  // 'ja-JP' → ja, 'en-PH' / 'fil' / 'tl' → en, 'ko-KR' → ko
  function norm(v) {
    v = String(v || '').toLowerCase();
    if (v === 'ja' || v === 'jp' || v.startsWith('ja-')) return 'ja';
    if (v === 'ko' || v === 'kr' || v.startsWith('ko-')) return 'ko';
    if (v === 'en' || v === 'ph' || v === 'fil' || v === 'tl' ||
        v.startsWith('en-') || v.startsWith('fil-') || v.startsWith('tl-')) return 'en';
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
        if (l === 'ko') u.searchParams.delete('lang'); else u.searchParams.set('lang', l);
        history.replaceState(null, '', u.pathname + u.search + u.hash);
      } catch (e) { /* 무시 */ }
    });
  });

  let fromQuery = null;
  try { fromQuery = norm(new URLSearchParams(location.search).get('lang')); } catch (e) { /* 무시 */ }
  const chosen = fromQuery || saved();
  if (chosen) { apply(chosen); return; }

  // 브라우저 첫 번째 언어: ja* → 日本語, en* / fil* / tl* → English, 그 외(ko 등)는 아래 IP 판별.
  const navLangs = (navigator.languages && navigator.languages.length) ? navigator.languages : [navigator.language || ''];
  const fromBrowser = norm(navLangs[0]);
  if (fromBrowser === 'ja' || fromBrowser === 'en') { apply(fromBrowser); return; }

  // 일본 IP 면 일본어, 필리핀 IP 면 영어 — 서버에 /api/geo 가 없거나 느려도 한국어로 그대로 둔다.
  if (!window.fetch) return;
  const ctrl = ('AbortController' in window) ? new AbortController() : null;
  const timer = setTimeout(() => { if (ctrl) ctrl.abort(); }, 3000);
  fetch('https://api.eggplant.life/api/geo', { cache: 'no-store', signal: ctrl ? ctrl.signal : undefined })
    .then((r) => (r.ok ? r.json() : null))
    .then((j) => {
      // 그사이 사용자가 직접 골랐으면 건드리지 않는다.
      if (!j || saved() || current !== 'ko') return;
      if (j.market === 'jp') apply('ja');
      else if (j.market === 'ph') apply('en');
    })
    .catch(() => { /* 무시 — 한국어 유지 */ })
    .finally(() => clearTimeout(timer));
})();
