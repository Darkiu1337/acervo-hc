import 'package:flutter/cupertino.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

enum LoginType { web, cookie }

enum CookieVerificationType { normal, webview, skip }

class LoginPageState {
  LoginType loginType = LoginType.web;
  CookieVerificationType cookieVerificationType = CookieVerificationType.normal;

  FocusNode ipbPassHashFocusNode = FocusNode();
  FocusNode igneousFocusNode = FocusNode();

  String? ipbMemberId;
  String? ipbPassHash;
  String? igneous;

  LoadingState loginState = LoadingState.idle;
  LoadingState cookieLoginLoadingState = LoadingState.idle;
}
