// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get authWalletRequired => '지갑주소를 입력해주세요';

  @override
  String get authWalletFormat => '0x로 시작하는 42자리 형식이어야 해요';

  @override
  String get authNicknameRequired => '닉네임을 입력해주세요';

  @override
  String get authNicknameTooShort => '닉네임은 2자 이상이어야 해요';

  @override
  String get authNicknameTooLong => '닉네임은 12자 이하여야 해요';

  @override
  String get authNicknameCharset => '한글·일본어·영문·숫자·_ 만 사용 가능해요 (공백·특수문자 금지)';

  @override
  String get authPasswordRequired => '비밀번호를 입력해주세요';

  @override
  String get authPasswordTooShort => '비밀번호는 8자 이상이어야 해요';

  @override
  String get authPasswordTooLong => '비밀번호는 64자 이하여야 해요';

  @override
  String get authPasswordMix => '영문과 숫자를 모두 포함해야 해요';

  @override
  String authPhoneCheckExample(String example) {
    return '휴대폰 번호를 확인해주세요 (예: $example)';
  }

  @override
  String get authPhoneCheck => '휴대폰 번호를 확인해주세요';

  @override
  String get authTooManyRequests => '요청이 너무 많아요. 잠시 후 다시 시도해주세요';

  @override
  String get authSmsQuotaExceeded => '오늘 문자 발송 한도를 넘었어요. 내일 다시 시도해주세요';

  @override
  String authSmsSendFailedCode(String code) {
    return '문자를 보내지 못했어요. 잠시 후 다시 시도해주세요 ($code)';
  }

  @override
  String get authSmsSendFailed => '문자를 보내지 못했어요. 잠시 후 다시 시도해주세요';

  @override
  String get authSmsCodeInvalid => '문자로 받은 6자리 숫자를 입력해주세요';

  @override
  String get authPhoneVerifyFailedRetry => '휴대폰 인증을 마치지 못했어요. 다시 시도해주세요';

  @override
  String get authSmsCodeWrong => '인증번호가 맞지 않아요';

  @override
  String get authSmsCodeExpired => '인증번호가 만료됐어요. 다시 받아주세요';

  @override
  String authPhoneVerifyFailedCode(String code) {
    return '휴대폰 인증을 마치지 못했어요 ($code)';
  }

  @override
  String get authPhoneVerifyFailedLater => '휴대폰 인증을 마치지 못했어요. 잠시 후 다시 시도해주세요';

  @override
  String get authPhoneStepTitle => '2단계 · 휴대폰 인증';

  @override
  String get authPhoneStepDesc =>
      '문자로 받은 인증번호를 입력하면 끝! 한 번호로 한 계정만 인증할 수 있어요. 번호는 저장하지 않고 확인용 암호값만 남아요.';

  @override
  String get authPhoneNumberLabel => '휴대폰 번호';

  @override
  String get authSending => '보내는 중…';

  @override
  String get authGetCode => '인증번호 받기';

  @override
  String get authCodeLabel => '인증번호 6자리';

  @override
  String get authChecking => '확인 중…';

  @override
  String get authVerify => '인증하기';

  @override
  String get authChangeNumber => '번호 바꾸기';

  @override
  String get authResendCode => '인증번호 다시 받기';

  @override
  String get authResponseSlow => '응답이 너무 느려요. 네트워크 상태를 확인하고 다시 시도해주세요.';

  @override
  String get authRegisterFailed => '가입 중 문제가 생겼어요. 잠시 후 다시 시도해주세요';

  @override
  String authReferralCredited(String nickname) {
    return '🎉 추천인 $nickname님께 +200 QTA 지급 완료!';
  }

  @override
  String get authReferralNotFound => '추천인 닉네임을 찾을 수 없어 초대 보너스가 적용되지 않았어요.';

  @override
  String get authReferralSelf => '자기 자신은 추천인으로 입력할 수 없어요.';

  @override
  String get authReferralAlreadyProcessed => '이미 처리된 초대예요.';

  @override
  String get authRegisterTitle => '회원가입';

  @override
  String get authRegisterHeadline => '닉네임만 정하면\n바로 가입 🍆';

  @override
  String get authRegisterDesc =>
      '지갑이 없어도 가입할 수 있어요. 가입 후 \'나의 가지 → 프로필 인증\' 에서 1단계 지갑 인증 · 2단계 휴대폰 인증을 마치면 1,000 QTA 를 드려요.';

  @override
  String get authNicknameLabel => '닉네임';

  @override
  String get authNicknameHint => '2~12자, 중복 불가';

  @override
  String get authNicknamePlaceholder => '익명가지123';

  @override
  String get authPasswordLabel => '비밀번호';

  @override
  String get authMin8 => '8자 이상';

  @override
  String get authPasswordPlaceholder => '영문·숫자·특수문자 조합 권장';

  @override
  String get authPasswordConfirmLabel => '비밀번호 확인';

  @override
  String get authEnterAgain => '다시 한 번 입력';

  @override
  String get authPasswordConfirmRequired => '비밀번호 확인을 입력해주세요';

  @override
  String get authPasswordMismatch => '비밀번호가 일치하지 않아요';

  @override
  String get authReferrerLabel => '추천인 닉네임 (선택)';

  @override
  String get authReferrerHint => '친구가 +200 QTA 받아요 · 무제한';

  @override
  String get authReferrerPlaceholder => '추천해주신 분의 닉네임';

  @override
  String get authRegisterBonusInfo =>
      '지갑·휴대폰 인증을 마치면 +1,000 QTA 지급! 추천인을 입력하면 추천인에게 +200 QTA가 무제한으로 지급돼요.\n※ 가입 후 탈퇴하면 추천인의 보너스는 즉시 회수돼요.';

  @override
  String get authWalletImmutableInfo =>
      '지갑주소는 변경할 수 없어요. 닉네임/비밀번호 분실 시 같은 지갑으로만 복구할 수 있습니다.';

  @override
  String get authRegisterButton => '가입하기';

  @override
  String get authHaveAccountLogin => '이미 계정이 있어요 — 로그인';

  @override
  String get authServerSlow => '서버 응답이 늦어요. 잠시 후 다시 시도해주세요 🕐';

  @override
  String get authLookupFailed => '계정 조회 중 문제가 생겼어요. 다시 시도해주세요.';

  @override
  String get authPasswordResetDone => '비밀번호를 새로 설정했어요 🔒';

  @override
  String get authResetFailed => '비밀번호 재설정 중 문제가 생겼어요. 다시 시도해주세요.';

  @override
  String get authFindAccountTitle => '계정 찾기';

  @override
  String get authFindHeadline => '지갑주소로\n계정을 찾아요';

  @override
  String get authFindDesc =>
      '가입할 때 사용한 퀀타리움 지갑주소를 입력해주세요.\n지갑 소유를 인증하면 닉네임을 확인하고 비밀번호를 다시 설정할 수 있어요.';

  @override
  String get authQuantariumWalletLabel => '퀀타리움 지갑주소';

  @override
  String get authPaste => '붙여넣기';

  @override
  String get authCheckAccount => '계정 확인';

  @override
  String get authRegisteredNickname => '등록된 닉네임';

  @override
  String get authNewPasswordTitle => '새 비밀번호 설정';

  @override
  String get authNewPasswordDesc =>
      '재설정 후 기존에 로그인된 모든 기기는 자동으로 로그아웃돼요.\n이 계정을 쓰던 기기라면 바로 재설정되고, 다른 기기·앱 재설치 후라면 아래 지갑 인증이 필요해요.';

  @override
  String get authNewPasswordLabel => '새 비밀번호';

  @override
  String get authNewPasswordConfirmLabel => '새 비밀번호 확인';

  @override
  String get authResetPasswordButton => '비밀번호 재설정';

  @override
  String get authFindAgain => '다른 지갑주소로 다시 찾기';

  @override
  String get authWalletVerifiedInfo => '지갑 인증 완료 — 본인 지갑임이 확인됐어요';

  @override
  String get authVerifyAgain => '다시 인증하기';

  @override
  String get authWalletVerifyTitle => '지갑 인증';

  @override
  String get authWalletRegisterTitle => '지갑 등록';

  @override
  String get authWalletVerifyResetTitle => '지갑 인증 (다른 기기에서 재설정 시)';

  @override
  String get authWalletVerifyDescRegister =>
      '다른 사람이 내 지갑주소를 쓰지 못하도록, 이 지갑에서 화면에 나오는 아주 적은 수량(0.1 QTA 미만)을 가지 인증 지갑으로 보내 본인 지갑임을 확인해요.';

  @override
  String get authWalletVerifyDescVerify =>
      '내 퀀타리움 지갑에서 화면에 나오는 아주 적은 수량(0.1 QTA 미만)을 가지 인증 지갑으로 보내면 지갑 주인임이 확인돼요. 출금한 QTA 는 이 지갑으로 송금돼요.';

  @override
  String get authWalletVerifyDescReset =>
      '이 지갑에서 화면에 나오는 아주 적은 수량(0.1 QTA 미만)을 가지 인증 지갑으로 보내 본인 지갑임을 확인해요. 내 지갑으로 누군가 먼저 가입했다면 이 방법으로 계정을 되찾을 수 있어요.';

  @override
  String get authMyQuantariumWalletLabel => '내 퀀타리움 지갑주소';

  @override
  String get authWalletHint42 => '0x + 40자리 (총 42자)';

  @override
  String get authPreparing => '준비 중…';

  @override
  String get authWalletVerifyStart => '지갑 인증 시작';

  @override
  String get authAmountToSend => '보낼 금액';

  @override
  String get authAmountCopied => '금액을 복사했어요';

  @override
  String get authRecipientMyWallet => '받는 주소 (내 지갑)';

  @override
  String get authRecipientEggplantWallet => '받는 주소 (가지 인증 지갑)';

  @override
  String get authAddressCopied => '주소를 복사했어요';

  @override
  String authWalletSendInstruction(String wallet) {
    return '퀀타리움 지갑 앱에서 $wallet 지갑으로 위 수량을 정확히 보내고, 블록에 담기면(보통 수십 초) 아래 버튼을 눌러주세요. 30분 안에 보내야 해요.';
  }

  @override
  String get authSentCheck => '송금했어요 — 확인하기';

  @override
  String get authNewAmount => '새 금액 받기';

  @override
  String get authCopy => '복사';

  @override
  String get authReceiveAmountInvalid =>
      '소수점 아래 6자리 숫자를 입력해주세요 (예: 0.234567 이면 234567)';

  @override
  String get authWalletStepTitle => '1단계 · 지갑 인증';

  @override
  String get authWalletStepDesc =>
      '내 퀀타리움 지갑주소를 넣으면 가지 본사 지갑이 5.xxxxxx QTA 를 보내드려요. 그중 앱이 알려주는 1.xxxxxx QTA 를 본사 지갑으로 돌려보내면 인증 끝! (지갑 주인만 보낼 수 있어서 안전해요)';

  @override
  String get authRequesting => '요청 중…';

  @override
  String get authReceiveCoinButton => '이 지갑으로 인증 코인 받기';

  @override
  String get authReceiveSendFailed => '지금 인증 코인을 보내지 못했어요. 잠시 후 다시 요청해주세요';

  @override
  String get authRequestAgain => '다시 요청하기';

  @override
  String authReceiveSending(String wallet) {
    return '가지 본사 지갑에서 $wallet 으로 보내는 중이에요… (보통 1분 이내)';
  }

  @override
  String authReceiveSent(String wallet) {
    return '보냈어요! 퀀타리움 지갑 앱에서 $wallet 에 들어온 수량을 확인하고 소수점 아래 6자리를 입력해주세요. 블록에 담기기까지 수십 초 걸릴 수 있어요.';
  }

  @override
  String get authCheckWalletCode => 'scan.quantarium.io 에서 내 지갑 보기';

  @override
  String get authReceivedAmount => '받은 수량';

  @override
  String authAttemptsLeft(String count) {
    return '남은 기회 $count번 · 24시간 안에 입력해주세요';
  }

  @override
  String get authLoginFailed => '로그인 중 문제가 생겼어요. 다시 시도해주세요.';

  @override
  String get authLoginTitle => '로그인';

  @override
  String get authLoginDesc =>
      '닉네임과 비밀번호로 로그인하세요.\n큐알쳇 회원이라면 큐알쳇 닉네임·비밀번호로 바로 로그인돼요.';

  @override
  String get authLoginNicknameHint => '가입할 때 설정한 닉네임';

  @override
  String get authLoginButton => '로그인';

  @override
  String get authFindNicknamePassword => '닉네임 / 비밀번호 찾기';

  @override
  String get authSessionInfo => '다른 기기에서 같은 계정으로 로그인하면 이전 기기의 세션은 즉시 종료돼요.';

  @override
  String get authSplashTagline => '익명으로 안전한 중고거래 🍆';

  @override
  String get authOnboarding1Headline => '전화번호 없이\n익명으로 거래해요';

  @override
  String get authOnboarding1Desc => '닉네임 하나면 충분해요.\n개인정보 노출 걱정 없이 안전하게.';

  @override
  String get authOnboarding2Headline => '우리 동네\n이웃과 거래해요';

  @override
  String get authOnboarding2Desc => '내 동네 인증된 사람들과만 만나요.\nQR 코드로 안심하고 직거래!';

  @override
  String get authOnboarding3Headline => '쓸수록 쌓이는\nQTA 토큰 보상';

  @override
  String get authOnboarding3Desc =>
      '지갑·휴대폰 인증하면 +1,000 QTA,\n친구 초대마다 +200 QTA × 무제한!';

  @override
  String get authPermTitle => '원활한 사용을 위해\n아래 권한이 필요해요';

  @override
  String get authPermSubtitle => '한 번만 허용하면 다시 묻지 않아요.';

  @override
  String get authPermCamera => '카메라';

  @override
  String get authPermCameraDesc => 'QR 스캔 · 상품 사진/영상 촬영';

  @override
  String get authPermMic => '마이크';

  @override
  String get authPermMicDesc => '익명 음성통화 (상대방에게만 전달)';

  @override
  String get authPermPhotos => '사진 / 동영상';

  @override
  String get authPermPhotosDesc => '갤러리에서 상품 사진 선택';

  @override
  String get authPermNotifications => '알림';

  @override
  String get authPermNotificationsDesc => '새 채팅 · 통화 알림';

  @override
  String get authPermContinue => '확인하고 계속';

  @override
  String get authPermLater => '나중에 하기';

  @override
  String get authSkip => '건너뛰기';

  @override
  String get authStart => '시작하기';

  @override
  String get authNext => '다음';

  @override
  String get authHaveAccountQuestion => '이미 계정이 있어요?';

  @override
  String get authDeleteAgreeRequired => '안내 사항에 동의해야 탈퇴할 수 있어요.';

  @override
  String get authDeletePasswordRequired => '비밀번호를 입력해주세요.';

  @override
  String get authDeleteDialogTitle => '정말 탈퇴할까요?';

  @override
  String get authDeleteDialogBody =>
      '계정과 모든 데이터가 즉시 영구 삭제돼요.\n복구는 불가능하며, 잔여 QTA·받은 추천 보너스는 회수돼요.';

  @override
  String get authDeleteDialogConfirm => '영구 삭제';

  @override
  String get authDeleteFailed => '탈퇴 처리 중 문제가 생겼어요. 다시 시도해주세요.';

  @override
  String get authDeleteDone => '탈퇴가 완료되었어요. 이용해주셔서 감사했어요. 🍆';

  @override
  String get authDeleteTitle => '계정 영구 삭제';

  @override
  String get authDeleteWarning => '탈퇴하면 즉시 영구 삭제돼요\n한 번 사라진 데이터는 복구되지 않아요.';

  @override
  String get authDeleteDataTitle => '삭제되는 데이터';

  @override
  String get authDeleteBullet1 => '내 닉네임 · 동네 · 매너 점수 · 매너 리뷰';

  @override
  String get authDeleteBullet2 => '내가 등록한 모든 상품';

  @override
  String authDeleteBullet3(String balance) {
    return '잔여 QTA 잔액 ($balance QTA) 폐기';
  }

  @override
  String get authDeleteBullet4 => '받은 친구 초대 보너스는 즉시 회수 (−200 QTA × 인원)';

  @override
  String get authDeleteBullet5 => '내가 추천인이 됐던 친구의 보너스도 즉시 회수';

  @override
  String get authDeleteBullet6 => '숨김/차단/키워드 알림/검색 기록 모두 사라짐';

  @override
  String get authDeleteBullet7 => '채팅 메시지·통화 기록은 원래부터 저장된 게 없어요 🔐';

  @override
  String get authDeleteAgree => '위 사항을 모두 이해했고, 영구 삭제에 동의해요.';

  @override
  String get authDeletePasswordTitle => '비밀번호 재확인';

  @override
  String get authDeleteButton => '영구 삭제하기';

  @override
  String get authDeleteCancelBack => '취소하고 돌아가기';

  @override
  String get authProfileVerifyTitle => '프로필 인증';

  @override
  String get authProfileStepsTitle => '인증 단계';

  @override
  String get authProfileStep0Title => '가입';

  @override
  String get authProfileStep0Desc =>
      '닉네임·비밀번호로 가입하면 자동 완료.\n둘러보기 · 채팅 · 통화 · 상품 등록 가능.';

  @override
  String get authProfileStep1Desc =>
      '내 퀀타리움 지갑주소를 넣으면 가지 본사 지갑이 5.xxxxxx QTA를 보내드려요.\n받은 지갑에서 안내된 1.xxxxxx QTA를 본사로 돌려보내면 인증 끝!\n출금한 QTA 는 이 지갑으로 송금돼요.';

  @override
  String get authProfileDoneLabel => '완료됨';

  @override
  String get authProfileWalletDoneSnack => '지갑 인증을 마쳤어요. 이제 2단계 휴대폰 인증!';

  @override
  String get authProfileStep2Title => '휴대폰 인증';

  @override
  String get authProfileStep2Desc =>
      '문자로 받은 인증번호를 입력해요. 한 번호로 한 계정만 인증돼요.\n거래완료 · QTA 결제 거래 · 출금이 열려요.\n\n🔒 전화번호는 암호화해 보관하며, 불법 이용 추적 외에는 쓰지 않아요. 한국(010)·일본(070/080/090)·필리핀(09) 휴대폰 번호만 인증돼요.';

  @override
  String get authProfileWalletFirst => '1단계 지갑 인증을 먼저 마쳐주세요.';

  @override
  String get authProfileComingSoon => '곧 열려요';

  @override
  String get authProfilePhoneStart => '휴대폰 인증 시작';

  @override
  String get authProfileStep1First => '1단계 먼저';

  @override
  String get authProfilePhoneDoneSnack => '휴대폰 인증을 마쳤어요';

  @override
  String get authProfilePolicyTitle => '익명성 정책';

  @override
  String get authProfilePolicy1 => '채팅 / 음성통화는 인증 단계와 무관하게 항상 닉네임만 노출됩니다.';

  @override
  String get authProfilePolicy2 =>
      '인증 정보는 거래 자격 확인 용도로만 쓰이며, 거래 상대방·다른 사용자에게 절대 노출되지 않습니다.';

  @override
  String get authProfilePolicy3 => '같은 지갑·같은 휴대폰 번호로 여러 계정을 인증할 수 없어요.';

  @override
  String get authProfileBonusDialogTitle => '인증 완료 🎉';

  @override
  String authProfileBonusDialogBody(String bonus) {
    return '1·2단계 인증을 모두 마쳤어요!\n인증 보너스 +$bonus QTA 를 드렸어요.\n이제 QTA 결제 거래와 출금을 할 수 있어요.';
  }

  @override
  String get authProfileAllDone => '인증 완료';

  @override
  String get authProfileStep1Done => '1단계 완료 · 휴대폰 인증 남음';

  @override
  String get authProfileUnverified => '미인증';

  @override
  String authProfileProgress(String done) {
    return '인증 $done/2 단계';
  }

  @override
  String authProfileBonusReceived(String bonus) {
    return '인증 보너스 $bonus QTA 를 받았어요';
  }

  @override
  String authProfileBonusPending(String bonus) {
    return '1·2단계 인증을 모두 마치면 $bonus QTA 를 드려요!';
  }

  @override
  String get authProfileDoneBadge => '완료';

  @override
  String get authGuardPhoneTitle => '휴대폰 인증이 필요해요';

  @override
  String get authGuardWalletTitle => '지갑 인증이 필요해요';

  @override
  String get authGuardPhoneMessage =>
      '거래(결제)는 1인 1계정 보장을 위해 1단계 지갑 인증과 2단계 휴대폰 인증이 필요해요.\n인증해도 채팅·통화는 익명 그대로 유지돼요.';

  @override
  String get authGuardWalletMessage =>
      'QTA 출금을 위해 1단계 지갑 인증과 2단계 휴대폰 인증이 필요해요.\n두 단계를 모두 마치면 1,000 QTA 도 드려요.';

  @override
  String get authGuardGoVerify => '인증하러 가기';

  @override
  String get authPassPopupTitle => '가지마켓 본인인증';

  @override
  String get authAccountSuspended => '이용이 정지된 계정이에요';

  @override
  String authRegisterFailedStatus(String status) {
    return '가입 실패 (status=$status)';
  }

  @override
  String get authServerTooSlow => '서버 응답이 너무 느려요. 네트워크를 확인하고 다시 시도해주세요.';

  @override
  String get authDeleteFailedShort => '탈퇴 처리 실패';

  @override
  String get authLoginFailedShort => '로그인 실패';

  @override
  String get authSsoFailed => 'SSO 인증 실패';

  @override
  String get authNotFound => '찾을 수 없어요';

  @override
  String get authResetFailedShort => '비밀번호 재설정 실패';

  @override
  String get authRegionSaveFailed => '동네를 저장하지 못했어요';

  @override
  String get authNicknameLength => '닉네임은 2~12자여야 해요';

  @override
  String get authNicknameChangeFailed => '닉네임 변경 실패';

  @override
  String get authWalletVerifyStartFailed => '지갑 인증을 시작하지 못했어요';

  @override
  String get authTransferNotConfirmed => '아직 송금이 확인되지 않았어요';

  @override
  String get authAmountCheckFailed => '수량을 확인하지 못했어요';

  @override
  String get authCannotConnect => '서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요.';

  @override
  String get authTimeout => '응답 시간이 초과되었어요.';

  @override
  String get authGenericError => '오류가 발생했어요';

  @override
  String get authQuantumBadge => '양자내성 서명(SPHINCS+)으로 보낸 거래예요';

  @override
  String get authViewTxOnScan => 'scan.quantarium.io 에서 본사 송금 보기';

  @override
  String get authResetWalletTitle => '지갑 인증 (다른 기기에서 재설정 시)';

  @override
  String get authResetWalletDesc =>
      '가입할 때 등록한 지갑과 같은지 먼저 확인한 뒤, 가지 본사 지갑이 그 지갑으로 5.xxxxxx QTA 를 보내드려요. 앱이 알려주는 1.xxxxxx QTA 를 본사 지갑으로 돌려보내면 인증 끝!';

  @override
  String get authResetWalletVerified => '지갑 인증 완료! 아래에 새 비밀번호를 입력하세요.';

  @override
  String get authScanHint =>
      '지갑 앱에 소량이 안 보이면 위 scan 버튼을 눌러 화면의 Value(예: 0.234567 QTA)를 확인하고, 소수점 아래 6자리를 아래 칸에 입력하세요.';

  @override
  String authReturnSent(String wallet, String amount) {
    return '가지 본사 지갑이 $wallet 으로 $amount QTA 를 보냈어요.';
  }

  @override
  String get authReturnTitle => '이제 이 수량을 본사 지갑으로 돌려보내 주세요';

  @override
  String get authReturnDesc =>
      '퀀타리움 지갑 앱에서 아래 수량을 정확히, 아래 주소로 보내세요. 지갑 주인만 보낼 수 있어서 이걸로 내 지갑임이 증명돼요.';

  @override
  String get authReturnAmountLabel => '돌려보낼 수량 (정확히)';

  @override
  String get authReturnToLabel => '받는 주소 (가지 본사 지갑)';

  @override
  String get authReturnNote =>
      '이 수량은 이번 한 번만 쓰여요 · 2시간 안에 보내주세요 · 블록에 담기기까지 수십 초 걸릴 수 있어요';

  @override
  String get authReturnSentButton => '보냈어요 — 확인하기';

  @override
  String get chatLeaveWarningSubtitle => '🔒 나가면 양쪽 모두 완전 삭제돼요';

  @override
  String get chatVoiceCallTooltip => '익명 음성통화';

  @override
  String get chatOfferSheetTitle => '💰 가격 제안하기';

  @override
  String chatOfferAmountHint(String unit) {
    return '제안 금액 ($unit)';
  }

  @override
  String get chatCurrencyUnitKrw => '원';

  @override
  String get chatCurrencyUnitJpy => '엔';

  @override
  String get chatOfferSend => '제안 보내기';

  @override
  String get chatOfferAutoCancelNote => '이전에 보낸 미응답 제안은 자동으로 취소돼요.';

  @override
  String get chatOfferAccept => '수락';

  @override
  String get chatOfferReject => '거절';

  @override
  String get chatOfferCancelAction => '취소';

  @override
  String chatOfferDialogTitle(String action) {
    return '가격 제안 $action';
  }

  @override
  String get chatOfferAcceptConfirm => '이 가격에 거래를 진행하시겠어요?';

  @override
  String get chatOfferRejectConfirm => '제안을 거절할까요?';

  @override
  String get chatPeerNotFound => '상대방 정보를 찾을 수 없어요';

  @override
  String get chatClearMessages => '대화 내용 삭제';

  @override
  String get chatClearMessagesSubtitle => '이 방의 메시지만 비워요 (방은 유지)';

  @override
  String get chatLeaveRoom => '채팅방 나가기';

  @override
  String get chatLeaveRoomSubtitle => '양쪽 모두 대화 + 방을 완전 삭제해요 (복구 불가)';

  @override
  String chatLeaveRoomConfirm(String nickname) {
    return '$nickname님과의 대화를 완전히 삭제할까요?\n\n• 메시지 전부 영구 삭제\n• 상대방 화면에서도 즉시 사라짐\n• 복구 불가';
  }

  @override
  String get chatDeletePermanently => '완전히 삭제';

  @override
  String get chatDeleteFailedRetry => '삭제 실패. 잠시 후 다시 시도해주세요';

  @override
  String get chatClearMessagesConfirm =>
      '이 방의 모든 메시지를 지울까요?\n방은 유지되며 상대방 화면의 메시지도 같이 지워져요.';

  @override
  String get chatMessagesCleared => '대화 내용을 비웠어요';

  @override
  String get chatDeleteFailed => '삭제 실패';

  @override
  String chatEmptyTitle(String nickname) {
    return '$nickname 님과\n익명 채팅이 시작되었어요';
  }

  @override
  String get chatEmptyNote => '이 대화는 서버/기기 어디에도 저장되지 않아요.\n화면을 벗어나면 내용이 사라져요.';

  @override
  String get chatRead => '읽음';

  @override
  String get chatOfferLabel => '가격 제안';

  @override
  String get chatInputHint => '메시지 입력';

  @override
  String get chatConnecting => '연결 중...';

  @override
  String get chatOfferCancelButton => '제안 취소하기';

  @override
  String get chatCallOutgoing => '호출 중...';

  @override
  String get chatCallIncoming => '걸려온 익명 통화';

  @override
  String get chatCallEnded => '통화 종료';

  @override
  String get chatCallHeader => '완전 익명 음성 통화';

  @override
  String get chatCallP2pNote => '이 통화는 P2P로 직접 연결돼요.\n서버에 녹음·저장되지 않아요.';

  @override
  String get chatCallDecline => '거절';

  @override
  String get chatCallAccept => '수락';

  @override
  String get chatCallUnmute => '음소거 해제';

  @override
  String get chatCallMute => '음소거';

  @override
  String get chatCallHangup => '종료';

  @override
  String get chatCallSpeaker => '스피커';

  @override
  String get chatCallEarpiece => '수화기';

  @override
  String chatLeaveRoomConfirmList(String nickname) {
    return '$nickname님과의 대화를 완전히 삭제할까요?\n\n• 주고받은 모든 메시지가 사라져요\n• 상대방 화면에서도 함께 삭제돼요\n• 복구할 수 없어요';
  }

  @override
  String get chatRoomDeleted => '채팅방을 삭제했어요';

  @override
  String get chatTabTitle => '채팅';

  @override
  String get chatQrScanTooltip => 'QR 스캔해서 대화 시작';

  @override
  String get chatPrivacyBanner => '대화는 어디에도 저장되지 않아요. 앱을 닫으면 사라져요.';

  @override
  String get chatListEmptyTitle => '아직 대화가 없어요';

  @override
  String get chatListEmptyHint => '관심있는 상품에서 \"채팅하기\"를 눌러보세요';

  @override
  String get chatSwipeLeave => '나가기';

  @override
  String chatRoomAboutProduct(String title) {
    return '$title 관련 대화';
  }

  @override
  String get chatSendFirstMessage => '메시지를 보내보세요';

  @override
  String chatLastMessageMine(String message) {
    return '나: $message';
  }

  @override
  String get chatAnonymous => '익명';

  @override
  String get chatEnterAmount => '금액을 입력해주세요';

  @override
  String get chatReconnecting => '연결 중이에요. 잠시 후 다시 시도해주세요';

  @override
  String get chatRoomNotFound => '대화방을 찾을 수 없어요';

  @override
  String get chatNewMessage => '새 메시지';

  @override
  String get chatEnterMessage => '내용을 입력해주세요';

  @override
  String get chatCallPeerDeclined => '상대방이 통화를 거절했어요';

  @override
  String get chatCallRetryLater => '연결을 시도했어요. 잠시 후 다시 걸어주세요.';

  @override
  String get chatCallFailed => '통화 실패';

  @override
  String get chatCallAlreadyInCall => '이미 통화 중이에요';

  @override
  String get chatCallStillConnecting => '연결 중이에요';

  @override
  String get chatCallWaitingAnswer => '응답을 기다리고 있어요';

  @override
  String get chatCallHasIncoming => '걸려온 통화가 있어요';

  @override
  String get chatMicPermissionRequired => '마이크 권한이 필요해요';

  @override
  String get chatCallServerDisconnected => '서버에 연결되지 않았어요';

  @override
  String get chatCallNoAnswer => '상대방이 받지 않았어요';

  @override
  String get chatMicPermissionSettings => '설정 > 권한 > 마이크에서 권한을 켜주세요';

  @override
  String get chatCallAgoraConfigMissing => 'Agora 설정이 누락되었어요';

  @override
  String get chatCallPeerNotConnected => '상대와 연결되지 않았어요';

  @override
  String get chatCallEndedMessage => '통화가 종료되었어요';

  @override
  String get chatCallAuthExpired => '통화 인증이 만료되었어요';

  @override
  String get chatCallDisconnected => '통화 연결이 끊어졌어요';

  @override
  String get chatCallNetworkUnstable => '네트워크가 불안정해요';

  @override
  String get chatCallkitAppName => '가지마켓';

  @override
  String get chatCallkitAccept => '받기';

  @override
  String get chatCallkitDecline => '거절';

  @override
  String get chatMissedCall => '부재중 전화';

  @override
  String get chatIncomingCallChannel => '전화 수신 (V2)';

  @override
  String get chatMissedCallChannel => '부재중 전화 (V2)';

  @override
  String get chatChannelChatName => '채팅 메시지';

  @override
  String get chatChannelChatDesc => '새 채팅 메시지 알림';

  @override
  String get chatChannelKeywordName => '키워드 알림';

  @override
  String get chatChannelKeywordDesc => '관심 키워드와 일치하는 새 상품 알림';

  @override
  String get chatChannelPushName => 'Eggplant 메시지';

  @override
  String get chatChannelPushDesc => '새 채팅 메시지 푸시 알림';

  @override
  String get chatChannelCallName => 'Eggplant 전화';

  @override
  String get chatChannelCallDesc => '음성 통화 수신 알림';

  @override
  String get chatKeywordAlertTitle => '🔔 새 매물 알림';

  @override
  String get chatKeywordAlertMaskedBody => '관심 키워드와 일치하는 새 상품이 있어요';

  @override
  String get chatKeywordTicker => '새 매물';

  @override
  String get chatMaskedMessageTitle => '💬 새 메시지가 있어요';

  @override
  String get chatMaskedMessageBody => '메시지를 보려면 탭하세요';

  @override
  String get chatPermMicBody => '설정 > 앱 > Eggplant에서 마이크를 켜주세요.';

  @override
  String get chatPermCameraTitle => '카메라 권한이 필요해요';

  @override
  String get chatPermCameraBody => '설정 > 앱 > Eggplant에서 카메라를 켜주세요.';

  @override
  String get chatPermGalleryTitle => '갤러리 권한이 필요해요';

  @override
  String get chatPermGalleryBodyAndroid =>
      '설정 > 앱 > Eggplant에서 사진/동영상 권한을 켜주세요.';

  @override
  String get chatPermGalleryBodyIos => '설정 > Eggplant에서 사진 권한을 켜주세요.';

  @override
  String get chatPermNotifTitle => '🔔 알림 권한이 꺼져 있어요';

  @override
  String get chatPermNotifBody =>
      '알림이 꺼져 있으면 새 메시지·통화·키워드 매물 알림을 놓칠 수 있어요.\n\n설정에서 알림을 켜시겠어요?\n\n※ Eggplant는 알림 본문을 잠금화면에서 가리는 옵션도 제공해요. \"나의 Eggplant > 알림 본문 가리기\" 에서 켤 수 있어요.';

  @override
  String get chatPermOpenSettings => '설정 열기';

  @override
  String get chatPermFsiTitle => '🔒 잠금화면 통화 알림 권한';

  @override
  String get chatPermFsiBody =>
      '잠금화면에서 통화 수신을 표시하려면\n\"전체 화면 알림\" 권한이 필요해요.\n\n권한이 꺼져 있으면 잠금화면에서는\n벨소리만 울리고 통화 화면이 뜨지 않아요.\n\n한 번만 설정하면 끝나요.';

  @override
  String get chatPermAllow => '권한 허용';

  @override
  String get chatOfferStatusAccepted => '수락됨';

  @override
  String get chatOfferStatusRejected => '거절됨';

  @override
  String get chatOfferStatusCancelled => '취소됨';

  @override
  String get chatOfferStatusPending => '응답 대기';

  @override
  String get chatTimeJustNow => '방금 전';

  @override
  String chatTimeMinutesAgo(int n) {
    return '$n분 전';
  }

  @override
  String chatTimeHoursAgo(int n) {
    return '$n시간 전';
  }

  @override
  String chatTimeDaysAgo(int n) {
    return '$n일 전';
  }

  @override
  String chatTimeWeeksAgo(int n) {
    return '$n주 전';
  }

  @override
  String chatTimeMonthsAgo(int n) {
    return '$n개월 전';
  }

  @override
  String chatTimeYearsAgo(int n) {
    return '$n년 전';
  }

  @override
  String get chatCurrencyUnitPhp => '페소';

  @override
  String get chatAttachTooltip => '사진 · 약속';

  @override
  String get chatAttachGallery => '앨범에서 사진 보내기';

  @override
  String get chatAttachCamera => '카메라로 찍어 보내기';

  @override
  String get chatAttachAppointment => '거래 약속 잡기';

  @override
  String get chatPhotoSendFailed => '사진을 보내지 못했어요. 다시 시도해주세요';

  @override
  String get chatPhotoUnavailable => '사진을 열 수 없어요\n(받은 지 24시간이 지났거나 이미 지워졌어요)';

  @override
  String get chatAppointmentChange => '변경';

  @override
  String chatAppointmentSetBy(String name) {
    return '$name님이 거래 약속을 잡았어요';
  }

  @override
  String chatAppointmentCancelledBy(String name) {
    return '$name님이 거래 약속을 취소했어요';
  }

  @override
  String get chatAppointmentReminderNote => '약속 30분 전에 알려드려요';

  @override
  String get chatAppointmentTitle => '거래 약속 잡기';

  @override
  String get chatAppointmentEditTitle => '거래 약속 변경';

  @override
  String get chatAppointmentPlace => '만날 장소 (선택)';

  @override
  String get chatAppointmentCancel => '약속 취소';

  @override
  String get chatAppointmentSend => '약속 보내기';

  @override
  String get chatAppointmentPast => '지금보다 나중 시각을 골라주세요';

  @override
  String get chatAppointmentReminderTitle => '30분 뒤 거래 약속이 있어요';

  @override
  String get chatAppointmentReminderBody => '약속 시간을 지켜주세요';

  @override
  String get chatAppointmentSetByMe => '거래 약속을 잡았어요';

  @override
  String get chatAppointmentCancelledByMe => '거래 약속을 취소했어요';

  @override
  String get commonCancel => '취소';

  @override
  String get commonConfirm => '확인';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonSave => '저장';

  @override
  String get commonClose => '닫기';

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonLater => '나중에';

  @override
  String get commonFree => '나눔';

  @override
  String get commonLoginRequired => '로그인이 필요해요';

  @override
  String get commonNetworkError => '네트워크 오류가 발생했어요. 잠시 후 다시 시도해주세요';

  @override
  String priceKrw(String amount) {
    return '$amount원';
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
  String get homeSearchHint => '상품명 검색';

  @override
  String get homeSetRegion => '동네 설정';

  @override
  String get homeSearchClose => '검색 닫기';

  @override
  String get homeSearch => '검색';

  @override
  String get homeQrScan => 'QR 스캔';

  @override
  String get homeRecentSearches => '최근 검색어';

  @override
  String get homeClearAll => '전체 삭제';

  @override
  String get homeNoRecentSearches => '최근 검색 기록이 없어요';

  @override
  String get homeRangeAll => '전체';

  @override
  String get homeDistance => '거리';

  @override
  String get homeNoProducts => '아직 상품이 없어요';

  @override
  String get homeCheckNetwork => '네트워크를 확인하고 다시 시도해주세요';

  @override
  String get homeFirstProduct => '첫 번째 상품을 등록해보세요!';

  @override
  String get homeRefresh => '새로고침';

  @override
  String homeMyRegionsTitle(int count, int max) {
    return '내 동네 $count/$max';
  }

  @override
  String get homeMyRegionsHint =>
      '전체를 누르면 내 동네 상품이 모두 보이고, 동네를 누르면 그 동네 상품만 보여요.';

  @override
  String get homeRemoveRegion => '이 동네 빼기';

  @override
  String homeMaxRegions(int max) {
    return '최대 $max곳까지 설정할 수 있어요';
  }

  @override
  String get homeAddRegion => '동네 추가하기';

  @override
  String get homeCategoryAll => '전체';

  @override
  String get homeCategoryDigital => '디지털기기';

  @override
  String get homeCategoryAppliance => '생활가전';

  @override
  String get homeCategoryFurniture => '가구/인테리어';

  @override
  String get homeCategoryClothing => '의류';

  @override
  String get homeCategoryBeauty => '뷰티/미용';

  @override
  String get homeCategoryBook => '도서/티켓';

  @override
  String get homeCategorySports => '스포츠/레저';

  @override
  String get homeCategoryHobby => '취미/게임';

  @override
  String get homeCategoryKids => '유아동';

  @override
  String get homeCategoryPet => '반려동물';

  @override
  String get homeCategoryFood => '식품';

  @override
  String get homeCategoryEtc => '기타';

  @override
  String get homeLikesTitle => '찜한 상품';

  @override
  String homeLikesTitleCount(int count) {
    return '찜한 상품 $count';
  }

  @override
  String get homeLoadFailed => '불러올 수 없어요';

  @override
  String get homeTryLater => '잠시 후 다시 시도해주세요';

  @override
  String get homeNoLikes => '찜한 상품이 없어요';

  @override
  String get homeNoLikesHint => '관심있는 상품에 하트를 눌러보세요';

  @override
  String get homeSignupBonus => '🎉 가입을 환영해요! +500 QTA 가 지급됐어요';

  @override
  String homeLoginBonusRemaining(int remaining) {
    return ' · 오늘 $remaining회 더 받을 수 있어요';
  }

  @override
  String get homeLoginBonusLimitReached => ' · 오늘 한도 끝!';

  @override
  String homeLoginBonus(int amount, String tail) {
    return '📅 출석 보너스 +$amount QTA$tail';
  }

  @override
  String get homeWrite => '글쓰기';

  @override
  String get homeTabHome => '홈';

  @override
  String get homeTabLikes => '찜';

  @override
  String get homeTabChat => '채팅';

  @override
  String get homeTabMy => '내 정보';

  @override
  String get homeLocationServiceOff => '위치 서비스를 켜주세요 (설정 > 위치)';

  @override
  String get homeLocationPermissionNeeded => '위치 권한이 필요해요. 설정에서 허용해주세요.';

  @override
  String homeRegionVerifiedToast(String region) {
    return '$region 인증 완료 🎉';
  }

  @override
  String get homeMyRegion => '내 동네';

  @override
  String get homeLocationFailed => '현재 위치를 확인하지 못했어요. 위치 권한과 GPS 를 확인해주세요';

  @override
  String get homeRegionVerified => '동네 인증 완료';

  @override
  String get homeRegionVerifyNeeded => '동네 인증 필요';

  @override
  String homeRegionVerifiedDesc(String region) {
    return '$region · GPS 4km 이내 확인됨';
  }

  @override
  String homeRegionVerifyDesc(String region) {
    return '$region · GPS 인증으로 거리순 검색 가능해져요';
  }

  @override
  String get homeReverify => '재인증';

  @override
  String get homeVerify => '인증하기';

  @override
  String get homeRegionSettingsTitle => '내 동네 설정';

  @override
  String get homeRegionSearchHint => '동, 읍, 면으로 검색 (예: 강남)';

  @override
  String get homeRegionVerifyDialogTitle => '동네 인증할까요?';

  @override
  String homeRegionVerifyDialogBody(String region) {
    return '$region 에 정말 사는지 GPS 로 한 번만 확인하면 거리순 검색을 쓸 수 있어요.\n\n정확한 위치는 서버에 저장하지 않아요.';
  }

  @override
  String get homeVerifyNow => '지금 인증';

  @override
  String homeRegionSet(String region) {
    return '$region 으로 설정되었어요';
  }

  @override
  String get homeLoginToUse => '로그인 후 이용해주세요';

  @override
  String get homeMyQr => '내 QR 코드';

  @override
  String get homeShowQr => '상대방에게 QR을 보여주세요';

  @override
  String get homeQrDesc => 'QR을 스캔하면 바로 익명 채팅이 시작돼요 💨';

  @override
  String get homeQrAnonymous => '🔐 완전 익명 · 대화 저장 X';

  @override
  String get homeQrLinkCopied => 'QR 링크가 복사되었어요';

  @override
  String get homeQrCopyLink => 'QR 링크 복사';

  @override
  String get homeQrNotEggplant => 'Eggplant QR이 아니에요';

  @override
  String get homeQrInvalid => '잘못된 QR 형식이에요';

  @override
  String get homeQrOwn => '내 QR은 스캔할 수 없어요';

  @override
  String get homeQrChatFailed => '채팅방을 열지 못했어요';

  @override
  String get homeQrScanGuide => 'Eggplant QR을 프레임 안에 맞춰주세요';

  @override
  String get homeQrScanDesc => '스캔 즉시 익명 채팅이 시작돼요';

  @override
  String get homeAnonymous => '익명';

  @override
  String homePageNotFound(String error) {
    return '페이지를 찾을 수 없어요: $error';
  }

  @override
  String get homeFilterAvailable => '거래 가능만';

  @override
  String get homeFilterPrice => '가격';

  @override
  String get homeSortRecent => '최신순';

  @override
  String get homeSortPriceAsc => '낮은 가격순';

  @override
  String get homeSortPriceDesc => '높은 가격순';

  @override
  String get homeSortTitle => '정렬';

  @override
  String get homePriceTitle => '가격 범위';

  @override
  String get homePriceMin => '최소';

  @override
  String get homePriceMax => '최대';

  @override
  String get homePriceReset => '초기화';

  @override
  String get homePriceApply => '적용하기';

  @override
  String get homePriceInvalid => '최소 가격이 최대 가격보다 커요';

  @override
  String get homeFilterNoResult => '조건에 맞는 상품이 없어요';

  @override
  String get homeFilterClear => '필터 지우기';

  @override
  String get homeAllMyRegions => '내 동네 전체';

  @override
  String homeAllMyRegionsCount(int count) {
    return '내 동네 $count곳';
  }

  @override
  String get homeFilterFree => '나눔';

  @override
  String get homePopularSearches => '인기 검색어';

  @override
  String get inboxTitle => '알림';

  @override
  String get inboxEmpty => '아직 알림이 없어요';

  @override
  String get inboxEmptyHint =>
      '찜한 상품 가격 내림, 거래 확인, 거래 후기, 키워드 알림이 여기에 모여요. 30일 동안 보관돼요.';

  @override
  String get inboxLoadFailed => '알림을 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요.';

  @override
  String get inboxClearConfirm => '알림을 모두 지울까요?';

  @override
  String get recentTitle => '최근 본 상품';

  @override
  String get recentEmpty => '최근 본 상품이 없어요';

  @override
  String get myTabTitle => '나의 Eggplant';

  @override
  String myMannerTemp(String temp) {
    return '매너온도 $temp°C';
  }

  @override
  String get myRegionUnset => '동네 미설정';

  @override
  String get myMenuSelling => '내가 판매중인 상품';

  @override
  String get myMenuLikes => '찜한 상품';

  @override
  String get myMenuChat => '채팅';

  @override
  String get myMenuProfile => '프로필 등록 / 닉네임 수정';

  @override
  String get myMenuProfileSub => '채팅·통화에 표시될 내 닉네임 설정';

  @override
  String get myMenuRegion => '내 동네 설정';

  @override
  String get myRegionNeeded => '설정 필요';

  @override
  String get myMenuQr => '내 QR 코드';

  @override
  String get myMenuQrSub => '친구에게 보여주고 대화 시작';

  @override
  String get myMenuInvite => '친구 초대 (+200 QTA)';

  @override
  String get myMenuInviteSub => '친구가 가입할 때 내 닉네임을 입력하면 +200 QTA · 무제한';

  @override
  String get myMenuKeyword => '키워드 알림';

  @override
  String get myMenuKeywordSub => '관심 키워드 등록하고 새 매물 알림 받기';

  @override
  String get myMenuHidden => '숨긴 게시물';

  @override
  String get myMenuHiddenSub => '내가 가린 게시물 다시 보기';

  @override
  String get myMenuPrivacy => '개인정보 보호';

  @override
  String get myMenuPrivacySub => '채팅·통화 절대 저장 안 함 · 한 번 흘러간 메시지는 영구 소실';

  @override
  String get myPrivacyDialogTitle => '개인정보 보호';

  @override
  String get myMenuAppInfo => '앱 정보';

  @override
  String get myAppLegalese => '© 2026 Eggplant Team\n익명으로 안전한 중고거래';

  @override
  String get myMenuLogout => '로그아웃';

  @override
  String get myMenuDeleteAccount => '계정 영구 삭제 (탈퇴)';

  @override
  String get myMenuDeleteAccountSub =>
      '한 번 사라지면 복구되지 않아요 · 잔여 QTA·추천 보너스 즉시 회수';

  @override
  String get myStatSelling => '판매중';

  @override
  String get myStatLikes => '찜';

  @override
  String get myWalletCopied => '지갑주소를 복사했어요. 닉네임·비밀번호 찾기에 붙여넣을 수 있어요.';

  @override
  String get myQtaBalance => 'QTA 잔액';

  @override
  String get myHistory => '내역';

  @override
  String get myHide => '가리기';

  @override
  String get myShowAll => '전체 보기';

  @override
  String get myCopy => '복사';

  @override
  String get myWithdrawRequestBtn => '지갑으로 출금 신청';

  @override
  String get myWithdrawNeedMin => '출금하려면 5,000 QTA 이상 필요해요';

  @override
  String get myWalletCardNote =>
      '닉네임·비밀번호 분실 시 이 지갑주소로 복구할 수 있어요.\n5,000 QTA 부터 5,000 단위로 본인 지갑으로 출금할 수 있어요.';

  @override
  String get myMaskOnSnack => '알림 본문이 가려져요. 잠금화면에서 안전하게 사용하세요 🔒';

  @override
  String get myMaskOffSnack => '알림 본문이 표시돼요';

  @override
  String get myMaskTitle => '알림 본문 가리기';

  @override
  String get myMaskSub => '잠금화면/푸시 미리보기에 메시지 내용 대신 \"새 메시지가 있어요\" 표시';

  @override
  String get myUnverified => '미인증';

  @override
  String get myCtaPhoneOpenTitle => '2단계 휴대폰 인증하고 1,000 QTA 받기';

  @override
  String get myCtaPhoneSoonTitle => '2단계 휴대폰 인증 · 곧 열려요';

  @override
  String get myCtaWalletTitle => '1단계 지갑 인증부터 시작하기';

  @override
  String get myCtaPhoneOpenDesc => '마지막 단계예요! 인증해도 채팅·통화는 익명 그대로예요.';

  @override
  String get myCtaPhoneSoonDesc => '1단계 완료! 휴대폰 인증이 열리면 마치고 1,000 QTA 를 받으세요.';

  @override
  String get myCtaWalletDesc => '지갑·휴대폰 인증을 모두 마치면 1,000 QTA 를 드려요.';

  @override
  String get myBrowseCreditedTitle => '오늘 채굴 보너스 받았어요!';

  @override
  String get myBrowseTitle => '오늘 둘러보기 채굴';

  @override
  String get myBrowseCreditedSub => '내일 자정(KST)에 다시 시작돼요.';

  @override
  String myBrowseSub(int threshold) {
    return '상품 $threshold개 보면 +10 QTA 적립';
  }

  @override
  String get myBrowseStart => '홈 탭에서 상품을 둘러보세요 🛍️';

  @override
  String myBrowseRemaining(int count) {
    return '$count개 더 보면 +10 QTA!';
  }

  @override
  String get myBrowseSoon => '곧 적립돼요…';

  @override
  String get myBrowseLink => '채굴 내역 보기 · 상품 등록하면 가격의 10% 채굴';

  @override
  String get myUserNotFound => '사용자를 찾을 수 없어요';

  @override
  String get myServerSlow => '서버 응답이 늦어요. 잠시 후 다시 시도해주세요 🕐';

  @override
  String get myLoadError => '불러오는 중 오류가 발생했어요';

  @override
  String get myMoreReviewsSlow => '추가 리뷰 로딩이 늦어요. 잠시 후 다시 시도해주세요 🕐';

  @override
  String get myThisUser => '이 사용자';

  @override
  String get myBlockConfirmTitle => '차단할까요?';

  @override
  String myBlockConfirmBody(String nick) {
    return '$nick님을 차단하면 서로의 게시글과 채팅이 모두 안 보이게 돼요. 언제든 해제할 수 있어요.';
  }

  @override
  String get myBlock => '차단';

  @override
  String myBlockedSnack(String nick) {
    return '$nick님을 차단했어요';
  }

  @override
  String get myUnblockConfirmTitle => '차단 해제할까요?';

  @override
  String myUnblockConfirmBody(String nick) {
    return '$nick님을 다시 볼 수 있게 돼요.';
  }

  @override
  String get myUnblockShort => '해제';

  @override
  String get myUnblockedSnack => '차단을 해제했어요';

  @override
  String get myReportSpam => '스팸·광고';

  @override
  String get myReportFraud => '사기 의심';

  @override
  String get myReportAbuse => '욕설·비방';

  @override
  String get myReportInappropriate => '부적절한 내용';

  @override
  String get myReportFake => '허위 매물';

  @override
  String get myReportOther => '기타';

  @override
  String get myReportTitle => '신고 사유를 골라주세요';

  @override
  String get myReportDesc => '여러 명이 같은 사유로 신고하면 운영팀이 검토해요.';

  @override
  String get myReportDetailHint => '추가 설명 (선택)';

  @override
  String get myReportDone => '신고를 접수했어요';

  @override
  String get myReportSubmit => '신고하기';

  @override
  String get myProfileMine => '내 프로필';

  @override
  String get myProfileSeller => '판매자 정보';

  @override
  String get myUnblockMenu => '차단 해제';

  @override
  String get myBlockMenu => '차단하기';

  @override
  String get myTopPraise => '많이 받은 매너 칭찬';

  @override
  String get myReceivedReviews => '받은 거래 후기';

  @override
  String get myNoReviews => '아직 받은 후기가 없어요';

  @override
  String get myAnonNickname => '익명가지';

  @override
  String get myMannerLabel => '매너온도';

  @override
  String get myReviewsLabel => '받은 후기';

  @override
  String get myRatingGood => '좋아요';

  @override
  String get myRatingSoso => '보통이에요';

  @override
  String get myRatingBad => '별로예요';

  @override
  String myAgoMinutes(int n) {
    return '$n분 전';
  }

  @override
  String myAgoHours(int n) {
    return '$n시간 전';
  }

  @override
  String myAgoDays(int n) {
    return '$n일 전';
  }

  @override
  String myAgoWeeks(int n) {
    return '$n주 전';
  }

  @override
  String myAgoMonths(int n) {
    return '$n개월 전';
  }

  @override
  String get myPhotoLoadFail => '사진을 불러올 수 없어요. 권한을 확인하고 다시 시도해주세요';

  @override
  String get myNicknameEmpty => '닉네임을 입력해주세요';

  @override
  String get myNicknameTooShort => '닉네임은 2자 이상이어야 해요';

  @override
  String get myNicknameTooLong => '닉네임은 12자 이하여야 해요';

  @override
  String get myProfileSaved => '프로필이 저장됐어요. 채팅·통화에 바로 반영돼요 ✨';

  @override
  String get myProfilePhotoSaved => '프로필 사진이 저장됐어요 ✨';

  @override
  String get myProfileEditTitle => '프로필 등록';

  @override
  String get myPhotoChange => '사진 변경';

  @override
  String get myPhotoAdd => '사진 등록';

  @override
  String get myPhotoReset => '기본 가지로 변경';

  @override
  String get myNicknameIntro => '채팅·통화에 표시될 내 닉네임을 설정하세요';

  @override
  String get myNicknameLabel => '닉네임';

  @override
  String get myNicknameHint => '2~12자, 한글/영문/숫자';

  @override
  String get myNicknameGuideTitle => '닉네임 안내';

  @override
  String get myNicknameGuideBody =>
      '• 변경 즉시 채팅·통화에 반영돼요\n• 다른 사용자와 중복될 수 없어요\n• 본인인증과 무관하게 닉네임만 사용해요';

  @override
  String get mySaveButton => '저장하기';

  @override
  String get myWdNeedWalletTitle => '1단계 지갑 인증이 필요해요';

  @override
  String get myWdNeedWalletBody =>
      '출금한 QTA 는 인증한 지갑으로 송금돼요.\n본사 지갑이 보낸 수량을 입력해 지갑 주인임을 확인해주세요.';

  @override
  String get myWdNeedPhoneTitle => '2단계 휴대폰 인증이 필요해요';

  @override
  String get myWdPreparingTitle => '출금은 준비 중이에요';

  @override
  String get myWdNeedPhoneBody =>
      '1인 1계정 보장을 위해 출금 전에 휴대폰 인증이 필요해요.\n마치면 1,000 QTA 도 드려요.';

  @override
  String get myWdPreparingBody =>
      '출금에는 휴대폰 인증이 필요한데, 준비하고 있어요.\n열리면 앱 업데이트로 알려드릴게요. 그동안 QTA 는 그대로 쌓여요.';

  @override
  String get myWdNoWallet => '지갑 주소가 등록되지 않았어요';

  @override
  String myWdInsufficientMin(String min) {
    return '잔액이 부족해요. 최소 $min QTA 부터 신청할 수 있어요.';
  }

  @override
  String get myWdConfirmTitle => '출금 신청';

  @override
  String myWdConfirmBody(String amount, String wallet) {
    return '$amount QTA 를\n$wallet\n로 출금 신청할까요?\n\n신청 즉시 잔액에서 차감되며, 운영자가 1~3일 내에 송금 처리합니다.';
  }

  @override
  String get myWdApply => '신청';

  @override
  String get myWdRequested => '출금 신청 완료 — 처리되면 알려드릴게요';

  @override
  String get myWdCancelTitle => '신청 취소';

  @override
  String myWdCancelBody(String amount) {
    return '$amount QTA 출금 신청을 취소할까요?\n취소 즉시 잔액으로 환불돼요.';
  }

  @override
  String get myWdNo => '아니요';

  @override
  String get myWdCancelDo => '취소하기';

  @override
  String get myWdCancelled => '취소 및 환불 완료';

  @override
  String get myDateTimeFormat => 'M월 d일 HH:mm';

  @override
  String get myWdTitle => 'QTA 출금';

  @override
  String get myWdAvailable => '출금 가능 잔액';

  @override
  String get myWdRuleShort => '5,000 QTA 부터 5,000 단위로 신청';

  @override
  String myWdPendingStatus(String amount, String status) {
    return '$amount QTA 출금이 $status 이에요';
  }

  @override
  String get myWdRequestBtn => '출금 신청하기';

  @override
  String get myWdInsufficient => '잔액이 부족해요';

  @override
  String get myWdHistory => '신청 내역';

  @override
  String get myWdHistoryEmpty => '아직 출금 신청 내역이 없어요';

  @override
  String get myWdNotice =>
      '출금은 가입 시 등록된 퀀타리움 지갑주소로만 송금돼요. 운영자가 1~3일 안에 처리합니다. 처리 시작 후엔 취소할 수 없어요.';

  @override
  String get myWdTxCopied => '트랜잭션 해시를 복사했어요';

  @override
  String myWdReason(String reason) {
    return '사유: $reason';
  }

  @override
  String get myWdAmountTitle => '출금 금액 입력';

  @override
  String myWdAmountRule(String min, String unit) {
    return '$min QTA 부터 $unit QTA 단위로 신청 가능';
  }

  @override
  String myWdMinBtn(String amount) {
    return '최소 $amount';
  }

  @override
  String myWdMaxBtn(String amount) {
    return '전액 $amount';
  }

  @override
  String get myWdToWallet => '받는 지갑';

  @override
  String myWdSubmitAmount(String amount) {
    return '$amount QTA 신청하기';
  }

  @override
  String get myLedgerTitle => 'QTA 내역';

  @override
  String get myLedgerWithdraw => '출금';

  @override
  String get myLedgerBalance => '현재 잔액';

  @override
  String get myLedgerRecent => '최근 내역';

  @override
  String get myLedgerEmpty => '아직 내역이 없어요. 출석·거래로 QTA를 적립해보세요!';

  @override
  String get myRuleTitle => 'QTA 적립 규칙';

  @override
  String get myRuleVerify => '지갑·휴대폰 인증 완료 시 +1,000 QTA (1회)';

  @override
  String myRuleListing(int rate) {
    return '상품 등록 시 가격의 10%를 QTA로 채굴 (1 QTA = $rate원) · 삭제하면 차감';
  }

  @override
  String get myRuleLogin => '로그인할 때마다 +10 QTA · 하루 3번까지';

  @override
  String get myRuleTrade => '거래완료 시 판매자·구매자 각각 +10 QTA';

  @override
  String get myRuleWithdraw => '5,000 QTA 부터 5,000 단위로 지갑 출금 가능';

  @override
  String get myMiningLoadFail => '채굴 내역을 불러오지 못했어요. 당겨서 다시 시도해주세요';

  @override
  String get myMiningTitle => '채굴 내역';

  @override
  String get myMiningTotalLabel => '지금까지 채굴한 QTA';

  @override
  String myMiningTotalSub(String listing, String money) {
    return '상품 등록 채굴 $listing QTA · 약 $money';
  }

  @override
  String myMiningRule(int percent, int rate, String examplePrice,
      String exampleQta, String maxPerListing, String maxPerDay) {
    return '⛏️ 상품을 올리면 가격의 $percent%를 QTA로 채굴해요 (1 QTA = $rate원)\n   예) $examplePrice 상품 → +$exampleQta QTA\n• 상품 1개 최대 $maxPerListing QTA · 하루 최대 $maxPerDay QTA\n• 가격을 내리면 차액만큼, 상품을 삭제하면 받은 만큼 차감돼요\n• 판매 완료된 상품은 차감되지 않아요 (삭제하면 차감)';
  }

  @override
  String get myMiningRecords => '채굴 기록';

  @override
  String get myMiningEmpty => '아직 채굴 기록이 없어요. 상품을 올려 QTA를 채굴해보세요!';

  @override
  String get myRefLoadFail => '내 초대 내역을 불러올 수 없어요.';

  @override
  String get myRefNetworkError => '네트워크 오류: 잠시 후 다시 시도해주세요.';

  @override
  String get myRefTitle => '친구 초대';

  @override
  String get myRefHeadline => '친구가 가입할 때\n내 닉네임을 입력하면 +200 QTA';

  @override
  String get myRefCopyNick => '닉네임 복사';

  @override
  String get myRefNickCopied => '닉네임을 복사했어요';

  @override
  String get myRefOncePerPerson =>
      '한 사람당 1번만 처리되지만, 내가 초대할 수 있는 친구 수에는 제한이 없어요.';

  @override
  String get myRefStatValid => '유효한 초대';

  @override
  String get myRefStatEarned => '누적 적립';

  @override
  String get myRefStatClawed => '회수 (탈퇴)';

  @override
  String get myRefRuleTitle => '친구 초대 보너스 규칙';

  @override
  String get myRefRuleBody =>
      '• 친구 1명당 +200 QTA · 무제한\n• 친구가 회원가입 마지막 칸에 내 닉네임 입력\n• 친구가 탈퇴하면 그 200 QTA는 즉시 회수돼요\n• 자기 자신은 추천인이 될 수 없어요';

  @override
  String get myRefListTitle => '내가 초대한 친구';

  @override
  String get myRefEmpty => '아직 초대한 친구가 없어요';

  @override
  String get myRefDeletedFriend => '(탈퇴한 친구)';

  @override
  String get myRefUnknown => '(알 수 없음)';

  @override
  String get myRefClawedBadge => '−200 QTA 회수';

  @override
  String get myReasonSignup => '가입 보너스';

  @override
  String get myReasonVerifyBonus => '인증 완료 보너스';

  @override
  String get myReasonLoginDaily => '출석 보너스';

  @override
  String get myReasonTradeSeller => '판매 완료 보상';

  @override
  String get myReasonTradeBuyer => '구매 완료 보상';

  @override
  String get myReasonWithdrawal => '출금 신청';

  @override
  String get myReasonWithdrawalRefund => '출금 취소·환불';

  @override
  String get myReasonListingReward => '상품 등록 채굴';

  @override
  String get myReasonListingAdjust => '가격 인하 차감';

  @override
  String get myReasonListingClawback => '상품 삭제 차감';

  @override
  String get myReasonMiningListing => '상품 7일 유지 채굴';

  @override
  String get myReasonMiningBrowse => '둘러보기 채굴';

  @override
  String get myWdStatusRequested => '대기 중';

  @override
  String get myWdStatusProcessing => '송금 중';

  @override
  String get myWdStatusCompleted => '완료';

  @override
  String get myWdStatusRejected => '거절·환불';

  @override
  String get myQtaLoadFail => 'QTA 잔액을 불러오지 못했어요';

  @override
  String get myWdLoadFail => '출금 내역을 불러오지 못했어요';

  @override
  String myWdErrMin(String min) {
    return '최소 $min QTA 부터 신청할 수 있어요';
  }

  @override
  String myWdErrUnit(String unit) {
    return '$unit QTA 단위로만 신청할 수 있어요';
  }

  @override
  String get myWdErrBalance => 'QTA 잔액이 부족해요';

  @override
  String get myWdErrPending => '진행 중인 신청이 있어요. 처리되면 다시 시도해주세요.';

  @override
  String get myWdErrRequestFail => '출금 신청에 실패했어요';

  @override
  String get myWdUserCancelled => '사용자 취소';

  @override
  String get myWdErrCancelFail => '취소에 실패했어요';

  @override
  String get myVerifyLabelNone => '미인증';

  @override
  String get myVerifyLabelIdentity => '본인인증 완료';

  @override
  String get myVerifyLabelBank => '출금 인증 완료';

  @override
  String get myMenuLanguage => '언어';

  @override
  String get myRuleVerifyRequired =>
      '채굴한 QTA는 바로 쌓여요 · 거래완료와 출금은 휴대폰 인증 후에 할 수 있어요';

  @override
  String get myPrivacyNoCollect => '수집하지 않아요';

  @override
  String get myPrivacyItemName => '이메일 · 실명';

  @override
  String get myPrivacyItemNameSub => '닉네임과 비밀번호만으로 가입해요';

  @override
  String get myPrivacyItemGps => '정확한 위치';

  @override
  String get myPrivacyItemGpsSub => '동네 인증에 쓴 GPS는 바로 버려요';

  @override
  String get myPrivacyItemChat => '채팅 내용';

  @override
  String get myPrivacyItemChatSub => '서버에 저장하지 않아요';

  @override
  String get myPrivacyItemCall => '통화 내용';

  @override
  String get myPrivacyItemCallSub => '기기끼리 바로 연결돼요 (서버를 거치지 않아요)';

  @override
  String get myPrivacyPhoneTitle => '휴대폰 번호';

  @override
  String get myPrivacyPhoneSub => '휴대폰 인증에만 쓰고 암호화해 보관해요. 탈퇴하면 바로 삭제돼요';

  @override
  String get myPrivacyVolatileTitle => '채팅은 남지 않아요';

  @override
  String get myPrivacyVolatileSub =>
      '지나간 메시지는 복원되지 않아요. 앱을 닫거나 기기를 바꾸면 대화가 비워져요';

  @override
  String get productCategoryAll => '전체';

  @override
  String get productCategoryDigital => '디지털기기';

  @override
  String get productCategoryAppliance => '생활가전';

  @override
  String get productCategoryFurniture => '가구/인테리어';

  @override
  String get productCategoryClothing => '의류';

  @override
  String get productCategoryBeauty => '뷰티/미용';

  @override
  String get productCategoryBook => '도서/티켓';

  @override
  String get productCategorySports => '스포츠/레저';

  @override
  String get productCategoryHobby => '취미/게임';

  @override
  String get productCategoryKids => '유아동';

  @override
  String get productCategoryPet => '반려동물';

  @override
  String get productCategoryFood => '식품';

  @override
  String get productCategoryEtc => '기타';

  @override
  String get productAnonymousSeller => '익명가지';

  @override
  String get productTimeJustNow => '방금 전';

  @override
  String productTimeMinutesAgo(int n) {
    return '$n분 전';
  }

  @override
  String productTimeHoursAgo(int n) {
    return '$n시간 전';
  }

  @override
  String productTimeDaysAgo(int n) {
    return '$n일 전';
  }

  @override
  String productTimeMonthsAgo(int n) {
    return '$n개월 전';
  }

  @override
  String productTimeYearsAgo(int n) {
    return '$n년 전';
  }

  @override
  String get productStatusSale => '판매중';

  @override
  String get productStatusReserved => '예약중';

  @override
  String get productStatusSold => '거래완료';

  @override
  String get productReviewGood => '좋아요';

  @override
  String get productReviewBad => '별로예요';

  @override
  String get productReviewSoso => '보통이에요';

  @override
  String get productStatusSoldOut => '판매완료';

  @override
  String get productDetailLoadFailed => '상품 정보를 불러오지 못했습니다.';

  @override
  String get productDetailTimeout => '서버 응답이 늦어요. 잠시 후 다시 시도해주세요.';

  @override
  String get productQtaConfirmUnavailableTitle => '휴대폰 인증 준비 중이에요';

  @override
  String get productQtaConfirmUnavailableBody =>
      '거래완료는 휴대폰 인증을 마친 뒤에 할 수 있어요.\n휴대폰 인증이 열리면 바로 완료할 수 있게 안내해 드릴게요.';

  @override
  String get productConfirmVerifyTitle => '거래완료 전에 휴대폰 인증이 필요해요';

  @override
  String get productConfirmVerifyBody =>
      '모든 거래는 휴대폰 인증을 마쳐야 최종 완료돼요 (1인 1계정 보장).\n그동안 채굴한 QTA는 그대로 쌓여 있어요. 인증해도 채팅·통화는 익명 그대로예요.';

  @override
  String get productConfirmDialogTitle => '거래를 확인할까요?';

  @override
  String productConfirmDialogBodyQta(String qta) {
    return '확인하면 $qta 가 판매자에게 결제돼요.\n물건을 받은 뒤에 확인해주세요.';
  }

  @override
  String get productConfirmDialogBody =>
      '물건을 받은 뒤에 확인해주세요.\n확인하면 거래가 완료되고 후기를 남길 수 있어요.';

  @override
  String get productConfirmDeal => '거래 확인';

  @override
  String get productConfirmDone => '거래를 확인했어요 🍆';

  @override
  String get productBuyerAssignedTitle => '판매자가 회원님을 구매자로 지정했어요';

  @override
  String productBuyerAssignedBodyQta(String qta) {
    return '거래를 확인하면 $qta 가 결제돼요.';
  }

  @override
  String get productBuyerAssignedBody => '물건을 받으셨다면 거래를 확인해주세요.';

  @override
  String get productConfirmDealButton => '거래 확인하기';

  @override
  String get productSoldVerifyTitle => '거래완료 전에 휴대폰 인증이 필요해요';

  @override
  String get productSoldVerifyBody =>
      '모든 거래는 휴대폰 인증을 마쳐야 거래완료로 바꿀 수 있어요 (1인 1계정 보장).\n그동안 채굴한 QTA는 그대로 쌓여 있어요. 인증해도 채팅·통화는 익명 그대로예요.';

  @override
  String get productStatusChangedSold =>
      '거래완료로 변경했어요. 구매자가 거래를 확인하면 결제·보너스가 지급돼요';

  @override
  String productStatusChanged(String status) {
    return '상태를 $status(으)로 변경했어요';
  }

  @override
  String get productBuyer => '구매자';

  @override
  String productReviewQuestion(String nickname) {
    return '$nickname 님과의 거래는 어떠셨나요?';
  }

  @override
  String get productReviewHint => '거래 후기를 남겨주세요 (선택)';

  @override
  String get productReviewThanks => '후기 등록 감사합니다 🙏';

  @override
  String get productReviewSubmit => '후기 등록';

  @override
  String get productChatOpenFailed => '채팅방을 열 수 없어요';

  @override
  String get productChatStartFailed => '채팅을 시작하지 못했어요. 잠시 후 다시 시도해주세요';

  @override
  String get productEscrowNavigating => '안전결제 화면으로 이동합니다';

  @override
  String get productChangeToSale => '판매중으로 변경';

  @override
  String get productChangeToReserved => '예약중으로 변경';

  @override
  String get productChangeToSold => '거래완료로 변경';

  @override
  String get productEdit => '수정';

  @override
  String get productDeleteTitle => '상품을 삭제할까요?';

  @override
  String get productDeleteBody =>
      '• 상품과 사진/영상이 영구 삭제돼요\n• 이 상품으로 받은 등록 채굴 QTA가 차감돼요\n• 복구할 수 없어요';

  @override
  String productDeletedWithClawback(int qta) {
    return '상품을 삭제했어요 · 등록 채굴 -$qta QTA';
  }

  @override
  String get productDeleted => '상품을 삭제했어요';

  @override
  String get productHide => '숨기기';

  @override
  String get productReport => '신고';

  @override
  String get productReportReceived => '신고가 접수되었습니다';

  @override
  String get productDetailTitle => '상품상세';

  @override
  String get productOwnerMenuTooltip => '상태 변경 / 삭제';

  @override
  String get productMore => '더보기';

  @override
  String get productDetailEmpty => '상품 정보가 없습니다.';

  @override
  String get productNoTitle => '제목 없음';

  @override
  String get productNoSellerInfo => '판매자 정보 없음';

  @override
  String get productDescriptionTitle => '상품 설명';

  @override
  String get productNoDescription => '설명 없음';

  @override
  String get productManage => '관리';

  @override
  String get productChatButton => '채팅하기';

  @override
  String productMannerTemp(String temp) {
    return '매너온도 $temp';
  }

  @override
  String get productPickBuyerTitle => '거래한 구매자를 선택해주세요';

  @override
  String get productPickBuyerHint => '선택한 구매자가 앱에서 \"거래 확인\"을 눌러야 거래가 완료돼요.';

  @override
  String get productPickBuyerSearchHint => '구매자 닉네임 검색';

  @override
  String get productPickBuyerChatPartners => '이 상품으로 대화한 사람';

  @override
  String get productPickBuyerNoResults => '검색 결과가 없어요';

  @override
  String get productPickBuyerEmpty => '구매자의 닉네임을 검색해주세요';

  @override
  String get productVideoLoadFailed => '영상을 불러올 수 없어요';

  @override
  String productMaxImages(int max) {
    return '최대 $max장까지 등록 가능해요';
  }

  @override
  String get productAddPhoto => '사진 추가';

  @override
  String get productPhotoPickFailed => '사진을 가져오지 못했어요. 권한을 확인하고 다시 시도해주세요';

  @override
  String get productAddVideo => '영상 추가';

  @override
  String get productVideoPickFailed => '영상을 가져오지 못했어요. 권한을 확인하고 다시 시도해주세요';

  @override
  String get productVideoTooLarge => '영상 크기는 50MB 이하여야 해요';

  @override
  String get productYoutubeAddTitle => '유튜브 링크 추가';

  @override
  String get productYoutubeAddBody =>
      '유튜브 영상 URL을 붙여넣어 주세요.\n예: https://youtu.be/xxxxxxxxxxx';

  @override
  String get productYoutubeInvalid => '유튜브 링크 형식이 올바르지 않아요';

  @override
  String get productSetRegionFirst => '먼저 동네를 설정해주세요';

  @override
  String get productUploadTimeout =>
      '업로드가 너무 오래 걸려요. 사진/영상 크기를 줄이거나 Wi-Fi에서 다시 시도해주세요.';

  @override
  String get productCreateUnexpectedError => '등록 중 문제가 생겼어요. 잠시 후 다시 시도해주세요';

  @override
  String productCreatedWithReward(int qta) {
    return '상품이 등록되었어요 🍆  등록 채굴 +$qta QTA';
  }

  @override
  String get productCreated => '상품이 등록되었어요 🍆';

  @override
  String get productCreateTitle => '중고거래 글쓰기';

  @override
  String get productDone => '완료';

  @override
  String get productFieldTitle => '제목';

  @override
  String get productFieldTitleHint => '상품명을 입력해주세요';

  @override
  String get productFieldTitleRequired => '제목을 입력해주세요';

  @override
  String get productFieldCategory => '카테고리';

  @override
  String get productFieldPrice => '가격';

  @override
  String get productFieldPriceHintKrw => '0 (나눔하려면 0원)';

  @override
  String get productFieldPriceHintJpy => '0 (나눔하려면 0엔)';

  @override
  String get productFieldPriceRequired => '가격을 입력해주세요';

  @override
  String get productFieldQtaPrice => 'QTA 결제 (선택)';

  @override
  String get productFieldQtaPriceHint => '0 = 사용 안 함 / 구매자 거래 확인 시 차감';

  @override
  String get productFieldQtaPriceHelper =>
      '예) 5,000 → 구매자가 거래를 확인하면 구매자 잔액에서 5,000 QTA 가 이체돼요';

  @override
  String get productFieldDescription => '자세한 설명';

  @override
  String get productFieldDescriptionHint =>
      '게시글 등록 전에 체크해주세요.\n- 판매금지물품인지 확인\n- 카테고리가 적절한지 확인\n\n상품의 상태, 사용기간 등을 자세히 적어주세요.';

  @override
  String get productFieldDescriptionMin => '10자 이상 입력해주세요';

  @override
  String get productProhibitedGuide => '거래 금지 품목 안내';

  @override
  String get productPhotos => '사진';

  @override
  String get productVideo => '영상';

  @override
  String get productOptional => '(선택)';

  @override
  String get productRemove => '제거';

  @override
  String get productPickCamera => '카메라로 촬영';

  @override
  String get productPickGallery => '갤러리에서 선택';

  @override
  String get productPickYoutube => '유튜브 링크 붙여넣기';

  @override
  String get productCoverPhoto => '대표';

  @override
  String get productYoutubeVideo => '유튜브 영상';

  @override
  String get productNotFound => '상품을 찾을 수 없어요';

  @override
  String get productNoChanges => '변경된 내용이 없어요';

  @override
  String get productUpdated => '상품을 수정했어요 ✨';

  @override
  String get productEditTitle => '상품 수정';

  @override
  String get productFieldTitleTooLong => '제목이 너무 길어요';

  @override
  String get productFieldRegion => '동네';

  @override
  String get productSetRegion => '동네를 설정해주세요';

  @override
  String get productChange => '변경';

  @override
  String get productFieldDescriptionEditHint => '상품의 상태, 사용기간 등을 자세히 적어주세요.';

  @override
  String get productUploadedVideoLocked =>
      '업로드한 영상은 수정할 수 없어요.\n변경하려면 상품을 삭제 후 다시 등록해주세요.';

  @override
  String get productYoutubeLinkOptional => '유튜브 링크 (선택)';

  @override
  String productEditingBanner(String title) {
    return '수정 중: $title';
  }

  @override
  String productWaitHoursMinutes(int h, int m) {
    return '$h시간 $m분';
  }

  @override
  String productWaitMinutes(int m) {
    return '$m분';
  }

  @override
  String productBumpWait(String wait) {
    return '$wait 후에 다시 끌어올릴 수 있어요';
  }

  @override
  String get productBumped => '🍆 끌어올렸어요! 피드 맨 위로 올라갔어요';

  @override
  String get productDeleteDialogTitle => '상품 삭제';

  @override
  String productDeleteConfirmNamed(String title) {
    return '$title을(를) 정말 삭제할까요?';
  }

  @override
  String get productStatusChangedGeneric => '상태를 변경했어요';

  @override
  String get productMySelling => '내 판매상품';

  @override
  String productMySellingCount(int count) {
    return '내 판매상품 $count';
  }

  @override
  String get productNewPost => '새 글쓰기';

  @override
  String get productMySellingEmpty => '등록한 상품이 없어요';

  @override
  String get productMySellingEmptyHint => '우측 하단 \"새 글쓰기\"로 올려보세요';

  @override
  String get productMyMenuTooltip => '끌어올리기 / 상태 변경 / 삭제';

  @override
  String get productBump => '끌어올리기';

  @override
  String get productBumpWaiting => '끌어올리기 (대기중)';

  @override
  String get productChangeStatus => '상태 변경';

  @override
  String get productBanMedicine => '의약품·의료기기';

  @override
  String get productBanMedicineEx =>
      '전문/일반의약품, 다이어트약, 발기부전치료제, 콘택트렌즈, 보청기, 주사기';

  @override
  String get productBanDrugs => '마약류·향정신성의약품';

  @override
  String get productBanDrugsEx => '대마, 필로폰, 졸피뎀, 프로포폴, 환각버섯 등';

  @override
  String get productBanAlcohol => '주류';

  @override
  String get productBanAlcoholEx => '소주·맥주·와인·위스키·전통주 (빈 병·잔은 가능)';

  @override
  String get productBanTobacco => '담배·전자담배';

  @override
  String get productBanTobaccoEx => '담배, 전자담배 기기·액상, 니코틴 제품';

  @override
  String get productBanWeapons => '총포·도검·화약류·무기';

  @override
  String get productBanWeaponsEx => '총기, 실탄, 석궁, 전기충격기, 가스분사기, 도검';

  @override
  String get productBanAdult => '성인용품·음란물';

  @override
  String get productBanAdultEx => '성인용품, 음란물, 착용 속옷, 조건만남';

  @override
  String get productBanAccounts => '계정·개인정보·명의';

  @override
  String get productBanAccountsEx => '게임/SNS 계정, 통장, 유심·대포폰, 신분증, 공인인증서';

  @override
  String get productBanCashing => '현금화·대출·가상화폐';

  @override
  String get productBanCashingEx => '상품권깡, 소액결제 현금화, 작업대출, 비트코인 등 코인 매매';

  @override
  String get productBanAnimals => '반려동물·야생동물';

  @override
  String get productBanAnimalsEx => '반려동물 분양·판매 (무료분양·책임비 포함), 멸종위기종, 웅담';

  @override
  String get productBanCounterfeit => '위조품';

  @override
  String get productBanCounterfeitEx => '짝퉁, 레플리카, 미러급, ST급';

  @override
  String get productBanStolen => '도난품·불법개조·불법복제';

  @override
  String get productBanStolenEx => '장물, 불법 개조품, 해적판, 크랙';

  @override
  String get productBanBodily => '헌혈증·처방전·인체유래물';

  @override
  String get productBanBodilyEx => '헌혈증, 처방전, 장기·난자·모유';

  @override
  String get productBanMilitary => '군용품·경찰 제복';

  @override
  String get productBanMilitaryEx => '군복, 방탄복, 경찰 제복·배지, 수갑';

  @override
  String get productBanSpycam => '불법 촬영·도청 장비';

  @override
  String get productBanSpycamEx => '몰래카메라, 위장형 카메라, 도청기';

  @override
  String get productBanHacking => '해킹·불법 프로그램';

  @override
  String get productBanHackingEx => '해킹툴, 게임핵, 불법 매크로';

  @override
  String get productBanScalping => '암표·대리 서비스';

  @override
  String get productBanScalpingEx => '웃돈 티켓 리셀, 티켓팅 대행, 대리시험';

  @override
  String get productBanWasteBags => '종량제 봉투';

  @override
  String get productBanWasteBagsEx => '쓰레기 종량제 봉투, 폐기물 스티커';

  @override
  String get productBanFireworks => '폭죽·불꽃놀이';

  @override
  String get productBanFireworksEx => '폭죽, 불꽃놀이 화약류, 사제 폭발물';

  @override
  String get productBanIntro =>
      '법으로 거래가 금지되었거나 안전을 해칠 수 있는 물품은 가지에서 판매할 수 없어요. 아래 품목이 포함된 게시글은 등록되지 않으며, 운영정책 위반 시 이용이 제한될 수 있어요.';

  @override
  String get productBanInfoTitle => '게시글에 적을 수 없는 정보';

  @override
  String get productBanInfoBody =>
      '• 전화번호, 계좌번호, 이메일\n• 카카오톡 ID, 오픈채팅·텔레그램 링크 등 외부 메신저\n• 욕설·비속어·혐오 표현\n\n거래 대화는 가지 채팅으로 해주세요. 외부 메신저·선입금 유도는 사기 위험이 커요.';

  @override
  String get productPolicyRejectedTitle => '등록할 수 없는 게시글이에요';

  @override
  String get productViewProhibited => '금지 품목 보기';

  @override
  String get productHiddenTimeout => '서버 응답이 늦어요. 잠시 후 다시 시도해주세요 🕐';

  @override
  String get productHiddenLoadFailed => '숨긴 게시물을 불러오지 못했어요';

  @override
  String productUnhidden(String title) {
    return '\"$title\" 다시 보여요';
  }

  @override
  String get productUnhideFailed => '숨김 해제 실패';

  @override
  String get productHiddenTitle => '숨긴 게시물';

  @override
  String get productUnhide => '숨김 해제';

  @override
  String get productHiddenEmpty => '숨긴 게시물이 없어요';

  @override
  String get productHiddenEmptyHint => '게시물 우측 상단의 ⋯ 메뉴에서 가릴 수 있어요';

  @override
  String get productKeywordDeleteTitle => '키워드 삭제';

  @override
  String productKeywordDeleteBody(String keyword) {
    return '\"$keyword\" 알림을 끌까요?';
  }

  @override
  String get productKeywordAlertsTitle => '키워드 알림';

  @override
  String productKeywordAlertsIntro(int max) {
    return '관심 키워드를 등록하면 동네에 새 매물이 올라올 때 알림을 보내드려요. (최대 $max개)';
  }

  @override
  String get productKeywordFull => '키워드 슬롯이 모두 찼어요';

  @override
  String get productKeywordHint => '예: 닌텐도, 자전거, 캠핑';

  @override
  String get productKeywordAdd => '등록';

  @override
  String get productKeywordEmpty => '등록한 키워드가 없어요';

  @override
  String get productKeywordEmptyHint => '위에서 관심 키워드를 추가해보세요';

  @override
  String get productKeywordTooShort => '키워드는 2자 이상이어야 해요';

  @override
  String get productKeywordTooLong => '키워드는 30자 이하로 입력해주세요';

  @override
  String productKeywordMax(int max) {
    return '키워드는 최대 $max개까지 등록할 수 있어요';
  }

  @override
  String get productKeywordAddFailed => '알림 등록에 실패했어요. 잠시 후 다시 시도해주세요';

  @override
  String get productLoadFailed => '상품을 불러오지 못했어요';

  @override
  String get productCreateFailed => '등록 실패';

  @override
  String get productCreateFailedRetry => '등록에 실패했어요. 잠시 후 다시 시도해주세요';

  @override
  String get productLikesLoadFailed => '찜한 상품을 불러올 수 없어요';

  @override
  String get productNothingToUpdate => '수정할 내용이 없어요';

  @override
  String get productUpdateFailed => '수정 실패';

  @override
  String get productBumpFailed => '끌어올리기 실패';

  @override
  String get productChangeFailed => '변경 실패';

  @override
  String get productDeleteFailed => '삭제 실패';

  @override
  String get productConfirmFailed => '거래 확인 실패';

  @override
  String get productReviewFailed => '후기 등록 실패';

  @override
  String get productNetworkSlow => '응답이 늦어요. 네트워크 상태를 확인하고 다시 시도해주세요';

  @override
  String get productNetworkUnreachable => '서버에 연결할 수 없어요. 네트워크를 확인해주세요';

  @override
  String get productBlockFailed => '차단 실패';

  @override
  String get productUnblockFailed => '차단 해제 실패';

  @override
  String get productReportFailed => '신고 접수 실패';

  @override
  String get productFieldPriceHintPhp => '0 (나눔하려면 0페소)';

  @override
  String get productShare => '공유하기';

  @override
  String get productLinkCopied => '상품 링크를 복사했어요';

  @override
  String productSellerOthers(String name) {
    return '$name님의 판매 상품';
  }

  @override
  String get productSimilar => '이런 상품은 어때요?';

  @override
  String get productSeeAll => '모두 보기';

  @override
  String get productMeetPlaceTitle => '거래 희망 장소';

  @override
  String get productFieldMeetPlace => '거래 희망 장소 (선택)';

  @override
  String get productFieldMeetPlaceHint => '예) 강남역 2번 출구 앞';

  @override
  String get productDraftTitle => '작성 중인 글이 있어요';

  @override
  String get productDraftBody => '이어서 쓸까요?';

  @override
  String get productDraftDiscard => '새로 쓰기';

  @override
  String get productDraftResume => '이어 쓰기';

  @override
  String get regionPrefectureSearchHint => '도도부현·시구정촌 이름으로 검색 (예: 渋谷)';

  @override
  String regionCitySearchHint(String prefecture) {
    return '$prefecture의 시구정촌 검색';
  }

  @override
  String regionCityCount(int count) {
    return '$count곳';
  }

  @override
  String get regionChangePrefecture => '도도부현 다시 선택';

  @override
  String get regionNoResults => '검색 결과가 없어요';

  @override
  String regionAdded(String region, int count, int max) {
    return '$region 추가 ($count/$max)';
  }

  @override
  String regionRemoved(String region, int count, int max) {
    return '$region 뺐어요 ($count/$max)';
  }

  @override
  String regionMultiHint(int max) {
    return '보고 싶은 동네를 최대 $max곳까지 모두 고른 뒤 아래 확인을 누르세요. 다시 누르면 빠져요.';
  }

  @override
  String get regionKeepOne => '동네는 한 곳 이상 있어야 해요';

  @override
  String regionConfirm(int count, int max) {
    return '확인 ($count/$max)';
  }

  @override
  String reviewQuestion(String nickname) {
    return '$nickname님과 거래가 어떠셨나요?';
  }

  @override
  String get reviewQuestionSub => '거래 후기는 서로의 매너온도에 반영돼요';

  @override
  String get reviewRatingBad => '별로예요';

  @override
  String get reviewRatingGood => '좋아요';

  @override
  String get reviewRatingBest => '최고예요';

  @override
  String get reviewRatingSoso => '보통이에요';

  @override
  String get reviewTagsTitleGood => '어떤 점이 좋았나요?';

  @override
  String get reviewTagsTitleBad => '어떤 점이 별로였나요?';

  @override
  String get reviewTagsSub => '해당하는 항목을 모두 골라주세요';

  @override
  String get reviewBadPrivateNotice =>
      '별로예요 평가와 고른 항목은 상대방 프로필에 공개되지 않고 매너온도에만 반영돼요';

  @override
  String get reviewCommentTitle => '따뜻한 거래 후기를 남겨주세요';

  @override
  String get reviewCommentTitleBad => '아쉬웠던 점을 알려주세요';

  @override
  String reviewCommentOptional(String nickname) {
    return '선택 사항이에요. 후기 글은 $nickname님의 프로필에 공개돼요';
  }

  @override
  String get reviewCommentOptionalBad => '선택 사항이에요. 이 내용은 공개되지 않아요';

  @override
  String reviewCommentHint(String nickname) {
    return '$nickname님에게 고마운 마음을 전해보세요';
  }

  @override
  String get reviewCommentHintBad => '어떤 점이 아쉬웠나요?';

  @override
  String get reviewNext => '다음';

  @override
  String get reviewBack => '이전';

  @override
  String get reviewSubmit => '후기 보내기';

  @override
  String get reviewSent => '거래 후기를 보냈어요';

  @override
  String get reviewSendButton => '거래 후기 보내기';

  @override
  String get reviewViewMine => '보낸 후기 보기';

  @override
  String reviewSentTo(String nickname) {
    return '$nickname님에게 보낸 후기';
  }

  @override
  String get reviewPromptBody => '거래 후기를 남기면 서로의 매너온도에 반영돼요';

  @override
  String get reviewPromptDone => '거래 후기를 보냈어요. 따뜻한 거래 감사합니다!';

  @override
  String get reviewRoleBuyer => '구매자';

  @override
  String get reviewRoleSeller => '판매자';

  @override
  String get reviewPraiseTitle => '받은 매너 칭찬';

  @override
  String get reviewPraiseMore => '더보기';

  @override
  String get reviewPraiseLess => '접기';

  @override
  String get reviewNoPraise => '아직 받은 매너 칭찬이 없어요';

  @override
  String get reviewReceivedTitle => '받은 거래 후기';

  @override
  String get reviewNoComments => '아직 받은 거래 후기가 없어요';

  @override
  String get reviewPurchasesTitle => '구매 내역';

  @override
  String get reviewPurchasesEmpty => '구매한 상품이 없어요';

  @override
  String get reviewPurchasesLoadFailed => '구매 내역을 불러오지 못했어요';

  @override
  String get reviewCounterpartFallback => '거래 상대';

  @override
  String get reviewTagKind => '친절하고 매너가 좋아요';

  @override
  String get reviewTagPunctual => '시간 약속을 잘 지켜요';

  @override
  String get reviewTagFastReply => '응답이 빨라요';

  @override
  String get reviewTagAsDescribed => '상품 상태가 설명한 것과 같아요';

  @override
  String get reviewTagDetailedDesc => '상품 설명이 자세해요';

  @override
  String get reviewTagGoodPrice => '좋은 상품을 저렴하게 판매해요';

  @override
  String get reviewTagFreeShare => '무료로 나눠주셨어요';

  @override
  String get reviewTagPaidOnTime => '제시간에 결제·수령했어요';

  @override
  String get reviewTagNoHaggle => '무리하게 가격을 깎지 않아요';

  @override
  String get reviewTagLate => '시간 약속을 안 지켜요';

  @override
  String get reviewTagSlowReply => '응답이 느려요';

  @override
  String get reviewTagRude => '불친절해요';

  @override
  String get reviewTagNotAsDescribed => '상품 상태가 설명과 달라요';

  @override
  String get reviewTagPriceChange => '가격을 갑자기 바꿔요';

  @override
  String get reviewTagNoShow => '약속 장소에 나타나지 않았어요';

  @override
  String get reviewTagHaggle => '무리하게 가격을 깎아요';
}
