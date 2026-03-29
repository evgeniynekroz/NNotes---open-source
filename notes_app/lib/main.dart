import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:local_auth/local_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

// ─── Palette ─────────────────────────────────────────────────

const _seed       = Color(0xFF977DFF);
const _lightBg    = Color(0xFFFCF8FF);
const _darkBg     = Color(0xFF0D0012);
const _gradLight1 = Color(0xFFFFCCF2);
const _gradLight2 = Color(0xFF977DFF);
const _gradDark1  = Color(0xFF1A0033);
const _gradDark2  = Color(0xFF3D1A7A);

// ─── Models ──────────────────────────────────────────────────

class DrawPoint {
  final Offset offset;
  final bool isStart;
  final Color color;
  final double width;
  const DrawPoint({
    required this.offset,
    required this.isStart,
    required this.color,
    required this.width,
  });
}

class Note {
  String id;
  String title;
  String content;
  String folder;
  int color;
  DateTime createdAt;
  DateTime updatedAt;
  bool isPinned;

  Note({
    required this.id,
    this.title = '',
    this.content = '',
    this.folder = 'All',
    this.color = 0xFFFFFFFF,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'folder': folder,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isPinned': isPinned,
  };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'],
    title: j['title'] ?? '',
    content: j['content'] ?? '',
    folder: j['folder'] ?? 'All',
    color: j['color'] ?? 0xFFFFFFFF,
    createdAt: DateTime.parse(j['createdAt']),
    updatedAt: DateTime.parse(j['updatedAt']),
    isPinned: j['isPinned'] ?? false,
  );
}

// ─── Store ───────────────────────────────────────────────────

class NotesStore extends ChangeNotifier {
  final List<Note> _notes = [];
  final List<String> _folders = ['All'];
  late Box _box;

  List<Note> get notes => List.unmodifiable(_notes);
  List<String> get folders => List.unmodifiable(_folders);

  Future<void> init() async {
    _box = await Hive.openBox('notes_v1');
    final raw = _box.get('notes', defaultValue: '[]') as String;
    final fRaw = _box.get('folders', defaultValue: '["All"]') as String;
    _notes.addAll((jsonDecode(raw) as List).map((e) => Note.fromJson(e)));
    _folders
      ..clear()
      ..addAll((jsonDecode(fRaw) as List).cast<String>());
    notifyListeners();
  }

  void _persist() {
    _box.put('notes', jsonEncode(_notes.map((n) => n.toJson()).toList()));
    _box.put('folders', jsonEncode(_folders));
  }

  void add(Note n) { _notes.insert(0, n); _persist(); notifyListeners(); }

  void update(Note n) {
    final i = _notes.indexWhere((e) => e.id == n.id);
    if (i != -1) { _notes[i] = n; _persist(); notifyListeners(); }
  }

  void delete(String id) {
    _notes.removeWhere((n) => n.id == id);
    _persist();
    notifyListeners();
  }

  void addFolder(String name) {
    if (!_folders.contains(name)) { _folders.add(name); _persist(); notifyListeners(); }
  }

  List<Note> search(String q) {
    final lq = q.toLowerCase();
    return _notes
      .where((n) => n.title.toLowerCase().contains(lq) || n.content.toLowerCase().contains(lq))
      .toList();
  }

  List<Note> byFolder(String f) =>
    f == 'All' ? _notes : _notes.where((n) => n.folder == f).toList();
}

// ─── Math Detector ───────────────────────────────────────────

class MathHelper {
  static final _rx = RegExp(
    r'(\d[\d\s]*[\+\-\*\/\^]\s*[\d\s]+\s*=\s*\??'
    r'|[a-z][\²\^2].*=.*'
    r'|\d+\s*[\+\-\*\/]\s*\d+)',
    caseSensitive: false,
  );

  static String? detect(String text) => _rx.firstMatch(text)?.group(0);

  static String? solve(String expr) {
    try {
      final cleaned = expr
        .replaceAll('²', '^2')
        .replaceAll('?', '')
        .replaceAll(RegExp(r'=.*'), '');
      final result = Parser()
        .parse(cleaned)
        .evaluate(EvaluationType.REAL, ContextModel());
      return result.toStringAsFixed(result % 1 == 0 ? 0 : 4);
    } catch (_) {
      return null;
    }
  }
}

// ─── Entry Point ─────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final store = NotesStore();
  await store.init();
  runApp(NotesApp(store: store));
}

// ─── App ─────────────────────────────────────────────────────

class NotesApp extends StatelessWidget {
  final NotesStore store;
  const NotesApp({super.key, required this.store});

  ThemeData _theme(Brightness br) {
    final dark = br == Brightness.dark;
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: br,
        surface: dark ? _darkBg : _lightBg,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: br).textTheme,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) => MaterialApp(
        title: 'NNotes',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: AuthGate(store: store),
      ),
    );
  }
}

// ─── Auth Gate ───────────────────────────────────────────────

class AuthGate extends StatefulWidget {
  final NotesStore store;
  const AuthGate({super.key, required this.store});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _authed = false;
  String _pin = '';
  String _input = '';
  bool _creating = false;
  String _confirm = '';
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('notes_v1');
    _pin = box.get('pin', defaultValue: '') as String;
    if (_pin.isEmpty) {
      _creating = true;
    } else {
      _tryBio();
    }
  }

  Future<void> _tryBio() async {
    try {
      final auth = LocalAuthentication();
      final ok = await auth.authenticate(
        localizedReason: 'Войди в NNotes',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (ok && mounted) setState(() => _authed = true);
    } catch (_) {}
  }

  void _onKey(String k) {
    if (_input.length >= 4) return;
    final next = _input + k;
    setState(() => _input = next);
    if (next.length < 4) return;

    if (_creating && !_confirming) {
      setState(() { _confirm = next; _input = ''; _confirming = true; });
      return;
    }
    if (_creating && _confirming) {
      if (next == _confirm) {
        Hive.box('notes_v1').put('pin', next);
        setState(() { _pin = next; _authed = true; });
      } else {
        HapticFeedback.vibrate();
        setState(() { _input = ''; _confirming = false; _confirm = ''; });
      }
      return;
    }
    if (next == _pin) {
      setState(() => _authed = true);
    } else {
      HapticFeedback.vibrate();
      setState(() => _input = '');
    }
  }

  void _backspace() {
    if (_input.isNotEmpty) setState(() => _input = _input.substring(0, _input.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    if (_authed) return HomeScreen(store: widget.store);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String prompt = _creating
      ? (_confirming ? 'Повтори пин-код' : 'Создай пин-код')
      : 'Введи пин-код';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
              ? [_gradDark1, _gradDark2, const Color(0xFF6A3FCC)]
              : [_gradLight1, _gradLight2, const Color(0xFF0033FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(.2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.note_alt_rounded, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 32),
              Text(prompt,
                style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 32),
              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(10),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _input.length
                      ? Colors.white
                      : Colors.white.withOpacity(.3),
                  ),
                )),
              ),
              const SizedBox(height: 48),
              // Numpad
              for (final row in [[1, 2, 3], [4, 5, 6], [7, 8, 9]])
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: row.map((n) => _PinBtn(
                    label: '$n',
                    onTap: () => _onKey('$n'),
                  )).toList(),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_creating)
                    _PinBtn(label: '⬡', onTap: _tryBio)
                  else
                    const SizedBox(width: 88),
                  _PinBtn(label: '0', onTap: () => _onKey('0')),
                  _PinBtn(label: '⌫', onTap: _backspace),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PinBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80, height: 80,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.15),
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(
          fontSize: 26, fontWeight: FontWeight.w500, color: Colors.white,
        )),
      ),
    );
  }
}

// ─── Home Screen ─────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final NotesStore store;
  const HomeScreen({super.key, required this.store});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _folder = 'All';
  String _query = '';
  final _searchCtrl = TextEditingController();

  List<Note> get _visible {
    final base = _query.isNotEmpty
      ? widget.store.search(_query)
      : widget.store.byFolder(_folder);
    return [...base.where((n) => n.isPinned), ...base.where((n) => !n.isPinned)];
  }

  void _open([Note? note]) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => NoteEditor(store: widget.store, note: note),
    ));
    setState(() {});
  }

  void _addFolder() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Новая папка'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название папки'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                widget.store.addFolder(ctrl.text.trim());
                setState(() {});
              }
              Navigator.pop(context);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: isDark
              ? [_gradDark1, cs.surface]
              : [_gradLight1.withOpacity(.4), cs.surface],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: Text('Заметки',
                      style: GoogleFonts.inter(
                        fontSize: 34, fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      )),
                  ),
                  IconButton.filledTonal(
                    onPressed: _addFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: 'Новая папка',
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SearchBar(
                  controller: _searchCtrl,
                  hintText: 'Поиск по заметкам...',
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.search),
                  ),
                  trailing: [
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() { _query = ''; _searchCtrl.clear(); }),
                      ),
                  ],
                  onChanged: (v) => setState(() => _query = v),
                  elevation: const WidgetStatePropertyAll(0),
                ),
              ),
              const SizedBox(height: 14),

              // Folders chips
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: widget.store.folders.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = widget.store.folders[i];
                    final active = f == _folder;
                    return FilterChip(
                      label: Text(f),
                      selected: active,
                      onSelected: (_) => setState(() => _folder = f),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Notes
              Expanded(
                child: _visible.isEmpty
                  ? Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note_outlined, size: 72, color: cs.outline),
                        const SizedBox(height: 12),
                        Text('Нет заметок', style: TextStyle(color: cs.outline, fontSize: 16)),
                      ],
                    ))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: .82,
                      ),
                      itemCount: _visible.length,
                      itemBuilder: (_, i) => _NoteCard(
                        note: _visible[i],
                        onTap: () => _open(_visible[i]),
                        onDelete: () {
                          widget.store.delete(_visible[i].id);
                          setState(() {});
                        },
                        onPin: () {
                          final n = _visible[i];
                          final updated = Note(
                            id: n.id, title: n.title, content: n.content,
                            folder: n.folder, color: n.color,
                            createdAt: n.createdAt, updatedAt: n.updatedAt,
                            isPinned: !n.isPinned,
                          );
                          widget.store.update(updated);
                          setState(() {});
                        },
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Заметка'),
      ),
    );
  }
}

// ─── Note Card ───────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasColor = note.color != 0xFFFFFFFF;
    final base = hasColor ? Color(note.color) : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: cs.outline.withOpacity(.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(note.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(note.isPinned ? 'Открепить' : 'Закрепить'),
                onTap: () { Navigator.pop(context); onPin(); },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
                onTap: () { Navigator.pop(context); onDelete(); },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: hasColor
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                  ? [cs.surfaceContainerHighest, cs.surfaceContainerHigh]
                  : [cs.surfaceContainerLowest, cs.secondaryContainer.withOpacity(.4)],
              ),
          color: hasColor ? base : null,
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.isPinned) ...[
              Icon(Icons.push_pin, size: 13, color: cs.primary),
              const SizedBox(height: 4),
            ],
            if (note.title.isNotEmpty) ...[
              Text(
                note.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: hasColor ? Colors.white : cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Expanded(
              child: Text(
                note.content,
                maxLines: 7,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: hasColor
                    ? Colors.white.withOpacity(.85)
                    : cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('d MMM', 'ru').format(note.updatedAt),
              style: TextStyle(
                fontSize: 11,
                color: hasColor ? Colors.white.withOpacity(.6) : cs.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Note Editor ─────────────────────────────────────────────

class NoteEditor extends StatefulWidget {
  final NotesStore store;
  final Note? note;
  const NoteEditor({super.key, required this.store, this.note});
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _title;
  late TextEditingController _content;
  bool _preview = false;
  bool _drawing = false;
  Color _noteColor = const Color(0xFFFFFFFF);
  bool _pinned = false;
  String _folder = 'All';
  String? _mathExpr;

  // Drawing state
  final List<DrawPoint> _points = [];
  Color _penColor = const Color(0xFF977DFF);
  double _penWidth = 4.0;
  bool _eraser = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _title   = TextEditingController(text: n?.title ?? '');
    _content = TextEditingController(text: n?.content ?? '');
    if (n != null) {
      _noteColor = Color(n.color);
      _pinned    = n.isPinned;
      _folder    = n.folder;
    }
    _content.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    final expr = MathHelper.detect(_content.text);
    if (expr != _mathExpr) setState(() => _mathExpr = expr);
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _save() {
    final now = DateTime.now();
    final n = widget.note;
    final note = Note(
      id: n?.id ?? const Uuid().v4(),
      title: _title.text.trim(),
      content: _content.text,
      folder: _folder,
      color: _noteColor.value,
      createdAt: n?.createdAt ?? now,
      updatedAt: now,
      isPinned: _pinned,
    );
    n == null ? widget.store.add(note) : widget.store.update(note);
    Navigator.pop(context);
  }

  // Insert markdown syntax around selection
  void _md(String before, [String after = '']) {
    final s = _content.selection;
    final t = _content.text;
    if (!s.isValid || s.isCollapsed) {
      final ins = '$before$after';
      final pos = (s.isValid ? s.start : t.length);
      _content.value = TextEditingValue(
        text: t.substring(0, pos) + ins + t.substring(pos),
        selection: TextSelection.collapsed(offset: pos + before.length),
      );
    } else {
      final sel = t.substring(s.start, s.end);
      final rep = '$before$sel$after';
      _content.value = TextEditingValue(
        text: t.replaceRange(s.start, s.end, rep),
        selection: TextSelection.collapsed(offset: s.start + rep.length),
      );
    }
  }

  void _showMath() {
    if (_mathExpr == null) return;
    final result = MathHelper.solve(_mathExpr!);
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Выражение',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 6),
            Text(_mathExpr!,
              style: GoogleFonts.jetBrainsMono(fontSize: 18)),
            const Divider(height: 32),
            Text('Результат',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 6),
            Text(
              result != null ? '= $result' : 'Не удалось вычислить',
              style: GoogleFonts.inter(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickColor() {
    Color temp = _noteColor;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Цвет заметки'),
        content: BlockPicker(
          pickerColor: temp,
          onColorChanged: (c) => temp = c,
          availableColors: const [
            Colors.white, Color(0xFFFFCCF2), Color(0xFFE8D5FF),
            Color(0xFFD5E8FF), Color(0xFFD5FFE8), Color(0xFFFFE8D5),
            Color(0xFF977DFF), Color(0xFF5B3FD4), Color(0xFF2D1B6E),
            Color(0xFF1A0033), Colors.black, Color(0xFF1E1E2E),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            setState(() => _noteColor = temp);
            Navigator.pop(context);
          }, child: const Text('OK')),
        ],
      ),
    );
  }

  void _pickFolder() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ...widget.store.folders.map((f) => ListTile(
              leading: Icon(
                _folder == f ? Icons.folder : Icons.folder_outlined,
                color: _folder == f ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(f),
              onTap: () { setState(() => _folder = f); Navigator.pop(context); },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasColor = _noteColor.value != 0xFFFFFFFF;

    Color bgColor = hasColor
      ? (isDark ? _noteColor.withOpacity(.2) : _noteColor.withOpacity(.12))
      : cs.surface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _save,
        ),
        actions: [
          // Pin
          IconButton(
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () => setState(() => _pinned = !_pinned),
            tooltip: 'Закрепить',
          ),
          // Color
          GestureDetector(
            onTap: _pickColor,
            child: Container(
              width: 28, height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: hasColor ? _noteColor : cs.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outline.withOpacity(.4), width: 1.5),
              ),
            ),
          ),
          // Folder
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            onPressed: _pickFolder,
            tooltip: 'Папка',
          ),
          // Preview toggle
          IconButton(
            icon: Icon(_preview ? Icons.edit_note_rounded : Icons.visibility_outlined),
            onPressed: () => setState(() { _preview = !_preview; _drawing = false; }),
            tooltip: _preview ? 'Редактор' : 'Просмотр',
          ),
          // Draw toggle
          IconButton(
            icon: Icon(_drawing ? Icons.text_fields_rounded : Icons.draw_outlined),
            onPressed: () => setState(() { _drawing = !_drawing; _preview = false; }),
            tooltip: _drawing ? 'Текст' : 'Рисование',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: TextField(
              controller: _title,
              style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                hintText: 'Заголовок',
                hintStyle: TextStyle(color: cs.outline.withOpacity(.5)),
                border: InputBorder.none,
              ),
              maxLines: 2,
              minLines: 1,
            ),
          ),

          // Math banner
          if (_mathExpr != null && !_drawing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FilledButton.tonal(
                onPressed: _showMath,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.functions_rounded, size: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text(
                      'Решить: $_mathExpr',
                      overflow: TextOverflow.ellipsis,
                    )),
                  ],
                ),
              ),
            ),

          // Markdown toolbar (edit mode)
          if (!_preview && !_drawing) _MdToolbar(onInsert: _md),

          // Drawing toolbar
          if (_drawing) _DrawToolbar(
            color: _penColor,
            width: _penWidth,
            isEraser: _eraser,
            onColor: (c) => setState(() => _penColor = c),
            onWidth: (w) => setState(() => _penWidth = w),
            onEraser: () => setState(() => _eraser = !_eraser),
            onClear: () => setState(() => _points.clear()),
          ),

          // Body
          Expanded(
            child: _drawing
              ? _Canvas(
                  points: _points,
                  color: _penColor,
                  width: _penWidth,
                  eraser: _eraser,
                  onAdd: (p) => setState(() => _points.add(p)),
                )
              : _preview
                ? Markdown(
                    data: _content.text,
                    selectable: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
                      code: GoogleFonts.jetBrainsMono(
                        backgroundColor: cs.surfaceContainerHighest,
                        fontSize: 13,
                      ),
                    ),
                    onTapLink: (_, href, __) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri != null && await canLaunchUrl(uri)) launchUrl(uri);
                    },
                  )
                : _Editor(
                    controller: _content,
                    onInsert: _md,
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Editor with custom text-selection menu ───────────────────

class _Editor extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String, [String]) onInsert;
  const _Editor({required this.controller, required this.onInsert});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: null,
      expands: true,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(fontSize: 16, height: 1.7),
      decoration: InputDecoration(
        hintText: 'Начни писать...',
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline.withOpacity(.5)),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      ),
      contextMenuBuilder: (ctx, editableState) {
        final items = editableState.contextMenuButtonItems;
        return AdaptiveTextSelectionToolbar(
          anchors: editableState.contextMenuAnchors,
          children: [
            ...AdaptiveTextSelectionToolbar.getAdaptiveButtons(ctx, items),
            // ─ Markdown actions in "other"
            TextSelectionToolbarTextButton(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: () {
                onInsert('**', '**');
                editableState.hideToolbar();
              },
              child: const Text('Жирный'),
            ),
            TextSelectionToolbarTextButton(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: () {
                onInsert('*', '*');
                editableState.hideToolbar();
              },
              child: const Text('Курсив'),
            ),
            TextSelectionToolbarTextButton(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: () {
                onInsert('~~', '~~');
                editableState.hideToolbar();
              },
              child: const Text('Зачёркнутый'),
            ),
            TextSelectionToolbarTextButton(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: () {
                onInsert('`', '`');
                editableState.hideToolbar();
              },
              child: const Text('Код'),
            ),
            TextSelectionToolbarTextButton(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: () {
                onInsert('[', '](https://)');
                editableState.hideToolbar();
              },
              child: const Text('Ссылка'),
            ),
            TextSelectionToolbarTextButton(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: () {
                onInsert('==', '==');
                editableState.hideToolbar();
              },
              child: const Text('Выделить'),
            ),
          ],
        );
      },
    );
  }
}

// ─── Markdown Toolbar ────────────────────────────────────────

class _MdToolbar extends StatelessWidget {
  final void Function(String, [String]) onInsert;
  const _MdToolbar({required this.onInsert});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // (label, before, after)
    final btns = [
      ('B',   '**',             '**'),
      ('I',   '*',              '*'),
      ('~~',  '~~',             '~~'),
      ('H1',  '# ',             ''),
      ('H2',  '## ',            ''),
      ('H3',  '### ',           ''),
      ('"',   '> ',             ''),
      ('—',   '---\n',          ''),
      ('`',   '`',              '`'),
      ('```', '```\n',          '\n```'),
      ('🔗',  '[',              '](https://)'),
      ('- ',  '\n- ',           ''),
      ('☑',   '\n- [ ] ',       ''),
      ('Таб', '\n| A | B |\n|---|---|\n| 1 | 2 |\n', ''),
    ];

    return Container(
      height: 46,
      color: cs.surfaceContainerHighest.withOpacity(.5),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: btns.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => ActionChip(
          label: Text(btns[i].$1),
          labelStyle: const TextStyle(fontSize: 13),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          onPressed: () => onInsert(btns[i].$2, btns[i].$3),
        ),
      ),
    );
  }
}

// ─── Drawing Canvas ──────────────────────────────────────────

class _Canvas extends StatelessWidget {
  final List<DrawPoint> points;
  final Color color;
  final double width;
  final bool eraser;
  final void Function(DrawPoint) onAdd;
  const _Canvas({
    required this.points,
    required this.color,
    required this.width,
    required this.eraser,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => onAdd(DrawPoint(
        offset: d.localPosition,
        isStart: true,
        color: eraser ? const Color(0x00000000) : color,
        width: eraser ? width * 5 : width,
      )),
      onPanUpdate: (d) => onAdd(DrawPoint(
        offset: d.localPosition,
        isStart: false,
        color: eraser ? const Color(0x00000000) : color,
        width: eraser ? width * 5 : width,
      )),
      child: CustomPaint(
        painter: _Painter(points),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  final List<DrawPoint> pts;
  _Painter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < pts.length - 1; i++) {
      if (pts[i+1].isStart) continue;
      final p = Paint()
        ..strokeWidth = pts[i].width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (pts[i].color.alpha == 0) {
        p.color = Colors.white;
        p.blendMode = BlendMode.clear;
      } else {
        p.color = pts[i].color;
      }
      canvas.drawLine(pts[i].offset, pts[i+1].offset, p);
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}

class _DrawToolbar extends StatelessWidget {
  final Color color;
  final double width;
  final bool isEraser;
  final void Function(Color) onColor;
  final void Function(double) onWidth;
  final VoidCallback onEraser;
  final VoidCallback onClear;
  const _DrawToolbar({
    required this.color, required this.width, required this.isEraser,
    required this.onColor, required this.onWidth,
    required this.onEraser, required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.surfaceContainerHighest.withOpacity(.5),
      child: Row(
        children: [
          // Color dot
          GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Цвет кисти'),
                content: ColorPicker(
                  pickerColor: color,
                  onColorChanged: onColor,
                  enableAlpha: false,
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outline, width: 2),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Thickness
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Толщина: ${width.round()}',
                style: TextStyle(fontSize: 11, color: cs.outline)),
              Slider(
                value: width, min: 1, max: 24,
                divisions: 23,
                onChanged: onWidth,
              ),
            ],
          )),
          // Eraser
          IconButton(
            icon: Icon(isEraser ? Icons.auto_fix_high : Icons.auto_fix_off_outlined),
            color: isEraser ? cs.primary : null,
            onPressed: onEraser,
            tooltip: 'Ластик',
          ),
          // Clear
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: onClear,
            tooltip: 'Очистить',
          ),
        ],
      ),
    );
  }
}
