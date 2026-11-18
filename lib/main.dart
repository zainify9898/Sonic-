import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bg = Color(0xFF080F1E);
const panel = Color(0xFF142039);
const blue = Color(0xFF4385FF);
const mint = Color(0xFF72E4DA);

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const Soniq()); }

class Song {
  final String path;
  final String title;
  Song(this.path, this.title);
}

class Soniq extends StatelessWidget {
  const Soniq({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'SONIQ',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: bg, colorScheme: const ColorScheme.dark(primary: blue, secondary: mint, surface: panel),
      appBarTheme: const AppBarTheme(backgroundColor: bg),
      cardTheme: CardThemeData(color: panel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    ), home: const MusicHome(),
  );
}

class MusicHome extends StatefulWidget {
  const MusicHome({super.key});
  @override State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome> {
  final player = AudioPlayer();
  final search = TextEditingController();
  final songs = <Song>[];
  final favorites = <String>{};
  final playlists = <String, List<String>>{};
  final history = <String>[];
  final queue = <String>[];
  StreamSubscription<Duration>? positionSub, durationSub;
  StreamSubscription<void>? completeSub;
  Duration position = Duration.zero, duration = Duration.zero;
  String? current;
  bool playing = false, shuffle = false;
  int repeat = 0, tab = 0;
  String mood = 'All';
  Timer? sleep;
  SharedPreferences? prefs;

  @override void initState() { super.initState(); _load();
    positionSub = player.onPositionChanged.listen((v) { if (mounted) setState(() => position = v); });
    durationSub = player.onDurationChanged.listen((v) { if (mounted) setState(() => duration = v); });
    completeSub = player.onPlayerComplete.listen((_) => _next(completed: true));
    player.onPlayerStateChanged.listen((v) { if (mounted) setState(() => playing = v == PlayerState.playing); });
  }
  Future<void> _load() async {
    prefs = await SharedPreferences.getInstance();
    final paths = prefs!.getStringList('songs') ?? [];
    for (final path in paths) { if (await File(path).exists()) songs.add(Song(path, p.basenameWithoutExtension(path))); }
    favorites.addAll(prefs!.getStringList('favorites') ?? []);
    history.addAll(prefs!.getStringList('history') ?? []);
    for (final name in prefs!.getStringList('playlistNames') ?? []) { playlists[name] = prefs!.getStringList('playlist:$name') ?? []; }
    if (mounted) setState(() {});
  }
  Future<void> _save() async {
    final store = prefs; if (store == null) return;
    await store.setStringList('songs', songs.map((e) => e.path).toList());
    await store.setStringList('favorites', favorites.toList());
    await store.setStringList('history', history.take(100).toList());
    await store.setStringList('playlistNames', playlists.keys.toList());
    for (final entry in playlists.entries) { await store.setStringList('playlist:${entry.key}', entry.value); }
  }
  Future<void> _import() async {
    try {
      final files = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true, withData: false);
      if (files == null) return;
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'music'));
      await dir.create(recursive: true);
      var count = 0;
      for (final item in files.files) {
        if (item.path == null) continue;
        final source = File(item.path!);
        if (!await source.exists()) continue;
        final target = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_${p.basename(item.name)}');
        await source.copy(target);
        songs.add(Song(target, p.basenameWithoutExtension(item.name)));
        count++;
      }
      await _save(); if (mounted) { setState(() {}); _notice('Imported $count tracks'); }
    } catch (e) { _notice('Import failed: $e'); }
  }
  void _notice(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  Future<void> _play(String path, {bool resetQueue = true}) async {
    try {
      if (resetQueue) { queue..clear()..addAll(songs.map((s) => s.path)); }
      current = path; position = Duration.zero;
      history.remove(path); history.insert(0, path); await _save();
      await player.stop(); await player.play(DeviceFileSource(path));
      if (mounted) setState(() {});
    } catch (e) { _notice('Could not play file: $e'); }
  }
  Future<void> _toggle() async { if (playing) { await player.pause(); } else if (current != null) { await player.resume(); } }
  Future<void> _next({bool completed = false, bool backwards = false}) async {
    if (current == null || queue.isEmpty) return;
    if (completed && repeat == 2) { await player.seek(Duration.zero); await player.resume(); return; }
    var i = queue.indexOf(current!); if (i < 0) i = 0;
    if (shuffle && !backwards && queue.length > 1) {
      var n = i; while (n == i) { n = Random().nextInt(queue.length); }
      await _play(queue[n], resetQueue: false); return;
    }
    final n = i + (backwards ? -1 : 1);
    if (n < 0 || n >= queue.length) {
      if (repeat == 1) { await _play(queue[(n + queue.length) % queue.length], resetQueue: false); }
      else { await player.stop(); }
    } else { await _play(queue[n], resetQueue: false); }
  }
  void _sleep(int minutes) {
    sleep?.cancel(); if (minutes > 0) sleep = Timer(Duration(minutes: minutes), () { player.pause(); if (mounted) _notice('Sleep timer finished'); });
    _notice(minutes == 0 ? 'Sleep timer off' : 'Sleep timer: $minutes minutes');
  }
  void _favorite(String path) { setState(() { if (!favorites.add(path)) favorites.remove(path); }); _save(); }
  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New playlist'), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist name')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create'))],
    ));
    controller.dispose(); if (name == null || name.isEmpty) return;
    setState(() => playlists.putIfAbsent(name, () => [])); await _save();
  }
  void _songActions(Song song) {
    showModalBottomSheet(context: context, backgroundColor: panel, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.playlist_play), title: const Text('Play next'), onTap: () { Navigator.pop(ctx); setState(() { queue.remove(song.path); final i = queue.indexOf(current ?? ''); queue.insert(i < 0 ? 0 : i + 1, song.path); }); }),
      ListTile(leading: const Icon(Icons.queue_music), title: const Text('Add to queue'), onTap: () { Navigator.pop(ctx); setState(() => queue.add(song.path)); }),
      ...playlists.keys.map((name) => ListTile(leading: const Icon(Icons.playlist_add), title: Text('Add to $name'), onTap: () { Navigator.pop(ctx); setState(() { if (!playlists[name]!.contains(song.path)) playlists[name]!.add(song.path); }); _save(); _notice('Added to $name'); })),
    ])));
  }
  Widget _songList(List<Song> items) => items.isEmpty
    ? const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('No tracks here yet. Import audio from your phone.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))))
    : ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length, itemBuilder: (_, i) {
      final s = items[i]; final active = current == s.path;
      return Card(child: ListTile(
        leading: Container(width: 46, height: 46, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [blue, mint])), child: const Icon(Icons.graphic_eq, color: bg)),
        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? mint : Colors.white)),
        subtitle: Text(active && playing ? 'Now playing' : 'Local audio', style: const TextStyle(color: Colors.white54)),
        onTap: () => _play(s.path),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: () => _favorite(s.path), icon: Icon(favorites.contains(s.path) ? Icons.favorite : Icons.favorite_border, color: favorites.contains(s.path) ? mint : Colors.white60)),
          IconButton(onPressed: () => _songActions(s), icon: const Icon(Icons.more_vert)),
        ]),
      ));
    });
  Widget _home() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Hear it your way.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), const Text('Your music. Your space.', style: TextStyle(color: Colors.white54)),
    const SizedBox(height: 24),
    Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.auto_awesome, color: mint, size: 32), const SizedBox(height: 10),
      const Text('Your music, offline', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6), const Text('Import tracks from your phone and listen without an account.', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 14), FilledButton.icon(onPressed: _import, icon: const Icon(Icons.file_upload_outlined), label: const Text('Import music')),
    ]))), const SizedBox(height: 24),
    const Text('Pick your vibe', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: ['All','Focus','Chill','Energize','Night'].map((m) => ChoiceChip(label: Text(m), selected: mood == m, onSelected: (_) => setState(() => mood = m))).toList()),
    const SizedBox(height: 24), const Text('Recently played', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    _songList(history.map((path) => songs.where((s) => s.path == path).firstOrNull).whereType<Song>().toList()),
    const SizedBox(height: 12), const Text('All tracks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), _songList(songs),
  ]);
  Widget _search() { final q = search.text.toLowerCase(); return Column(children: [
    TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search your songs', filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
    const SizedBox(height: 16), _songList(songs.where((s) => s.title.toLowerCase().contains(q)).toList()),
  ]); }
  Widget _library() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Expanded(child: Text('Your library', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))), IconButton(onPressed: _import, icon: const Icon(Icons.add_circle_outline))]),
    const SizedBox(height: 16), const Text('Favorites', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)), _songList(songs.where((s) => favorites.contains(s.path)).toList()),
    const SizedBox(height: 18), Row(children: [const Expanded(child: Text('Playlists', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))), IconButton(onPressed: _createPlaylist, icon: const Icon(Icons.add))]),
    ...playlists.entries.map((entry) => ExpansionTile(title: Text(entry.key), leading: const Icon(Icons.library_music, color: mint), children: [
      _songList(entry.value.map((path) => songs.where((s) => s.path == path).firstOrNull).whereType<Song>().toList()),
    ])),
    const SizedBox(height: 18), const Text('Queue', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)), _songList(queue.map((path) => songs.where((s) => s.path == path).firstOrNull).whereType<Song>().toList()),
  ]);
  Widget _profile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Your SONIQ', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 20),
    Card(child: ListTile(leading: const Icon(Icons.music_note, color: mint), title: Text('${songs.length} imported tracks'), subtitle: Text('${favorites.length} favorites • ${history.length} recently played'))),
    const Card(child: ListTile(leading: Icon(Icons.cloud_off, color: mint), title: Text('Offline-first'), subtitle: Text('Your files and playlists stay on this device.'))),
    const Card(child: ListTile(leading: Icon(Icons.info_outline, color: mint), title: Text('Prototype'), subtitle: Text('Online catalog, lyrics, music rooms and AI services are not connected.'))),
  ]);
  Widget _miniPlayer() {
    if (current == null) return const SizedBox.shrink();
    final title = songs.where((s) => s.path == current).firstOrNull?.title ?? 'Unknown';
    final max = max(1, duration.inMilliseconds).toDouble();
    return Container(color: panel, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [const Icon(Icons.graphic_eq, color: mint), const SizedBox(width: 10), Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
        IconButton(onPressed: () => setState(() => shuffle = !shuffle), icon: Icon(Icons.shuffle, color: shuffle ? mint : Colors.white54)),
        IconButton(onPressed: () => _next(backwards: true), icon: const Icon(Icons.skip_previous)),
        IconButton(onPressed: _toggle, icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: mint, size: 34)),
        IconButton(onPressed: () => _next(), icon: const Icon(Icons.skip_next)),
      ]),
      SliderTheme(data: SliderThemeData(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)), child: Slider(value: position.inMilliseconds.clamp(0, max.toInt()).toDouble(), max: max, onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2,'0')}', style: const TextStyle(fontSize: 11)),
        TextButton.icon(onPressed: () => setState(() => repeat = (repeat + 1) % 3), icon: Icon(repeat == 2 ? Icons.repeat_one : Icons.repeat, size: 17, color: repeat == 0 ? Colors.white54 : mint), label: Text(['Off','All','One'][repeat], style: const TextStyle(fontSize: 11))),
        PopupMenuButton<int>(tooltip: 'Sleep timer', icon: const Icon(Icons.bedtime_outlined, size: 20), onSelected: _sleep, itemBuilder: (_) => [0, 5, 15, 30, 60].map((n) => PopupMenuItem(value: n, child: Text(n == 0 ? 'Sleep off' : '$n minutes'))).toList()),
        Text('${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2,'0')}', style: const TextStyle(fontSize: 11)),
      ]),
    ]));
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [Icon(Icons.graphic_eq, color: mint), SizedBox(width: 9), Text('SONIQ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3))])),
    body: ListView(padding: const EdgeInsets.all(16), children: [if (tab == 0) _home(), if (tab == 1) _search(), if (tab == 2) _library(), if (tab == 3) _profile()]),
    bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
      _miniPlayer(), NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), backgroundColor: bg, indicatorColor: panel,
        destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'), NavigationDestination(icon: Icon(Icons.search), label: 'Search'), NavigationDestination(icon: Icon(Icons.library_music_outlined), label: 'Library'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile')]),
    ]),
  );
  @override void dispose() { sleep?.cancel(); positionSub?.cancel(); durationSub?.cancel(); completeSub?.cancel(); player.dispose(); search.dispose(); super.dispose(); }
}
