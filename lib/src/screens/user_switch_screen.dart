import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../widgets/responsive_dialog.dart';
import 'main_screen.dart';
import 'login_screen.dart';

class UserSwitchScreen extends ConsumerStatefulWidget {
  const UserSwitchScreen({super.key});

  @override
  ConsumerState<UserSwitchScreen> createState() => _UserSwitchScreenState();
}

class _UserSwitchScreenState extends ConsumerState<UserSwitchScreen> {
  List<User> _savedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedUsers();
  }

  Future<void> _loadSavedUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await ref.read(authProvider.notifier).getSavedUsers();
      if (!mounted) return;
      setState(() {
        _savedUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _switchUser(User user) async {
    await ref.read(authProvider.notifier).switchUser(user);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    }
  }

  Future<void> _deleteUser(User user) async {
    await ref.read(authProvider.notifier).removeUser(user);
    await _loadSavedUsers();
  }

  void _showDeleteConfirmation(User user) {
    showDialog(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: Text(S.of(context).deleteAccount),
        content: Text(S.of(context).deleteAccountConfirm(user.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteUser(user);
            },
            child: Text(S.of(context).delete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(S.of(context).selectAccount),
            backgroundColor: cs.surface,
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      )
                      .then((_) => _loadSavedUsers());
                },
              ),
            ],
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_savedUsers.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_add,
                      size: 80,
                      color: cs.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      S.of(context).noSavedAccounts,
                      style: tt.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).addAccountToGetStarted,
                      style: tt.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            )
                            .then((_) => _loadSavedUsers());
                      },
                      icon: const Icon(Icons.add),
                      label: Text(S.of(context).addAccount),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final user = _savedUsers[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: cs.primary,
                        child: Text(
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        user.name,
                        style: tt.titleMedium,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            user.host ?? S.of(context).unknownHost,
                            style: tt.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            S.of(context).lastUsedTime(user.lastUpdateTime != null ? _formatDateTime(context, user.lastUpdateTime!) : S.of(context).unknown),
                            style: tt.bodySmall?.copyWith(
                                  color: cs.outline,
                                ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _showDeleteConfirmation(user);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: const Icon(Icons.delete),
                              title: Text(S.of(context).deleteAccount),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _switchUser(user),
                    ),
                  );
                }, childCount: _savedUsers.length),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(BuildContext context, DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final s = S.of(context);

    if (difference.inDays > 0) {
      return s.daysAgo(difference.inDays);
    } else if (difference.inHours > 0) {
      return s.hoursAgo(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return s.minutesAgo(difference.inMinutes);
    } else {
      return s.justNow;
    }
  }
}
