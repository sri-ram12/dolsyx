import 'package:flutter/material.dart';
import '../services/productivity_service.dart';
import '../theme/app_theme.dart';

class ProductivityScreen extends StatefulWidget {
  const ProductivityScreen({super.key});

  @override
  State<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends State<ProductivityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ProductivityService _productivityService = ProductivityService();

  List<dynamic> _notes = [];
  List<dynamic> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final notes = await _productivityService.getNotes();
    final tasks = await _productivityService.getTasks();
    if (mounted) {
      setState(() {
        _notes = notes;
        _tasks = tasks;
        _isLoading = false;
      });
    }
  }

  Future<void> _addNote() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Add Note', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: 'Content'), maxLines: 3),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (titleCtrl.text.isNotEmpty) {
                Navigator.pop(context);
                await _productivityService.createNote(titleCtrl.text, contentCtrl.text, '#4A90E2');
                _fetchData();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addTask() async {
    final titleCtrl = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Add List', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Task title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (titleCtrl.text.isNotEmpty) {
                Navigator.pop(context);
                await _productivityService.createTask(titleCtrl.text, '', null);
                _fetchData();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
        backgroundColor: AppTheme.surfaceColor,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Notes'),
            Tab(text: 'Tasks'),
          ],
        ),
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildNotesTab(),
                _buildTasksTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          if (_tabController.index == 0) {
            _addNote();
          } else {
            _addTask();
          }
        },
      ),
    );
  }

  Widget _buildNotesTab() {
    if (_notes.isEmpty) return Center(child: Text('No notes yet.', style: TextStyle(color: AppTheme.textSecondary)));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        return Card(
          color: AppTheme.surfaceColor,
          child: ListTile(
            title: Text(note['title'] ?? '', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text(note['content'] ?? '', style: TextStyle(color: AppTheme.textSecondary)),
          ),
        );
      },
    );
  }

  Widget _buildTasksTab() {
    if (_tasks.isEmpty) return Center(child: Text('No tasks yet.', style: TextStyle(color: AppTheme.textSecondary)));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        final isCompleted = task['status'] == 'done';
        return Card(
          color: AppTheme.surfaceColor,
          child: ListTile(
            leading: Checkbox(
              value: isCompleted,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) async {
                setState(() => task['status'] = val! ? 'done' : 'todo');
                await _productivityService.updateTaskStatus(task['_id'], val! ? 'done' : 'todo');
              },
            ),
            title: Text(
              task['title'] ?? '',
              style: TextStyle(
                color: AppTheme.textPrimary,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
