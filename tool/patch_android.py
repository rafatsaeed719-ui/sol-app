"""يظبط ملفات أندرويد اللي بيولدها flutter create: الاسم، الصلاحيات، minSdk."""
import pathlib, re

app = pathlib.Path('android/app')
manifest = app / 'src/main/AndroidManifest.xml'
m = manifest.read_text()
m = re.sub(r'android:label="[^"]*"', 'android:label="SOL"', m)
perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
]
add = ''.join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m)
m = re.sub(r'(<manifest[^>]*>\n)', r'\1' + add, m, count=1)
manifest.write_text(m)

for name in ['build.gradle.kts', 'build.gradle']:
    g = app / name
    if not g.exists():
        continue
    s = g.read_text()
    s = re.sub(r'minSdk(Version)?\s*(=\s*)?flutter\.minSdkVersion', 'minSdk = 23', s)
    s = re.sub(r'ndkVersion\s*(=\s*)?flutter\.ndkVersion', 'ndkVersion = "27.0.12077973"', s)
    g.write_text(s)
    print('patched', g)

# مكتبات Firebase الجديدة محتاجة Kotlin 2
for name in ['settings.gradle.kts', 'settings.gradle']:
    st = pathlib.Path('android') / name
    if not st.exists():
        continue
    s = st.read_text()
    s = re.sub(r'(org\.jetbrains\.kotlin\.android"\)?\s*version\s*)"[^"]+"', r'\1"2.1.0"', s)
    st.write_text(s)
    print('patched', st)
    print(s)

print(manifest.read_text()[:600])
