import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/admin.dart';
import '../../models/group.dart';
import '../../models/weight_record.dart' as wr;
import '../../services/admin_auth_service.dart';
import '../../services/weight_record_service.dart';
import '../../utils/app_colors.dart';
import '../login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminAuthService _adminAuthService = AdminAuthService();
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'ReNova Admin Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          FutureBuilder<Admin?>(
            future: _adminAuthService.getCurrentAdmin(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final admin = snapshot.data!;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            admin.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            admin.role.displayName,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.account_circle,
                            color: Colors.white, size: 32),
                        onSelected: (value) async {
                          if (value == 'logout') {
                            await _adminAuthService.signOut();
                            if (mounted) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                              );
                            }
                          } else if (value == 'profile') {
                            _showProfileDialog(admin);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'profile',
                            child: Row(
                              children: [
                                Icon(Icons.person, size: 20),
                                SizedBox(width: 8),
                                Text('Profile'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout, size: 20),
                                SizedBox(width: 8),
                                Text('Logout'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Sidebar Navigation
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            backgroundColor: Colors.grey[100],
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard),
                label: Text('Overview'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.groups),
                label: Text('Organizations'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.place),
                label: Text('EcoSpots'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.scale),
                label: Text('Weight Records'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.person),
                label: Text('Users'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.admin_panel_settings),
                label: Text('Admin Users'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildOverview();
      case 1:
        return _buildOrganizations();
      case 2:
        return _buildEcoSpots();
      case 3:
        return _buildWeightRecords();
      case 4:
        return _buildUsers();
      case 5:
        return _buildAdminUsers();
      default:
        return _buildOverview();
    }
  }

  Widget _buildOverview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Overview',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 24),
          // Statistics Cards
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('group_organizations')
                .snapshots(),
            builder: (context, groupsSnapshot) {
              final groupsCount =
                  groupsSnapshot.hasData ? groupsSnapshot.data!.docs.length : 0;

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .snapshots(),
                builder: (context, usersSnapshot) {
                  final usersCount = usersSnapshot.hasData
                      ? usersSnapshot.data!.docs.length
                      : 0;

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('ecospots')
                        .snapshots(),
                    builder: (context, ecoSpotsSnapshot) {
                      final ecoSpotsCount = ecoSpotsSnapshot.hasData
                          ? ecoSpotsSnapshot.data!.docs.length
                          : 0;

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('weight_records')
                            .snapshots(),
                        builder: (context, weightsSnapshot) {
                          final weightsCount = weightsSnapshot.hasData
                              ? weightsSnapshot.data!.docs.length
                              : 0;

                          // Calculate total weight
                          double totalWeight = 0;
                          if (weightsSnapshot.hasData) {
                            for (var doc in weightsSnapshot.data!.docs) {
                              final weight = (doc.data()
                                      as Map<String, dynamic>)['weightInKg'] ??
                                  0;
                              totalWeight += (weight as num).toDouble();
                            }
                          }

                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      title: 'Organizations',
                                      value: groupsCount.toString(),
                                      icon: Icons.groups,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      title: 'Total Users',
                                      value: usersCount.toString(),
                                      icon: Icons.person,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      title: 'EcoSpots',
                                      value: ecoSpotsCount.toString(),
                                      icon: Icons.place,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      title: 'Weight Records',
                                      value: weightsCount.toString(),
                                      icon: Icons.scale,
                                      color: Colors.purple,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      title: 'Total Weight Collected',
                                      value: '${totalWeight.toStringAsFixed(1)} kg',
                                      icon: Icons.analytics,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  const Expanded(child: SizedBox()),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 32),
          // Recent Activity
          Text(
            'Recent Activity',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _buildRecentActivity(),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 32),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('weight_records')
          .orderBy('recordedAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.data!.docs.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No recent activity'),
              ),
            ),
          );
        }

        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: snapshot.data!.docs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final recordedAt = (data['recordedAt'] as Timestamp).toDate();
              final timeAgo = _getTimeAgo(recordedAt);

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.withOpacity(0.1),
                  child: const Icon(Icons.scale, color: Colors.green),
                ),
                title: Text(
                  '${data['recordedByName']} recorded ${data['weightInKg']}kg of ${data['materialType']}',
                ),
                subtitle: Text('$timeAgo at ${data['ecoSpotName']}'),
                trailing: Text(
                  '${recordedAt.day}/${recordedAt.month}/${recordedAt.year}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildOrganizations() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('group_organizations')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orgs = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Organizations (${orgs.length})',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Phone')),
                      DataColumn(label: Text('Members')),
                      DataColumn(label: Text('Created')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: orgs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final createdAt =
                          (data['createdAt'] as Timestamp?)?.toDate();
                      final members = data['members'] as List<dynamic>? ?? [];

                      return DataRow(
                        cells: [
                          DataCell(Text(data['groupName'] ?? 'N/A')),
                          DataCell(Text(data['email'] ?? 'N/A')),
                          DataCell(Text(data['phoneNumber'] ?? 'N/A')),
                          DataCell(Text(members.length.toString())),
                          DataCell(Text(createdAt != null
                              ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                              : 'N/A')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEcoSpots() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('ecospots').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final ecoSpots = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EcoSpots (${ecoSpots.length})',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),
              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Location')),
                      DataColumn(label: Text('Collections')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Created')),
                    ],
                    rows: ecoSpots.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final createdAt =
                          (data['createdAt'] as Timestamp?)?.toDate();

                      return DataRow(
                        cells: [
                          DataCell(Text(data['name'] ?? 'N/A')),
                          DataCell(Text(data['type'] ?? 'N/A')),
                          DataCell(Text(data['address'] ?? 'N/A')),
                          DataCell(
                              Text((data['collectionCount'] ?? 0).toString())),
                          DataCell(Text(data['status'] ?? 'N/A')),
                          DataCell(Text(createdAt != null
                              ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                              : 'N/A')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeightRecords() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('weight_records')
          .orderBy('recordedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weight Records (${records.length})',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),
              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('EcoSpot')),
                      DataColumn(label: Text('Material')),
                      DataColumn(label: Text('Weight (kg)')),
                      DataColumn(label: Text('Recorded By')),
                      DataColumn(label: Text('Notes')),
                    ],
                    rows: records.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final recordedAt =
                          (data['recordedAt'] as Timestamp?)?.toDate();

                      return DataRow(
                        cells: [
                          DataCell(Text(recordedAt != null
                              ? '${recordedAt.day}/${recordedAt.month}/${recordedAt.year}'
                              : 'N/A')),
                          DataCell(Text(data['ecoSpotName'] ?? 'N/A')),
                          DataCell(Text(data['materialType'] ?? 'N/A')),
                          DataCell(Text(
                              (data['weightInKg'] ?? 0).toStringAsFixed(2))),
                          DataCell(Text(data['recordedByName'] ?? 'N/A')),
                          DataCell(Text(data['notes'] ?? '-')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsers() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Users (${users.length})',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),
              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Phone')),
                      DataColumn(label: Text('Created')),
                    ],
                    rows: users.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final createdAt =
                          (data['createdAt'] as Timestamp?)?.toDate();

                      return DataRow(
                        cells: [
                          DataCell(Text(data['displayName'] ?? 'N/A')),
                          DataCell(Text(data['email'] ?? 'N/A')),
                          DataCell(Text(data['phoneNumber'] ?? 'N/A')),
                          DataCell(Text(createdAt != null
                              ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                              : 'N/A')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminUsers() {
    return FutureBuilder<Admin?>(
      future: _adminAuthService.getCurrentAdmin(),
      builder: (context, currentAdminSnapshot) {
        if (!currentAdminSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final currentAdmin = currentAdminSnapshot.data!;
        final isSuperAdmin = currentAdmin.role == AdminRole.superAdmin;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('admins').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final admins = snapshot.data!.docs;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Admin Users (${admins.length})',
                        style:
                            Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      if (isSuperAdmin)
                        ElevatedButton.icon(
                          onPressed: _showCreateAdminDialog,
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text('Create Admin',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Role')),
                          DataColumn(label: Text('City/Region')),
                          DataColumn(label: Text('Last Login')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: admins.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final lastLogin =
                              (data['lastLogin'] as Timestamp?)?.toDate();
                          final isActive = data['isActive'] ?? true;

                          return DataRow(
                            cells: [
                              DataCell(Text(data['displayName'] ?? 'N/A')),
                              DataCell(Text(data['email'] ?? 'N/A')),
                              DataCell(Text(data['role'] ?? 'N/A')),
                              DataCell(Text(data['city'] ?? data['region'] ?? 'N/A')),
                              DataCell(Text(lastLogin != null
                                  ? _getTimeAgo(lastLogin)
                                  : 'Never')),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Colors.green.withOpacity(0.1)
                                        : Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      color:
                                          isActive ? Colors.green : Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                isSuperAdmin && doc.id != currentAdmin.id
                                    ? IconButton(
                                        icon: Icon(
                                          isActive
                                              ? Icons.block
                                              : Icons.check_circle,
                                          color: isActive
                                              ? Colors.red
                                              : Colors.green,
                                        ),
                                        onPressed: () async {
                                          if (isActive) {
                                            await _adminAuthService
                                                .deactivateAdmin(doc.id);
                                          } else {
                                            await _adminAuthService
                                                .reactivateAdmin(doc.id);
                                          }
                                        },
                                        tooltip: isActive
                                            ? 'Deactivate'
                                            : 'Activate',
                                      )
                                    : const SizedBox(),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileDialog(Admin admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileItem('Name', admin.displayName),
            _buildProfileItem('Email', admin.email),
            _buildProfileItem('Role', admin.role.displayName),
            if (admin.city != null) _buildProfileItem('City', admin.city!),
            if (admin.region != null) _buildProfileItem('Region', admin.region!),
            _buildProfileItem(
              'Status',
              admin.isActive ? 'Active' : 'Inactive',
            ),
            _buildProfileItem(
              'Last Login',
              admin.lastLogin != null ? _getTimeAgo(admin.lastLogin!) : 'Never',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateAdminDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    final cityController = TextEditingController();
    AdminRole selectedRole = AdminRole.moderator;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Admin User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<AdminRole>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: AdminRole.values.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: cityController,
                  decoration: const InputDecoration(
                    labelText: 'City/Region (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    emailController.text.isEmpty ||
                    passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all required fields'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  await _adminAuthService.createAdmin(
                    email: emailController.text.trim(),
                    password: passwordController.text,
                    displayName: nameController.text.trim(),
                    role: selectedRole,
                    city: cityController.text.trim().isEmpty
                        ? null
                        : cityController.text.trim(),
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Admin created successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Create',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes minute${minutes != 1 ? "s" : ""} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours != 1 ? "s" : ""} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days day${days != 1 ? "s" : ""} ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks week${weeks != 1 ? "s" : ""} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months != 1 ? "s" : ""} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years year${years != 1 ? "s" : ""} ago';
    }
  }
}
