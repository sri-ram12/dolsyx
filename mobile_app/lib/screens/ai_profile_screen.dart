import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AiProfileScreen extends StatefulWidget {
  const AiProfileScreen({super.key});

  @override
  State<AiProfileScreen> createState() => _AiProfileScreenState();
}

class _AiProfileScreenState extends State<AiProfileScreen> {
  String _selectedModel = 'Groq Llama 3.3 70B (Fast)';
  bool _memoryEnabled = true;
  final List<String> _memories = [
    'User prefers concise, code-first answers.',
    'User primary language preference: English.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'AI Assistant Profile',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)],
                ),
              ),
              child: CircleAvatar(
                radius: 42,
                backgroundColor: AppTheme.surfaceColor,
                child: const Icon(Icons.auto_awesome, color: Color(0xFFEC4899), size: 46),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI Assistant',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.verified, color: Color(0xFF3B82F6), size: 20),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Your intelligent assistant for questions, ideas, writing, coding and image creation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),

            // Model Selection Section
            _buildSectionHeader('AI MODEL ENGINE'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  RadioListTile<String>(
                    activeColor: AppTheme.primaryColor,
                    title: Text('Groq Llama 3.3 70B', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Ultra-fast open-weights intelligence', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    value: 'Groq Llama 3.3 70B (Fast)',
                    groupValue: _selectedModel,
                    onChanged: (val) => setState(() => _selectedModel = val!),
                  ),
                  Divider(height: 1, color: Colors.white10),
                  RadioListTile<String>(
                    activeColor: AppTheme.primaryColor,
                    title: Text('Google Gemini 1.5 Pro', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Multimodal reasoning & large context', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    value: 'Google Gemini 1.5 Pro',
                    groupValue: _selectedModel,
                    onChanged: (val) => setState(() => _selectedModel = val!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Long-Term Memory Section
            _buildSectionHeader('LONG-TERM MEMORY'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  SwitchListTile(
                    activeColor: AppTheme.primaryColor,
                    title: Text('Enable AI Memory', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Allows AI to remember your preferences across chats', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    value: _memoryEnabled,
                    onChanged: (val) => setState(() => _memoryEnabled = val),
                  ),
                  if (_memoryEnabled && _memories.isNotEmpty) ...[
                    Divider(height: 1, color: Colors.white10),
                    ..._memories.map((mem) => ListTile(
                          leading: const Icon(Icons.psychology, color: Color(0xFF8B5CF6), size: 20),
                          title: Text(mem, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                            onPressed: () {
                              setState(() => _memories.remove(mem));
                            },
                          ),
                        )),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Usage Overview
            _buildSectionHeader('USAGE & METRICS'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricItem('14.2k', 'Tokens Used'),
                  _buildMetricItem('12', 'Images Created'),
                  _buildMetricItem('\$0.04', 'Estimated Cost'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Clear AI History Action
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.15),
                foregroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('Clear AI History & Memory', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                setState(() => _memories.clear());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('AI History & Memory cleared cleanly!')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
      ),
    );
  }

  Widget _buildMetricItem(String val, String label) {
    return Column(
      children: [
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }
}
