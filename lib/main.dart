import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    final tzName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (_) {
    // Falls back to UTC if the device timezone can't be read.
  }
  await _initNotifications();
  runApp(const JarvisApp());
}

Future<void> _initNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notifications.initialize(initSettings);
  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------
const cyan = Color(0xFF3FD8FF);
const cyanSoft = Color(0xFF8FE9FF);
const bg0 = Color(0xFF020509);
const panelBg = Color(0xFF0A1622);
const green = Color(0xFF4EE08A);
const amber = Color(0xFFFFCF6B);
const red = Color(0xFFFF5C5C);

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'J.A.R.V.I.S',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg0,
        fontFamily: 'monospace',
        colorScheme: const ColorScheme.dark(primary: cyan, secondary: cyanSoft),
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Home Screen
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _listening = false;
  bool _speechAvailable = false;
  String _statusLine = 'Tap the mic and speak, or type a command below.';

  final List<_ChatMsg> _chat = [
    _ChatMsg(false, 'At your service. Try a command below or tap the mic.'),
  ];
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  // weather
  String _wTemp = '--°';
  String _wDesc = 'Loading…';
  String _wLoc = '—';
  String _wFeels = '--', _wHum = '--', _wWind = '--';
  final TextEditingController _cityCtrl = TextEditingController();

  // notes / reminders
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _reminders = [];

  // settings
  String? _geminiKey;
  List<dynamic> _voices = [];
  String? _selectedVoiceName;
  String _recogLocale = 'en-IN';
  final TextEditingController _geminiCtrl = TextEditingController();
  final TextEditingController _alarmCtrl = TextEditingController(); // HH:MM

  Timer? _clockTimer;
  String _clock = '--:--:--';
  String _dateLabel = '—';

  static const Map<String, String> apps = {
    'youtube': 'https://youtube.com',
    'spotify': 'https://open.spotify.com',
    'whatsapp': 'https://web.whatsapp.com',
    'instagram': 'https://instagram.com',
    'telegram': 'https://web.telegram.org',
    'facebook': 'https://facebook.com',
    'twitter': 'https://twitter.com',
    'gmail': 'https://mail.google.com',
    'maps': 'https://maps.google.com',
    'netflix': 'https://netflix.com',
    'github': 'https://github.com',
    'reddit': 'https://reddit.com',
  };

  static const systemPrompt =
      "You are JARVIS, a helpful voice assistant. Answer the user's question "
      "directly in 1-4 short sentences of plain text. No markdown.";

  @override
  void initState() {
    super.initState();
    _tickClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());
    _initSpeech();
    _initTts();
    _loadPrefs();
    _loadWeatherByLocation();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _chatCtrl.dispose();
    _cityCtrl.dispose();
    _geminiCtrl.dispose();
    _alarmCtrl.dispose();
    super.dispose();
  }

  void _tickClock() {
    final now = DateTime.now();
    setState(() {
      _clock =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      _dateLabel = '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}';
    });
  }

  String _weekday(int d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];
  String _month(int m) => [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
        'Nov', 'Dec'
      ][m - 1];

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          setState(() => _listening = false);
        }
      },
      onError: (e) => setState(() => _listening = false),
    );
    setState(() {});
  }

  Future<void> _initTts() async {
    await _tts.setPitch(0.82); // deeper, JARVIS-like tone
    await _tts.setSpeechRate(0.5);
    try {
      final voices = await _tts.getVoices;
      _voices = voices is List ? voices : [];
      final prefs = await SharedPreferences.getInstance();
      _selectedVoiceName = prefs.getString('jarvis_voice_name');
      _selectedVoiceName ??= _pickDefaultMaleVoice();
      await _applySelectedVoice();
    } catch (_) {}
    setState(() {});
  }

  String? _pickDefaultMaleVoice() {
    final malePattern = RegExp(r'male|david|daniel|alex|fred|george|mark|man\b',
        caseSensitive: false);
    final femalePattern = RegExp(
        r'female|samantha|victoria|karen|zira|moira|woman\b',
        caseSensitive: false);
    for (final v in _voices) {
      final name = (v['name'] ?? '').toString();
      if (malePattern.hasMatch(name) && !femalePattern.hasMatch(name)) {
        return name;
      }
    }
    for (final v in _voices) {
      final name = (v['name'] ?? '').toString();
      if (!femalePattern.hasMatch(name)) return name;
    }
    return _voices.isNotEmpty ? (_voices.first['name'] ?? '').toString() : null;
  }

  Future<void> _applySelectedVoice() async {
    if (_selectedVoiceName == null) return;
    final match = _voices.firstWhere(
      (v) => v['name'] == _selectedVoiceName,
      orElse: () => null,
    );
    if (match != null) {
      try {
        await _tts.setVoice(
            {'name': match['name'], 'locale': match['locale'] ?? 'en-US'});
      } catch (_) {}
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _geminiKey = prefs.getString('jarvis_gemini_key');
    _recogLocale = prefs.getString('jarvis_recog_lang') ?? 'en-IN';
    final notesJson = prefs.getString('jarvis_notes');
    final remJson = prefs.getString('jarvis_reminders');
    _notes = notesJson != null
        ? List<Map<String, dynamic>>.from(jsonDecode(notesJson))
        : [];
    _reminders = remJson != null
        ? List<Map<String, dynamic>>.from(jsonDecode(remJson))
        : [];
    // re-arm any reminders that are still in the future
    for (final r in _reminders) {
      final target = DateTime.tryParse(r['time'] ?? '');
      if (target != null && target.isAfter(DateTime.now())) {
        _scheduleNotification(r['id'], target, r['message']);
      }
    }
    setState(() {});
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jarvis_notes', jsonEncode(_notes));
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jarvis_reminders', jsonEncode(_reminders));
  }

  // ---------------- weather ----------------
  static const Map<int, String> wmo = {
    0: 'Clear Sky', 1: 'Mainly Clear', 2: 'Partly Cloudy', 3: 'Overcast',
    45: 'Fog', 48: 'Fog', 51: 'Light Drizzle', 53: 'Drizzle',
    55: 'Dense Drizzle', 61: 'Light Rain', 63: 'Rain', 65: 'Heavy Rain',
    71: 'Light Snow', 73: 'Snow', 75: 'Heavy Snow', 80: 'Rain Showers',
    81: 'Rain Showers', 82: 'Violent Showers', 95: 'Thunderstorm',
    96: 'Thunderstorm', 99: 'Thunderstorm',
  };

  Future<void> _loadWeatherByLocation() async {
    // GPS-based location removed to avoid a build-tooling conflict with
    // geolocator_android. Defaults to a fixed city — use the "Search a
    // city…" box in the Weather panel for anywhere else.
    await _renderWeather(13.0827, 80.2707, 'Chennai, India (default)');
  }

  Future<void> _renderWeather(double lat, double lon, String label) async {
    try {
      final r = await http.get(Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m'));
      final w = jsonDecode(r.body)['current'];
      setState(() {
        _wTemp = '${w['temperature_2m'].round()}°C';
        _wDesc = wmo[w['weather_code']] ?? '—';
        _wLoc = label;
        _wFeels = '${w['apparent_temperature'].round()}°C';
        _wHum = '${w['relative_humidity_2m']}%';
        _wWind = '${w['wind_speed_10m'].round()} km/h';
      });
    } catch (_) {
      setState(() => _wDesc = 'Weather unavailable');
    }
  }

  Future<void> _searchCity() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) return;
    try {
      final g = await http.get(Uri.parse(
          'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1'));
      final gd = jsonDecode(g.body);
      if (gd['results'] == null || (gd['results'] as List).isEmpty) {
        _toast('City not found');
        return;
      }
      final r0 = gd['results'][0];
      await _renderWeather(
          r0['latitude'], r0['longitude'], '${r0['name']}, ${r0['country'] ?? ''}');
    } catch (_) {
      _toast('Weather search failed');
    }
  }

  // ---------------- AI ----------------
  Future<String?> _askGemini(String query, String apiKey) async {
    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=$apiKey');
      final r = await http.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': '$systemPrompt\n\nQuestion: $query'}
                ]
              }
            ]
          }));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      return data['candidates']?[0]?['content']?['parts']?[0]?['text']
          ?.toString()
          .trim();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _askPollinations(String query) async {
    try {
      final url = Uri.parse(
          'https://text.pollinations.ai/${Uri.encodeComponent(query)}?system=${Uri.encodeComponent(systemPrompt)}&model=openai');
      final r = await http.get(url);
      if (r.statusCode != 200) return null;
      final text = r.body.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  Future<String> _askAI(String query) async {
    if (_geminiKey != null && _geminiKey!.isNotEmpty) {
      final ans = await _askGemini(query, _geminiKey!);
      if (ans != null) return ans;
    }
    final ans = await _askPollinations(query);
    return ans ?? "I couldn't reach an answer for that — check your connection.";
  }

  Future<String?> _wikiAnswer(String query) async {
    try {
      final s = await http.get(Uri.parse(
          'https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&format=json&srlimit=1&origin=*'));
      final sd = jsonDecode(s.body);
      final results = sd['query']?['search'];
      if (results == null || results.isEmpty) return null;
      final title = results[0]['title'];
      final sum = await http.get(Uri.parse(
          'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}'));
      final sumd = jsonDecode(sum.body);
      final extract = sumd['extract'];
      if (extract == null) return null;
      final parts = (extract as String).split('. ');
      return parts.take(2).join('. ').trim();
    } catch (_) {
      return null;
    }
  }

  // ---------------- voice ----------------
  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      _toast('Voice input not available on this device.');
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() {
      _listening = true;
      _statusLine = 'LISTENING…';
    });
    await _speech.listen(
      localeId: _recogLocale,
      onResult: (result) {
        if (result.finalResult) {
          final text = result.recognizedWords;
          setState(() {
            _listening = false;
            _statusLine = 'Tap the mic and speak, or type a command below.';
          });
          _addBubble(true, text);
          _handleCommand(text);
        }
      },
    );
  }

  // ---------------- notes / reminders ----------------
  void _addNote(String text) {
    _notes.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': text
    });
    _saveNotes();
    setState(() {});
  }

  void _deleteNote(String id) {
    _notes.removeWhere((n) => n['id'] == id);
    _saveNotes();
    setState(() {});
  }

  Future<DateTime> _addReminder(int hh, int mm, String message) async {
    var target = DateTime.now();
    target = DateTime(target.year, target.month, target.day, hh, mm);
    if (target.isBefore(DateTime.now())) {
      target = target.add(const Duration(days: 1));
    }
    final id = DateTime.now().millisecondsSinceEpoch;
    _reminders.add({'id': id, 'time': target.toIso8601String(), 'message': message});
    _saveReminders();
    await _scheduleNotification(id, target, message);
    setState(() {});
    return target;
  }

  void _deleteReminder(dynamic id) {
    _reminders.removeWhere((r) => r['id'] == id);
    _saveReminders();
    notifications.cancel(id is int ? id : int.tryParse(id.toString()) ?? 0);
    setState(() {});
  }

  Future<void> _scheduleNotification(
      dynamic id, DateTime target, String message) async {
    final notifId = id is int ? id : int.tryParse(id.toString()) ?? 0;
    try {
      await notifications.zonedSchedule(
        notifId,
        'J.A.R.V.I.S Reminder',
        message,
        tz.TZDateTime.from(target, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'jarvis_reminders',
            'Reminders & Alarms',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  // ---------------- app / URL opening ----------------
  Future<void> _openApp(String name) async {
    final url = apps[name];
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _openInChrome(String url) async {
    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: url,
        package: 'com.android.chrome',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (_) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSongInSpotify(String query) async {
    final webUrl = 'https://open.spotify.com/search/${Uri.encodeComponent(query)}';
    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: webUrl,
        package: 'com.spotify.music',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (_) {
      await launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
    }
  }

  // ---------------- command parsing ----------------
  List<int>? _extractTime(String t) {
    final m =
        RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?', caseSensitive: false)
            .firstMatch(t);
    if (m == null) return null;
    int hh = int.tryParse(m.group(1) ?? '') ?? -1;
    int mm = int.tryParse(m.group(2) ?? '0') ?? 0;
    final ap = m.group(3)?.toLowerCase();
    if (hh < 0) return null;
    if (ap == 'pm' && hh < 12) hh += 12;
    if (ap == 'am' && hh == 12) hh = 0;
    if (hh > 23 || mm > 59) return null;
    return [hh, mm];
  }

  String _stripWakeWord(String t) {
    return t
        .replaceFirst(RegExp(r'^\s*(hey\s+)?jarvis[,]?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^\s*(please|can you|could you)\s+', caseSensitive: false), '')
        .trim();
  }

  void _addBubble(bool fromUser, String text) {
    setState(() => _chat.add(_ChatMsg(fromUser, text)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _handleCommand(String raw) async {
    final t = _stripWakeWord(raw.toLowerCase());
    String? reply;

    if (t.contains('remind me')) {
      final tm = _extractTime(t);
      final m = RegExp(r'remind me (to|about)\s+(.*?)(\s+at\s+.*)?$').firstMatch(t);
      final message = m != null ? m.group(2)!.trim() : t.replaceAll('remind me', '').trim();
      if (tm != null) {
        final target = await _addReminder(tm[0], tm[1], message);
        reply = 'Reminder set for ${_fmtTime(target)} — $message.';
      } else {
        reply = "Please give me a time too, e.g. 'remind me to call mom at 6 pm'.";
      }
    } else if (t.contains('take a note') || t.contains('note that') || t.contains('write a note')) {
      final text = t
          .replaceFirst(RegExp(r'^(take a note( that)?|note that|write a note( that)?)\s*'), '')
          .trim();
      if (text.isNotEmpty) {
        _addNote(text);
        reply = 'Noted: $text';
      } else {
        reply = 'What should I note down?';
      }
    } else if (t.contains('read my notes') || t.contains('my notes')) {
      reply = _notes.isNotEmpty
          ? 'Your recent notes: ${_notes.reversed.take(5).map((n) => n['text']).join('; ')}'
          : "You don't have any notes yet.";
    } else if (t.contains('alarm')) {
      final tm = _extractTime(t);
      if (tm != null) {
        final target = await _addReminder(tm[0], tm[1], 'Alarm');
        reply = 'Alarm set for ${_fmtTime(target)}.';
      } else {
        reply = "Please tell me a time, e.g. 'set alarm 7:30 am'.";
      }
    } else if (t.startsWith('play ')) {
      final song = t
          .replaceFirst(RegExp(r'^play\s+(a\s+)?(song\s+)?(called\s+)?'), '')
          .replaceFirst(RegExp(r'\s+(on spotify|on youtube)$'), '')
          .trim();
      final wantsYoutube = t.endsWith(' on youtube');
      if (song.isEmpty) {
        await _openApp('spotify');
        reply = 'Opening Spotify.';
      } else if (wantsYoutube) {
        await launchUrl(Uri.parse(
            'https://www.youtube.com/results?search_query=${Uri.encodeComponent(song)}'));
        reply = 'Searching YouTube for $song.';
      } else {
        await _openSongInSpotify(song);
        reply = 'Playing $song on Spotify.';
      }
    } else if (t.startsWith('search for') || t.startsWith('google ') || t.startsWith('search ')) {
      final q = t.replaceFirst(RegExp(r'^(search for|search|google)\s*'), '').trim();
      if (q.isNotEmpty) {
        await _openInChrome('https://www.google.com/search?q=${Uri.encodeComponent(q)}');
        reply = 'Searching Chrome for $q.';
      } else {
        reply = 'What should I search for?';
      }
    } else if (t.contains('browser') || t.contains('chrome')) {
      await _openInChrome('https://google.com');
      reply = 'Opening Chrome.';
    } else if (apps.keys.any((name) => t.contains(name)) &&
        (t.contains('open') || t.contains('launch') || t.split(' ').length <= 3)) {
      final opened = apps.keys.firstWhere((name) => t.contains(name));
      await _openApp(opened);
      reply = 'Opening ${opened[0].toUpperCase()}${opened.substring(1)}.';
    } else if (t.startsWith('who is') || t.startsWith('what is') ||
        t.startsWith('define') || t.startsWith('tell me about')) {
      final q = t
          .replaceFirst(RegExp(r'^(who is|what is|define|tell me about)\s*'), '')
          .trim();
      _addBubble(false, 'Searching…');
      var answer = q.isNotEmpty ? await _wikiAnswer(q) : null;
      answer ??= q.isNotEmpty ? await _askAI(raw) : null;
      reply = answer ?? "I couldn't find an answer to that.";
      _addBubble(false, reply);
      _speak(reply);
      return;
    } else if (t.contains('time')) {
      final now = DateTime.now();
      reply = "It's ${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}.";
    } else if (t.contains('date') || t.contains('today')) {
      final now = DateTime.now();
      reply = 'Today is ${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}.';
    } else if (t.contains('weather')) {
      reply = '$_wDesc, $_wTemp — see the Weather panel.';
    } else if (['hello', 'hi', 'hey'].contains(t) || t.contains('how are you')) {
      reply = 'At your service. What can I do for you?';
    } else {
      _addBubble(false, 'Thinking…');
      reply = await _askAI(raw);
      _addBubble(false, reply);
      _speak(reply);
      return;
    }

    _addBubble(false, reply);
    _speak(reply);
  }

  String _fmtTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:${t.minute.toString().padLeft(2, '0')} $ap';
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: panelBg, duration: const Duration(seconds: 2)),
    );
  }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _chatCtrl.clear();
    _addBubble(true, text);
    _handleCommand(text);
  }

  void _setAlarmFromField() {
    final val = _alarmCtrl.text.trim(); // expects HH:MM 24h
    final parts = val.split(':');
    if (parts.length != 2) {
      _toast('Enter time as HH:MM, e.g. 07:30');
      return;
    }
    final hh = int.tryParse(parts[0]);
    final mm = int.tryParse(parts[1]);
    if (hh == null || mm == null) {
      _toast('Enter time as HH:MM, e.g. 07:30');
      return;
    }
    _addReminder(hh, mm, 'Alarm').then((target) {
      _toast('Alarm set for ${_fmtTime(target)}');
    });
  }

  Future<void> _saveGeminiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final val = _geminiCtrl.text.trim();
    if (val.isNotEmpty) {
      await prefs.setString('jarvis_gemini_key', val);
      _geminiKey = val;
      _toast('Gemini key saved — now using Gemini for questions');
    } else {
      await prefs.remove('jarvis_gemini_key');
      _geminiKey = null;
      _toast('Key cleared — back to free fallback AI');
    }
    _geminiCtrl.clear();
    setState(() {});
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _header(),
            const SizedBox(height: 14),
            _corePanel(),
            const SizedBox(height: 14),
            _panel('WEATHER', tag: 'LIVE', child: _weatherBody()),
            const SizedBox(height: 14),
            _panel('QUICK OPEN', child: _quickOpenGrid()),
            const SizedBox(height: 14),
            _panel('COMMAND LOG', child: _commandLogBody()),
            const SizedBox(height: 14),
            _panel('NOTES & REMINDERS', tag: 'ON THIS PHONE', child: _notesBody()),
            const SizedBox(height: 14),
            _panel('VOICE SETTINGS', child: _voiceSettingsBody()),
            const SizedBox(height: 14),
            _panel('AI ENGINE',
                tag: (_geminiKey?.isNotEmpty ?? false) ? 'GEMINI' : 'FREE FALLBACK',
                child: _aiSettingsBody()),
            const SizedBox(height: 14),
            _panel('ALARM', child: _alarmBody()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.circle, color: green, size: 8),
              SizedBox(width: 6),
              Text('MOBILE • NATIVE APP',
                  style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            ]),
            const SizedBox(height: 2),
            const Text('J.A.R.V.I.S',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_dateLabel, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(_clock, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ],
    );
  }

  Widget _corePanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Text(_listening ? 'LISTENING…' : 'STANDING BY',
              style: const TextStyle(color: red, fontSize: 11, letterSpacing: 3)),
          const SizedBox(height: 4),
          Text(_statusLine,
              textAlign: TextAlign.center,
              style: const TextStyle(color: cyanSoft, fontSize: 12)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _toggleListening,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0D2C3F),
                border: Border.all(color: _listening ? red : cyan, width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: (_listening ? red : cyan).withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: _listening ? 4 : 1)
                ],
              ),
              child: Icon(Icons.mic, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(height: 8),
          const Text('TAP TO TALK',
              style: TextStyle(color: cyanSoft, fontSize: 11, letterSpacing: 1)),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: panelBg.withOpacity(0.6),
        border: Border.all(color: cyan.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(4),
      );

  Widget _panel(String title, {String? tag, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, color: cyan),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: cyanSoft, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
              if (tag != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      border: Border.all(color: tag == 'LIVE' || tag == 'GEMINI' ? green : amber),
                      borderRadius: BorderRadius.circular(3)),
                  child: Text(tag,
                      style: TextStyle(
                          color: tag == 'LIVE' || tag == 'GEMINI' ? green : amber, fontSize: 9)),
                )
              ]
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _weatherBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_wTemp, style: const TextStyle(color: Colors.white, fontSize: 24)),
                Text(_wDesc, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Text(_wLoc, style: const TextStyle(color: cyanSoft, fontSize: 11)),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Feels $_wFeels', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                Text('Humidity $_wHum', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                Text('Wind $_wWind', style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _textField(_cityCtrl, 'Search a city…')),
          const SizedBox(width: 6),
          _smallButton('GO', _searchCity),
        ]),
      ],
    );
  }

  Widget _quickOpenGrid() {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: apps.keys.map((name) {
        return GestureDetector(
          onTap: () => _handleCommand('open $name'),
          child: Column(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  border: Border.all(color: cyan.withOpacity(0.25)),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.apps, color: cyanSoft, size: 18),
            ),
            const SizedBox(height: 4),
            Text(name.toUpperCase(),
                style: const TextStyle(color: Colors.white38, fontSize: 8)),
          ]),
        );
      }).toList(),
    );
  }

  Widget _commandLogBody() {
    return Column(
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            controller: _chatScroll,
            shrinkWrap: true,
            itemCount: _chat.length,
            itemBuilder: (ctx, i) {
              final m = _chat[i];
              return Align(
                alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                  decoration: BoxDecoration(
                      color: m.fromUser ? cyan.withOpacity(0.18) : cyan.withOpacity(0.06),
                      border: Border.all(color: cyan.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _textField(_chatCtrl, 'Type a command…', onSubmit: (_) => _sendChat())),
          const SizedBox(width: 6),
          _smallButton('SEND', _sendChat),
        ]),
        const SizedBox(height: 8),
        const Text(
          "Try: open youtube · take a note buy milk · remind me to call mom at 6 pm · set alarm 07:30 · or ask anything else",
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  Widget _notesBody() {
    if (_notes.isEmpty && _reminders.isEmpty) {
      return const Text('No notes or reminders yet.',
          style: TextStyle(color: Colors.white38, fontSize: 12));
    }
    return Column(
      children: [
        ..._reminders.map((r) {
          final t = DateTime.parse(r['time']);
          return _listRow('⏰ ${_fmtTime(t)} — ${r['message']}', () => _deleteReminder(r['id']));
        }),
        ..._notes.reversed.map((n) => _listRow('📝 ${n['text']}', () => _deleteNote(n['id']))),
      ],
    );
  }

  Widget _listRow(String text, VoidCallback onDelete) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12))),
        GestureDetector(
            onTap: onDelete, child: const Icon(Icons.close, color: red, size: 16)),
      ]),
    );
  }

  Widget _voiceSettingsBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: panelBg,
              value: _selectedVoiceName,
              hint: const Text('Select voice', style: TextStyle(color: Colors.white38)),
              items: _voices
                  .map<DropdownMenuItem<String>>((v) => DropdownMenuItem(
                      value: v['name'], child: Text(v['name'], style: const TextStyle(color: Colors.white, fontSize: 12))))
                  .toList(),
              onChanged: (val) async {
                setState(() => _selectedVoiceName = val);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('jarvis_voice_name', val ?? '');
                await _applySelectedVoice();
              },
            ),
          ),
          _smallButton('TEST', () => _speak('At your service. This is how I\'ll sound.')),
        ]),
        const SizedBox(height: 8),
        DropdownButton<String>(
          isExpanded: true,
          dropdownColor: panelBg,
          value: _recogLocale,
          items: const [
            DropdownMenuItem(value: 'en-IN', child: Text('English (India) — recommended', style: TextStyle(color: Colors.white, fontSize: 12))),
            DropdownMenuItem(value: 'en-US', child: Text('English (US)', style: TextStyle(color: Colors.white, fontSize: 12))),
            DropdownMenuItem(value: 'en-GB', child: Text('English (UK)', style: TextStyle(color: Colors.white, fontSize: 12))),
            DropdownMenuItem(value: 'en-AU', child: Text('English (Australia)', style: TextStyle(color: Colors.white, fontSize: 12))),
          ],
          onChanged: (val) async {
            setState(() => _recogLocale = val ?? 'en-IN');
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('jarvis_recog_lang', _recogLocale);
          },
        ),
      ],
    );
  }

  Widget _aiSettingsBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _textField(_geminiCtrl, 'Paste your free Gemini API key…', obscure: true)),
          const SizedBox(width: 6),
          _smallButton('SAVE', _saveGeminiKey),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Get a free key (no card) at aistudio.google.com/apikey. Saved only on this device.',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  Widget _alarmBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _textField(_alarmCtrl, 'HH:MM (24h), e.g. 07:30')),
          const SizedBox(width: 6),
          _smallButton('SET', _setAlarmFromField),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Uses real native notifications — fires even if the app is in the background, unlike a web app.',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  Widget _textField(TextEditingController ctrl, String hint,
      {bool obscure = false, void Function(String)? onSubmit}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      onSubmitted: onSubmit,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: Colors.white.withOpacity(0.03),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cyan.withOpacity(0.25))),
      ),
    );
  }

  Widget _smallButton(String label, VoidCallback onTap) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: cyan.withOpacity(0.15),
          foregroundColor: cyanSoft,
          side: const BorderSide(color: cyan),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

class _ChatMsg {
  final bool fromUser;
  final String text;
  _ChatMsg(this.fromUser, this.text);
}
