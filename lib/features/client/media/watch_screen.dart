import 'package:flutter/material.dart';

import '../client_runtime.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.runtime});

  final ClientRuntime runtime;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.runtime.startWatching();
  }

  @override
  void dispose() {
    widget.runtime.stopWatching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (_tab) {
      0 => _DarkShell(child: _watch(context)),
      1 => _LightShell(child: _history()),
      _ => _LightShell(child: _settings()),
    };
    return Scaffold(
      body: child,
      bottomNavigationBar: _PinnedNav(
        dark: _tab == 0,
        child: _Nav(tab: _tab, onTap: (i) => setState(() => _tab = i)),
      ),
    );
  }

  Widget _watch(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 104),
        children: [
          const _Top(dark: true),
          const SizedBox(height: 34),
          const Text('Canlı izleme', style: _darkTitle),
          const SizedBox(height: 8),
          const Text('Bebek odası yayını bağlı. Son olaylar altta görünür.',
              style: _darkSubtitle),
          const SizedBox(height: 18),
          const _LightPill('Bağlı'),
          const SizedBox(height: 22),
          const _VideoPanel(),
          const SizedBox(height: 22),
          const _Event(
              label: 'Son uyarı',
              value: 'Ağlama algılandı · 09:38',
              color: _pink),
          const SizedBox(height: 16),
          const _Event(
              label: 'Hareket', value: 'Sakin · skor %08', color: _mint),
          const SizedBox(height: 16),
          const _Event(
              label: 'Bildirim', value: 'Yerel bildirim açık', color: _amber),
          const SizedBox(height: 30),
          const Text(
            'Hızlı işlemler',
            style: TextStyle(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          _ActionGroup(
            actions: [
              _ActionSpec('Yeniden bağlan', _mint, _navy, () {}),
              _ActionSpec('Adresi değiştir', _pink, Colors.white,
                  () => Navigator.pop(context)),
              _ActionSpec(
                  'Geçmişi aç', _amber, _navy, () => setState(() => _tab = 1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _history() {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 104),
        children: [
          const _Top(),
          const SizedBox(height: 34),
          const Text('Uyarı geçmişi', style: _title),
          const SizedBox(height: 8),
          const Text(
              'Ağlama, hareket ve sistem olaylarını zaman çizgisi olarak takip et.',
              style: _subtitle),
          const SizedBox(height: 30),
          const SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Filter('Tümü', true),
                SizedBox(width: 10),
                _Filter('Ses', false),
                SizedBox(width: 10),
                _Filter('Hareket', false),
                SizedBox(width: 10),
                _Filter('Sistem', false),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _Timeline('09:38', 'Ağlama algılandı',
              'Ses seviyesi ortamdan 18 dB yüksek. Cooldown başladı.', _pink),
          const SizedBox(height: 16),
          const _Timeline('09:31', 'Client bağlandı',
              'Ebeveyn cihazı 192.168.1.42 adresinden bağlandı.', _mint),
          const SizedBox(height: 16),
          const _Timeline('09:12', 'Hareket algılandı',
              'Hareket skoru 2.1 sn boyunca eşik üzerinde kaldı.', _amber),
          const SizedBox(height: 16),
          const _Timeline('08:58', 'Telegram gönderildi',
              'Bot API üzerinden uyarı mesajı gönderildi.', Color(0xFF9BBCFF)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDecoration(dark: true),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Günlük özeti',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                Text(
                  'Bugün 2 ses, 1 hareket, 2 sistem olayı var.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 17, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settings() {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 104),
        children: [
          const _Top(),
          const SizedBox(height: 34),
          const Text('Ayarlar', style: _title),
          const SizedBox(height: 8),
          const Text(
              'Gürültü, hareket, bildirim ve entegrasyonları sade kontrollerle yönet.',
              style: _subtitle),
          const SizedBox(height: 30),
          const _SliderCard('Bildirim cooldown',
              'Tekrarlayan uyarıları sınırlar.', '60 sn', _pink, .68),
          const SizedBox(height: 18),
          const _SliderCard('Ağlama eşiği',
              'Ortam sesine göre algılama hassasiyeti.', '%65', _mint, .65),
          const SizedBox(height: 18),
          const _SliderCard('Hareket eşiği',
              'Kamera görüntüsündeki değişim hassasiyeti.', '%22', _amber, .22),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDecoration(dark: true),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Entegrasyonlar',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 20),
                _SwitchLine('Telegram Bot', 'Kurulu değil', false),
                _SwitchLine('Cihaz uyumasın', 'Server modunda açık', true),
                _SwitchLine('Dil', 'Türkçe / English', true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPanel extends StatelessWidget {
  const _VideoPanel();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
        alignment: Alignment.bottomCenter,
        child: const Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 8,
          children: [
            _VideoMetric('Ses: Açık'),
            _VideoMetric('Gecikme: 0.4 sn'),
            _VideoMetric('WS: Aktif'),
          ],
        ),
      ),
    );
  }
}

class _VideoMetric extends StatelessWidget {
  const _VideoMetric(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(color: Colors.white, fontSize: 16));
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard(
      this.title, this.description, this.value, this.color, this.progress);

  final String title;
  final String description;
  final String value;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      color: _navy, fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 22, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          Text(description,
              style: const TextStyle(color: _slate, fontSize: 17)),
          const SizedBox(height: 22),
          LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: color,
              backgroundColor: const Color(0xFFECEFF4)),
        ],
      ),
    );
  }
}

class _SwitchLine extends StatelessWidget {
  const _SwitchLine(this.title, this.description, this.on);

  final String title;
  final String description;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900)),
                Text(description,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 16)),
              ],
            ),
          ),
          Switch(value: on, onChanged: null, activeThumbColor: _mint),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.time, this.title, this.text, this.color);

  final String time;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(time,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _navy,
                        fontSize: 21,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(text,
                    style: const TextStyle(
                        color: _slate, fontSize: 17, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Event extends StatelessWidget {
  const _Event({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          CircleAvatar(radius: 26, backgroundColor: color),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: _slate, fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _navy, fontSize: 21, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.actions});

  final List<_ActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              for (final action in actions) ...[
                _Action(action),
                if (action != actions.last) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final action in actions) ...[
              Expanded(child: _Action(action)),
              if (action != actions.last) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _ActionSpec {
  const _ActionSpec(
      this.text, this.backgroundColor, this.foregroundColor, this.onTap);

  final String text;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;
}

class _Action extends StatelessWidget {
  const _Action(this.spec);

  final _ActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: FilledButton(
        onPressed: spec.onTap,
        style: FilledButton.styleFrom(
          backgroundColor: spec.backgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        child: Text(
          spec.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: spec.foregroundColor,
              fontWeight: FontWeight.w900,
              fontSize: 18),
        ),
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter(this.text, this.active);

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: ShapeDecoration(
          color: active ? _navy : Colors.white, shape: const StadiumBorder()),
      child: Text(
        text,
        style: TextStyle(
            color: active ? Colors.white : _slate,
            fontSize: 17,
            fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({required this.tab, required this.onTap});

  final int tab;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.all(7),
      decoration:
          const ShapeDecoration(color: Colors.white, shape: StadiumBorder()),
      child: Row(
        children: [
          for (final entry in ['İzle', 'Geçmiş', 'Ayarlar'].asMap().entries)
            Expanded(
              child: InkWell(
                onTap: () => onTap(entry.key),
                borderRadius: BorderRadius.circular(32),
                child: Container(
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: tab == entry.key
                        ? const Color(0xFFFFDCE6)
                        : Colors.transparent,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tab == entry.key ? _navy : _slate,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PinnedNav extends StatelessWidget {
  const _PinnedNav({required this.child, required this.dark});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? _navy : const Color(0xFFF9F7FC),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22111827),
            blurRadius: 22,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: child,
        ),
      ),
    );
  }
}

class _LightPill extends StatelessWidget {
  const _LightPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration:
            const ShapeDecoration(color: Colors.white, shape: StadiumBorder()),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _navy, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _Top extends StatelessWidget {
  const _Top({this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : _navy;
    return Row(
      children: [
        Text('09:41',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w900, fontSize: 18)),
        const Spacer(),
        Icon(Icons.signal_cellular_alt_rounded, color: color),
        const SizedBox(width: 12),
        Icon(Icons.battery_5_bar_rounded, color: color),
      ],
    );
  }
}

class _DarkShell extends StatelessWidget {
  const _DarkShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.7, -.85),
          radius: .9,
          colors: [Color(0xFF24465A), _navy, Color(0xFF07111F)],
        ),
      ),
      child: child,
    );
  }
}

class _LightShell extends StatelessWidget {
  const _LightShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.55, -.75),
          radius: .85,
          colors: [_mintSoft, Color(0xFFFDF7F4), Color(0xFFF9F7FC)],
        ),
      ),
      child: child,
    );
  }
}

BoxDecoration _cardDecoration({bool dark = false}) {
  return BoxDecoration(
    color: dark ? _navy : Colors.white,
    borderRadius: BorderRadius.circular(28),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: const [
      BoxShadow(
          color: Color(0x24111827), blurRadius: 22, offset: Offset(0, 12)),
    ],
  );
}

const _navy = Color(0xFF101B31);
const _slate = Color(0xFF6E7686);
const _pink = Color(0xFFFF708B);
const _mint = Color(0xFF87D8CC);
const _mintSoft = Color(0xFFD9F7F1);
const _amber = Color(0xFFFFD37B);

const _title = TextStyle(
    color: _navy, fontSize: 38, height: 1.05, fontWeight: FontWeight.w900);
const _subtitle = TextStyle(color: _slate, fontSize: 19, height: 1.2);
const _darkTitle = TextStyle(
    color: Colors.white,
    fontSize: 38,
    height: 1.05,
    fontWeight: FontWeight.w900);
const _darkSubtitle =
    TextStyle(color: Colors.white70, fontSize: 19, height: 1.2);
