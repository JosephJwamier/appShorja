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

    // إضافات Agora الاختيارية: الحزمة تشحن كل ملحقات SDK حتى ما لا يستدعيه
    // التطبيق أبدًا. شاشتا البث (live_broadcast_screen/live_viewer_screen)
    // تستعملان سبع دوال فقط — initialize / enableVideo / startPreview /
    // joinChannel / registerEventHandler / leaveChannel / release — بلا خلفية
    // افتراضية، ولا تجميل صوت، ولا كتم ضوضاء بالذكاء الاصطناعي، ولا مشاركة
    // شاشة. استبعادها يوفّر ~43 ميغابايت لكل معمارية.
    //
    // القائمة مُعدَّدة صراحةً لا بنمط عام مثل *_extension.so: بعض ما ينتهي
    // بهذه اللاحقة أساسي — libagora_video_encoder_extension.so هو مُرمِّز
    // الفيديو نفسه، وحذفه يوقف البث كليًا.
    //
    // تبقى في الحزمة عمدًا: libagora_ffmpeg.so و libagora-soundtouch.so و
    // libagora-fdkaac.so (~7 ميغابايت). وثائق Agora تسمح بحذفها عند عدم
    // استعمال مشغّل الوسائط، وهو ما ينطبق علينا، لكن أثرها لا يظهر إلا في
    // بثّ حقيقي — تُحذف بعد اختبار على جهاز، لا قبله.
    packaging {
        jniLibs {
            val unusedAgoraExtensions = listOf(
                "agora_clear_vision",              // تحسين الصورة/الإضاءة المنخفضة
                "agora_lip_sync",                  // مزامنة الشفاه للأفاتار
                "agora_spatial_audio",             // الصوت المكاني
                "agora_ai_noise_suppression",      // كتم الضوضاء بالذكاء الاصطناعي
                "agora_ai_noise_suppression_ll",
                "agora_ai_echo_cancellation",      // إلغاء الصدى بالذكاء الاصطناعي
                "agora_ai_echo_cancellation_ll",   // (الأساسي منهما داخل النواة)
                "agora_segmentation",              // الخلفية الافتراضية
                "agora_face_capture",              // تتبّع الوجه للأفاتار
                "agora_face_detection",
                "agora_audio_beauty",              // تجميل الصوت
                "agora_content_inspect",           // فحص المحتوى السحابي
                "agora_video_av1_encoder",         // ترميز AV1 (الافتراضي H.264)
                "agora_video_quality_analyzer",
                "agora_screen_capture",            // مشاركة الشاشة
            )
            excludes += unusedAgoraExtensions.map { "**/lib${it}_extension.so" }
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
