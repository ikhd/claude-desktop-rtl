<div align="center">

# Claude Desktop RTL

**دعم العربية والكتابة من اليمين لليسار (RTL) في تطبيق Claude للكمبيوتر — ويندوز و ماك.**

**Proper right-to-left (Arabic) support for the Claude Desktop app — Windows & macOS.**

`بنقرة واحدة` · `نفس التطبيق ونفس الدخول` · `يتحدّث تلقائياً بعد التحديثات` · `ويندوز + ماك`

</div>

---

<div dir="rtl">

## العربية

### وش يسوي
تطبيق Claude ما يعرض العربية من اليمين لليسار. **Claude Desktop RTL** يحقن طبقة صغيرة في التطبيق تخلّي **كل فقرة تختار اتجاهها بنفسها** — العربي يمين، والإنجليزي والكود يسار — حتى لو كانوا مختلطين في نفس الرسالة، ويواكب الردود وهي تُكتب.

ويعدّل **تطبيق Claude الموجود عندك مباشرة**: نفس الأيقونة، نفس تسجيل الدخول، نفس المحادثات، وClaude Code / Cowork يظلّون شغّالين. ومهمة بالخلفية **تعيد تطبيق التعديل تلقائياً** بعد تحديثات Claude.

### المميزات
- 🎯 **نص مختلط صحيح** — يعتمد خوارزمية المتصفح "أول حرف قوي" (`dir="auto"`)، فالفقرة الإنجليزية اللي فيها كلمة عربية وحدة ما تنقلب غلط.
- 🧩 **نفس التطبيق** — ما فيه نسخة ثانية؛ دخولك ومحادثاتك ما تُمَس.
- ⌨️ **تبديل فوري** — `Ctrl+Alt+R` يشغّل/يطفّي RTL (ويُحفظ).
- 🔁 **يصمد مع التحديثات** — يعيد تطبيق نفسه تلقائياً بعد كل تحديث.
- 💻 **ويندوز + ماك** — محرّك واحد مشترك، ومثبّت أصلي لكل نظام.
- 🧱 الأكواد والجداول تبقى LTR، وطباعة عربية أوضح.
- ↩️ **قابل للتراجع** — نسخة احتياطية كاملة + إلغاء بأمر واحد.

### المتطلبات
- **Node.js** — تستخدمه أدوات التعديل. (ويندوز يثبّته تلقائياً عبر `winget` لو ناقص.)
- **ماك فقط:** `python3` + Xcode Command Line Tools.

### التثبيت
**ويندوز** — دبل-كليك على **`Claude-RTL.bat`** ووافق على طلب الأدمن (UAC). افتح Claude عادي بعدها.

**ماك**
```bash
bash install-mac.sh
```
> أول تشغيل على ماك قد يطلب السماح لطرفيّتك من **System Settings → Privacy & Security → App Management** (مرة وحدة، بدون باسوورد).

### الاستخدام
- التبديل داخل Claude: **`Ctrl+Alt+R`**.
- من الـ Console: `__claudeRTL.toggle()`.

### إلغاء التثبيت
- **ويندوز:** `powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Uninstall`
- **ماك:** `bash install-mac.sh --uninstall`

### كيف يعمل
- **`rtl-engine.js`** — الطبقة المحقونة في الواجهة. تضع `dir="auto"` على الكتل النصية وصندوق الكتابة عبر `MutationObserver` مُهَدّأ، تعزل الأكواد/الجداول LTR، وتحقن أنماطاً متوافقة مع CSP. مكتوبة بـ ASCII بالكامل (ما يقدر أي مثبّت يفسدها).
- **ويندوز (`install-windows.ps1`)** — يحقن المحرّك في `app.asar`، يعيد تغليفه، يحدّث هاش السلامة داخل `Claude.exe`، يعيد توقيعه، ويحدّث الشهادة المدمجة اللي تتحقق منها الخدمة المرافقة (عشان Claude Code يظل شغّال). نسخة احتياطية + تراجع تلقائي، ومهمة مجدوّلة تعيد التطبيق بعد التحديثات.
- **ماك (`install-mac.sh`)** — يحقن ويعيد التغليف، **يعيد حساب هاش رأس الـ asar ويحدّث `ElectronAsarIntegrity` في `Info.plist`** (تبقى السلامة مفعّلة)، يكتب الملفات داخل التطبيق عبر Finder (بدون sudo)، ويعيد التوقيع ad-hoc، وLaunchAgent يعيد التطبيق بعد التحديثات.

### تنبيه
هذا تعديل مجتمعي على العميل وقد يخالف شروط خدمة Anthropic — استخدمه لتحسين إمكانية الوصول وعلى مسؤوليتك. على ويندوز يضيف شهادة موقّعة ذاتياً لمخزن الجذر ويعيد توقيع ملفّين، فقد ينبّه مكافح الفيروسات. الحل الأمثل أن تدعم Anthropic الـ RTL أصلياً — يستاهل ترفع لهم طلب.

</div>

---

## English

### What it does
Claude Desktop doesn't render Arabic right-to-left. **Claude Desktop RTL** injects a tiny layer into the app so every block resolves **its own** direction — Arabic goes RTL, English and code stay LTR — even when they're mixed in the same message, and it keeps up while answers stream in.

It patches **your existing Claude app in place**: same icon, same login, same chats, and Claude Code / Cowork keep working. A background task **re-applies the patch automatically** after Claude updates.

### Features
- 🎯 **Correct mixed text** — uses the browser's native *first-strong* algorithm (`dir="auto"`), so an English paragraph with one Arabic word isn't wrongly flipped.
- 🧩 **Same app** — no second copy; your login and chats are untouched.
- ⌨️ **Instant toggle** — `Ctrl+Alt+R` turns RTL on/off (remembered).
- 🔁 **Survives updates** — auto re-applies itself after each Claude update.
- 💻 **Windows + macOS** — one shared engine, native installer per OS.
- 🧱 Code blocks, tables and math stay LTR; cleaner Arabic typography.
- ↩️ **Reversible** — full backup + one-command uninstall.

### Requirements
- **Node.js** — used by the patch tooling. (Windows auto-installs it via `winget` if missing.)
- **macOS only:** `python3` + Xcode Command Line Tools (`xcode-select --install`).

### Install
**Windows** — double-click **`Claude-RTL.bat`** and approve the admin prompt (UAC). Open Claude normally afterwards.

**macOS**
```bash
bash install-mac.sh
```
> First run on macOS may ask to allow your terminal under **System Settings → Privacy & Security → App Management** (one-time, no password).

### Usage
- Toggle RTL inside Claude: **`Ctrl+Alt+R`**.
- From the DevTools console: `__claudeRTL.toggle()`.

### Uninstall
- **Windows:** `powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Uninstall`
- **macOS:** `bash install-mac.sh --uninstall`

### How it works
- **`rtl-engine.js`** — the injected renderer layer. It stamps `dir="auto"` on text blocks and the composer through a throttled `MutationObserver`, isolates code/tables as LTR, and injects CSP-safe styles. ASCII-only by design (no byte can be corrupted by an installer).
- **Windows (`install-windows.ps1`)** — injects the engine into `app.asar`, repacks it, updates the integrity hash inside `Claude.exe`, re-signs it, and updates the embedded certificate the companion service checks (so Claude Code keeps working). Backup + automatic rollback. A logon Scheduled Task re-applies the patch after updates.
- **macOS (`install-mac.sh`)** — injects + repacks, **recomputes the asar header SHA-256 and updates `ElectronAsarIntegrity` in `Info.plist`** (integrity stays ON), writes the patched files back through Finder (no `sudo`), and ad-hoc re-signs. A `LaunchAgent` re-applies after updates.

### Notes & safety
This is a community client modification and may conflict with Anthropic's Terms of Service — use it for accessibility, at your own discretion. On Windows it adds a self-signed certificate to the trusted root and re-signs two binaries, so antivirus may warn. The ideal long-term fix is native RTL support in Claude — please request it from Anthropic too.

---

<div align="center">

صُنع بعناية لمستخدمي العربية · Made with care for Arabic users

**MIT License**

</div>
