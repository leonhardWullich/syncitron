import 'package:flutter/material.dart';
import 'package:replicore/replicore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/todo.dart';
import '../data/todo_repository.dart';
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
      setState(() => _lastMetrics = metrics);

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
          ValueListenableBuilder<ReplicoreException?>(
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
      builder: (_) => AlertDialog(
        title: const Text('Sync Metrics'),
        content: SingleChildScrollView(
          child: _lastMetrics == null
              ? const Text('No sync has been performed yet.')
              : Text(_lastMetrics.toString()),
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Close'),
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
