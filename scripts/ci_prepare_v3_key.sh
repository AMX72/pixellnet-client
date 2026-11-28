#!/usr/bin/env bash
# T-027 / А2.5 — готовит хранилище ключа подписи v3 на раннере CI и проверяет его ДО долгой сборки (30-45 мин).
#
# Вход (окружение; значения секретов в журнал не попадают, пароли в аргументы команд не передаются):
#   V3_B64             ANDROID_V3_KEYSTORE_BASE64 — PKCS12, base64 одной строкой
#   V3_ALIAS           ANDROID_V3_KEY_ALIAS
#   V3_STORE_PASSWORD  ANDROID_V3_STORE_PASSWORD
#   V3_KEY_PASSWORD    ANDROID_V3_KEY_PASSWORD
#   EXPECT_SHA256      ожидаемый отпечаток сертификата (из android/pixellnet-identities.properties, app.cert.sha256)
#   OUT_DIR            куда положить хранилище (RUNNER_TEMP)
#   SKIP_JAVA_CHECK=1  только для локального прогона без JDK
# Выход: строка store_file=<путь> в $GITHUB_OUTPUT (если задан); код 1 и ::error:: при любой проблеме.
#
# Что проверяет: все 4 секрета заданы (у форков и PR их нет); файл читается как PKCS12; отпечаток сертификата = ожидаемому;
# Java/keytool читает хранилище (хранилище создано OpenSSL 3: PBES2/AES-256 — если JDK не прочтёт, пересохраняем в старый
# формат через openssl, сам ключ не меняется); пароль ключа подходит (ключ расшифровывается).
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }

missing=()
[ -n "${V3_B64:-}" ] || missing+=(ANDROID_V3_KEYSTORE_BASE64)
[ -n "${V3_ALIAS:-}" ] || missing+=(ANDROID_V3_KEY_ALIAS)
[ -n "${V3_STORE_PASSWORD:-}" ] || missing+=(ANDROID_V3_STORE_PASSWORD)
[ -n "${V3_KEY_PASSWORD:-}" ] || missing+=(ANDROID_V3_KEY_PASSWORD)
if [ "${#missing[@]}" -gt 0 ]; then
  fail "Нет секретов GitHub: ${missing[*]}. Новое приложение (com.pxllnet.app) подписывается только ключом v3 из секретов; у форков и запусков без доступа к секретам собрать его нельзя (и чем попало мы его не подписываем)."
fi
EXPECT="${EXPECT_SHA256:?EXPECT_SHA256 не задан}"
OUT_DIR="${OUT_DIR:-${RUNNER_TEMP:-/tmp}}"
KEYTOOL="${KEYTOOL:-keytool}"
KS="$OUT_DIR/pixellnet-v3.p12"
umask 077
printf '%s' "$V3_B64" | tr -d '[:space:]' | base64 --decode > "$KS" || fail "ANDROID_V3_KEYSTORE_BASE64 не декодируется как base64"
[ -s "$KS" ] || fail "ANDROID_V3_KEYSTORE_BASE64 пуст после декодирования"
# PKCS12 = DER SEQUENCE (0x30 ...)
[ "$(head -c1 "$KS" | od -An -tx1 | tr -d ' \n')" = "30" ] || fail "Файл ключа v3 не похож на PKCS12 (первый байт не 0x30)"
echo "хранилище v3: $(wc -c < "$KS") байт"

normalize() { tr -d ':[:space:]' | tr 'A-F' 'a-f'; }

fingerprint() { # <файл>
  openssl pkcs12 -in "$1" -nokeys -passin env:V3_STORE_PASSWORD 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//'
}

got=$(fingerprint "$KS" || true)
[ -n "$got" ] || fail "openssl не прочёл хранилище v3: неверный ANDROID_V3_STORE_PASSWORD или повреждённый файл"
if [ "$(printf '%s' "$got" | normalize)" != "$(printf '%s' "$EXPECT" | normalize)" ]; then
  fail "Отпечаток сертификата в секрете ANDROID_V3_KEYSTORE_BASE64 ($got) не равен ожидаемому ($EXPECT). Это не тот ключ."
fi
echo "отпечаток SHA-256 сертификата v3 совпал: $got"

if [ "${SKIP_JAVA_CHECK:-}" != "1" ]; then
  java_list() { "$KEYTOOL" -list -v -keystore "$1" -storetype PKCS12 -storepass:env V3_STORE_PASSWORD -alias "$V3_ALIAS" 2>&1; }
  if ! out=$(java_list "$KS"); then
    echo "::warning::JDK не прочёл хранилище как есть (${out##*$'\n'}). Пересохраняю в совместимый PKCS12 через openssl (ключ тот же)."
    KS2="$OUT_DIR/pixellnet-v3-compat.p12"
    # ключ и сертификат через конвейер, на диск в открытом виде не попадают
    openssl pkcs12 -in "$KS" -nodes -passin env:V3_STORE_PASSWORD 2>/dev/null \
      | openssl pkcs12 -export -name "$V3_ALIAS" -passout env:V3_STORE_PASSWORD \
          -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 -out "$KS2" \
      || fail "не удалось пересохранить хранилище v3 в совместимый формат"
    rm -f "$KS"
    KS="$KS2"
    out=$(java_list "$KS") || fail "JDK (keytool) не читает хранилище v3 даже после пересохранения: ${out##*$'\n'}"
    got2=$(fingerprint "$KS" || true)
    [ "$(printf '%s' "$got2" | normalize)" = "$(printf '%s' "$EXPECT" | normalize)" ] || fail "после пересохранения отпечаток изменился ($got2)"
  fi
  echo "keytool читает хранилище; алиас найден:"
  printf '%s\n' "$out" | grep -E '^(Alias name|Creation date|Entry type|Owner|Valid from|\s*SHA256:)' | sed 's/^/  /' || true
  # Пароль ключа: расшифровываем ключ во временное хранилище (оно сразу удаляется).
  CHECK="$OUT_DIR/pixellnet-v3-keycheck.p12"
  rm -f "$CHECK"
  if ! imp=$("$KEYTOOL" -importkeystore -noprompt \
        -srckeystore "$KS" -srcstoretype PKCS12 -srcstorepass:env V3_STORE_PASSWORD \
        -srcalias "$V3_ALIAS" -srckeypass:env V3_KEY_PASSWORD \
        -destkeystore "$CHECK" -deststoretype PKCS12 -deststorepass:env V3_STORE_PASSWORD 2>&1); then
    rm -f "$CHECK"
    fail "ключ v3 не расшифровывается: неверный ANDROID_V3_KEY_PASSWORD или алиас (${imp##*$'\n'})"
  fi
  rm -f "$CHECK"
  echo "пароль ключа подошёл"
fi

chmod 600 "$KS"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "store_file=$KS" >> "$GITHUB_OUTPUT"
fi
echo "ключ v3 готов: $KS (удаляется в конце задания)"
