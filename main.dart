import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const ink = Color(0xFF14272E);
const paper = Color(0xFFF3F6F4);
const lineC = Color(0xFFD5DFDC);
const accent = Color(0xFF2A5D9F);
const muted = Color(0xFF5D7078);

class Level {
  final int max;
  final String name;
  final Color color;
  final String advice;
  const Level(this.max, this.name, this.color, this.advice);
}

const aqLevels = [
  Level(50, 'Good', Color(0xFF2E7D4F), 'The air is clean. A good time for outdoor activity.'),
  Level(100, 'Moderate', Color(0xFF9A7B00), 'Acceptable for most people. Sensitive people may want to limit long time outdoors.'),
  Level(150, 'Unhealthy for sensitive groups', Color(0xFFC26A00), 'People with asthma, older adults and children should spend less time outside.'),
  Level(200, 'Unhealthy', Color(0xFFB3261E), 'Everyone should reduce strenuous outdoor activity.'),
  Level(300, 'Very unhealthy', Color(0xFF7B2A8F), 'Avoid outdoor activity as much as possible.'),
  Level(9999, 'Hazardous', Color(0xFF5A1A1A), 'Stay indoors and keep windows closed.'),
];
Level aqOf(num v) => aqLevels.firstWhere((x) => v <= x.max);
String uvName(num v) => v <= 2 ? 'Low' : v <= 5 ? 'Moderate' : v <= 7 ? 'High' : v <= 10 ? 'Very high' : 'Extreme';
Color uvColor(num v) => v < 3 ? const Color(0xFF2E7D4F) : v < 6 ? const Color(0xFF9A7B00) : v < 8 ? const Color(0xFFC26A00) : const Color(0xFFB3261E);
String dateStr(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Place {
  final double lat, lon;
  final String name;
  Place(this.lat, this.lon, this.name);
  Map toJson() => {'lat': lat, 'lon': lon, 'name': name};
  factory Place.fromJson(Map j) => Place((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble(), j['name']);
}

class LogEntry {
  final int id, mins;
  final String date, place, act, prod, note;
  final int aqi;
  final double uv;
  LogEntry(this.id, this.date, this.place, this.aqi, this.uv, this.mins, this.act, this.prod, this.note);
  Map toJson() => {'id': id, 'date': date, 'place': place, 'aqi': aqi, 'uv': uv, 'mins': mins, 'act': act, 'prod': prod, 'note': note};
  factory LogEntry.fromJson(Map j) => LogEntry(j['id'], j['date'], j['place'], j['aqi'], (j['uv'] as num).toDouble(), j['mins'], j['act'], j['prod'] ?? '', j['note'] ?? '');
}

void main() => runApp(const PerelunoApp());

class PerelunoApp extends StatelessWidget {
  const PerelunoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pereluno',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: paper,
          colorScheme: ColorScheme.fromSeed(seedColor: accent),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: lineC)),
          ),
        ),
        home: const Root(),
      );
}

Widget card(Widget child) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: lineC), borderRadius: BorderRadius.circular(14)),
      child: child,
    );
Widget h2(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)));
Widget mutedText(String t) => Text(t, style: const TextStyle(color: muted, fontSize: 14));
Widget errText(String t) => t.isEmpty ? const SizedBox() : Padding(padding: const EdgeInsets.only(top: 6), child: Text(t, style: const TextStyle(color: Color(0xFFB3261E), fontSize: 14)));

// ---------- Root: decides between login and app ----------
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  String? user;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      final s = sp.getString('pl_session');
      final users = jsonDecode(sp.getString('pl_users') ?? '{}') as Map;
      setState(() {
        user = (s != null && users.containsKey(s)) ? s : null;
        ready = true;
      });
    });
  }

  Future<void> setSession(String? n) async {
    final sp = await SharedPreferences.getInstance();
    if (n == null) {
      await sp.remove('pl_session');
    } else {
      await sp.setString('pl_session', n);
    }
    setState(() => user = n);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return user == null ? AuthPage(onDone: setSession) : Home(key: ValueKey(user), user: user!, onLogout: () => setSession(null));
  }
}

// ---------- Auth ----------
class AuthPage extends StatefulWidget {
  final Future<void> Function(String) onDone;
  const AuthPage({super.key, required this.onDone});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final nm = TextEditingController(), pin = TextEditingController();
  String err = '';

  Future<void> go(bool reg) async {
    final n = nm.text.trim(), p = pin.text;
    if (n.isEmpty || !RegExp(r'^\d{4,}$').hasMatch(p)) {
      setState(() => err = 'Enter a name and a PIN of at least 4 digits.');
      return;
    }
    final sp = await SharedPreferences.getInstance();
    final users = Map<String, dynamic>.from(jsonDecode(sp.getString('pl_users') ?? '{}'));
    if (reg) {
      if (users.containsKey(n)) {
        setState(() => err = 'That name is taken. Choose another or log in.');
        return;
      }
      users[n] = p;
      await sp.setString('pl_users', jsonEncode(users));
    } else if (users[n] != p) {
      setState(() => err = 'Incorrect name or PIN.');
      return;
    }
    await widget.onDone(n);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(14), children: [
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Pereluno', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: ink))),
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Track your environment and health', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              mutedText('Air quality and UV index where you are, plus a daily log of your exposure.'),
              const SizedBox(height: 12),
              TextField(controller: nm, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN (at least 4 digits)')),
              errText(err),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: FilledButton(onPressed: () => go(false), child: const Text('Log in'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => go(true), child: const Text('Create account'))),
              ]),
            ])),
            mutedText('Your account and data are stored on this device only in this version. Secure online login comes in the next stage.'),
          ]),
        ),
      );
}

// ---------- Home ----------
class Home extends StatefulWidget {
  final String user;
  final VoidCallback onLogout;
  const Home({super.key, required this.user, required this.onLogout});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  Place? place;
  List<LogEntry> logs = [];
  Map? cur;
  String airStatus = 'Waiting for location', locErr = '', saved = '';
  final city = TextEditingController(), mins = TextEditingController(text: '30'), prod = TextEditingController(), note = TextEditingController();
  String act = 'Walking';
  static const acts = ['Walking', 'Running', 'Sports', 'Outdoor work', 'Driving', 'Sitting outside', 'Indoors only'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('pl_data_${widget.user}');
    if (raw != null) {
      final j = jsonDecode(raw) as Map;
      setState(() {
        place = j['place'] == null ? null : Place.fromJson(j['place']);
        logs = (j['logs'] as List).map((e) => LogEntry.fromJson(e)).toList();
      });
    }
    if (place != null) loadAir();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('pl_data_${widget.user}', jsonEncode({'place': place?.toJson(), 'logs': logs.map((e) => e.toJson()).toList()}));
  }

  Future<bool> ipLocate() async {
    try {
      final r = await http.get(Uri.parse('https://get.geojs.io/v1/ip/geo.json'));
      final j = jsonDecode(r.body) as Map;
      if (j['latitude'] == null) return false;
      final name = [j['city'], j['country']].where((e) => e != null && e != '').join(', ');
      setState(() {
        place = Place(double.parse('${j['latitude']}'), double.parse('${j['longitude']}'), '$name (approximate)');
        locErr = 'Exact GPS is unavailable, so an approximate location from your network was used. Type your city for better accuracy.';
      });
      await _save();
      loadAir();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> useGPS() async {
    setState(() => locErr = '');
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw 'denied';
      final p = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 12));
      setState(() => place = Place(p.latitude, p.longitude, 'My current location'));
      await _save();
      loadAir();
    } catch (_) {
      if (!await ipLocate()) setState(() => locErr = 'Could not get your location. Type your city and press Search.');
    }
  }

  Future<void> findCity() async {
    final q = city.text.trim();
    if (q.isEmpty) return;
    setState(() => locErr = '');
    try {
      final r = await http.get(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'count': '1', 'language': 'en', 'name': q}));
      final j = jsonDecode(r.body) as Map;
      final res = j['results'] as List?;
      if (res == null || res.isEmpty) {
        setState(() => locErr = 'City not found. Try a different spelling.');
        return;
      }
      final c = res[0] as Map;
      final name = [c['name'], c['admin1'], c['country']].where((e) => e != null).join(', ');
      setState(() => place = Place((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble(), name));
      await _save();
      loadAir();
    } catch (e) {
      setState(() => locErr = 'Network request failed: $e');
    }
  }

  Future<void> loadAir() async {
    if (place == null) return;
    setState(() => airStatus = 'Loading...');
    try {
      final r = await http.get(Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
        'latitude': '${place!.lat}',
        'longitude': '${place!.lon}',
        'current': 'us_aqi,pm2_5,pm10,uv_index',
        'timezone': 'auto',
      }));
      final j = jsonDecode(r.body) as Map;
      setState(() => cur = j['current'] as Map);
    } catch (_) {
      setState(() {
        cur = null;
        airStatus = 'Could not load data. Check your internet, then choose your location again.';
      });
    }
  }

  Future<void> addLog() async {
    if (cur == null) {
      setState(() => saved = 'Choose your location first so the air quality is saved with your log.');
      return;
    }
    logs.add(LogEntry(DateTime.now().millisecondsSinceEpoch, dateStr(DateTime.now()), place!.name, (cur!['us_aqi'] as num).round(),
        double.parse((cur!['uv_index'] as num).toStringAsFixed(1)), int.tryParse(mins.text) ?? 0, act, prod.text.trim(), note.text.trim()));
    await _save();
    prod.clear();
    note.clear();
    setState(() => saved = 'Saved to your history.');
  }

  Future<void> delLog(int id) async {
    setState(() => logs.removeWhere((l) => l.id == id));
    await _save();
  }

  // ----- Today -----
  Widget todayTab() {
    final c = cur;
    final lvl = c == null ? null : aqOf((c['us_aqi'] as num).round());
    return ListView(padding: const EdgeInsets.all(14), children: [
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        h2('Location'),
        mutedText(place?.name ?? 'No location selected yet'),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: useGPS, child: const Text('Use my current location'))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: city, decoration: const InputDecoration(hintText: 'Or type your city'))),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: findCity, child: const Text('Search')),
        ]),
        errText(locErr),
      ])),
      AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: lvl?.color ?? const Color(0xFF6B7A80), borderRadius: BorderRadius.circular(18)),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lvl == null ? airStatus : 'Air quality: ${lvl.name}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            Text(c == null ? '--' : '${(c['us_aqi'] as num).round()}', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w700, height: 1.1)),
            Text(lvl?.advice ?? 'Choose your location to see the air quality right now.'),
            const SizedBox(height: 14),
            Row(children: [
              _stat('PM2.5', c == null ? '--' : '${(c['pm2_5'] as num).round()}', ''),
              _stat('PM10', c == null ? '--' : '${(c['pm10'] as num).round()}', ''),
              _stat('UV index', c == null ? '--' : (c['uv_index'] as num).toStringAsFixed(1), c == null ? '' : uvName(c['uv_index'])),
            ]),
          ]),
        ),
      ),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        h2("Log today's exposure"),
        TextField(controller: mins, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Time outdoors (minutes)')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: act,
          decoration: const InputDecoration(labelText: 'Activity'),
          items: acts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
          onChanged: (v) => setState(() => act = v ?? act),
        ),
        const SizedBox(height: 10),
        TextField(controller: prod, decoration: const InputDecoration(labelText: 'Products used (optional)', hintText: 'e.g. sunscreen, perfume, cleaner')),
        const SizedBox(height: 10),
        TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: addLog, child: const Text("Save today's log"))),
        if (saved.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: mutedText(saved)),
      ])),
    ]);
  }

  Widget _stat(String label, String value, String sub) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );

  // ----- History -----
  Widget histTab() {
    final L = logs.reversed.toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      card(L.isEmpty
          ? mutedText('No entries yet. Save your first log from the Today tab.')
          : Column(children: [
              for (final l in L)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: lineC))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${l.date}  ·  ${l.place}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('Air: ${l.aqi} (${aqOf(l.aqi).name}) · UV: ${l.uv} (${uvName(l.uv)})'),
                    Text('${l.act} for ${l.mins} min'),
                    if (l.prod.isNotEmpty) Text('Products: ${l.prod}'),
                    if (l.note.isNotEmpty) mutedText(l.note),
                    TextButton(onPressed: () => delLog(l.id), child: const Text('Delete')),
                  ]),
                ),
            ])),
    ]);
  }

  // ----- Reports -----
  Widget bars(List<double?> vals, List<String> labels, Color Function(double) colorFn, double maxV) => SizedBox(
        height: 160,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < vals.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (vals[i] != null) ...[
                  Text('${(vals[i]! * 10).round() / 10}', style: const TextStyle(fontSize: 10, color: muted)),
                  Container(
                    height: math.max(3, vals[i]! / maxV * 100),
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: colorFn(vals[i]!), borderRadius: BorderRadius.circular(4)),
                  ),
                ],
                Text(labels[i].substring(5), style: const TextStyle(fontSize: 10, color: muted)),
              ]),
            ),
        ]),
      );

  Widget repTab() {
    final days = [for (var i = 6; i >= 0; i--) dateStr(DateTime.now().subtract(Duration(days: i)))];
    List<double?> avg(num Function(LogEntry) f) => days.map<double?>((d) {
          final x = logs.where((l) => l.date == d).toList();
          return x.isEmpty ? null : x.map(f).reduce((a, b) => a + b) / x.length;
        }).toList();
    final A = avg((l) => l.aqi), U = avg((l) => l.uv);
    double mx(List<double?> v, double m) => v.whereType<double>().fold(m, math.max);
    final w = logs.where((l) => days.contains(l.date)).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [h2('Average air quality (last 7 days)'), bars(A, days, (v) => aqOf(v).color, mx(A, 100))])),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [h2('Average UV index (last 7 days)'), bars(U, days, uvColor, mx(U, 8))])),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        h2('Summary'),
        if (w.isEmpty)
          mutedText('No entries in the last 7 days.')
        else ...[
          Text('Entries: ${w.length}'),
          Text('Total time outdoors: ${w.fold<int>(0, (a, l) => a + l.mins)} min'),
          Text('Highest air quality index: ${w.map((l) => l.aqi).reduce(math.max)}'),
          Text('Highest UV index: ${w.map((l) => l.uv).reduce(math.max)}'),
          Text('Entries with unhealthy air (above 100): ${w.where((l) => l.aqi > 100).length}'),
        ],
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: paper,
          title: const Text('Pereluno', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
          actions: [
            Center(child: mutedText(widget.user)),
            TextButton(onPressed: widget.onLogout, child: const Text('Log out')),
          ],
        ),
        body: SafeArea(child: [todayTab, histTab, repTab][tab]()),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
          ],
        ),
      );
}
