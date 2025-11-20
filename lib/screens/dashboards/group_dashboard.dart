import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../services/auth_service.dart';
import '../../services/group_auth_service.dart';
import '../../utils/app_colors.dart';
import '../../models/group.dart';
import '../../models/ecospot.dart';
import '../../models/weight_record.dart' as wr;
import '../../services/group_service.dart';
import '../../services/ecospot_service.dart';
import '../../services/weight_record_service.dart';
import '../group_creation_screen.dart';
import '../login_screen.dart';
import '../member_selection_screen.dart';

class GroupDashboard extends StatefulWidget {
  const GroupDashboard({super.key});

  @override
  State<GroupDashboard> createState() => _GroupDashboardState();
}

class _GroupDashboardState extends State<GroupDashboard> {
  final AuthService _authService = AuthService();
  final GroupAuthService _groupAuthService = GroupAuthService();
  int _selectedIndex = 0;

  // Location state
  Position? _currentPosition;
  String? _currentAddress;
  bool _isLoadingLocation = false;
  String _locationError = '';

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _handleSignOut() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  // Location methods
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = '';
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError =
              'Location services are disabled. Please enable them.';
          _isLoadingLocation = false;
        });
        return;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Location permissions are denied.';
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permissions are permanently denied.';
          _isLoadingLocation = false;
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Try to get address from coordinates
      String address = 'Location retrieved';
      try {
        debugPrint(
          'Fetching address for: ${position.latitude}, ${position.longitude}',
        );

        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        debugPrint('Placemarks found: ${placemarks.length}');

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];

          debugPrint('Placemark details:');
          debugPrint('  - name: ${place.name}');
          debugPrint('  - street: ${place.street}');
          debugPrint('  - subLocality: ${place.subLocality}');
          debugPrint('  - locality: ${place.locality}');
          debugPrint(
            '  - subAdministrativeArea: ${place.subAdministrativeArea}',
          );
          debugPrint('  - administrativeArea: ${place.administrativeArea}');
          debugPrint('  - postalCode: ${place.postalCode}');
          debugPrint('  - country: ${place.country}');

          // Build address with priority order
          List<String> addressComponents = [];

          // Add street or name if available
          if (place.street != null &&
              place.street!.isNotEmpty &&
              place.street != 'Unnamed Road') {
            addressComponents.add(place.street!);
          } else if (place.name != null &&
              place.name!.isNotEmpty &&
              place.name != place.locality) {
            addressComponents.add(place.name!);
          }

          // Add sub-locality
          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            addressComponents.add(place.subLocality!);
          }

          // Add locality (city)
          if (place.locality != null && place.locality!.isNotEmpty) {
            addressComponents.add(place.locality!);
          }

          // Add administrative area (state/region)
          if (place.administrativeArea != null &&
              place.administrativeArea!.isNotEmpty) {
            addressComponents.add(place.administrativeArea!);
          }

          // Add country
          if (place.country != null && place.country!.isNotEmpty) {
            addressComponents.add(place.country!);
          }

          if (addressComponents.isNotEmpty) {
            address = addressComponents.join(', ');
            debugPrint('Final address: $address');
          } else {
            // If still no components, use postal code or show general location
            if (place.postalCode != null && place.postalCode!.isNotEmpty) {
              address = 'Near ${place.postalCode}';
            } else {
              address =
                  'Current Location (${position.latitude.toStringAsFixed(2)}°, ${position.longitude.toStringAsFixed(2)}°)';
            }
            debugPrint('Using fallback address: $address');
          }
        } else {
          debugPrint(
            'No placemarks returned - geocoding may not be available on this platform',
          );
          // More user-friendly message instead of raw coordinates
          address = 'Current Location';
        }
      } catch (geocodingError) {
        // If geocoding fails, show user-friendly message
        debugPrint(
          'Geocoding error (may need Google Maps API key for web): $geocodingError',
        );
        // Show simplified coordinates instead of full precision
        address = 'Current Location';
      }

      setState(() {
        _currentPosition = position;
        _currentAddress = address;
        _isLoadingLocation = false;
      });
    } catch (e) {
      debugPrint('Location error: $e');
      setState(() {
        _locationError = 'Failed to get location: ${e.toString()}';
        _isLoadingLocation = false;
      });
    }
  }

  // Get recent activities for the group
  Future<List<Map<String, dynamic>>> _getRecentActivities(Group group) async {
    List<Map<String, dynamic>> activities = [];

    try {
      // Get recent weight records (last 5)
      final weightService = WeightRecordService();
      final weightRecords = await weightService.getRecentWeightRecords(
        group.id,
        5,
      );

      for (var record in weightRecords) {
        final timeAgo = _getTimeAgo(record.recordedAt);
        activities.add({
          'icon': Icons.scale,
          'title':
              '${record.recordedByName} recorded ${record.weightInKg}kg of ${record.materialType.displayName}',
          'subtitle': '$timeAgo at ${record.ecoSpotName}',
          'color': Colors.green,
          'timestamp': record.recordedAt,
        });
      }

      // Get recent EcoSpot creations
      final ecoSpots = await EcoSpotService.getEcoSpotsByGroup(group.id);
      final recentEcoSpots = ecoSpots
          .where(
            (spot) => spot.createdAt.isAfter(
              DateTime.now().subtract(const Duration(days: 7)),
            ),
          )
          .take(3)
          .toList();

      for (var ecoSpot in recentEcoSpots) {
        final timeAgo = _getTimeAgo(ecoSpot.createdAt);
        activities.add({
          'icon': Icons.place,
          'title': 'New EcoSpot created: ${ecoSpot.name}',
          'subtitle': '$timeAgo • ${ecoSpot.typeDisplayName}',
          'color': Colors.blue,
          'timestamp': ecoSpot.createdAt,
        });
      }

      // Get recent member joins (from group members list)
      final groupDoc = await FirebaseFirestore.instance
          .collection('group_organizations')
          .doc(group.id)
          .get();

      if (groupDoc.exists) {
        final members = groupDoc.data()?['members'] as List<dynamic>?;
        if (members != null && members.isNotEmpty) {
          // For new members, we'll show if the group was recently created
          // or if members count is small (indicating recent growth)
          final groupCreatedAt = (groupDoc.data()?['createdAt'] as Timestamp?)
              ?.toDate();
          if (groupCreatedAt != null) {
            final daysSinceCreation = DateTime.now()
                .difference(groupCreatedAt)
                .inDays;
            if (daysSinceCreation <= 7) {
              activities.add({
                'icon': Icons.group_add,
                'title':
                    '${members.length} member${members.length != 1 ? "s" : ""} in ${group.groupName}',
                'subtitle': _getTimeAgo(groupCreatedAt),
                'color': Colors.orange,
                'timestamp': groupCreatedAt,
              });
            }
          }
        }
      }

      // Get recently updated EcoSpots
      final activeEcoSpots = ecoSpots
          .where(
            (spot) =>
                spot.lastUpdated != null &&
                spot.lastUpdated!.isAfter(
                  DateTime.now().subtract(const Duration(days: 3)),
                ),
          )
          .take(3)
          .toList();

      for (var ecoSpot in activeEcoSpots) {
        if (ecoSpot.lastUpdated != null) {
          final timeAgo = _getTimeAgo(ecoSpot.lastUpdated!);
          activities.add({
            'icon': Icons.recycling,
            'title': 'Activity at ${ecoSpot.name}',
            'subtitle':
                '$timeAgo • ${ecoSpot.collectionCount} total collections',
            'color': Colors.teal,
            'timestamp': ecoSpot.lastUpdated!,
          });
        }
      }

      // Sort all activities by timestamp (most recent first)
      activities.sort(
        (a, b) =>
            (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime),
      );

      // Return top 10 most recent activities
      return activities.take(10).toList();
    } catch (e) {
      debugPrint('Error fetching activities: $e');
      return [];
    }
  }

  // Helper function to format time ago
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoSpot Manager Dashboard'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              // Handle create new group/event
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              // Handle notifications
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'profile') {
                // Handle profile
              } else if (value == 'settings') {
                // Handle settings
              } else if (value == 'logout') {
                _handleSignOut();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person),
                      SizedBox(width: 8),
                      Text('Profile'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings),
                      SizedBox(width: 8),
                      Text('Settings'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 8),
                      Text('Logout'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(user),
          _buildEcoSpotsTab(),
          _buildCollectionEventsTab(),
          _buildMembersTab(),
          _buildProfileTab(user),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.secondaryText,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.eco), label: 'EcoSpots'),
          BottomNavigationBarItem(
            icon: Icon(Icons.event),
            label: 'Collections',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Members'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showCreateOptions(context);
        },
        backgroundColor: Colors.green,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHomeTab(User? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Card
          Card(
            elevation: 4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Colors.green, Color(0xFF4CAF50)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EcoSpot Manager',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  Text(
                    user?.displayName ?? 'Community Leader',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Leading sustainable waste management in your community',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Quick Stats
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Managed EcoSpots',
                  '8',
                  Icons.eco,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Community Members',
                  '248',
                  Icons.people,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Collections This Month',
                  '12',
                  Icons.delete_outline,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Quick Actions
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.add_location,
                  title: 'Add EcoSpot',
                  color: Colors.green,
                  onTap: () {
                    // Navigate to EcoSpots tab
                    setState(() {
                      _selectedIndex = 1; // EcoSpots tab index
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tap "New EcoSpot" to create an EcoSpot'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.event_note,
                  title: 'Schedule Collection',
                  color: Colors.blue,
                  onTap: () {
                    // Navigate to Collection Events tab
                    setState(() {
                      _selectedIndex = 2; // Collection Events tab index
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Tap "New Event" to schedule a collection',
                        ),
                        backgroundColor: Colors.blue,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.people_outline,
                  title: 'Recruit Volunteers',
                  color: Colors.orange,
                  onTap: () {
                    // Navigate to Members tab
                    setState(() {
                      _selectedIndex = 3; // Members tab index
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invite members to join your group'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.store,
                  title: 'Market',
                  color: Colors.purple,
                  onTap: () {
                    _showMarketOverlay();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.analytics,
                  title: 'Analytics',
                  color: Colors.indigo,
                  onTap: () {
                    _showAnalyticsOverlay();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(), // Empty space for symmetry
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recent Activity
          Text(
            'Recent Activity',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<Group?>(
            future: _groupAuthService.getCurrentUserGroup(),
            builder: (context, groupSnapshot) {
              if (!groupSnapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final group = groupSnapshot.data!;
              return FutureBuilder<List<Map<String, dynamic>>>(
                future: _getRecentActivities(group),
                builder: (context, activitiesSnapshot) {
                  if (!activitiesSnapshot.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final activities = activitiesSnapshot.data!;

                  if (activities.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.history,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No recent activity',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Activity will appear here as your group grows',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: activities.map((activity) {
                      return _buildActivityCard(
                        icon: activity['icon'] as IconData,
                        title: activity['title'] as String,
                        subtitle: activity['subtitle'] as String,
                        color: activity['color'] as Color,
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEcoSpotsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Managed EcoSpots',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  // Get current group first
                  final group = await _groupAuthService.getCurrentUserGroup();
                  if (group != null && mounted) {
                    _showCreateEcoSpotDialog(group);
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please create or join a group first'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('New EcoSpot'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Location Section
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Your Location',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const Spacer(),
                      if (!_isLoadingLocation)
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _getCurrentLocation,
                          tooltip: 'Refresh location',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingLocation)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_locationError.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _locationError,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Tip: For web, allow location access in your browser settings.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else if (_currentPosition != null && _currentAddress != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.place,
                                    size: 20,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _currentAddress!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}, '
                                'Long: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _getCurrentLocation,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Get Current Location'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // EcoSpots List
          FutureBuilder<Group?>(
            future: _groupAuthService.getCurrentUserGroup(),
            builder: (context, groupSnapshot) {
              if (groupSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (!groupSnapshot.hasData || groupSnapshot.data == null) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Please create or join a group first'),
                  ),
                );
              }

              final group = groupSnapshot.data!;

              return FutureBuilder<List<EcoSpot>>(
                future: EcoSpotService.getEcoSpotsByGroup(group.id),
                builder: (context, ecoSpotSnapshot) {
                  if (ecoSpotSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (ecoSpotSnapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error loading EcoSpots: ${ecoSpotSnapshot.error}',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final ecoSpots = ecoSpotSnapshot.data ?? [];

                  if (ecoSpots.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.eco, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No EcoSpots yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create your first EcoSpot to get started',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: ecoSpots.map((ecoSpot) {
                      return _buildEcoSpotCard(ecoSpot);
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionEventsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Collection Events',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  // Handle create collection event
                },
                icon: const Icon(Icons.add),
                label: const Text('New Event'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Upcoming Collection Events
          _buildSectionHeader('Upcoming Collections', Icons.schedule),
          _buildCollectionEventCard(
            'Downtown Neighborhood Cleanup',
            'Oct 25, 2024 • 9:00 AM',
            'Central Park Area',
            '45 registered',
            'upcoming',
            Colors.green,
          ),
          _buildCollectionEventCard(
            'Beach Waste Collection Drive',
            'Nov 2, 2024 • 7:00 AM',
            'Coastal Zone',
            '78 registered',
            'upcoming',
            Colors.blue,
          ),
          _buildCollectionEventCard(
            'Community Recycling Day',
            'Nov 15, 2024 • 2:00 PM',
            'Community Center',
            '32 registered',
            'upcoming',
            Colors.orange,
          ),

          const SizedBox(height: 24),

          // Past Collection Events
          _buildSectionHeader('Completed Collections', Icons.history),
          _buildCollectionEventCard(
            'School Recycling Campaign',
            'Oct 10, 2024',
            'Education District',
            '120 participated',
            'completed',
            Colors.grey,
          ),
          _buildCollectionEventCard(
            'Monthly Waste Sorting',
            'Sep 20, 2024',
            'Town Square',
            '89 participated',
            'completed',
            Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    return FutureBuilder<Group?>(
      future: _groupAuthService.getCurrentUserGroup(),
      builder: (context, groupSnapshot) {
        if (groupSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!groupSnapshot.hasData || groupSnapshot.data == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.group_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No group found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please create or join a group first',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        final group = groupSnapshot.data!;
        final activeMembers = group.members.where((m) => m.isActive).toList();
        final inactiveMembers = group.members
            .where((m) => !m.isActive)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Member Management',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  FutureBuilder<bool>(
                    future: _groupAuthService.hasPermission('add_members'),
                    builder: (context, permSnapshot) {
                      if (permSnapshot.data == true) {
                        return TextButton.icon(
                          onPressed: () {
                            _showAddMembersDialog(group);
                          },
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add Member'),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Member Statistics Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        Icons.people,
                        'Total Members',
                        '${group.members.length}',
                        Colors.blue,
                      ),
                      _buildStatItem(
                        Icons.check_circle,
                        'Active',
                        '${activeMembers.length}',
                        Colors.green,
                      ),
                      _buildStatItem(
                        Icons.cancel,
                        'Inactive',
                        '${inactiveMembers.length}',
                        Colors.orange,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Active Members Section
              if (activeMembers.isNotEmpty) ...[
                _buildSectionHeader(
                  'Active Members (${activeMembers.length})',
                  Icons.people,
                ),
                const SizedBox(height: 12),
                ...activeMembers.map(
                  (member) => _buildRealMemberCard(member, group),
                ),
                const SizedBox(height: 24),
              ],

              // Inactive Members Section
              if (inactiveMembers.isNotEmpty) ...[
                _buildSectionHeader(
                  'Inactive Members (${inactiveMembers.length})',
                  Icons.people_outline,
                ),
                const SizedBox(height: 12),
                ...inactiveMembers.map(
                  (member) => _buildRealMemberCard(member, group),
                ),
              ],

              // Empty state
              if (group.members.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.person_add,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No members yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add members to start building your team',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildRealMemberCard(GroupMember member, Group group) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: member.isActive ? AppColors.primary : Colors.grey,
          child: Text(
            member.name.isNotEmpty ? member.name[0].toUpperCase() : 'U',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                member.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (!member.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Inactive',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              member.email,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.badge, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  member.roleDisplayName,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  'Joined ${_formatDate(member.joinedAt)}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        trailing: FutureBuilder<bool>(
          future: _groupAuthService.hasPermission('remove_members'),
          builder: (context, snapshot) {
            if (snapshot.data == true && member.role != MemberRole.leader) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'remove') {
                    _showRemoveMemberDialog(group, member);
                  } else if (value == 'toggle_status') {
                    _toggleMemberStatus(group, member);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'toggle_status',
                    child: Row(
                      children: [
                        Icon(
                          member.isActive ? Icons.block : Icons.check_circle,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(member.isActive ? 'Deactivate' : 'Activate'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Remove', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 1) {
      return 'Today';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else {
      return '${(difference.inDays / 365).floor()}y ago';
    }
  }

  Future<void> _toggleMemberStatus(Group group, GroupMember member) async {
    try {
      await GroupService.updateMember(
        group.id,
        member.userId,
        isActive: !member.isActive,
      );

      if (mounted) {
        setState(() {}); // Refresh the UI
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Member ${member.isActive ? "deactivated" : "activated"} successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update member status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showRemoveMemberDialog(Group group, GroupMember member) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Are you sure you want to remove ${member.name} from the group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await GroupService.removeMember(group.id, member.userId);
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {}); // Refresh the UI
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Member removed successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to remove member: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab(User? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group Profile',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),

          // Current Member Display
          FutureBuilder<MemberRole?>(
            future: _groupAuthService.getCurrentUserRole(),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.hasData) {
                return Card(
                  color: AppColors.primary.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary,
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Current Access Role',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _getRoleDisplayName(roleSnapshot.data!),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final group = await _groupAuthService
                                .getCurrentUserGroup();
                            if (group != null && mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      MemberSelectionScreen(group: group),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Switch Role'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          const SizedBox(height: 16),

          // Group Status Card
          FutureBuilder<Group?>(
            future: _groupAuthService.getCurrentUserGroup(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Card(
                  color: AppColors.error.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error loading group information: ${snapshot.error}',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                );
              }

              final group = snapshot.data;

              if (group == null) {
                return _buildCreateGroupCard();
              }

              return _buildGroupInfoCard(group);
            },
          ),

          const SizedBox(height: 24),

          // Leader Profile
          _buildLeaderProfileCard(user),
        ],
      ),
    );
  }

  Widget _buildCreateGroupCard() {
    return Card(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.group_add, size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text(
              'Create Your Group',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Start your environmental journey by creating and registering your group.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.secondaryText, fontSize: 14),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GroupCreationScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Create Group',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupInfoCard(Group group) {
    return Card(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.groupName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Created ${_formatDate(group.createdAt)}',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(group.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    group.statusDisplayName,
                    style: TextStyle(
                      color: _getStatusColor(group.status),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Progress Bar
            Text(
              'Profile Completion: ${group.profileCompletionPercentage}%',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: group.profileCompletionPercentage / 100,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),

            const SizedBox(height: 16),

            // Group Details
            _buildDetailRow('Description', group.groupDetails),
            if (group.location != null)
              _buildDetailRow('Location', group.location!),
            if (group.contactNumber != null)
              _buildDetailRow('Contact', group.contactNumber!),
            _buildDetailRow(
              'Members',
              '${group.activeMembersCount}/${group.maxMembers}',
            ),
            _buildDetailRow('Focus Areas', group.focusAreas.join(', ')),
            _buildDetailRow(
              'Verification Status',
              group.verificationStatusDisplayName,
            ),

            const SizedBox(height: 16),

            // Members Section
            if (group.members.isNotEmpty) ...[
              const Text(
                'Group Members',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  children: group.members.map((member) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              member.name.isNotEmpty
                                  ? member.name[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  member.roleDisplayName,
                                  style: TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!member.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Inactive',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _showEditGroupDialog(group);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Details'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Add Members Button (only visible to authorized members)
            FutureBuilder<bool>(
              future: _groupAuthService.hasPermission('add_members'),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return Column(
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _showAddMembersDialog(group);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(
                            Icons.person_add,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Add Members',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            if (group.rejectionReason != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Rejection Reason',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(group.rejectionReason!),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderProfileCard(User? user) {
    return Card(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leader Profile',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    (user?.displayName?.isNotEmpty == true)
                        ? user!.displayName![0].toUpperCase()
                        : 'G',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? 'Group',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Group',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(GroupStatus status) {
    switch (status) {
      case GroupStatus.pending:
        return Colors.orange;
      case GroupStatus.approved:
        return AppColors.success;
      case GroupStatus.rejected:
        return AppColors.error;
      case GroupStatus.suspended:
        return Colors.red;
    }
  }

  void _showEditGroupDialog(Group group) {
    // TODO: Implement edit group functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit group functionality coming soon!')),
    );
  }

  void _showCreateEcoSpotDialog(Group group) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    final TextEditingController locationController = TextEditingController();
    final TextEditingController contactController = TextEditingController();
    final TextEditingController hoursController = TextEditingController();

    EcoSpotType selectedType = EcoSpotType.collectionPoint;
    List<String> selectedMaterials = [];

    final List<String> availableMaterials = [
      'Plastic',
      'Paper',
      'Glass',
      'Metal',
      'Electronics',
      'Organic Waste',
      'Textiles',
      'Batteries',
    ];

    // Pre-fill location if available
    if (_currentAddress != null) {
      locationController.text = _currentAddress!;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create New EcoSpot'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name Field
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'EcoSpot Name *',
                      hintText: 'e.g., Downtown Recycling Hub',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description Field
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description *',
                      hintText: 'Describe this EcoSpot...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location Field
                  TextField(
                    controller: locationController,
                    decoration: InputDecoration(
                      labelText: 'Location *',
                      hintText: 'Enter address or location',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.location_on),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.my_location),
                        onPressed: () {
                          if (_currentAddress != null) {
                            locationController.text = _currentAddress!;
                          } else {
                            _getCurrentLocation();
                          }
                        },
                        tooltip: 'Use current location',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Type Dropdown
                  DropdownButtonFormField<EcoSpotType>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'EcoSpot Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: EcoSpotType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(_getEcoSpotTypeDisplay(type)),
                      );
                    }).toList(),
                    onChanged: (EcoSpotType? newType) {
                      if (newType != null) {
                        setState(() {
                          selectedType = newType;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Accepted Materials
                  const Text(
                    'Accepted Materials',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableMaterials.map((material) {
                      final isSelected = selectedMaterials.contains(material);
                      return FilterChip(
                        label: Text(material),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              selectedMaterials.add(material);
                            } else {
                              selectedMaterials.remove(material);
                            }
                          });
                        },
                        selectedColor: AppColors.primary.withOpacity(0.3),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Contact Number
                  TextField(
                    controller: contactController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact Number (Optional)',
                      hintText: 'Phone number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Operating Hours
                  TextField(
                    controller: hoursController,
                    decoration: const InputDecoration(
                      labelText: 'Operating Hours (Optional)',
                      hintText: 'e.g., Mon-Fri: 9AM-5PM',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.access_time),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                // Validate required fields
                if (nameController.text.trim().isEmpty ||
                    descriptionController.text.trim().isEmpty ||
                    locationController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in all required fields'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                try {
                  // Show loading
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Creating EcoSpot...'),
                        ],
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );

                  // Create EcoSpot
                  await EcoSpotService.createEcoSpot(
                    name: nameController.text.trim(),
                    description: descriptionController.text.trim(),
                    location: locationController.text.trim(),
                    latitude: _currentPosition?.latitude,
                    longitude: _currentPosition?.longitude,
                    groupId: group.id,
                    groupName: group.groupName,
                    type: selectedType,
                    acceptedMaterials: selectedMaterials,
                    contactNumber: contactController.text.trim().isEmpty
                        ? null
                        : contactController.text.trim(),
                    operatingHours: hoursController.text.trim().isEmpty
                        ? null
                        : hoursController.text.trim(),
                  );

                  if (mounted) {
                    setState(() {}); // Refresh the UI
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('EcoSpot created successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to create EcoSpot: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Create',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecordWeightDialog(Group group) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Get user profile for name
    String userName = 'Unknown User';
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        userName = userDoc.data()?['displayName'] ?? 'Unknown User';
      }
    } catch (e) {
      // Use email if display name not available
      userName = user.email ?? 'Unknown User';
    }

    // Get list of EcoSpots for this group
    List<EcoSpot> ecoSpots = [];
    try {
      ecoSpots = await EcoSpotService.getEcoSpotsByGroup(group.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load EcoSpots: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (ecoSpots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please create an EcoSpot first before recording weight data',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final weightController = TextEditingController();
    final notesController = TextEditingController();
    EcoSpot? selectedEcoSpot = ecoSpots.first;
    wr.MaterialType selectedMaterial = wr.MaterialType.mixed;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Weight Data'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // EcoSpot Selection
                const Text(
                  'Select EcoSpot',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<EcoSpot>(
                  value: selectedEcoSpot,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: ecoSpots.map((ecoSpot) {
                    return DropdownMenuItem(
                      value: ecoSpot,
                      child: Text(ecoSpot.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedEcoSpot = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Material Type Selection
                const Text(
                  'Material Type',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<wr.MaterialType>(
                  value: selectedMaterial,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: wr.MaterialType.values.map((material) {
                    return DropdownMenuItem(
                      value: material,
                      child: Row(
                        children: [
                          Text(
                            material.icon,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 8),
                          Text(material.displayName),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedMaterial = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Weight Input
                const Text(
                  'Weight (kg)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter weight in kilograms',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixText: 'kg',
                  ),
                ),
                const SizedBox(height: 16),

                // Notes (Optional)
                const Text(
                  'Notes (Optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Add any additional notes...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
            ElevatedButton.icon(
              onPressed: () async {
                // Validate weight input
                final weightText = weightController.text.trim();
                if (weightText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter weight'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final weight = double.tryParse(weightText);
                // Validate weight with minimum threshold of 0.01 kg (10 grams)
                if (weight == null || weight < 0.01) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please enter a valid weight (minimum 0.01 kg)',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (selectedEcoSpot == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select an EcoSpot'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  // Show loading
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Recording weight data...'),
                        ],
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );

                  // Create weight record
                  final weightRecord = wr.WeightRecord(
                    id: '',
                    groupId: group.id,
                    ecoSpotId: selectedEcoSpot!.id,
                    ecoSpotName: selectedEcoSpot!.name,
                    materialType: selectedMaterial,
                    weightInKg: weight,
                    notes: notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                    recordedBy: user.uid,
                    recordedByName: userName,
                    recordedAt: DateTime.now(),
                  );

                  await WeightRecordService().createWeightRecord(weightRecord);

                  if (mounted) {
                    setState(() {}); // Refresh the UI
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Weight data recorded successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to record weight: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text(
                'Record',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getEcoSpotTypeDisplay(EcoSpotType type) {
    switch (type) {
      case EcoSpotType.recyclingCenter:
        return 'Recycling Center';
      case EcoSpotType.collectionPoint:
        return 'Collection Point';
      case EcoSpotType.dropOffLocation:
        return 'Drop-off Location';
      case EcoSpotType.communityCenter:
        return 'Community Center';
      case EcoSpotType.beachCleanup:
        return 'Beach Cleanup';
      case EcoSpotType.other:
        return 'Other';
    }
  }

  void _showAddMembersDialog(Group group) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    MemberRole selectedRole = MemberRole.member;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Member Name',
                    hintText: 'Enter member\'s full name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter member\'s email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<MemberRole>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: MemberRole.values.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(
                        role.toString().split('.').last.toUpperCase(),
                      ),
                    );
                  }).toList(),
                  onChanged: (MemberRole? newRole) {
                    if (newRole != null) {
                      setState(() {
                        selectedRole = newRole;
                      });
                    }
                  },
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
                if (nameController.text.trim().isEmpty ||
                    emailController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill in all fields')),
                  );
                  return;
                }

                try {
                  // For now, we'll use a placeholder userId since we don't have
                  // user registration integrated yet
                  final String memberId = emailController.text.trim();

                  await GroupService.addMember(
                    group.id,
                    memberId,
                    nameController.text.trim(),
                    emailController.text.trim(),
                    role: selectedRole,
                  );

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${nameController.text.trim()} added as ${selectedRole.toString().split('.').last}',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to add member: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text(
                'Add Member',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.group_add, color: Colors.green),
              title: const Text('Create New Group'),
              onTap: () {
                Navigator.pop(context);
                // Handle create group
              },
            ),
            ListTile(
              leading: const Icon(Icons.event, color: Colors.orange),
              title: const Text('Plan New Event'),
              onTap: () {
                Navigator.pop(context);
                // Handle create event
              },
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Colors.blue),
              title: const Text('Invite Members'),
              onTap: () {
                Navigator.pop(context);
                // Handle invite members
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMarketOverlay() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recycled Materials Market',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildMarketContent()),
          ],
        ),
      ),
    );
  }

  void _showAnalyticsOverlay() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Waste Management Analytics',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildAnalyticsContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Market Stats
          Card(
            color: AppColors.background,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMarketStatCard(
                      'Total Sales',
                      '\$2,340',
                      Icons.monetization_on,
                      AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMarketStatCard(
                      'Products Listed',
                      '23',
                      Icons.inventory,
                      AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMarketStatCard(
                      'Active Orders',
                      '8',
                      Icons.shopping_cart,
                      AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Product Categories
          const Text(
            'Product Categories',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildCategoryCard(
                  'Plastic Items',
                  '12 products',
                  Icons.recycling,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCategoryCard(
                  'Paper Crafts',
                  '8 products',
                  Icons.article,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCategoryCard(
                  'Metal Art',
                  '3 products',
                  Icons.build,
                  Colors.grey,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Featured Products
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Products',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () {
                  _showAddProductDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _buildProductCard(
            'Recycled Plastic Planters',
            '\$25.00',
            '5 available',
            'Made from plastic bottles and containers',
            Icons.local_florist,
            Colors.green,
            'active',
          ),
          _buildProductCard(
            'Upcycled Paper Notebooks',
            '\$12.00',
            '15 available',
            'Handmade notebooks from recycled paper',
            Icons.book,
            Colors.brown,
            'active',
          ),
          _buildProductCard(
            'Glass Bottle Vases',
            '\$18.00',
            '8 available',
            'Beautiful vases from recycled glass bottles',
            Icons.local_florist,
            Colors.blue,
            'active',
          ),

          const SizedBox(height: 24),

          // Recent Orders
          const Text(
            'Recent Orders',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          _buildOrderCard(
            'Order #ORD-2024-001',
            'Recycled Plastic Planters x2',
            '\$50.00',
            'John Smith',
            'pending',
            Colors.orange,
          ),
          _buildOrderCard(
            'Order #ORD-2024-002',
            'Upcycled Paper Notebooks x5',
            '\$60.00',
            'Maria Garcia',
            'delivered',
            Colors.green,
          ),
          _buildOrderCard(
            'Order #ORD-2024-003',
            'Glass Bottle Vases x3',
            '\$54.00',
            'David Johnson',
            'processing',
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsContent() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please log in to view analytics'));
    }

    return FutureBuilder<Group?>(
      future: _groupAuthService.getCurrentUserGroup(),
      builder: (context, groupSnapshot) {
        if (!groupSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final group = groupSnapshot.data!;
        final weightService = WeightRecordService();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showRecordWeightDialog(group),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'Record Weight Data',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Statistics
              FutureBuilder<Map<String, dynamic>>(
                future: weightService.getGroupStatistics(group.id),
                builder: (context, statsSnapshot) {
                  if (!statsSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final stats = statsSnapshot.data!;
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              'Total Weight',
                              '${stats['totalWeight'].toStringAsFixed(1)} kg',
                              Icons.scale,
                              Colors.green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              'This Month',
                              '${stats['thisMonthWeight'].toStringAsFixed(1)} kg',
                              Icons.calendar_today,
                              Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              'Total Records',
                              '${stats['totalRecords']}',
                              Icons.receipt_long,
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              'Avg Weight',
                              '${stats['averageWeight'].toStringAsFixed(1)} kg',
                              Icons.analytics,
                              Colors.purple,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Material Breakdown
              FutureBuilder<Map<wr.MaterialType, double>>(
                future: weightService.getTotalWeightByMaterial(group.id),
                builder: (context, materialSnapshot) {
                  if (!materialSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }

                  final materialTotals = materialSnapshot.data!;
                  if (materialTotals.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Material Breakdown',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...materialTotals.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Text(
                                    entry.key.icon,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.key.displayName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(
                                          value:
                                              entry.value /
                                              materialTotals.values.reduce(
                                                (a, b) => a > b ? a : b,
                                              ),
                                          backgroundColor: Colors.grey[200],
                                          color: AppColors.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${entry.value.toStringAsFixed(1)} kg',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Recent Records
              FutureBuilder<List<wr.WeightRecord>>(
                future: weightService.getRecentWeightRecords(group.id, 10),
                builder: (context, recordsSnapshot) {
                  if (!recordsSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final records = recordsSnapshot.data!;
                  if (records.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.scale,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No weight records yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Click "Record Weight Data" to add your first record',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recent Records',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...records.map((record) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      record.materialType.icon,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          record.materialType.displayName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          record.ecoSpotName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${record.recordedAt.day}/${record.recordedAt.month}/${record.recordedAt.year} • ${record.recordedByName}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${record.weightInKg} kg',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.green),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildEcoSpotCard(EcoSpot ecoSpot) {
    Color statusColor;
    switch (ecoSpot.status) {
      case EcoSpotStatus.active:
        statusColor = Colors.green;
        break;
      case EcoSpotStatus.inactive:
        statusColor = Colors.grey;
        break;
      case EcoSpotStatus.pending:
        statusColor = Colors.orange;
        break;
      case EcoSpotStatus.suspended:
        statusColor = Colors.red;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _showEcoSpotDetails(ecoSpot);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.1),
                    child: Icon(Icons.eco, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ecoSpot.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ecoSpot.typeDisplayName,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      ecoSpot.statusDisplayName,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      ecoSpot.location,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
              if (ecoSpot.acceptedMaterials.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      ecoSpot.acceptedMaterials.take(3).map((material) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            material,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList()..addAll(
                        ecoSpot.acceptedMaterials.length > 3
                            ? [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    '+${ecoSpot.acceptedMaterials.length - 3} more',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ]
                            : [],
                      ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.recycling, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${ecoSpot.collectionCount} collections',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, size: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEcoSpotDetails(EcoSpot ecoSpot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ecoSpot.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildEcoSpotDetailRow(
                Icons.category,
                'Type',
                ecoSpot.typeDisplayName,
              ),
              _buildEcoSpotDetailRow(
                Icons.location_on,
                'Location',
                ecoSpot.location,
              ),
              if (ecoSpot.description.isNotEmpty)
                _buildEcoSpotDetailRow(
                  Icons.description,
                  'Description',
                  ecoSpot.description,
                ),
              if (ecoSpot.contactNumber != null)
                _buildEcoSpotDetailRow(
                  Icons.phone,
                  'Contact',
                  ecoSpot.contactNumber!,
                ),
              if (ecoSpot.operatingHours != null)
                _buildEcoSpotDetailRow(
                  Icons.access_time,
                  'Hours',
                  ecoSpot.operatingHours!,
                ),
              if (ecoSpot.acceptedMaterials.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Accepted Materials:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ecoSpot.acceptedMaterials.map((material) {
                    return Chip(
                      label: Text(material),
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              _buildEcoSpotDetailRow(
                Icons.recycling,
                'Collections',
                '${ecoSpot.collectionCount}',
              ),
              _buildEcoSpotDetailRow(
                Icons.verified,
                'Status',
                ecoSpot.statusDisplayName,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (ecoSpot.status == EcoSpotStatus.active)
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await EcoSpotService.incrementCollectionCount(ecoSpot.id);
                  Navigator.pop(context);
                  setState(() {}); // Refresh the UI
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Collection recorded!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.add_circle, color: Colors.white),
              label: const Text(
                'Record Collection',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEcoSpotDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupManagementCard(
    String name,
    String category,
    int members,
    bool isActive,
    Color color,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(Icons.group, color: color),
        ),
        title: Text(name),
        subtitle: Text('$category • $members members'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isActive ? 'Active' : 'Pending',
                style: TextStyle(
                  color: isActive ? Colors.green : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
        onTap: () {
          // Handle group management
        },
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionEventCard(
    String title,
    String dateTime,
    String location,
    String participants,
    String status,
    Color color,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(dateTime, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(location, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.people, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(participants, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          title,
          style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCategoryCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Card(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            Text(
              subtitle,
              style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(
    String name,
    String price,
    String availability,
    String description,
    IconData icon,
    Color color,
    String status,
  ) {
    return Card(
      color: AppColors.background,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: status == 'active'
                              ? AppColors.success.withOpacity(0.1)
                              : AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status == 'active' ? 'Available' : 'Sold Out',
                          style: TextStyle(
                            color: status == 'active'
                                ? AppColors.success
                                : AppColors.error,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        price,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        availability,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(
    String orderNumber,
    String productInfo,
    String amount,
    String customer,
    String status,
    Color statusColor,
  ) {
    return Card(
      color: AppColors.background,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.shopping_bag, color: statusColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        orderNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    productInfo,
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Customer: $customer',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        amount,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Product'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Product Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Price (\$)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // TODO: Implement add product functionality
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Product added successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Add Product'),
            ),
          ],
        );
      },
    );
  }

  String _getRoleDisplayName(MemberRole role) {
    switch (role) {
      case MemberRole.leader:
        return 'Group';
      case MemberRole.chair:
        return 'Chairperson';
      case MemberRole.secretary:
        return 'Secretary';
      case MemberRole.treasurer:
        return 'Treasurer';
      case MemberRole.member:
        return 'Member';
    }
  }
}
