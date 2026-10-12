# App Functions (not built yet)

Spoken answers for Gemini and other assistants through `androidx.appfunctions`.
The code is written but not part of the build, because `androidx.appfunctions`
1.0.0-alpha09 and -alpha10 declare `minCompileSdk=37` and
`minAndroidGradlePluginVersion=9.1.0` (their AAR metadata). This project is on
AGP 8.13, compileSdk 36 (installed platforms: 36, 36.1), and Flutter 3.41 knows
AGP up to 9.0 only.

To enable it, after moving to AGP 9.1 / Gradle 9 / compileSdk 37:

1. settings.gradle.kts: `id("com.google.devtools.ksp") version "2.2.20-2.0.4" apply false`
   (match the Kotlin version).
2. app/build.gradle.kts: apply `com.google.devtools.ksp`; add
   `implementation("androidx.appfunctions:appfunctions:1.0.0-alpha10")`,
   `ksp("androidx.appfunctions:appfunctions-compiler:1.0.0-alpha10")` and
   `ksp { arg("appfunctions:aggregateAppFunctions", "true") }`.
3. Move `AmudAppFunctions.kt` to `app/src/main/kotlin/page/amud/appfunctions/`,
   `app_metadata.xml` to `res/xml/`, `res/values*/appfunctions.xml` to `res/`.
4. Put `manifest-snippet.xml` inside `<application>` of the main manifest.
5. Test: `adb shell cmd app_function list-app-functions` on Android 16+.

The functions read the widget timeline the Dart side already publishes
(`HomeWidgetPreferences` / `amudTimeline`, which now includes `sunriseTime` and
`sunsetTime`), so they work with the app closed.
