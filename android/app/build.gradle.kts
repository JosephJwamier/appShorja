import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// مفتاح توقيع الإصدار. القيم تُقرأ من android/key.properties (خارج git —
// انظر key.properties.example) أو، في CI، من متغيّرات البيئة بالأسماء نفسها.
// إن غاب الملف والمتغيّرات معًا فلا يُعرَّف signingConfigs.release أصلًا،
// فيفشل بناء الإصدار برسالة واضحة بدل أن يُوقَّع بمفتاح debug بصمت —
// حزمة كهذه يرفضها Google Play، والأسوأ أنها لا يمكن تحديثها لاحقًا.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        FileInputStream(file).use { load(it) }
    }
}
fun signingValue(name: String): String? =
    keystoreProperties.getProperty(name) ?: System.getenv(name)
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { signingValue(it) != null }

android {
    namespace = "com.balla.balla"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // مطابق لمُعرّف حزمة iOS (com.balla.balla). الاسم السابق
        // com.example.marketplace_app كان الاسم الافتراضي الذي يولّده Flutter،
        // ومتجر Google Play يرفض أي حزمة تبدأ بـ com.example.
        applicationId = "com.balla.balla"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(signingValue("storeFile")!!)
                storePassword = signingValue("storePassword")
                keyAlias = signingValue("keyAlias")
                keyPassword = signingValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // بلا مفتاح إصدار يبقى signingConfig فارغًا (حزمة غير موقّعة)
            // ولا يُستبدل بمفتاح debug أبدًا. الفشل الصريح يحدث في فحص
            // طور التنفيذ أسفل الملف، لا هنا: كتلة release تُقيَّم في طور
            // الضبط مع كل أمر Gradle، فرمي استثناء هنا كان يكسر
            // assembleDebug أيضًا.
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// يفشل فقط عندما يطلب البناء فعلًا مهمة إصدار (assemble/bundle/package
// Release)، فتبقى نسخة debug و`flutter run` تعملان بلا مفتاح.
gradle.taskGraph.whenReady {
    if (hasReleaseSigning) return@whenReady
    val releaseTask = allTasks.firstOrNull { task ->
        task.project == project && Regex("^(assemble|bundle|package).*Release$").matches(task.name)
    }
    if (releaseTask != null) {
        throw GradleException(
            "Release signing is not configured (task '${releaseTask.name}'): create " +
            "android/key.properties (see android/key.properties.example) or set " +
            "storeFile/storePassword/keyAlias/keyPassword in the environment. " +
            "Debug builds are unaffected."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
