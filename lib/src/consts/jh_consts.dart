class JHConsts {
  /// Serviço de sincronização do projeto original: o identificador não muda no rebranding.
  static const String serverAddress = 'https://jhentai.top';

  static const String APP_ID_HEADER = "X-App-Id";
  static const String TIMESTAMP_HEADER = "X-Timestamp";
  static const String NONCE_HEADER = "X-Nonce";
  static const String SIGNATURE_HEADER = "X-Signature";

  /// Namespace usado pelo servidor de sync; manter para não perder as configurações já sincronizadas.
  static const String APP_ID = "jhentai";
}
