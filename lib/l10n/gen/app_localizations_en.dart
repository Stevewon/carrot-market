// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get authWalletRequired => 'Please enter your wallet address';

  @override
  String get authWalletFormat => 'Must be 42 characters starting with 0x';

  @override
  String get authNicknameRequired => 'Please enter a nickname';

  @override
  String get authNicknameTooShort => 'Nickname must be at least 2 characters';

  @override
  String get authNicknameTooLong => 'Nickname must be 12 characters or less';

  @override
  String get authNicknameCharset =>
      'Only Korean, Japanese, English letters, numbers and _ are allowed (no spaces or symbols)';

  @override
  String get authPasswordRequired => 'Please enter a password';

  @override
  String get authPasswordTooShort => 'Password must be at least 8 characters';

  @override
  String get authPasswordTooLong => 'Password must be 64 characters or less';

  @override
  String get authPasswordMix => 'Use both letters and numbers';

  @override
  String authPhoneCheckExample(String example) {
    return 'Please check your phone number (e.g. $example)';
  }

  @override
  String get authPhoneCheck => 'Please check your phone number';

  @override
  String get authTooManyRequests =>
      'Too many requests. Please try again in a moment';

  @override
  String get authSmsQuotaExceeded =>
      'You\'ve hit today\'s SMS limit. Please try again tomorrow';

  @override
  String authSmsSendFailedCode(String code) {
    return 'Couldn\'t send the SMS. Please try again in a moment ($code)';
  }

  @override
  String get authSmsSendFailed =>
      'Couldn\'t send the SMS. Please try again in a moment';

  @override
  String get authSmsCodeInvalid => 'Enter the 6-digit code we sent by SMS';

  @override
  String get authPhoneVerifyFailedRetry =>
      'Phone verification didn\'t go through. Please try again';

  @override
  String get authSmsCodeWrong => 'That code isn\'t right';

  @override
  String get authSmsCodeExpired =>
      'The code has expired. Please request a new one';

  @override
  String authPhoneVerifyFailedCode(String code) {
    return 'Phone verification didn\'t go through ($code)';
  }

  @override
  String get authPhoneVerifyFailedLater =>
      'Phone verification didn\'t go through. Please try again in a moment';

  @override
  String get authPhoneStepTitle => 'Step 2 · Phone verification';

  @override
  String get authPhoneStepDesc =>
      'Just enter the code we send by SMS and you\'re done! One number can verify only one account. We don\'t store your number — only an encrypted hash for checking.';

  @override
  String get authPhoneNumberLabel => 'Mobile number';

  @override
  String get authSending => 'Sending…';

  @override
  String get authGetCode => 'Get code';

  @override
  String get authCodeLabel => '6-digit code';

  @override
  String get authChecking => 'Checking…';

  @override
  String get authVerify => 'Verify';

  @override
  String get authChangeNumber => 'Change number';

  @override
  String get authResendCode => 'Resend code';

  @override
  String get authResponseSlow =>
      'This is taking too long. Check your connection and try again.';

  @override
  String get authRegisterFailed =>
      'Something went wrong while signing up. Please try again in a moment';

  @override
  String authReferralCredited(String nickname) {
    return '🎉 +200 QTA sent to your referrer $nickname!';
  }

  @override
  String get authReferralNotFound =>
      'We couldn\'t find that referrer nickname, so the invite bonus wasn\'t applied.';

  @override
  String get authReferralSelf => 'You can\'t enter yourself as a referrer.';

  @override
  String get authReferralAlreadyProcessed =>
      'This invite has already been used.';

  @override
  String get authRegisterTitle => 'Sign up';

  @override
  String get authRegisterHeadline => 'Just pick a nickname\nand you\'re in 🍆';

  @override
  String get authRegisterDesc =>
      'No wallet needed to sign up. After signing up, go to \'My Eggplant → Profile verification\' and finish Step 1 wallet verification and Step 2 phone verification to get 1,000 QTA.';

  @override
  String get authNicknameLabel => 'Nickname';

  @override
  String get authNicknameHint => '2–12 characters, must be unique';

  @override
  String get authNicknamePlaceholder => 'AnonEggplant123';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authMin8 => 'At least 8 characters';

  @override
  String get authPasswordPlaceholder =>
      'Mix of letters, numbers and symbols recommended';

  @override
  String get authPasswordConfirmLabel => 'Confirm password';

  @override
  String get authEnterAgain => 'Enter it again';

  @override
  String get authPasswordConfirmRequired => 'Please confirm your password';

  @override
  String get authPasswordMismatch => 'Passwords don\'t match';

  @override
  String get authReferrerLabel => 'Referrer nickname (optional)';

  @override
  String get authReferrerHint => 'Your friend gets +200 QTA · no limit';

  @override
  String get authReferrerPlaceholder =>
      'Nickname of the person who invited you';

  @override
  String get authRegisterBonusInfo =>
      'Finish wallet and phone verification to get +1,000 QTA! Enter a referrer and they get +200 QTA — no limit.\n※ If you delete your account after signing up, your referrer\'s bonus is taken back right away.';

  @override
  String get authWalletImmutableInfo =>
      'Your wallet address can\'t be changed. If you forget your nickname or password, you can only recover your account with the same wallet.';

  @override
  String get authRegisterButton => 'Sign up';

  @override
  String get authHaveAccountLogin => 'Already have an account? Log in';

  @override
  String get authServerSlow =>
      'The server is slow right now. Please try again in a moment 🕐';

  @override
  String get authLookupFailed =>
      'Something went wrong while looking up your account. Please try again.';

  @override
  String get authPasswordResetDone => 'Your new password is set 🔒';

  @override
  String get authResetFailed =>
      'Something went wrong while resetting your password. Please try again.';

  @override
  String get authFindAccountTitle => 'Find account';

  @override
  String get authFindHeadline => 'Find your account\nwith your wallet address';

  @override
  String get authFindDesc =>
      'Enter the Quantarium wallet address you used when you signed up.\nOnce you verify you own the wallet, you can see your nickname and set a new password.';

  @override
  String get authQuantariumWalletLabel => 'Quantarium wallet address';

  @override
  String get authPaste => 'Paste';

  @override
  String get authCheckAccount => 'Check account';

  @override
  String get authRegisteredNickname => 'Registered nickname';

  @override
  String get authNewPasswordTitle => 'Set a new password';

  @override
  String get authNewPasswordDesc =>
      'After resetting, all devices currently logged in will be logged out automatically.\nOn a device you\'ve used with this account, you can reset right away. On a different device or after reinstalling the app, you\'ll need the wallet verification below.';

  @override
  String get authNewPasswordLabel => 'New password';

  @override
  String get authNewPasswordConfirmLabel => 'Confirm new password';

  @override
  String get authResetPasswordButton => 'Reset password';

  @override
  String get authFindAgain => 'Search with a different wallet address';

  @override
  String get authWalletVerifiedInfo =>
      'Wallet verified — it\'s confirmed as yours';

  @override
  String get authVerifyAgain => 'Verify again';

  @override
  String get authWalletVerifyTitle => 'Wallet verification';

  @override
  String get authWalletRegisterTitle => 'Register wallet';

  @override
  String get authWalletVerifyResetTitle =>
      'Wallet verification (when resetting on another device)';

  @override
  String get authWalletVerifyDescRegister =>
      'To make sure no one else uses your wallet address, send the tiny amount shown on screen (less than 0.1 QTA) from this wallet to the Eggplant verification wallet to prove it\'s yours.';

  @override
  String get authWalletVerifyDescVerify =>
      'Send the tiny amount shown on screen (less than 0.1 QTA) from your Quantarium wallet to the Eggplant verification wallet to prove you own it. QTA you withdraw will be sent to this wallet.';

  @override
  String get authWalletVerifyDescReset =>
      'Send the tiny amount shown on screen (less than 0.1 QTA) from this wallet to the Eggplant verification wallet to prove it\'s yours. If someone signed up with your wallet first, you can get your account back this way.';

  @override
  String get authMyQuantariumWalletLabel => 'Your Quantarium wallet address';

  @override
  String get authWalletHint42 => '0x + 40 characters (42 total)';

  @override
  String get authPreparing => 'Preparing…';

  @override
  String get authWalletVerifyStart => 'Start wallet verification';

  @override
  String get authAmountToSend => 'Amount to send';

  @override
  String get authAmountCopied => 'Amount copied';

  @override
  String get authRecipientMyWallet => 'Recipient address (your wallet)';

  @override
  String get authRecipientEggplantWallet =>
      'Recipient address (Eggplant verification wallet)';

  @override
  String get authAddressCopied => 'Address copied';

  @override
  String authWalletSendInstruction(String wallet) {
    return 'In the Quantarium wallet app, send exactly the amount above from $wallet. Once it\'s in a block (usually a few seconds to a minute), tap the button below. You must send it within 30 minutes.';
  }

  @override
  String get authSentCheck => 'I\'ve sent it — check now';

  @override
  String get authNewAmount => 'Get a new amount';

  @override
  String get authCopy => 'Copy';

  @override
  String get authReceiveAmountInvalid =>
      'Enter the 6 digits after the decimal point (e.g. for 0.234567, enter 234567)';

  @override
  String get authWalletStepTitle => 'Step 1 · Wallet verification';

  @override
  String get authWalletStepDesc =>
      'Enter your Quantarium wallet address and the Eggplant HQ wallet will send you 5.xxxxxx QTA. Send back the 1.xxxxxx QTA the app tells you to the HQ wallet and you\'re verified! (Only the wallet owner can send, so it\'s safe)';

  @override
  String get authRequesting => 'Requesting…';

  @override
  String get authReceiveCoinButton => 'Get verification coins to this wallet';

  @override
  String get authReceiveSendFailed =>
      'We couldn\'t send the verification coins right now. Please request again in a moment';

  @override
  String get authRequestAgain => 'Request again';

  @override
  String authReceiveSending(String wallet) {
    return 'Sending from the Eggplant HQ wallet to $wallet… (usually under 1 minute)';
  }

  @override
  String authReceiveSent(String wallet) {
    return 'Sent! Check the amount that arrived in $wallet in the Quantarium wallet app and enter the 6 digits after the decimal point. It may take a few seconds to a minute to be included in a block.';
  }

  @override
  String get authCheckWalletCode => 'View my wallet on scan.quantarium.io';

  @override
  String get authReceivedAmount => 'Amount received';

  @override
  String authAttemptsLeft(String count) {
    return '$count tries left · enter within 24 hours';
  }

  @override
  String get authLoginFailed =>
      'Something went wrong while logging in. Please try again.';

  @override
  String get authLoginTitle => 'Log in';

  @override
  String get authLoginDesc =>
      'Log in with your nickname and password.\nQRChat members can log in right away with their QRChat nickname and password.';

  @override
  String get authLoginNicknameHint => 'The nickname you chose when signing up';

  @override
  String get authLoginButton => 'Log in';

  @override
  String get authFindNicknamePassword => 'Forgot nickname / password?';

  @override
  String get authSessionInfo =>
      'If you log in to the same account on another device, your session on the previous device ends immediately.';

  @override
  String get authSplashTagline => 'Safe, anonymous buy & sell 🍆';

  @override
  String get authOnboarding1Headline =>
      'No phone number needed\nBuy & sell anonymously';

  @override
  String get authOnboarding1Desc =>
      'A nickname is all you need.\nStay safe without exposing your personal info.';

  @override
  String get authOnboarding2Headline => 'Trade with neighbors\nin your area';

  @override
  String get authOnboarding2Desc =>
      'Meet only people verified in your neighborhood.\nMeet up with peace of mind using QR codes!';

  @override
  String get authOnboarding3Headline =>
      'Earn QTA token rewards\nthe more you use it';

  @override
  String get authOnboarding3Desc =>
      '+1,000 QTA for wallet & phone verification,\n+200 QTA for every friend you invite — no limit!';

  @override
  String get authPermTitle =>
      'For the best experience,\nwe need these permissions';

  @override
  String get authPermSubtitle => 'Allow once and we won\'t ask again.';

  @override
  String get authPermCamera => 'Camera';

  @override
  String get authPermCameraDesc => 'QR scanning · taking item photos/videos';

  @override
  String get authPermMic => 'Microphone';

  @override
  String get authPermMicDesc =>
      'Anonymous voice calls (heard only by the other person)';

  @override
  String get authPermPhotos => 'Photos / Videos';

  @override
  String get authPermPhotosDesc => 'Choose item photos from your gallery';

  @override
  String get authPermNotifications => 'Notifications';

  @override
  String get authPermNotificationsDesc => 'New chat · call alerts';

  @override
  String get authPermContinue => 'Got it, continue';

  @override
  String get authPermLater => 'Maybe later';

  @override
  String get authSkip => 'Skip';

  @override
  String get authStart => 'Get started';

  @override
  String get authNext => 'Next';

  @override
  String get authHaveAccountQuestion => 'Already have an account?';

  @override
  String get authDeleteAgreeRequired =>
      'You need to agree to the notice to delete your account.';

  @override
  String get authDeletePasswordRequired => 'Please enter your password.';

  @override
  String get authDeleteDialogTitle => 'Delete your account?';

  @override
  String get authDeleteDialogBody =>
      'Your account and all data will be permanently deleted right away.\nThis can\'t be undone, and any remaining QTA and referral bonuses received will be taken back.';

  @override
  String get authDeleteDialogConfirm => 'Delete permanently';

  @override
  String get authDeleteFailed =>
      'Something went wrong while deleting your account. Please try again.';

  @override
  String get authDeleteDone =>
      'Your account has been deleted. Thanks for using Eggplant. 🍆';

  @override
  String get authDeleteTitle => 'Permanently delete account';

  @override
  String get authDeleteWarning =>
      'Deleting your account is immediate and permanent\nDeleted data can\'t be recovered.';

  @override
  String get authDeleteDataTitle => 'Data that will be deleted';

  @override
  String get authDeleteBullet1 =>
      'Your nickname · neighborhood · manner score · manner reviews';

  @override
  String get authDeleteBullet2 => 'All items you\'ve listed';

  @override
  String authDeleteBullet3(String balance) {
    return 'Remaining QTA balance ($balance QTA) is forfeited';
  }

  @override
  String get authDeleteBullet4 =>
      'Friend invite bonuses you received are taken back right away (−200 QTA × people)';

  @override
  String get authDeleteBullet5 =>
      'Bonuses for friends who named you as referrer are also taken back right away';

  @override
  String get authDeleteBullet6 =>
      'Hidden items, blocks, keyword alerts and search history all disappear';

  @override
  String get authDeleteBullet7 =>
      'Chat messages and call history were never stored in the first place 🔐';

  @override
  String get authDeleteAgree =>
      'I understand all of the above and agree to permanent deletion.';

  @override
  String get authDeletePasswordTitle => 'Confirm your password';

  @override
  String get authDeleteButton => 'Delete permanently';

  @override
  String get authDeleteCancelBack => 'Cancel and go back';

  @override
  String get authProfileVerifyTitle => 'Profile verification';

  @override
  String get authProfileStepsTitle => 'Verification steps';

  @override
  String get authProfileStep0Title => 'Sign up';

  @override
  String get authProfileStep0Desc =>
      'Done automatically when you sign up with a nickname and password.\nBrowse · chat · call · list items.';

  @override
  String get authProfileStep1Desc =>
      'Enter your Quantarium wallet address and the Eggplant HQ wallet will send you 5.xxxxxx QTA.\nSend the 1.xxxxxx QTA shown back to HQ from that wallet and you\'re verified!\nQTA you withdraw will be sent to this wallet.';

  @override
  String get authProfileDoneLabel => 'Done';

  @override
  String get authProfileWalletDoneSnack =>
      'Wallet verified. Next up: Step 2 phone verification!';

  @override
  String get authProfileStep2Title => 'Phone verification';

  @override
  String get authProfileStep2Desc =>
      'Enter the code we send by SMS. One number can verify only one account.\nUnlocks completing deals · QTA payment deals · withdrawals.\n\n🔒 Your phone number is stored encrypted and used only to trace misuse. Only Philippine (09), Korean (010) and Japanese (070/080/090) mobile numbers can be verified.';

  @override
  String get authProfileWalletFirst =>
      'Please finish Step 1 wallet verification first.';

  @override
  String get authProfileComingSoon => 'Coming soon';

  @override
  String get authProfilePhoneStart => 'Start phone verification';

  @override
  String get authProfileStep1First => 'Step 1 first';

  @override
  String get authProfilePhoneDoneSnack => 'Phone verified';

  @override
  String get authProfilePolicyTitle => 'Anonymity policy';

  @override
  String get authProfilePolicy1 =>
      'In chats and voice calls, only your nickname is ever shown, no matter your verification step.';

  @override
  String get authProfilePolicy2 =>
      'Verification info is used only to check deal eligibility and is never shown to the other party or other users.';

  @override
  String get authProfilePolicy3 =>
      'The same wallet or phone number can\'t be used to verify multiple accounts.';

  @override
  String get authProfileBonusDialogTitle => 'Verified 🎉';

  @override
  String authProfileBonusDialogBody(String bonus) {
    return 'You\'ve completed Steps 1 and 2!\nWe\'ve sent you a +$bonus QTA verification bonus.\nYou can now make QTA payment deals and withdrawals.';
  }

  @override
  String get authProfileAllDone => 'Verified';

  @override
  String get authProfileStep1Done => 'Step 1 done · phone verification left';

  @override
  String get authProfileUnverified => 'Not verified';

  @override
  String authProfileProgress(String done) {
    return 'Verification $done/2 steps';
  }

  @override
  String authProfileBonusReceived(String bonus) {
    return 'You received a $bonus QTA verification bonus';
  }

  @override
  String authProfileBonusPending(String bonus) {
    return 'Finish Steps 1 and 2 to get $bonus QTA!';
  }

  @override
  String get authProfileDoneBadge => 'Done';

  @override
  String get authGuardPhoneTitle => 'Phone verification required';

  @override
  String get authGuardWalletTitle => 'Wallet verification required';

  @override
  String get authGuardPhoneMessage =>
      'To keep it one person, one account, deals (payments) require Step 1 wallet verification and Step 2 phone verification.\nYour chats and calls stay anonymous even after verifying.';

  @override
  String get authGuardWalletMessage =>
      'To withdraw QTA, you need Step 1 wallet verification and Step 2 phone verification.\nFinish both and you\'ll also get 1,000 QTA.';

  @override
  String get authGuardGoVerify => 'Verify now';

  @override
  String get authPassPopupTitle => 'Eggplant identity verification';

  @override
  String get authAccountSuspended => 'This account has been suspended';

  @override
  String authRegisterFailedStatus(String status) {
    return 'Sign-up failed (status=$status)';
  }

  @override
  String get authServerTooSlow =>
      'The server is taking too long. Check your connection and try again.';

  @override
  String get authDeleteFailedShort => 'Account deletion failed';

  @override
  String get authLoginFailedShort => 'Login failed';

  @override
  String get authSsoFailed => 'SSO verification failed';

  @override
  String get authNotFound => 'Not found';

  @override
  String get authResetFailedShort => 'Password reset failed';

  @override
  String get authRegionSaveFailed => 'Couldn\'t save your neighborhood';

  @override
  String get authNicknameLength => 'Nickname must be 2–12 characters';

  @override
  String get authNicknameChangeFailed => 'Couldn\'t change nickname';

  @override
  String get authWalletVerifyStartFailed =>
      'Couldn\'t start wallet verification';

  @override
  String get authTransferNotConfirmed =>
      'Your transfer hasn\'t been confirmed yet';

  @override
  String get authAmountCheckFailed => 'Couldn\'t check the amount';

  @override
  String get authCannotConnect =>
      'Can\'t connect to the server. Please try again in a moment.';

  @override
  String get authTimeout => 'The request timed out.';

  @override
  String get authGenericError => 'Something went wrong';

  @override
  String get authQuantumBadge =>
      'Sent with a quantum-resistant signature (SPHINCS+)';

  @override
  String get authViewTxOnScan => 'View the HQ transfer on scan.quantarium.io';

  @override
  String get authResetWalletTitle =>
      'Wallet verification (when resetting on another device)';

  @override
  String get authResetWalletDesc =>
      'We\'ll first check that it matches the wallet you registered, then the Eggplant HQ wallet will send 5.xxxxxx QTA to it. Send back the 1.xxxxxx QTA the app tells you to the HQ wallet and you\'re verified!';

  @override
  String get authResetWalletVerified =>
      'Wallet verified! Enter your new password below.';

  @override
  String get authScanHint =>
      'If the small amount doesn\'t show in your wallet app, tap the scan button above, check the Value on screen (e.g. 0.234567 QTA), and enter the 6 digits after the decimal point below.';

  @override
  String authReturnSent(String wallet, String amount) {
    return 'The Eggplant HQ wallet sent $amount QTA to $wallet.';
  }

  @override
  String get authReturnTitle => 'Now send this amount back to the HQ wallet';

  @override
  String get authReturnDesc =>
      'In the Quantarium wallet app, send exactly the amount below to the address below. Only the wallet owner can send, so this proves the wallet is yours.';

  @override
  String get authReturnAmountLabel => 'Amount to send back (exact)';

  @override
  String get authReturnToLabel => 'Recipient address (Eggplant HQ wallet)';

  @override
  String get authReturnNote =>
      'This amount works only this once · send within 2 hours · it may take a few seconds to a minute to be included in a block';

  @override
  String get authReturnSentButton => 'I\'ve sent it — check now';

  @override
  String get chatLeaveWarningSubtitle =>
      '🔒 Leaving deletes this chat for both of you';

  @override
  String get chatVoiceCallTooltip => 'Anonymous voice call';

  @override
  String get chatOfferSheetTitle => '💰 Make an offer';

  @override
  String chatOfferAmountHint(String unit) {
    return 'Offer amount ($unit)';
  }

  @override
  String get chatCurrencyUnitKrw => '₩';

  @override
  String get chatCurrencyUnitJpy => '¥';

  @override
  String get chatOfferSend => 'Send offer';

  @override
  String get chatOfferAutoCancelNote =>
      'Any earlier offer that hasn\'t been answered will be canceled automatically.';

  @override
  String get chatOfferAccept => 'Accept';

  @override
  String get chatOfferReject => 'Decline';

  @override
  String get chatOfferCancelAction => 'Cancel';

  @override
  String chatOfferDialogTitle(String action) {
    return '$action offer';
  }

  @override
  String get chatOfferAcceptConfirm => 'Go ahead with the deal at this price?';

  @override
  String get chatOfferRejectConfirm => 'Decline this offer?';

  @override
  String get chatPeerNotFound => 'Couldn\'t find this user\'s info';

  @override
  String get chatClearMessages => 'Clear messages';

  @override
  String get chatClearMessagesSubtitle =>
      'Only clears the messages in this chat (the chat stays)';

  @override
  String get chatLeaveRoom => 'Leave chat';

  @override
  String get chatLeaveRoomSubtitle =>
      'Permanently deletes the chat and messages for both of you (can\'t be undone)';

  @override
  String chatLeaveRoomConfirm(String nickname) {
    return 'Permanently delete your chat with $nickname?\n\n• All messages deleted forever\n• Removed from their screen right away\n• Can\'t be undone';
  }

  @override
  String get chatDeletePermanently => 'Delete permanently';

  @override
  String get chatDeleteFailedRetry =>
      'Couldn\'t delete. Please try again in a moment';

  @override
  String get chatClearMessagesConfirm =>
      'Clear all messages in this chat?\nThe chat stays, and the messages will also be cleared from their screen.';

  @override
  String get chatMessagesCleared => 'Messages cleared';

  @override
  String get chatDeleteFailed => 'Couldn\'t delete';

  @override
  String chatEmptyTitle(String nickname) {
    return 'Your anonymous chat with\n$nickname has started';
  }

  @override
  String get chatEmptyNote =>
      'This chat isn\'t saved on any server or device.\nOnce you leave this screen, it\'s gone.';

  @override
  String get chatRead => 'Read';

  @override
  String get chatOfferLabel => 'Offer';

  @override
  String get chatInputHint => 'Type a message';

  @override
  String get chatConnecting => 'Connecting...';

  @override
  String get chatOfferCancelButton => 'Cancel offer';

  @override
  String get chatCallOutgoing => 'Calling...';

  @override
  String get chatCallIncoming => 'Incoming anonymous call';

  @override
  String get chatCallEnded => 'Call ended';

  @override
  String get chatCallHeader => 'Fully anonymous voice call';

  @override
  String get chatCallP2pNote =>
      'This call connects directly (P2P).\nNothing is recorded or saved on our servers.';

  @override
  String get chatCallDecline => 'Decline';

  @override
  String get chatCallAccept => 'Answer';

  @override
  String get chatCallUnmute => 'Unmute';

  @override
  String get chatCallMute => 'Mute';

  @override
  String get chatCallHangup => 'End';

  @override
  String get chatCallSpeaker => 'Speaker';

  @override
  String get chatCallEarpiece => 'Earpiece';

  @override
  String chatLeaveRoomConfirmList(String nickname) {
    return 'Permanently delete your chat with $nickname?\n\n• Every message you\'ve exchanged will be gone\n• It\'ll be deleted from their screen too\n• This can\'t be undone';
  }

  @override
  String get chatRoomDeleted => 'Chat deleted';

  @override
  String get chatTabTitle => 'Chats';

  @override
  String get chatQrScanTooltip => 'Scan a QR code to start chatting';

  @override
  String get chatPrivacyBanner =>
      'Chats aren\'t saved anywhere. They disappear when you close the app.';

  @override
  String get chatListEmptyTitle => 'No chats yet';

  @override
  String get chatListEmptyHint =>
      'Tap \"Chat\" on an item you like to get started';

  @override
  String get chatSwipeLeave => 'Leave';

  @override
  String chatRoomAboutProduct(String title) {
    return 'Chat about $title';
  }

  @override
  String get chatSendFirstMessage => 'Say hi with a message';

  @override
  String chatLastMessageMine(String message) {
    return 'You: $message';
  }

  @override
  String get chatAnonymous => 'Anonymous';

  @override
  String get chatEnterAmount => 'Please enter an amount';

  @override
  String get chatReconnecting =>
      'Still connecting. Please try again in a moment';

  @override
  String get chatRoomNotFound => 'Couldn\'t find this chat';

  @override
  String get chatNewMessage => 'New message';

  @override
  String get chatEnterMessage => 'Please enter a message';

  @override
  String get chatCallPeerDeclined => 'The other person declined the call';

  @override
  String get chatCallRetryLater =>
      'We tried to connect. Please call again in a moment.';

  @override
  String get chatCallFailed => 'Call failed';

  @override
  String get chatCallAlreadyInCall => 'You\'re already on a call';

  @override
  String get chatCallStillConnecting => 'Still connecting';

  @override
  String get chatCallWaitingAnswer => 'Waiting for them to answer';

  @override
  String get chatCallHasIncoming => 'You have an incoming call';

  @override
  String get chatMicPermissionRequired => 'Microphone access is needed';

  @override
  String get chatCallServerDisconnected => 'Couldn\'t connect to the server';

  @override
  String get chatCallNoAnswer => 'No answer';

  @override
  String get chatMicPermissionSettings =>
      'Turn it on in Settings > Permissions > Microphone';

  @override
  String get chatCallAgoraConfigMissing => 'Agora settings are missing';

  @override
  String get chatCallPeerNotConnected => 'Couldn\'t reach the other person';

  @override
  String get chatCallEndedMessage => 'The call has ended';

  @override
  String get chatCallAuthExpired => 'Call authorization has expired';

  @override
  String get chatCallDisconnected => 'The call got disconnected';

  @override
  String get chatCallNetworkUnstable => 'Your connection is unstable';

  @override
  String get chatCallkitAppName => 'Eggplant';

  @override
  String get chatCallkitAccept => 'Answer';

  @override
  String get chatCallkitDecline => 'Decline';

  @override
  String get chatMissedCall => 'Missed call';

  @override
  String get chatIncomingCallChannel => 'Incoming calls (V2)';

  @override
  String get chatMissedCallChannel => 'Missed calls (V2)';

  @override
  String get chatChannelChatName => 'Chat messages';

  @override
  String get chatChannelChatDesc => 'Alerts for new chat messages';

  @override
  String get chatChannelKeywordName => 'Keyword alerts';

  @override
  String get chatChannelKeywordDesc =>
      'Alerts for new listings that match your keywords';

  @override
  String get chatChannelPushName => 'Eggplant messages';

  @override
  String get chatChannelPushDesc => 'Push notifications for new chat messages';

  @override
  String get chatChannelCallName => 'Eggplant calls';

  @override
  String get chatChannelCallDesc => 'Alerts for incoming voice calls';

  @override
  String get chatKeywordAlertTitle => '🔔 New listing alert';

  @override
  String get chatKeywordAlertMaskedBody =>
      'There\'s a new listing that matches your keywords';

  @override
  String get chatKeywordTicker => 'New listing';

  @override
  String get chatMaskedMessageTitle => '💬 You have a new message';

  @override
  String get chatMaskedMessageBody => 'Tap to view the message';

  @override
  String get chatPermMicBody =>
      'Turn on the microphone in Settings > Apps > Eggplant.';

  @override
  String get chatPermCameraTitle => 'Camera access is needed';

  @override
  String get chatPermCameraBody =>
      'Turn on the camera in Settings > Apps > Eggplant.';

  @override
  String get chatPermGalleryTitle => 'Photo access is needed';

  @override
  String get chatPermGalleryBodyAndroid =>
      'Turn on Photos and videos access in Settings > Apps > Eggplant.';

  @override
  String get chatPermGalleryBodyIos =>
      'Turn on Photos access in Settings > Eggplant.';

  @override
  String get chatPermNotifTitle => '🔔 Notifications are off';

  @override
  String get chatPermNotifBody =>
      'With notifications off, you might miss new messages, calls, and keyword listing alerts.\n\nTurn on notifications in Settings?\n\n※ Eggplant can also hide notification content on your lock screen. Turn it on in \"My Eggplant > Hide notification content\".';

  @override
  String get chatPermOpenSettings => 'Open Settings';

  @override
  String get chatPermFsiTitle => '🔒 Lock screen call alerts';

  @override
  String get chatPermFsiBody =>
      'To show incoming calls on your lock screen,\nthe \"Full-screen notifications\" permission is needed.\n\nIf it\'s off, your phone will only ring\nand the call screen won\'t appear on the lock screen.\n\nYou only need to set this once.';

  @override
  String get chatPermAllow => 'Allow';

  @override
  String get chatOfferStatusAccepted => 'Accepted';

  @override
  String get chatOfferStatusRejected => 'Declined';

  @override
  String get chatOfferStatusCancelled => 'Canceled';

  @override
  String get chatOfferStatusPending => 'Awaiting reply';

  @override
  String get chatTimeJustNow => 'Just now';

  @override
  String chatTimeMinutesAgo(int n) {
    return '${n}m ago';
  }

  @override
  String chatTimeHoursAgo(int n) {
    return '${n}h ago';
  }

  @override
  String chatTimeDaysAgo(int n) {
    return '${n}d ago';
  }

  @override
  String chatTimeWeeksAgo(int n) {
    return '${n}w ago';
  }

  @override
  String chatTimeMonthsAgo(int n) {
    return '${n}mo ago';
  }

  @override
  String chatTimeYearsAgo(int n) {
    return '${n}y ago';
  }

  @override
  String get chatCurrencyUnitPhp => '₱';

  @override
  String get chatAttachTooltip => 'Photo · Meetup';

  @override
  String get chatAttachGallery => 'Send a photo from gallery';

  @override
  String get chatAttachCamera => 'Take a photo';

  @override
  String get chatAttachAppointment => 'Schedule a meetup';

  @override
  String get chatPhotoSendFailed =>
      'Couldn\'t send the photo. Please try again';

  @override
  String get chatPhotoUnavailable =>
      'Can\'t open this photo\n(it expired after 24 hours or was already deleted)';

  @override
  String get chatAppointmentChange => 'Change';

  @override
  String chatAppointmentSetBy(String name) {
    return '$name scheduled a meetup';
  }

  @override
  String chatAppointmentCancelledBy(String name) {
    return '$name cancelled the meetup';
  }

  @override
  String get chatAppointmentReminderNote =>
      'We\'ll remind you 30 minutes before';

  @override
  String get chatAppointmentTitle => 'Schedule a meetup';

  @override
  String get chatAppointmentEditTitle => 'Change the meetup';

  @override
  String get chatAppointmentPlace => 'Meeting place (optional)';

  @override
  String get chatAppointmentCancel => 'Cancel meetup';

  @override
  String get chatAppointmentSend => 'Send';

  @override
  String get chatAppointmentPast => 'Please choose a time in the future';

  @override
  String get chatAppointmentReminderTitle => 'You have a meetup in 30 minutes';

  @override
  String get chatAppointmentReminderBody => 'Please be on time';

  @override
  String get chatAppointmentSetByMe => 'You scheduled a meetup';

  @override
  String get chatAppointmentCancelledByMe => 'You cancelled the meetup';

  @override
  String get ctTab => 'CoinTrip';

  @override
  String get ctTitle => 'CoinTrip';

  @override
  String get ctNetworkError => 'Check your network and try again';

  @override
  String get ctLocationFailed =>
      'We couldn\'t find your location. Please try again shortly';

  @override
  String get ctUnion => 'Friend union';

  @override
  String get ctMyWallet => 'Coin wallet';

  @override
  String get ctIntroTitle => 'Welcome to CoinTrip';

  @override
  String get ctIntroFind =>
      'Find coins scattered on the map. Whoever picks one up first keeps it.';

  @override
  String ctIntroPick(int meters) {
    return 'Get within ${meters}m of a coin and the [Pick up] button turns on. Coins far away show only a rough area.';
  }

  @override
  String ctIntroBlack(int qta) {
    return 'Black coins are an adventure. Most hold good coins, but some are empty (a dud) or a penalty. On a penalty you must watch an ad to the end or give up $qta of your QTA. Think before you grab!';
  }

  @override
  String ctIntroUnion(String times) {
    return 'Form a friend union and everyone shares whatever any member picks up. The finder gets ${times}x.';
  }

  @override
  String get ctIntroWallet =>
      'A coin shows on the map once you register a wallet for it: a Quantarium wallet for Quantarium coins, a 0x address for Ethereum, BNB and Polygon coins, and a Solana address for Solana coins.';

  @override
  String get ctIntroSafety =>
      'Watch your surroundings, not the screen, while walking. Never enter roads, construction sites, private property, or other places you shouldn\'t go.';

  @override
  String get ctRedNotice =>
      'Coins sent to a wrong address because you entered it incorrectly are entirely your own responsibility. They cannot be returned, so always double-check the address.';

  @override
  String get ctAckCheck => 'I have read and understood the above';

  @override
  String get ctAckButton => 'I understand';

  @override
  String get ctNeedWalletTitle => 'Register a wallet to see coins';

  @override
  String get ctNeedWalletBody =>
      'Quantarium coins go to your Quantarium wallet, Ethereum, BNB and Polygon coins to a 0x address, and Solana coins to a Solana address. Coins you have no wallet for don\'t appear on the map.';

  @override
  String get ctRegisterWallet => 'Register a wallet';

  @override
  String get ctLocationServiceOff => 'Turn on your phone\'s location (GPS)';

  @override
  String get ctLocationNeeded => 'Please allow location access';

  @override
  String get ctLocationWhy =>
      'CoinTrip uses your location only to show nearby coins and to check that you\'re close enough. Your location isn\'t stored.';

  @override
  String get ctRefresh => 'Refresh';

  @override
  String get ctMyCoinWalletMenu => 'CoinTrip coin wallet (coins you picked up)';

  @override
  String get ctRetry => 'Try again';

  @override
  String get ctOpenSettings => 'Open settings';

  @override
  String get ctNoCoinsShort => 'No coins nearby';

  @override
  String ctNearby(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coins',
      one: '1 coin',
    );
    return '$_temp0';
  }

  @override
  String get ctNoCoinsNearby => 'No coins nearby. Zoom out or come back later.';

  @override
  String get ctPhoneRequired =>
      'Phone verification is required to pick up coins';

  @override
  String get ctVerifyPhone => 'Verify';

  @override
  String get ctMockedLocation =>
      'You can\'t pick up coins while a fake-location app is on';

  @override
  String ctDistanceM(int meters) {
    return '${meters}m';
  }

  @override
  String ctDistanceKm(String km) {
    return '${km}km';
  }

  @override
  String get ctBlackCoin => 'Black coin';

  @override
  String ctBlackCoinHint(int qta) {
    return 'Adventure coin — mostly good coins, sometimes empty or a penalty (an ad or $qta QTA)';
  }

  @override
  String ctApprox(int meters) {
    return 'This is a rough area. Get within ${meters}m to see the exact spot.';
  }

  @override
  String get ctGoldCoin => 'Gold coin';

  @override
  String get ctGoldCoinHint =>
      'You won\'t know which coin or how much until you pick it up';

  @override
  String get ctRevealTitle => 'Watch an ad to open';

  @override
  String get ctRevealBody =>
      'Watch an ad to the end to see which coin and how many are inside — and get them.';

  @override
  String get ctRevealDeadline =>
      'If you don\'t watch, you don\'t get it and the coin goes back on the map (decide within 10 minutes)';

  @override
  String get ctRevealWatch => 'Watch ad and open';

  @override
  String get ctRevealGiveUp => 'Give up (coin goes back on the map)';

  @override
  String get ctEmptyTitle => 'Empty!';

  @override
  String get ctEmptyBody =>
      'This black coin was empty. You lose nothing. Try the next one!';

  @override
  String get ctDudTitle => 'Penalty!';

  @override
  String ctDudBody(int qta) {
    return 'The black coin held a penalty. Watch an ad to the end and you\'re off the hook; otherwise you give up $qta of your QTA.';
  }

  @override
  String get ctDudDeadline =>
      'If you don\'t choose within 10 minutes, the QTA is taken';

  @override
  String get ctDudWatchAd => 'Watch an ad';

  @override
  String ctDudPay(int qta) {
    return 'Pay $qta QTA';
  }

  @override
  String get ctDudAdNotFinished => 'You need to watch the ad to the end';

  @override
  String get ctDudAdFailed => 'Couldn\'t load the ad. Please try again shortly';

  @override
  String get ctDudAdChecking =>
      'Ad confirmation is taking a while. Please tap again shortly';

  @override
  String get ctDudAdOk => 'You watched the ad — you\'re off the hook';

  @override
  String ctDudPaid(int qta) {
    return 'You paid $qta QTA';
  }

  @override
  String get ctPick => 'Pick up';

  @override
  String ctGetCloser(int meters) {
    return 'Pick up within ${meters}m';
  }

  @override
  String get ctPickedTitle => 'You picked up a coin!';

  @override
  String get ctBlackOpened => 'You opened the black coin…';

  @override
  String ctSharedWith(String total, String symbol) {
    return '$total $symbol in total — shared with your union';
  }

  @override
  String ctSharedMore(int count) {
    return 'and $count more';
  }

  @override
  String get ctToWallet => 'Added to your in-app coin wallet';

  @override
  String get ctWithdrawDone =>
      'Withdrawal requested. We\'ll send it after review.';

  @override
  String get ctReceiveWallets => 'Receiving wallets';

  @override
  String get ctQuantariumWallet => 'Quantarium wallet';

  @override
  String get ctQuantariumWalletSub => 'Receives Quantarium coins';

  @override
  String get ctRegister => 'Register';

  @override
  String get ctChange => 'Change';

  @override
  String get ctExtWallet => 'Existing wallet address';

  @override
  String get ctExtWalletSub => 'Receives Ethereum, BNB and Polygon coins';

  @override
  String get ctNotRegistered => 'Not registered';

  @override
  String get ctMyCoins => 'Coins collected';

  @override
  String get ctNoBalances => 'You haven\'t picked up any coins yet';

  @override
  String get ctWithdrawals => 'Withdrawal history';

  @override
  String ctWithdrawMin(String amount, String symbol) {
    return 'Min. withdrawal $amount $symbol';
  }

  @override
  String get ctWithdraw => 'Withdraw';

  @override
  String get ctWdRequested => 'Requested';

  @override
  String get ctWdProcessing => 'Sending';

  @override
  String get ctWdCompleted => 'Sent';

  @override
  String get ctWdRejected => 'Rejected (refunded)';

  @override
  String ctWithdrawTitle(String symbol) {
    return 'Withdraw $symbol';
  }

  @override
  String get ctWithdrawAmount => 'Amount to withdraw';

  @override
  String ctWithdrawRange(String min, String max, String symbol) {
    return '$min – $max $symbol';
  }

  @override
  String get ctWithdrawTo => 'Receiving address';

  @override
  String get ctWithdrawNoAddress => 'Please register a receiving wallet first';

  @override
  String get ctWithdrawSubmit => 'Request withdrawal';

  @override
  String get ctSaved => 'Saved';

  @override
  String get ctRemove => 'Remove';

  @override
  String get ctRemoveConfirm =>
      'Remove this wallet address? Other coins will no longer appear on the map.';

  @override
  String get ctExtWalletDesc =>
      'This address receives Ethereum, BNB and Polygon coins. One 42-character address starting with 0x works for all three chains. If it\'s an exchange deposit address, make sure it matches the coin\'s chain.';

  @override
  String get ctSolWallet => 'Solana wallet address';

  @override
  String get ctSolWalletSub => 'Receives Solana coins';

  @override
  String get ctSolWalletDesc =>
      'This address receives Solana coins. Enter a Solana address (32–44 characters, not 0x). If it\'s an exchange deposit address, make sure it\'s on the Solana chain.';

  @override
  String get ctSolWalletInvalid => 'Not a Solana wallet address';

  @override
  String get ctSolRemoveConfirm =>
      'Remove your Solana address? Solana coins will no longer appear on the map.';

  @override
  String get ctExtWalletLabel => 'Wallet address';

  @override
  String get ctExtWalletInvalid =>
      'Not a 42-character address starting with 0x';

  @override
  String get ctPaste => 'Paste';

  @override
  String get ctSave => 'Save';

  @override
  String ctUnionDesc(String times, int max) {
    return 'Whenever any member picks up a coin, everyone shares it. The finder gets $times shares, everyone else 1 share. Up to $max members.';
  }

  @override
  String ctUnionExample(String total, String finder, String each) {
    return 'e.g. In a union of 3, picking up $total gives the finder $finder and the other two $each each';
  }

  @override
  String get ctUnionWalletNote =>
      'Members who don\'t have a wallet for that coin are left out of that coin\'s share.';

  @override
  String get ctUnionCreate => 'Create a union';

  @override
  String get ctUnionName => 'Union name';

  @override
  String get ctUnionJoin => 'Join with an invite code';

  @override
  String get ctUnionCode => 'Invite code';

  @override
  String get ctUnionJoinButton => 'Join';

  @override
  String get ctUnionCopy => 'Copy';

  @override
  String ctUnionShareText(String code) {
    return 'Join my Eggplant CoinTrip union! In the app, go to CoinTrip > Friend union and enter invite code $code.';
  }

  @override
  String get ctUnionCopied => 'Invite message copied. Send it to your friends.';

  @override
  String ctUnionMembers(int count, int max) {
    return 'Members $count/$max';
  }

  @override
  String get ctMe => 'me';

  @override
  String get ctUnionOwner => 'Leader';

  @override
  String get ctUnionKick => 'Remove';

  @override
  String ctUnionKickConfirm(String nickname) {
    return 'Remove $nickname from the union?';
  }

  @override
  String get ctUnionLeave => 'Leave union';

  @override
  String get ctUnionLeaveConfirm =>
      'Leave this union? After leaving you won\'t receive shares of coins members pick up.';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'OK';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonLater => 'Later';

  @override
  String get commonFree => 'Free';

  @override
  String get commonLoginRequired => 'Please log in first';

  @override
  String get commonNetworkError =>
      'Network error. Please try again in a moment.';

  @override
  String priceKrw(String amount) {
    return '₩$amount';
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
  String get homeSearchHint => 'Search items';

  @override
  String get homeSetRegion => 'Set neighborhood';

  @override
  String get homeSearchClose => 'Close search';

  @override
  String get homeSearch => 'Search';

  @override
  String get homeQrScan => 'Scan QR';

  @override
  String get homeRecentSearches => 'Recent searches';

  @override
  String get homeClearAll => 'Clear all';

  @override
  String get homeNoRecentSearches => 'No recent searches';

  @override
  String get homeRangeAll => 'All';

  @override
  String get homeDistance => 'Distance';

  @override
  String get homeNoProducts => 'No listings yet';

  @override
  String get homeCheckNetwork => 'Check your connection and try again';

  @override
  String get homeFirstProduct => 'Be the first to post a listing!';

  @override
  String get homeRefresh => 'Refresh';

  @override
  String homeMyRegionsTitle(int count, int max) {
    return 'My neighborhoods $count/$max';
  }

  @override
  String get homeMyRegionsHint =>
      'Tap All to see every area you picked, or one area to see only that one.';

  @override
  String get homeRemoveRegion => 'Remove this neighborhood';

  @override
  String homeMaxRegions(int max) {
    return 'You can add up to $max neighborhoods';
  }

  @override
  String get homeAddRegion => 'Add a neighborhood';

  @override
  String get homeCategoryAll => 'All';

  @override
  String get homeCategoryDigital => 'Electronics';

  @override
  String get homeCategoryAppliance => 'Home appliances';

  @override
  String get homeCategoryFurniture => 'Furniture & decor';

  @override
  String get homeCategoryClothing => 'Clothing';

  @override
  String get homeCategoryBeauty => 'Beauty';

  @override
  String get homeCategoryBook => 'Books & tickets';

  @override
  String get homeCategorySports => 'Sports & outdoors';

  @override
  String get homeCategoryHobby => 'Hobbies & games';

  @override
  String get homeCategoryKids => 'Baby & kids';

  @override
  String get homeCategoryPet => 'Pets';

  @override
  String get homeCategoryFood => 'Food';

  @override
  String get homeCategoryEtc => 'Others';

  @override
  String get homeLikesTitle => 'Saved items';

  @override
  String homeLikesTitleCount(int count) {
    return 'Saved items $count';
  }

  @override
  String get homeLoadFailed => 'Couldn\'t load';

  @override
  String get homeTryLater => 'Please try again in a moment';

  @override
  String get homeNoLikes => 'No saved items yet';

  @override
  String get homeNoLikesHint => 'Tap the heart on items you like';

  @override
  String get homeSignupBonus => '🎉 Welcome! You got +500 QTA';

  @override
  String homeLoginBonusRemaining(int remaining) {
    return ' · $remaining more left today';
  }

  @override
  String get homeLoginBonusLimitReached => ' · Daily limit reached!';

  @override
  String homeLoginBonus(int amount, String tail) {
    return '📅 Daily check-in bonus +$amount QTA$tail';
  }

  @override
  String get homeWrite => 'Sell';

  @override
  String get homeTabHome => 'Home';

  @override
  String get homeTabLikes => 'Saved';

  @override
  String get homeTabChat => 'Chats';

  @override
  String get homeTabMy => 'Me';

  @override
  String get homeLocationServiceOff =>
      'Please turn on location services (Settings > Location)';

  @override
  String get homeLocationPermissionNeeded =>
      'Location access is needed. Please allow it in Settings.';

  @override
  String homeRegionVerifiedToast(String region) {
    return '$region verified 🎉';
  }

  @override
  String get homeMyRegion => 'My neighborhood';

  @override
  String get homeLocationFailed =>
      'Couldn\'t get your current location. Please check location access and GPS';

  @override
  String get homeRegionVerified => 'Neighborhood verified';

  @override
  String get homeRegionVerifyNeeded => 'Verify your neighborhood';

  @override
  String homeRegionVerifiedDesc(String region) {
    return '$region · Confirmed within 4 km by GPS';
  }

  @override
  String homeRegionVerifyDesc(String region) {
    return '$region · Verify with GPS to sort by distance';
  }

  @override
  String get homeReverify => 'Re-verify';

  @override
  String get homeVerify => 'Verify';

  @override
  String get homeRegionSettingsTitle => 'My neighborhood settings';

  @override
  String get homeRegionSearchHint => 'Search by area (e.g. Makati)';

  @override
  String get homeRegionVerifyDialogTitle => 'Verify your neighborhood?';

  @override
  String homeRegionVerifyDialogBody(String region) {
    return 'Confirm once with GPS that you really live in $region, and you can sort search results by distance.\n\nYour exact location is never saved on our servers.';
  }

  @override
  String get homeVerifyNow => 'Verify now';

  @override
  String homeRegionSet(String region) {
    return 'Neighborhood set to $region';
  }

  @override
  String get homeLoginToUse => 'Please log in to continue';

  @override
  String get homeMyQr => 'My QR code';

  @override
  String get homeShowQr => 'Show this QR to the other person';

  @override
  String get homeQrDesc =>
      'Scan the QR to start an anonymous chat instantly 💨';

  @override
  String get homeQrAnonymous => '🔐 Fully anonymous · Chats not saved';

  @override
  String get homeQrLinkCopied => 'QR link copied';

  @override
  String get homeQrCopyLink => 'Copy QR link';

  @override
  String get homeQrNotEggplant => 'This isn\'t an Eggplant QR code';

  @override
  String get homeQrInvalid => 'Invalid QR code format';

  @override
  String get homeQrOwn => 'You can\'t scan your own QR code';

  @override
  String get homeQrChatFailed => 'Couldn\'t open the chat';

  @override
  String get homeQrScanGuide => 'Line up the Eggplant QR code inside the frame';

  @override
  String get homeQrScanDesc => 'An anonymous chat starts as soon as you scan';

  @override
  String get homeAnonymous => 'Anonymous';

  @override
  String homePageNotFound(String error) {
    return 'Page not found: $error';
  }

  @override
  String get homeGoHome => 'Go home';

  @override
  String get homeLinkBroken =>
      'This link can\'t be opened. If it\'s an old QR link, ask the other person for a new QR.';

  @override
  String get homeFilterAvailable => 'Available only';

  @override
  String get homeFilterPrice => 'Price';

  @override
  String get homeSortRecent => 'Newest';

  @override
  String get homeSortPriceAsc => 'Price: low to high';

  @override
  String get homeSortPriceDesc => 'Price: high to low';

  @override
  String get homeSortTitle => 'Sort';

  @override
  String get homePriceTitle => 'Price range';

  @override
  String get homePriceMin => 'Min';

  @override
  String get homePriceMax => 'Max';

  @override
  String get homePriceReset => 'Reset';

  @override
  String get homePriceApply => 'Apply';

  @override
  String get homePriceInvalid => 'Min price is higher than max price';

  @override
  String get homeFilterNoResult => 'No items match your filters';

  @override
  String get homeFilterClear => 'Clear filters';

  @override
  String get homeAllMyRegions => 'All my areas';

  @override
  String homeAllMyRegionsCount(int count) {
    return 'My $count areas';
  }

  @override
  String get homeFilterFree => 'Free';

  @override
  String get homePopularSearches => 'Popular searches';

  @override
  String get inboxTitle => 'Notifications';

  @override
  String get inboxEmpty => 'No notifications yet';

  @override
  String get inboxEmptyHint =>
      'Price drops on saved items, deal confirmations, reviews and keyword alerts show up here. Kept for 30 days.';

  @override
  String get inboxLoadFailed =>
      'Couldn\'t load notifications. Pull down to try again.';

  @override
  String get inboxClearConfirm => 'Delete all notifications?';

  @override
  String get recentTitle => 'Recently viewed';

  @override
  String get recentEmpty => 'No recently viewed items';

  @override
  String get myTabTitle => 'My Eggplant';

  @override
  String myMannerTemp(String temp) {
    return 'Manner temperature $temp°C';
  }

  @override
  String get myRegionUnset => 'No neighborhood set';

  @override
  String get myMenuSelling => 'My listings';

  @override
  String get myMenuLikes => 'Saved items';

  @override
  String get myMenuChat => 'Chats';

  @override
  String get myMenuProfile => 'Set up profile / Edit nickname';

  @override
  String get myMenuProfileSub => 'Set the nickname shown in chats and calls';

  @override
  String get myMenuRegion => 'My neighborhood';

  @override
  String get myRegionNeeded => 'Not set';

  @override
  String get myMenuQr => 'My QR code';

  @override
  String get myMenuQrSub => 'Show it to a friend to start chatting';

  @override
  String get myMenuInvite => 'Invite friends (+200 QTA)';

  @override
  String get myMenuInviteSub =>
      'Get +200 QTA when a friend enters your nickname at sign-up · No limit';

  @override
  String get myMenuKeyword => 'Keyword alerts';

  @override
  String get myMenuKeywordSub =>
      'Add keywords and get notified about new listings';

  @override
  String get myMenuHidden => 'Hidden posts';

  @override
  String get myMenuHiddenSub => 'See posts you\'ve hidden';

  @override
  String get myMenuPrivacy => 'Privacy';

  @override
  String get myMenuPrivacySub =>
      'Chats and calls are never stored · Messages disappear for good';

  @override
  String get myPrivacyDialogTitle => 'Privacy';

  @override
  String get myMenuAppInfo => 'App info';

  @override
  String get myAppLegalese =>
      '© 2026 Eggplant Team\nSafe, anonymous buy & sell';

  @override
  String get myMenuLogout => 'Log out';

  @override
  String get myMenuDeleteAccount => 'Delete account permanently';

  @override
  String get myMenuDeleteAccountSub =>
      'This can\'t be undone · Remaining QTA and referral bonuses are taken back immediately';

  @override
  String get myStatSelling => 'Selling';

  @override
  String get myStatLikes => 'Saved';

  @override
  String get myWalletCopied =>
      'Wallet address copied. You can paste it to recover your nickname or password.';

  @override
  String get myQtaBalance => 'QTA balance';

  @override
  String get myHistory => 'History';

  @override
  String get myHide => 'Hide';

  @override
  String get myShowAll => 'Show all';

  @override
  String get myCopy => 'Copy';

  @override
  String get myWithdrawRequestBtn => 'Withdraw to wallet';

  @override
  String get myWithdrawNeedMin => 'You need at least 5,000 QTA to withdraw';

  @override
  String get myWalletCardNote =>
      'Forgot your nickname or password? You can recover your account with this wallet address.\nWithdraw to your own wallet from 5,000 QTA, in multiples of 5,000.';

  @override
  String get myMaskOnSnack =>
      'Notification content is now hidden. Safe to use on your lock screen 🔒';

  @override
  String get myMaskOffSnack => 'Notification content will be shown';

  @override
  String get myMaskTitle => 'Hide notification content';

  @override
  String get myMaskSub =>
      'Show \"You have a new message\" instead of the message on lock screen / push previews';

  @override
  String get myUnverified => 'Not verified';

  @override
  String get myCtaPhoneOpenTitle =>
      'Step 2: Verify your phone and get 1,000 QTA';

  @override
  String get myCtaPhoneSoonTitle => 'Step 2: Phone verification · Coming soon';

  @override
  String get myCtaWalletTitle => 'Start with Step 1: Wallet verification';

  @override
  String get myCtaPhoneOpenDesc =>
      'Last step! Your chats and calls stay anonymous even after verifying.';

  @override
  String get myCtaPhoneSoonDesc =>
      'Step 1 done! Once phone verification opens, finish it to get 1,000 QTA.';

  @override
  String get myCtaWalletDesc =>
      'Complete both wallet and phone verification to get 1,000 QTA.';

  @override
  String get myBrowseCreditedTitle => 'You got today\'s mining bonus!';

  @override
  String get myBrowseTitle => 'Today\'s browse mining';

  @override
  String get myBrowseCreditedSub => 'Resets tomorrow at midnight (KST).';

  @override
  String myBrowseSub(int threshold) {
    return 'View $threshold items to earn +10 QTA';
  }

  @override
  String get myBrowseStart => 'Browse items on the Home tab 🛍️';

  @override
  String myBrowseRemaining(int count) {
    return 'View $count more to get +10 QTA!';
  }

  @override
  String get myBrowseSoon => 'Crediting soon…';

  @override
  String get myBrowseLink =>
      'View mining history · Mine 10% of the price when you list an item';

  @override
  String get myUserNotFound => 'User not found';

  @override
  String get myServerSlow =>
      'The server is slow to respond. Please try again in a moment 🕐';

  @override
  String get myLoadError => 'Something went wrong while loading';

  @override
  String get myMoreReviewsSlow =>
      'Loading more reviews is taking a while. Please try again in a moment 🕐';

  @override
  String get myThisUser => 'this user';

  @override
  String get myBlockConfirmTitle => 'Block this user?';

  @override
  String myBlockConfirmBody(String nick) {
    return 'If you block $nick, you won\'t see each other\'s posts or chats. You can unblock anytime.';
  }

  @override
  String get myBlock => 'Block';

  @override
  String myBlockedSnack(String nick) {
    return 'You blocked $nick';
  }

  @override
  String get myUnblockConfirmTitle => 'Unblock this user?';

  @override
  String myUnblockConfirmBody(String nick) {
    return 'You\'ll be able to see $nick again.';
  }

  @override
  String get myUnblockShort => 'Unblock';

  @override
  String get myUnblockedSnack => 'User unblocked';

  @override
  String get myReportSpam => 'Spam / Ads';

  @override
  String get myReportFraud => 'Suspected scam';

  @override
  String get myReportAbuse => 'Abusive language';

  @override
  String get myReportInappropriate => 'Inappropriate content';

  @override
  String get myReportFake => 'Fake listing';

  @override
  String get myReportOther => 'Other';

  @override
  String get myReportTitle => 'Why are you reporting this?';

  @override
  String get myReportDesc =>
      'If several people report the same reason, our team will review it.';

  @override
  String get myReportDetailHint => 'More details (optional)';

  @override
  String get myReportDone => 'Report submitted';

  @override
  String get myReportSubmit => 'Report';

  @override
  String get myProfileMine => 'My profile';

  @override
  String get myProfileSeller => 'Seller info';

  @override
  String get myUnblockMenu => 'Unblock';

  @override
  String get myBlockMenu => 'Block';

  @override
  String get myTopPraise => 'Top manner compliments';

  @override
  String get myReceivedReviews => 'Reviews received';

  @override
  String get myNoReviews => 'No reviews yet';

  @override
  String get myAnonNickname => 'Anonymous Eggplant';

  @override
  String get myMannerLabel => 'Manner temperature';

  @override
  String get myReviewsLabel => 'Reviews';

  @override
  String get myRatingGood => 'Good';

  @override
  String get myRatingSoso => 'Okay';

  @override
  String get myRatingBad => 'Not great';

  @override
  String myAgoMinutes(int n) {
    return '${n}m ago';
  }

  @override
  String myAgoHours(int n) {
    return '${n}h ago';
  }

  @override
  String myAgoDays(int n) {
    return '${n}d ago';
  }

  @override
  String myAgoWeeks(int n) {
    return '${n}w ago';
  }

  @override
  String myAgoMonths(int n) {
    return '${n}mo ago';
  }

  @override
  String get myPhotoLoadFail =>
      'Couldn\'t load the photo. Check permissions and try again';

  @override
  String get myNicknameEmpty => 'Please enter a nickname';

  @override
  String get myNicknameTooShort => 'Nickname must be at least 2 characters';

  @override
  String get myNicknameTooLong => 'Nickname must be 12 characters or less';

  @override
  String get myProfileSaved =>
      'Profile saved. It shows up in chats and calls right away ✨';

  @override
  String get myProfilePhotoSaved => 'Profile photo saved ✨';

  @override
  String get myProfileEditTitle => 'Profile';

  @override
  String get myPhotoChange => 'Change photo';

  @override
  String get myPhotoAdd => 'Add photo';

  @override
  String get myPhotoReset => 'Use default eggplant';

  @override
  String get myNicknameIntro => 'Set the nickname shown in chats and calls';

  @override
  String get myNicknameLabel => 'Nickname';

  @override
  String get myNicknameHint => '2–12 characters, letters/numbers';

  @override
  String get myNicknameGuideTitle => 'About nicknames';

  @override
  String get myNicknameGuideBody =>
      '• Changes show up in chats and calls right away\n• Must be different from other users\' nicknames\n• Only your nickname is shown, whether or not you\'re verified';

  @override
  String get mySaveButton => 'Save';

  @override
  String get myWdNeedWalletTitle => 'Step 1 wallet verification required';

  @override
  String get myWdNeedWalletBody =>
      'Withdrawn QTA is sent to your verified wallet.\nEnter the amount our official wallet sent you to confirm you own the wallet.';

  @override
  String get myWdNeedPhoneTitle => 'Step 2 phone verification required';

  @override
  String get myWdPreparingTitle => 'Withdrawals coming soon';

  @override
  String get myWdNeedPhoneBody =>
      'To keep it one account per person, phone verification is required before withdrawing.\nYou\'ll also get 1,000 QTA when you finish.';

  @override
  String get myWdPreparingBody =>
      'Withdrawals need phone verification, which we\'re still preparing.\nWe\'ll let you know with an app update once it\'s ready. Your QTA keeps adding up in the meantime.';

  @override
  String get myWdNoWallet => 'No wallet address registered';

  @override
  String myWdInsufficientMin(String min) {
    return 'Not enough balance. You can request from $min QTA.';
  }

  @override
  String get myWdConfirmTitle => 'Request withdrawal';

  @override
  String myWdConfirmBody(String amount, String wallet) {
    return 'Withdraw $amount QTA to\n$wallet\n?\n\nThe amount is deducted from your balance right away, and our team will send it within 1–3 days.';
  }

  @override
  String get myWdApply => 'Request';

  @override
  String get myWdRequested =>
      'Withdrawal requested — we\'ll let you know once it\'s processed';

  @override
  String get myWdCancelTitle => 'Cancel request';

  @override
  String myWdCancelBody(String amount) {
    return 'Cancel your $amount QTA withdrawal request?\nIt will be refunded to your balance right away.';
  }

  @override
  String get myWdNo => 'No';

  @override
  String get myWdCancelDo => 'Cancel request';

  @override
  String get myWdCancelled => 'Cancelled and refunded';

  @override
  String get myDateTimeFormat => 'MMM d, HH:mm';

  @override
  String get myWdTitle => 'Withdraw QTA';

  @override
  String get myWdAvailable => 'Available to withdraw';

  @override
  String get myWdRuleShort => 'From 5,000 QTA, in multiples of 5,000';

  @override
  String myWdPendingStatus(String amount, String status) {
    return 'Your $amount QTA withdrawal is $status';
  }

  @override
  String get myWdRequestBtn => 'Request withdrawal';

  @override
  String get myWdInsufficient => 'Not enough balance';

  @override
  String get myWdHistory => 'Request history';

  @override
  String get myWdHistoryEmpty => 'No withdrawal requests yet';

  @override
  String get myWdNotice =>
      'Withdrawals are only sent to the Quantarium wallet address you registered at sign-up. Our team processes them within 1–3 days. Requests can\'t be cancelled once processing starts.';

  @override
  String get myWdTxCopied => 'Transaction hash copied';

  @override
  String myWdReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get myWdAmountTitle => 'Enter amount';

  @override
  String myWdAmountRule(String min, String unit) {
    return 'From $min QTA, in multiples of $unit QTA';
  }

  @override
  String myWdMinBtn(String amount) {
    return 'Min $amount';
  }

  @override
  String myWdMaxBtn(String amount) {
    return 'Max $amount';
  }

  @override
  String get myWdToWallet => 'Receiving wallet';

  @override
  String myWdSubmitAmount(String amount) {
    return 'Request $amount QTA';
  }

  @override
  String get myLedgerTitle => 'QTA history';

  @override
  String get myLedgerWithdraw => 'Withdraw';

  @override
  String get myLedgerBalance => 'Current balance';

  @override
  String get myLedgerRecent => 'Recent activity';

  @override
  String get myLedgerEmpty =>
      'No history yet. Earn QTA by logging in daily and trading!';

  @override
  String get myRuleTitle => 'How to earn QTA';

  @override
  String get myRuleVerify =>
      '+1,000 QTA for completing wallet & phone verification (one time)';

  @override
  String myRuleListing(int rate) {
    return 'Mine 10% of the price in QTA when you list an item (1 QTA = ₱$rate) · Deducted if you delete it';
  }

  @override
  String get myRuleLogin =>
      '+10 QTA each time you log in · Up to 3 times a day';

  @override
  String get myRuleTrade =>
      '+10 QTA each for seller and buyer when a deal is completed';

  @override
  String get myRuleWithdraw =>
      'Withdraw to your wallet from 5,000 QTA, in multiples of 5,000';

  @override
  String get myMiningLoadFail =>
      'Couldn\'t load mining history. Pull down to try again';

  @override
  String get myMiningTitle => 'Mining history';

  @override
  String get myMiningTotalLabel => 'Total QTA mined';

  @override
  String myMiningTotalSub(String listing, String money) {
    return 'Listing mining $listing QTA · about $money';
  }

  @override
  String myMiningRule(int percent, int rate, String examplePrice,
      String exampleQta, String maxPerListing, String maxPerDay) {
    return '⛏️ List an item and mine $percent% of its price in QTA (1 QTA = ₱$rate)\n   e.g. $examplePrice item → +$exampleQta QTA\n• Up to $maxPerListing QTA per item · $maxPerDay QTA per day\n• Lower the price and the difference is deducted; delete the item and what you received is deducted\n• Sold items aren\'t deducted (unless you delete them)';
  }

  @override
  String get myMiningRecords => 'Mining records';

  @override
  String get myMiningEmpty =>
      'No mining records yet. List an item to start mining QTA!';

  @override
  String get myRefLoadFail => 'Couldn\'t load your invite history.';

  @override
  String get myRefNetworkError =>
      'Network error: please try again in a moment.';

  @override
  String get myRefTitle => 'Invite friends';

  @override
  String get myRefHeadline =>
      'Get +200 QTA when a friend\nenters your nickname at sign-up';

  @override
  String get myRefCopyNick => 'Copy nickname';

  @override
  String get myRefShareLink => 'Send an invite link';

  @override
  String myRefShareText(String nickname) {
    return 'Buy and sell anonymously on Eggplant! Enter \'$nickname\' as the referrer when you sign up.';
  }

  @override
  String get myRefLinkCopied => 'Invite link copied. Send it to your friend.';

  @override
  String get myRefNickCopied => 'Nickname copied';

  @override
  String get myRefOncePerPerson =>
      'Each friend counts only once, but there\'s no limit to how many friends you can invite.';

  @override
  String get myRefStatValid => 'Valid invites';

  @override
  String get myRefStatEarned => 'Total earned';

  @override
  String get myRefStatClawed => 'Taken back (left)';

  @override
  String get myRefRuleTitle => 'Invite bonus rules';

  @override
  String get myRefRuleBody =>
      '• +200 QTA per friend · No limit\n• Your friend enters your nickname in the last field at sign-up\n• If your friend deletes their account, that 200 QTA is taken back right away\n• You can\'t refer yourself';

  @override
  String get myRefListTitle => 'Friends you invited';

  @override
  String get myRefEmpty => 'You haven\'t invited anyone yet';

  @override
  String get myRefDeletedFriend => '(Deleted account)';

  @override
  String get myRefUnknown => '(Unknown)';

  @override
  String get myRefClawedBadge => '−200 QTA taken back';

  @override
  String get myReasonSignup => 'Sign-up bonus';

  @override
  String get myReasonVerifyBonus => 'Verification bonus';

  @override
  String get myReasonLoginDaily => 'Daily login bonus';

  @override
  String get myReasonTradeSeller => 'Sale completed reward';

  @override
  String get myReasonTradeBuyer => 'Purchase completed reward';

  @override
  String get myReasonWithdrawal => 'Withdrawal request';

  @override
  String get myReasonWithdrawalRefund => 'Withdrawal cancelled / refunded';

  @override
  String get myReasonListingReward => 'Listing mining';

  @override
  String get myReasonListingAdjust => 'Price drop deduction';

  @override
  String get myReasonListingClawback => 'Deleted listing deduction';

  @override
  String get myReasonMiningListing => '7-day listing mining';

  @override
  String get myReasonMiningBrowse => 'Browse mining';

  @override
  String get myWdStatusRequested => 'Pending';

  @override
  String get myWdStatusProcessing => 'Sending';

  @override
  String get myWdStatusCompleted => 'Completed';

  @override
  String get myWdStatusRejected => 'Rejected / Refunded';

  @override
  String get myQtaLoadFail => 'Couldn\'t load your QTA balance';

  @override
  String get myWdLoadFail => 'Couldn\'t load withdrawal history';

  @override
  String myWdErrMin(String min) {
    return 'You can request from $min QTA';
  }

  @override
  String myWdErrUnit(String unit) {
    return 'Requests must be in multiples of $unit QTA';
  }

  @override
  String get myWdErrBalance => 'Not enough QTA balance';

  @override
  String get myWdErrPending =>
      'You already have a request in progress. Please try again once it\'s processed.';

  @override
  String get myWdErrRequestFail => 'Withdrawal request failed';

  @override
  String get myWdUserCancelled => 'Cancelled by user';

  @override
  String get myWdErrCancelFail => 'Couldn\'t cancel';

  @override
  String get myVerifyLabelNone => 'Not verified';

  @override
  String get myVerifyLabelIdentity => 'Identity verified';

  @override
  String get myVerifyLabelBank => 'Withdrawal verified';

  @override
  String get myMenuLanguage => 'Language';

  @override
  String get myRuleVerifyRequired =>
      'Mined QTA is added right away · Completing deals and withdrawals need phone verification';

  @override
  String get myPrivacyNoCollect => 'We never collect';

  @override
  String get myPrivacyItemName => 'Email · Real name';

  @override
  String get myPrivacyItemNameSub => 'Just a nickname and password';

  @override
  String get myPrivacyItemGps => 'Exact location';

  @override
  String get myPrivacyItemGpsSub => 'Neighborhood-check GPS is discarded';

  @override
  String get myPrivacyItemChat => 'Chat messages';

  @override
  String get myPrivacyItemChatSub => 'Never stored on our servers';

  @override
  String get myPrivacyItemCall => 'Call content';

  @override
  String get myPrivacyItemCallSub => 'Device to device, not via our servers';

  @override
  String get myPrivacyPhoneTitle => 'Phone number';

  @override
  String get myPrivacyPhoneSub =>
      'Only for verification · encrypted · deleted when you leave';

  @override
  String get myPrivacyVolatileTitle => 'Chats are not kept';

  @override
  String get myPrivacyVolatileSub =>
      'Closing the app or switching devices clears them for good';

  @override
  String get productCategoryAll => 'All';

  @override
  String get productCategoryDigital => 'Electronics';

  @override
  String get productCategoryAppliance => 'Home Appliances';

  @override
  String get productCategoryFurniture => 'Furniture & Decor';

  @override
  String get productCategoryClothing => 'Clothing';

  @override
  String get productCategoryBeauty => 'Beauty';

  @override
  String get productCategoryBook => 'Books & Tickets';

  @override
  String get productCategorySports => 'Sports & Outdoors';

  @override
  String get productCategoryHobby => 'Hobbies & Games';

  @override
  String get productCategoryKids => 'Baby & Kids';

  @override
  String get productCategoryPet => 'Pet Supplies';

  @override
  String get productCategoryFood => 'Food';

  @override
  String get productCategoryEtc => 'Others';

  @override
  String get productAnonymousSeller => 'Anonymous Eggplant';

  @override
  String get productTimeJustNow => 'Just now';

  @override
  String productTimeMinutesAgo(int n) {
    return '${n}m ago';
  }

  @override
  String productTimeHoursAgo(int n) {
    return '${n}h ago';
  }

  @override
  String productTimeDaysAgo(int n) {
    return '${n}d ago';
  }

  @override
  String productTimeMonthsAgo(int n) {
    return '${n}mo ago';
  }

  @override
  String productTimeYearsAgo(int n) {
    return '${n}y ago';
  }

  @override
  String get productStatusSale => 'For sale';

  @override
  String get productStatusReserved => 'Reserved';

  @override
  String get productStatusSold => 'Sold';

  @override
  String get productReviewGood => 'Great';

  @override
  String get productReviewBad => 'Not great';

  @override
  String get productReviewSoso => 'Okay';

  @override
  String get productStatusSoldOut => 'Sold';

  @override
  String get productDetailLoadFailed => 'Couldn\'t load item details.';

  @override
  String get productDetailTimeout =>
      'The server is slow to respond. Please try again in a moment.';

  @override
  String get productQtaConfirmUnavailableTitle =>
      'Phone verification is coming soon';

  @override
  String get productQtaConfirmUnavailableBody =>
      'Deals can be completed after phone verification.\nWe will let you know as soon as phone verification opens.';

  @override
  String get productConfirmVerifyTitle =>
      'Phone verification needed before completing the deal';

  @override
  String get productConfirmVerifyBody =>
      'Every deal is completed only after phone verification (one account per person).\nThe QTA you have mined stays in your balance. Your chats and calls stay anonymous even after verifying.';

  @override
  String get productConfirmDialogTitle => 'Confirm this deal?';

  @override
  String productConfirmDialogBodyQta(String qta) {
    return 'Once confirmed, $qta will be paid to the seller.\nPlease confirm only after you\'ve received the item.';
  }

  @override
  String get productConfirmDialogBody =>
      'Please confirm only after you\'ve received the item.\nOnce confirmed, the deal is complete and you can leave a review.';

  @override
  String get productConfirmDeal => 'Confirm deal';

  @override
  String get productConfirmDone => 'Deal confirmed 🍆';

  @override
  String get productBuyerAssignedTitle => 'The seller marked you as the buyer';

  @override
  String productBuyerAssignedBodyQta(String qta) {
    return 'Once you confirm the deal, $qta will be paid.';
  }

  @override
  String get productBuyerAssignedBody =>
      'If you\'ve received the item, please confirm the deal.';

  @override
  String get productConfirmDealButton => 'Confirm deal';

  @override
  String get productSoldVerifyTitle =>
      'Phone verification needed before completing the deal';

  @override
  String get productSoldVerifyBody =>
      'You can mark a deal as Sold only after phone verification (one account per person).\nThe QTA you have mined stays in your balance. Your chats and calls stay anonymous even after verifying.';

  @override
  String get productStatusChangedSold =>
      'Marked as Sold. Payment and bonus will be released once the buyer confirms the deal';

  @override
  String productStatusChanged(String status) {
    return 'Status changed to $status';
  }

  @override
  String get productBuyer => 'Buyer';

  @override
  String productReviewQuestion(String nickname) {
    return 'How was your deal with $nickname?';
  }

  @override
  String get productReviewHint => 'Leave a review (optional)';

  @override
  String get productReviewThanks => 'Thanks for your review 🙏';

  @override
  String get productReviewSubmit => 'Submit review';

  @override
  String get productChatOpenFailed => 'Couldn\'t open the chat';

  @override
  String get productChatStartFailed =>
      'Couldn\'t start the chat. Please try again in a moment';

  @override
  String get productEscrowNavigating => 'Going to Safe Pay';

  @override
  String get productChangeToSale => 'Mark as For sale';

  @override
  String get productChangeToReserved => 'Mark as Reserved';

  @override
  String get productChangeToSold => 'Mark as Sold';

  @override
  String get productEdit => 'Edit';

  @override
  String get productDeleteTitle => 'Delete this item?';

  @override
  String get productDeleteBody =>
      '• The item and its photos/videos will be permanently deleted\n• Listing mining QTA earned from this item will be deducted\n• This can\'t be undone';

  @override
  String productDeletedWithClawback(int qta) {
    return 'Item deleted · Listing mining -$qta QTA';
  }

  @override
  String get productDeleted => 'Item deleted';

  @override
  String get productHide => 'Hide';

  @override
  String get productReport => 'Report';

  @override
  String get productReportReceived => 'Report received';

  @override
  String get productDetailTitle => 'Item details';

  @override
  String get productOwnerMenuTooltip => 'Change status / Delete';

  @override
  String get productMore => 'More';

  @override
  String get productDetailEmpty => 'No item details.';

  @override
  String get productNoTitle => 'Untitled';

  @override
  String get productNoSellerInfo => 'No seller info';

  @override
  String get productDescriptionTitle => 'Description';

  @override
  String get productNoDescription => 'No description';

  @override
  String get productManage => 'Manage';

  @override
  String get productChatButton => 'Chat';

  @override
  String productMannerTemp(String temp) {
    return 'Manner temperature $temp';
  }

  @override
  String get productPickBuyerTitle => 'Choose the buyer you dealt with';

  @override
  String get productPickBuyerHint =>
      'The deal is complete once the buyer taps \"Confirm deal\" in the app.';

  @override
  String get productPickBuyerSearchHint => 'Search buyer nickname';

  @override
  String get productPickBuyerChatPartners =>
      'People who chatted about this item';

  @override
  String get productPickBuyerNoResults => 'No results found';

  @override
  String get productPickBuyerEmpty => 'Search for the buyer\'s nickname';

  @override
  String get productVideoLoadFailed => 'Couldn\'t load the video';

  @override
  String productMaxImages(int max) {
    return 'You can add up to $max photos';
  }

  @override
  String get productAddPhoto => 'Add photo';

  @override
  String get productPhotoPickFailed =>
      'Couldn\'t get the photo. Please check permissions and try again';

  @override
  String get productAddVideo => 'Add video';

  @override
  String get productVideoPickFailed =>
      'Couldn\'t get the video. Please check permissions and try again';

  @override
  String get productVideoTooLarge => 'Videos must be 50MB or smaller';

  @override
  String get productYoutubeAddTitle => 'Add YouTube link';

  @override
  String get productYoutubeAddBody =>
      'Paste a YouTube video URL.\nE.g. https://youtu.be/xxxxxxxxxxx';

  @override
  String get productYoutubeInvalid => 'That YouTube link doesn\'t look right';

  @override
  String get productSetRegionFirst => 'Please set your neighborhood first';

  @override
  String get productUploadTimeout =>
      'Upload is taking too long. Try smaller photos/videos or switch to Wi-Fi.';

  @override
  String get productCreateUnexpectedError =>
      'Something went wrong while posting. Please try again in a moment';

  @override
  String productCreatedWithReward(int qta) {
    return 'Item posted 🍆  Listing mining +$qta QTA';
  }

  @override
  String get productCreated => 'Item posted 🍆';

  @override
  String get productCreateTitle => 'Sell an item';

  @override
  String get productDone => 'Done';

  @override
  String get productFieldTitle => 'Title';

  @override
  String get productFieldTitleHint => 'Enter the item name';

  @override
  String get productFieldTitleRequired => 'Please enter a title';

  @override
  String get productFieldCategory => 'Category';

  @override
  String get productFieldPrice => 'Price';

  @override
  String get productFieldPriceHintKrw => '0 (enter ₩0 to give it away free)';

  @override
  String get productFieldPriceHintJpy => '0 (enter ¥0 to give it away free)';

  @override
  String get productFieldPriceRequired => 'Please enter a price';

  @override
  String get productFieldQtaPrice => 'QTA payment (optional)';

  @override
  String get productFieldQtaPriceHint =>
      '0 = off / deducted when the buyer confirms the deal';

  @override
  String get productFieldQtaPriceHelper =>
      'E.g. 5,000 → when the buyer confirms the deal, 5,000 QTA is transferred from the buyer\'s balance';

  @override
  String get productFieldDescription => 'Description';

  @override
  String get productFieldDescriptionHint =>
      'Please check before posting:\n- Make sure it\'s not a prohibited item\n- Make sure the category is right\n\nDescribe the item\'s condition, how long it\'s been used, etc.';

  @override
  String get productFieldDescriptionMin =>
      'Please enter at least 10 characters';

  @override
  String get productProhibitedGuide => 'Prohibited items guide';

  @override
  String get productPhotos => 'Photos';

  @override
  String get productVideo => 'Video';

  @override
  String get productOptional => '(optional)';

  @override
  String get productRemove => 'Remove';

  @override
  String get productPickCamera => 'Take a photo';

  @override
  String get productPickGallery => 'Choose from gallery';

  @override
  String get productPickYoutube => 'Paste YouTube link';

  @override
  String get productCoverPhoto => 'Cover';

  @override
  String get productYoutubeVideo => 'YouTube video';

  @override
  String get productNotFound => 'Item not found';

  @override
  String get productNoChanges => 'Nothing was changed';

  @override
  String get productUpdated => 'Item updated ✨';

  @override
  String get productEditTitle => 'Edit item';

  @override
  String get productFieldTitleTooLong => 'Title is too long';

  @override
  String get productFieldRegion => 'Neighborhood';

  @override
  String get productSetRegion => 'Please set your neighborhood';

  @override
  String get productChange => 'Change';

  @override
  String get productFieldDescriptionEditHint =>
      'Describe the item\'s condition, how long it\'s been used, etc.';

  @override
  String get productUploadedVideoLocked =>
      'Uploaded videos can\'t be edited.\nTo change it, delete the item and post it again.';

  @override
  String get productYoutubeLinkOptional => 'YouTube link (optional)';

  @override
  String productEditingBanner(String title) {
    return 'Editing: $title';
  }

  @override
  String productWaitHoursMinutes(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String productWaitMinutes(int m) {
    return '${m}m';
  }

  @override
  String productBumpWait(String wait) {
    return 'You can bump again in $wait';
  }

  @override
  String get productBumped =>
      '🍆 Bumped! Your item is now at the top of the feed';

  @override
  String get productDeleteDialogTitle => 'Delete item';

  @override
  String productDeleteConfirmNamed(String title) {
    return 'Are you sure you want to delete $title?';
  }

  @override
  String get productStatusChangedGeneric => 'Status changed';

  @override
  String get productMySelling => 'My listings';

  @override
  String productMySellingCount(int count) {
    return 'My listings $count';
  }

  @override
  String get productNewPost => 'New post';

  @override
  String get productMySellingEmpty => 'You haven\'t listed anything yet';

  @override
  String get productMySellingEmptyHint =>
      'Tap \"New post\" at the bottom right to start selling';

  @override
  String get productMyMenuTooltip => 'Bump / Change status / Delete';

  @override
  String get productBump => 'Bump';

  @override
  String get productBumpWaiting => 'Bump (waiting)';

  @override
  String get productChangeStatus => 'Change status';

  @override
  String get productBanMedicine => 'Medicines & medical devices';

  @override
  String get productBanMedicineEx =>
      'Prescription drugs (antibiotics, Cytotec/misoprostol, ED pills), medicines not registered with FDA Philippines, slimming pills and injectables, contact lenses, hearing aids, syringes';

  @override
  String get productBanDrugs => 'Illegal drugs & psychotropics';

  @override
  String get productBanDrugsEx =>
      'Shabu (meth), marijuana/damo, kush, ecstasy, cocaine, party drugs, magic mushrooms, Nubain (RA 9165)';

  @override
  String get productBanAlcohol => 'Alcohol';

  @override
  String get productBanAlcoholEx =>
      'Beer, gin, rum, brandy, lambanog, whisky, wine (empty bottles and glasses are OK)';

  @override
  String get productBanTobacco => 'Tobacco & vapes';

  @override
  String get productBanTobaccoEx =>
      'Cigarettes (yosi), vapes and pods, e-juice, heated tobacco (IQOS), nicotine pouches (RA 11900)';

  @override
  String get productBanWeapons => 'Firearms, blades, explosives & weapons';

  @override
  String get productBanWeaponsEx =>
      'Guns (baril), paltik/sumpak, ammunition (bala), gun parts, airsoft guns and gel blasters (RA 10591), stun guns, pepper spray, balisong';

  @override
  String get productBanAdult => 'Adult products & obscene material';

  @override
  String get productBanAdultEx =>
      'Adult toys, porn and obscene material, worn underwear, paid dating/hookups';

  @override
  String get productBanAccounts => 'Accounts, personal data & identities';

  @override
  String get productBanAccountsEx =>
      'Registered SIM cards (RA 11934), PhilSys National ID, SSS/UMID, PhilHealth, driver\'s licenses, passports, GCash/Maya and bank accounts, game/social media accounts';

  @override
  String get productBanCashing => 'Cash-outs, loans & crypto';

  @override
  String get productBanCashingEx =>
      '5-6 and online lending (pautang), GCash/Maya cash-out services, gift card cash-outs, trading Bitcoin or other crypto';

  @override
  String get productBanAnimals => 'Pets & wildlife';

  @override
  String get productBanAnimalsEx =>
      'Selling or rehoming pets for a fee, protected wildlife (RA 9147) like tarsiers, pangolins, hornbills and sea turtles (pawikan) or their eggs and parts';

  @override
  String get productBanCounterfeit => 'Counterfeits';

  @override
  String get productBanCounterfeitEx =>
      'Fake/peke branded goods, \"Class A\", mirror-grade, premium or OEM copies (IP Code, RA 8293)';

  @override
  String get productBanStolen => 'Stolen, illegally modified & pirated goods';

  @override
  String get productBanStolenEx =>
      'Stolen items (nakaw), illegally modified items, pirated movies and games, cracked software';

  @override
  String get productBanBodily => 'Prescriptions & human-derived items';

  @override
  String get productBanBodilyEx =>
      'Prescriptions (reseta), organs (e.g. kidney), blood, eggs/sperm, breast milk';

  @override
  String get productBanMilitary => 'Military gear & police uniforms';

  @override
  String get productBanMilitaryEx =>
      'AFP/PNP uniforms, badges and insignia, bulletproof vests, handcuffs, night-vision goggles';

  @override
  String get productBanSpycam => 'Hidden cameras & bugging devices';

  @override
  String get productBanSpycamEx =>
      'Spy cameras, pinhole/disguised cameras, wiretaps (RA 9995, RA 4200)';

  @override
  String get productBanHacking => 'Hacking & illegal software';

  @override
  String get productBanHackingEx =>
      'Hacking tools and services, phishing kits, game hacks/cheats (e.g. ML), illegal macros';

  @override
  String get productBanScalping => 'Scalped tickets & proxy services';

  @override
  String get productBanScalpingEx =>
      'Marked-up concert ticket resale, ticketing proxies, proxy exam-taking';

  @override
  String get productBanWasteBags => 'Official garbage bags';

  @override
  String get productBanWasteBagsEx =>
      'Pay-as-you-throw garbage bags, bulky waste disposal stickers';

  @override
  String get productBanFireworks => 'Firecrackers & pyrotechnics';

  @override
  String get productBanFireworksEx =>
      'Paputok and fireworks, banned firecrackers (Piccolo, Super Lolo, Goodbye Philippines, Judas\' belt), kwitis, homemade explosives (RA 7183, EO 28)';

  @override
  String get productBanIntro =>
      'Items banned by law or that could put people at risk can\'t be sold on Eggplant. Posts containing the items below won\'t be published, and violating our policies may restrict your account.';

  @override
  String get productBanInfoTitle => 'Info you can\'t include in posts';

  @override
  String get productBanInfoBody =>
      '• Phone numbers, bank account numbers, emails\n• Viber, Messenger, WhatsApp or Telegram contacts and links (\"PM me on FB\")\n• Profanity, slurs and hate speech\n\nPlease keep deal conversations in Eggplant chat. Moving to outside messengers or paying upfront carries a high risk of scams.';

  @override
  String get productPolicyRejectedTitle => 'This post can\'t be published';

  @override
  String get productViewProhibited => 'View prohibited items';

  @override
  String get productHiddenTimeout =>
      'The server is slow to respond. Please try again in a moment 🕐';

  @override
  String get productHiddenLoadFailed => 'Couldn\'t load hidden posts';

  @override
  String productUnhidden(String title) {
    return '\"$title\" is visible again';
  }

  @override
  String get productUnhideFailed => 'Couldn\'t unhide';

  @override
  String get productHiddenTitle => 'Hidden posts';

  @override
  String get productUnhide => 'Unhide';

  @override
  String get productHiddenEmpty => 'No hidden posts';

  @override
  String get productHiddenEmptyHint =>
      'You can hide posts from the ⋯ menu at the top right of a post';

  @override
  String get productKeywordDeleteTitle => 'Delete keyword';

  @override
  String productKeywordDeleteBody(String keyword) {
    return 'Turn off alerts for \"$keyword\"?';
  }

  @override
  String get productKeywordAlertsTitle => 'Keyword alerts';

  @override
  String productKeywordAlertsIntro(int max) {
    return 'Add keywords you\'re interested in and we\'ll notify you when new items are posted in your neighborhood. (Up to $max)';
  }

  @override
  String get productKeywordFull => 'All keyword slots are full';

  @override
  String get productKeywordHint => 'E.g. Nintendo, bike, camping';

  @override
  String get productKeywordAdd => 'Add';

  @override
  String get productKeywordEmpty => 'No keywords yet';

  @override
  String get productKeywordEmptyHint =>
      'Add a keyword you\'re interested in above';

  @override
  String get productKeywordTooShort => 'Keywords must be at least 2 characters';

  @override
  String get productKeywordTooLong => 'Keywords must be 30 characters or less';

  @override
  String productKeywordMax(int max) {
    return 'You can add up to $max keywords';
  }

  @override
  String get productKeywordAddFailed =>
      'Couldn\'t set up the alert. Please try again in a moment';

  @override
  String get productLoadFailed => 'Couldn\'t load items';

  @override
  String get productCreateFailed => 'Posting failed';

  @override
  String get productCreateFailedRetry =>
      'Posting failed. Please try again in a moment';

  @override
  String get productLikesLoadFailed => 'Couldn\'t load your liked items';

  @override
  String get productNothingToUpdate => 'Nothing to update';

  @override
  String get productUpdateFailed => 'Update failed';

  @override
  String get productBumpFailed => 'Bump failed';

  @override
  String get productChangeFailed => 'Change failed';

  @override
  String get productDeleteFailed => 'Delete failed';

  @override
  String get productConfirmFailed => 'Couldn\'t confirm the deal';

  @override
  String get productReviewFailed => 'Couldn\'t submit review';

  @override
  String get productNetworkSlow =>
      'Slow response. Please check your connection and try again';

  @override
  String get productNetworkUnreachable =>
      'Can\'t connect to the server. Please check your connection';

  @override
  String get productBlockFailed => 'Block failed';

  @override
  String get productUnblockFailed => 'Unblock failed';

  @override
  String get productReportFailed => 'Couldn\'t submit report';

  @override
  String get productFieldPriceHintPhp => '0 (enter ₱0 to give it away free)';

  @override
  String get productShare => 'Share';

  @override
  String get productLinkCopied => 'Item link copied';

  @override
  String productSellerOthers(String name) {
    return 'More from $name';
  }

  @override
  String get productSimilar => 'You might also like';

  @override
  String get productSeeAll => 'See all';

  @override
  String get productMeetPlaceTitle => 'Preferred meeting place';

  @override
  String get productFieldMeetPlace => 'Meeting place (optional)';

  @override
  String get productFieldMeetPlaceHint => 'e.g. SM Megamall main entrance';

  @override
  String get productDraftTitle => 'You have an unfinished post';

  @override
  String get productDraftBody => 'Do you want to continue where you left off?';

  @override
  String get productDraftDiscard => 'Start over';

  @override
  String get productDraftResume => 'Continue';

  @override
  String get regionPrefectureSearchHint =>
      'Search province or city (e.g. Makati)';

  @override
  String regionCitySearchHint(String prefecture) {
    return 'Search cities/municipalities in $prefecture';
  }

  @override
  String regionCityCount(int count) {
    return '$count cities/municipalities';
  }

  @override
  String get regionChangePrefecture => 'Change province';

  @override
  String get regionNoResults => 'No matching areas';

  @override
  String regionAdded(String region, int count, int max) {
    return 'Added $region ($count/$max)';
  }

  @override
  String regionRemoved(String region, int count, int max) {
    return 'Removed $region ($count/$max)';
  }

  @override
  String regionMultiHint(int max) {
    return 'Pick up to $max areas, then tap Confirm below. Tap again to remove.';
  }

  @override
  String get regionKeepOne => 'You need at least one neighborhood';

  @override
  String regionConfirm(int count, int max) {
    return 'Confirm ($count/$max)';
  }

  @override
  String reviewQuestion(String nickname) {
    return 'How was your deal with $nickname?';
  }

  @override
  String get reviewQuestionSub =>
      'Reviews affect each other\'s Manner temperature';

  @override
  String get reviewRatingBad => 'Not great';

  @override
  String get reviewRatingGood => 'Good';

  @override
  String get reviewRatingBest => 'Awesome';

  @override
  String get reviewRatingSoso => 'Okay';

  @override
  String get reviewTagsTitleGood => 'What did you like?';

  @override
  String get reviewTagsTitleBad => 'What went wrong?';

  @override
  String get reviewTagsSub => 'Select all that apply';

  @override
  String get reviewBadPrivateNotice =>
      '\"Not great\" ratings and the items you pick won\'t be shown on their profile. They only affect their Manner temperature.';

  @override
  String get reviewCommentTitle => 'Leave a kind review';

  @override
  String get reviewCommentTitleBad => 'Tell us what was disappointing';

  @override
  String reviewCommentOptional(String nickname) {
    return 'Optional. Your review will be shown on $nickname\'s profile.';
  }

  @override
  String get reviewCommentOptionalBad =>
      'Optional. This won\'t be made public.';

  @override
  String reviewCommentHint(String nickname) {
    return 'Say thanks to $nickname';
  }

  @override
  String get reviewCommentHintBad => 'What was disappointing?';

  @override
  String get reviewNext => 'Next';

  @override
  String get reviewBack => 'Back';

  @override
  String get reviewSubmit => 'Send review';

  @override
  String get reviewSent => 'Review sent';

  @override
  String get reviewSendButton => 'Leave a review';

  @override
  String get reviewViewMine => 'View my review';

  @override
  String reviewSentTo(String nickname) {
    return 'Your review for $nickname';
  }

  @override
  String get reviewPromptBody =>
      'Your review affects each other\'s Manner temperature';

  @override
  String get reviewPromptDone => 'Review sent. Thanks for a great deal!';

  @override
  String get reviewRoleBuyer => 'Buyer';

  @override
  String get reviewRoleSeller => 'Seller';

  @override
  String get reviewPraiseTitle => 'Manner compliments received';

  @override
  String get reviewPraiseMore => 'See more';

  @override
  String get reviewPraiseLess => 'Show less';

  @override
  String get reviewNoPraise => 'No manner compliments yet';

  @override
  String get reviewReceivedTitle => 'Reviews received';

  @override
  String get reviewNoComments => 'No reviews yet';

  @override
  String get reviewPurchasesTitle => 'Purchases';

  @override
  String get reviewPurchasesEmpty => 'No purchases yet';

  @override
  String get reviewPurchasesLoadFailed => 'Couldn\'t load your purchases';

  @override
  String get reviewCounterpartFallback => 'Trade partner';

  @override
  String get reviewTagKind => 'Kind and polite';

  @override
  String get reviewTagPunctual => 'On time';

  @override
  String get reviewTagFastReply => 'Replies quickly';

  @override
  String get reviewTagAsDescribed => 'Item was as described';

  @override
  String get reviewTagDetailedDesc => 'Detailed item description';

  @override
  String get reviewTagGoodPrice => 'Good items at fair prices';

  @override
  String get reviewTagFreeShare => 'Gave it away for free';

  @override
  String get reviewTagPaidOnTime => 'Paid and picked up on time';

  @override
  String get reviewTagNoHaggle => 'Didn\'t haggle unreasonably';

  @override
  String get reviewTagLate => 'Wasn\'t on time';

  @override
  String get reviewTagSlowReply => 'Slow to reply';

  @override
  String get reviewTagRude => 'Unfriendly';

  @override
  String get reviewTagNotAsDescribed => 'Item wasn\'t as described';

  @override
  String get reviewTagPriceChange => 'Changed the price suddenly';

  @override
  String get reviewTagNoShow => 'Didn\'t show up at the meetup';

  @override
  String get reviewTagHaggle => 'Haggled unreasonably';
}
