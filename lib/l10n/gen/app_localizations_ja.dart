// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get authWalletRequired => 'ウォレットアドレスを入力してください';

  @override
  String get authWalletFormat => '0xで始まる42文字の形式で入力してください';

  @override
  String get authNicknameRequired => 'ニックネームを入力してください';

  @override
  String get authNicknameTooShort => 'ニックネームは2文字以上で入力してください';

  @override
  String get authNicknameTooLong => 'ニックネームは12文字以内で入力してください';

  @override
  String get authNicknameCharset => 'ひらがな・カタカナ・漢字・英数字・_ のみ使えます（スペース・記号は使えません）';

  @override
  String get authPasswordRequired => 'パスワードを入力してください';

  @override
  String get authPasswordTooShort => 'パスワードは8文字以上で入力してください';

  @override
  String get authPasswordTooLong => 'パスワードは64文字以内で入力してください';

  @override
  String get authPasswordMix => '英字と数字を両方含めてください';

  @override
  String authPhoneCheckExample(String example) {
    return '電話番号をご確認ください(例:$example)';
  }

  @override
  String get authPhoneCheck => '電話番号をご確認ください';

  @override
  String get authTooManyRequests => 'リクエストが多すぎます。しばらくしてから再度お試しください';

  @override
  String get authSmsQuotaExceeded => '本日のSMS送信上限を超えました。明日もう一度お試しください';

  @override
  String authSmsSendFailedCode(String code) {
    return 'SMSを送信できませんでした。しばらくしてから再度お試しください($code)';
  }

  @override
  String get authSmsSendFailed => 'SMSを送信できませんでした。しばらくしてから再度お試しください';

  @override
  String get authSmsCodeInvalid => 'SMSで届いた6桁の数字を入力してください';

  @override
  String get authPhoneVerifyFailedRetry => '電話番号認証を完了できませんでした。もう一度お試しください';

  @override
  String get authSmsCodeWrong => '認証コードが正しくありません';

  @override
  String get authSmsCodeExpired => '認証コードの有効期限が切れました。再度取得してください';

  @override
  String authPhoneVerifyFailedCode(String code) {
    return '電話番号認証を完了できませんでした($code)';
  }

  @override
  String get authPhoneVerifyFailedLater =>
      '電話番号認証を完了できませんでした。しばらくしてから再度お試しください';

  @override
  String get authPhoneStepTitle => 'ステップ2 · 電話番号認証';

  @override
  String get authPhoneStepDesc =>
      'SMSで届いた認証コードを入力すれば完了です。1つの番号で認証できるのは1アカウントのみです。番号は保存されず、確認用の暗号値だけが残ります。';

  @override
  String get authPhoneNumberLabel => '携帯電話番号';

  @override
  String get authSending => '送信中…';

  @override
  String get authGetCode => '認証コードを受け取る';

  @override
  String get authCodeLabel => '認証コード(6桁)';

  @override
  String get authChecking => '確認中…';

  @override
  String get authVerify => '認証する';

  @override
  String get authChangeNumber => '番号を変更';

  @override
  String get authResendCode => '認証コードを再送';

  @override
  String get authResponseSlow => '応答に時間がかかっています。ネットワーク状況を確認して、もう一度お試しください。';

  @override
  String get authRegisterFailed => '登録中に問題が発生しました。しばらくしてから再度お試しください';

  @override
  String authReferralCredited(String nickname) {
    return '🎉 紹介者の$nicknameさんに +200 QTA を付与しました!';
  }

  @override
  String get authReferralNotFound => '紹介者のニックネームが見つからず、招待ボーナスは適用されませんでした。';

  @override
  String get authReferralSelf => 'ご自身を紹介者として入力することはできません。';

  @override
  String get authReferralAlreadyProcessed => 'この招待はすでに処理済みです。';

  @override
  String get authRegisterTitle => '新規登録';

  @override
  String get authRegisterHeadline => 'ニックネームを決めるだけで\nすぐに登録 🍆';

  @override
  String get authRegisterDesc =>
      'ウォレットがなくても登録できます。登録後「マイページ → プロフィール認証」でステップ1 ウォレット認証・ステップ2 電話番号認証を完了すると、1,000 QTA をプレゼントします。';

  @override
  String get authNicknameLabel => 'ニックネーム';

  @override
  String get authNicknameHint => '2〜12文字、重複不可';

  @override
  String get authNicknamePlaceholder => 'なすび123';

  @override
  String get authPasswordLabel => 'パスワード';

  @override
  String get authMin8 => '8文字以上';

  @override
  String get authPasswordPlaceholder => '英字・数字・記号の組み合わせを推奨';

  @override
  String get authPasswordConfirmLabel => 'パスワード(確認)';

  @override
  String get authEnterAgain => 'もう一度入力';

  @override
  String get authPasswordConfirmRequired => '確認用パスワードを入力してください';

  @override
  String get authPasswordMismatch => 'パスワードが一致しません';

  @override
  String get authReferrerLabel => '紹介者のニックネーム(任意)';

  @override
  String get authReferrerHint => '紹介者に +200 QTA・無制限';

  @override
  String get authReferrerPlaceholder => '紹介してくれた方のニックネーム';

  @override
  String get authRegisterBonusInfo =>
      'ウォレット・電話番号認証を完了すると +1,000 QTA をプレゼント!紹介者を入力すると、紹介者に +200 QTA が無制限で付与されます。\n※ 登録後に退会すると、紹介者のボーナスは即時に回収されます。';

  @override
  String get authWalletImmutableInfo =>
      'ウォレットアドレスは変更できません。ニックネーム/パスワードを忘れた場合は、同じウォレットでのみ復旧できます。';

  @override
  String get authRegisterButton => '登録する';

  @override
  String get authHaveAccountLogin => 'アカウントをお持ちの方 — ログイン';

  @override
  String get authServerSlow => 'サーバーの応答が遅れています。しばらくしてから再度お試しください 🕐';

  @override
  String get authLookupFailed => 'アカウントの照会中に問題が発生しました。もう一度お試しください。';

  @override
  String get authPasswordResetDone => 'パスワードを再設定しました 🔒';

  @override
  String get authResetFailed => 'パスワードの再設定中に問題が発生しました。もう一度お試しください。';

  @override
  String get authFindAccountTitle => 'アカウントを探す';

  @override
  String get authFindHeadline => 'ウォレットアドレスで\nアカウントを探します';

  @override
  String get authFindDesc =>
      '登録時に使用した Quantarium ウォレットアドレスを入力してください。\nウォレットの所有を認証すると、ニックネームの確認とパスワードの再設定ができます。';

  @override
  String get authQuantariumWalletLabel => 'Quantarium ウォレットアドレス';

  @override
  String get authPaste => '貼り付け';

  @override
  String get authCheckAccount => 'アカウントを確認';

  @override
  String get authRegisteredNickname => '登録済みのニックネーム';

  @override
  String get authNewPasswordTitle => '新しいパスワードの設定';

  @override
  String get authNewPasswordDesc =>
      '再設定後、ログイン中のすべての端末は自動的にログアウトされます。\nこのアカウントを使っていた端末ならすぐに再設定でき、別の端末やアプリ再インストール後の場合は下のウォレット認証が必要です。';

  @override
  String get authNewPasswordLabel => '新しいパスワード';

  @override
  String get authNewPasswordConfirmLabel => '新しいパスワード(確認)';

  @override
  String get authResetPasswordButton => 'パスワードを再設定';

  @override
  String get authFindAgain => '別のウォレットアドレスで探す';

  @override
  String get authWalletVerifiedInfo => 'ウォレット認証完了 — ご本人のウォレットであることを確認しました';

  @override
  String get authVerifyAgain => 'もう一度認証する';

  @override
  String get authWalletVerifyTitle => 'ウォレット認証';

  @override
  String get authWalletRegisterTitle => 'ウォレット登録';

  @override
  String get authWalletVerifyResetTitle => 'ウォレット認証(別の端末で再設定する場合)';

  @override
  String get authWalletVerifyDescRegister =>
      '他の人にウォレットアドレスを使われないよう、このウォレットから画面に表示されるごく少量(0.1 QTA 未満)を Eggplant 認証ウォレットへ送って、ご本人のウォレットであることを確認します。';

  @override
  String get authWalletVerifyDescVerify =>
      'ご自身の Quantarium ウォレットから画面に表示されるごく少量(0.1 QTA 未満)を Eggplant 認証ウォレットへ送ると、ウォレットの所有者であることが確認されます。出金した QTA はこのウォレットに送金されます。';

  @override
  String get authWalletVerifyDescReset =>
      'このウォレットから画面に表示されるごく少量(0.1 QTA 未満)を Eggplant 認証ウォレットへ送って、ご本人のウォレットであることを確認します。誰かが先にあなたのウォレットで登録していた場合も、この方法でアカウントを取り戻せます。';

  @override
  String get authMyQuantariumWalletLabel => 'あなたの Quantarium ウォレットアドレス';

  @override
  String get authWalletHint42 => '0x + 40文字(計42文字)';

  @override
  String get authPreparing => '準備中…';

  @override
  String get authWalletVerifyStart => 'ウォレット認証を開始';

  @override
  String get authAmountToSend => '送る数量';

  @override
  String get authAmountCopied => '数量をコピーしました';

  @override
  String get authRecipientMyWallet => '送り先アドレス(自分のウォレット)';

  @override
  String get authRecipientEggplantWallet => '送り先アドレス(Eggplant 認証ウォレット)';

  @override
  String get authAddressCopied => 'アドレスをコピーしました';

  @override
  String authWalletSendInstruction(String wallet) {
    return 'Quantarium ウォレットアプリで $wallet から上記の数量を正確に送り、ブロックに取り込まれたら(通常数十秒)下のボタンを押してください。30分以内に送る必要があります。';
  }

  @override
  String get authSentCheck => '送金しました — 確認する';

  @override
  String get authNewAmount => '新しい数量を受け取る';

  @override
  String get authCopy => 'コピー';

  @override
  String get authReceiveAmountInvalid =>
      '小数点以下6桁の数字を入力してください(例:0.234567 なら 234567)';

  @override
  String get authWalletStepTitle => 'ステップ1 · ウォレット認証';

  @override
  String get authWalletStepDesc =>
      'Quantarium ウォレットアドレスを入力すると、Eggplant 本社ウォレットから 5.xxxxxx QTA をお送りします。アプリに表示される 1.xxxxxx QTA を本社ウォレットへ返送すれば認証完了です!(ウォレットの持ち主しか送金できないので安全です)';

  @override
  String get authRequesting => 'リクエスト中…';

  @override
  String get authReceiveCoinButton => 'このウォレットで認証コインを受け取る';

  @override
  String get authReceiveSendFailed => '現在、認証コインを送れませんでした。しばらくしてから再度リクエストしてください';

  @override
  String get authRequestAgain => 'もう一度リクエスト';

  @override
  String authReceiveSending(String wallet) {
    return 'Eggplant 本社ウォレットから $wallet へ送信中です…(通常1分以内)';
  }

  @override
  String authReceiveSent(String wallet) {
    return '送信しました!Quantarium ウォレットアプリで $wallet に届いた数量を確認し、小数点以下6桁を入力してください。ブロックに取り込まれるまで数十秒かかる場合があります。';
  }

  @override
  String get authCheckWalletCode => 'scan.quantarium.io で自分のウォレットを見る';

  @override
  String get authReceivedAmount => '受け取った数量';

  @override
  String authAttemptsLeft(String count) {
    return '残り$count回 · 24時間以内に入力してください';
  }

  @override
  String get authLoginFailed => 'ログイン中に問題が発生しました。もう一度お試しください。';

  @override
  String get authLoginTitle => 'ログイン';

  @override
  String get authLoginDesc =>
      'ニックネームとパスワードでログインしてください。\nQRChat 会員の方は、QRChat のニックネーム・パスワードでそのままログインできます。';

  @override
  String get authLoginNicknameHint => '登録時に設定したニックネーム';

  @override
  String get authLoginButton => 'ログイン';

  @override
  String get authFindNicknamePassword => 'ニックネーム / パスワードを忘れた方';

  @override
  String get authSessionInfo => '別の端末で同じアカウントにログインすると、以前の端末のセッションはすぐに終了します。';

  @override
  String get authSplashTagline => '匿名で安心な中古取引 🍆';

  @override
  String get authOnboarding1Headline => '電話番号なしで\n匿名で取引できます';

  @override
  String get authOnboarding1Desc => 'ニックネームだけでOK。\n個人情報が知られる心配なく安心です。';

  @override
  String get authOnboarding2Headline => '近くの地域の\nご近所さんと取引';

  @override
  String get authOnboarding2Desc => '地域認証済みの人とだけ会えます。\nQRコードで安心して手渡し取引!';

  @override
  String get authOnboarding3Headline => '使うほど貯まる\nQTA トークン報酬';

  @override
  String get authOnboarding3Desc =>
      'ウォレット・電話番号認証で +1,000 QTA、\n友達招待ごとに +200 QTA × 無制限!';

  @override
  String get authPermTitle => '快適にご利用いただくため\n以下の権限が必要です';

  @override
  String get authPermSubtitle => '一度許可すれば、再度確認することはありません。';

  @override
  String get authPermCamera => 'カメラ';

  @override
  String get authPermCameraDesc => 'QRスキャン · 商品の写真/動画撮影';

  @override
  String get authPermMic => 'マイク';

  @override
  String get authPermMicDesc => '匿名音声通話(相手にのみ届きます)';

  @override
  String get authPermPhotos => '写真 / 動画';

  @override
  String get authPermPhotosDesc => 'ギャラリーから商品写真を選択';

  @override
  String get authPermNotifications => '通知';

  @override
  String get authPermNotificationsDesc => '新着チャット · 通話の通知';

  @override
  String get authPermContinue => '確認して続ける';

  @override
  String get authPermLater => 'あとで';

  @override
  String get authSkip => 'スキップ';

  @override
  String get authStart => 'はじめる';

  @override
  String get authNext => '次へ';

  @override
  String get authHaveAccountQuestion => 'アカウントをお持ちですか?';

  @override
  String get authDeleteAgreeRequired => '注意事項に同意いただくと退会できます。';

  @override
  String get authDeletePasswordRequired => 'パスワードを入力してください。';

  @override
  String get authDeleteDialogTitle => '本当に退会しますか?';

  @override
  String get authDeleteDialogBody =>
      'アカウントとすべてのデータが即時に完全削除されます。\n復元はできず、残りの QTA・受け取った紹介ボーナスは回収されます。';

  @override
  String get authDeleteDialogConfirm => '完全に削除';

  @override
  String get authDeleteFailed => '退会処理中に問題が発生しました。もう一度お試しください。';

  @override
  String get authDeleteDone => '退会が完了しました。ご利用ありがとうございました。🍆';

  @override
  String get authDeleteTitle => 'アカウントの完全削除';

  @override
  String get authDeleteWarning => '退会すると即時に完全削除されます\n削除されたデータは復元できません。';

  @override
  String get authDeleteDataTitle => '削除されるデータ';

  @override
  String get authDeleteBullet1 => 'ニックネーム · 地域 · マナースコア · マナーレビュー';

  @override
  String get authDeleteBullet2 => '出品したすべての商品';

  @override
  String authDeleteBullet3(String balance) {
    return '残りの QTA 残高($balance QTA)は破棄';
  }

  @override
  String get authDeleteBullet4 => '受け取った友達招待ボーナスは即時回収(−200 QTA × 人数)';

  @override
  String get authDeleteBullet5 => 'あなたが紹介者になった友達のボーナスも即時回収';

  @override
  String get authDeleteBullet6 => '非表示/ブロック/キーワード通知/検索履歴もすべて削除';

  @override
  String get authDeleteBullet7 => 'チャットメッセージ・通話履歴はもともと保存されていません 🔐';

  @override
  String get authDeleteAgree => '上記の内容をすべて理解し、完全削除に同意します。';

  @override
  String get authDeletePasswordTitle => 'パスワードの再確認';

  @override
  String get authDeleteButton => '完全に削除する';

  @override
  String get authDeleteCancelBack => 'キャンセルして戻る';

  @override
  String get authProfileVerifyTitle => 'プロフィール認証';

  @override
  String get authProfileStepsTitle => '認証ステップ';

  @override
  String get authProfileStep0Title => '登録';

  @override
  String get authProfileStep0Desc =>
      'ニックネーム・パスワードで登録すると自動で完了。\n閲覧 · チャット · 通話 · 出品ができます。';

  @override
  String get authProfileStep1Desc =>
      'Quantarium ウォレットアドレスを入力すると、Eggplant 本社ウォレットから 5.xxxxxx QTA をお送りします。\n受け取ったウォレットから案内された 1.xxxxxx QTA を本社へ送り返せば認証完了!\n出金した QTA はこのウォレットに送金されます。';

  @override
  String get authProfileDoneLabel => '完了済み';

  @override
  String get authProfileWalletDoneSnack => 'ウォレット認証が完了しました。次はステップ2の電話番号認証です!';

  @override
  String get authProfileStep2Title => '電話番号認証';

  @override
  String get authProfileStep2Desc =>
      'SMSで届いた認証コードを入力します。1つの番号で認証できるのは1アカウントのみです。\n取引完了 · QTA 決済取引 · 出金が利用できるようになります。\n\n🔒 電話番号は暗号化して保管し、不正利用の追跡以外には使用しません。日本(070/080/090)・韓国(010)・フィリピン(09)の携帯電話番号のみ認証できます。';

  @override
  String get authProfileWalletFirst => '先にステップ1のウォレット認証を完了してください。';

  @override
  String get authProfileComingSoon => '近日公開';

  @override
  String get authProfilePhoneStart => '電話番号認証を開始';

  @override
  String get authProfileStep1First => '先にステップ1へ';

  @override
  String get authProfilePhoneDoneSnack => '電話番号認証が完了しました';

  @override
  String get authProfilePolicyTitle => '匿名性ポリシー';

  @override
  String get authProfilePolicy1 =>
      'チャット / 音声通話では、認証ステップに関係なく常にニックネームのみが表示されます。';

  @override
  String get authProfilePolicy2 =>
      '認証情報は取引資格の確認にのみ使用され、取引相手や他のユーザーに公開されることはありません。';

  @override
  String get authProfilePolicy3 => '同じウォレット・同じ電話番号で複数のアカウントを認証することはできません。';

  @override
  String get authProfileBonusDialogTitle => '認証完了 🎉';

  @override
  String authProfileBonusDialogBody(String bonus) {
    return 'ステップ1・2の認証がすべて完了しました!\n認証ボーナス +$bonus QTA をプレゼントしました。\nQTA 決済取引と出金ができるようになりました。';
  }

  @override
  String get authProfileAllDone => '認証完了';

  @override
  String get authProfileStep1Done => 'ステップ1完了 · 電話番号認証が残っています';

  @override
  String get authProfileUnverified => '未認証';

  @override
  String authProfileProgress(String done) {
    return '認証 $done/2 ステップ';
  }

  @override
  String authProfileBonusReceived(String bonus) {
    return '認証ボーナス $bonus QTA を受け取りました';
  }

  @override
  String authProfileBonusPending(String bonus) {
    return 'ステップ1・2の認証をすべて完了すると $bonus QTA をプレゼント!';
  }

  @override
  String get authProfileDoneBadge => '完了';

  @override
  String get authGuardPhoneTitle => '電話番号認証が必要です';

  @override
  String get authGuardWalletTitle => 'ウォレット認証が必要です';

  @override
  String get authGuardPhoneMessage =>
      '取引(決済)には、1人1アカウントを保証するため、ステップ1 ウォレット認証とステップ2 電話番号認証が必要です。\n認証後もチャット・通話は匿名のままです。';

  @override
  String get authGuardWalletMessage =>
      'QTA の出金には、ステップ1 ウォレット認証とステップ2 電話番号認証が必要です。\n両方を完了すると 1,000 QTA もプレゼントします。';

  @override
  String get authGuardGoVerify => '認証する';

  @override
  String get authPassPopupTitle => 'Eggplant 本人確認';

  @override
  String get authAccountSuspended => 'このアカウントは利用停止されています';

  @override
  String authRegisterFailedStatus(String status) {
    return '登録に失敗しました(status=$status)';
  }

  @override
  String get authServerTooSlow => 'サーバーの応答が遅すぎます。ネットワークを確認して、もう一度お試しください。';

  @override
  String get authDeleteFailedShort => '退会処理に失敗しました';

  @override
  String get authLoginFailedShort => 'ログインに失敗しました';

  @override
  String get authSsoFailed => 'SSO 認証に失敗しました';

  @override
  String get authNotFound => '見つかりません';

  @override
  String get authResetFailedShort => 'パスワードの再設定に失敗しました';

  @override
  String get authRegionSaveFailed => '地域を保存できませんでした';

  @override
  String get authNicknameLength => 'ニックネームは2〜12文字で入力してください';

  @override
  String get authNicknameChangeFailed => 'ニックネームの変更に失敗しました';

  @override
  String get authWalletVerifyStartFailed => 'ウォレット認証を開始できませんでした';

  @override
  String get authTransferNotConfirmed => 'まだ送金が確認できていません';

  @override
  String get authAmountCheckFailed => '数量を確認できませんでした';

  @override
  String get authCannotConnect => 'サーバーに接続できません。しばらくしてから再度お試しください。';

  @override
  String get authTimeout => '応答がタイムアウトしました。';

  @override
  String get authGenericError => 'エラーが発生しました';

  @override
  String get authQuantumBadge => '耐量子署名(SPHINCS+)で送金された取引です';

  @override
  String get authViewTxOnScan => 'scan.quantarium.io で本社からの送金を見る';

  @override
  String get authResetWalletTitle => 'ウォレット認証(別の端末で再設定する場合)';

  @override
  String get authResetWalletDesc =>
      '登録時のウォレットと一致するかを確認したうえで、Eggplant 本社ウォレットからそのウォレットへ 5.xxxxxx QTA をお送りします。アプリに表示される 1.xxxxxx QTA を本社ウォレットへ返送すれば認証完了です!';

  @override
  String get authResetWalletVerified => 'ウォレット認証が完了しました。下に新しいパスワードを入力してください。';

  @override
  String get authScanHint =>
      'ウォレットアプリで少額が表示されない場合は、上の scan ボタンで画面の Value(例:0.234567 QTA)を確認し、小数点以下6桁を下の欄に入力してください。';

  @override
  String authReturnSent(String wallet, String amount) {
    return 'Eggplant 本社ウォレットから $wallet へ $amount QTA を送金しました。';
  }

  @override
  String get authReturnTitle => 'この数量を本社ウォレットへ返送してください';

  @override
  String get authReturnDesc =>
      'Quantarium ウォレットアプリで、下の数量を正確に下のアドレスへ送金してください。ウォレットの持ち主しか送金できないため、これでご本人のウォレットであることが証明されます。';

  @override
  String get authReturnAmountLabel => '返送する数量(正確に)';

  @override
  String get authReturnToLabel => '送金先(Eggplant 本社ウォレット)';

  @override
  String get authReturnNote =>
      'この数量は今回1回限りです・2時間以内に送金してください・ブロックに取り込まれるまで数十秒かかることがあります';

  @override
  String get authReturnSentButton => '送金しました — 確認する';

  @override
  String get chatLeaveWarningSubtitle => '🔒 退出すると双方から完全に削除されます';

  @override
  String get chatVoiceCallTooltip => '匿名音声通話';

  @override
  String get chatOfferSheetTitle => '💰 価格を提案する';

  @override
  String chatOfferAmountHint(String unit) {
    return '提案金額($unit)';
  }

  @override
  String get chatCurrencyUnitKrw => 'ウォン';

  @override
  String get chatCurrencyUnitJpy => '円';

  @override
  String get chatOfferSend => '提案を送る';

  @override
  String get chatOfferAutoCancelNote => '以前に送った未回答の提案は自動的に取り消されます。';

  @override
  String get chatOfferAccept => '承諾';

  @override
  String get chatOfferReject => '拒否';

  @override
  String get chatOfferCancelAction => '取り消し';

  @override
  String chatOfferDialogTitle(String action) {
    return '価格提案の$action';
  }

  @override
  String get chatOfferAcceptConfirm => 'この価格で取引を進めますか？';

  @override
  String get chatOfferRejectConfirm => '提案を拒否しますか？';

  @override
  String get chatPeerNotFound => '相手の情報が見つかりません';

  @override
  String get chatClearMessages => 'メッセージを削除';

  @override
  String get chatClearMessagesSubtitle => 'このルームのメッセージだけを消去します(ルームは残ります)';

  @override
  String get chatLeaveRoom => 'チャットルームを退出';

  @override
  String get chatLeaveRoomSubtitle => '双方のメッセージとルームを完全に削除します(復元不可)';

  @override
  String chatLeaveRoomConfirm(String nickname) {
    return '$nicknameさんとのチャットを完全に削除しますか？\n\n• すべてのメッセージを完全に削除\n• 相手の画面からもすぐに消えます\n• 復元できません';
  }

  @override
  String get chatDeletePermanently => '完全に削除';

  @override
  String get chatDeleteFailedRetry => '削除に失敗しました。しばらくしてからもう一度お試しください';

  @override
  String get chatClearMessagesConfirm =>
      'このルームのすべてのメッセージを削除しますか？\nルームは残り、相手の画面のメッセージも一緒に削除されます。';

  @override
  String get chatMessagesCleared => 'メッセージを削除しました';

  @override
  String get chatDeleteFailed => '削除に失敗しました';

  @override
  String chatEmptyTitle(String nickname) {
    return '$nicknameさんとの\n匿名チャットが始まりました';
  }

  @override
  String get chatEmptyNote => 'このチャットはサーバーにも端末にも保存されません。\n画面を離れると内容は消えます。';

  @override
  String get chatRead => '既読';

  @override
  String get chatOfferLabel => '価格提案';

  @override
  String get chatInputHint => 'メッセージを入力';

  @override
  String get chatConnecting => '接続中...';

  @override
  String get chatOfferCancelButton => '提案を取り消す';

  @override
  String get chatCallOutgoing => '呼び出し中...';

  @override
  String get chatCallIncoming => '匿名通話の着信';

  @override
  String get chatCallEnded => '通話終了';

  @override
  String get chatCallHeader => '完全匿名の音声通話';

  @override
  String get chatCallP2pNote => 'この通話はP2Pで直接つながります。\nサーバーに録音・保存されることはありません。';

  @override
  String get chatCallDecline => '拒否';

  @override
  String get chatCallAccept => '応答';

  @override
  String get chatCallUnmute => 'ミュート解除';

  @override
  String get chatCallMute => 'ミュート';

  @override
  String get chatCallHangup => '終了';

  @override
  String get chatCallSpeaker => 'スピーカー';

  @override
  String get chatCallEarpiece => '受話口';

  @override
  String chatLeaveRoomConfirmList(String nickname) {
    return '$nicknameさんとのチャットを完全に削除しますか？\n\n• やり取りしたすべてのメッセージが消えます\n• 相手の画面からも削除されます\n• 復元できません';
  }

  @override
  String get chatRoomDeleted => 'チャットルームを削除しました';

  @override
  String get chatTabTitle => 'チャット';

  @override
  String get chatQrScanTooltip => 'QRをスキャンしてチャットを開始';

  @override
  String get chatPrivacyBanner => 'チャットはどこにも保存されません。アプリを閉じると消えます。';

  @override
  String get chatListEmptyTitle => 'まだチャットはありません';

  @override
  String get chatListEmptyHint => '気になる商品の「チャットする」をタップしてみましょう';

  @override
  String get chatSwipeLeave => '退出';

  @override
  String chatRoomAboutProduct(String title) {
    return '$titleについてのチャット';
  }

  @override
  String get chatSendFirstMessage => 'メッセージを送ってみましょう';

  @override
  String chatLastMessageMine(String message) {
    return '自分: $message';
  }

  @override
  String get chatAnonymous => '匿名';

  @override
  String get chatEnterAmount => '金額を入力してください';

  @override
  String get chatReconnecting => '接続中です。しばらくしてからもう一度お試しください';

  @override
  String get chatRoomNotFound => 'チャットルームが見つかりません';

  @override
  String get chatNewMessage => '新しいメッセージ';

  @override
  String get chatEnterMessage => '内容を入力してください';

  @override
  String get chatCallPeerDeclined => '相手が通話を拒否しました';

  @override
  String get chatCallRetryLater => '接続できませんでした。しばらくしてからもう一度おかけください。';

  @override
  String get chatCallFailed => '通話に失敗しました';

  @override
  String get chatCallAlreadyInCall => 'すでに通話中です';

  @override
  String get chatCallStillConnecting => '接続中です';

  @override
  String get chatCallWaitingAnswer => '応答を待っています';

  @override
  String get chatCallHasIncoming => '着信中の通話があります';

  @override
  String get chatMicPermissionRequired => 'マイクの権限が必要です';

  @override
  String get chatCallServerDisconnected => 'サーバーに接続できませんでした';

  @override
  String get chatCallNoAnswer => '相手が応答しませんでした';

  @override
  String get chatMicPermissionSettings => '設定 > 権限 > マイク で権限をオンにしてください';

  @override
  String get chatCallAgoraConfigMissing => 'Agoraの設定がありません';

  @override
  String get chatCallPeerNotConnected => '相手とつながりませんでした';

  @override
  String get chatCallEndedMessage => '通話が終了しました';

  @override
  String get chatCallAuthExpired => '通話の認証が期限切れになりました';

  @override
  String get chatCallDisconnected => '通話が切断されました';

  @override
  String get chatCallNetworkUnstable => 'ネットワークが不安定です';

  @override
  String get chatCallkitAppName => 'Eggplant';

  @override
  String get chatCallkitAccept => '応答';

  @override
  String get chatCallkitDecline => '拒否';

  @override
  String get chatMissedCall => '不在着信';

  @override
  String get chatIncomingCallChannel => '着信 (V2)';

  @override
  String get chatMissedCallChannel => '不在着信 (V2)';

  @override
  String get chatChannelChatName => 'チャットメッセージ';

  @override
  String get chatChannelChatDesc => '新しいチャットメッセージの通知';

  @override
  String get chatChannelKeywordName => 'キーワード通知';

  @override
  String get chatChannelKeywordDesc => '登録キーワードに一致する新着商品の通知';

  @override
  String get chatChannelPushName => 'Eggplant メッセージ';

  @override
  String get chatChannelPushDesc => '新しいチャットメッセージのプッシュ通知';

  @override
  String get chatChannelCallName => 'Eggplant 通話';

  @override
  String get chatChannelCallDesc => '音声通話の着信通知';

  @override
  String get chatKeywordAlertTitle => '🔔 新着商品のお知らせ';

  @override
  String get chatKeywordAlertMaskedBody => '登録キーワードに一致する新着商品があります';

  @override
  String get chatKeywordTicker => '新着商品';

  @override
  String get chatMaskedMessageTitle => '💬 新しいメッセージがあります';

  @override
  String get chatMaskedMessageBody => 'タップしてメッセージを表示';

  @override
  String get chatPermMicBody => '設定 > アプリ > Eggplant でマイクをオンにしてください。';

  @override
  String get chatPermCameraTitle => 'カメラの権限が必要です';

  @override
  String get chatPermCameraBody => '設定 > アプリ > Eggplant でカメラをオンにしてください。';

  @override
  String get chatPermGalleryTitle => '写真へのアクセス権限が必要です';

  @override
  String get chatPermGalleryBodyAndroid =>
      '設定 > アプリ > Eggplant で写真と動画の権限をオンにしてください。';

  @override
  String get chatPermGalleryBodyIos => '設定 > Eggplant で写真へのアクセスをオンにしてください。';

  @override
  String get chatPermNotifTitle => '🔔 通知がオフになっています';

  @override
  String get chatPermNotifBody =>
      '通知がオフだと、新着メッセージ・通話・キーワード商品のお知らせを見逃すことがあります。\n\n設定で通知をオンにしますか？\n\n※ Eggplantでは、ロック画面で通知の本文を隠すこともできます。「マイページ > 通知の本文を隠す」からオンにできます。';

  @override
  String get chatPermOpenSettings => '設定を開く';

  @override
  String get chatPermFsiTitle => '🔒 ロック画面の着信表示の権限';

  @override
  String get chatPermFsiBody =>
      'ロック画面に着信を表示するには\n「全画面通知」の権限が必要です。\n\n権限がオフの場合、ロック画面では\n着信音が鳴るだけで通話画面が表示されません。\n\n設定は一度だけで完了します。';

  @override
  String get chatPermAllow => '権限を許可';

  @override
  String get chatOfferStatusAccepted => '承諾済み';

  @override
  String get chatOfferStatusRejected => '拒否済み';

  @override
  String get chatOfferStatusCancelled => '取り消し済み';

  @override
  String get chatOfferStatusPending => '回答待ち';

  @override
  String get chatTimeJustNow => 'たった今';

  @override
  String chatTimeMinutesAgo(int n) {
    return '$n分前';
  }

  @override
  String chatTimeHoursAgo(int n) {
    return '$n時間前';
  }

  @override
  String chatTimeDaysAgo(int n) {
    return '$n日前';
  }

  @override
  String chatTimeWeeksAgo(int n) {
    return '$n週間前';
  }

  @override
  String chatTimeMonthsAgo(int n) {
    return '$nか月前';
  }

  @override
  String chatTimeYearsAgo(int n) {
    return '$n年前';
  }

  @override
  String get chatCurrencyUnitPhp => 'ペソ';

  @override
  String get chatAttachTooltip => '写真・約束';

  @override
  String get chatAttachGallery => 'アルバムから写真を送る';

  @override
  String get chatAttachCamera => 'カメラで撮って送る';

  @override
  String get chatAttachAppointment => '取引の約束を決める';

  @override
  String get chatPhotoSendFailed => '写真を送れませんでした。もう一度お試しください';

  @override
  String get chatPhotoUnavailable => '写真を開けません\n（24時間が過ぎたか、すでに削除されました）';

  @override
  String get chatAppointmentChange => '変更';

  @override
  String chatAppointmentSetBy(String name) {
    return '$nameさんが取引の約束を決めました';
  }

  @override
  String chatAppointmentCancelledBy(String name) {
    return '$nameさんが取引の約束をキャンセルしました';
  }

  @override
  String get chatAppointmentReminderNote => '約束の30分前にお知らせします';

  @override
  String get chatAppointmentTitle => '取引の約束を決める';

  @override
  String get chatAppointmentEditTitle => '取引の約束を変更';

  @override
  String get chatAppointmentPlace => '待ち合わせ場所（任意）';

  @override
  String get chatAppointmentCancel => '約束をキャンセル';

  @override
  String get chatAppointmentSend => '約束を送る';

  @override
  String get chatAppointmentPast => '今より後の時刻を選んでください';

  @override
  String get chatAppointmentReminderTitle => '30分後に取引の約束があります';

  @override
  String get chatAppointmentReminderBody => '約束の時間を守りましょう';

  @override
  String get chatAppointmentSetByMe => '取引の約束を決めました';

  @override
  String get chatAppointmentCancelledByMe => '取引の約束をキャンセルしました';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonConfirm => 'OK';

  @override
  String get commonDelete => '削除';

  @override
  String get commonSave => '保存';

  @override
  String get commonClose => '閉じる';

  @override
  String get commonRetry => '再試行';

  @override
  String get commonLater => 'あとで';

  @override
  String get commonFree => '無料';

  @override
  String get commonLoginRequired => 'ログインが必要です';

  @override
  String get commonNetworkError => '通信エラーが発生しました。しばらくしてから再度お試しください';

  @override
  String priceKrw(String amount) {
    return '$amountウォン';
  }

  @override
  String priceJpy(String amount) {
    return '¥$amount';
  }

  @override
  String pricePhp(String amount) {
    return '₱$amount';
  }

  @override
  String get homeSearchHint => '商品名で検索';

  @override
  String get homeSetRegion => '地域を設定';

  @override
  String get homeSearchClose => '検索を閉じる';

  @override
  String get homeSearch => '検索';

  @override
  String get homeQrScan => 'QRスキャン';

  @override
  String get homeRecentSearches => '最近の検索';

  @override
  String get homeClearAll => 'すべて削除';

  @override
  String get homeNoRecentSearches => '最近の検索履歴はありません';

  @override
  String get homeRangeAll => 'すべて';

  @override
  String get homeDistance => '距離';

  @override
  String get homeNoProducts => 'まだ商品がありません';

  @override
  String get homeCheckNetwork => 'ネットワークを確認して、もう一度お試しください';

  @override
  String get homeFirstProduct => '最初の商品を出品してみましょう!';

  @override
  String get homeRefresh => '更新';

  @override
  String homeMyRegionsTitle(int count, int max) {
    return 'マイエリア $count/$max';
  }

  @override
  String get homeMyRegionsHint => '見たい地域をタップするとすぐに切り替わります。';

  @override
  String get homeRemoveRegion => 'この地域を外す';

  @override
  String homeMaxRegions(int max) {
    return '最大$maxか所まで設定できます';
  }

  @override
  String get homeAddRegion => '地域を追加する';

  @override
  String get homeCategoryAll => 'すべて';

  @override
  String get homeCategoryDigital => 'デジタル機器';

  @override
  String get homeCategoryAppliance => '家電';

  @override
  String get homeCategoryFurniture => '家具・インテリア';

  @override
  String get homeCategoryClothing => 'ファッション';

  @override
  String get homeCategoryBeauty => 'コスメ・美容';

  @override
  String get homeCategoryBook => '本・チケット';

  @override
  String get homeCategorySports => 'スポーツ・レジャー';

  @override
  String get homeCategoryHobby => 'ホビー・ゲーム';

  @override
  String get homeCategoryKids => 'ベビー・キッズ';

  @override
  String get homeCategoryPet => 'ペット用品';

  @override
  String get homeCategoryFood => '食品';

  @override
  String get homeCategoryEtc => 'その他';

  @override
  String get homeLikesTitle => 'いいねした商品';

  @override
  String homeLikesTitleCount(int count) {
    return 'いいねした商品 $count';
  }

  @override
  String get homeLoadFailed => '読み込めませんでした';

  @override
  String get homeTryLater => 'しばらくしてからもう一度お試しください';

  @override
  String get homeNoLikes => 'いいねした商品はありません';

  @override
  String get homeNoLikesHint => '気になる商品のハートをタップしてみましょう';

  @override
  String get homeSignupBonus => '🎉 ようこそ!+500 QTAをプレゼントしました';

  @override
  String homeLoginBonusRemaining(int remaining) {
    return ' · 今日はあと$remaining回もらえます';
  }

  @override
  String get homeLoginBonusLimitReached => ' · 今日の上限に達しました!';

  @override
  String homeLoginBonus(int amount, String tail) {
    return '📅 ログインボーナス +$amount QTA$tail';
  }

  @override
  String get homeWrite => '出品';

  @override
  String get homeTabHome => 'ホーム';

  @override
  String get homeTabLikes => 'いいね';

  @override
  String get homeTabChat => 'チャット';

  @override
  String get homeTabMy => 'マイページ';

  @override
  String get homeLocationServiceOff => '位置情報サービスをオンにしてください(設定 > 位置情報)';

  @override
  String get homeLocationPermissionNeeded => '位置情報の許可が必要です。設定から許可してください。';

  @override
  String homeRegionVerifiedToast(String region) {
    return '$regionの地域認証が完了しました 🎉';
  }

  @override
  String get homeMyRegion => 'マイエリア';

  @override
  String get homeLocationFailed => '現在地を確認できませんでした。位置情報の許可とGPSを確認してください';

  @override
  String get homeRegionVerified => '地域認証済み';

  @override
  String get homeRegionVerifyNeeded => '地域認証が必要です';

  @override
  String homeRegionVerifiedDesc(String region) {
    return '$region · GPSで4km以内を確認済み';
  }

  @override
  String homeRegionVerifyDesc(String region) {
    return '$region · GPS認証で距離順の検索が使えます';
  }

  @override
  String get homeReverify => '再認証';

  @override
  String get homeVerify => '認証する';

  @override
  String get homeRegionSettingsTitle => '地域設定';

  @override
  String get homeRegionSearchHint => '市区町村名で検索(例:渋谷)';

  @override
  String get homeRegionVerifyDialogTitle => '地域認証をしますか?';

  @override
  String homeRegionVerifyDialogBody(String region) {
    return '$regionにお住まいかどうかをGPSで一度確認するだけで、距離順の検索が使えるようになります。\n\n正確な位置情報はサーバーに保存されません。';
  }

  @override
  String get homeVerifyNow => '今すぐ認証';

  @override
  String homeRegionSet(String region) {
    return '$regionに設定しました';
  }

  @override
  String get homeLoginToUse => 'ログインしてからご利用ください';

  @override
  String get homeMyQr => 'マイQRコード';

  @override
  String get homeShowQr => '相手にQRコードを見せてください';

  @override
  String get homeQrDesc => 'QRをスキャンするとすぐに匿名チャットが始まります 💨';

  @override
  String get homeQrAnonymous => '🔐 完全匿名・会話は保存されません';

  @override
  String get homeQrLinkCopied => 'QRリンクをコピーしました';

  @override
  String get homeQrCopyLink => 'QRリンクをコピー';

  @override
  String get homeQrNotEggplant => 'EggplantのQRコードではありません';

  @override
  String get homeQrInvalid => 'QRコードの形式が正しくありません';

  @override
  String get homeQrOwn => '自分のQRコードはスキャンできません';

  @override
  String get homeQrChatFailed => 'チャットルームを開けませんでした';

  @override
  String get homeQrScanGuide => 'EggplantのQRコードを枠内に合わせてください';

  @override
  String get homeQrScanDesc => 'スキャンするとすぐに匿名チャットが始まります';

  @override
  String get homeAnonymous => '匿名';

  @override
  String homePageNotFound(String error) {
    return 'ページが見つかりません: $error';
  }

  @override
  String get homeFilterAvailable => '取引可能のみ';

  @override
  String get homeFilterPrice => '価格';

  @override
  String get homeSortRecent => '新着順';

  @override
  String get homeSortPriceAsc => '価格の安い順';

  @override
  String get homeSortPriceDesc => '価格の高い順';

  @override
  String get homeSortTitle => '並び替え';

  @override
  String get homePriceTitle => '価格の範囲';

  @override
  String get homePriceMin => '最低';

  @override
  String get homePriceMax => '最高';

  @override
  String get homePriceReset => 'リセット';

  @override
  String get homePriceApply => '適用する';

  @override
  String get homePriceInvalid => '最低価格が最高価格より高くなっています';

  @override
  String get homeFilterNoResult => '条件に合う商品がありません';

  @override
  String get homeFilterClear => 'フィルターを解除';

  @override
  String get myTabTitle => 'マイページ';

  @override
  String myMannerTemp(String temp) {
    return 'マナー温度 $temp°C';
  }

  @override
  String get myRegionUnset => '地域未設定';

  @override
  String get myMenuSelling => '出品中の商品';

  @override
  String get myMenuLikes => 'いいねした商品';

  @override
  String get myMenuChat => 'チャット';

  @override
  String get myMenuProfile => 'プロフィール登録・ニックネーム変更';

  @override
  String get myMenuProfileSub => 'チャット・通話で表示されるニックネームを設定';

  @override
  String get myMenuRegion => '地域設定';

  @override
  String get myRegionNeeded => '未設定';

  @override
  String get myMenuQr => 'マイQRコード';

  @override
  String get myMenuQrSub => '相手に見せてチャットを始める';

  @override
  String get myMenuInvite => '友だち招待 (+200 QTA)';

  @override
  String get myMenuInviteSub => '友だちが登録時にあなたのニックネームを入力すると +200 QTA・上限なし';

  @override
  String get myMenuKeyword => 'キーワード通知';

  @override
  String get myMenuKeywordSub => '気になるキーワードを登録して新着商品の通知を受け取る';

  @override
  String get myMenuHidden => '非表示にした投稿';

  @override
  String get myMenuHiddenSub => '非表示にした投稿をもう一度見る';

  @override
  String get myMenuPrivacy => 'プライバシー保護';

  @override
  String get myMenuPrivacySub => 'チャット・通話は一切保存しません・流れたメッセージは完全に消えます';

  @override
  String get myPrivacyDialogTitle => 'プライバシー保護';

  @override
  String get myMenuAppInfo => 'アプリ情報';

  @override
  String get myAppLegalese => '© 2026 Eggplant Team\n匿名で安心なフリマ取引';

  @override
  String get myMenuLogout => 'ログアウト';

  @override
  String get myMenuDeleteAccount => 'アカウント削除(退会)';

  @override
  String get myMenuDeleteAccountSub => '削除すると復元できません・残りのQTA・招待ボーナスは即時回収されます';

  @override
  String get myStatSelling => '販売中';

  @override
  String get myStatLikes => 'いいね';

  @override
  String get myWalletCopied => 'ウォレットアドレスをコピーしました。ニックネーム・パスワードの再設定に貼り付けられます。';

  @override
  String get myQtaBalance => 'QTA残高';

  @override
  String get myHistory => '履歴';

  @override
  String get myHide => '隠す';

  @override
  String get myShowAll => 'すべて表示';

  @override
  String get myCopy => 'コピー';

  @override
  String get myWithdrawRequestBtn => 'ウォレットへ出金申請';

  @override
  String get myWithdrawNeedMin => '出金には5,000 QTA以上が必要です';

  @override
  String get myWalletCardNote =>
      'ニックネーム・パスワードを忘れたときは、このウォレットアドレスで復旧できます。\n5,000 QTAから5,000単位でご自身のウォレットへ出金できます。';

  @override
  String get myMaskOnSnack => '通知の本文を非表示にしました。ロック画面でも安心です 🔒';

  @override
  String get myMaskOffSnack => '通知の本文を表示します';

  @override
  String get myMaskTitle => '通知の本文を隠す';

  @override
  String get myMaskSub => 'ロック画面・プッシュのプレビューにメッセージ内容の代わりに「新しいメッセージがあります」と表示';

  @override
  String get myUnverified => '未認証';

  @override
  String get myCtaPhoneOpenTitle => 'ステップ2 電話番号認証で1,000 QTAを受け取る';

  @override
  String get myCtaPhoneSoonTitle => 'ステップ2 電話番号認証・まもなく開始';

  @override
  String get myCtaWalletTitle => 'ステップ1 ウォレット認証から始める';

  @override
  String get myCtaPhoneOpenDesc => '最後のステップです!認証してもチャット・通話は匿名のままです。';

  @override
  String get myCtaPhoneSoonDesc =>
      'ステップ1完了!電話番号認証が始まったら完了して1,000 QTAを受け取りましょう。';

  @override
  String get myCtaWalletDesc => 'ウォレット・電話番号認証をすべて完了すると1,000 QTAをプレゼント。';

  @override
  String get myBrowseCreditedTitle => '今日のマイニングボーナスを受け取りました!';

  @override
  String get myBrowseTitle => '今日の閲覧マイニング';

  @override
  String get myBrowseCreditedSub => '明日0時(日本時間)にリセットされます。';

  @override
  String myBrowseSub(int threshold) {
    return '商品を$threshold件見ると +10 QTA';
  }

  @override
  String get myBrowseStart => 'ホームタブで商品を見てみましょう 🛍️';

  @override
  String myBrowseRemaining(int count) {
    return 'あと$count件見ると +10 QTA!';
  }

  @override
  String get myBrowseSoon => 'まもなく付与されます…';

  @override
  String get myBrowseLink => 'マイニング履歴・出品すると価格の10%をマイニング';

  @override
  String get myUserNotFound => 'ユーザーが見つかりません';

  @override
  String get myServerSlow => 'サーバーの応答が遅れています。しばらくしてからもう一度お試しください 🕐';

  @override
  String get myLoadError => '読み込み中にエラーが発生しました';

  @override
  String get myMoreReviewsSlow => '評価の読み込みが遅れています。しばらくしてからもう一度お試しください 🕐';

  @override
  String get myThisUser => 'このユーザー';

  @override
  String get myBlockConfirmTitle => 'ブロックしますか?';

  @override
  String myBlockConfirmBody(String nick) {
    return '$nickさんをブロックすると、お互いの投稿とチャットがすべて表示されなくなります。いつでも解除できます。';
  }

  @override
  String get myBlock => 'ブロック';

  @override
  String myBlockedSnack(String nick) {
    return '$nickさんをブロックしました';
  }

  @override
  String get myUnblockConfirmTitle => 'ブロックを解除しますか?';

  @override
  String myUnblockConfirmBody(String nick) {
    return '$nickさんが再び表示されるようになります。';
  }

  @override
  String get myUnblockShort => '解除';

  @override
  String get myUnblockedSnack => 'ブロックを解除しました';

  @override
  String get myReportSpam => 'スパム・宣伝';

  @override
  String get myReportFraud => '詐欺の疑い';

  @override
  String get myReportAbuse => '暴言・誹謗中傷';

  @override
  String get myReportInappropriate => '不適切な内容';

  @override
  String get myReportFake => '虚偽の出品';

  @override
  String get myReportOther => 'その他';

  @override
  String get myReportTitle => '通報の理由を選んでください';

  @override
  String get myReportDesc => '複数の人が同じ理由で通報すると運営チームが確認します。';

  @override
  String get myReportDetailHint => '補足説明(任意)';

  @override
  String get myReportDone => '通報を受け付けました';

  @override
  String get myReportSubmit => '通報する';

  @override
  String get myProfileMine => 'マイプロフィール';

  @override
  String get myProfileSeller => '出品者情報';

  @override
  String get myUnblockMenu => 'ブロック解除';

  @override
  String get myBlockMenu => 'ブロックする';

  @override
  String get myTopPraise => 'よくもらったマナー評価';

  @override
  String get myReceivedReviews => 'もらった取引評価';

  @override
  String get myNoReviews => 'まだ評価はありません';

  @override
  String get myAnonNickname => '匿名ユーザー';

  @override
  String get myMannerLabel => 'マナー温度';

  @override
  String get myReviewsLabel => '評価';

  @override
  String get myRatingGood => '良かった';

  @override
  String get myRatingSoso => '普通';

  @override
  String get myRatingBad => '残念だった';

  @override
  String myAgoMinutes(int n) {
    return '$n分前';
  }

  @override
  String myAgoHours(int n) {
    return '$n時間前';
  }

  @override
  String myAgoDays(int n) {
    return '$n日前';
  }

  @override
  String myAgoWeeks(int n) {
    return '$n週間前';
  }

  @override
  String myAgoMonths(int n) {
    return '$nか月前';
  }

  @override
  String get myPhotoLoadFail => '写真を読み込めませんでした。権限を確認してもう一度お試しください';

  @override
  String get myNicknameEmpty => 'ニックネームを入力してください';

  @override
  String get myNicknameTooShort => 'ニックネームは2文字以上で入力してください';

  @override
  String get myNicknameTooLong => 'ニックネームは12文字以内で入力してください';

  @override
  String get myProfileSaved => 'プロフィールを保存しました。チャット・通話にすぐ反映されます ✨';

  @override
  String get myProfilePhotoSaved => 'プロフィール写真を保存しました ✨';

  @override
  String get myProfileEditTitle => 'プロフィール登録';

  @override
  String get myPhotoChange => '写真を変更';

  @override
  String get myPhotoAdd => '写真を登録';

  @override
  String get myPhotoReset => 'デフォルト画像に戻す';

  @override
  String get myNicknameIntro => 'チャット・通話で表示されるニックネームを設定してください';

  @override
  String get myNicknameLabel => 'ニックネーム';

  @override
  String get myNicknameHint => '2〜12文字(日本語・英数字)';

  @override
  String get myNicknameGuideTitle => 'ニックネームについて';

  @override
  String get myNicknameGuideBody =>
      '• 変更するとすぐにチャット・通話に反映されます\n• 他のユーザーと同じニックネームは使えません\n• 電話番号認証の有無にかかわらず、ニックネームのみ使用します';

  @override
  String get mySaveButton => '保存する';

  @override
  String get myWdNeedWalletTitle => 'ステップ1 ウォレット認証が必要です';

  @override
  String get myWdNeedWalletBody =>
      '出金したQTAは認証済みのウォレットに送金されます。\n運営のウォレットから届いた数量を入力して、ウォレットの所有者であることを確認してください。';

  @override
  String get myWdNeedPhoneTitle => 'ステップ2 電話番号認証が必要です';

  @override
  String get myWdPreparingTitle => '出金は準備中です';

  @override
  String get myWdNeedPhoneBody =>
      '1人1アカウントを守るため、出金前に電話番号認証が必要です。\n完了すると1,000 QTAもプレゼントします。';

  @override
  String get myWdPreparingBody =>
      '出金には電話番号認証が必要ですが、現在準備中です。\n開始したらアプリのアップデートでお知らせします。それまでQTAはそのまま貯まります。';

  @override
  String get myWdNoWallet => 'ウォレットアドレスが登録されていません';

  @override
  String myWdInsufficientMin(String min) {
    return '残高が不足しています。$min QTAから申請できます。';
  }

  @override
  String get myWdConfirmTitle => '出金申請';

  @override
  String myWdConfirmBody(String amount, String wallet) {
    return '$amount QTAを\n$wallet\nへ出金申請しますか?\n\n申請するとすぐに残高から差し引かれ、運営が1〜3日以内に送金します。';
  }

  @override
  String get myWdApply => '申請';

  @override
  String get myWdRequested => '出金を申請しました — 処理されたらお知らせします';

  @override
  String get myWdCancelTitle => '申請の取り消し';

  @override
  String myWdCancelBody(String amount) {
    return '$amount QTAの出金申請を取り消しますか?\n取り消すとすぐに残高へ返金されます。';
  }

  @override
  String get myWdNo => 'いいえ';

  @override
  String get myWdCancelDo => '取り消す';

  @override
  String get myWdCancelled => '取り消し・返金が完了しました';

  @override
  String get myDateTimeFormat => 'M月d日 HH:mm';

  @override
  String get myWdTitle => 'QTA出金';

  @override
  String get myWdAvailable => '出金可能残高';

  @override
  String get myWdRuleShort => '5,000 QTAから5,000単位で申請';

  @override
  String myWdPendingStatus(String amount, String status) {
    return '$amount QTAの出金は「$status」です';
  }

  @override
  String get myWdRequestBtn => '出金を申請する';

  @override
  String get myWdInsufficient => '残高が不足しています';

  @override
  String get myWdHistory => '申請履歴';

  @override
  String get myWdHistoryEmpty => 'まだ出金申請の履歴はありません';

  @override
  String get myWdNotice =>
      '出金は登録済みのQuantariumウォレットアドレスにのみ送金されます。運営が1〜3日以内に処理します。処理開始後は取り消しできません。';

  @override
  String get myWdTxCopied => 'トランザクションハッシュをコピーしました';

  @override
  String myWdReason(String reason) {
    return '理由: $reason';
  }

  @override
  String get myWdAmountTitle => '出金数量の入力';

  @override
  String myWdAmountRule(String min, String unit) {
    return '$min QTAから$unit QTA単位で申請できます';
  }

  @override
  String myWdMinBtn(String amount) {
    return '最小 $amount';
  }

  @override
  String myWdMaxBtn(String amount) {
    return '全額 $amount';
  }

  @override
  String get myWdToWallet => '受取ウォレット';

  @override
  String myWdSubmitAmount(String amount) {
    return '$amount QTAを申請する';
  }

  @override
  String get myLedgerTitle => 'QTA履歴';

  @override
  String get myLedgerWithdraw => '出金';

  @override
  String get myLedgerBalance => '現在の残高';

  @override
  String get myLedgerRecent => '最近の履歴';

  @override
  String get myLedgerEmpty => 'まだ履歴はありません。ログインボーナスや取引でQTAを貯めましょう!';

  @override
  String get myRuleTitle => 'QTA獲得ルール';

  @override
  String get myRuleVerify => 'ウォレット・電話番号認証の完了で +1,000 QTA(1回)';

  @override
  String myRuleListing(int rate) {
    return '出品すると価格の10%をQTAでマイニング(1 QTA = $rate円)・削除すると差し引き';
  }

  @override
  String get myRuleLogin => 'ログインごとに +10 QTA・1日3回まで';

  @override
  String get myRuleTrade => '取引完了で出品者・購入者それぞれ +10 QTA';

  @override
  String get myRuleWithdraw => '5,000 QTAから5,000単位でウォレットへ出金可能';

  @override
  String get myMiningLoadFail => 'マイニング履歴を読み込めませんでした。下に引っ張って再度お試しください';

  @override
  String get myMiningTitle => 'マイニング履歴';

  @override
  String get myMiningTotalLabel => 'これまでにマイニングしたQTA';

  @override
  String myMiningTotalSub(String listing, String money) {
    return '出品マイニング $listing QTA・約$money';
  }

  @override
  String myMiningRule(int percent, int rate, String examplePrice,
      String exampleQta, String maxPerListing, String maxPerDay) {
    return '⛏️ 出品すると価格の$percent%をQTAでマイニングします(1 QTA = $rate円)\n   例)$examplePriceの商品 → +$exampleQta QTA\n• 1商品あたり最大$maxPerListing QTA・1日最大$maxPerDay QTA\n• 値下げすると差額分、商品を削除すると受け取った分が差し引かれます\n• 売り切れになった商品は差し引かれません(削除すると差し引き)';
  }

  @override
  String get myMiningRecords => 'マイニング記録';

  @override
  String get myMiningEmpty => 'まだマイニング記録はありません。出品してQTAをマイニングしましょう!';

  @override
  String get myRefLoadFail => '招待履歴を読み込めませんでした。';

  @override
  String get myRefNetworkError => 'ネットワークエラー:しばらくしてからもう一度お試しください。';

  @override
  String get myRefTitle => '友だち招待';

  @override
  String get myRefHeadline => '友だちが登録時に\nあなたのニックネームを入力すると +200 QTA';

  @override
  String get myRefCopyNick => 'ニックネームをコピー';

  @override
  String get myRefNickCopied => 'ニックネームをコピーしました';

  @override
  String get myRefOncePerPerson => '1人につき1回のみですが、招待できる友だちの数に上限はありません。';

  @override
  String get myRefStatValid => '有効な招待';

  @override
  String get myRefStatEarned => '累計獲得';

  @override
  String get myRefStatClawed => '回収(退会)';

  @override
  String get myRefRuleTitle => '友だち招待ボーナスのルール';

  @override
  String get myRefRuleBody =>
      '• 友だち1人につき +200 QTA・上限なし\n• 友だちが会員登録の最後の欄にあなたのニックネームを入力\n• 友だちが退会すると、その200 QTAはすぐに回収されます\n• 自分自身を招待者にすることはできません';

  @override
  String get myRefListTitle => '招待した友だち';

  @override
  String get myRefEmpty => 'まだ招待した友だちはいません';

  @override
  String get myRefDeletedFriend => '(退会した友だち)';

  @override
  String get myRefUnknown => '(不明)';

  @override
  String get myRefClawedBadge => '−200 QTA 回収';

  @override
  String get myReasonSignup => '登録ボーナス';

  @override
  String get myReasonVerifyBonus => '認証完了ボーナス';

  @override
  String get myReasonLoginDaily => 'ログインボーナス';

  @override
  String get myReasonTradeSeller => '販売完了報酬';

  @override
  String get myReasonTradeBuyer => '購入完了報酬';

  @override
  String get myReasonWithdrawal => '出金申請';

  @override
  String get myReasonWithdrawalRefund => '出金取り消し・返金';

  @override
  String get myReasonListingReward => '出品マイニング';

  @override
  String get myReasonListingAdjust => '値下げによる差し引き';

  @override
  String get myReasonListingClawback => '商品削除による差し引き';

  @override
  String get myReasonMiningListing => '出品7日継続マイニング';

  @override
  String get myReasonMiningBrowse => '閲覧マイニング';

  @override
  String get myWdStatusRequested => '受付中';

  @override
  String get myWdStatusProcessing => '送金中';

  @override
  String get myWdStatusCompleted => '完了';

  @override
  String get myWdStatusRejected => '却下・返金';

  @override
  String get myQtaLoadFail => 'QTA残高を読み込めませんでした';

  @override
  String get myWdLoadFail => '出金履歴を読み込めませんでした';

  @override
  String myWdErrMin(String min) {
    return '$min QTAから申請できます';
  }

  @override
  String myWdErrUnit(String unit) {
    return '$unit QTA単位でのみ申請できます';
  }

  @override
  String get myWdErrBalance => 'QTA残高が不足しています';

  @override
  String get myWdErrPending => '処理中の申請があります。処理が終わってから再度お試しください。';

  @override
  String get myWdErrRequestFail => '出金申請に失敗しました';

  @override
  String get myWdUserCancelled => 'ユーザーによる取り消し';

  @override
  String get myWdErrCancelFail => '取り消しに失敗しました';

  @override
  String get myVerifyLabelNone => '未認証';

  @override
  String get myVerifyLabelIdentity => '電話番号認証済み';

  @override
  String get myVerifyLabelBank => '出金認証済み';

  @override
  String get myMenuLanguage => '言語';

  @override
  String get myRuleVerifyRequired =>
      '採掘した QTA はすぐに貯まります · 取引完了と出金は電話番号認証の後にできます';

  @override
  String get myPrivacyNoCollect => '収集しない情報';

  @override
  String get myPrivacyItemName => 'メールアドレス・本名';

  @override
  String get myPrivacyItemNameSub => 'ニックネームとパスワードだけ';

  @override
  String get myPrivacyItemGps => '正確な位置情報';

  @override
  String get myPrivacyItemGpsSub => '地域認証のGPSはすぐ破棄';

  @override
  String get myPrivacyItemChat => 'チャットの内容';

  @override
  String get myPrivacyItemChatSub => 'サーバーに保存しません';

  @override
  String get myPrivacyItemCall => '通話の内容';

  @override
  String get myPrivacyItemCallSub => '端末同士で直接(サーバー非経由)';

  @override
  String get myPrivacyPhoneTitle => '電話番号';

  @override
  String get myPrivacyPhoneSub => '認証にのみ使用・暗号化して保管・退会で即削除';

  @override
  String get myPrivacyVolatileTitle => 'チャットは残りません';

  @override
  String get myPrivacyVolatileSub => 'アプリを閉じるか端末を変えると消えます';

  @override
  String get productCategoryAll => 'すべて';

  @override
  String get productCategoryDigital => 'デジタル機器';

  @override
  String get productCategoryAppliance => '家電';

  @override
  String get productCategoryFurniture => '家具・インテリア';

  @override
  String get productCategoryClothing => 'ファッション';

  @override
  String get productCategoryBeauty => 'コスメ・美容';

  @override
  String get productCategoryBook => '本・チケット';

  @override
  String get productCategorySports => 'スポーツ・レジャー';

  @override
  String get productCategoryHobby => 'ホビー・ゲーム';

  @override
  String get productCategoryKids => 'ベビー・キッズ';

  @override
  String get productCategoryPet => 'ペット用品';

  @override
  String get productCategoryFood => '食品';

  @override
  String get productCategoryEtc => 'その他';

  @override
  String get productAnonymousSeller => '匿名ユーザー';

  @override
  String get productTimeJustNow => 'たった今';

  @override
  String productTimeMinutesAgo(int n) {
    return '$n分前';
  }

  @override
  String productTimeHoursAgo(int n) {
    return '$n時間前';
  }

  @override
  String productTimeDaysAgo(int n) {
    return '$n日前';
  }

  @override
  String productTimeMonthsAgo(int n) {
    return '$nか月前';
  }

  @override
  String productTimeYearsAgo(int n) {
    return '$n年前';
  }

  @override
  String get productStatusSale => '販売中';

  @override
  String get productStatusReserved => '取引中';

  @override
  String get productStatusSold => '売り切れ';

  @override
  String get productReviewGood => '良かった';

  @override
  String get productReviewBad => '残念だった';

  @override
  String get productReviewSoso => '普通';

  @override
  String get productStatusSoldOut => '売り切れ';

  @override
  String get productDetailLoadFailed => '商品情報を読み込めませんでした。';

  @override
  String get productDetailTimeout => 'サーバーの応答が遅れています。しばらくしてからもう一度お試しください。';

  @override
  String get productQtaConfirmUnavailableTitle => '電話番号認証は準備中です';

  @override
  String get productQtaConfirmUnavailableBody =>
      '取引完了は電話番号認証の後にできます。\n電話番号認証が始まりましたら、すぐに完了できるようご案内します。';

  @override
  String get productConfirmVerifyTitle => '取引完了の前に電話番号認証が必要です';

  @override
  String get productConfirmVerifyBody =>
      'すべての取引は電話番号認証を完了すると最終的に完了します(1人1アカウントの保証)。\nこれまでに採掘した QTA はそのまま貯まっています。認証してもチャット・通話は匿名のままです。';

  @override
  String get productConfirmDialogTitle => '取引を確認しますか?';

  @override
  String productConfirmDialogBodyQta(String qta) {
    return '確認すると$qtaが出品者に支払われます。\n商品を受け取ってから確認してください。';
  }

  @override
  String get productConfirmDialogBody =>
      '商品を受け取ってから確認してください。\n確認すると取引が完了し、評価を書くことができます。';

  @override
  String get productConfirmDeal => '取引を確認';

  @override
  String get productConfirmDone => '取引を確認しました 🍆';

  @override
  String get productBuyerAssignedTitle => '出品者があなたを購入者に指定しました';

  @override
  String productBuyerAssignedBodyQta(String qta) {
    return '取引を確認すると$qtaが支払われます。';
  }

  @override
  String get productBuyerAssignedBody => '商品を受け取ったら取引を確認してください。';

  @override
  String get productConfirmDealButton => '取引を確認する';

  @override
  String get productSoldVerifyTitle => '取引完了の前に電話番号認証が必要です';

  @override
  String get productSoldVerifyBody =>
      'すべての取引は電話番号認証を完了すると取引完了にできます(1人1アカウントの保証)。\nこれまでに採掘した QTA はそのまま貯まっています。認証してもチャット・通話は匿名のままです。';

  @override
  String get productStatusChangedSold =>
      '取引完了に変更しました。購入者が取引を確認すると、支払い・ボーナスが付与されます';

  @override
  String productStatusChanged(String status) {
    return 'ステータスを「$status」に変更しました';
  }

  @override
  String get productBuyer => '購入者';

  @override
  String productReviewQuestion(String nickname) {
    return '$nicknameさんとの取引はいかがでしたか?';
  }

  @override
  String get productReviewHint => '取引の評価コメントを書いてください(任意)';

  @override
  String get productReviewThanks => '評価ありがとうございます 🙏';

  @override
  String get productReviewSubmit => '評価を送信';

  @override
  String get productChatOpenFailed => 'チャットルームを開けません';

  @override
  String get productChatStartFailed => 'チャットを開始できませんでした。しばらくしてからもう一度お試しください';

  @override
  String get productEscrowNavigating => 'あんしん決済画面に移動します';

  @override
  String get productChangeToSale => '販売中に変更';

  @override
  String get productChangeToReserved => '取引中に変更';

  @override
  String get productChangeToSold => '売り切れに変更';

  @override
  String get productEdit => '編集';

  @override
  String get productDeleteTitle => '商品を削除しますか?';

  @override
  String get productDeleteBody =>
      '• 商品と写真・動画が完全に削除されます\n• この商品で獲得した出品マイニングQTAが差し引かれます\n• 元に戻すことはできません';

  @override
  String productDeletedWithClawback(int qta) {
    return '商品を削除しました · 出品マイニング -$qta QTA';
  }

  @override
  String get productDeleted => '商品を削除しました';

  @override
  String get productHide => '非表示にする';

  @override
  String get productReport => '通報';

  @override
  String get productReportReceived => '通報を受け付けました';

  @override
  String get productDetailTitle => '商品詳細';

  @override
  String get productOwnerMenuTooltip => 'ステータス変更 / 削除';

  @override
  String get productMore => 'その他';

  @override
  String get productDetailEmpty => '商品情報がありません。';

  @override
  String get productNoTitle => 'タイトルなし';

  @override
  String get productNoSellerInfo => '出品者情報なし';

  @override
  String get productDescriptionTitle => '商品の説明';

  @override
  String get productNoDescription => '説明なし';

  @override
  String get productManage => '管理';

  @override
  String get productChatButton => 'チャットする';

  @override
  String productMannerTemp(String temp) {
    return 'マナー温度 $temp';
  }

  @override
  String get productPickBuyerTitle => '取引した購入者を選択してください';

  @override
  String get productPickBuyerHint => '選択した購入者がアプリで「取引を確認」を押すと取引が完了します。';

  @override
  String get productPickBuyerSearchHint => '購入者のニックネームを検索';

  @override
  String get productPickBuyerChatPartners => 'この商品でチャットした人';

  @override
  String get productPickBuyerNoResults => '検索結果がありません';

  @override
  String get productPickBuyerEmpty => '購入者のニックネームを検索してください';

  @override
  String get productVideoLoadFailed => '動画を読み込めません';

  @override
  String productMaxImages(int max) {
    return '写真は最大$max枚まで登録できます';
  }

  @override
  String get productAddPhoto => '写真を追加';

  @override
  String get productPhotoPickFailed => '写真を読み込めませんでした。権限を確認してもう一度お試しください';

  @override
  String get productAddVideo => '動画を追加';

  @override
  String get productVideoPickFailed => '動画を読み込めませんでした。権限を確認してもう一度お試しください';

  @override
  String get productVideoTooLarge => '動画のサイズは50MB以下にしてください';

  @override
  String get productYoutubeAddTitle => 'YouTubeリンクを追加';

  @override
  String get productYoutubeAddBody =>
      'YouTube動画のURLを貼り付けてください。\n例: https://youtu.be/xxxxxxxxxxx';

  @override
  String get productYoutubeInvalid => 'YouTubeリンクの形式が正しくありません';

  @override
  String get productSetRegionFirst => '先に地域を設定してください';

  @override
  String get productUploadTimeout =>
      'アップロードに時間がかかりすぎています。写真・動画のサイズを小さくするか、Wi-Fi環境でもう一度お試しください。';

  @override
  String get productCreateUnexpectedError =>
      '出品中に問題が発生しました。しばらくしてからもう一度お試しください';

  @override
  String productCreatedWithReward(int qta) {
    return '出品しました 🍆  出品マイニング +$qta QTA';
  }

  @override
  String get productCreated => '出品しました 🍆';

  @override
  String get productCreateTitle => '出品する';

  @override
  String get productDone => '完了';

  @override
  String get productFieldTitle => '商品名';

  @override
  String get productFieldTitleHint => '商品名を入力してください';

  @override
  String get productFieldTitleRequired => '商品名を入力してください';

  @override
  String get productFieldCategory => 'カテゴリー';

  @override
  String get productFieldPrice => '価格';

  @override
  String get productFieldPriceHintKrw => '0(無料で譲る場合は0ウォン)';

  @override
  String get productFieldPriceHintJpy => '0(無料で譲る場合は0円)';

  @override
  String get productFieldPriceRequired => '価格を入力してください';

  @override
  String get productFieldQtaPrice => 'QTA決済(任意)';

  @override
  String get productFieldQtaPriceHint => '0 = 使用しない / 購入者の取引確認時に引き落とし';

  @override
  String get productFieldQtaPriceHelper =>
      '例) 5,000 → 購入者が取引を確認すると、購入者の残高から5,000 QTAが送金されます';

  @override
  String get productFieldDescription => '商品の説明';

  @override
  String get productFieldDescriptionHint =>
      '出品前にご確認ください。\n- 出品禁止物ではないか\n- カテゴリーは適切か\n\n商品の状態や使用期間などを詳しく書いてください。';

  @override
  String get productFieldDescriptionMin => '10文字以上入力してください';

  @override
  String get productProhibitedGuide => '出品禁止物について';

  @override
  String get productPhotos => '写真';

  @override
  String get productVideo => '動画';

  @override
  String get productOptional => '(任意)';

  @override
  String get productRemove => '削除';

  @override
  String get productPickCamera => 'カメラで撮影';

  @override
  String get productPickGallery => 'ギャラリーから選択';

  @override
  String get productPickYoutube => 'YouTubeリンクを貼り付け';

  @override
  String get productCoverPhoto => 'メイン';

  @override
  String get productYoutubeVideo => 'YouTube動画';

  @override
  String get productNotFound => '商品が見つかりません';

  @override
  String get productNoChanges => '変更された内容がありません';

  @override
  String get productUpdated => '商品を更新しました ✨';

  @override
  String get productEditTitle => '商品の編集';

  @override
  String get productFieldTitleTooLong => '商品名が長すぎます';

  @override
  String get productFieldRegion => '地域';

  @override
  String get productSetRegion => '地域を設定してください';

  @override
  String get productChange => '変更';

  @override
  String get productFieldDescriptionEditHint => '商品の状態や使用期間などを詳しく書いてください。';

  @override
  String get productUploadedVideoLocked =>
      'アップロードした動画は編集できません。\n変更する場合は、商品を削除してから出品し直してください。';

  @override
  String get productYoutubeLinkOptional => 'YouTubeリンク(任意)';

  @override
  String productEditingBanner(String title) {
    return '編集中: $title';
  }

  @override
  String productWaitHoursMinutes(int h, int m) {
    return '$h時間$m分';
  }

  @override
  String productWaitMinutes(int m) {
    return '$m分';
  }

  @override
  String productBumpWait(String wait) {
    return 'あと$waitで再びUPできます';
  }

  @override
  String get productBumped => '🍆 UPしました!フィードの一番上に表示されます';

  @override
  String get productDeleteDialogTitle => '商品の削除';

  @override
  String productDeleteConfirmNamed(String title) {
    return '「$title」を本当に削除しますか?';
  }

  @override
  String get productStatusChangedGeneric => 'ステータスを変更しました';

  @override
  String get productMySelling => '出品した商品';

  @override
  String productMySellingCount(int count) {
    return '出品した商品 $count';
  }

  @override
  String get productNewPost => '出品する';

  @override
  String get productMySellingEmpty => '出品した商品はありません';

  @override
  String get productMySellingEmptyHint => '右下の「出品する」から出品してみましょう';

  @override
  String get productMyMenuTooltip => 'UP / ステータス変更 / 削除';

  @override
  String get productBump => 'UP(上に表示)';

  @override
  String get productBumpWaiting => 'UP(待機中)';

  @override
  String get productChangeStatus => 'ステータス変更';

  @override
  String get productBanMedicine => '医薬品・医療機器';

  @override
  String get productBanMedicineEx => '医薬品・市販薬、ダイエット薬、ED治療薬、コンタクトレンズ、補聴器、注射器';

  @override
  String get productBanDrugs => '麻薬・向精神薬';

  @override
  String get productBanDrugsEx => '大麻、覚醒剤、睡眠薬(向精神薬)、危険ドラッグ、マジックマッシュルームなど';

  @override
  String get productBanAlcohol => '酒類';

  @override
  String get productBanAlcoholEx => 'ビール・日本酒・焼酎・ワイン・ウイスキー(空き瓶・グラスは出品可)';

  @override
  String get productBanTobacco => 'たばこ・電子たばこ';

  @override
  String get productBanTobaccoEx => 'たばこ、電子たばこ本体・リキッド、ニコチン製品';

  @override
  String get productBanWeapons => '銃砲・刀剣・火薬類・武器';

  @override
  String get productBanWeaponsEx => '実銃、実弾、クロスボウ、スタンガン、日本刀・刀剣、ダガーナイフ';

  @override
  String get productBanAdult => 'アダルトグッズ・わいせつ物';

  @override
  String get productBanAdultEx => 'アダルトグッズ、わいせつ物、使用済み下着、援助交際・パパ活';

  @override
  String get productBanAccounts => 'アカウント・個人情報・名義';

  @override
  String get productBanAccountsEx => 'ゲーム/SNSアカウント、銀行口座・通帳、SIMカード・他人名義の携帯、身分証';

  @override
  String get productBanCashing => '現金化・貸付・暗号資産';

  @override
  String get productBanCashingEx => 'クレジットカード現金化、個人融資・闇金、ビットコインなどの暗号資産の売買';

  @override
  String get productBanAnimals => 'ペット・野生動物';

  @override
  String get productBanAnimalsEx => 'ペット・生体の譲渡や販売(里親募集を含む)、絶滅危惧種、象牙';

  @override
  String get productBanCounterfeit => '偽ブランド品';

  @override
  String get productBanCounterfeitEx => '偽物、コピー品、スーパーコピー、N級品';

  @override
  String get productBanStolen => '盗品・違法改造・海賊版';

  @override
  String get productBanStolenEx => '盗品、違法改造品、海賊版、マジコン';

  @override
  String get productBanBodily => '献血・処方箋・人体由来物';

  @override
  String get productBanBodilyEx => '処方箋、臓器・卵子・精子、母乳';

  @override
  String get productBanMilitary => '軍用品・警察制服';

  @override
  String get productBanMilitaryEx => '警察制服・警察手帳、自衛隊官品、防弾チョッキ、手錠';

  @override
  String get productBanSpycam => '盗撮・盗聴機器';

  @override
  String get productBanSpycamEx => '隠しカメラ、偽装カメラ、盗聴器';

  @override
  String get productBanHacking => 'ハッキング・不正プログラム';

  @override
  String get productBanHackingEx => 'ハッキングツール、チートツール、不正なマクロ';

  @override
  String get productBanScalping => 'チケット転売・代行サービス';

  @override
  String get productBanScalpingEx => 'チケットの高額転売、チケット取り代行、代理受験';

  @override
  String get productBanWasteBags => '粗大ごみ処理券';

  @override
  String get productBanWasteBagsEx => '粗大ごみ処理券、ごみ処理シール';

  @override
  String get productBanFireworks => '花火・爆竹';

  @override
  String get productBanFireworksEx => '花火、爆竹、手製の爆発物';

  @override
  String get productBanIntro =>
      '法律で取引が禁止されている物や安全を損なうおそれのある物は、Eggplantでは出品できません。以下の品目を含む投稿は出品できず、利用規約に違反した場合はご利用が制限されることがあります。';

  @override
  String get productBanInfoTitle => '投稿に記載できない情報';

  @override
  String get productBanInfoBody =>
      '• 電話番号、口座番号、メールアドレス\n• LINE ID、オープンチャット・Telegramのリンクなどの外部メッセンジャー\n• 暴言・不適切な表現・差別的な表現\n\n取引のやり取りはEggplantのチャットをご利用ください。外部メッセンジャーへの誘導や先払いの要求は詐欺の危険が高いです。';

  @override
  String get productPolicyRejectedTitle => '出品できない投稿です';

  @override
  String get productViewProhibited => '出品禁止物を見る';

  @override
  String get productHiddenTimeout => 'サーバーの応答が遅れています。しばらくしてからもう一度お試しください 🕐';

  @override
  String get productHiddenLoadFailed => '非表示にした投稿を読み込めませんでした';

  @override
  String productUnhidden(String title) {
    return '「$title」を再表示しました';
  }

  @override
  String get productUnhideFailed => '再表示に失敗しました';

  @override
  String get productHiddenTitle => '非表示にした投稿';

  @override
  String get productUnhide => '再表示';

  @override
  String get productHiddenEmpty => '非表示にした投稿はありません';

  @override
  String get productHiddenEmptyHint => '投稿の右上の ⋯ メニューから非表示にできます';

  @override
  String get productKeywordDeleteTitle => 'キーワードの削除';

  @override
  String productKeywordDeleteBody(String keyword) {
    return '「$keyword」の通知をオフにしますか?';
  }

  @override
  String get productKeywordAlertsTitle => 'キーワード通知';

  @override
  String productKeywordAlertsIntro(int max) {
    return '気になるキーワードを登録すると、地域に新しい商品が出品されたときにお知らせします。(最大$max件)';
  }

  @override
  String get productKeywordFull => 'キーワードの登録枠がいっぱいです';

  @override
  String get productKeywordHint => '例: ニンテンドー、自転車、キャンプ';

  @override
  String get productKeywordAdd => '登録';

  @override
  String get productKeywordEmpty => '登録したキーワードはありません';

  @override
  String get productKeywordEmptyHint => '上から気になるキーワードを追加してみましょう';

  @override
  String get productKeywordTooShort => 'キーワードは2文字以上で入力してください';

  @override
  String get productKeywordTooLong => 'キーワードは30文字以内で入力してください';

  @override
  String productKeywordMax(int max) {
    return 'キーワードは最大$max件まで登録できます';
  }

  @override
  String get productKeywordAddFailed => '通知の登録に失敗しました。しばらくしてからもう一度お試しください';

  @override
  String get productLoadFailed => '商品を読み込めませんでした';

  @override
  String get productCreateFailed => '登録に失敗しました';

  @override
  String get productCreateFailedRetry => '出品に失敗しました。しばらくしてからもう一度お試しください';

  @override
  String get productLikesLoadFailed => 'いいねした商品を読み込めません';

  @override
  String get productNothingToUpdate => '変更する内容がありません';

  @override
  String get productUpdateFailed => '更新に失敗しました';

  @override
  String get productBumpFailed => 'UPに失敗しました';

  @override
  String get productChangeFailed => '変更に失敗しました';

  @override
  String get productDeleteFailed => '削除に失敗しました';

  @override
  String get productConfirmFailed => '取引の確認に失敗しました';

  @override
  String get productReviewFailed => '評価の送信に失敗しました';

  @override
  String get productNetworkSlow => '応答が遅れています。ネットワーク状態を確認してもう一度お試しください';

  @override
  String get productNetworkUnreachable => 'サーバーに接続できません。ネットワークを確認してください';

  @override
  String get productBlockFailed => 'ブロックに失敗しました';

  @override
  String get productUnblockFailed => 'ブロック解除に失敗しました';

  @override
  String get productReportFailed => '通報の送信に失敗しました';

  @override
  String get productFieldPriceHintPhp => '0(無料で譲る場合は0ペソ)';

  @override
  String get productShare => '共有';

  @override
  String get productLinkCopied => '商品リンクをコピーしました';

  @override
  String productSellerOthers(String name) {
    return '$nameさんの出品商品';
  }

  @override
  String get productSimilar => 'こんな商品はいかがですか？';

  @override
  String get productSeeAll => 'すべて見る';

  @override
  String get productMeetPlaceTitle => '取引希望場所';

  @override
  String get productFieldMeetPlace => '取引希望場所（任意）';

  @override
  String get productFieldMeetPlaceHint => '例）渋谷駅ハチ公前';

  @override
  String get productDraftTitle => '書きかけの投稿があります';

  @override
  String get productDraftBody => '続きから書きますか？';

  @override
  String get productDraftDiscard => '新しく書く';

  @override
  String get productDraftResume => '続きを書く';

  @override
  String get regionPrefectureSearchHint => '都道府県・市区町村名で検索(例:渋谷)';

  @override
  String regionCitySearchHint(String prefecture) {
    return '$prefectureの市区町村を検索';
  }

  @override
  String regionCityCount(int count) {
    return '$count市区町村';
  }

  @override
  String get regionChangePrefecture => '都道府県を選び直す';

  @override
  String get regionNoResults => '該当する地域がありません';

  @override
  String regionAdded(String region, int count, int max) {
    return '$region を追加 ($count/$max)';
  }

  @override
  String regionRemoved(String region, int count, int max) {
    return '$region を外しました ($count/$max)';
  }

  @override
  String regionMultiHint(int max) {
    return '下のリストをタップして最大$maxか所まで追加・もう一度タップで外れます。上の地域をタップするとその地域に切り替わります。';
  }

  @override
  String get regionKeepOne => '地域は1か所以上必要です';

  @override
  String reviewQuestion(String nickname) {
    return '$nicknameさんとの取引はいかがでしたか？';
  }

  @override
  String get reviewQuestionSub => '評価はお互いのマナー温度に反映されます';

  @override
  String get reviewRatingBad => '残念だった';

  @override
  String get reviewRatingGood => '良かった';

  @override
  String get reviewRatingBest => '最高だった';

  @override
  String get reviewRatingSoso => '普通';

  @override
  String get reviewTagsTitleGood => 'どんなところが良かったですか？';

  @override
  String get reviewTagsTitleBad => 'どんなところが残念でしたか？';

  @override
  String get reviewTagsSub => '当てはまるものをすべて選んでください';

  @override
  String get reviewBadPrivateNotice =>
      '「残念だった」の評価と選んだ項目は相手のプロフィールには公開されず、マナー温度にのみ反映されます';

  @override
  String get reviewCommentTitle => '取引のコメントを書きましょう';

  @override
  String get reviewCommentTitleBad => '残念だった点を教えてください';

  @override
  String reviewCommentOptional(String nickname) {
    return '任意です。コメントは$nicknameさんのプロフィールに公開されます';
  }

  @override
  String get reviewCommentOptionalBad => '任意です。この内容は公開されません';

  @override
  String reviewCommentHint(String nickname) {
    return '$nicknameさんに感謝の気持ちを伝えましょう';
  }

  @override
  String get reviewCommentHintBad => 'どんな点が残念でしたか？';

  @override
  String get reviewNext => '次へ';

  @override
  String get reviewBack => '戻る';

  @override
  String get reviewSubmit => '評価を送信する';

  @override
  String get reviewSent => '取引の評価を送信しました';

  @override
  String get reviewSendButton => '取引を評価する';

  @override
  String get reviewViewMine => '送った評価を見る';

  @override
  String reviewSentTo(String nickname) {
    return '$nicknameさんに送った評価';
  }

  @override
  String get reviewPromptBody => '評価はお互いのマナー温度に反映されます';

  @override
  String get reviewPromptDone => '評価を送信しました。気持ちのよいお取引をありがとうございました！';

  @override
  String get reviewRoleBuyer => '購入者';

  @override
  String get reviewRoleSeller => '出品者';

  @override
  String get reviewPraiseTitle => 'もらったマナー評価';

  @override
  String get reviewPraiseMore => 'もっと見る';

  @override
  String get reviewPraiseLess => '閉じる';

  @override
  String get reviewNoPraise => 'まだマナー評価はありません';

  @override
  String get reviewReceivedTitle => 'もらった取引コメント';

  @override
  String get reviewNoComments => 'まだ取引コメントはありません';

  @override
  String get reviewPurchasesTitle => '購入した商品';

  @override
  String get reviewPurchasesEmpty => '購入した商品はありません';

  @override
  String get reviewPurchasesLoadFailed => '購入履歴を読み込めませんでした';

  @override
  String get reviewCounterpartFallback => '取引相手';

  @override
  String get reviewTagKind => '親切で丁寧な対応でした';

  @override
  String get reviewTagPunctual => '時間を守ってくれました';

  @override
  String get reviewTagFastReply => '返信が早かったです';

  @override
  String get reviewTagAsDescribed => '商品の状態が説明どおりでした';

  @override
  String get reviewTagDetailedDesc => '商品説明が詳しかったです';

  @override
  String get reviewTagGoodPrice => '良い商品をお手頃価格で出品しています';

  @override
  String get reviewTagFreeShare => '無料で譲ってくれました';

  @override
  String get reviewTagPaidOnTime => '期日どおりに支払い・受け取りをしてくれました';

  @override
  String get reviewTagNoHaggle => '無理な値下げ交渉がありませんでした';

  @override
  String get reviewTagLate => '時間を守りませんでした';

  @override
  String get reviewTagSlowReply => '返信が遅かったです';

  @override
  String get reviewTagRude => '対応が不親切でした';

  @override
  String get reviewTagNotAsDescribed => '商品の状態が説明と違いました';

  @override
  String get reviewTagPriceChange => '急に価格を変更されました';

  @override
  String get reviewTagNoShow => '待ち合わせ場所に来ませんでした';

  @override
  String get reviewTagHaggle => '無理な値下げ交渉をされました';
}
