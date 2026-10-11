"""يظبط ملفات الويب اللي بيولدها flutter create: الاسم، الأيقونة، الألوان."""
import json, pathlib, shutil
from PIL import Image

web = pathlib.Path('web')
idx = web / 'index.html'
s = idx.read_text()
s = s.replace('<title>store</title>', '<title>SOL Perfume</title>')
s = s.replace('content="A new Flutter project."', 'content="SOL Perfume - اطلب بضاعتك بسهولة"')
s = s.replace('<html>', '<html lang="ar" dir="rtl">')
s = s.replace('content="store"', 'content="SOL"')
if 'theme-color' not in s:
    s = s.replace('<head>', '<head>\n  <meta name="theme-color" content="#0A0A0A">', 1)
idx.write_text(s)

m = json.loads((web / 'manifest.json').read_text())
m.update({'name': 'SOL Perfume', 'short_name': 'SOL', 'background_color': '#0A0A0A',
          'theme_color': '#0A0A0A', 'description': 'SOL Perfume'})
(web / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2))

src = Image.open('assets/icon.png').convert('RGB')
for name, size in [('Icon-192.png', 192), ('Icon-512.png', 512),
                   ('Icon-maskable-192.png', 192), ('Icon-maskable-512.png', 512)]:
    src.resize((size, size)).save(web / 'icons' / name)
src.resize((32, 32)).save(web / 'favicon.png')
print('web patched')
