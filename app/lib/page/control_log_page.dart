import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:navbot_d1_flutter/provider/control_log_store.dart';

class ControlLogPage extends StatefulWidget {
  const ControlLogPage({super.key});

  @override
  State<ControlLogPage> createState() => _ControlLogPageState();
}

class _ControlLogPageState extends State<ControlLogPage> {
  final ScrollController _scrollController = ScrollController();
  bool _followLatest = true;

  bool get _isChinese =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

  String _text(String zh, String en) => _isChinese ? zh : en;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(
      ClipboardData(text: ControlLogStore.instance.exportText()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_text('日志已复制', 'Logs copied'))));
  }

  Color _levelColor(ControlLogLevel level, ColorScheme colors) {
    return switch (level) {
      ControlLogLevel.debug => colors.onSurfaceVariant,
      ControlLogLevel.info => colors.primary,
      ControlLogLevel.warning => Colors.orange.shade800,
      ControlLogLevel.error => colors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = ControlLogStore.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_text('控制日志', 'Control logs')),
        actions: [
          IconButton(
            tooltip: _text('复制全部', 'Copy all'),
            onPressed: _copyLogs,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: _text('清空', 'Clear'),
            onPressed: store.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: store.revision,
        builder: (context, _, __) {
          final entries = store.entries;
          if (_followLatest) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scrollToLatest();
            });
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: theme.colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Text(
                      '${_text('日志', 'Entries')}: ${entries.length}',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(width: 20),
                    Text(
                      '${_text('速度包', 'Speed packets')}: '
                      '${store.speedPacketCount}',
                      style: theme.textTheme.labelLarge,
                    ),
                    const Spacer(),
                    Text(_text('跟随最新', 'Follow latest')),
                    Switch(
                      value: _followLatest,
                      onChanged: (value) {
                        setState(() => _followLatest = value);
                        if (value) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _scrollToLatest(),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child:
                    entries.isEmpty
                        ? Center(child: Text(_text('暂无日志', 'No logs yet')))
                        : SelectionArea(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  entry.format(),
                                  style: TextStyle(
                                    color: _levelColor(
                                      entry.level,
                                      theme.colorScheme,
                                    ),
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    height: 1.25,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
              ),
            ],
          );
        },
      ),
    );
  }
}
