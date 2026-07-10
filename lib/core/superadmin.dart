/// v0.0.37: Superadmin (admin flavor) flag.
///
/// В обычной сборке всегда false.
/// В admin-сборке: `flutter build apk --dart-define=SUPERADMIN=true`
/// или через product flavor `admin` в android/app/build.gradle
/// (там добавить: buildConfigField "boolean", "SUPERADMIN", "true"
///  и передавать через flutter.dart-defines).
///
/// Примечание для agent-hiddify-android: добавь в build.gradle:
///   productFlavors {
///     prod   { applicationIdSuffix "" }
///     admin  { applicationIdSuffix ".admin"
///               buildConfigField "boolean","SUPERADMIN","true" }
///   }
/// И в MainActivity.kt передавай через dart-defines при flutter build.
const bool kSuperAdminBuild = bool.fromEnvironment('SUPERADMIN', defaultValue: false);
