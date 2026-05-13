import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../deliverable_status_labels.dart';
import '../widgets/more_options_menu.dart';
import 'grant_detail_screen.dart';
import 'org_timeline_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _newOrgController = TextEditingController();
  final _inviteEmailController = TextEditingController();

  late TabController _tabs;

  List<Map<String, dynamic>> _memberships = [];
  String? _selectedOrgId;
  bool _loading = true;
  String? _banner;
  int _grantsTick = 0;
  Future<Map<String, List<Map<String, dynamic>>>>? _adminTabFuture;
  String? _adminTabFutureOrg;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _newOrgController.dispose();
    _inviteEmailController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _banner = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final rows = await _supabase.from('memberships').select(
            'id, role, organization_id, organizations ( id, name, created_at )',
          ).eq('user_id', user.id);

      final list = List<Map<String, dynamic>>.from(rows);
      setState(() {
        _memberships = list;
        if (_selectedOrgId == null && list.isNotEmpty) {
          _selectedOrgId = list.first['organization_id'] as String;
        } else if (_selectedOrgId != null) {
          final still = list.any((m) => m['organization_id'] == _selectedOrgId);
          if (!still) {
            _selectedOrgId = list.isEmpty ? null : list.first['organization_id'] as String;
          }
        }
      });
    } catch (e) {
      setState(() {
        _banner = 'Could not load organizations: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Map<String, dynamic>? get _selectedMembership {
    if (_selectedOrgId == null) return null;
    for (final m in _memberships) {
      if (m['organization_id'] == _selectedOrgId) return m;
    }
    return null;
  }

  bool get _isAdmin => (_selectedMembership?['role'] as String?) == 'admin';

  String? _orgName(String? orgId) {
    if (orgId == null) return null;
    for (final m in _memberships) {
      if (m['organization_id'] == orgId) {
        final org = m['organizations'];
        if (org is Map) {
          return org['name'] as String?;
        }
      }
    }
    return null;
  }

  Future<void> _createOrganization() async {
    final name = _newOrgController.text.trim();
    if (name.isEmpty) {
      setState(() => _banner = 'Enter an organization name.');
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);
    try {
      final orgId = await _supabase.rpc<String>(
        'create_organization_with_admin_membership',
        params: {'p_name': name},
      );
      if (orgId.isEmpty) {
        throw Exception('Organization was created but id was not returned.');
      }
      _newOrgController.clear();
      await _reload();
      setState(() => _selectedOrgId = orgId);
    } catch (e) {
      setState(() => _banner = 'Create organization failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editSelectedOrganizationName() async {
    final orgId = _selectedOrgId;
    if (orgId == null || !_isAdmin) return;

    final initial = _orgName(orgId) ?? '';
    final controller = TextEditingController(text: initial);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename organization'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Organization name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final name = controller.text.trim();
    controller.dispose();

    if (ok != true) return;
    if (name.isEmpty) {
      setState(() => _banner = 'Organization name cannot be empty.');
      return;
    }

    setState(() => _loading = true);
    try {
      await _supabase.from('organizations').update({'name': name}).eq('id', orgId);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organization updated.')),
        );
      }
    } catch (e) {
      setState(() => _banner = 'Could not update organization: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editGrantFromList(Map<String, dynamic> g) async {
    if (!_isAdmin) return;
    final id = g['id'] as String?;
    if (id == null) return;
    final titleCtrl = TextEditingController(text: g['title'] as String? ?? '');
    try {
      var start = DateTime.tryParse('${g['start_date'] ?? '1970-01-01'}T00:00:00') ?? DateTime.now();
      var end = DateTime.tryParse('${g['end_date'] ?? '1970-01-01'}T00:00:00') ?? DateTime.now();
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
      if (mounted) setState(() => _grantsTick++);
    } catch (e) {
      setState(() => _banner = 'Could not update grant: $e');
    } finally {
      titleCtrl.dispose();
    }
  }

  Future<void> _deleteGrantFromList(Map<String, dynamic> g) async {
    final id = g['id'] as String?;
    if (id == null) return;
    if (!_isAdmin) {
      final ps = g['proposal_status'] as String? ?? 'approved';
      final prop = g['proposed_by'] as String?;
      final uid = _supabase.auth.currentUser?.id;
      if (ps != 'pending' || prop != uid) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this grant?'),
        content: const Text(
          'This permanently deletes the grant, all its deliverables, file records, '
          'and stored files. This cannot be undone.',
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
      final delRows = await _supabase
          .from('deliverables')
          .select('deliverable_files(storage_path)')
          .eq('grant_id', id);
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
      await _supabase.from('grants').delete().eq('id', id);
      if (mounted) setState(() => _grantsTick++);
    } catch (e) {
      setState(() => _banner = 'Could not delete grant: $e');
    }
  }

  Future<void> _deleteSelectedOrganization() async {
    final orgId = _selectedOrgId;
    if (orgId == null || !_isAdmin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete organization?'),
        content: const Text(
          'This permanently deletes the organization, its grants, deliverables, '
          'invites, and related data for all members. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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

    setState(() => _loading = true);
    try {
      await _supabase.from('organizations').delete().eq('id', orgId);
      setState(() => _selectedOrgId = null);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organization deleted.')),
        );
      }
    } catch (e) {
      setState(() => _banner = 'Could not delete organization: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendInvite(String role) async {
    final orgId = _selectedOrgId;
    if (orgId == null) return;
    final email = _inviteEmailController.text.trim();
    if (email.isEmpty) {
      setState(() => _banner = 'Invite email required.');
      return;
    }
    try {
      await _supabase.from('organization_invites').insert({
        'organization_id': orgId,
        'email': email,
        'role': role,
      });
      _inviteEmailController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invite saved')),
        );
      }
    } catch (e) {
      setState(() => _banner = 'Invite failed: $e');
    }
  }

  Future<void> _acceptInvite(Map<String, dynamic> invite) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final orgId = invite['organization_id'] as String;
    final role = invite['role'] as String? ?? 'member';

    try {
      final existing = await _supabase
          .from('memberships')
          .select('id')
          .eq('user_id', user.id)
          .eq('organization_id', orgId)
          .maybeSingle();
      if (existing != null) {
        await _supabase.from('organization_invites').delete().eq('id', invite['id']);
        await _reload();
        return;
      }

      await _supabase.from('memberships').insert({
        'user_id': user.id,
        'organization_id': orgId,
        'role': role,
      });
      await _supabase.from('organization_invites').delete().eq('id', invite['id']);
      await _reload();
      setState(() => _selectedOrgId = orgId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You joined the organization.')),
        );
      }
    } catch (e) {
      setState(() => _banner = 'Could not accept invite: $e');
    }
  }

  Future<void> _updateMemberRole(String membershipId, String newRole) async {
    try {
      await _supabase.from('memberships').update({'role': newRole}).eq('id', membershipId);
      await _reload();
    } catch (e) {
      setState(() => _banner = 'Role update failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _pendingInvitesForUser() async {
    final email = _supabase.auth.currentUser?.email;
    if (email == null) return [];
    final rows = await _supabase
        .from('organization_invites')
        .select('*, organizations ( name )')
        .eq('email', email);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _membersForOrg(String orgId) async {
    final rows = await _supabase.from('memberships').select().eq('organization_id', orgId);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _grantsForOrg(String orgId) async {
    final rows = await _supabase.from('grants').select().eq('organization_id', orgId).order('start_date');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _addGrant() async {
    final orgId = _selectedOrgId;
    if (orgId == null) return;

    final titleCtrl = TextEditingController();
    var start = DateTime.now();
    var end = DateTime.now().add(const Duration(days: 365));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('New grant'),
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
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (ok != true || titleCtrl.text.trim().isEmpty) return;

    final user = _supabase.auth.currentUser;
    try {
      final row = <String, dynamic>{
        'organization_id': orgId,
        'title': titleCtrl.text.trim(),
        'start_date': start.toIso8601String().split('T').first,
        'end_date': end.toIso8601String().split('T').first,
      };
      if (_isAdmin) {
        row['proposal_status'] = 'approved';
      } else {
        row['proposal_status'] = 'pending';
        row['proposed_by'] = user?.id;
      }
      await _supabase.from('grants').insert(row);
      if (mounted) setState(() => _grantsTick++);
    } catch (e) {
      setState(() => _banner = 'Create grant failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _pendingGrants(String orgId) async {
    final rows = await _supabase
        .from('grants')
        .select()
        .eq('organization_id', orgId)
        .eq('proposal_status', 'pending')
        .order('start_date');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _pendingDeliverableProposals(String orgId) async {
    final grantRows =
        await _supabase.from('grants').select('id, title').eq('organization_id', orgId);
    final grants = List<Map<String, dynamic>>.from(grantRows);
    if (grants.isEmpty) return [];
    final grantIds = grants.map((g) => g['id'] as String).toList();
    final orFilter = grantIds.map((id) => 'grant_id.eq.$id').join(',');
    final delRows = await _supabase
        .from('deliverables')
        .select()
        .eq('proposal_status', 'pending')
        .or(orFilter)
        .order('due_date');
    final dels = List<Map<String, dynamic>>.from(delRows);
    final grantById = {for (final g in grants) g['id'] as String: g};
    for (final d in dels) {
      final gid = d['grant_id'] as String?;
      if (gid != null) {
        d['grants'] = grantById[gid];
      }
    }
    return dels;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _adminTabFutureForCurrentOrg() {
    final org = _selectedOrgId!;
    if (_adminTabFuture == null || _adminTabFutureOrg != org) {
      _adminTabFutureOrg = org;
      _adminTabFuture = _adminTabData(org);
    }
    return _adminTabFuture!;
  }

  Future<void> _setGrantProposalStatus(String grantId, String status) async {
    try {
      await _supabase.from('grants').update({'proposal_status': status}).eq('id', grantId);
      if (mounted) {
        setState(() {
          _grantsTick++;
          if (_selectedOrgId != null) {
            _adminTabFuture = _adminTabData(_selectedOrgId!);
            _adminTabFutureOrg = _selectedOrgId;
          }
        });
      }
    } catch (e) {
      setState(() => _banner = 'Could not update grant proposal: $e');
    }
  }

  Future<void> _setDeliverableProposalStatus(String deliverableId, String status) async {
    try {
      await _supabase.from('deliverables').update({'proposal_status': status}).eq('id', deliverableId);
      if (mounted) {
        setState(() {
          _grantsTick++;
          if (_selectedOrgId != null) {
            _adminTabFuture = _adminTabData(_selectedOrgId!);
            _adminTabFutureOrg = _selectedOrgId;
          }
        });
      }
    } catch (e) {
      setState(() => _banner = 'Could not update deliverable proposal: $e');
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _adminTabData(String orgId) async {
    final pendingGrants = await _pendingGrants(orgId);
    final pendingDeliverables = await _pendingDeliverableProposals(orgId);
    final deliverables = await _adminDeliverables(orgId);
    return {
      'pendingGrants': pendingGrants,
      'pendingDeliverables': pendingDeliverables,
      'deliverables': deliverables,
    };
  }

  Future<List<Map<String, dynamic>>> _adminDeliverables(String orgId) async {
    final grantRows =
        await _supabase.from('grants').select('id, title').eq('organization_id', orgId);
    final grants = List<Map<String, dynamic>>.from(grantRows);
    if (grants.isEmpty) return [];
    final grantIds = grants.map((g) => g['id'] as String).toList();
    final orFilter = grantIds.map((id) => 'grant_id.eq.$id').join(',');
    final delRows =
        await _supabase.from('deliverables').select().or(orFilter).order('due_date');
    final dels = List<Map<String, dynamic>>.from(delRows);
    final grantById = {for (final g in grants) g['id'] as String: g};
    for (final d in dels) {
      final gid = d['grant_id'] as String?;
      if (gid != null) {
        d['grants'] = grantById[gid];
      }
    }
    return dels;
  }

  Future<List<Map<String, dynamic>>> _notificationsForCurrentUser(String orgId) async {
    final rows = await _supabase
        .from('admin_notifications')
        .select()
        .eq('organization_id', orgId)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _markNotificationRead(String notificationId) async {
    await _supabase.from('admin_notifications').update({
      'is_read': true,
      'read_at': DateTime.now().toIso8601String(),
    }).eq('id', notificationId);
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(_orgName(_selectedOrgId) ?? 'Grant Manager'),
        actions: [
          if (_memberships.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButton<String>(
                value: _selectedOrgId,
                hint: const Text('Organization'),
                items: _memberships.map((m) {
                  final id = m['organization_id'] as String;
                  final name = _orgName(id) ?? id;
                  return DropdownMenuItem(value: id, child: Text(name));
                }).toList(),
                onChanged: (v) => setState(() {
                  _selectedOrgId = v;
                  _adminTabFuture = null;
                  _adminTabFutureOrg = null;
                }),
              ),
            ),
          TextButton(
            onPressed: () async {
              await _supabase.auth.signOut();
            },
            child: Text(user?.email ?? 'Logout'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Grants'),
            Tab(text: 'Timeline'),
            Tab(text: 'Organization'),
            Tab(text: 'Admin'),
            Tab(text: 'Notifications'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_banner != null)
                  MaterialBanner(
                    content: Text(_banner!),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => _banner = null),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildGrantsTab(),
                      _buildTimelineTab(),
                      _buildOrgTab(),
                      _buildAdminTab(),
                      _buildNotificationsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildGrantsTab() {
    if (_selectedOrgId == null) {
      return const Center(
        child: Text('Create or join an organization from the Organization tab.'),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('grants-$_selectedOrgId-$_grantsTick'),
      future: _grantsForOrg(_selectedOrgId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        final grants = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _grantsTick++);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: grants.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Text(
                        _orgName(_selectedOrgId) ?? 'Grants',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _addGrant,
                        icon: const Icon(Icons.add),
                        label: Text(_isAdmin ? 'Grant' : 'Propose grant'),
                      ),
                    ],
                  ),
                );
              }
              final g = grants[i - 1];
              final ps = g['proposal_status'] as String? ?? 'approved';
              final proposedBy = g['proposed_by'] as String?;
              final uid = _supabase.auth.currentUser?.id;
              final isOwnPending = ps == 'pending' && proposedBy == uid;
              final hasGrantMenu = _isAdmin || isOwnPending;
              return Card(
                child: ListTile(
                  title: Text(g['title'] as String? ?? ''),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${g['start_date'] ?? ''} → ${g['end_date'] ?? ''}'),
                      if (ps != 'approved')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(ps == 'pending' ? 'Pending approval' : 'Rejected'),
                            ),
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: ps != 'approved',
                  trailing: hasGrantMenu
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MoreOptionsButton(
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _editGrantFromList(g);
                                } else if (v == 'delete') {
                                  _deleteGrantFromList(g);
                                }
                              },
                              itemBuilder: (c) {
                                if (_isAdmin) {
                                  return [
                                    moreMenuItem(
                                      c,
                                      value: 'edit',
                                      label: 'Edit',
                                      icon: Icons.edit_outlined,
                                    ),
                                    moreMenuItem(
                                      c,
                                      value: 'delete',
                                      label: 'Delete',
                                      icon: Icons.delete_outline,
                                      destructive: true,
                                    ),
                                  ];
                                }
                                return [
                                  moreMenuItem(
                                    c,
                                    value: 'delete',
                                    label: 'Delete proposal',
                                    icon: Icons.delete_outline,
                                    destructive: true,
                                  ),
                                ];
                              },
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (context) => GrantDetailScreen(
                          grant: g,
                          organizationId: _selectedOrgId!,
                          isAdmin: _isAdmin,
                        ),
                      ),
                    );
                    if (changed == true && mounted) {
                      setState(() => _grantsTick++);
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTimelineTab() {
    if (_selectedOrgId == null) {
      return const Center(
        child: Text('Create or join an organization to see the timeline.'),
      );
    }
    return OrgTimelineView(
      key: ValueKey('tl-$_selectedOrgId'),
      organizationId: _selectedOrgId!,
      organizationName: _orgName(_selectedOrgId) ?? 'Organization',
    );
  }

  Widget _buildOrgTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Signed in as ${_supabase.auth.currentUser?.email}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Text('Create organization', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _newOrgController,
          decoration: const InputDecoration(
            labelText: 'Organization name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _loading ? null : _createOrganization,
            child: const Text('Create'),
          ),
        ),
        if (_isAdmin && _selectedOrgId != null) ...[
          const Divider(height: 32),
          Text('Current organization', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _orgName(_selectedOrgId) ?? '—',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  MoreOptionsButton(
                    enabled: !_loading,
                    onSelected: (v) {
                      if (v == 'rename') {
                        _editSelectedOrganizationName();
                      } else if (v == 'delete') {
                        _deleteSelectedOrganization();
                      }
                    },
                    itemBuilder: (c) => [
                      moreMenuItem(c, value: 'rename', label: 'Rename', icon: Icons.edit_outlined),
                      moreMenuItem(
                        c,
                        value: 'delete',
                        label: 'Delete organization',
                        icon: Icons.delete_outline,
                        destructive: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const Divider(height: 32),
        Text('Pending invites for you', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _pendingInvitesForUser(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const LinearProgressIndicator();
            }
            final invites = snap.data!;
            if (invites.isEmpty) {
              return const Text('No pending invites.');
            }
            return Column(
              children: invites.map((inv) {
                final org = inv['organizations'];
                final name = org is Map ? org['name'] as String? : null;
                return Card(
                  child: ListTile(
                    title: Text(name ?? 'Organization'),
                    subtitle: Text('Role: ${inv['role']}'),
                    trailing: FilledButton(
                      onPressed: () => _acceptInvite(inv),
                      child: const Text('Join'),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        if (_isAdmin && _selectedOrgId != null) ...[
          const Divider(height: 32),
          Text('Invite people', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _inviteEmailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => _sendInvite('member'),
                child: const Text('Invite as member'),
              ),
              OutlinedButton(
                onPressed: () => _sendInvite('admin'),
                child: const Text('Invite as admin'),
              ),
            ],
          ),
        ],
        const Divider(height: 32),
        Text('Members', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_selectedOrgId == null)
          const Text('Select or create an organization.')
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('mem-$_selectedOrgId'),
            future: _membersForOrg(_selectedOrgId!),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const LinearProgressIndicator();
              }
              final members = snap.data!;
              if (members.isEmpty) {
                return const Text('No members.');
              }
              return Column(
                children: members.map((m) {
                  final id = m['id'] as String;
                  final uid = m['user_id'] as String;
                  final role = m['role'] as String? ?? 'member';
                  return Card(
                    child: ListTile(
                      title: Text(uid),
                      subtitle: Text('Role: $role'),
                      trailing: _isAdmin
                          ? DropdownButton<String>(
                              value: role,
                              items: const [
                                DropdownMenuItem(value: 'admin', child: Text('admin')),
                                DropdownMenuItem(value: 'member', child: Text('member')),
                                DropdownMenuItem(value: 'contributor', child: Text('contributor')),
                              ],
                              onChanged: (v) {
                                if (v != null) _updateMemberRole(id, v);
                              },
                            )
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildAdminTab() {
    if (!_isAdmin || _selectedOrgId == null) {
      return const Center(
        child: Text('Admin tools are available to organization admins.'),
      );
    }

    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      key: ValueKey('adm-$_selectedOrgId'),
      future: _adminTabFutureForCurrentOrg(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        final data = snapshot.data ?? {};
        final rows = data['deliverables'] ?? [];
        final pendingGrants = data['pendingGrants'] ?? [];
        final pendingDeliverables = data['pendingDeliverables'] ?? [];
        final completed = rows.where((r) => r['status'] == 'completed').length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'Deliverables tracked',
                      value: '${rows.length}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricTile(
                      label: 'Completed',
                      value: '$completed',
                    ),
                  ),
                ],
              ),
            ),
            if (pendingGrants.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Grant proposals'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: pendingGrants.length,
                  itemBuilder: (context, i) {
                    final g = pendingGrants[i];
                    final id = g['id'] as String;
                    return SizedBox(
                      width: 280,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      g['title'] as String? ?? 'Grant',
                                      style: Theme.of(context).textTheme.titleSmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  MoreOptionsButton(
                                    onSelected: (v) {
                                      if (v == 'approve') {
                                        _setGrantProposalStatus(id, 'approved');
                                      } else if (v == 'reject') {
                                        _setGrantProposalStatus(id, 'rejected');
                                      }
                                    },
                                    itemBuilder: (c) => [
                                      moreMenuItem(
                                        c,
                                        value: 'approve',
                                        label: 'Approve',
                                        icon: Icons.check,
                                      ),
                                      moreMenuItem(
                                        c,
                                        value: 'reject',
                                        label: 'Reject',
                                        icon: Icons.close,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                '${g['start_date'] ?? ''} → ${g['end_date'] ?? ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (pendingDeliverables.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Deliverable proposals'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: pendingDeliverables.length,
                  itemBuilder: (context, i) {
                    final d = pendingDeliverables[i];
                    final grant = d['grants'];
                    final grantTitle = grant is Map ? grant['title'] as String? : null;
                    final id = d['id'] as String;
                    return SizedBox(
                      width: 300,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      d['title'] as String? ?? 'Deliverable',
                                      style: Theme.of(context).textTheme.titleSmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  MoreOptionsButton(
                                    onSelected: (v) {
                                      if (v == 'approve') {
                                        _setDeliverableProposalStatus(id, 'approved');
                                      } else if (v == 'reject') {
                                        _setDeliverableProposalStatus(id, 'rejected');
                                      }
                                    },
                                    itemBuilder: (c) => [
                                      moreMenuItem(
                                        c,
                                        value: 'approve',
                                        label: 'Approve',
                                        icon: Icons.check,
                                      ),
                                      moreMenuItem(
                                        c,
                                        value: 'reject',
                                        label: 'Reject',
                                        icon: Icons.close,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                grantTitle ?? 'Grant',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const Spacer(),
                              Text(
                                'Due ${d['due_date'] ?? '—'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('All deliverables across grants'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final d = rows[i];
                  final grant = d['grants'];
                  final grantTitle = grant is Map ? grant['title'] as String? : null;
                  final dps = d['proposal_status'] as String? ?? 'approved';
                  return Card(
                    child: ListTile(
                      title: Text(d['title'] as String? ?? ''),
                      subtitle: Text(
                        '${grantTitle ?? 'Grant'} · due ${d['due_date'] ?? '—'}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(
                            label: Text(
                              workflowStatusLabel(d['status'] as String?),
                            ),
                          ),
                          if (dps != 'approved')
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(proposalStatusLabel(dps)),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNotificationsTab() {
    if (_selectedOrgId == null) {
      return const Center(
        child: Text('Select or create an organization to view notifications.'),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('notif-$_selectedOrgId'),
      future: _notificationsForCurrentUser(_selectedOrgId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }

        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              children: const [
                SizedBox(height: 160),
                Center(child: Text('No notifications yet.')),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final title = row['title'] as String? ?? 'Notification';
              final message = row['message'] as String? ?? '';
              final isRead = row['is_read'] == true;
              final createdAt = row['created_at'] as String?;

              return Card(
                child: ListTile(
                  leading: Icon(
                    isRead ? Icons.notifications_none : Icons.notifications_active,
                  ),
                  title: Text(title),
                  subtitle: Text(
                    createdAt == null ? message : '$message\n$createdAt',
                  ),
                  isThreeLine: true,
                  trailing: isRead
                      ? const Chip(label: Text('Read'))
                      : MoreOptionsButton(
                          tooltip: 'Notification actions',
                          onSelected: (v) async {
                            if (v == 'read') {
                              await _markNotificationRead(row['id'] as String);
                              if (mounted) setState(() {});
                            }
                          },
                          itemBuilder: (c) => [
                            moreMenuItem(
                              c,
                              value: 'read',
                              label: 'Mark as read',
                              icon: Icons.mark_email_read_outlined,
                            ),
                          ],
                        ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
