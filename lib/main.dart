import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QwenApp());
}

// ============================================================
// APP
// ============================================================

class QwenApp extends StatefulWidget {
  const QwenApp({super.key});

  @override
  State<QwenApp> createState() => _QwenAppState();
}

class _QwenAppState extends State<QwenApp> {
  ThemeMode themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    loadTheme();
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();

    final saved = prefs.getString('theme_mode');

    if (!mounted) return;

    setState(() {
      if (saved == 'light') {
        themeMode = ThemeMode.light;
      } else {
        themeMode = ThemeMode.dark;
      }
    });
  }

  Future<void> changeTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'theme_mode',
      mode == ThemeMode.light ? 'light' : 'dark',
    );

    if (!mounted) return;

    setState(() {
      themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Qwen',
      themeMode: themeMode,

      // ========================================================
      // LIGHT THEME
      // ========================================================

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,

        scaffoldBackgroundColor:
            const Color(0xFFFFFDF7),

        colorScheme: ColorScheme.light(
          primary: const Color(0xFFE5B900),
          onPrimary: Colors.black,

          secondary: const Color(0xFFE5B900),
          onSecondary: Colors.black,

          surface: const Color(0xFFFFFDF7),
          onSurface: const Color(0xFF171717),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFDF7),
          foregroundColor: Color(0xFF171717),
          elevation: 0,
        ),

        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFFFFFDF7),
        ),

        inputDecorationTheme:
            InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F3EA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(18),
            ),
            borderSide: BorderSide.none,
          ),
        ),
      ),

      // ========================================================
      // DARK THEME
      // ========================================================

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,

        scaffoldBackgroundColor:
            const Color(0xFF11110F),

        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFF2D35E),
          onPrimary: Colors.black,

          secondary: const Color(0xFFF2D35E),
          onSecondary: Colors.black,

          surface: const Color(0xFF11110F),
          onSurface: const Color(0xFFF2F0E8),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF11110F),
          foregroundColor: Color(0xFFF2F0E8),
          elevation: 0,
        ),

        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF11110F),
        ),

        inputDecorationTheme:
            InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1916),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(18),
            ),
            borderSide: BorderSide.none,
          ),
        ),
      ),

      home: ChatPage(
        onThemeChanged: changeTheme,
        currentTheme: themeMode,
      ),
    );
  }
}

// ============================================================
// CHAT PAGE
// ============================================================

class ChatPage extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final ThemeMode currentTheme;

  const ChatPage({
    super.key,
    required this.onThemeChanged,
    required this.currentTheme,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController controller =
      TextEditingController();

  final TextEditingController apiController =
      TextEditingController();

  Database? db;

  String chatId = '';
  String apiUrl = '';

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> chats = [];

  bool loading = false;
  bool databaseReady = false;

  // ==========================================================
  // COLORS
  // ==========================================================

  Color get accent => Theme.of(context).colorScheme.primary;

  bool get isDark =>
      Theme.of(context).brightness == Brightness.dark;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();
    initializeApp();
  }

  Future<void> initializeApp() async {
    await loadApiUrl();
    await initDatabase();
  }

  // ==========================================================
  // API
  // ==========================================================

  Future<void> loadApiUrl() async {
    final prefs =
        await SharedPreferences.getInstance();

    final saved =
        prefs.getString('api_url') ?? '';

    if (!mounted) return;

    setState(() {
      apiUrl = saved;
      apiController.text = saved;
    });
  }

  Future<void> saveApiUrl() async {
    String url =
        apiController.text.trim();

    while (url.endsWith('/')) {
      url =
          url.substring(0, url.length - 1);
    }

    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      'api_url',
      url,
    );

    if (!mounted) return;

    setState(() {
      apiUrl = url;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'API URL saved',
        ),
      ),
    );
  }

  // ==========================================================
  // DATABASE
  // ==========================================================

  Future<void> initDatabase() async {
    db = await openDatabase(
      p.join(
        await getDatabasesPath(),
        'qwen_chats.db',
      ),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chats (
            id TEXT PRIMARY KEY,
            title TEXT,
            created_at INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id TEXT,
            role TEXT,
            content TEXT
          )
        ''');
      },
    );

    await loadChats();

    if (chats.isEmpty) {
      await createNewChat(
        closeDrawer: false,
      );
    } else {
      chatId =
          chats.first['id'].toString();

      await loadMessages();
    }

    if (!mounted) return;

    setState(() {
      databaseReady = true;
    });
  }

  Future<void> loadChats() async {
    final result = await db!.query(
      'chats',
      orderBy: 'created_at DESC',
    );

    if (!mounted) return;

    setState(() {
      chats =
          List<Map<String, dynamic>>.from(
        result,
      );
    });
  }

  Future<void> loadMessages() async {
    if (chatId.isEmpty) return;

    final result = await db!.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'id ASC',
    );

    if (!mounted) return;

    setState(() {
      messages =
          List<Map<String, dynamic>>.from(
        result,
      );
    });
  }

  Future<void> saveMessage(
    String role,
    String content,
  ) async {
    await db!.insert(
      'messages',
      {
        'chat_id': chatId,
        'role': role,
        'content': content,
      },
    );
  }

  // ==========================================================
  // NEW CHAT
  // ==========================================================

  Future<void> createNewChat({
    bool closeDrawer = true,
  }) async {
    if (db == null) return;

    final newId =
        DateTime.now()
            .microsecondsSinceEpoch
            .toString();

    await db!.insert(
      'chats',
      {
        'id': newId,
        'title': 'New Chat',
        'created_at':
            DateTime.now()
                .millisecondsSinceEpoch,
      },
    );

    if (!mounted) return;

    setState(() {
      chatId = newId;
      messages = [];
    });

    await loadChats();

    if (closeDrawer) {
      Navigator.of(context).maybePop();
    }
  }

  // ==========================================================
  // SWITCH CHAT
  // ==========================================================

  Future<void> switchChat(
    String id,
  ) async {
    if (loading) return;

    setState(() {
      chatId = id;
      messages = [];
    });

    await loadMessages();

    if (!mounted) return;

    Navigator.of(context).maybePop();
  }

  // ==========================================================
  // RENAME CHAT
  // ==========================================================

  Future<void> renameChat(
    Map<String, dynamic> chat,
  ) async {
    final renameController =
        TextEditingController(
      text: chat['title']?.toString() ??
          'New Chat',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Rename chat',
          ),
          content: TextField(
            controller: renameController,
            autofocus: true,
            decoration:
                const InputDecoration(
              hintText: 'Chat name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () async {
                final title =
                    renameController
                        .text
                        .trim();

                if (title.isNotEmpty) {
                  await db!.update(
                    'chats',
                    {
                      'title': title,
                    },
                    where: 'id = ?',
                    whereArgs: [
                      chat['id'],
                    ],
                  );

                  await loadChats();
                }

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text(
                'Save',
              ),
            ),
          ],
        );
      },
    );

    renameController.dispose();
  }

  // ==========================================================
  // DELETE CHAT
  // ==========================================================

  Future<void> deleteChat(
    Map<String, dynamic> chat,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Delete chat?',
          ),
          content: const Text(
            'This conversation will be permanently deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),
              child: const Text(
                'Delete',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final id =
        chat['id'].toString();

    await db!.delete(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [id],
    );

    await db!.delete(
      'chats',
      where: 'id = ?',
      whereArgs: [id],
    );

    await loadChats();

    if (chats.isEmpty) {
      await createNewChat(
        closeDrawer: false,
      );
      return;
    }

    if (id == chatId) {
      chatId =
          chats.first['id'].toString();

      await loadMessages();
    }

    if (!mounted) return;

    setState(() {});
  }

  // ==========================================================
  // UPDATE TITLE FROM FIRST MESSAGE
  // ==========================================================

  Future<void> updateChatTitle(
    String firstMessage,
  ) async {
    if (db == null) return;

    String title =
        firstMessage.trim();

    if (title.length > 32) {
      title =
          '${title.substring(0, 32)}...';
    }

    await db!.update(
      'chats',
      {
        'title': title,
      },
      where: 'id = ?',
      whereArgs: [chatId],
    );

    await loadChats();
  }

  // ==========================================================
  // SEND MESSAGE
  // ==========================================================

  Future<void> sendMessage() async {
    final text =
        controller.text.trim();

    if (text.isEmpty) return;
    if (loading) return;
    if (!databaseReady) return;

    if (apiUrl.isEmpty) {
      openSettings();
      return;
    }

    controller.clear();

    // IMPORTANT:
    // History does NOT contain the new message.
    final historyForServer =
        messages.map((message) {
      return {
        'role': message['role'],
        'content':
            message['content'],
      };
    }).toList();

    final firstMessage =
        messages.isEmpty;

    setState(() {
      loading = true;

      messages.add({
        'role': 'user',
        'content': text,
      });
    });

    await saveMessage(
      'user',
      text,
    );

    if (firstMessage) {
      await updateChatTitle(text);
    }

    try {
      final result = await http
          .post(
            Uri.parse(
              '$apiUrl/chat',
            ),
            headers: {
              'Content-Type':
                  'application/json',
            },
            body: jsonEncode({
              'chat_id': chatId,
              'message': text,
              'history':
                  historyForServer,
            }),
          )
          .timeout(
        const Duration(
          minutes: 5,
        ),
      );

      if (result.statusCode == 200) {
        final data =
            jsonDecode(result.body);

        final answer =
            data['response']
                    ?.toString() ??
                '';

        await saveMessage(
          'assistant',
          answer,
        );

        if (!mounted) return;

        setState(() {
          messages.add({
            'role': 'assistant',
            'content': answer,
          });
        });
      } else {
        if (!mounted) return;

        setState(() {
          messages.add({
            'role': 'assistant',
            'content':
                'Server error: ${result.statusCode}',
          });
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        messages.add({
          'role': 'assistant',
          'content':
              'I couldn\'t connect to Qwen.\n\n'
              'Make sure your Kaggle server is running '
              'and the API URL is still valid.',
        });
      });
    }

    if (!mounted) return;

    setState(() {
      loading = false;
    });
  }

  // ==========================================================
  // SETTINGS
  // ==========================================================

  void openSettings() {
    apiController.text = apiUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Theme.of(context)
              .colorScheme
              .surface,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 22,
            bottom:
                MediaQuery.of(
                      sheetContext,
                    ).viewInsets.bottom +
                    22,
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  QwenLogo(
                    size: 46,
                    color: accent,
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 28,
              ),

              const Text(
                'Connection',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              TextField(
                controller:
                    apiController,
                keyboardType:
                    TextInputType.url,
                decoration:
                    const InputDecoration(
                  hintText:
                      'https://something.trycloudflare.com',
                  prefixIcon:
                      Icon(Icons.link),
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await saveApiUrl();

                    if (sheetContext
                        .mounted) {
                      Navigator.pop(
                        sheetContext,
                      );
                    }
                  },
                  child: const Text(
                    'Save connection',
                  ),
                ),
              ),

              const SizedBox(
                height: 25,
              ),

              const Text(
                'Appearance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              Row(
                children: [
                  Expanded(
                    child:
                        _themeButton(
                      icon:
                          Icons.dark_mode_outlined,
                      label: 'Dark',
                      selected:
                          widget.currentTheme ==
                              ThemeMode.dark,
                      onTap: () =>
                          widget.onThemeChanged(
                        ThemeMode.dark,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child:
                        _themeButton(
                      icon:
                          Icons.light_mode_outlined,
                      label: 'Light',
                      selected:
                          widget.currentTheme ==
                              ThemeMode.light,
                      onTap: () =>
                          widget.onThemeChanged(
                        ThemeMode.light,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 18,
              ),

              Text(
                'Qwen3 30B-A3B',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface
                      .withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),

              const SizedBox(
                height: 5,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _themeButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          vertical: 14,
        ),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(16),
          color: selected
              ? accent.withValues(
                  alpha: 0.16,
                )
              : Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.04),
          border: Border.all(
            color: selected
                ? accent
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(
                      alpha: 0.08,
                    ),
          ),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected
                  ? accent
                  : null,
            ),
            const SizedBox(
              width: 7,
            ),
            Text(
              label,
              style: TextStyle(
                fontWeight:
                    selected
                        ? FontWeight.bold
                        : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // DRAWER
  // ==========================================================

  Widget buildDrawer() {
    final surface =
        Theme.of(context)
            .colorScheme
            .surface;

    return Drawer(
      backgroundColor: surface,
      width: 310,
      child: SafeArea(
        child: Column(
          children: [
            // --------------------------------------------------
            // HEADER
            // --------------------------------------------------

            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                20,
                18,
                14,
                18,
              ),
              child: Row(
                children: [
                  QwenLogo(
                    size: 48,
                    color: accent,
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          'Qwen',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Personal AI',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        Navigator.pop(
                      context,
                    ),
                    icon: const Icon(
                      Icons.close,
                    ),
                  ),
                ],
              ),
            ),

            // --------------------------------------------------
            // NEW CHAT
            // --------------------------------------------------

            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 14,
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      createNewChat,
                  icon: Icon(
                    Icons.add,
                    color: accent,
                  ),
                  label: const Text(
                    'New chat',
                  ),
                  style:
                      OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 14,
                    ),
                    side: BorderSide(
                      color: accent
                          .withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: Align(
                alignment:
                    Alignment.centerLeft,
                child: Text(
                  'RECENT CHATS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        FontWeight.bold,
                    letterSpacing: 1.4,
                    color: Theme.of(
                      context,
                    )
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 7,
            ),

            // --------------------------------------------------
            // CHAT LIST
            // --------------------------------------------------

            Expanded(
              child: chats.isEmpty
                  ? const Center(
                      child: Text(
                        'No conversations',
                      ),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 8,
                      ),
                      itemCount:
                          chats.length,
                      itemBuilder:
                          (context, index) {
                        final chat =
                            chats[index];

                        final id =
                            chat['id']
                                .toString();

                        final selected =
                            id == chatId;

                        return Container(
                          margin:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 2,
                          ),
                          decoration:
                              BoxDecoration(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              13,
                            ),
                            color: selected
                                ? accent
                                    .withValues(
                                    alpha: 0.13,
                                  )
                                : Colors
                                    .transparent,
                          ),
                          child:
                              ListTile(
                            dense: true,
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                13,
                              ),
                            ),
                            leading:
                                Icon(
                              Icons
                                  .chat_bubble_outline,
                              size: 19,
                              color: selected
                                  ? accent
                                  : null,
                            ),
                            title: Text(
                              chat['title']
                                      ?.toString() ??
                                  'New Chat',
                              maxLines: 1,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                              style:
                                  TextStyle(
                                fontWeight:
                                    selected
                                        ? FontWeight
                                            .w600
                                        : FontWeight
                                            .normal,
                              ),
                            ),
                            trailing:
                                PopupMenuButton<
                                    String>(
                              icon:
                                  const Icon(
                                Icons
                                    .more_horiz,
                                size: 19,
                              ),
                              onSelected:
                                  (value) {
                                if (value ==
                                    'rename') {
                                  renameChat(
                                    chat,
                                  );
                                }

                                if (value ==
                                    'delete') {
                                  deleteChat(
                                    chat,
                                  );
                                }
                              },
                              itemBuilder:
                                  (context) =>
                                      const [
                                PopupMenuItem(
                                  value:
                                      'rename',
                                  child:
                                      Text(
                                    'Rename',
                                  ),
                                ),
                                PopupMenuItem(
                                  value:
                                      'delete',
                                  child:
                                      Text(
                                    'Delete',
                                  ),
                                ),
                              ],
                            ),
                            onTap: () =>
                                switchChat(
                              id,
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // --------------------------------------------------
            // SETTINGS
            // --------------------------------------------------

            const Divider(
              height: 1,
            ),

            ListTile(
              leading: const Icon(
                Icons.settings_outlined,
              ),
              title: const Text(
                'Settings',
              ),
              onTap: openSettings,
            ),

            Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 12,
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment
                        .center,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(
                      shape:
                          BoxShape.circle,
                      color: apiUrl.isEmpty
                          ? Colors.grey
                          : accent,
                    ),
                  ),
                  const SizedBox(
                    width: 7,
                  ),
                  Text(
                    apiUrl.isEmpty
                        ? 'Not connected'
                        : 'Connected',
                    style:
                        const TextStyle(
                      fontSize: 11,
                      color:
                          Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // EMPTY CHAT
  // ==========================================================

  Widget buildEmptyState() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            QwenLogo(
              size: 82,
              color: accent,
            ),

            const SizedBox(
              height: 25,
            ),

            const Text(
              'How can I help?',
              style: TextStyle(
                fontSize: 27,
                fontWeight:
                    FontWeight.w700,
              ),
            ),

            const SizedBox(
              height: 9,
            ),

            Text(
              'Ask Qwen anything.',
              style: TextStyle(
                color: Theme.of(
                  context,
                )
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
                fontSize: 15,
              ),
            ),

            const SizedBox(
              height: 22,
            ),

            if (apiUrl.isEmpty)
              OutlinedButton.icon(
                onPressed:
                    openSettings,
                icon: Icon(
                  Icons.link,
                  color: accent,
                ),
                label: const Text(
                  'Connect to Qwen',
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // MESSAGE LIST
  // ==========================================================

  Widget buildMessages() {
    return ListView.builder(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        18,
        16,
        20,
      ),
      itemCount:
          messages.length,
      itemBuilder:
          (context, index) {
        final message =
            messages[index];

        return MessageBubble(
          message:
              message['content']
                  .toString(),
          isUser:
              message['role'] ==
                  'user',
        );
      },
    );
  }

  // ==========================================================
  // INPUT
  // ==========================================================

  Widget buildInput() {
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller:
                    controller,
                enabled:
                    databaseReady &&
                        !loading,
                minLines: 1,
                maxLines: 5,
                textCapitalization:
                    TextCapitalization
                        .sentences,
                onSubmitted:
                    (_) =>
                        sendMessage(),
                decoration:
                    InputDecoration(
                  hintText:
                      'Message Qwen...',
                  suffixIcon:
                      controller.text
                              .isNotEmpty
                          ? null
                          : null,
                ),
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            Material(
              color: accent,
              shape:
                  const CircleBorder(),
              child: InkWell(
                customBorder:
                    const CircleBorder(),
                onTap:
                    loading ||
                            !databaseReady
                        ? null
                        : sendMessage,
                child: const Padding(
                  padding:
                      EdgeInsets.all(13),
                  child: Icon(
                    Icons.arrow_upward,
                    color: Colors.black,
                    size: 21,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: buildDrawer(),

      appBar: AppBar(
        titleSpacing: 16,

        title: Row(
          children: [
            QwenLogo(
              size: 34,
              color: accent,
            ),

            const SizedBox(
              width: 10,
            ),

            Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                const Text(
                  'Qwen',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),

                Text(
                  loading
                      ? 'Thinking...'
                      : 'Ready',
                  style: TextStyle(
                    fontSize: 10,
                    color: loading
                        ? accent
                        : Theme.of(
                            context,
                          )
                            .colorScheme
                            .onSurface
                            .withValues(
                              alpha: 0.45,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed:
                databaseReady
                    ? createNewChat
                    : null,
            icon: const Icon(
              Icons.edit_outlined,
            ),
          ),

          IconButton(
            tooltip: 'Settings',
            onPressed:
                openSettings,
            icon: const Icon(
              Icons.tune,
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          if (apiUrl.isEmpty)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 9,
              ),
              color: accent
                  .withValues(alpha: 0.12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 17,
                    color: accent,
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  const Expanded(
                    child: Text(
                      'Connect your Qwen server to start chatting.',
                      style: TextStyle(
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        openSettings,
                    child: const Text(
                      'Connect',
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: messages.isEmpty
                ? buildEmptyState()
                : buildMessages(),
          ),

          if (loading)
            LinearProgressIndicator(
              minHeight: 2,
              color: accent,
            ),

          buildInput(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    apiController.dispose();
    db?.close();

    super.dispose();
  }
}

// ============================================================
// MESSAGE BUBBLE
// ============================================================

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        Theme.of(context)
            .colorScheme
            .primary;

    final isDark =
        Theme.of(context)
                .brightness ==
            Brightness.dark;

    if (isUser) {
      return Align(
        alignment:
            Alignment.centerRight,
        child: Container(
          constraints:
              const BoxConstraints(
            maxWidth: 330,
          ),
          margin:
              const EdgeInsets.symmetric(
            vertical: 5,
          ),
          padding:
              const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration:
              BoxDecoration(
            color: accent,
            borderRadius:
                BorderRadius.circular(
              19,
            ),
          ),
          child: Text(
            message,
            style:
                const TextStyle(
              color: Colors.black,
              fontSize: 15.5,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment:
          Alignment.centerLeft,
      child: Container(
        constraints:
            const BoxConstraints(
          maxWidth: 350,
        ),
        margin:
            const EdgeInsets.symmetric(
          vertical: 5,
        ),
        padding:
            const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: 8,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            QwenLogo(
              size: 28,
              color: accent,
            ),

            const SizedBox(
              width: 10,
            ),

            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isDark
                      ? const Color(
                          0xFFE8E6DE,
                        )
                      : const Color(
                          0xFF24231F,
                        ),
                  fontSize: 15.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// QWEN LOGO
// ============================================================

class QwenLogo extends StatelessWidget {
  final double size;
  final Color color;

  const QwenLogo({
    super.key,
    this.size = 60,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration:
          BoxDecoration(
        color: color,
        borderRadius:
            BorderRadius.circular(
          size * 0.30,
        ),
      ),
      child: CustomPaint(
        painter: QwenLogoPainter(),
      ),
    );
  }
}

class QwenLogoPainter
    extends CustomPainter {
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = Colors.black
      ..style =
          PaintingStyle.stroke
      ..strokeWidth =
          size.width * 0.075
      ..strokeCap =
          StrokeCap.round;

    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        size.width * 0.27;

    // Outer AI ring
    canvas.drawCircle(
      center,
      radius,
      paint,
    );

    // Three AI connection lines
    final points = [
      Offset(
        center.dx,
        center.dy - radius * 1.75,
      ),
      Offset(
        center.dx -
            radius * 1.52,
        center.dy +
            radius * 0.9,
      ),
      Offset(
        center.dx +
            radius * 1.52,
        center.dy +
            radius * 0.9,
      ),
    ];

    for (final point in points) {
      canvas.drawLine(
        center,
        point,
        paint,
      );
    }

    // Center core
    final core =
        Paint()
          ..color =
              Colors.black
          ..style =
              PaintingStyle.fill;

    canvas.drawCircle(
      center,
      size.width * 0.09,
      core,
    );
  }

  @override
  bool shouldRepaint(
    CustomPainter oldDelegate,
  ) {
    return false;
  }
}