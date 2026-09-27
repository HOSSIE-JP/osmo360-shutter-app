import 'package:flutter/material.dart';

typedef ProjectDraft = ({String name, String description});

/// Own input controllers for the entire dialog route, including its exit animation.
class ProjectEditorDialog extends StatefulWidget {
  const ProjectEditorDialog({super.key, this.initial, this.edit = false});
  final ProjectDraft? initial;
  final bool edit;
  @override
  State<ProjectEditorDialog> createState() => _ProjectEditorDialogState();
}

class _ProjectEditorDialogState extends State<ProjectEditorDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initial?.name ?? '');
  late final description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  void save() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, (
        name: name.text.trim(),
        description: description.text.trim(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.edit ? 'プロジェクトを編集' : '新規プロジェクト'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              maxLength: 80,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'プロジェクト名'),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'プロジェクト名を入力してください' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '説明・メモ'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(onPressed: save, child: const Text('保存')),
    ],
  );
}

class MapKeyDialog extends StatefulWidget {
  const MapKeyDialog({super.key, required this.initialKey});
  final String initialKey;
  @override
  State<MapKeyDialog> createState() => _MapKeyDialogState();
}

class _MapKeyDialogState extends State<MapKeyDialog> {
  late final input = TextEditingController(text: widget.initialKey);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Google Maps APIキー'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: TextField(
        controller: input,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'Maps JavaScript API key',
          helperText: '空欄で保存すると地図を無効化します',
          helperMaxLines: 2,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
}
