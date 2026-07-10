import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// v0.0.37: Real Chat + Rollout page — доступна ТОЛЬКО в admin-flavor сборке.
/// Compile-time gated через kSuperAdminBuild (см. core/superadmin.dart).
/// Physically absent в prod-сборке (тот же файл, но dart tree-shaking
/// удалит route если kSuperAdminBuild=false).
///
/// Endpoints:
/// - GET /api/admin/chat/messages?after_id=N (poll каждые 5 сек)
/// - POST /api/admin/chat/send (superadmin sending)
/// - POST /api/admin/rollout/apply (Apply to users button)
class DeveloperChatPage extends HookWidget {
  const DeveloperChatPage({super.key});

  static const _baseUrl = 'https://pixellnet.com';
  static const _pollInterval = Duration(seconds: 5);
  static const _tokenKey = 'pixellnet.admin.token';

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> _setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<List<Map<String, dynamic>>> _fetchMessages(int afterId) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return [];
    final response = await http.get(
      Uri.parse('$_baseUrl/api/admin/chat/messages?after_id=$afterId'),
      headers: {'X-Admin-Token': token},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['messages'] as List).cast<Map<String, dynamic>>();
  }

  Future<bool> _sendMessage(String content) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return false;
    final response = await http.post(
      Uri.parse('$_baseUrl/api/admin/chat/send'),
      headers: {
        'X-Admin-Token': token,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'content': content}),
    ).timeout(const Duration(seconds: 10));
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>?> _rolloutApply(
    String version,
    String changelog,
    String channel,
  ) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return null;
    final response = await http.post(
      Uri.parse('$_baseUrl/api/admin/rollout/apply'),
      headers: {
        'X-Admin-Token': token,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'channel': channel,
        'version': version,
        'changelog': changelog,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final messages = useState<List<Map<String, dynamic>>>([]);
    final lastId = useState<int>(0);
    final controller = useTextEditingController();
    final scrollController = useScrollController();
    final isSending = useState(false);
    final tokenSet = useState<bool>(false);

    // Check token on mount
    useEffect(() {
      _getToken().then((t) {
        tokenSet.value = t != null && t.isNotEmpty;
      });
      return null;
    }, const []);

    // Polling
    useEffect(() {
      if (!tokenSet.value) return null;
      final timer = Timer.periodic(_pollInterval, (_) async {
        try {
          final newMsgs = await _fetchMessages(lastId.value);
          if (newMsgs.isNotEmpty) {
            messages.value = [...messages.value, ...newMsgs];
            lastId.value = newMsgs.last['id'] as int;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollController.hasClients) {
                scrollController.animateTo(
                  scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        } catch (_) {}
      });
      return timer.cancel;
    }, [tokenSet.value]);

    Future<void> sendMessage() async {
      final text = controller.text.trim();
      if (text.isEmpty) return;
      isSending.value = true;
      try {
        final ok = await _sendMessage(text);
        if (ok) {
          controller.clear();
          // Force poll
          final newMsgs = await _fetchMessages(lastId.value);
          if (newMsgs.isNotEmpty) {
            messages.value = [...messages.value, ...newMsgs];
            lastId.value = newMsgs.last['id'] as int;
          }
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось отправить (проверь token)')),
          );
        }
      } finally {
        isSending.value = false;
      }
    }

    Future<void> promptSetToken() async {
      final tokenController = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Admin token'),
          content: TextField(
            controller: tokenController,
            decoration: const InputDecoration(hintText: '64 hex chars'),
            obscureText: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, tokenController.text.trim()),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
      if (result != null && result.isNotEmpty) {
        await _setToken(result);
        tokenSet.value = true;
      }
    }

    Future<void> applyRollout() async {
      final versionCtrl = TextEditingController();
      final changelogCtrl = TextEditingController();
      String channel = 'stable';
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (_, setState) => AlertDialog(
            title: const Text('Apply to users'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: versionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Version (e.g. 0.0.38)',
                  ),
                ),
                const Gap(8),
                TextField(
                  controller: changelogCtrl,
                  decoration: const InputDecoration(labelText: 'Changelog'),
                  maxLines: 3,
                ),
                const Gap(8),
                DropdownButton<String>(
                  value: channel,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'stable', child: Text('stable (все юзеры)')),
                    DropdownMenuItem(value: 'beta', child: Text('beta')),
                    DropdownMenuItem(value: 'dev', child: Text('dev')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => channel = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
      final res = await _rolloutApply(
        versionCtrl.text.trim(),
        changelogCtrl.text.trim(),
        channel,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res != null
                ? 'v${res['version']} promoted to ${res['channel']}'
                : 'Rollout failed'),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Claude'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rocket_launch_rounded),
            tooltip: 'Apply to users',
            onPressed: tokenSet.value ? applyRollout : null,
          ),
          IconButton(
            icon: const Icon(Icons.key_rounded),
            tooltip: 'Set admin token',
            onPressed: promptSetToken,
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'ADMIN',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ],
      ),
      body: !tokenSet.value
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 64),
                  const Gap(16),
                  const Text('Установи admin token для доступа к чату'),
                  const Gap(16),
                  FilledButton(
                    onPressed: promptSetToken,
                    child: const Text('Ввести token'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: messages.value.length,
                    itemBuilder: (context, index) {
                      final msg = messages.value[index];
                      return _MessageBubble(
                        content: msg['content'] as String,
                        isIncoming: msg['role'] == 'claude',
                        createdAt: DateTime.parse(msg['created_at'] as String),
                      );
                    },
                  ),
                ),
                if (isSending.value)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: LinearProgressIndicator(),
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => sendMessage(),
                            decoration: InputDecoration(
                              hintText: 'Сообщение Claude...',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const Gap(8),
                        FilledButton.icon(
                          onPressed: isSending.value ? null : sendMessage,
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Send'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.content,
    required this.isIncoming,
    required this.createdAt,
  });

  final String content;
  final bool isIncoming;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isIncoming ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isIncoming
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.primaryContainer,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isIncoming ? 4 : 16),
                bottomRight: Radius.circular(isIncoming ? 16 : 4),
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isIncoming ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Text(
                  content,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Gap(2),
                Text(
                  '${createdAt.hour.toString().padLeft(2, '0')}:'
                  '${createdAt.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
