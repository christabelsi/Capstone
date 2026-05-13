import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../deliverable_status_labels.dart';
import '../widgets/more_options_menu.dart';

class GrantDetailScreen extends StatefulWidget {
  const GrantDetailScreen({
    super.key,
    required this.grant,
    required this.organizationId,
    required this.isAdmin,
  });

  final Map<String, dynamic> grant;
  final String organizationId;
  final bool isAdmin;

  @override
  State<GrantDetailScreen> createState() => _GrantDetailScreenState();
}

class _GrantDetailScreenState extends State<GrantDetailScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _deliverables = [];
  bool _loading = true;
  String? _error;
  int _fileListEpoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _grantApproved {
    final s = widget.grant['proposal_status'] as String?;
    return s == null || s == 'approved';
  }

  String get _grantProposalStatus =>
      widget.grant['proposal_status'] as String? ?? 'approved';

  Future<void> _setGrantProposalStatus(String proposalStatus) async {
    try {
      await _supabase
          .from('grants')
          .update({'proposal_status': proposalStatus})
          .eq('id', widget.grant['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            proposalStatus == 'approved' ? 'Grant approved.' : 'Grant proposal rejected.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update grant: $e')),
        );
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('deliverables')
          .select()
          .eq('grant_id', widget.grant['id'])
          .order('due_date');
      setState(() {
        _deliverables = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addDeliverable() async {
    final titleCtrl = TextEditingController();
    var due = DateTime.now().add(const Duration(days: 14));
    const status = 'in_progress';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('New deliverable'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(due.toLocal().toString().split(' ').first),
                subtitle: const Text('Due date'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: due,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setModalState(() => due = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (ok != true || titleCtrl.text.trim().isEmpty) return;

    final user = _supabase.auth.currentUser;
    try {
      final row = <String, dynamic>{
        'grant_id': widget.grant['id'],
        'title': titleCtrl.text.trim(),
        'due_date': due.toIso8601String().split('T').first,
        'status': status,
      };
      if (widget.isAdmin) {
        row['proposal_status'] = 'approved';
      } else {
        row['proposal_status'] = 'pending';
        row['proposed_by'] = user?.id;
      }
      await _supabase.from('deliverables').insert(row);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create deliverable: $e')),
        );
      }
    }
  }

  Future<void> _setDeliverableStatus(String id, String status) async {
    try {
      await _supabase.from('deliverables').update({'status': status}).eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }

  Future<void> _setDeliverableProposalStatus(String id, String proposalStatus) async {
    try {
      await _supabase.from('deliverables').update({'proposal_status': proposalStatus}).eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update proposal: $e')),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _filesFor(String deliverableId) async {
    final rows = await _supabase
        .from('deliverable_files')
        .select()
        .eq('deliverable_id', deliverableId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _uploadFile(String deliverableId) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    final bytes = f.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file bytes (try a smaller file).')),
        );
      }
      return;
    }

    final safeName = f.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path =
        '${widget.organizationId}/$deliverableId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    try {
      await _supabase.storage.from(SupabaseConfig.grantFilesBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final user = _supabase.auth.currentUser;
      await _supabase.from('deliverable_files').insert({
        'deliverable_id': deliverableId,
        'uploaded_by': user?.id,
        'storage_path': path,
        'file_name': f.name,
        'mime_type': f.extension != null ? 'application/octet-stream' : null,
        'file_size': bytes.length,
      });

      if (mounted) {
        setState(() => _fileListEpoch++);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File uploaded.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Future<void> _openFile(Map<String, dynamic> row) async {
    final path = row['storage_path'] as String?;
    if (path == null) return;
    try {
      final url = await _supabase.storage
          .from(SupabaseConfig.grantFilesBucket)
          .createSignedUrl(path, 3600);
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open browser. URL: $url')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get link: $e')),
        );
      }
    }
  }

  bool _canDeleteFile(Map<String, dynamic> row) {
    if (widget.isAdmin) return true;
    final uid = _supabase.auth.currentUser?.id;
    return uid != null && row['uploaded_by'] == uid;
  }

  bool _canEditDeliverable(Map<String, dynamic> d) {
    if (widget.isAdmin) return true;
    final dps = d['proposal_status'] as String? ?? 'approved';
    final uid = _supabase.auth.currentUser?.id;
    return dps == 'pending' && d['proposed_by'] == uid;
  }

  void _onDeliverableMenu(String action, String deliverableId, Map<String, dynamic> d) {
    if (action == 'approve_proposal') {
      _setDeliverableProposalStatus(deliverableId, 'approved');
    } else if (action == 'reject_proposal') {
      _setDeliverableProposalStatus(deliverableId, 'rejected');
    } else if (action == 'edit') {
      _editDeliverable(d);
    } else if (action == 'upload') {
      _uploadFile(deliverableId);
    } else if (action == 'delete') {
      _deleteDeliverable(d);
    }
  }

  List<PopupMenuEntry<String>> _deliverableMenuEntries(
    BuildContext context,
    Map<String, dynamic> d,
  ) {
    final dps = d['proposal_status'] as String? ?? 'approved';
    final items = <PopupMenuEntry<String>>[];
    if (widget.isAdmin && dps == 'pending') {
      items.add(
        moreMenuItem(
          context,
          value: 'approve_proposal',
          label: 'Approve proposal',
          icon: Icons.check_circle_outline,
        ),
      );
      items.add(
        moreMenuItem(
          context,
          value: 'reject_proposal',
          label: 'Reject proposal',
          icon: Icons.cancel_outlined,
        ),
      );
    }
    if (_canEditDeliverable(d)) {
      items.add(moreMenuItem(context, value: 'edit', label: 'Edit', icon: Icons.edit_outlined));
    }
    items.add(moreMenuItem(context, value: 'upload', label: 'Upload file', icon: Icons.upload_file));
    if (widget.isAdmin) {
      items.add(
        moreMenuItem(
          context,
          value: 'delete',
          label: 'Delete deliverable',
          icon: Icons.delete_outline,
          destructive: true,
        ),
      );
    }
    return items;
  }

  Future<void> _deleteDeliverableFile(Map<String, dynamic> row) async {
    if (!_canDeleteFile(row)) return;
    final id = row['id'] as String?;
    final path = row['storage_path'] as String?;
    if (id == null || path == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this upload?'),
        content: Text(
          'Remove "${row['file_name'] ?? 'file'}" from this deliverable. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.storage.from(SupabaseConfig.grantFilesBucket).remove([path]);
      await _supabase.from('deliverable_files').delete().eq('id', id);
      if (mounted) {
        setState(() => _fileListEpoch++);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _editGrant() async {
    if (!widget.isAdmin) return;
    final id = widget.grant['id'] as String?;
    if (id == null) return;

    final titleCtrl = TextEditingController(text: widget.grant['title'] as String? ?? '');
    try {
      var start = DateTime.tryParse(
            '${widget.grant['start_date'] ?? '1970-01-01'}T00:00:00',
          ) ??
          DateTime.now();
      var end = DateTime.tryParse('${widget.grant['end_date'] ?? '1970-01-01'}T00:00:00') ?? DateTime.now();

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: const Text('Edit grant'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(start.toLocal().toString().split(' ').first),
                    subtitle: const Text('Start date'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: ctx,
                        initialDate: start,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (p != null) setModalState(() => start = p);
                    },
                  ),
                  ListTile(
                    title: Text(end.toLocal().toString().split(' ').first),
                    subtitle: const Text('End date'),
                    trailing: const Icon(Icons.event),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: ctx,
                        initialDate: end,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (p != null) setModalState(() => end = p);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          ),
        ),
      );

      if (ok != true || titleCtrl.text.trim().isEmpty) return;
      await _supabase.from('grants').update({
        'title': titleCtrl.text.trim(),
        'start_date': start.toIso8601String().split('T').first,
        'end_date': end.toIso8601String().split('T').first,
      }).eq('id', id);
      if (!mounted) return;
      widget.grant['title'] = titleCtrl.text.trim();
      widget.grant['start_date'] = start.toIso8601String().split('T').first;
      widget.grant['end_date'] = end.toIso8601String().split('T').first;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grant updated.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update grant: $e')),
        );
      }
    } finally {
      titleCtrl.dispose();
    }
  }

  Future<void> _editDeliverable(Map<String, dynamic> d) async {
    final id = d['id'] as String?;
    if (id == null) return;

    final titleCtrl = TextEditingController(text: d['title'] as String? ?? '');
    try {
      var due = DateTime.tryParse('${d['due_date'] ?? '1970-01-01'}T00:00:00') ?? DateTime.now();

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: const Text('Edit deliverable'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text(due.toLocal().toString().split(' ').first),
                  subtitle: const Text('Due date'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: due,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) setModalState(() => due = p);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          ),
        ),
      );

      if (ok != true || titleCtrl.text.trim().isEmpty) return;
      await _supabase.from('deliverables').update({
        'title': titleCtrl.text.trim(),
        'due_date': due.toIso8601String().split('T').first,
      }).eq('id', id);
      if (mounted) await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deliverable updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update deliverable: $e')),
        );
      }
    } finally {
      titleCtrl.dispose();
    }
  }

  Future<void> _deleteGrant() async {
    if (!widget.isAdmin) return;
    final grantId = widget.grant['id'] as String?;
    if (grantId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this grant?'),
        content: const Text(
          'This permanently deletes the grant, all its deliverables, file records, '
          'and removes stored files for this grant. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete grant'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final delRows = await _supabase
          .from('deliverables')
          .select('deliverable_files(storage_path)')
          .eq('grant_id', grantId);
      final paths = <String>[];
      for (final row in List<Map<String, dynamic>>.from(delRows)) {
        final nested = row['deliverable_files'];
        if (nested is List) {
          for (final f in nested) {
            if (f is Map && f['storage_path'] is String) {
              paths.add(f['storage_path'] as String);
            }
          }
        }
      }
      if (paths.isNotEmpty) {
        await _supabase.storage.from(SupabaseConfig.grantFilesBucket).remove(paths);
      }
      await _supabase.from('grants').delete().eq('id', grantId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grant deleted.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete grant: $e')),
        );
      }
    }
  }

  Future<void> _deleteDeliverable(Map<String, dynamic> deliverable) async {
    if (!widget.isAdmin) return;
    final deliverableId = deliverable['id'] as String?;
    if (deliverableId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this deliverable?'),
        content: Text(
          'This permanently deletes "${deliverable['title'] ?? 'deliverable'}" and all uploads attached to it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final fileRows = await _supabase
          .from('deliverable_files')
          .select('storage_path')
          .eq('deliverable_id', deliverableId);
      final paths = <String>[];
      for (final row in List<Map<String, dynamic>>.from(fileRows)) {
        final path = row['storage_path'];
        if (path is String) paths.add(path);
      }

      if (paths.isNotEmpty) {
        await _supabase.storage.from(SupabaseConfig.grantFilesBucket).remove(paths);
      }

      await _supabase.from('deliverables').delete().eq('id', deliverableId);
      if (!mounted) return;
      setState(() => _fileListEpoch++);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deliverable deleted.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete deliverable: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.grant['title'] as String? ?? 'Grant';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.isAdmin)
            MoreOptionsButton(
              onSelected: (v) {
                if (v == 'edit') _editGrant();
                if (v == 'delete') _deleteGrant();
              },
              itemBuilder: (c) => [
                moreMenuItem(c, value: 'edit', label: 'Edit', icon: Icons.edit_outlined),
                moreMenuItem(
                  c,
                  value: 'delete',
                  label: 'Delete grant',
                  icon: Icons.delete_outline,
                  destructive: true,
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: _grantApproved
          ? FloatingActionButton.extended(
              onPressed: _addDeliverable,
              icon: const Icon(Icons.add_task),
              label: Text(widget.isAdmin ? 'Deliverable' : 'Propose deliverable'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (widget.isAdmin && _grantProposalStatus == 'pending')
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Grant proposal',
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'This grant is waiting for an admin to approve or reject it.',
                                      ),
                                    ],
                                  ),
                                ),
                                MoreOptionsButton(
                                  onSelected: (v) {
                                    if (v == 'approve') {
                                      _setGrantProposalStatus('approved');
                                    } else if (v == 'reject') {
                                      _setGrantProposalStatus('rejected');
                                    }
                                  },
                                  itemBuilder: (c) => [
                                    moreMenuItem(
                                      c,
                                      value: 'approve',
                                      label: 'Approve grant',
                                      icon: Icons.check_circle_outline,
                                    ),
                                    moreMenuItem(
                                      c,
                                      value: 'reject',
                                      label: 'Reject grant',
                                      icon: Icons.cancel_outlined,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        'Deliverables',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (_deliverables.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No deliverables yet. Tap the button to add one.'),
                        ),
                      ..._deliverables.map((d) {
                        final id = d['id'] as String;
                        final raw = d['status'] as String? ?? 'in_progress';
                        final status = raw == 'pending' ? 'in_progress' : raw;
                        final dps = d['proposal_status'] as String? ?? 'approved';
                        const workflowValues = {'in_progress', 'completed', 'needs_review'};
                        final dropdownValue =
                            workflowValues.contains(status) ? status : 'in_progress';
                        final workLabel = workflowStatusLabel(d['status'] as String?);
                        final proposalLine =
                            dps != 'approved' ? ' · Proposal: ${proposalStatusLabel(dps)}' : '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ExpansionTile(
                            title: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        d['title'] as String? ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Due: ${d['due_date'] ?? '—'} · $workLabel$proposalLine',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                MoreOptionsButton(
                                  onSelected: (v) => _onDeliverableMenu(v, id, d),
                                  itemBuilder: (c) => _deliverableMenuEntries(c, d),
                                ),
                              ],
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    const Text('Work status:'),
                                    const SizedBox(width: 8),
                                    DropdownButton<String>(
                                      value: dropdownValue,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'in_progress',
                                          child: Text('In progress'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'completed',
                                          child: Text('Completed'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'needs_review',
                                          child: Text('Needs review'),
                                        ),
                                      ],
                                      onChanged: (dps == 'approved' || widget.isAdmin)
                                          ? (v) {
                                              if (v != null) _setDeliverableStatus(id, v);
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                key: ValueKey('$id-$_fileListEpoch'),
                                future: _filesFor(id),
                                builder: (context, snap) {
                                  if (!snap.hasData) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: LinearProgressIndicator(),
                                    );
                                  }
                                  final files = snap.data!;
                                  if (files.isEmpty) {
                                    return const ListTile(
                                      title: Text('No files yet'),
                                    );
                                  }
                                  return Column(
                                    children: files.map((file) {
                                      return ListTile(
                                        leading: const Icon(Icons.insert_drive_file),
                                        title: Text(file['file_name'] as String? ?? 'file'),
                                        subtitle: Text(
                                          'Uploaded ${file['created_at'] ?? ''}',
                                        ),
                                        trailing: MoreOptionsButton(
                                          onSelected: (v) {
                                            if (v == 'open') {
                                              _openFile(file);
                                            } else if (v == 'delete') {
                                              _deleteDeliverableFile(file);
                                            }
                                          },
                                          itemBuilder: (c) {
                                            final out = <PopupMenuEntry<String>>[
                                              moreMenuItem(
                                                c,
                                                value: 'open',
                                                label: 'Open',
                                                icon: Icons.open_in_new,
                                              ),
                                            ];
                                            if (_canDeleteFile(file)) {
                                              out.add(
                                                moreMenuItem(
                                                  c,
                                                  value: 'delete',
                                                  label: 'Delete',
                                                  icon: Icons.delete_outline,
                                                  destructive: true,
                                                ),
                                              );
                                            }
                                            return out;
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
