import 'package:flutter/material.dart';
import 'package:syncitron/syncitron.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/todo.dart';
import '../data/todo_repository.dart';
import '../main.dart'; // for appRealtimeManager
import '../sync/sync_service.dart';

class TodoListScreen extends StatefulWidget {
  final Database db;
  final SyncEngine engine;
  final Logger logger;
  final MetricsCollector metricsCollector;

  const TodoListScreen({
    super.key,
    required this.db,
    required this.engine,
    required this.logger,
    required this.metricsCollector,
  });

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  late final TodoRepository _repo;
  final _titleController = TextEditingController();

  List<Todo> _todos = [];
  bool _loading = true;
  SyncSessionMetrics? _lastMetrics;
  final List<_SyncHistoryEntry> _syncHistory = [];
  bool _syncing = false;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    widget.logger.info('TodoListScreen initialized for user $_userId');
    _repo = TodoRepository(widget.db);
    _loadTodos();
    SyncService.instance.syncStatus.addListener(_onSyncStatusChanged);
  }

  @override
  void dispose() {
    SyncService.instance.syncStatus.removeListener(_onSyncStatusChanged);
    _titleController.dispose();
    super.dispose();
  }

  void _onSyncStatusChanged() {
    if (SyncService.instance.syncStatus.value ==
        'Sync completed successfully.') {
      _loadTodos();
    }
  }

  Future<void> _loadTodos() async {
    try {
      final todos = await _repo.fetchAll(_userId);
      if (mounted) {
        setState(() {
          _todos = todos;
          _loading = false;
        });
      }
      widget.logger.debug('Loaded ${todos.length} todos');
    } catch (e) {
      widget.logger.error('Failed to load todos', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading todos: $e')),
        );
      }
    }
  }

  Future<void> _addTodo(String title) async {
    try {
      await _repo.insert(Todo.create(userId: _userId, title: title.trim()));
      widget.logger.info('Todo created', context: {'title': title});
      await _loadTodos();
    } catch (e) {
      widget.logger.error('Failed to create todo', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating todo: $e')),
        );
      }
    }
  }

  Future<void> _toggleDone(Todo todo) async {
    try {
      await _repo.update(todo.copyWith(isDone: !todo.isDone));
      widget.logger.debug('Todo toggled', context: {
        'id': todo.id,
        'is_done': !todo.isDone,
      });
      await _loadTodos();
    } catch (e) {
      widget.logger.error('Failed to toggle todo', error: e);
    }
  }

  Future<void> _deleteTodo(Todo todo) async {
    try {
      await _repo.softDelete(todo);
      widget.logger.info('Todo deleted', context: {'id': todo.id});
      await _loadTodos();
    } catch (e) {
      widget.logger.error('Failed to delete todo', error: e);
    }
  }

  Future<void> _onRefresh() async {
    if (_syncing) return;

    setState(() => _syncing = true);
    try {
      widget.logger.info('Manual sync started');
      final metrics = await widget.engine.syncAll();
      setState(() {
        _lastMetrics = metrics;
        _syncHistory.insert(
            0,
            _SyncHistoryEntry(
              timestamp: DateTime.now(),
              metrics: metrics,
            ));
        // Keep only last 50 syncs
        if (_syncHistory.length > 50) {
          _syncHistory.removeLast();
        }
      });

      widget.logger.info('Manual sync completed', context: {
        'success': metrics.overallSuccess,
        'duration_ms': metrics.totalDuration.inMilliseconds,
        'pulled': metrics.totalRecordsPulled,
        'pushed': metrics.totalRecordsPushed,
      });

      await _loadTodos();

      if (mounted && !metrics.overallSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync completed with ${metrics.totalErrors} errors',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } on SyncNetworkException catch (e) {
      widget.logger.warning('Network error during sync', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                e.isOffline ? 'You appear to be offline' : 'Network error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on SyncAuthException catch (e) {
      widget.logger.error('Auth error during sync', error: e);
      // Navigate to login
      if (mounted) {
        await Supabase.instance.client.auth.signOut();
        if (mounted) Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (e) {
      widget.logger.error('Sync failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Todos'),
        elevation: 0,
        actions: [
          // Real-Time connection indicator
          if (appRealtimeManager != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Tooltip(
                  message: appRealtimeManager!.isConnected
                      ? 'Real-time sync active'
                      : 'Real-time disconnected',
                  child: Icon(
                    Icons.wifi,
                    size: 18,
                    color: appRealtimeManager!.isConnected
                        ? Colors.lightGreenAccent
                        : Colors.white38,
                  ),
                ),
              ),
            ),
          // Sync button with metrics display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : GestureDetector(
                      onTap: _onRefresh,
                      child: Tooltip(
                        message: _lastMetrics != null
                            ? 'Last sync: ${_lastMetrics!.totalRecordsPulled} pulled, ${_lastMetrics!.totalRecordsPushed} pushed'
                            : 'Tap to sync',
                        child: Icon(
                          Icons.sync,
                          color: _lastMetrics?.overallSuccess ?? true
                              ? Colors.white
                              : Colors.orange,
                        ),
                      ),
                    ),
            ),
          ),
          // Menu button
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('View Sync Metrics'),
                onTap: () => _showMetricsDialog(),
              ),
              PopupMenuItem(
                child: const Text('Sign Out'),
                onTap: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (mounted) Navigator.of(context).pushReplacementNamed('/');
                },
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Sync status/error banner ───────────────────────────────────────
          ValueListenableBuilder<syncitronException?>(
            valueListenable: SyncService.instance.syncError,
            builder: (_, error, __) {
              if (error == null) return const SizedBox.shrink();

              final (icon, message) = switch (error) {
                SyncNetworkException e when e.isOffline => (
                    Icons.wifi_off,
                    'You\'re offline. Changes saved locally.'
                  ),
                SyncNetworkException() => (
                    Icons.cloud_off,
                    'Server unreachable. Retrying soon.'
                  ),
                SyncAuthException() => (
                    Icons.lock_outline,
                    'Session expired. Please log in again.'
                  ),
                _ => (Icons.sync_problem, 'Sync error: ${error.message}'),
              };

              return MaterialBanner(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                leading: Icon(icon),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: _onRefresh,
                    child: const Text('Retry'),
                  ),
                ],
              );
            },
          ),

          // ── Last sync metrics display ──────────────────────────────────────
          if (_lastMetrics != null)
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _lastMetrics!.overallSuccess
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _lastMetrics!.overallSuccess
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        '${_lastMetrics!.totalRecordsPulled}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('Pulled', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        '${_lastMetrics!.totalRecordsPushed}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('Pushed', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        '${_lastMetrics!.totalDuration.inMilliseconds}ms',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('Duration', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

          // ── Todo list ──────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: _todos.isEmpty
                        ? const Center(
                            child: Text('No todos yet. Add one below!'),
                          )
                        : ListView.builder(
                            itemCount: _todos.length,
                            itemBuilder: (_, i) => _TodoTile(
                              todo: _todos[i],
                              onToggle: () => _toggleDone(_todos[i]),
                              onDelete: () => _deleteTodo(_todos[i]),
                            ),
                          ),
                  ),
          ),

          // ── Add input ──────────────────────────────────────────────────────
          _AddTodoBar(
            controller: _titleController,
            onAdd: (title) {
              _addTodo(title);
              _titleController.clear();
            },
          ),
        ],
      ),
    );
  }

  void _showMetricsDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sync History',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                      ),
                    ),
                    Text(
                      '${_syncHistory.length} syncs',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _syncHistory.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sync_disabled,
                                  size: 48, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No sync performed yet',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _syncHistory.length,
                        itemBuilder: (context, index) {
                          final entry = _syncHistory[index];
                          return _SyncHistoryTile(
                            entry: entry,
                            isFirst: index == 0,
                          );
                        },
                      ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_syncHistory.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _syncHistory.clear());
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear History'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: Navigator.of(context).pop,
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sync History Models & Widgets ────────────────────────────────────────────

class _SyncHistoryEntry {
  final DateTime timestamp;
  final SyncSessionMetrics metrics;

  _SyncHistoryEntry({required this.timestamp, required this.metrics});
}

class _SyncHistoryTile extends StatefulWidget {
  final _SyncHistoryEntry entry;
  final bool isFirst;

  const _SyncHistoryTile({required this.entry, required this.isFirst});

  @override
  State<_SyncHistoryTile> createState() => _SyncHistoryTileState();
}

class _SyncHistoryTileState extends State<_SyncHistoryTile> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isFirst; // Auto-expand first item
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.day}.${dt.month}.${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.entry.metrics;
    final isSuccess = m.overallSuccess;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      elevation: _expanded ? 2 : 0,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Status icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSuccess
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSuccess ? Icons.check_circle : Icons.warning,
                      color: isSuccess ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Timestamp & summary
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatTimestamp(widget.entry.timestamp),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '↓ ${m.totalRecordsPulled}  ↑ ${m.totalRecordsPushed}  · ${_formatDuration(m.totalDuration)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                        ),
                      ],
                    ),
                  ),
                  // Expand icon
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          // Expanded details
          if (_expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  // Metrics grid
                  _MetricRow(
                    label: 'Duration',
                    value: _formatDuration(m.totalDuration),
                    icon: Icons.timer_outlined,
                  ),
                  _MetricRow(
                    label: 'Records Pulled',
                    value: '${m.totalRecordsPulled}',
                    icon: Icons.download_outlined,
                  ),
                  _MetricRow(
                    label: 'Records Pushed',
                    value: '${m.totalRecordsPushed}',
                    icon: Icons.upload_outlined,
                  ),
                  _MetricRow(
                    label: 'Conflicts',
                    value: '${m.totalConflicts}',
                    icon: Icons.merge_outlined,
                  ),
                  if (m.totalErrors > 0)
                    _MetricRow(
                      label: 'Errors',
                      value: '${m.totalErrors}',
                      icon: Icons.error_outline,
                      valueColor: Colors.red,
                    ),
                  const SizedBox(height: 8),
                  // Table-specific breakdown
                  if (m.tableMetrics.isNotEmpty) ...[
                    Text(
                      'Per-Table Breakdown',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...m.tableMetrics.map((tm) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_outlined,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tm.tableName,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Text(
                              '↓${tm.recordsPulled} ↑${tm.recordsPushed}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _MetricRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
          ),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TodoTile({
    required this.todo,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(value: todo.isDone, onChanged: (_) => onToggle()),
      title: Text(
        todo.title,
        style: todo.isDone
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (todo.isSynced == 0)
            Tooltip(
              message: 'Not yet synced',
              child: Icon(
                Icons.circle,
                size: 8,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _AddTodoBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onAdd;

  const _AddTodoBar({required this.controller, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Add a todo…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) onAdd(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) onAdd(controller.text);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
