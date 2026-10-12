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
]
add = ''.join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in s)
s = s.replace('<application', add + '    <application', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Delivery محل"', s, count=1)
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
    t = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', t)
    t = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23', t)
    open(g, 'w', encoding='utf-8').write(t)
    print('patched', g)

# the default widget test refers to a counter app that does not exist here
if os.path.isdir('test'):
    shutil.rmtree('test')
print(open(man, encoding='utf-8').read())
