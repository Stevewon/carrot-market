import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko')
  ];

  /// No description provided for @authWalletRequired.
  ///
  /// In ko, this message translates to:
  /// **'지갑주소를 입력해주세요'**
  String get authWalletRequired;

  /// No description provided for @authWalletFormat.
  ///
  /// In ko, this message translates to:
  /// **'0x로 시작하는 42자리 형식이어야 해요'**
  String get authWalletFormat;

  /// No description provided for @authNicknameRequired.
  ///
  /// In ko, this message translates to:
  /// **'닉네임을 입력해주세요'**
  String get authNicknameRequired;

  /// No description provided for @authNicknameTooShort.
  ///
  /// In ko, this message translates to:
  /// **'닉네임은 2자 이상이어야 해요'**
  String get authNicknameTooShort;

  /// No description provided for @authNicknameTooLong.
  ///
  /// In ko, this message translates to:
  /// **'닉네임은 12자 이하여야 해요'**
  String get authNicknameTooLong;

  /// No description provided for @authNicknameCharset.
  ///
  /// In ko, this message translates to:
  /// **'한글·일본어·영문·숫자·_ 만 사용 가능해요 (공백·특수문자 금지)'**
  String get authNicknameCharset;

  /// No description provided for @authPasswordRequired.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 입력해주세요'**
  String get authPasswordRequired;

  /// No description provided for @authPasswordTooShort.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 8자 이상이어야 해요'**
  String get authPasswordTooShort;

  /// No description provided for @authPasswordTooLong.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 64자 이하여야 해요'**
  String get authPasswordTooLong;

  /// No description provided for @authPasswordMix.
  ///
  /// In ko, this message translates to:
  /// **'영문과 숫자를 모두 포함해야 해요'**
  String get authPasswordMix;

  /// No description provided for @authPhoneCheckExample.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 번호를 확인해주세요 (예: {example})'**
  String authPhoneCheckExample(String example);

  /// No description provided for @authPhoneCheck.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 번호를 확인해주세요'**
  String get authPhoneCheck;

  /// No description provided for @authTooManyRequests.
  ///
  /// In ko, this message translates to:
  /// **'요청이 너무 많아요. 잠시 후 다시 시도해주세요'**
  String get authTooManyRequests;

  /// No description provided for @authSmsQuotaExceeded.
  ///
  /// In ko, this message translates to:
  /// **'오늘 문자 발송 한도를 넘었어요. 내일 다시 시도해주세요'**
  String get authSmsQuotaExceeded;

  /// No description provided for @authSmsSendFailedCode.
  ///
  /// In ko, this message translates to:
  /// **'문자를 보내지 못했어요. 잠시 후 다시 시도해주세요 ({code})'**
  String authSmsSendFailedCode(String code);

  /// No description provided for @authSmsSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'문자를 보내지 못했어요. 잠시 후 다시 시도해주세요'**
  String get authSmsSendFailed;

  /// No description provided for @authSmsCodeInvalid.
  ///
  /// In ko, this message translates to:
  /// **'문자로 받은 6자리 숫자를 입력해주세요'**
  String get authSmsCodeInvalid;

  /// No description provided for @authPhoneVerifyFailedRetry.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 인증을 마치지 못했어요. 다시 시도해주세요'**
  String get authPhoneVerifyFailedRetry;

  /// No description provided for @authSmsCodeWrong.
  ///
  /// In ko, this message translates to:
  /// **'인증번호가 맞지 않아요'**
  String get authSmsCodeWrong;

  /// No description provided for @authSmsCodeExpired.
  ///
  /// In ko, this message translates to:
  /// **'인증번호가 만료됐어요. 다시 받아주세요'**
  String get authSmsCodeExpired;

  /// No description provided for @authPhoneVerifyFailedCode.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 인증을 마치지 못했어요 ({code})'**
  String authPhoneVerifyFailedCode(String code);

  /// No description provided for @authPhoneVerifyFailedLater.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 인증을 마치지 못했어요. 잠시 후 다시 시도해주세요'**
  String get authPhoneVerifyFailedLater;

  /// No description provided for @authPhoneStepTitle.
  ///
  /// In ko, this message translates to:
  /// **'2단계 · 휴대폰 인증'**
  String get authPhoneStepTitle;

  /// No description provided for @authPhoneStepDesc.
  ///
  /// In ko, this message translates to:
  /// **'문자로 받은 인증번호를 입력하면 끝! 한 번호로 한 계정만 인증할 수 있어요. 번호는 저장하지 않고 확인용 암호값만 남아요.'**
  String get authPhoneStepDesc;

  /// No description provided for @authPhoneNumberLabel.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 번호'**
  String get authPhoneNumberLabel;

  /// No description provided for @authSending.
  ///
  /// In ko, this message translates to:
  /// **'보내는 중…'**
  String get authSending;

  /// No description provided for @authGetCode.
  ///
  /// In ko, this message translates to:
  /// **'인증번호 받기'**
  String get authGetCode;

  /// No description provided for @authCodeLabel.
  ///
  /// In ko, this message translates to:
  /// **'인증번호 6자리'**
  String get authCodeLabel;

  /// No description provided for @authChecking.
  ///
  /// In ko, this message translates to:
  /// **'확인 중…'**
  String get authChecking;

  /// No description provided for @authVerify.
  ///
  /// In ko, this message translates to:
  /// **'인증하기'**
  String get authVerify;

  /// No description provided for @authChangeNumber.
  ///
  /// In ko, this message translates to:
  /// **'번호 바꾸기'**
  String get authChangeNumber;

  /// No description provided for @authResendCode.
  ///
  /// In ko, this message translates to:
  /// **'인증번호 다시 받기'**
  String get authResendCode;

  /// No description provided for @authResponseSlow.
  ///
  /// In ko, this message translates to:
  /// **'응답이 너무 느려요. 네트워크 상태를 확인하고 다시 시도해주세요.'**
  String get authResponseSlow;

  /// No description provided for @authRegisterFailed.
  ///
  /// In ko, this message translates to:
  /// **'가입 중 문제가 생겼어요. 잠시 후 다시 시도해주세요'**
  String get authRegisterFailed;

  /// No description provided for @authReferralCredited.
  ///
  /// In ko, this message translates to:
  /// **'🎉 추천인 {nickname}님께 +200 QTA 지급 완료!'**
  String authReferralCredited(String nickname);

  /// No description provided for @authReferralNotFound.
  ///
  /// In ko, this message translates to:
  /// **'추천인 닉네임을 찾을 수 없어 초대 보너스가 적용되지 않았어요.'**
  String get authReferralNotFound;

  /// No description provided for @authReferralSelf.
  ///
  /// In ko, this message translates to:
  /// **'자기 자신은 추천인으로 입력할 수 없어요.'**
  String get authReferralSelf;

  /// No description provided for @authReferralAlreadyProcessed.
  ///
  /// In ko, this message translates to:
  /// **'이미 처리된 초대예요.'**
  String get authReferralAlreadyProcessed;

  /// No description provided for @authRegisterTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원가입'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterHeadline.
  ///
  /// In ko, this message translates to:
  /// **'닉네임만 정하면\n바로 가입 🍆'**
  String get authRegisterHeadline;

  /// No description provided for @authRegisterDesc.
  ///
  /// In ko, this message translates to:
  /// **'지갑이 없어도 가입할 수 있어요. 가입 후 \'나의 가지 → 프로필 인증\' 에서 1단계 지갑 인증 · 2단계 휴대폰 인증을 마치면 1,000 QTA 를 드려요.'**
  String get authRegisterDesc;

  /// No description provided for @authNicknameLabel.
  ///
  /// In ko, this message translates to:
  /// **'닉네임'**
  String get authNicknameLabel;

  /// No description provided for @authNicknameHint.
  ///
  /// In ko, this message translates to:
  /// **'2~12자, 중복 불가'**
  String get authNicknameHint;

  /// No description provided for @authNicknamePlaceholder.
  ///
  /// In ko, this message translates to:
  /// **'익명가지123'**
  String get authNicknamePlaceholder;

  /// No description provided for @authPasswordLabel.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호'**
  String get authPasswordLabel;

  /// No description provided for @authMin8.
  ///
  /// In ko, this message translates to:
  /// **'8자 이상'**
  String get authMin8;

  /// No description provided for @authPasswordPlaceholder.
  ///
  /// In ko, this message translates to:
  /// **'영문·숫자·특수문자 조합 권장'**
  String get authPasswordPlaceholder;

  /// No description provided for @authPasswordConfirmLabel.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 확인'**
  String get authPasswordConfirmLabel;

  /// No description provided for @authEnterAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 한 번 입력'**
  String get authEnterAgain;

  /// No description provided for @authPasswordConfirmRequired.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 확인을 입력해주세요'**
  String get authPasswordConfirmRequired;

  /// No description provided for @authPasswordMismatch.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 일치하지 않아요'**
  String get authPasswordMismatch;

  /// No description provided for @authReferrerLabel.
  ///
  /// In ko, this message translates to:
  /// **'추천인 닉네임 (선택)'**
  String get authReferrerLabel;

  /// No description provided for @authReferrerHint.
  ///
  /// In ko, this message translates to:
  /// **'친구가 +200 QTA 받아요 · 무제한'**
  String get authReferrerHint;

  /// No description provided for @authReferrerPlaceholder.
  ///
  /// In ko, this message translates to:
  /// **'추천해주신 분의 닉네임'**
  String get authReferrerPlaceholder;

  /// No description provided for @authRegisterBonusInfo.
  ///
  /// In ko, this message translates to:
  /// **'지갑·휴대폰 인증을 마치면 +1,000 QTA 지급! 추천인을 입력하면 추천인에게 +200 QTA가 무제한으로 지급돼요.\n※ 가입 후 탈퇴하면 추천인의 보너스는 즉시 회수돼요.'**
  String get authRegisterBonusInfo;

  /// No description provided for @authWalletImmutableInfo.
  ///
  /// In ko, this message translates to:
  /// **'지갑주소는 변경할 수 없어요. 닉네임/비밀번호 분실 시 같은 지갑으로만 복구할 수 있습니다.'**
  String get authWalletImmutableInfo;

  /// No description provided for @authRegisterButton.
  ///
  /// In ko, this message translates to:
  /// **'가입하기'**
  String get authRegisterButton;

  /// No description provided for @authHaveAccountLogin.
  ///
  /// In ko, this message translates to:
  /// **'이미 계정이 있어요 — 로그인'**
  String get authHaveAccountLogin;

  /// No description provided for @authServerSlow.
  ///
  /// In ko, this message translates to:
  /// **'서버 응답이 늦어요. 잠시 후 다시 시도해주세요 🕐'**
  String get authServerSlow;

  /// No description provided for @authLookupFailed.
  ///
  /// In ko, this message translates to:
  /// **'계정 조회 중 문제가 생겼어요. 다시 시도해주세요.'**
  String get authLookupFailed;

  /// No description provided for @authPasswordResetDone.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 새로 설정했어요 🔒'**
  String get authPasswordResetDone;

  /// No description provided for @authResetFailed.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재설정 중 문제가 생겼어요. 다시 시도해주세요.'**
  String get authResetFailed;

  /// No description provided for @authFindAccountTitle.
  ///
  /// In ko, this message translates to:
  /// **'계정 찾기'**
  String get authFindAccountTitle;

  /// No description provided for @authFindHeadline.
  ///
  /// In ko, this message translates to:
  /// **'지갑주소로\n계정을 찾아요'**
  String get authFindHeadline;

  /// No description provided for @authFindDesc.
  ///
  /// In ko, this message translates to:
  /// **'가입할 때 사용한 퀀타리움 지갑주소를 입력해주세요.\n지갑 소유를 인증하면 닉네임을 확인하고 비밀번호를 다시 설정할 수 있어요.'**
  String get authFindDesc;

  /// No description provided for @authQuantariumWalletLabel.
  ///
  /// In ko, this message translates to:
  /// **'퀀타리움 지갑주소'**
  String get authQuantariumWalletLabel;

  /// No description provided for @authPaste.
  ///
  /// In ko, this message translates to:
  /// **'붙여넣기'**
  String get authPaste;

  /// No description provided for @authCheckAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정 확인'**
  String get authCheckAccount;

  /// No description provided for @authRegisteredNickname.
  ///
  /// In ko, this message translates to:
  /// **'등록된 닉네임'**
  String get authRegisteredNickname;

  /// No description provided for @authNewPasswordTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호 설정'**
  String get authNewPasswordTitle;

  /// No description provided for @authNewPasswordDesc.
  ///
  /// In ko, this message translates to:
  /// **'재설정 후 기존에 로그인된 모든 기기는 자동으로 로그아웃돼요.\n이 계정을 쓰던 기기라면 바로 재설정되고, 다른 기기·앱 재설치 후라면 아래 지갑 인증이 필요해요.'**
  String get authNewPasswordDesc;

  /// No description provided for @authNewPasswordLabel.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호'**
  String get authNewPasswordLabel;

  /// No description provided for @authNewPasswordConfirmLabel.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호 확인'**
  String get authNewPasswordConfirmLabel;

  /// No description provided for @authResetPasswordButton.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재설정'**
  String get authResetPasswordButton;

  /// No description provided for @authFindAgain.
  ///
  /// In ko, this message translates to:
  /// **'다른 지갑주소로 다시 찾기'**
  String get authFindAgain;

  /// No description provided for @authWalletVerifiedInfo.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증 완료 — 본인 지갑임이 확인됐어요'**
  String get authWalletVerifiedInfo;

  /// No description provided for @authVerifyAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 인증하기'**
  String get authVerifyAgain;

  /// No description provided for @authWalletVerifyTitle.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증'**
  String get authWalletVerifyTitle;

  /// No description provided for @authWalletRegisterTitle.
  ///
  /// In ko, this message translates to:
  /// **'지갑 등록'**
  String get authWalletRegisterTitle;

  /// No description provided for @authWalletVerifyResetTitle.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증 (다른 기기에서 재설정 시)'**
  String get authWalletVerifyResetTitle;

  /// No description provided for @authWalletVerifyDescRegister.
  ///
  /// In ko, this message translates to:
  /// **'다른 사람이 내 지갑주소를 쓰지 못하도록, 이 지갑에서 화면에 나오는 아주 적은 수량(0.1 QTA 미만)을 가지 인증 지갑으로 보내 본인 지갑임을 확인해요.'**
  String get authWalletVerifyDescRegister;

  /// No description provided for @authWalletVerifyDescVerify.
  ///
  /// In ko, this message translates to:
  /// **'내 퀀타리움 지갑에서 화면에 나오는 아주 적은 수량(0.1 QTA 미만)을 가지 인증 지갑으로 보내면 지갑 주인임이 확인돼요. 출금한 QTA 는 이 지갑으로 송금돼요.'**
  String get authWalletVerifyDescVerify;

  /// No description provided for @authWalletVerifyDescReset.
  ///
  /// In ko, this message translates to:
  /// **'이 지갑에서 화면에 나오는 아주 적은 수량(0.1 QTA 미만)을 가지 인증 지갑으로 보내 본인 지갑임을 확인해요. 내 지갑으로 누군가 먼저 가입했다면 이 방법으로 계정을 되찾을 수 있어요.'**
  String get authWalletVerifyDescReset;

  /// No description provided for @authMyQuantariumWalletLabel.
  ///
  /// In ko, this message translates to:
  /// **'내 퀀타리움 지갑주소'**
  String get authMyQuantariumWalletLabel;

  /// No description provided for @authWalletHint42.
  ///
  /// In ko, this message translates to:
  /// **'0x + 40자리 (총 42자)'**
  String get authWalletHint42;

  /// No description provided for @authPreparing.
  ///
  /// In ko, this message translates to:
  /// **'준비 중…'**
  String get authPreparing;

  /// No description provided for @authWalletVerifyStart.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증 시작'**
  String get authWalletVerifyStart;

  /// No description provided for @authAmountToSend.
  ///
  /// In ko, this message translates to:
  /// **'보낼 금액'**
  String get authAmountToSend;

  /// No description provided for @authAmountCopied.
  ///
  /// In ko, this message translates to:
  /// **'금액을 복사했어요'**
  String get authAmountCopied;

  /// No description provided for @authRecipientMyWallet.
  ///
  /// In ko, this message translates to:
  /// **'받는 주소 (내 지갑)'**
  String get authRecipientMyWallet;

  /// No description provided for @authRecipientEggplantWallet.
  ///
  /// In ko, this message translates to:
  /// **'받는 주소 (가지 인증 지갑)'**
  String get authRecipientEggplantWallet;

  /// No description provided for @authAddressCopied.
  ///
  /// In ko, this message translates to:
  /// **'주소를 복사했어요'**
  String get authAddressCopied;

  /// No description provided for @authWalletSendInstruction.
  ///
  /// In ko, this message translates to:
  /// **'퀀타리움 지갑 앱에서 {wallet} 지갑으로 위 수량을 정확히 보내고, 블록에 담기면(보통 수십 초) 아래 버튼을 눌러주세요. 30분 안에 보내야 해요.'**
  String authWalletSendInstruction(String wallet);

  /// No description provided for @authSentCheck.
  ///
  /// In ko, this message translates to:
  /// **'송금했어요 — 확인하기'**
  String get authSentCheck;

  /// No description provided for @authNewAmount.
  ///
  /// In ko, this message translates to:
  /// **'새 금액 받기'**
  String get authNewAmount;

  /// No description provided for @authCopy.
  ///
  /// In ko, this message translates to:
  /// **'복사'**
  String get authCopy;

  /// No description provided for @authReceiveAmountInvalid.
  ///
  /// In ko, this message translates to:
  /// **'소수점 아래 6자리 숫자를 입력해주세요 (예: 0.234567 이면 234567)'**
  String get authReceiveAmountInvalid;

  /// No description provided for @authWalletStepTitle.
  ///
  /// In ko, this message translates to:
  /// **'1단계 · 지갑 인증'**
  String get authWalletStepTitle;

  /// No description provided for @authWalletStepDesc.
  ///
  /// In ko, this message translates to:
  /// **'내 퀀타리움 지갑주소를 넣으면 가지 본사 지갑이 5.xxxxxx QTA 를 보내드려요. 그중 앱이 알려주는 1.xxxxxx QTA 를 본사 지갑으로 돌려보내면 인증 끝! (지갑 주인만 보낼 수 있어서 안전해요)'**
  String get authWalletStepDesc;

  /// No description provided for @authRequesting.
  ///
  /// In ko, this message translates to:
  /// **'요청 중…'**
  String get authRequesting;

  /// No description provided for @authReceiveCoinButton.
  ///
  /// In ko, this message translates to:
  /// **'이 지갑으로 인증 코인 받기'**
  String get authReceiveCoinButton;

  /// No description provided for @authReceiveSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'지금 인증 코인을 보내지 못했어요. 잠시 후 다시 요청해주세요'**
  String get authReceiveSendFailed;

  /// No description provided for @authRequestAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 요청하기'**
  String get authRequestAgain;

  /// No description provided for @authReceiveSending.
  ///
  /// In ko, this message translates to:
  /// **'가지 본사 지갑에서 {wallet} 으로 보내는 중이에요… (보통 1분 이내)'**
  String authReceiveSending(String wallet);

  /// No description provided for @authReceiveSent.
  ///
  /// In ko, this message translates to:
  /// **'보냈어요! 퀀타리움 지갑 앱에서 {wallet} 에 들어온 수량을 확인하고 소수점 아래 6자리를 입력해주세요. 블록에 담기기까지 수십 초 걸릴 수 있어요.'**
  String authReceiveSent(String wallet);

  /// No description provided for @authCheckWalletCode.
  ///
  /// In ko, this message translates to:
  /// **'scan.quantarium.io 에서 내 지갑 보기'**
  String get authCheckWalletCode;

  /// No description provided for @authReceivedAmount.
  ///
  /// In ko, this message translates to:
  /// **'받은 수량'**
  String get authReceivedAmount;

  /// No description provided for @authAttemptsLeft.
  ///
  /// In ko, this message translates to:
  /// **'남은 기회 {count}번 · 24시간 안에 입력해주세요'**
  String authAttemptsLeft(String count);

  /// No description provided for @authLoginFailed.
  ///
  /// In ko, this message translates to:
  /// **'로그인 중 문제가 생겼어요. 다시 시도해주세요.'**
  String get authLoginFailed;

  /// No description provided for @authLoginTitle.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get authLoginTitle;

  /// No description provided for @authLoginDesc.
  ///
  /// In ko, this message translates to:
  /// **'닉네임과 비밀번호로 로그인하세요.\n큐알쳇 회원이라면 큐알쳇 닉네임·비밀번호로 바로 로그인돼요.'**
  String get authLoginDesc;

  /// No description provided for @authLoginNicknameHint.
  ///
  /// In ko, this message translates to:
  /// **'가입할 때 설정한 닉네임'**
  String get authLoginNicknameHint;

  /// No description provided for @authLoginButton.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get authLoginButton;

  /// No description provided for @authFindNicknamePassword.
  ///
  /// In ko, this message translates to:
  /// **'닉네임 / 비밀번호 찾기'**
  String get authFindNicknamePassword;

  /// No description provided for @authSessionInfo.
  ///
  /// In ko, this message translates to:
  /// **'다른 기기에서 같은 계정으로 로그인하면 이전 기기의 세션은 즉시 종료돼요.'**
  String get authSessionInfo;

  /// No description provided for @authSplashTagline.
  ///
  /// In ko, this message translates to:
  /// **'익명으로 안전한 중고거래 🍆'**
  String get authSplashTagline;

  /// No description provided for @authOnboarding1Headline.
  ///
  /// In ko, this message translates to:
  /// **'전화번호 없이\n익명으로 거래해요'**
  String get authOnboarding1Headline;

  /// No description provided for @authOnboarding1Desc.
  ///
  /// In ko, this message translates to:
  /// **'닉네임 하나면 충분해요.\n개인정보 노출 걱정 없이 안전하게.'**
  String get authOnboarding1Desc;

  /// No description provided for @authOnboarding2Headline.
  ///
  /// In ko, this message translates to:
  /// **'우리 동네\n이웃과 거래해요'**
  String get authOnboarding2Headline;

  /// No description provided for @authOnboarding2Desc.
  ///
  /// In ko, this message translates to:
  /// **'내 동네 인증된 사람들과만 만나요.\nQR 코드로 안심하고 직거래!'**
  String get authOnboarding2Desc;

  /// No description provided for @authOnboarding3Headline.
  ///
  /// In ko, this message translates to:
  /// **'쓸수록 쌓이는\nQTA 토큰 보상'**
  String get authOnboarding3Headline;

  /// No description provided for @authOnboarding3Desc.
  ///
  /// In ko, this message translates to:
  /// **'지갑·휴대폰 인증하면 +1,000 QTA,\n친구 초대마다 +200 QTA × 무제한!'**
  String get authOnboarding3Desc;

  /// No description provided for @authPermTitle.
  ///
  /// In ko, this message translates to:
  /// **'원활한 사용을 위해\n아래 권한이 필요해요'**
  String get authPermTitle;

  /// No description provided for @authPermSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'한 번만 허용하면 다시 묻지 않아요.'**
  String get authPermSubtitle;

  /// No description provided for @authPermCamera.
  ///
  /// In ko, this message translates to:
  /// **'카메라'**
  String get authPermCamera;

  /// No description provided for @authPermCameraDesc.
  ///
  /// In ko, this message translates to:
  /// **'QR 스캔 · 상품 사진/영상 촬영'**
  String get authPermCameraDesc;

  /// No description provided for @authPermMic.
  ///
  /// In ko, this message translates to:
  /// **'마이크'**
  String get authPermMic;

  /// No description provided for @authPermMicDesc.
  ///
  /// In ko, this message translates to:
  /// **'익명 음성통화 (상대방에게만 전달)'**
  String get authPermMicDesc;

  /// No description provided for @authPermPhotos.
  ///
  /// In ko, this message translates to:
  /// **'사진 / 동영상'**
  String get authPermPhotos;

  /// No description provided for @authPermPhotosDesc.
  ///
  /// In ko, this message translates to:
  /// **'갤러리에서 상품 사진 선택'**
  String get authPermPhotosDesc;

  /// No description provided for @authPermNotifications.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get authPermNotifications;

  /// No description provided for @authPermNotificationsDesc.
  ///
  /// In ko, this message translates to:
  /// **'새 채팅 · 통화 알림'**
  String get authPermNotificationsDesc;

  /// No description provided for @authPermContinue.
  ///
  /// In ko, this message translates to:
  /// **'확인하고 계속'**
  String get authPermContinue;

  /// No description provided for @authPermLater.
  ///
  /// In ko, this message translates to:
  /// **'나중에 하기'**
  String get authPermLater;

  /// No description provided for @authSkip.
  ///
  /// In ko, this message translates to:
  /// **'건너뛰기'**
  String get authSkip;

  /// No description provided for @authStart.
  ///
  /// In ko, this message translates to:
  /// **'시작하기'**
  String get authStart;

  /// No description provided for @authNext.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get authNext;

  /// No description provided for @authHaveAccountQuestion.
  ///
  /// In ko, this message translates to:
  /// **'이미 계정이 있어요?'**
  String get authHaveAccountQuestion;

  /// No description provided for @authDeleteAgreeRequired.
  ///
  /// In ko, this message translates to:
  /// **'안내 사항에 동의해야 탈퇴할 수 있어요.'**
  String get authDeleteAgreeRequired;

  /// No description provided for @authDeletePasswordRequired.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 입력해주세요.'**
  String get authDeletePasswordRequired;

  /// No description provided for @authDeleteDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'정말 탈퇴할까요?'**
  String get authDeleteDialogTitle;

  /// No description provided for @authDeleteDialogBody.
  ///
  /// In ko, this message translates to:
  /// **'계정과 모든 데이터가 즉시 영구 삭제돼요.\n복구는 불가능하며, 잔여 QTA·받은 추천 보너스는 회수돼요.'**
  String get authDeleteDialogBody;

  /// No description provided for @authDeleteDialogConfirm.
  ///
  /// In ko, this message translates to:
  /// **'영구 삭제'**
  String get authDeleteDialogConfirm;

  /// No description provided for @authDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴 처리 중 문제가 생겼어요. 다시 시도해주세요.'**
  String get authDeleteFailed;

  /// No description provided for @authDeleteDone.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴가 완료되었어요. 이용해주셔서 감사했어요. 🍆'**
  String get authDeleteDone;

  /// No description provided for @authDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'계정 영구 삭제'**
  String get authDeleteTitle;

  /// No description provided for @authDeleteWarning.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하면 즉시 영구 삭제돼요\n한 번 사라진 데이터는 복구되지 않아요.'**
  String get authDeleteWarning;

  /// No description provided for @authDeleteDataTitle.
  ///
  /// In ko, this message translates to:
  /// **'삭제되는 데이터'**
  String get authDeleteDataTitle;

  /// No description provided for @authDeleteBullet1.
  ///
  /// In ko, this message translates to:
  /// **'내 닉네임 · 동네 · 매너 점수 · 매너 리뷰'**
  String get authDeleteBullet1;

  /// No description provided for @authDeleteBullet2.
  ///
  /// In ko, this message translates to:
  /// **'내가 등록한 모든 상품'**
  String get authDeleteBullet2;

  /// No description provided for @authDeleteBullet3.
  ///
  /// In ko, this message translates to:
  /// **'잔여 QTA 잔액 ({balance} QTA) 폐기'**
  String authDeleteBullet3(String balance);

  /// No description provided for @authDeleteBullet4.
  ///
  /// In ko, this message translates to:
  /// **'받은 친구 초대 보너스는 즉시 회수 (−200 QTA × 인원)'**
  String get authDeleteBullet4;

  /// No description provided for @authDeleteBullet5.
  ///
  /// In ko, this message translates to:
  /// **'내가 추천인이 됐던 친구의 보너스도 즉시 회수'**
  String get authDeleteBullet5;

  /// No description provided for @authDeleteBullet6.
  ///
  /// In ko, this message translates to:
  /// **'숨김/차단/키워드 알림/검색 기록 모두 사라짐'**
  String get authDeleteBullet6;

  /// No description provided for @authDeleteBullet7.
  ///
  /// In ko, this message translates to:
  /// **'채팅 메시지·통화 기록은 원래부터 저장된 게 없어요 🔐'**
  String get authDeleteBullet7;

  /// No description provided for @authDeleteAgree.
  ///
  /// In ko, this message translates to:
  /// **'위 사항을 모두 이해했고, 영구 삭제에 동의해요.'**
  String get authDeleteAgree;

  /// No description provided for @authDeletePasswordTitle.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재확인'**
  String get authDeletePasswordTitle;

  /// No description provided for @authDeleteButton.
  ///
  /// In ko, this message translates to:
  /// **'영구 삭제하기'**
  String get authDeleteButton;

  /// No description provided for @authDeleteCancelBack.
  ///
  /// In ko, this message translates to:
  /// **'취소하고 돌아가기'**
  String get authDeleteCancelBack;

  /// No description provided for @authProfileVerifyTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로필 인증'**
  String get authProfileVerifyTitle;

  /// No description provided for @authProfileStepsTitle.
  ///
  /// In ko, this message translates to:
  /// **'인증 단계'**
  String get authProfileStepsTitle;

  /// No description provided for @authProfileStep0Title.
  ///
  /// In ko, this message translates to:
  /// **'가입'**
  String get authProfileStep0Title;

  /// No description provided for @authProfileStep0Desc.
  ///
  /// In ko, this message translates to:
  /// **'닉네임·비밀번호로 가입하면 자동 완료.\n둘러보기 · 채팅 · 통화 · 상품 등록 가능.'**
  String get authProfileStep0Desc;

  /// No description provided for @authProfileStep1Desc.
  ///
  /// In ko, this message translates to:
  /// **'내 퀀타리움 지갑주소를 넣으면 가지 본사 지갑이 5.xxxxxx QTA를 보내드려요.\n받은 지갑에서 안내된 1.xxxxxx QTA를 본사로 돌려보내면 인증 끝!\n출금한 QTA 는 이 지갑으로 송금돼요.'**
  String get authProfileStep1Desc;

  /// No description provided for @authProfileDoneLabel.
  ///
  /// In ko, this message translates to:
  /// **'완료됨'**
  String get authProfileDoneLabel;

  /// No description provided for @authProfileWalletDoneSnack.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증을 마쳤어요. 이제 2단계 휴대폰 인증!'**
  String get authProfileWalletDoneSnack;

  /// No description provided for @authProfileStep2Title.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 인증'**
  String get authProfileStep2Title;

  /// No description provided for @authProfileStep2Desc.
  ///
  /// In ko, this message translates to:
  /// **'문자로 받은 인증번호를 입력해요. 한 번호로 한 계정만 인증돼요.\n거래완료 · QTA 결제 거래 · 출금이 열려요.\n\n🔒 전화번호는 암호화해 보관하며, 불법 이용 추적 외에는 쓰지 않아요. 한국(010)·일본(070/080/090)·필리핀(09) 휴대폰 번호만 인증돼요.'**
  String get authProfileStep2Desc;

  /// No description provided for @authProfileWalletFirst.
  ///
  /// In ko, this message translates to:
  /// **'1단계 지갑 인증을 먼저 마쳐주세요.'**
  String get authProfileWalletFirst;

  /// No description provided for @authProfileComingSoon.
  ///
  /// In ko, this message translates to:
  /// **'곧 열려요'**
  String get authProfileComingSoon;

  /// No description provided for @authProfilePhoneStart.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 인증 시작'**
  String get authProfilePhoneStart;

  /// No description provided for @authProfileStep1First.
  ///
  /// In ko, this message translates to:
  /// **'1단계 먼저'**
  String get authProfileStep1First;

  /// No description provided for @authProfilePhoneDoneSnack.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 인증을 마쳤어요'**
  String get authProfilePhoneDoneSnack;

  /// No description provided for @authProfilePolicyTitle.
  ///
  /// In ko, this message translates to:
  /// **'익명성 정책'**
  String get authProfilePolicyTitle;

  /// No description provided for @authProfilePolicy1.
  ///
  /// In ko, this message translates to:
  /// **'채팅 / 음성통화는 인증 단계와 무관하게 항상 닉네임만 노출됩니다.'**
  String get authProfilePolicy1;

  /// No description provided for @authProfilePolicy2.
  ///
  /// In ko, this message translates to:
  /// **'인증 정보는 거래 자격 확인 용도로만 쓰이며, 거래 상대방·다른 사용자에게 절대 노출되지 않습니다.'**
  String get authProfilePolicy2;

  /// No description provided for @authProfilePolicy3.
  ///
  /// In ko, this message translates to:
  /// **'같은 지갑·같은 휴대폰 번호로 여러 계정을 인증할 수 없어요.'**
  String get authProfilePolicy3;

  /// No description provided for @authProfileBonusDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'인증 완료 🎉'**
  String get authProfileBonusDialogTitle;

  /// No description provided for @authProfileBonusDialogBody.
  ///
  /// In ko, this message translates to:
  /// **'1·2단계 인증을 모두 마쳤어요!\n인증 보너스 +{bonus} QTA 를 드렸어요.\n이제 QTA 결제 거래와 출금을 할 수 있어요.'**
  String authProfileBonusDialogBody(String bonus);

  /// No description provided for @authProfileAllDone.
  ///
  /// In ko, this message translates to:
  /// **'인증 완료'**
  String get authProfileAllDone;

  /// No description provided for @authProfileStep1Done.
  ///
  /// In ko, this message translates to:
  /// **'1단계 완료 · 휴대폰 인증 남음'**
  String get authProfileStep1Done;

  /// No description provided for @authProfileUnverified.
  ///
  /// In ko, this message translates to:
  /// **'미인증'**
  String get authProfileUnverified;

  /// No description provided for @authProfileProgress.
  ///
  /// In ko, this message translates to:
  /// **'인증 {done}/2 단계'**
  String authProfileProgress(String done);

  /// No description provided for @authProfileBonusReceived.
  ///
  /// In ko, this message translates to:
  /// **'인증 보너스 {bonus} QTA 를 받았어요'**
  String authProfileBonusReceived(String bonus);

  /// No description provided for @authProfileBonusPending.
  ///
  /// In ko, this message translates to:
  /// **'1·2단계 인증을 모두 마치면 {bonus} QTA 를 드려요!'**
  String authProfileBonusPending(String bonus);

  /// No description provided for @authProfileDoneBadge.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get authProfileDoneBadge;

  /// No description provided for @authGuardPhoneTitle.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 인증이 필요해요'**
  String get authGuardPhoneTitle;

  /// No description provided for @authGuardWalletTitle.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증이 필요해요'**
  String get authGuardWalletTitle;

  /// No description provided for @authGuardPhoneMessage.
  ///
  /// In ko, this message translates to:
  /// **'거래(결제)는 1인 1계정 보장을 위해 1단계 지갑 인증과 2단계 휴대폰 인증이 필요해요.\n인증해도 채팅·통화는 익명 그대로 유지돼요.'**
  String get authGuardPhoneMessage;

  /// No description provided for @authGuardWalletMessage.
  ///
  /// In ko, this message translates to:
  /// **'QTA 출금을 위해 1단계 지갑 인증과 2단계 휴대폰 인증이 필요해요.\n두 단계를 모두 마치면 1,000 QTA 도 드려요.'**
  String get authGuardWalletMessage;

  /// No description provided for @authGuardGoVerify.
  ///
  /// In ko, this message translates to:
  /// **'인증하러 가기'**
  String get authGuardGoVerify;

  /// No description provided for @authPassPopupTitle.
  ///
  /// In ko, this message translates to:
  /// **'가지마켓 본인인증'**
  String get authPassPopupTitle;

  /// No description provided for @authAccountSuspended.
  ///
  /// In ko, this message translates to:
  /// **'이용이 정지된 계정이에요'**
  String get authAccountSuspended;

  /// No description provided for @authRegisterFailedStatus.
  ///
  /// In ko, this message translates to:
  /// **'가입 실패 (status={status})'**
  String authRegisterFailedStatus(String status);

  /// No description provided for @authServerTooSlow.
  ///
  /// In ko, this message translates to:
  /// **'서버 응답이 너무 느려요. 네트워크를 확인하고 다시 시도해주세요.'**
  String get authServerTooSlow;

  /// No description provided for @authDeleteFailedShort.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴 처리 실패'**
  String get authDeleteFailedShort;

  /// No description provided for @authLoginFailedShort.
  ///
  /// In ko, this message translates to:
  /// **'로그인 실패'**
  String get authLoginFailedShort;

  /// No description provided for @authSsoFailed.
  ///
  /// In ko, this message translates to:
  /// **'SSO 인증 실패'**
  String get authSsoFailed;

  /// No description provided for @authNotFound.
  ///
  /// In ko, this message translates to:
  /// **'찾을 수 없어요'**
  String get authNotFound;

  /// No description provided for @authResetFailedShort.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재설정 실패'**
  String get authResetFailedShort;

  /// No description provided for @authRegionSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'동네를 저장하지 못했어요'**
  String get authRegionSaveFailed;

  /// No description provided for @authNicknameLength.
  ///
  /// In ko, this message translates to:
  /// **'닉네임은 2~12자여야 해요'**
  String get authNicknameLength;

  /// No description provided for @authNicknameChangeFailed.
  ///
  /// In ko, this message translates to:
  /// **'닉네임 변경 실패'**
  String get authNicknameChangeFailed;

  /// No description provided for @authWalletVerifyStartFailed.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증을 시작하지 못했어요'**
  String get authWalletVerifyStartFailed;

  /// No description provided for @authTransferNotConfirmed.
  ///
  /// In ko, this message translates to:
  /// **'아직 송금이 확인되지 않았어요'**
  String get authTransferNotConfirmed;

  /// No description provided for @authAmountCheckFailed.
  ///
  /// In ko, this message translates to:
  /// **'수량을 확인하지 못했어요'**
  String get authAmountCheckFailed;

  /// No description provided for @authCannotConnect.
  ///
  /// In ko, this message translates to:
  /// **'서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요.'**
  String get authCannotConnect;

  /// No description provided for @authTimeout.
  ///
  /// In ko, this message translates to:
  /// **'응답 시간이 초과되었어요.'**
  String get authTimeout;

  /// No description provided for @authGenericError.
  ///
  /// In ko, this message translates to:
  /// **'오류가 발생했어요'**
  String get authGenericError;

  /// No description provided for @authQuantumBadge.
  ///
  /// In ko, this message translates to:
  /// **'양자내성 서명(SPHINCS+)으로 보낸 거래예요'**
  String get authQuantumBadge;

  /// No description provided for @authViewTxOnScan.
  ///
  /// In ko, this message translates to:
  /// **'scan.quantarium.io 에서 본사 송금 보기'**
  String get authViewTxOnScan;

  /// No description provided for @authResetWalletTitle.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증 (다른 기기에서 재설정 시)'**
  String get authResetWalletTitle;

  /// No description provided for @authResetWalletDesc.
  ///
  /// In ko, this message translates to:
  /// **'가입할 때 등록한 지갑과 같은지 먼저 확인한 뒤, 가지 본사 지갑이 그 지갑으로 5.xxxxxx QTA 를 보내드려요. 앱이 알려주는 1.xxxxxx QTA 를 본사 지갑으로 돌려보내면 인증 끝!'**
  String get authResetWalletDesc;

  /// No description provided for @authResetWalletVerified.
  ///
  /// In ko, this message translates to:
  /// **'지갑 인증 완료! 아래에 새 비밀번호를 입력하세요.'**
  String get authResetWalletVerified;

  /// No description provided for @authScanHint.
  ///
  /// In ko, this message translates to:
  /// **'지갑 앱에 소량이 안 보이면 위 scan 버튼을 눌러 화면의 Value(예: 0.234567 QTA)를 확인하고, 소수점 아래 6자리를 아래 칸에 입력하세요.'**
  String get authScanHint;

  /// No description provided for @authReturnSent.
  ///
  /// In ko, this message translates to:
  /// **'가지 본사 지갑이 {wallet} 으로 {amount} QTA 를 보냈어요.'**
  String authReturnSent(String wallet, String amount);

  /// No description provided for @authReturnTitle.
  ///
  /// In ko, this message translates to:
  /// **'이제 이 수량을 본사 지갑으로 돌려보내 주세요'**
  String get authReturnTitle;

  /// No description provided for @authReturnDesc.
  ///
  /// In ko, this message translates to:
  /// **'퀀타리움 지갑 앱에서 아래 수량을 정확히, 아래 주소로 보내세요. 지갑 주인만 보낼 수 있어서 이걸로 내 지갑임이 증명돼요.'**
  String get authReturnDesc;

  /// No description provided for @authReturnAmountLabel.
  ///
  /// In ko, this message translates to:
  /// **'돌려보낼 수량 (정확히)'**
  String get authReturnAmountLabel;

  /// No description provided for @authReturnToLabel.
  ///
  /// In ko, this message translates to:
  /// **'받는 주소 (가지 본사 지갑)'**
  String get authReturnToLabel;

  /// No description provided for @authReturnNote.
  ///
  /// In ko, this message translates to:
  /// **'이 수량은 이번 한 번만 쓰여요 · 2시간 안에 보내주세요 · 블록에 담기기까지 수십 초 걸릴 수 있어요'**
  String get authReturnNote;

  /// No description provided for @authReturnSentButton.
  ///
  /// In ko, this message translates to:
  /// **'보냈어요 — 확인하기'**
  String get authReturnSentButton;

  /// No description provided for @chatLeaveWarningSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'🔒 나가면 양쪽 모두 완전 삭제돼요'**
  String get chatLeaveWarningSubtitle;

  /// No description provided for @chatVoiceCallTooltip.
  ///
  /// In ko, this message translates to:
  /// **'익명 음성통화'**
  String get chatVoiceCallTooltip;

  /// No description provided for @chatOfferSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'💰 가격 제안하기'**
  String get chatOfferSheetTitle;

  /// No description provided for @chatOfferAmountHint.
  ///
  /// In ko, this message translates to:
  /// **'제안 금액 ({unit})'**
  String chatOfferAmountHint(String unit);

  /// No description provided for @chatCurrencyUnitKrw.
  ///
  /// In ko, this message translates to:
  /// **'원'**
  String get chatCurrencyUnitKrw;

  /// No description provided for @chatCurrencyUnitJpy.
  ///
  /// In ko, this message translates to:
  /// **'엔'**
  String get chatCurrencyUnitJpy;

  /// No description provided for @chatOfferSend.
  ///
  /// In ko, this message translates to:
  /// **'제안 보내기'**
  String get chatOfferSend;

  /// No description provided for @chatOfferAutoCancelNote.
  ///
  /// In ko, this message translates to:
  /// **'이전에 보낸 미응답 제안은 자동으로 취소돼요.'**
  String get chatOfferAutoCancelNote;

  /// No description provided for @chatOfferAccept.
  ///
  /// In ko, this message translates to:
  /// **'수락'**
  String get chatOfferAccept;

  /// No description provided for @chatOfferReject.
  ///
  /// In ko, this message translates to:
  /// **'거절'**
  String get chatOfferReject;

  /// No description provided for @chatOfferCancelAction.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get chatOfferCancelAction;

  /// No description provided for @chatOfferDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'가격 제안 {action}'**
  String chatOfferDialogTitle(String action);

  /// No description provided for @chatOfferAcceptConfirm.
  ///
  /// In ko, this message translates to:
  /// **'이 가격에 거래를 진행하시겠어요?'**
  String get chatOfferAcceptConfirm;

  /// No description provided for @chatOfferRejectConfirm.
  ///
  /// In ko, this message translates to:
  /// **'제안을 거절할까요?'**
  String get chatOfferRejectConfirm;

  /// No description provided for @chatPeerNotFound.
  ///
  /// In ko, this message translates to:
  /// **'상대방 정보를 찾을 수 없어요'**
  String get chatPeerNotFound;

  /// No description provided for @chatClearMessages.
  ///
  /// In ko, this message translates to:
  /// **'대화 내용 삭제'**
  String get chatClearMessages;

  /// No description provided for @chatClearMessagesSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'이 방의 메시지만 비워요 (방은 유지)'**
  String get chatClearMessagesSubtitle;

  /// No description provided for @chatLeaveRoom.
  ///
  /// In ko, this message translates to:
  /// **'채팅방 나가기'**
  String get chatLeaveRoom;

  /// No description provided for @chatLeaveRoomSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'양쪽 모두 대화 + 방을 완전 삭제해요 (복구 불가)'**
  String get chatLeaveRoomSubtitle;

  /// No description provided for @chatLeaveRoomConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{nickname}님과의 대화를 완전히 삭제할까요?\n\n• 메시지 전부 영구 삭제\n• 상대방 화면에서도 즉시 사라짐\n• 복구 불가'**
  String chatLeaveRoomConfirm(String nickname);

  /// No description provided for @chatDeletePermanently.
  ///
  /// In ko, this message translates to:
  /// **'완전히 삭제'**
  String get chatDeletePermanently;

  /// No description provided for @chatDeleteFailedRetry.
  ///
  /// In ko, this message translates to:
  /// **'삭제 실패. 잠시 후 다시 시도해주세요'**
  String get chatDeleteFailedRetry;

  /// No description provided for @chatClearMessagesConfirm.
  ///
  /// In ko, this message translates to:
  /// **'이 방의 모든 메시지를 지울까요?\n방은 유지되며 상대방 화면의 메시지도 같이 지워져요.'**
  String get chatClearMessagesConfirm;

  /// No description provided for @chatMessagesCleared.
  ///
  /// In ko, this message translates to:
  /// **'대화 내용을 비웠어요'**
  String get chatMessagesCleared;

  /// No description provided for @chatDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'삭제 실패'**
  String get chatDeleteFailed;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'{nickname} 님과\n익명 채팅이 시작되었어요'**
  String chatEmptyTitle(String nickname);

  /// No description provided for @chatEmptyNote.
  ///
  /// In ko, this message translates to:
  /// **'이 대화는 서버/기기 어디에도 저장되지 않아요.\n화면을 벗어나면 내용이 사라져요.'**
  String get chatEmptyNote;

  /// No description provided for @chatRead.
  ///
  /// In ko, this message translates to:
  /// **'읽음'**
  String get chatRead;

  /// No description provided for @chatOfferLabel.
  ///
  /// In ko, this message translates to:
  /// **'가격 제안'**
  String get chatOfferLabel;

  /// No description provided for @chatInputHint.
  ///
  /// In ko, this message translates to:
  /// **'메시지 입력'**
  String get chatInputHint;

  /// No description provided for @chatConnecting.
  ///
  /// In ko, this message translates to:
  /// **'연결 중...'**
  String get chatConnecting;

  /// No description provided for @chatOfferCancelButton.
  ///
  /// In ko, this message translates to:
  /// **'제안 취소하기'**
  String get chatOfferCancelButton;

  /// No description provided for @chatCallOutgoing.
  ///
  /// In ko, this message translates to:
  /// **'호출 중...'**
  String get chatCallOutgoing;

  /// No description provided for @chatCallIncoming.
  ///
  /// In ko, this message translates to:
  /// **'걸려온 익명 통화'**
  String get chatCallIncoming;

  /// No description provided for @chatCallEnded.
  ///
  /// In ko, this message translates to:
  /// **'통화 종료'**
  String get chatCallEnded;

  /// No description provided for @chatCallHeader.
  ///
  /// In ko, this message translates to:
  /// **'완전 익명 음성 통화'**
  String get chatCallHeader;

  /// No description provided for @chatCallP2pNote.
  ///
  /// In ko, this message translates to:
  /// **'이 통화는 P2P로 직접 연결돼요.\n서버에 녹음·저장되지 않아요.'**
  String get chatCallP2pNote;

  /// No description provided for @chatCallDecline.
  ///
  /// In ko, this message translates to:
  /// **'거절'**
  String get chatCallDecline;

  /// No description provided for @chatCallAccept.
  ///
  /// In ko, this message translates to:
  /// **'수락'**
  String get chatCallAccept;

  /// No description provided for @chatCallUnmute.
  ///
  /// In ko, this message translates to:
  /// **'음소거 해제'**
  String get chatCallUnmute;

  /// No description provided for @chatCallMute.
  ///
  /// In ko, this message translates to:
  /// **'음소거'**
  String get chatCallMute;

  /// No description provided for @chatCallHangup.
  ///
  /// In ko, this message translates to:
  /// **'종료'**
  String get chatCallHangup;

  /// No description provided for @chatCallSpeaker.
  ///
  /// In ko, this message translates to:
  /// **'스피커'**
  String get chatCallSpeaker;

  /// No description provided for @chatCallEarpiece.
  ///
  /// In ko, this message translates to:
  /// **'수화기'**
  String get chatCallEarpiece;

  /// No description provided for @chatLeaveRoomConfirmList.
  ///
  /// In ko, this message translates to:
  /// **'{nickname}님과의 대화를 완전히 삭제할까요?\n\n• 주고받은 모든 메시지가 사라져요\n• 상대방 화면에서도 함께 삭제돼요\n• 복구할 수 없어요'**
  String chatLeaveRoomConfirmList(String nickname);

  /// No description provided for @chatRoomDeleted.
  ///
  /// In ko, this message translates to:
  /// **'채팅방을 삭제했어요'**
  String get chatRoomDeleted;

  /// No description provided for @chatTabTitle.
  ///
  /// In ko, this message translates to:
  /// **'채팅'**
  String get chatTabTitle;

  /// No description provided for @chatQrScanTooltip.
  ///
  /// In ko, this message translates to:
  /// **'QR 스캔해서 대화 시작'**
  String get chatQrScanTooltip;

  /// No description provided for @chatPrivacyBanner.
  ///
  /// In ko, this message translates to:
  /// **'대화는 어디에도 저장되지 않아요. 앱을 닫으면 사라져요.'**
  String get chatPrivacyBanner;

  /// No description provided for @chatListEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 대화가 없어요'**
  String get chatListEmptyTitle;

  /// No description provided for @chatListEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'관심있는 상품에서 \"채팅하기\"를 눌러보세요'**
  String get chatListEmptyHint;

  /// No description provided for @chatSwipeLeave.
  ///
  /// In ko, this message translates to:
  /// **'나가기'**
  String get chatSwipeLeave;

  /// No description provided for @chatRoomAboutProduct.
  ///
  /// In ko, this message translates to:
  /// **'{title} 관련 대화'**
  String chatRoomAboutProduct(String title);

  /// No description provided for @chatSendFirstMessage.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 보내보세요'**
  String get chatSendFirstMessage;

  /// No description provided for @chatLastMessageMine.
  ///
  /// In ko, this message translates to:
  /// **'나: {message}'**
  String chatLastMessageMine(String message);

  /// No description provided for @chatAnonymous.
  ///
  /// In ko, this message translates to:
  /// **'익명'**
  String get chatAnonymous;

  /// No description provided for @chatEnterAmount.
  ///
  /// In ko, this message translates to:
  /// **'금액을 입력해주세요'**
  String get chatEnterAmount;

  /// No description provided for @chatReconnecting.
  ///
  /// In ko, this message translates to:
  /// **'연결 중이에요. 잠시 후 다시 시도해주세요'**
  String get chatReconnecting;

  /// No description provided for @chatRoomNotFound.
  ///
  /// In ko, this message translates to:
  /// **'대화방을 찾을 수 없어요'**
  String get chatRoomNotFound;

  /// No description provided for @chatNewMessage.
  ///
  /// In ko, this message translates to:
  /// **'새 메시지'**
  String get chatNewMessage;

  /// No description provided for @chatEnterMessage.
  ///
  /// In ko, this message translates to:
  /// **'내용을 입력해주세요'**
  String get chatEnterMessage;

  /// No description provided for @chatCallPeerDeclined.
  ///
  /// In ko, this message translates to:
  /// **'상대방이 통화를 거절했어요'**
  String get chatCallPeerDeclined;

  /// No description provided for @chatCallRetryLater.
  ///
  /// In ko, this message translates to:
  /// **'연결을 시도했어요. 잠시 후 다시 걸어주세요.'**
  String get chatCallRetryLater;

  /// No description provided for @chatCallFailed.
  ///
  /// In ko, this message translates to:
  /// **'통화 실패'**
  String get chatCallFailed;

  /// No description provided for @chatCallAlreadyInCall.
  ///
  /// In ko, this message translates to:
  /// **'이미 통화 중이에요'**
  String get chatCallAlreadyInCall;

  /// No description provided for @chatCallStillConnecting.
  ///
  /// In ko, this message translates to:
  /// **'연결 중이에요'**
  String get chatCallStillConnecting;

  /// No description provided for @chatCallWaitingAnswer.
  ///
  /// In ko, this message translates to:
  /// **'응답을 기다리고 있어요'**
  String get chatCallWaitingAnswer;

  /// No description provided for @chatCallHasIncoming.
  ///
  /// In ko, this message translates to:
  /// **'걸려온 통화가 있어요'**
  String get chatCallHasIncoming;

  /// No description provided for @chatMicPermissionRequired.
  ///
  /// In ko, this message translates to:
  /// **'마이크 권한이 필요해요'**
  String get chatMicPermissionRequired;

  /// No description provided for @chatCallServerDisconnected.
  ///
  /// In ko, this message translates to:
  /// **'서버에 연결되지 않았어요'**
  String get chatCallServerDisconnected;

  /// No description provided for @chatCallNoAnswer.
  ///
  /// In ko, this message translates to:
  /// **'상대방이 받지 않았어요'**
  String get chatCallNoAnswer;

  /// No description provided for @chatMicPermissionSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정 > 권한 > 마이크에서 권한을 켜주세요'**
  String get chatMicPermissionSettings;

  /// No description provided for @chatCallAgoraConfigMissing.
  ///
  /// In ko, this message translates to:
  /// **'Agora 설정이 누락되었어요'**
  String get chatCallAgoraConfigMissing;

  /// No description provided for @chatCallPeerNotConnected.
  ///
  /// In ko, this message translates to:
  /// **'상대와 연결되지 않았어요'**
  String get chatCallPeerNotConnected;

  /// No description provided for @chatCallEndedMessage.
  ///
  /// In ko, this message translates to:
  /// **'통화가 종료되었어요'**
  String get chatCallEndedMessage;

  /// No description provided for @chatCallAuthExpired.
  ///
  /// In ko, this message translates to:
  /// **'통화 인증이 만료되었어요'**
  String get chatCallAuthExpired;

  /// No description provided for @chatCallDisconnected.
  ///
  /// In ko, this message translates to:
  /// **'통화 연결이 끊어졌어요'**
  String get chatCallDisconnected;

  /// No description provided for @chatCallNetworkUnstable.
  ///
  /// In ko, this message translates to:
  /// **'네트워크가 불안정해요'**
  String get chatCallNetworkUnstable;

  /// No description provided for @chatCallkitAppName.
  ///
  /// In ko, this message translates to:
  /// **'가지마켓'**
  String get chatCallkitAppName;

  /// No description provided for @chatCallkitAccept.
  ///
  /// In ko, this message translates to:
  /// **'받기'**
  String get chatCallkitAccept;

  /// No description provided for @chatCallkitDecline.
  ///
  /// In ko, this message translates to:
  /// **'거절'**
  String get chatCallkitDecline;

  /// No description provided for @chatMissedCall.
  ///
  /// In ko, this message translates to:
  /// **'부재중 전화'**
  String get chatMissedCall;

  /// No description provided for @chatIncomingCallChannel.
  ///
  /// In ko, this message translates to:
  /// **'전화 수신 (V2)'**
  String get chatIncomingCallChannel;

  /// No description provided for @chatMissedCallChannel.
  ///
  /// In ko, this message translates to:
  /// **'부재중 전화 (V2)'**
  String get chatMissedCallChannel;

  /// No description provided for @chatChannelChatName.
  ///
  /// In ko, this message translates to:
  /// **'채팅 메시지'**
  String get chatChannelChatName;

  /// No description provided for @chatChannelChatDesc.
  ///
  /// In ko, this message translates to:
  /// **'새 채팅 메시지 알림'**
  String get chatChannelChatDesc;

  /// No description provided for @chatChannelKeywordName.
  ///
  /// In ko, this message translates to:
  /// **'키워드 알림'**
  String get chatChannelKeywordName;

  /// No description provided for @chatChannelKeywordDesc.
  ///
  /// In ko, this message translates to:
  /// **'관심 키워드와 일치하는 새 상품 알림'**
  String get chatChannelKeywordDesc;

  /// No description provided for @chatChannelPushName.
  ///
  /// In ko, this message translates to:
  /// **'Eggplant 메시지'**
  String get chatChannelPushName;

  /// No description provided for @chatChannelPushDesc.
  ///
  /// In ko, this message translates to:
  /// **'새 채팅 메시지 푸시 알림'**
  String get chatChannelPushDesc;

  /// No description provided for @chatChannelCallName.
  ///
  /// In ko, this message translates to:
  /// **'Eggplant 전화'**
  String get chatChannelCallName;

  /// No description provided for @chatChannelCallDesc.
  ///
  /// In ko, this message translates to:
  /// **'음성 통화 수신 알림'**
  String get chatChannelCallDesc;

  /// No description provided for @chatKeywordAlertTitle.
  ///
  /// In ko, this message translates to:
  /// **'🔔 새 매물 알림'**
  String get chatKeywordAlertTitle;

  /// No description provided for @chatKeywordAlertMaskedBody.
  ///
  /// In ko, this message translates to:
  /// **'관심 키워드와 일치하는 새 상품이 있어요'**
  String get chatKeywordAlertMaskedBody;

  /// No description provided for @chatKeywordTicker.
  ///
  /// In ko, this message translates to:
  /// **'새 매물'**
  String get chatKeywordTicker;

  /// No description provided for @chatMaskedMessageTitle.
  ///
  /// In ko, this message translates to:
  /// **'💬 새 메시지가 있어요'**
  String get chatMaskedMessageTitle;

  /// No description provided for @chatMaskedMessageBody.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 보려면 탭하세요'**
  String get chatMaskedMessageBody;

  /// No description provided for @chatPermMicBody.
  ///
  /// In ko, this message translates to:
  /// **'설정 > 앱 > Eggplant에서 마이크를 켜주세요.'**
  String get chatPermMicBody;

  /// No description provided for @chatPermCameraTitle.
  ///
  /// In ko, this message translates to:
  /// **'카메라 권한이 필요해요'**
  String get chatPermCameraTitle;

  /// No description provided for @chatPermCameraBody.
  ///
  /// In ko, this message translates to:
  /// **'설정 > 앱 > Eggplant에서 카메라를 켜주세요.'**
  String get chatPermCameraBody;

  /// No description provided for @chatPermGalleryTitle.
  ///
  /// In ko, this message translates to:
  /// **'갤러리 권한이 필요해요'**
  String get chatPermGalleryTitle;

  /// No description provided for @chatPermGalleryBodyAndroid.
  ///
  /// In ko, this message translates to:
  /// **'설정 > 앱 > Eggplant에서 사진/동영상 권한을 켜주세요.'**
  String get chatPermGalleryBodyAndroid;

  /// No description provided for @chatPermGalleryBodyIos.
  ///
  /// In ko, this message translates to:
  /// **'설정 > Eggplant에서 사진 권한을 켜주세요.'**
  String get chatPermGalleryBodyIos;

  /// No description provided for @chatPermNotifTitle.
  ///
  /// In ko, this message translates to:
  /// **'🔔 알림 권한이 꺼져 있어요'**
  String get chatPermNotifTitle;

  /// No description provided for @chatPermNotifBody.
  ///
  /// In ko, this message translates to:
  /// **'알림이 꺼져 있으면 새 메시지·통화·키워드 매물 알림을 놓칠 수 있어요.\n\n설정에서 알림을 켜시겠어요?\n\n※ Eggplant는 알림 본문을 잠금화면에서 가리는 옵션도 제공해요. \"나의 Eggplant > 알림 본문 가리기\" 에서 켤 수 있어요.'**
  String get chatPermNotifBody;

  /// No description provided for @chatPermOpenSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정 열기'**
  String get chatPermOpenSettings;

  /// No description provided for @chatPermFsiTitle.
  ///
  /// In ko, this message translates to:
  /// **'🔒 잠금화면 통화 알림 권한'**
  String get chatPermFsiTitle;

  /// No description provided for @chatPermFsiBody.
  ///
  /// In ko, this message translates to:
  /// **'잠금화면에서 통화 수신을 표시하려면\n\"전체 화면 알림\" 권한이 필요해요.\n\n권한이 꺼져 있으면 잠금화면에서는\n벨소리만 울리고 통화 화면이 뜨지 않아요.\n\n한 번만 설정하면 끝나요.'**
  String get chatPermFsiBody;

  /// No description provided for @chatPermAllow.
  ///
  /// In ko, this message translates to:
  /// **'권한 허용'**
  String get chatPermAllow;

  /// No description provided for @chatOfferStatusAccepted.
  ///
  /// In ko, this message translates to:
  /// **'수락됨'**
  String get chatOfferStatusAccepted;

  /// No description provided for @chatOfferStatusRejected.
  ///
  /// In ko, this message translates to:
  /// **'거절됨'**
  String get chatOfferStatusRejected;

  /// No description provided for @chatOfferStatusCancelled.
  ///
  /// In ko, this message translates to:
  /// **'취소됨'**
  String get chatOfferStatusCancelled;

  /// No description provided for @chatOfferStatusPending.
  ///
  /// In ko, this message translates to:
  /// **'응답 대기'**
  String get chatOfferStatusPending;

  /// No description provided for @chatTimeJustNow.
  ///
  /// In ko, this message translates to:
  /// **'방금 전'**
  String get chatTimeJustNow;

  /// No description provided for @chatTimeMinutesAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}분 전'**
  String chatTimeMinutesAgo(int n);

  /// No description provided for @chatTimeHoursAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}시간 전'**
  String chatTimeHoursAgo(int n);

  /// No description provided for @chatTimeDaysAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}일 전'**
  String chatTimeDaysAgo(int n);

  /// No description provided for @chatTimeWeeksAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}주 전'**
  String chatTimeWeeksAgo(int n);

  /// No description provided for @chatTimeMonthsAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}개월 전'**
  String chatTimeMonthsAgo(int n);

  /// No description provided for @chatTimeYearsAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}년 전'**
  String chatTimeYearsAgo(int n);

  /// No description provided for @chatCurrencyUnitPhp.
  ///
  /// In ko, this message translates to:
  /// **'페소'**
  String get chatCurrencyUnitPhp;

  /// No description provided for @commonCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get commonConfirm;

  /// No description provided for @commonDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get commonRetry;

  /// No description provided for @commonLater.
  ///
  /// In ko, this message translates to:
  /// **'나중에'**
  String get commonLater;

  /// No description provided for @commonFree.
  ///
  /// In ko, this message translates to:
  /// **'나눔'**
  String get commonFree;

  /// No description provided for @commonLoginRequired.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 필요해요'**
  String get commonLoginRequired;

  /// No description provided for @commonNetworkError.
  ///
  /// In ko, this message translates to:
  /// **'네트워크 오류가 발생했어요. 잠시 후 다시 시도해주세요'**
  String get commonNetworkError;

  /// No description provided for @priceKrw.
  ///
  /// In ko, this message translates to:
  /// **'{amount}원'**
  String priceKrw(String amount);

  /// No description provided for @priceJpy.
  ///
  /// In ko, this message translates to:
  /// **'¥{amount}'**
  String priceJpy(String amount);

  /// No description provided for @pricePhp.
  ///
  /// In ko, this message translates to:
  /// **'₱{amount}'**
  String pricePhp(String amount);

  /// No description provided for @homeSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'상품명 검색'**
  String get homeSearchHint;

  /// No description provided for @homeSetRegion.
  ///
  /// In ko, this message translates to:
  /// **'동네 설정'**
  String get homeSetRegion;

  /// No description provided for @homeSearchClose.
  ///
  /// In ko, this message translates to:
  /// **'검색 닫기'**
  String get homeSearchClose;

  /// No description provided for @homeSearch.
  ///
  /// In ko, this message translates to:
  /// **'검색'**
  String get homeSearch;

  /// No description provided for @homeQrScan.
  ///
  /// In ko, this message translates to:
  /// **'QR 스캔'**
  String get homeQrScan;

  /// No description provided for @homeRecentSearches.
  ///
  /// In ko, this message translates to:
  /// **'최근 검색어'**
  String get homeRecentSearches;

  /// No description provided for @homeClearAll.
  ///
  /// In ko, this message translates to:
  /// **'전체 삭제'**
  String get homeClearAll;

  /// No description provided for @homeNoRecentSearches.
  ///
  /// In ko, this message translates to:
  /// **'최근 검색 기록이 없어요'**
  String get homeNoRecentSearches;

  /// No description provided for @homeRangeAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get homeRangeAll;

  /// No description provided for @homeDistance.
  ///
  /// In ko, this message translates to:
  /// **'거리'**
  String get homeDistance;

  /// No description provided for @homeNoProducts.
  ///
  /// In ko, this message translates to:
  /// **'아직 상품이 없어요'**
  String get homeNoProducts;

  /// No description provided for @homeCheckNetwork.
  ///
  /// In ko, this message translates to:
  /// **'네트워크를 확인하고 다시 시도해주세요'**
  String get homeCheckNetwork;

  /// No description provided for @homeFirstProduct.
  ///
  /// In ko, this message translates to:
  /// **'첫 번째 상품을 등록해보세요!'**
  String get homeFirstProduct;

  /// No description provided for @homeRefresh.
  ///
  /// In ko, this message translates to:
  /// **'새로고침'**
  String get homeRefresh;

  /// No description provided for @homeMyRegionsTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 동네 {count}/{max}'**
  String homeMyRegionsTitle(int count, int max);

  /// No description provided for @homeMyRegionsHint.
  ///
  /// In ko, this message translates to:
  /// **'보고 싶은 동네를 누르면 바로 바뀌어요.'**
  String get homeMyRegionsHint;

  /// No description provided for @homeRemoveRegion.
  ///
  /// In ko, this message translates to:
  /// **'이 동네 빼기'**
  String get homeRemoveRegion;

  /// No description provided for @homeMaxRegions.
  ///
  /// In ko, this message translates to:
  /// **'최대 {max}곳까지 설정할 수 있어요'**
  String homeMaxRegions(int max);

  /// No description provided for @homeAddRegion.
  ///
  /// In ko, this message translates to:
  /// **'동네 추가하기'**
  String get homeAddRegion;

  /// No description provided for @homeCategoryAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get homeCategoryAll;

  /// No description provided for @homeCategoryDigital.
  ///
  /// In ko, this message translates to:
  /// **'디지털기기'**
  String get homeCategoryDigital;

  /// No description provided for @homeCategoryAppliance.
  ///
  /// In ko, this message translates to:
  /// **'생활가전'**
  String get homeCategoryAppliance;

  /// No description provided for @homeCategoryFurniture.
  ///
  /// In ko, this message translates to:
  /// **'가구/인테리어'**
  String get homeCategoryFurniture;

  /// No description provided for @homeCategoryClothing.
  ///
  /// In ko, this message translates to:
  /// **'의류'**
  String get homeCategoryClothing;

  /// No description provided for @homeCategoryBeauty.
  ///
  /// In ko, this message translates to:
  /// **'뷰티/미용'**
  String get homeCategoryBeauty;

  /// No description provided for @homeCategoryBook.
  ///
  /// In ko, this message translates to:
  /// **'도서/티켓'**
  String get homeCategoryBook;

  /// No description provided for @homeCategorySports.
  ///
  /// In ko, this message translates to:
  /// **'스포츠/레저'**
  String get homeCategorySports;

  /// No description provided for @homeCategoryHobby.
  ///
  /// In ko, this message translates to:
  /// **'취미/게임'**
  String get homeCategoryHobby;

  /// No description provided for @homeCategoryKids.
  ///
  /// In ko, this message translates to:
  /// **'유아동'**
  String get homeCategoryKids;

  /// No description provided for @homeCategoryPet.
  ///
  /// In ko, this message translates to:
  /// **'반려동물'**
  String get homeCategoryPet;

  /// No description provided for @homeCategoryFood.
  ///
  /// In ko, this message translates to:
  /// **'식품'**
  String get homeCategoryFood;

  /// No description provided for @homeCategoryEtc.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get homeCategoryEtc;

  /// No description provided for @homeLikesTitle.
  ///
  /// In ko, this message translates to:
  /// **'찜한 상품'**
  String get homeLikesTitle;

  /// No description provided for @homeLikesTitleCount.
  ///
  /// In ko, this message translates to:
  /// **'찜한 상품 {count}'**
  String homeLikesTitleCount(int count);

  /// No description provided for @homeLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'불러올 수 없어요'**
  String get homeLoadFailed;

  /// No description provided for @homeTryLater.
  ///
  /// In ko, this message translates to:
  /// **'잠시 후 다시 시도해주세요'**
  String get homeTryLater;

  /// No description provided for @homeNoLikes.
  ///
  /// In ko, this message translates to:
  /// **'찜한 상품이 없어요'**
  String get homeNoLikes;

  /// No description provided for @homeNoLikesHint.
  ///
  /// In ko, this message translates to:
  /// **'관심있는 상품에 하트를 눌러보세요'**
  String get homeNoLikesHint;

  /// No description provided for @homeSignupBonus.
  ///
  /// In ko, this message translates to:
  /// **'🎉 가입을 환영해요! +500 QTA 가 지급됐어요'**
  String get homeSignupBonus;

  /// No description provided for @homeLoginBonusRemaining.
  ///
  /// In ko, this message translates to:
  /// **' · 오늘 {remaining}회 더 받을 수 있어요'**
  String homeLoginBonusRemaining(int remaining);

  /// No description provided for @homeLoginBonusLimitReached.
  ///
  /// In ko, this message translates to:
  /// **' · 오늘 한도 끝!'**
  String get homeLoginBonusLimitReached;

  /// No description provided for @homeLoginBonus.
  ///
  /// In ko, this message translates to:
  /// **'📅 출석 보너스 +{amount} QTA{tail}'**
  String homeLoginBonus(int amount, String tail);

  /// No description provided for @homeWrite.
  ///
  /// In ko, this message translates to:
  /// **'글쓰기'**
  String get homeWrite;

  /// No description provided for @homeTabHome.
  ///
  /// In ko, this message translates to:
  /// **'홈'**
  String get homeTabHome;

  /// No description provided for @homeTabLikes.
  ///
  /// In ko, this message translates to:
  /// **'찜'**
  String get homeTabLikes;

  /// No description provided for @homeTabChat.
  ///
  /// In ko, this message translates to:
  /// **'채팅'**
  String get homeTabChat;

  /// No description provided for @homeTabMy.
  ///
  /// In ko, this message translates to:
  /// **'내 정보'**
  String get homeTabMy;

  /// No description provided for @homeLocationServiceOff.
  ///
  /// In ko, this message translates to:
  /// **'위치 서비스를 켜주세요 (설정 > 위치)'**
  String get homeLocationServiceOff;

  /// No description provided for @homeLocationPermissionNeeded.
  ///
  /// In ko, this message translates to:
  /// **'위치 권한이 필요해요. 설정에서 허용해주세요.'**
  String get homeLocationPermissionNeeded;

  /// No description provided for @homeRegionVerifiedToast.
  ///
  /// In ko, this message translates to:
  /// **'{region} 인증 완료 🎉'**
  String homeRegionVerifiedToast(String region);

  /// No description provided for @homeMyRegion.
  ///
  /// In ko, this message translates to:
  /// **'내 동네'**
  String get homeMyRegion;

  /// No description provided for @homeLocationFailed.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치를 확인하지 못했어요. 위치 권한과 GPS 를 확인해주세요'**
  String get homeLocationFailed;

  /// No description provided for @homeRegionVerified.
  ///
  /// In ko, this message translates to:
  /// **'동네 인증 완료'**
  String get homeRegionVerified;

  /// No description provided for @homeRegionVerifyNeeded.
  ///
  /// In ko, this message translates to:
  /// **'동네 인증 필요'**
  String get homeRegionVerifyNeeded;

  /// No description provided for @homeRegionVerifiedDesc.
  ///
  /// In ko, this message translates to:
  /// **'{region} · GPS 4km 이내 확인됨'**
  String homeRegionVerifiedDesc(String region);

  /// No description provided for @homeRegionVerifyDesc.
  ///
  /// In ko, this message translates to:
  /// **'{region} · GPS 인증으로 거리순 검색 가능해져요'**
  String homeRegionVerifyDesc(String region);

  /// No description provided for @homeReverify.
  ///
  /// In ko, this message translates to:
  /// **'재인증'**
  String get homeReverify;

  /// No description provided for @homeVerify.
  ///
  /// In ko, this message translates to:
  /// **'인증하기'**
  String get homeVerify;

  /// No description provided for @homeRegionSettingsTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 동네 설정'**
  String get homeRegionSettingsTitle;

  /// No description provided for @homeRegionSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'동, 읍, 면으로 검색 (예: 강남)'**
  String get homeRegionSearchHint;

  /// No description provided for @homeRegionVerifyDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'동네 인증할까요?'**
  String get homeRegionVerifyDialogTitle;

  /// No description provided for @homeRegionVerifyDialogBody.
  ///
  /// In ko, this message translates to:
  /// **'{region} 에 정말 사는지 GPS 로 한 번만 확인하면 거리순 검색을 쓸 수 있어요.\n\n정확한 위치는 서버에 저장하지 않아요.'**
  String homeRegionVerifyDialogBody(String region);

  /// No description provided for @homeVerifyNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 인증'**
  String get homeVerifyNow;

  /// No description provided for @homeRegionSet.
  ///
  /// In ko, this message translates to:
  /// **'{region} 으로 설정되었어요'**
  String homeRegionSet(String region);

  /// No description provided for @homeLoginToUse.
  ///
  /// In ko, this message translates to:
  /// **'로그인 후 이용해주세요'**
  String get homeLoginToUse;

  /// No description provided for @homeMyQr.
  ///
  /// In ko, this message translates to:
  /// **'내 QR 코드'**
  String get homeMyQr;

  /// No description provided for @homeShowQr.
  ///
  /// In ko, this message translates to:
  /// **'상대방에게 QR을 보여주세요'**
  String get homeShowQr;

  /// No description provided for @homeQrDesc.
  ///
  /// In ko, this message translates to:
  /// **'QR을 스캔하면 바로 익명 채팅이 시작돼요 💨'**
  String get homeQrDesc;

  /// No description provided for @homeQrAnonymous.
  ///
  /// In ko, this message translates to:
  /// **'🔐 완전 익명 · 대화 저장 X'**
  String get homeQrAnonymous;

  /// No description provided for @homeQrLinkCopied.
  ///
  /// In ko, this message translates to:
  /// **'QR 링크가 복사되었어요'**
  String get homeQrLinkCopied;

  /// No description provided for @homeQrCopyLink.
  ///
  /// In ko, this message translates to:
  /// **'QR 링크 복사'**
  String get homeQrCopyLink;

  /// No description provided for @homeQrNotEggplant.
  ///
  /// In ko, this message translates to:
  /// **'Eggplant QR이 아니에요'**
  String get homeQrNotEggplant;

  /// No description provided for @homeQrInvalid.
  ///
  /// In ko, this message translates to:
  /// **'잘못된 QR 형식이에요'**
  String get homeQrInvalid;

  /// No description provided for @homeQrOwn.
  ///
  /// In ko, this message translates to:
  /// **'내 QR은 스캔할 수 없어요'**
  String get homeQrOwn;

  /// No description provided for @homeQrChatFailed.
  ///
  /// In ko, this message translates to:
  /// **'채팅방을 열지 못했어요'**
  String get homeQrChatFailed;

  /// No description provided for @homeQrScanGuide.
  ///
  /// In ko, this message translates to:
  /// **'Eggplant QR을 프레임 안에 맞춰주세요'**
  String get homeQrScanGuide;

  /// No description provided for @homeQrScanDesc.
  ///
  /// In ko, this message translates to:
  /// **'스캔 즉시 익명 채팅이 시작돼요'**
  String get homeQrScanDesc;

  /// No description provided for @homeAnonymous.
  ///
  /// In ko, this message translates to:
  /// **'익명'**
  String get homeAnonymous;

  /// No description provided for @homePageNotFound.
  ///
  /// In ko, this message translates to:
  /// **'페이지를 찾을 수 없어요: {error}'**
  String homePageNotFound(String error);

  /// No description provided for @myTabTitle.
  ///
  /// In ko, this message translates to:
  /// **'나의 Eggplant'**
  String get myTabTitle;

  /// No description provided for @myMannerTemp.
  ///
  /// In ko, this message translates to:
  /// **'매너온도 {temp}°C'**
  String myMannerTemp(String temp);

  /// No description provided for @myRegionUnset.
  ///
  /// In ko, this message translates to:
  /// **'동네 미설정'**
  String get myRegionUnset;

  /// No description provided for @myMenuSelling.
  ///
  /// In ko, this message translates to:
  /// **'내가 판매중인 상품'**
  String get myMenuSelling;

  /// No description provided for @myMenuLikes.
  ///
  /// In ko, this message translates to:
  /// **'찜한 상품'**
  String get myMenuLikes;

  /// No description provided for @myMenuChat.
  ///
  /// In ko, this message translates to:
  /// **'채팅'**
  String get myMenuChat;

  /// No description provided for @myMenuProfile.
  ///
  /// In ko, this message translates to:
  /// **'프로필 등록 / 닉네임 수정'**
  String get myMenuProfile;

  /// No description provided for @myMenuProfileSub.
  ///
  /// In ko, this message translates to:
  /// **'채팅·통화에 표시될 내 닉네임 설정'**
  String get myMenuProfileSub;

  /// No description provided for @myMenuRegion.
  ///
  /// In ko, this message translates to:
  /// **'내 동네 설정'**
  String get myMenuRegion;

  /// No description provided for @myRegionNeeded.
  ///
  /// In ko, this message translates to:
  /// **'설정 필요'**
  String get myRegionNeeded;

  /// No description provided for @myMenuQr.
  ///
  /// In ko, this message translates to:
  /// **'내 QR 코드'**
  String get myMenuQr;

  /// No description provided for @myMenuQrSub.
  ///
  /// In ko, this message translates to:
  /// **'친구에게 보여주고 대화 시작'**
  String get myMenuQrSub;

  /// No description provided for @myMenuInvite.
  ///
  /// In ko, this message translates to:
  /// **'친구 초대 (+200 QTA)'**
  String get myMenuInvite;

  /// No description provided for @myMenuInviteSub.
  ///
  /// In ko, this message translates to:
  /// **'친구가 가입할 때 내 닉네임을 입력하면 +200 QTA · 무제한'**
  String get myMenuInviteSub;

  /// No description provided for @myMenuKeyword.
  ///
  /// In ko, this message translates to:
  /// **'키워드 알림'**
  String get myMenuKeyword;

  /// No description provided for @myMenuKeywordSub.
  ///
  /// In ko, this message translates to:
  /// **'관심 키워드 등록하고 새 매물 알림 받기'**
  String get myMenuKeywordSub;

  /// No description provided for @myMenuHidden.
  ///
  /// In ko, this message translates to:
  /// **'숨긴 게시물'**
  String get myMenuHidden;

  /// No description provided for @myMenuHiddenSub.
  ///
  /// In ko, this message translates to:
  /// **'내가 가린 게시물 다시 보기'**
  String get myMenuHiddenSub;

  /// No description provided for @myMenuPrivacy.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 보호'**
  String get myMenuPrivacy;

  /// No description provided for @myMenuPrivacySub.
  ///
  /// In ko, this message translates to:
  /// **'채팅·통화 절대 저장 안 함 · 한 번 흘러간 메시지는 영구 소실'**
  String get myMenuPrivacySub;

  /// No description provided for @myPrivacyDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'🔐 개인정보 보호'**
  String get myPrivacyDialogTitle;

  /// No description provided for @myPrivacyDialogBody.
  ///
  /// In ko, this message translates to:
  /// **'Eggplant는 다음을 수집하지 않아요:\n\n• 전화번호 · 이메일 · 실명\n• 정확한 GPS (동네 인증 시 즉시 폐기)\n• 채팅 내용 (DB 저장 0)\n• 통화 내용 (P2P, 서버 미경유)\n\n채팅은 휘발성이에요. 한 번 흘러간 메시지는 양쪽 기기 어디에도 복원되지 않아요. 앱을 종료하거나 다른 기기로 로그인하면 모든 대화가 빈 상태에서 시작돼요 💨'**
  String get myPrivacyDialogBody;

  /// No description provided for @myMenuAppInfo.
  ///
  /// In ko, this message translates to:
  /// **'앱 정보'**
  String get myMenuAppInfo;

  /// No description provided for @myAppLegalese.
  ///
  /// In ko, this message translates to:
  /// **'© 2026 Eggplant Team\n익명으로 안전한 중고거래'**
  String get myAppLegalese;

  /// No description provided for @myMenuLogout.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get myMenuLogout;

  /// No description provided for @myMenuDeleteAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정 영구 삭제 (탈퇴)'**
  String get myMenuDeleteAccount;

  /// No description provided for @myMenuDeleteAccountSub.
  ///
  /// In ko, this message translates to:
  /// **'한 번 사라지면 복구되지 않아요 · 잔여 QTA·추천 보너스 즉시 회수'**
  String get myMenuDeleteAccountSub;

  /// No description provided for @myStatSelling.
  ///
  /// In ko, this message translates to:
  /// **'판매중'**
  String get myStatSelling;

  /// No description provided for @myStatLikes.
  ///
  /// In ko, this message translates to:
  /// **'찜'**
  String get myStatLikes;

  /// No description provided for @myWalletCopied.
  ///
  /// In ko, this message translates to:
  /// **'지갑주소를 복사했어요. 닉네임·비밀번호 찾기에 붙여넣을 수 있어요.'**
  String get myWalletCopied;

  /// No description provided for @myQtaBalance.
  ///
  /// In ko, this message translates to:
  /// **'QTA 잔액'**
  String get myQtaBalance;

  /// No description provided for @myHistory.
  ///
  /// In ko, this message translates to:
  /// **'내역'**
  String get myHistory;

  /// No description provided for @myHide.
  ///
  /// In ko, this message translates to:
  /// **'가리기'**
  String get myHide;

  /// No description provided for @myShowAll.
  ///
  /// In ko, this message translates to:
  /// **'전체 보기'**
  String get myShowAll;

  /// No description provided for @myCopy.
  ///
  /// In ko, this message translates to:
  /// **'복사'**
  String get myCopy;

  /// No description provided for @myWithdrawRequestBtn.
  ///
  /// In ko, this message translates to:
  /// **'지갑으로 출금 신청'**
  String get myWithdrawRequestBtn;

  /// No description provided for @myWithdrawNeedMin.
  ///
  /// In ko, this message translates to:
  /// **'출금하려면 5,000 QTA 이상 필요해요'**
  String get myWithdrawNeedMin;

  /// No description provided for @myWalletCardNote.
  ///
  /// In ko, this message translates to:
  /// **'닉네임·비밀번호 분실 시 이 지갑주소로 복구할 수 있어요.\n5,000 QTA 부터 5,000 단위로 본인 지갑으로 출금할 수 있어요.'**
  String get myWalletCardNote;

  /// No description provided for @myMaskOnSnack.
  ///
  /// In ko, this message translates to:
  /// **'알림 본문이 가려져요. 잠금화면에서 안전하게 사용하세요 🔒'**
  String get myMaskOnSnack;

  /// No description provided for @myMaskOffSnack.
  ///
  /// In ko, this message translates to:
  /// **'알림 본문이 표시돼요'**
  String get myMaskOffSnack;

  /// No description provided for @myMaskTitle.
  ///
  /// In ko, this message translates to:
  /// **'알림 본문 가리기'**
  String get myMaskTitle;

  /// No description provided for @myMaskSub.
  ///
  /// In ko, this message translates to:
  /// **'잠금화면/푸시 미리보기에 메시지 내용 대신 \"새 메시지가 있어요\" 표시'**
  String get myMaskSub;

  /// No description provided for @myUnverified.
  ///
  /// In ko, this message translates to:
  /// **'미인증'**
  String get myUnverified;

  /// No description provided for @myCtaPhoneOpenTitle.
  ///
  /// In ko, this message translates to:
  /// **'2단계 휴대폰 인증하고 1,000 QTA 받기'**
  String get myCtaPhoneOpenTitle;

  /// No description provided for @myCtaPhoneSoonTitle.
  ///
  /// In ko, this message translates to:
  /// **'2단계 휴대폰 인증 · 곧 열려요'**
  String get myCtaPhoneSoonTitle;

  /// No description provided for @myCtaWalletTitle.
  ///
  /// In ko, this message translates to:
  /// **'1단계 지갑 인증부터 시작하기'**
  String get myCtaWalletTitle;

  /// No description provided for @myCtaPhoneOpenDesc.
  ///
  /// In ko, this message translates to:
  /// **'마지막 단계예요! 인증해도 채팅·통화는 익명 그대로예요.'**
  String get myCtaPhoneOpenDesc;

  /// No description provided for @myCtaPhoneSoonDesc.
  ///
  /// In ko, this message translates to:
  /// **'1단계 완료! 휴대폰 인증이 열리면 마치고 1,000 QTA 를 받으세요.'**
  String get myCtaPhoneSoonDesc;

  /// No description provided for @myCtaWalletDesc.
  ///
  /// In ko, this message translates to:
  /// **'지갑·휴대폰 인증을 모두 마치면 1,000 QTA 를 드려요.'**
  String get myCtaWalletDesc;

  /// No description provided for @myBrowseCreditedTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 채굴 보너스 받았어요!'**
  String get myBrowseCreditedTitle;

  /// No description provided for @myBrowseTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 둘러보기 채굴'**
  String get myBrowseTitle;

  /// No description provided for @myBrowseCreditedSub.
  ///
  /// In ko, this message translates to:
  /// **'내일 자정(KST)에 다시 시작돼요.'**
  String get myBrowseCreditedSub;

  /// No description provided for @myBrowseSub.
  ///
  /// In ko, this message translates to:
  /// **'상품 {threshold}개 보면 +10 QTA 적립'**
  String myBrowseSub(int threshold);

  /// No description provided for @myBrowseStart.
  ///
  /// In ko, this message translates to:
  /// **'홈 탭에서 상품을 둘러보세요 🛍️'**
  String get myBrowseStart;

  /// No description provided for @myBrowseRemaining.
  ///
  /// In ko, this message translates to:
  /// **'{count}개 더 보면 +10 QTA!'**
  String myBrowseRemaining(int count);

  /// No description provided for @myBrowseSoon.
  ///
  /// In ko, this message translates to:
  /// **'곧 적립돼요…'**
  String get myBrowseSoon;

  /// No description provided for @myBrowseLink.
  ///
  /// In ko, this message translates to:
  /// **'채굴 내역 보기 · 상품 등록하면 가격의 10% 채굴'**
  String get myBrowseLink;

  /// No description provided for @myUserNotFound.
  ///
  /// In ko, this message translates to:
  /// **'사용자를 찾을 수 없어요'**
  String get myUserNotFound;

  /// No description provided for @myServerSlow.
  ///
  /// In ko, this message translates to:
  /// **'서버 응답이 늦어요. 잠시 후 다시 시도해주세요 🕐'**
  String get myServerSlow;

  /// No description provided for @myLoadError.
  ///
  /// In ko, this message translates to:
  /// **'불러오는 중 오류가 발생했어요'**
  String get myLoadError;

  /// No description provided for @myMoreReviewsSlow.
  ///
  /// In ko, this message translates to:
  /// **'추가 리뷰 로딩이 늦어요. 잠시 후 다시 시도해주세요 🕐'**
  String get myMoreReviewsSlow;

  /// No description provided for @myThisUser.
  ///
  /// In ko, this message translates to:
  /// **'이 사용자'**
  String get myThisUser;

  /// No description provided for @myBlockConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'차단할까요?'**
  String get myBlockConfirmTitle;

  /// No description provided for @myBlockConfirmBody.
  ///
  /// In ko, this message translates to:
  /// **'{nick}님을 차단하면 서로의 게시글과 채팅이 모두 안 보이게 돼요. 언제든 해제할 수 있어요.'**
  String myBlockConfirmBody(String nick);

  /// No description provided for @myBlock.
  ///
  /// In ko, this message translates to:
  /// **'차단'**
  String get myBlock;

  /// No description provided for @myBlockedSnack.
  ///
  /// In ko, this message translates to:
  /// **'{nick}님을 차단했어요'**
  String myBlockedSnack(String nick);

  /// No description provided for @myUnblockConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'차단 해제할까요?'**
  String get myUnblockConfirmTitle;

  /// No description provided for @myUnblockConfirmBody.
  ///
  /// In ko, this message translates to:
  /// **'{nick}님을 다시 볼 수 있게 돼요.'**
  String myUnblockConfirmBody(String nick);

  /// No description provided for @myUnblockShort.
  ///
  /// In ko, this message translates to:
  /// **'해제'**
  String get myUnblockShort;

  /// No description provided for @myUnblockedSnack.
  ///
  /// In ko, this message translates to:
  /// **'차단을 해제했어요'**
  String get myUnblockedSnack;

  /// No description provided for @myReportSpam.
  ///
  /// In ko, this message translates to:
  /// **'스팸·광고'**
  String get myReportSpam;

  /// No description provided for @myReportFraud.
  ///
  /// In ko, this message translates to:
  /// **'사기 의심'**
  String get myReportFraud;

  /// No description provided for @myReportAbuse.
  ///
  /// In ko, this message translates to:
  /// **'욕설·비방'**
  String get myReportAbuse;

  /// No description provided for @myReportInappropriate.
  ///
  /// In ko, this message translates to:
  /// **'부적절한 내용'**
  String get myReportInappropriate;

  /// No description provided for @myReportFake.
  ///
  /// In ko, this message translates to:
  /// **'허위 매물'**
  String get myReportFake;

  /// No description provided for @myReportOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get myReportOther;

  /// No description provided for @myReportTitle.
  ///
  /// In ko, this message translates to:
  /// **'신고 사유를 골라주세요'**
  String get myReportTitle;

  /// No description provided for @myReportDesc.
  ///
  /// In ko, this message translates to:
  /// **'여러 명이 같은 사유로 신고하면 운영팀이 검토해요.'**
  String get myReportDesc;

  /// No description provided for @myReportDetailHint.
  ///
  /// In ko, this message translates to:
  /// **'추가 설명 (선택)'**
  String get myReportDetailHint;

  /// No description provided for @myReportDone.
  ///
  /// In ko, this message translates to:
  /// **'신고를 접수했어요'**
  String get myReportDone;

  /// No description provided for @myReportSubmit.
  ///
  /// In ko, this message translates to:
  /// **'신고하기'**
  String get myReportSubmit;

  /// No description provided for @myProfileMine.
  ///
  /// In ko, this message translates to:
  /// **'내 프로필'**
  String get myProfileMine;

  /// No description provided for @myProfileSeller.
  ///
  /// In ko, this message translates to:
  /// **'판매자 정보'**
  String get myProfileSeller;

  /// No description provided for @myUnblockMenu.
  ///
  /// In ko, this message translates to:
  /// **'차단 해제'**
  String get myUnblockMenu;

  /// No description provided for @myBlockMenu.
  ///
  /// In ko, this message translates to:
  /// **'차단하기'**
  String get myBlockMenu;

  /// No description provided for @myTopPraise.
  ///
  /// In ko, this message translates to:
  /// **'많이 받은 매너 칭찬'**
  String get myTopPraise;

  /// No description provided for @myReceivedReviews.
  ///
  /// In ko, this message translates to:
  /// **'받은 거래 후기'**
  String get myReceivedReviews;

  /// No description provided for @myNoReviews.
  ///
  /// In ko, this message translates to:
  /// **'아직 받은 후기가 없어요'**
  String get myNoReviews;

  /// No description provided for @myAnonNickname.
  ///
  /// In ko, this message translates to:
  /// **'익명가지'**
  String get myAnonNickname;

  /// No description provided for @myMannerLabel.
  ///
  /// In ko, this message translates to:
  /// **'매너온도'**
  String get myMannerLabel;

  /// No description provided for @myReviewsLabel.
  ///
  /// In ko, this message translates to:
  /// **'받은 후기'**
  String get myReviewsLabel;

  /// No description provided for @myRatingGood.
  ///
  /// In ko, this message translates to:
  /// **'좋아요'**
  String get myRatingGood;

  /// No description provided for @myRatingSoso.
  ///
  /// In ko, this message translates to:
  /// **'보통이에요'**
  String get myRatingSoso;

  /// No description provided for @myRatingBad.
  ///
  /// In ko, this message translates to:
  /// **'별로예요'**
  String get myRatingBad;

  /// No description provided for @myAgoMinutes.
  ///
  /// In ko, this message translates to:
  /// **'{n}분 전'**
  String myAgoMinutes(int n);

  /// No description provided for @myAgoHours.
  ///
  /// In ko, this message translates to:
  /// **'{n}시간 전'**
  String myAgoHours(int n);

  /// No description provided for @myAgoDays.
  ///
  /// In ko, this message translates to:
  /// **'{n}일 전'**
  String myAgoDays(int n);

  /// No description provided for @myAgoWeeks.
  ///
  /// In ko, this message translates to:
  /// **'{n}주 전'**
  String myAgoWeeks(int n);

  /// No description provided for @myAgoMonths.
  ///
  /// In ko, this message translates to:
  /// **'{n}개월 전'**
  String myAgoMonths(int n);

  /// No description provided for @myPhotoLoadFail.
  ///
  /// In ko, this message translates to:
  /// **'사진을 불러올 수 없어요. 권한을 확인하고 다시 시도해주세요'**
  String get myPhotoLoadFail;

  /// No description provided for @myNicknameEmpty.
  ///
  /// In ko, this message translates to:
  /// **'닉네임을 입력해주세요'**
  String get myNicknameEmpty;

  /// No description provided for @myNicknameTooShort.
  ///
  /// In ko, this message translates to:
  /// **'닉네임은 2자 이상이어야 해요'**
  String get myNicknameTooShort;

  /// No description provided for @myNicknameTooLong.
  ///
  /// In ko, this message translates to:
  /// **'닉네임은 12자 이하여야 해요'**
  String get myNicknameTooLong;

  /// No description provided for @myProfileSaved.
  ///
  /// In ko, this message translates to:
  /// **'프로필이 저장됐어요. 채팅·통화에 바로 반영돼요 ✨'**
  String get myProfileSaved;

  /// No description provided for @myProfilePhotoSaved.
  ///
  /// In ko, this message translates to:
  /// **'프로필 사진이 저장됐어요 ✨'**
  String get myProfilePhotoSaved;

  /// No description provided for @myProfileEditTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로필 등록'**
  String get myProfileEditTitle;

  /// No description provided for @myPhotoChange.
  ///
  /// In ko, this message translates to:
  /// **'사진 변경'**
  String get myPhotoChange;

  /// No description provided for @myPhotoAdd.
  ///
  /// In ko, this message translates to:
  /// **'사진 등록'**
  String get myPhotoAdd;

  /// No description provided for @myPhotoReset.
  ///
  /// In ko, this message translates to:
  /// **'기본 가지로 변경'**
  String get myPhotoReset;

  /// No description provided for @myNicknameIntro.
  ///
  /// In ko, this message translates to:
  /// **'채팅·통화에 표시될 내 닉네임을 설정하세요'**
  String get myNicknameIntro;

  /// No description provided for @myNicknameLabel.
  ///
  /// In ko, this message translates to:
  /// **'닉네임'**
  String get myNicknameLabel;

  /// No description provided for @myNicknameHint.
  ///
  /// In ko, this message translates to:
  /// **'2~12자, 한글/영문/숫자'**
  String get myNicknameHint;

  /// No description provided for @myNicknameGuideTitle.
  ///
  /// In ko, this message translates to:
  /// **'닉네임 안내'**
  String get myNicknameGuideTitle;

  /// No description provided for @myNicknameGuideBody.
  ///
  /// In ko, this message translates to:
  /// **'• 변경 즉시 채팅·통화에 반영돼요\n• 다른 사용자와 중복될 수 없어요\n• 본인인증과 무관하게 닉네임만 사용해요'**
  String get myNicknameGuideBody;

  /// No description provided for @mySaveButton.
  ///
  /// In ko, this message translates to:
  /// **'저장하기'**
  String get mySaveButton;

  /// No description provided for @myWdNeedWalletTitle.
  ///
  /// In ko, this message translates to:
  /// **'1단계 지갑 인증이 필요해요'**
  String get myWdNeedWalletTitle;

  /// No description provided for @myWdNeedWalletBody.
  ///
  /// In ko, this message translates to:
  /// **'출금한 QTA 는 인증한 지갑으로 송금돼요.\n본사 지갑이 보낸 수량을 입력해 지갑 주인임을 확인해주세요.'**
  String get myWdNeedWalletBody;

  /// No description provided for @myWdNeedPhoneTitle.
  ///
  /// In ko, this message translates to:
  /// **'2단계 휴대폰 인증이 필요해요'**
  String get myWdNeedPhoneTitle;

  /// No description provided for @myWdPreparingTitle.
  ///
  /// In ko, this message translates to:
  /// **'출금은 준비 중이에요'**
  String get myWdPreparingTitle;

  /// No description provided for @myWdNeedPhoneBody.
  ///
  /// In ko, this message translates to:
  /// **'1인 1계정 보장을 위해 출금 전에 휴대폰 인증이 필요해요.\n마치면 1,000 QTA 도 드려요.'**
  String get myWdNeedPhoneBody;

  /// No description provided for @myWdPreparingBody.
  ///
  /// In ko, this message translates to:
  /// **'출금에는 휴대폰 인증이 필요한데, 준비하고 있어요.\n열리면 앱 업데이트로 알려드릴게요. 그동안 QTA 는 그대로 쌓여요.'**
  String get myWdPreparingBody;

  /// No description provided for @myWdNoWallet.
  ///
  /// In ko, this message translates to:
  /// **'지갑 주소가 등록되지 않았어요'**
  String get myWdNoWallet;

  /// No description provided for @myWdInsufficientMin.
  ///
  /// In ko, this message translates to:
  /// **'잔액이 부족해요. 최소 {min} QTA 부터 신청할 수 있어요.'**
  String myWdInsufficientMin(String min);

  /// No description provided for @myWdConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'출금 신청'**
  String get myWdConfirmTitle;

  /// No description provided for @myWdConfirmBody.
  ///
  /// In ko, this message translates to:
  /// **'{amount} QTA 를\n{wallet}\n로 출금 신청할까요?\n\n신청 즉시 잔액에서 차감되며, 운영자가 1~3일 내에 송금 처리합니다.'**
  String myWdConfirmBody(String amount, String wallet);

  /// No description provided for @myWdApply.
  ///
  /// In ko, this message translates to:
  /// **'신청'**
  String get myWdApply;

  /// No description provided for @myWdRequested.
  ///
  /// In ko, this message translates to:
  /// **'출금 신청 완료 — 처리되면 알려드릴게요'**
  String get myWdRequested;

  /// No description provided for @myWdCancelTitle.
  ///
  /// In ko, this message translates to:
  /// **'신청 취소'**
  String get myWdCancelTitle;

  /// No description provided for @myWdCancelBody.
  ///
  /// In ko, this message translates to:
  /// **'{amount} QTA 출금 신청을 취소할까요?\n취소 즉시 잔액으로 환불돼요.'**
  String myWdCancelBody(String amount);

  /// No description provided for @myWdNo.
  ///
  /// In ko, this message translates to:
  /// **'아니요'**
  String get myWdNo;

  /// No description provided for @myWdCancelDo.
  ///
  /// In ko, this message translates to:
  /// **'취소하기'**
  String get myWdCancelDo;

  /// No description provided for @myWdCancelled.
  ///
  /// In ko, this message translates to:
  /// **'취소 및 환불 완료'**
  String get myWdCancelled;

  /// No description provided for @myDateTimeFormat.
  ///
  /// In ko, this message translates to:
  /// **'M월 d일 HH:mm'**
  String get myDateTimeFormat;

  /// No description provided for @myWdTitle.
  ///
  /// In ko, this message translates to:
  /// **'QTA 출금'**
  String get myWdTitle;

  /// No description provided for @myWdAvailable.
  ///
  /// In ko, this message translates to:
  /// **'출금 가능 잔액'**
  String get myWdAvailable;

  /// No description provided for @myWdRuleShort.
  ///
  /// In ko, this message translates to:
  /// **'5,000 QTA 부터 5,000 단위로 신청'**
  String get myWdRuleShort;

  /// No description provided for @myWdPendingStatus.
  ///
  /// In ko, this message translates to:
  /// **'{amount} QTA 출금이 {status} 이에요'**
  String myWdPendingStatus(String amount, String status);

  /// No description provided for @myWdRequestBtn.
  ///
  /// In ko, this message translates to:
  /// **'출금 신청하기'**
  String get myWdRequestBtn;

  /// No description provided for @myWdInsufficient.
  ///
  /// In ko, this message translates to:
  /// **'잔액이 부족해요'**
  String get myWdInsufficient;

  /// No description provided for @myWdHistory.
  ///
  /// In ko, this message translates to:
  /// **'신청 내역'**
  String get myWdHistory;

  /// No description provided for @myWdHistoryEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 출금 신청 내역이 없어요'**
  String get myWdHistoryEmpty;

  /// No description provided for @myWdNotice.
  ///
  /// In ko, this message translates to:
  /// **'출금은 가입 시 등록된 퀀타리움 지갑주소로만 송금돼요. 운영자가 1~3일 안에 처리합니다. 처리 시작 후엔 취소할 수 없어요.'**
  String get myWdNotice;

  /// No description provided for @myWdTxCopied.
  ///
  /// In ko, this message translates to:
  /// **'트랜잭션 해시를 복사했어요'**
  String get myWdTxCopied;

  /// No description provided for @myWdReason.
  ///
  /// In ko, this message translates to:
  /// **'사유: {reason}'**
  String myWdReason(String reason);

  /// No description provided for @myWdAmountTitle.
  ///
  /// In ko, this message translates to:
  /// **'출금 금액 입력'**
  String get myWdAmountTitle;

  /// No description provided for @myWdAmountRule.
  ///
  /// In ko, this message translates to:
  /// **'{min} QTA 부터 {unit} QTA 단위로 신청 가능'**
  String myWdAmountRule(String min, String unit);

  /// No description provided for @myWdMinBtn.
  ///
  /// In ko, this message translates to:
  /// **'최소 {amount}'**
  String myWdMinBtn(String amount);

  /// No description provided for @myWdMaxBtn.
  ///
  /// In ko, this message translates to:
  /// **'전액 {amount}'**
  String myWdMaxBtn(String amount);

  /// No description provided for @myWdToWallet.
  ///
  /// In ko, this message translates to:
  /// **'받는 지갑'**
  String get myWdToWallet;

  /// No description provided for @myWdSubmitAmount.
  ///
  /// In ko, this message translates to:
  /// **'{amount} QTA 신청하기'**
  String myWdSubmitAmount(String amount);

  /// No description provided for @myLedgerTitle.
  ///
  /// In ko, this message translates to:
  /// **'QTA 내역'**
  String get myLedgerTitle;

  /// No description provided for @myLedgerWithdraw.
  ///
  /// In ko, this message translates to:
  /// **'출금'**
  String get myLedgerWithdraw;

  /// No description provided for @myLedgerBalance.
  ///
  /// In ko, this message translates to:
  /// **'현재 잔액'**
  String get myLedgerBalance;

  /// No description provided for @myLedgerRecent.
  ///
  /// In ko, this message translates to:
  /// **'최근 내역'**
  String get myLedgerRecent;

  /// No description provided for @myLedgerEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 내역이 없어요. 출석·거래로 QTA를 적립해보세요!'**
  String get myLedgerEmpty;

  /// No description provided for @myRuleTitle.
  ///
  /// In ko, this message translates to:
  /// **'QTA 적립 규칙'**
  String get myRuleTitle;

  /// No description provided for @myRuleVerify.
  ///
  /// In ko, this message translates to:
  /// **'지갑·휴대폰 인증 완료 시 +1,000 QTA (1회)'**
  String get myRuleVerify;

  /// No description provided for @myRuleListing.
  ///
  /// In ko, this message translates to:
  /// **'상품 등록 시 가격의 10%를 QTA로 채굴 (1 QTA = {rate}원) · 삭제하면 차감'**
  String myRuleListing(int rate);

  /// No description provided for @myRuleLogin.
  ///
  /// In ko, this message translates to:
  /// **'로그인할 때마다 +10 QTA · 하루 3번까지'**
  String get myRuleLogin;

  /// No description provided for @myRuleTrade.
  ///
  /// In ko, this message translates to:
  /// **'거래완료 시 판매자·구매자 각각 +10 QTA'**
  String get myRuleTrade;

  /// No description provided for @myRuleWithdraw.
  ///
  /// In ko, this message translates to:
  /// **'5,000 QTA 부터 5,000 단위로 지갑 출금 가능'**
  String get myRuleWithdraw;

  /// No description provided for @myMiningLoadFail.
  ///
  /// In ko, this message translates to:
  /// **'채굴 내역을 불러오지 못했어요. 당겨서 다시 시도해주세요'**
  String get myMiningLoadFail;

  /// No description provided for @myMiningTitle.
  ///
  /// In ko, this message translates to:
  /// **'채굴 내역'**
  String get myMiningTitle;

  /// No description provided for @myMiningTotalLabel.
  ///
  /// In ko, this message translates to:
  /// **'지금까지 채굴한 QTA'**
  String get myMiningTotalLabel;

  /// No description provided for @myMiningTotalSub.
  ///
  /// In ko, this message translates to:
  /// **'상품 등록 채굴 {listing} QTA · 약 {money}'**
  String myMiningTotalSub(String listing, String money);

  /// No description provided for @myMiningRule.
  ///
  /// In ko, this message translates to:
  /// **'⛏️ 상품을 올리면 가격의 {percent}%를 QTA로 채굴해요 (1 QTA = {rate}원)\n   예) {examplePrice} 상품 → +{exampleQta} QTA\n• 상품 1개 최대 {maxPerListing} QTA · 하루 최대 {maxPerDay} QTA\n• 가격을 내리면 차액만큼, 상품을 삭제하면 받은 만큼 차감돼요\n• 판매 완료된 상품은 차감되지 않아요 (삭제하면 차감)'**
  String myMiningRule(int percent, int rate, String examplePrice,
      String exampleQta, String maxPerListing, String maxPerDay);

  /// No description provided for @myMiningRecords.
  ///
  /// In ko, this message translates to:
  /// **'채굴 기록'**
  String get myMiningRecords;

  /// No description provided for @myMiningEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 채굴 기록이 없어요. 상품을 올려 QTA를 채굴해보세요!'**
  String get myMiningEmpty;

  /// No description provided for @myRefLoadFail.
  ///
  /// In ko, this message translates to:
  /// **'내 초대 내역을 불러올 수 없어요.'**
  String get myRefLoadFail;

  /// No description provided for @myRefNetworkError.
  ///
  /// In ko, this message translates to:
  /// **'네트워크 오류: 잠시 후 다시 시도해주세요.'**
  String get myRefNetworkError;

  /// No description provided for @myRefTitle.
  ///
  /// In ko, this message translates to:
  /// **'친구 초대'**
  String get myRefTitle;

  /// No description provided for @myRefHeadline.
  ///
  /// In ko, this message translates to:
  /// **'친구가 가입할 때\n내 닉네임을 입력하면 +200 QTA'**
  String get myRefHeadline;

  /// No description provided for @myRefCopyNick.
  ///
  /// In ko, this message translates to:
  /// **'닉네임 복사'**
  String get myRefCopyNick;

  /// No description provided for @myRefNickCopied.
  ///
  /// In ko, this message translates to:
  /// **'닉네임을 복사했어요'**
  String get myRefNickCopied;

  /// No description provided for @myRefOncePerPerson.
  ///
  /// In ko, this message translates to:
  /// **'한 사람당 1번만 처리되지만, 내가 초대할 수 있는 친구 수에는 제한이 없어요.'**
  String get myRefOncePerPerson;

  /// No description provided for @myRefStatValid.
  ///
  /// In ko, this message translates to:
  /// **'유효한 초대'**
  String get myRefStatValid;

  /// No description provided for @myRefStatEarned.
  ///
  /// In ko, this message translates to:
  /// **'누적 적립'**
  String get myRefStatEarned;

  /// No description provided for @myRefStatClawed.
  ///
  /// In ko, this message translates to:
  /// **'회수 (탈퇴)'**
  String get myRefStatClawed;

  /// No description provided for @myRefRuleTitle.
  ///
  /// In ko, this message translates to:
  /// **'친구 초대 보너스 규칙'**
  String get myRefRuleTitle;

  /// No description provided for @myRefRuleBody.
  ///
  /// In ko, this message translates to:
  /// **'• 친구 1명당 +200 QTA · 무제한\n• 친구가 회원가입 마지막 칸에 내 닉네임 입력\n• 친구가 탈퇴하면 그 200 QTA는 즉시 회수돼요\n• 자기 자신은 추천인이 될 수 없어요'**
  String get myRefRuleBody;

  /// No description provided for @myRefListTitle.
  ///
  /// In ko, this message translates to:
  /// **'내가 초대한 친구'**
  String get myRefListTitle;

  /// No description provided for @myRefEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 초대한 친구가 없어요'**
  String get myRefEmpty;

  /// No description provided for @myRefDeletedFriend.
  ///
  /// In ko, this message translates to:
  /// **'(탈퇴한 친구)'**
  String get myRefDeletedFriend;

  /// No description provided for @myRefUnknown.
  ///
  /// In ko, this message translates to:
  /// **'(알 수 없음)'**
  String get myRefUnknown;

  /// No description provided for @myRefClawedBadge.
  ///
  /// In ko, this message translates to:
  /// **'−200 QTA 회수'**
  String get myRefClawedBadge;

  /// No description provided for @myReasonSignup.
  ///
  /// In ko, this message translates to:
  /// **'가입 보너스'**
  String get myReasonSignup;

  /// No description provided for @myReasonVerifyBonus.
  ///
  /// In ko, this message translates to:
  /// **'인증 완료 보너스'**
  String get myReasonVerifyBonus;

  /// No description provided for @myReasonLoginDaily.
  ///
  /// In ko, this message translates to:
  /// **'출석 보너스'**
  String get myReasonLoginDaily;

  /// No description provided for @myReasonTradeSeller.
  ///
  /// In ko, this message translates to:
  /// **'판매 완료 보상'**
  String get myReasonTradeSeller;

  /// No description provided for @myReasonTradeBuyer.
  ///
  /// In ko, this message translates to:
  /// **'구매 완료 보상'**
  String get myReasonTradeBuyer;

  /// No description provided for @myReasonWithdrawal.
  ///
  /// In ko, this message translates to:
  /// **'출금 신청'**
  String get myReasonWithdrawal;

  /// No description provided for @myReasonWithdrawalRefund.
  ///
  /// In ko, this message translates to:
  /// **'출금 취소·환불'**
  String get myReasonWithdrawalRefund;

  /// No description provided for @myReasonListingReward.
  ///
  /// In ko, this message translates to:
  /// **'상품 등록 채굴'**
  String get myReasonListingReward;

  /// No description provided for @myReasonListingAdjust.
  ///
  /// In ko, this message translates to:
  /// **'가격 인하 차감'**
  String get myReasonListingAdjust;

  /// No description provided for @myReasonListingClawback.
  ///
  /// In ko, this message translates to:
  /// **'상품 삭제 차감'**
  String get myReasonListingClawback;

  /// No description provided for @myReasonMiningListing.
  ///
  /// In ko, this message translates to:
  /// **'상품 7일 유지 채굴'**
  String get myReasonMiningListing;

  /// No description provided for @myReasonMiningBrowse.
  ///
  /// In ko, this message translates to:
  /// **'둘러보기 채굴'**
  String get myReasonMiningBrowse;

  /// No description provided for @myWdStatusRequested.
  ///
  /// In ko, this message translates to:
  /// **'대기 중'**
  String get myWdStatusRequested;

  /// No description provided for @myWdStatusProcessing.
  ///
  /// In ko, this message translates to:
  /// **'송금 중'**
  String get myWdStatusProcessing;

  /// No description provided for @myWdStatusCompleted.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get myWdStatusCompleted;

  /// No description provided for @myWdStatusRejected.
  ///
  /// In ko, this message translates to:
  /// **'거절·환불'**
  String get myWdStatusRejected;

  /// No description provided for @myQtaLoadFail.
  ///
  /// In ko, this message translates to:
  /// **'QTA 잔액을 불러오지 못했어요'**
  String get myQtaLoadFail;

  /// No description provided for @myWdLoadFail.
  ///
  /// In ko, this message translates to:
  /// **'출금 내역을 불러오지 못했어요'**
  String get myWdLoadFail;

  /// No description provided for @myWdErrMin.
  ///
  /// In ko, this message translates to:
  /// **'최소 {min} QTA 부터 신청할 수 있어요'**
  String myWdErrMin(String min);

  /// No description provided for @myWdErrUnit.
  ///
  /// In ko, this message translates to:
  /// **'{unit} QTA 단위로만 신청할 수 있어요'**
  String myWdErrUnit(String unit);

  /// No description provided for @myWdErrBalance.
  ///
  /// In ko, this message translates to:
  /// **'QTA 잔액이 부족해요'**
  String get myWdErrBalance;

  /// No description provided for @myWdErrPending.
  ///
  /// In ko, this message translates to:
  /// **'진행 중인 신청이 있어요. 처리되면 다시 시도해주세요.'**
  String get myWdErrPending;

  /// No description provided for @myWdErrRequestFail.
  ///
  /// In ko, this message translates to:
  /// **'출금 신청에 실패했어요'**
  String get myWdErrRequestFail;

  /// No description provided for @myWdUserCancelled.
  ///
  /// In ko, this message translates to:
  /// **'사용자 취소'**
  String get myWdUserCancelled;

  /// No description provided for @myWdErrCancelFail.
  ///
  /// In ko, this message translates to:
  /// **'취소에 실패했어요'**
  String get myWdErrCancelFail;

  /// No description provided for @myVerifyLabelNone.
  ///
  /// In ko, this message translates to:
  /// **'미인증'**
  String get myVerifyLabelNone;

  /// No description provided for @myVerifyLabelIdentity.
  ///
  /// In ko, this message translates to:
  /// **'본인인증 완료'**
  String get myVerifyLabelIdentity;

  /// No description provided for @myVerifyLabelBank.
  ///
  /// In ko, this message translates to:
  /// **'출금 인증 완료'**
  String get myVerifyLabelBank;

  /// No description provided for @myMenuLanguage.
  ///
  /// In ko, this message translates to:
  /// **'언어'**
  String get myMenuLanguage;

  /// No description provided for @myRuleVerifyRequired.
  ///
  /// In ko, this message translates to:
  /// **'채굴한 QTA는 바로 쌓여요 · 거래완료와 출금은 휴대폰 인증 후에 할 수 있어요'**
  String get myRuleVerifyRequired;

  /// No description provided for @productCategoryAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get productCategoryAll;

  /// No description provided for @productCategoryDigital.
  ///
  /// In ko, this message translates to:
  /// **'디지털기기'**
  String get productCategoryDigital;

  /// No description provided for @productCategoryAppliance.
  ///
  /// In ko, this message translates to:
  /// **'생활가전'**
  String get productCategoryAppliance;

  /// No description provided for @productCategoryFurniture.
  ///
  /// In ko, this message translates to:
  /// **'가구/인테리어'**
  String get productCategoryFurniture;

  /// No description provided for @productCategoryClothing.
  ///
  /// In ko, this message translates to:
  /// **'의류'**
  String get productCategoryClothing;

  /// No description provided for @productCategoryBeauty.
  ///
  /// In ko, this message translates to:
  /// **'뷰티/미용'**
  String get productCategoryBeauty;

  /// No description provided for @productCategoryBook.
  ///
  /// In ko, this message translates to:
  /// **'도서/티켓'**
  String get productCategoryBook;

  /// No description provided for @productCategorySports.
  ///
  /// In ko, this message translates to:
  /// **'스포츠/레저'**
  String get productCategorySports;

  /// No description provided for @productCategoryHobby.
  ///
  /// In ko, this message translates to:
  /// **'취미/게임'**
  String get productCategoryHobby;

  /// No description provided for @productCategoryKids.
  ///
  /// In ko, this message translates to:
  /// **'유아동'**
  String get productCategoryKids;

  /// No description provided for @productCategoryPet.
  ///
  /// In ko, this message translates to:
  /// **'반려동물'**
  String get productCategoryPet;

  /// No description provided for @productCategoryFood.
  ///
  /// In ko, this message translates to:
  /// **'식품'**
  String get productCategoryFood;

  /// No description provided for @productCategoryEtc.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get productCategoryEtc;

  /// No description provided for @productAnonymousSeller.
  ///
  /// In ko, this message translates to:
  /// **'익명가지'**
  String get productAnonymousSeller;

  /// No description provided for @productTimeJustNow.
  ///
  /// In ko, this message translates to:
  /// **'방금 전'**
  String get productTimeJustNow;

  /// No description provided for @productTimeMinutesAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}분 전'**
  String productTimeMinutesAgo(int n);

  /// No description provided for @productTimeHoursAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}시간 전'**
  String productTimeHoursAgo(int n);

  /// No description provided for @productTimeDaysAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}일 전'**
  String productTimeDaysAgo(int n);

  /// No description provided for @productTimeMonthsAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}개월 전'**
  String productTimeMonthsAgo(int n);

  /// No description provided for @productTimeYearsAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}년 전'**
  String productTimeYearsAgo(int n);

  /// No description provided for @productStatusSale.
  ///
  /// In ko, this message translates to:
  /// **'판매중'**
  String get productStatusSale;

  /// No description provided for @productStatusReserved.
  ///
  /// In ko, this message translates to:
  /// **'예약중'**
  String get productStatusReserved;

  /// No description provided for @productStatusSold.
  ///
  /// In ko, this message translates to:
  /// **'거래완료'**
  String get productStatusSold;

  /// No description provided for @productReviewGood.
  ///
  /// In ko, this message translates to:
  /// **'좋아요'**
  String get productReviewGood;

  /// No description provided for @productReviewBad.
  ///
  /// In ko, this message translates to:
  /// **'별로예요'**
  String get productReviewBad;

  /// No description provided for @productReviewSoso.
  ///
  /// In ko, this message translates to:
  /// **'보통이에요'**
  String get productReviewSoso;

  /// No description provided for @productStatusSoldOut.
  ///
  /// In ko, this message translates to:
  /// **'판매완료'**
  String get productStatusSoldOut;

  /// No description provided for @productDetailLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'상품 정보를 불러오지 못했습니다.'**
  String get productDetailLoadFailed;

  /// No description provided for @productDetailTimeout.
  ///
  /// In ko, this message translates to:
  /// **'서버 응답이 늦어요. 잠시 후 다시 시도해주세요.'**
  String get productDetailTimeout;

  /// No description provided for @productQtaConfirmUnavailableTitle.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 인증 준비 중이에요'**
  String get productQtaConfirmUnavailableTitle;

  /// No description provided for @productQtaConfirmUnavailableBody.
  ///
  /// In ko, this message translates to:
  /// **'거래완료는 휴대폰 인증을 마친 뒤에 할 수 있어요.\n휴대폰 인증이 열리면 바로 완료할 수 있게 안내해 드릴게요.'**
  String get productQtaConfirmUnavailableBody;

  /// No description provided for @productConfirmVerifyTitle.
  ///
  /// In ko, this message translates to:
  /// **'거래완료 전에 휴대폰 인증이 필요해요'**
  String get productConfirmVerifyTitle;

  /// No description provided for @productConfirmVerifyBody.
  ///
  /// In ko, this message translates to:
  /// **'모든 거래는 휴대폰 인증을 마쳐야 최종 완료돼요 (1인 1계정 보장).\n그동안 채굴한 QTA는 그대로 쌓여 있어요. 인증해도 채팅·통화는 익명 그대로예요.'**
  String get productConfirmVerifyBody;

  /// No description provided for @productConfirmDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'거래를 확인할까요?'**
  String get productConfirmDialogTitle;

  /// No description provided for @productConfirmDialogBodyQta.
  ///
  /// In ko, this message translates to:
  /// **'확인하면 {qta} 가 판매자에게 결제돼요.\n물건을 받은 뒤에 확인해주세요.'**
  String productConfirmDialogBodyQta(String qta);

  /// No description provided for @productConfirmDialogBody.
  ///
  /// In ko, this message translates to:
  /// **'물건을 받은 뒤에 확인해주세요.\n확인하면 거래가 완료되고 후기를 남길 수 있어요.'**
  String get productConfirmDialogBody;

  /// No description provided for @productConfirmDeal.
  ///
  /// In ko, this message translates to:
  /// **'거래 확인'**
  String get productConfirmDeal;

  /// No description provided for @productConfirmDone.
  ///
  /// In ko, this message translates to:
  /// **'거래를 확인했어요 🍆'**
  String get productConfirmDone;

  /// No description provided for @productBuyerAssignedTitle.
  ///
  /// In ko, this message translates to:
  /// **'판매자가 회원님을 구매자로 지정했어요'**
  String get productBuyerAssignedTitle;

  /// No description provided for @productBuyerAssignedBodyQta.
  ///
  /// In ko, this message translates to:
  /// **'거래를 확인하면 {qta} 가 결제돼요.'**
  String productBuyerAssignedBodyQta(String qta);

  /// No description provided for @productBuyerAssignedBody.
  ///
  /// In ko, this message translates to:
  /// **'물건을 받으셨다면 거래를 확인해주세요.'**
  String get productBuyerAssignedBody;

  /// No description provided for @productConfirmDealButton.
  ///
  /// In ko, this message translates to:
  /// **'거래 확인하기'**
  String get productConfirmDealButton;

  /// No description provided for @productSoldVerifyTitle.
  ///
  /// In ko, this message translates to:
  /// **'거래완료 전에 휴대폰 인증이 필요해요'**
  String get productSoldVerifyTitle;

  /// No description provided for @productSoldVerifyBody.
  ///
  /// In ko, this message translates to:
  /// **'모든 거래는 휴대폰 인증을 마쳐야 거래완료로 바꿀 수 있어요 (1인 1계정 보장).\n그동안 채굴한 QTA는 그대로 쌓여 있어요. 인증해도 채팅·통화는 익명 그대로예요.'**
  String get productSoldVerifyBody;

  /// No description provided for @productStatusChangedSold.
  ///
  /// In ko, this message translates to:
  /// **'거래완료로 변경했어요. 구매자가 거래를 확인하면 결제·보너스가 지급돼요'**
  String get productStatusChangedSold;

  /// No description provided for @productStatusChanged.
  ///
  /// In ko, this message translates to:
  /// **'상태를 {status}(으)로 변경했어요'**
  String productStatusChanged(String status);

  /// No description provided for @productBuyer.
  ///
  /// In ko, this message translates to:
  /// **'구매자'**
  String get productBuyer;

  /// No description provided for @productReviewQuestion.
  ///
  /// In ko, this message translates to:
  /// **'{nickname} 님과의 거래는 어떠셨나요?'**
  String productReviewQuestion(String nickname);

  /// No description provided for @productReviewHint.
  ///
  /// In ko, this message translates to:
  /// **'거래 후기를 남겨주세요 (선택)'**
  String get productReviewHint;

  /// No description provided for @productReviewThanks.
  ///
  /// In ko, this message translates to:
  /// **'후기 등록 감사합니다 🙏'**
  String get productReviewThanks;

  /// No description provided for @productReviewSubmit.
  ///
  /// In ko, this message translates to:
  /// **'후기 등록'**
  String get productReviewSubmit;

  /// No description provided for @productChatOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'채팅방을 열 수 없어요'**
  String get productChatOpenFailed;

  /// No description provided for @productChatStartFailed.
  ///
  /// In ko, this message translates to:
  /// **'채팅을 시작하지 못했어요. 잠시 후 다시 시도해주세요'**
  String get productChatStartFailed;

  /// No description provided for @productEscrowNavigating.
  ///
  /// In ko, this message translates to:
  /// **'안전결제 화면으로 이동합니다'**
  String get productEscrowNavigating;

  /// No description provided for @productChangeToSale.
  ///
  /// In ko, this message translates to:
  /// **'판매중으로 변경'**
  String get productChangeToSale;

  /// No description provided for @productChangeToReserved.
  ///
  /// In ko, this message translates to:
  /// **'예약중으로 변경'**
  String get productChangeToReserved;

  /// No description provided for @productChangeToSold.
  ///
  /// In ko, this message translates to:
  /// **'거래완료로 변경'**
  String get productChangeToSold;

  /// No description provided for @productEdit.
  ///
  /// In ko, this message translates to:
  /// **'수정'**
  String get productEdit;

  /// No description provided for @productDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'상품을 삭제할까요?'**
  String get productDeleteTitle;

  /// No description provided for @productDeleteBody.
  ///
  /// In ko, this message translates to:
  /// **'• 상품과 사진/영상이 영구 삭제돼요\n• 이 상품으로 받은 등록 채굴 QTA가 차감돼요\n• 복구할 수 없어요'**
  String get productDeleteBody;

  /// No description provided for @productDeletedWithClawback.
  ///
  /// In ko, this message translates to:
  /// **'상품을 삭제했어요 · 등록 채굴 -{qta} QTA'**
  String productDeletedWithClawback(int qta);

  /// No description provided for @productDeleted.
  ///
  /// In ko, this message translates to:
  /// **'상품을 삭제했어요'**
  String get productDeleted;

  /// No description provided for @productHide.
  ///
  /// In ko, this message translates to:
  /// **'숨기기'**
  String get productHide;

  /// No description provided for @productReport.
  ///
  /// In ko, this message translates to:
  /// **'신고'**
  String get productReport;

  /// No description provided for @productReportReceived.
  ///
  /// In ko, this message translates to:
  /// **'신고가 접수되었습니다'**
  String get productReportReceived;

  /// No description provided for @productDetailTitle.
  ///
  /// In ko, this message translates to:
  /// **'상품상세'**
  String get productDetailTitle;

  /// No description provided for @productOwnerMenuTooltip.
  ///
  /// In ko, this message translates to:
  /// **'상태 변경 / 삭제'**
  String get productOwnerMenuTooltip;

  /// No description provided for @productMore.
  ///
  /// In ko, this message translates to:
  /// **'더보기'**
  String get productMore;

  /// No description provided for @productDetailEmpty.
  ///
  /// In ko, this message translates to:
  /// **'상품 정보가 없습니다.'**
  String get productDetailEmpty;

  /// No description provided for @productNoTitle.
  ///
  /// In ko, this message translates to:
  /// **'제목 없음'**
  String get productNoTitle;

  /// No description provided for @productNoSellerInfo.
  ///
  /// In ko, this message translates to:
  /// **'판매자 정보 없음'**
  String get productNoSellerInfo;

  /// No description provided for @productDescriptionTitle.
  ///
  /// In ko, this message translates to:
  /// **'상품 설명'**
  String get productDescriptionTitle;

  /// No description provided for @productNoDescription.
  ///
  /// In ko, this message translates to:
  /// **'설명 없음'**
  String get productNoDescription;

  /// No description provided for @productManage.
  ///
  /// In ko, this message translates to:
  /// **'관리'**
  String get productManage;

  /// No description provided for @productChatButton.
  ///
  /// In ko, this message translates to:
  /// **'채팅하기'**
  String get productChatButton;

  /// No description provided for @productMannerTemp.
  ///
  /// In ko, this message translates to:
  /// **'매너온도 {temp}'**
  String productMannerTemp(String temp);

  /// No description provided for @productPickBuyerTitle.
  ///
  /// In ko, this message translates to:
  /// **'거래한 구매자를 선택해주세요'**
  String get productPickBuyerTitle;

  /// No description provided for @productPickBuyerHint.
  ///
  /// In ko, this message translates to:
  /// **'선택한 구매자가 앱에서 \"거래 확인\"을 눌러야 거래가 완료돼요.'**
  String get productPickBuyerHint;

  /// No description provided for @productPickBuyerSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'구매자 닉네임 검색'**
  String get productPickBuyerSearchHint;

  /// No description provided for @productPickBuyerChatPartners.
  ///
  /// In ko, this message translates to:
  /// **'이 상품으로 대화한 사람'**
  String get productPickBuyerChatPartners;

  /// No description provided for @productPickBuyerNoResults.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과가 없어요'**
  String get productPickBuyerNoResults;

  /// No description provided for @productPickBuyerEmpty.
  ///
  /// In ko, this message translates to:
  /// **'구매자의 닉네임을 검색해주세요'**
  String get productPickBuyerEmpty;

  /// No description provided for @productVideoLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'영상을 불러올 수 없어요'**
  String get productVideoLoadFailed;

  /// No description provided for @productMaxImages.
  ///
  /// In ko, this message translates to:
  /// **'최대 {max}장까지 등록 가능해요'**
  String productMaxImages(int max);

  /// No description provided for @productAddPhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진 추가'**
  String get productAddPhoto;

  /// No description provided for @productPhotoPickFailed.
  ///
  /// In ko, this message translates to:
  /// **'사진을 가져오지 못했어요. 권한을 확인하고 다시 시도해주세요'**
  String get productPhotoPickFailed;

  /// No description provided for @productAddVideo.
  ///
  /// In ko, this message translates to:
  /// **'영상 추가'**
  String get productAddVideo;

  /// No description provided for @productVideoPickFailed.
  ///
  /// In ko, this message translates to:
  /// **'영상을 가져오지 못했어요. 권한을 확인하고 다시 시도해주세요'**
  String get productVideoPickFailed;

  /// No description provided for @productVideoTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'영상 크기는 50MB 이하여야 해요'**
  String get productVideoTooLarge;

  /// No description provided for @productYoutubeAddTitle.
  ///
  /// In ko, this message translates to:
  /// **'유튜브 링크 추가'**
  String get productYoutubeAddTitle;

  /// No description provided for @productYoutubeAddBody.
  ///
  /// In ko, this message translates to:
  /// **'유튜브 영상 URL을 붙여넣어 주세요.\n예: https://youtu.be/xxxxxxxxxxx'**
  String get productYoutubeAddBody;

  /// No description provided for @productYoutubeInvalid.
  ///
  /// In ko, this message translates to:
  /// **'유튜브 링크 형식이 올바르지 않아요'**
  String get productYoutubeInvalid;

  /// No description provided for @productSetRegionFirst.
  ///
  /// In ko, this message translates to:
  /// **'먼저 동네를 설정해주세요'**
  String get productSetRegionFirst;

  /// No description provided for @productUploadTimeout.
  ///
  /// In ko, this message translates to:
  /// **'업로드가 너무 오래 걸려요. 사진/영상 크기를 줄이거나 Wi-Fi에서 다시 시도해주세요.'**
  String get productUploadTimeout;

  /// No description provided for @productCreateUnexpectedError.
  ///
  /// In ko, this message translates to:
  /// **'등록 중 문제가 생겼어요. 잠시 후 다시 시도해주세요'**
  String get productCreateUnexpectedError;

  /// No description provided for @productCreatedWithReward.
  ///
  /// In ko, this message translates to:
  /// **'상품이 등록되었어요 🍆  등록 채굴 +{qta} QTA'**
  String productCreatedWithReward(int qta);

  /// No description provided for @productCreated.
  ///
  /// In ko, this message translates to:
  /// **'상품이 등록되었어요 🍆'**
  String get productCreated;

  /// No description provided for @productCreateTitle.
  ///
  /// In ko, this message translates to:
  /// **'중고거래 글쓰기'**
  String get productCreateTitle;

  /// No description provided for @productDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get productDone;

  /// No description provided for @productFieldTitle.
  ///
  /// In ko, this message translates to:
  /// **'제목'**
  String get productFieldTitle;

  /// No description provided for @productFieldTitleHint.
  ///
  /// In ko, this message translates to:
  /// **'상품명을 입력해주세요'**
  String get productFieldTitleHint;

  /// No description provided for @productFieldTitleRequired.
  ///
  /// In ko, this message translates to:
  /// **'제목을 입력해주세요'**
  String get productFieldTitleRequired;

  /// No description provided for @productFieldCategory.
  ///
  /// In ko, this message translates to:
  /// **'카테고리'**
  String get productFieldCategory;

  /// No description provided for @productFieldPrice.
  ///
  /// In ko, this message translates to:
  /// **'가격'**
  String get productFieldPrice;

  /// No description provided for @productFieldPriceHintKrw.
  ///
  /// In ko, this message translates to:
  /// **'0 (나눔하려면 0원)'**
  String get productFieldPriceHintKrw;

  /// No description provided for @productFieldPriceHintJpy.
  ///
  /// In ko, this message translates to:
  /// **'0 (나눔하려면 0엔)'**
  String get productFieldPriceHintJpy;

  /// No description provided for @productFieldPriceRequired.
  ///
  /// In ko, this message translates to:
  /// **'가격을 입력해주세요'**
  String get productFieldPriceRequired;

  /// No description provided for @productFieldQtaPrice.
  ///
  /// In ko, this message translates to:
  /// **'QTA 결제 (선택)'**
  String get productFieldQtaPrice;

  /// No description provided for @productFieldQtaPriceHint.
  ///
  /// In ko, this message translates to:
  /// **'0 = 사용 안 함 / 구매자 거래 확인 시 차감'**
  String get productFieldQtaPriceHint;

  /// No description provided for @productFieldQtaPriceHelper.
  ///
  /// In ko, this message translates to:
  /// **'예) 5,000 → 구매자가 거래를 확인하면 구매자 잔액에서 5,000 QTA 가 이체돼요'**
  String get productFieldQtaPriceHelper;

  /// No description provided for @productFieldDescription.
  ///
  /// In ko, this message translates to:
  /// **'자세한 설명'**
  String get productFieldDescription;

  /// No description provided for @productFieldDescriptionHint.
  ///
  /// In ko, this message translates to:
  /// **'게시글 등록 전에 체크해주세요.\n- 판매금지물품인지 확인\n- 카테고리가 적절한지 확인\n\n상품의 상태, 사용기간 등을 자세히 적어주세요.'**
  String get productFieldDescriptionHint;

  /// No description provided for @productFieldDescriptionMin.
  ///
  /// In ko, this message translates to:
  /// **'10자 이상 입력해주세요'**
  String get productFieldDescriptionMin;

  /// No description provided for @productProhibitedGuide.
  ///
  /// In ko, this message translates to:
  /// **'거래 금지 품목 안내'**
  String get productProhibitedGuide;

  /// No description provided for @productPhotos.
  ///
  /// In ko, this message translates to:
  /// **'사진'**
  String get productPhotos;

  /// No description provided for @productVideo.
  ///
  /// In ko, this message translates to:
  /// **'영상'**
  String get productVideo;

  /// No description provided for @productOptional.
  ///
  /// In ko, this message translates to:
  /// **'(선택)'**
  String get productOptional;

  /// No description provided for @productRemove.
  ///
  /// In ko, this message translates to:
  /// **'제거'**
  String get productRemove;

  /// No description provided for @productPickCamera.
  ///
  /// In ko, this message translates to:
  /// **'카메라로 촬영'**
  String get productPickCamera;

  /// No description provided for @productPickGallery.
  ///
  /// In ko, this message translates to:
  /// **'갤러리에서 선택'**
  String get productPickGallery;

  /// No description provided for @productPickYoutube.
  ///
  /// In ko, this message translates to:
  /// **'유튜브 링크 붙여넣기'**
  String get productPickYoutube;

  /// No description provided for @productCoverPhoto.
  ///
  /// In ko, this message translates to:
  /// **'대표'**
  String get productCoverPhoto;

  /// No description provided for @productYoutubeVideo.
  ///
  /// In ko, this message translates to:
  /// **'유튜브 영상'**
  String get productYoutubeVideo;

  /// No description provided for @productNotFound.
  ///
  /// In ko, this message translates to:
  /// **'상품을 찾을 수 없어요'**
  String get productNotFound;

  /// No description provided for @productNoChanges.
  ///
  /// In ko, this message translates to:
  /// **'변경된 내용이 없어요'**
  String get productNoChanges;

  /// No description provided for @productUpdated.
  ///
  /// In ko, this message translates to:
  /// **'상품을 수정했어요 ✨'**
  String get productUpdated;

  /// No description provided for @productEditTitle.
  ///
  /// In ko, this message translates to:
  /// **'상품 수정'**
  String get productEditTitle;

  /// No description provided for @productFieldTitleTooLong.
  ///
  /// In ko, this message translates to:
  /// **'제목이 너무 길어요'**
  String get productFieldTitleTooLong;

  /// No description provided for @productFieldRegion.
  ///
  /// In ko, this message translates to:
  /// **'동네'**
  String get productFieldRegion;

  /// No description provided for @productSetRegion.
  ///
  /// In ko, this message translates to:
  /// **'동네를 설정해주세요'**
  String get productSetRegion;

  /// No description provided for @productChange.
  ///
  /// In ko, this message translates to:
  /// **'변경'**
  String get productChange;

  /// No description provided for @productFieldDescriptionEditHint.
  ///
  /// In ko, this message translates to:
  /// **'상품의 상태, 사용기간 등을 자세히 적어주세요.'**
  String get productFieldDescriptionEditHint;

  /// No description provided for @productUploadedVideoLocked.
  ///
  /// In ko, this message translates to:
  /// **'업로드한 영상은 수정할 수 없어요.\n변경하려면 상품을 삭제 후 다시 등록해주세요.'**
  String get productUploadedVideoLocked;

  /// No description provided for @productYoutubeLinkOptional.
  ///
  /// In ko, this message translates to:
  /// **'유튜브 링크 (선택)'**
  String get productYoutubeLinkOptional;

  /// No description provided for @productEditingBanner.
  ///
  /// In ko, this message translates to:
  /// **'수정 중: {title}'**
  String productEditingBanner(String title);

  /// No description provided for @productWaitHoursMinutes.
  ///
  /// In ko, this message translates to:
  /// **'{h}시간 {m}분'**
  String productWaitHoursMinutes(int h, int m);

  /// No description provided for @productWaitMinutes.
  ///
  /// In ko, this message translates to:
  /// **'{m}분'**
  String productWaitMinutes(int m);

  /// No description provided for @productBumpWait.
  ///
  /// In ko, this message translates to:
  /// **'{wait} 후에 다시 끌어올릴 수 있어요'**
  String productBumpWait(String wait);

  /// No description provided for @productBumped.
  ///
  /// In ko, this message translates to:
  /// **'🍆 끌어올렸어요! 피드 맨 위로 올라갔어요'**
  String get productBumped;

  /// No description provided for @productDeleteDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'상품 삭제'**
  String get productDeleteDialogTitle;

  /// No description provided for @productDeleteConfirmNamed.
  ///
  /// In ko, this message translates to:
  /// **'{title}을(를) 정말 삭제할까요?'**
  String productDeleteConfirmNamed(String title);

  /// No description provided for @productStatusChangedGeneric.
  ///
  /// In ko, this message translates to:
  /// **'상태를 변경했어요'**
  String get productStatusChangedGeneric;

  /// No description provided for @productMySelling.
  ///
  /// In ko, this message translates to:
  /// **'내 판매상품'**
  String get productMySelling;

  /// No description provided for @productMySellingCount.
  ///
  /// In ko, this message translates to:
  /// **'내 판매상품 {count}'**
  String productMySellingCount(int count);

  /// No description provided for @productNewPost.
  ///
  /// In ko, this message translates to:
  /// **'새 글쓰기'**
  String get productNewPost;

  /// No description provided for @productMySellingEmpty.
  ///
  /// In ko, this message translates to:
  /// **'등록한 상품이 없어요'**
  String get productMySellingEmpty;

  /// No description provided for @productMySellingEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'우측 하단 \"새 글쓰기\"로 올려보세요'**
  String get productMySellingEmptyHint;

  /// No description provided for @productMyMenuTooltip.
  ///
  /// In ko, this message translates to:
  /// **'끌어올리기 / 상태 변경 / 삭제'**
  String get productMyMenuTooltip;

  /// No description provided for @productBump.
  ///
  /// In ko, this message translates to:
  /// **'끌어올리기'**
  String get productBump;

  /// No description provided for @productBumpWaiting.
  ///
  /// In ko, this message translates to:
  /// **'끌어올리기 (대기중)'**
  String get productBumpWaiting;

  /// No description provided for @productChangeStatus.
  ///
  /// In ko, this message translates to:
  /// **'상태 변경'**
  String get productChangeStatus;

  /// No description provided for @productBanMedicine.
  ///
  /// In ko, this message translates to:
  /// **'의약품·의료기기'**
  String get productBanMedicine;

  /// No description provided for @productBanMedicineEx.
  ///
  /// In ko, this message translates to:
  /// **'전문/일반의약품, 다이어트약, 발기부전치료제, 콘택트렌즈, 보청기, 주사기'**
  String get productBanMedicineEx;

  /// No description provided for @productBanDrugs.
  ///
  /// In ko, this message translates to:
  /// **'마약류·향정신성의약품'**
  String get productBanDrugs;

  /// No description provided for @productBanDrugsEx.
  ///
  /// In ko, this message translates to:
  /// **'대마, 필로폰, 졸피뎀, 프로포폴, 환각버섯 등'**
  String get productBanDrugsEx;

  /// No description provided for @productBanAlcohol.
  ///
  /// In ko, this message translates to:
  /// **'주류'**
  String get productBanAlcohol;

  /// No description provided for @productBanAlcoholEx.
  ///
  /// In ko, this message translates to:
  /// **'소주·맥주·와인·위스키·전통주 (빈 병·잔은 가능)'**
  String get productBanAlcoholEx;

  /// No description provided for @productBanTobacco.
  ///
  /// In ko, this message translates to:
  /// **'담배·전자담배'**
  String get productBanTobacco;

  /// No description provided for @productBanTobaccoEx.
  ///
  /// In ko, this message translates to:
  /// **'담배, 전자담배 기기·액상, 니코틴 제품'**
  String get productBanTobaccoEx;

  /// No description provided for @productBanWeapons.
  ///
  /// In ko, this message translates to:
  /// **'총포·도검·화약류·무기'**
  String get productBanWeapons;

  /// No description provided for @productBanWeaponsEx.
  ///
  /// In ko, this message translates to:
  /// **'총기, 실탄, 석궁, 전기충격기, 가스분사기, 도검'**
  String get productBanWeaponsEx;

  /// No description provided for @productBanAdult.
  ///
  /// In ko, this message translates to:
  /// **'성인용품·음란물'**
  String get productBanAdult;

  /// No description provided for @productBanAdultEx.
  ///
  /// In ko, this message translates to:
  /// **'성인용품, 음란물, 착용 속옷, 조건만남'**
  String get productBanAdultEx;

  /// No description provided for @productBanAccounts.
  ///
  /// In ko, this message translates to:
  /// **'계정·개인정보·명의'**
  String get productBanAccounts;

  /// No description provided for @productBanAccountsEx.
  ///
  /// In ko, this message translates to:
  /// **'게임/SNS 계정, 통장, 유심·대포폰, 신분증, 공인인증서'**
  String get productBanAccountsEx;

  /// No description provided for @productBanCashing.
  ///
  /// In ko, this message translates to:
  /// **'현금화·대출·가상화폐'**
  String get productBanCashing;

  /// No description provided for @productBanCashingEx.
  ///
  /// In ko, this message translates to:
  /// **'상품권깡, 소액결제 현금화, 작업대출, 비트코인 등 코인 매매'**
  String get productBanCashingEx;

  /// No description provided for @productBanAnimals.
  ///
  /// In ko, this message translates to:
  /// **'반려동물·야생동물'**
  String get productBanAnimals;

  /// No description provided for @productBanAnimalsEx.
  ///
  /// In ko, this message translates to:
  /// **'반려동물 분양·판매 (무료분양·책임비 포함), 멸종위기종, 웅담'**
  String get productBanAnimalsEx;

  /// No description provided for @productBanCounterfeit.
  ///
  /// In ko, this message translates to:
  /// **'위조품'**
  String get productBanCounterfeit;

  /// No description provided for @productBanCounterfeitEx.
  ///
  /// In ko, this message translates to:
  /// **'짝퉁, 레플리카, 미러급, ST급'**
  String get productBanCounterfeitEx;

  /// No description provided for @productBanStolen.
  ///
  /// In ko, this message translates to:
  /// **'도난품·불법개조·불법복제'**
  String get productBanStolen;

  /// No description provided for @productBanStolenEx.
  ///
  /// In ko, this message translates to:
  /// **'장물, 불법 개조품, 해적판, 크랙'**
  String get productBanStolenEx;

  /// No description provided for @productBanBodily.
  ///
  /// In ko, this message translates to:
  /// **'헌혈증·처방전·인체유래물'**
  String get productBanBodily;

  /// No description provided for @productBanBodilyEx.
  ///
  /// In ko, this message translates to:
  /// **'헌혈증, 처방전, 장기·난자·모유'**
  String get productBanBodilyEx;

  /// No description provided for @productBanMilitary.
  ///
  /// In ko, this message translates to:
  /// **'군용품·경찰 제복'**
  String get productBanMilitary;

  /// No description provided for @productBanMilitaryEx.
  ///
  /// In ko, this message translates to:
  /// **'군복, 방탄복, 경찰 제복·배지, 수갑'**
  String get productBanMilitaryEx;

  /// No description provided for @productBanSpycam.
  ///
  /// In ko, this message translates to:
  /// **'불법 촬영·도청 장비'**
  String get productBanSpycam;

  /// No description provided for @productBanSpycamEx.
  ///
  /// In ko, this message translates to:
  /// **'몰래카메라, 위장형 카메라, 도청기'**
  String get productBanSpycamEx;

  /// No description provided for @productBanHacking.
  ///
  /// In ko, this message translates to:
  /// **'해킹·불법 프로그램'**
  String get productBanHacking;

  /// No description provided for @productBanHackingEx.
  ///
  /// In ko, this message translates to:
  /// **'해킹툴, 게임핵, 불법 매크로'**
  String get productBanHackingEx;

  /// No description provided for @productBanScalping.
  ///
  /// In ko, this message translates to:
  /// **'암표·대리 서비스'**
  String get productBanScalping;

  /// No description provided for @productBanScalpingEx.
  ///
  /// In ko, this message translates to:
  /// **'웃돈 티켓 리셀, 티켓팅 대행, 대리시험'**
  String get productBanScalpingEx;

  /// No description provided for @productBanWasteBags.
  ///
  /// In ko, this message translates to:
  /// **'종량제 봉투'**
  String get productBanWasteBags;

  /// No description provided for @productBanWasteBagsEx.
  ///
  /// In ko, this message translates to:
  /// **'쓰레기 종량제 봉투, 폐기물 스티커'**
  String get productBanWasteBagsEx;

  /// No description provided for @productBanFireworks.
  ///
  /// In ko, this message translates to:
  /// **'폭죽·불꽃놀이'**
  String get productBanFireworks;

  /// No description provided for @productBanFireworksEx.
  ///
  /// In ko, this message translates to:
  /// **'폭죽, 불꽃놀이 화약류, 사제 폭발물'**
  String get productBanFireworksEx;

  /// No description provided for @productBanIntro.
  ///
  /// In ko, this message translates to:
  /// **'법으로 거래가 금지되었거나 안전을 해칠 수 있는 물품은 가지에서 판매할 수 없어요. 아래 품목이 포함된 게시글은 등록되지 않으며, 운영정책 위반 시 이용이 제한될 수 있어요.'**
  String get productBanIntro;

  /// No description provided for @productBanInfoTitle.
  ///
  /// In ko, this message translates to:
  /// **'게시글에 적을 수 없는 정보'**
  String get productBanInfoTitle;

  /// No description provided for @productBanInfoBody.
  ///
  /// In ko, this message translates to:
  /// **'• 전화번호, 계좌번호, 이메일\n• 카카오톡 ID, 오픈채팅·텔레그램 링크 등 외부 메신저\n• 욕설·비속어·혐오 표현\n\n거래 대화는 가지 채팅으로 해주세요. 외부 메신저·선입금 유도는 사기 위험이 커요.'**
  String get productBanInfoBody;

  /// No description provided for @productPolicyRejectedTitle.
  ///
  /// In ko, this message translates to:
  /// **'등록할 수 없는 게시글이에요'**
  String get productPolicyRejectedTitle;

  /// No description provided for @productViewProhibited.
  ///
  /// In ko, this message translates to:
  /// **'금지 품목 보기'**
  String get productViewProhibited;

  /// No description provided for @productHiddenTimeout.
  ///
  /// In ko, this message translates to:
  /// **'서버 응답이 늦어요. 잠시 후 다시 시도해주세요 🕐'**
  String get productHiddenTimeout;

  /// No description provided for @productHiddenLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'숨긴 게시물을 불러오지 못했어요'**
  String get productHiddenLoadFailed;

  /// No description provided for @productUnhidden.
  ///
  /// In ko, this message translates to:
  /// **'\"{title}\" 다시 보여요'**
  String productUnhidden(String title);

  /// No description provided for @productUnhideFailed.
  ///
  /// In ko, this message translates to:
  /// **'숨김 해제 실패'**
  String get productUnhideFailed;

  /// No description provided for @productHiddenTitle.
  ///
  /// In ko, this message translates to:
  /// **'숨긴 게시물'**
  String get productHiddenTitle;

  /// No description provided for @productUnhide.
  ///
  /// In ko, this message translates to:
  /// **'숨김 해제'**
  String get productUnhide;

  /// No description provided for @productHiddenEmpty.
  ///
  /// In ko, this message translates to:
  /// **'숨긴 게시물이 없어요'**
  String get productHiddenEmpty;

  /// No description provided for @productHiddenEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'게시물 우측 상단의 ⋯ 메뉴에서 가릴 수 있어요'**
  String get productHiddenEmptyHint;

  /// No description provided for @productKeywordDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'키워드 삭제'**
  String get productKeywordDeleteTitle;

  /// No description provided for @productKeywordDeleteBody.
  ///
  /// In ko, this message translates to:
  /// **'\"{keyword}\" 알림을 끌까요?'**
  String productKeywordDeleteBody(String keyword);

  /// No description provided for @productKeywordAlertsTitle.
  ///
  /// In ko, this message translates to:
  /// **'키워드 알림'**
  String get productKeywordAlertsTitle;

  /// No description provided for @productKeywordAlertsIntro.
  ///
  /// In ko, this message translates to:
  /// **'관심 키워드를 등록하면 동네에 새 매물이 올라올 때 알림을 보내드려요. (최대 {max}개)'**
  String productKeywordAlertsIntro(int max);

  /// No description provided for @productKeywordFull.
  ///
  /// In ko, this message translates to:
  /// **'키워드 슬롯이 모두 찼어요'**
  String get productKeywordFull;

  /// No description provided for @productKeywordHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 닌텐도, 자전거, 캠핑'**
  String get productKeywordHint;

  /// No description provided for @productKeywordAdd.
  ///
  /// In ko, this message translates to:
  /// **'등록'**
  String get productKeywordAdd;

  /// No description provided for @productKeywordEmpty.
  ///
  /// In ko, this message translates to:
  /// **'등록한 키워드가 없어요'**
  String get productKeywordEmpty;

  /// No description provided for @productKeywordEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'위에서 관심 키워드를 추가해보세요'**
  String get productKeywordEmptyHint;

  /// No description provided for @productKeywordTooShort.
  ///
  /// In ko, this message translates to:
  /// **'키워드는 2자 이상이어야 해요'**
  String get productKeywordTooShort;

  /// No description provided for @productKeywordTooLong.
  ///
  /// In ko, this message translates to:
  /// **'키워드는 30자 이하로 입력해주세요'**
  String get productKeywordTooLong;

  /// No description provided for @productKeywordMax.
  ///
  /// In ko, this message translates to:
  /// **'키워드는 최대 {max}개까지 등록할 수 있어요'**
  String productKeywordMax(int max);

  /// No description provided for @productKeywordAddFailed.
  ///
  /// In ko, this message translates to:
  /// **'알림 등록에 실패했어요. 잠시 후 다시 시도해주세요'**
  String get productKeywordAddFailed;

  /// No description provided for @productLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'상품을 불러오지 못했어요'**
  String get productLoadFailed;

  /// No description provided for @productCreateFailed.
  ///
  /// In ko, this message translates to:
  /// **'등록 실패'**
  String get productCreateFailed;

  /// No description provided for @productCreateFailedRetry.
  ///
  /// In ko, this message translates to:
  /// **'등록에 실패했어요. 잠시 후 다시 시도해주세요'**
  String get productCreateFailedRetry;

  /// No description provided for @productLikesLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'찜한 상품을 불러올 수 없어요'**
  String get productLikesLoadFailed;

  /// No description provided for @productNothingToUpdate.
  ///
  /// In ko, this message translates to:
  /// **'수정할 내용이 없어요'**
  String get productNothingToUpdate;

  /// No description provided for @productUpdateFailed.
  ///
  /// In ko, this message translates to:
  /// **'수정 실패'**
  String get productUpdateFailed;

  /// No description provided for @productBumpFailed.
  ///
  /// In ko, this message translates to:
  /// **'끌어올리기 실패'**
  String get productBumpFailed;

  /// No description provided for @productChangeFailed.
  ///
  /// In ko, this message translates to:
  /// **'변경 실패'**
  String get productChangeFailed;

  /// No description provided for @productDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'삭제 실패'**
  String get productDeleteFailed;

  /// No description provided for @productConfirmFailed.
  ///
  /// In ko, this message translates to:
  /// **'거래 확인 실패'**
  String get productConfirmFailed;

  /// No description provided for @productReviewFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기 등록 실패'**
  String get productReviewFailed;

  /// No description provided for @productNetworkSlow.
  ///
  /// In ko, this message translates to:
  /// **'응답이 늦어요. 네트워크 상태를 확인하고 다시 시도해주세요'**
  String get productNetworkSlow;

  /// No description provided for @productNetworkUnreachable.
  ///
  /// In ko, this message translates to:
  /// **'서버에 연결할 수 없어요. 네트워크를 확인해주세요'**
  String get productNetworkUnreachable;

  /// No description provided for @productBlockFailed.
  ///
  /// In ko, this message translates to:
  /// **'차단 실패'**
  String get productBlockFailed;

  /// No description provided for @productUnblockFailed.
  ///
  /// In ko, this message translates to:
  /// **'차단 해제 실패'**
  String get productUnblockFailed;

  /// No description provided for @productReportFailed.
  ///
  /// In ko, this message translates to:
  /// **'신고 접수 실패'**
  String get productReportFailed;

  /// No description provided for @productFieldPriceHintPhp.
  ///
  /// In ko, this message translates to:
  /// **'0 (나눔하려면 0페소)'**
  String get productFieldPriceHintPhp;

  /// No description provided for @regionPrefectureSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'도도부현·시구정촌 이름으로 검색 (예: 渋谷)'**
  String get regionPrefectureSearchHint;

  /// No description provided for @regionCitySearchHint.
  ///
  /// In ko, this message translates to:
  /// **'{prefecture}의 시구정촌 검색'**
  String regionCitySearchHint(String prefecture);

  /// No description provided for @regionCityCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}곳'**
  String regionCityCount(int count);

  /// No description provided for @regionChangePrefecture.
  ///
  /// In ko, this message translates to:
  /// **'도도부현 다시 선택'**
  String get regionChangePrefecture;

  /// No description provided for @regionNoResults.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과가 없어요'**
  String get regionNoResults;

  /// No description provided for @regionAdded.
  ///
  /// In ko, this message translates to:
  /// **'{region} 추가 ({count}/{max})'**
  String regionAdded(String region, int count, int max);

  /// No description provided for @regionRemoved.
  ///
  /// In ko, this message translates to:
  /// **'{region} 뺐어요 ({count}/{max})'**
  String regionRemoved(String region, int count, int max);

  /// No description provided for @regionMultiHint.
  ///
  /// In ko, this message translates to:
  /// **'아래 목록에서 눌러 최대 {max}곳까지 추가 · 다시 누르면 빠져요. 위 동네를 누르면 그 동네로 바뀌어요.'**
  String regionMultiHint(int max);

  /// No description provided for @regionKeepOne.
  ///
  /// In ko, this message translates to:
  /// **'동네는 한 곳 이상 있어야 해요'**
  String get regionKeepOne;

  /// No description provided for @reviewQuestion.
  ///
  /// In ko, this message translates to:
  /// **'{nickname}님과 거래가 어떠셨나요?'**
  String reviewQuestion(String nickname);

  /// No description provided for @reviewQuestionSub.
  ///
  /// In ko, this message translates to:
  /// **'거래 후기는 서로의 매너온도에 반영돼요'**
  String get reviewQuestionSub;

  /// No description provided for @reviewRatingBad.
  ///
  /// In ko, this message translates to:
  /// **'별로예요'**
  String get reviewRatingBad;

  /// No description provided for @reviewRatingGood.
  ///
  /// In ko, this message translates to:
  /// **'좋아요'**
  String get reviewRatingGood;

  /// No description provided for @reviewRatingBest.
  ///
  /// In ko, this message translates to:
  /// **'최고예요'**
  String get reviewRatingBest;

  /// No description provided for @reviewRatingSoso.
  ///
  /// In ko, this message translates to:
  /// **'보통이에요'**
  String get reviewRatingSoso;

  /// No description provided for @reviewTagsTitleGood.
  ///
  /// In ko, this message translates to:
  /// **'어떤 점이 좋았나요?'**
  String get reviewTagsTitleGood;

  /// No description provided for @reviewTagsTitleBad.
  ///
  /// In ko, this message translates to:
  /// **'어떤 점이 별로였나요?'**
  String get reviewTagsTitleBad;

  /// No description provided for @reviewTagsSub.
  ///
  /// In ko, this message translates to:
  /// **'해당하는 항목을 모두 골라주세요'**
  String get reviewTagsSub;

  /// No description provided for @reviewBadPrivateNotice.
  ///
  /// In ko, this message translates to:
  /// **'별로예요 평가와 고른 항목은 상대방 프로필에 공개되지 않고 매너온도에만 반영돼요'**
  String get reviewBadPrivateNotice;

  /// No description provided for @reviewCommentTitle.
  ///
  /// In ko, this message translates to:
  /// **'따뜻한 거래 후기를 남겨주세요'**
  String get reviewCommentTitle;

  /// No description provided for @reviewCommentTitleBad.
  ///
  /// In ko, this message translates to:
  /// **'아쉬웠던 점을 알려주세요'**
  String get reviewCommentTitleBad;

  /// No description provided for @reviewCommentOptional.
  ///
  /// In ko, this message translates to:
  /// **'선택 사항이에요. 후기 글은 {nickname}님의 프로필에 공개돼요'**
  String reviewCommentOptional(String nickname);

  /// No description provided for @reviewCommentOptionalBad.
  ///
  /// In ko, this message translates to:
  /// **'선택 사항이에요. 이 내용은 공개되지 않아요'**
  String get reviewCommentOptionalBad;

  /// No description provided for @reviewCommentHint.
  ///
  /// In ko, this message translates to:
  /// **'{nickname}님에게 고마운 마음을 전해보세요'**
  String reviewCommentHint(String nickname);

  /// No description provided for @reviewCommentHintBad.
  ///
  /// In ko, this message translates to:
  /// **'어떤 점이 아쉬웠나요?'**
  String get reviewCommentHintBad;

  /// No description provided for @reviewNext.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get reviewNext;

  /// No description provided for @reviewBack.
  ///
  /// In ko, this message translates to:
  /// **'이전'**
  String get reviewBack;

  /// No description provided for @reviewSubmit.
  ///
  /// In ko, this message translates to:
  /// **'후기 보내기'**
  String get reviewSubmit;

  /// No description provided for @reviewSent.
  ///
  /// In ko, this message translates to:
  /// **'거래 후기를 보냈어요'**
  String get reviewSent;

  /// No description provided for @reviewSendButton.
  ///
  /// In ko, this message translates to:
  /// **'거래 후기 보내기'**
  String get reviewSendButton;

  /// No description provided for @reviewViewMine.
  ///
  /// In ko, this message translates to:
  /// **'보낸 후기 보기'**
  String get reviewViewMine;

  /// No description provided for @reviewSentTo.
  ///
  /// In ko, this message translates to:
  /// **'{nickname}님에게 보낸 후기'**
  String reviewSentTo(String nickname);

  /// No description provided for @reviewPromptBody.
  ///
  /// In ko, this message translates to:
  /// **'거래 후기를 남기면 서로의 매너온도에 반영돼요'**
  String get reviewPromptBody;

  /// No description provided for @reviewPromptDone.
  ///
  /// In ko, this message translates to:
  /// **'거래 후기를 보냈어요. 따뜻한 거래 감사합니다!'**
  String get reviewPromptDone;

  /// No description provided for @reviewRoleBuyer.
  ///
  /// In ko, this message translates to:
  /// **'구매자'**
  String get reviewRoleBuyer;

  /// No description provided for @reviewRoleSeller.
  ///
  /// In ko, this message translates to:
  /// **'판매자'**
  String get reviewRoleSeller;

  /// No description provided for @reviewPraiseTitle.
  ///
  /// In ko, this message translates to:
  /// **'받은 매너 칭찬'**
  String get reviewPraiseTitle;

  /// No description provided for @reviewPraiseMore.
  ///
  /// In ko, this message translates to:
  /// **'더보기'**
  String get reviewPraiseMore;

  /// No description provided for @reviewPraiseLess.
  ///
  /// In ko, this message translates to:
  /// **'접기'**
  String get reviewPraiseLess;

  /// No description provided for @reviewNoPraise.
  ///
  /// In ko, this message translates to:
  /// **'아직 받은 매너 칭찬이 없어요'**
  String get reviewNoPraise;

  /// No description provided for @reviewReceivedTitle.
  ///
  /// In ko, this message translates to:
  /// **'받은 거래 후기'**
  String get reviewReceivedTitle;

  /// No description provided for @reviewNoComments.
  ///
  /// In ko, this message translates to:
  /// **'아직 받은 거래 후기가 없어요'**
  String get reviewNoComments;

  /// No description provided for @reviewPurchasesTitle.
  ///
  /// In ko, this message translates to:
  /// **'구매 내역'**
  String get reviewPurchasesTitle;

  /// No description provided for @reviewPurchasesEmpty.
  ///
  /// In ko, this message translates to:
  /// **'구매한 상품이 없어요'**
  String get reviewPurchasesEmpty;

  /// No description provided for @reviewPurchasesLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'구매 내역을 불러오지 못했어요'**
  String get reviewPurchasesLoadFailed;

  /// No description provided for @reviewCounterpartFallback.
  ///
  /// In ko, this message translates to:
  /// **'거래 상대'**
  String get reviewCounterpartFallback;

  /// No description provided for @reviewTagKind.
  ///
  /// In ko, this message translates to:
  /// **'친절하고 매너가 좋아요'**
  String get reviewTagKind;

  /// No description provided for @reviewTagPunctual.
  ///
  /// In ko, this message translates to:
  /// **'시간 약속을 잘 지켜요'**
  String get reviewTagPunctual;

  /// No description provided for @reviewTagFastReply.
  ///
  /// In ko, this message translates to:
  /// **'응답이 빨라요'**
  String get reviewTagFastReply;

  /// No description provided for @reviewTagAsDescribed.
  ///
  /// In ko, this message translates to:
  /// **'상품 상태가 설명한 것과 같아요'**
  String get reviewTagAsDescribed;

  /// No description provided for @reviewTagDetailedDesc.
  ///
  /// In ko, this message translates to:
  /// **'상품 설명이 자세해요'**
  String get reviewTagDetailedDesc;

  /// No description provided for @reviewTagGoodPrice.
  ///
  /// In ko, this message translates to:
  /// **'좋은 상품을 저렴하게 판매해요'**
  String get reviewTagGoodPrice;

  /// No description provided for @reviewTagFreeShare.
  ///
  /// In ko, this message translates to:
  /// **'무료로 나눠주셨어요'**
  String get reviewTagFreeShare;

  /// No description provided for @reviewTagPaidOnTime.
  ///
  /// In ko, this message translates to:
  /// **'제시간에 결제·수령했어요'**
  String get reviewTagPaidOnTime;

  /// No description provided for @reviewTagNoHaggle.
  ///
  /// In ko, this message translates to:
  /// **'무리하게 가격을 깎지 않아요'**
  String get reviewTagNoHaggle;

  /// No description provided for @reviewTagLate.
  ///
  /// In ko, this message translates to:
  /// **'시간 약속을 안 지켜요'**
  String get reviewTagLate;

  /// No description provided for @reviewTagSlowReply.
  ///
  /// In ko, this message translates to:
  /// **'응답이 느려요'**
  String get reviewTagSlowReply;

  /// No description provided for @reviewTagRude.
  ///
  /// In ko, this message translates to:
  /// **'불친절해요'**
  String get reviewTagRude;

  /// No description provided for @reviewTagNotAsDescribed.
  ///
  /// In ko, this message translates to:
  /// **'상품 상태가 설명과 달라요'**
  String get reviewTagNotAsDescribed;

  /// No description provided for @reviewTagPriceChange.
  ///
  /// In ko, this message translates to:
  /// **'가격을 갑자기 바꿔요'**
  String get reviewTagPriceChange;

  /// No description provided for @reviewTagNoShow.
  ///
  /// In ko, this message translates to:
  /// **'약속 장소에 나타나지 않았어요'**
  String get reviewTagNoShow;

  /// No description provided for @reviewTagHaggle.
  ///
  /// In ko, this message translates to:
  /// **'무리하게 가격을 깎아요'**
  String get reviewTagHaggle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
