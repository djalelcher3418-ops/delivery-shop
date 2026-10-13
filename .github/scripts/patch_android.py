"""Adds what the Delivery shop app needs to the Android project made by `flutter create`."""
import os, re, shutil

man = 'android/app/src/main/AndroidManifest.xml'
s = open(man, encoding='utf-8').read()
perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    # يبقي تتبع الموقع واستقبال الطلبات شغالاً والشاشة مطفأة
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.WAKE_LOCK',
    'android.permission.VIBRATE',
    # الطلب الجديد يضيء الشاشة ويظهر فوق القفل مثل المكالمة
    'android.permission.USE_FULL_SCREEN_INTENT',
]
add = ''.join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in s)
s = s.replace('<application', add + '    <application', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Delivery محل"', s, count=1)
if 'android:showWhenLocked' not in s:
    s = s.replace('android:name=".MainActivity"',
                  'android:name=".MainActivity"\n            android:showWhenLocked="true"\n            android:turnScreenOn="true"', 1)
tel = '<intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>'
if '<queries>' in s:
    s = s.replace('<queries>', '<queries>\n        ' + tel, 1)
else:
    s = s.replace('</manifest>', '    <queries>' + tel + '</queries>\n</manifest>', 1)
open(man, 'w', encoding='utf-8').write(s)

for g in ['android/app/build.gradle.kts', 'android/app/build.gradle']:
    if not os.path.exists(g):
        continue
    t = open(g, encoding='utf-8').read()
    # flutter_local_notifications يتطلب أندرويد 7.0 (API 24) على الأقل
    t = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', t)
    t = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24', t)
    # desugaring مطلوب لمكتبة الإشعارات
    kts = g.endswith('.kts')
    if 'oreLibraryDesugaringEnabled' not in t:
        flag = 'isCoreLibraryDesugaringEnabled = true' if kts else 'coreLibraryDesugaringEnabled true'
        t, n = re.subn(r'compileOptions\s*\{', 'compileOptions {\n        ' + flag, t, count=1)
        assert n == 1, 'compileOptions not found in ' + g
    if 'desugar_jdk_libs' not in t:
        dep = ('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if kts
               else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'")
        t += '\ndependencies {\n    ' + dep + '\n}\n'
    open(g, 'w', encoding='utf-8').write(t)
    print('patched', g)

    print(t)

# ---- توقيع ثابت: يقرأ android/key.properties (يكتبه البناء على GitHub) ويوقّع النسخة به ----
g = 'android/app/build.gradle.kts'
t = open(g, encoding='utf-8').read()
if 'keyProps' not in t:
    t = 'import java.util.Properties\n\n' + t
    t = t.replace('\nandroid {', '''
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {''', 1)
    t, n = re.subn(r'\n([ \t]*)buildTypes\s*\{', r'''
\1signingConfigs {
\1    create("release") {
\1        if (!keyProps.isEmpty()) {
\1            storeFile = file(keyProps.getProperty("storeFile"))
\1            storePassword = keyProps.getProperty("storePassword")
\1            keyAlias = keyProps.getProperty("keyAlias")
\1            keyPassword = keyProps.getProperty("keyPassword")
\1        }
\1    }
\1}

\1buildTypes {''', t, count=1)
    assert n == 1, 'buildTypes not found'
    t, n = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                   'signingConfig = signingConfigs.getByName(if (keyProps.isEmpty()) "debug" else "release")', t, count=1)
    assert n == 1, 'debug signingConfig not found'
    open(g, 'w', encoding='utf-8').write(t)
    print(t)

# the default widget test refers to a counter app that does not exist here
if os.path.isdir('test'):
    shutil.rmtree('test')
print(open(man, encoding='utf-8').read())
