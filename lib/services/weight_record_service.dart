import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/weight_record.dart';

class WeightRecordService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new weight record
  Future<String> createWeightRecord(WeightRecord record) async {
    try {
      final docRef = await _firestore
          .collection('weight_records')
          .add(record.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create weight record: $e');
    }
  }

  // Get all weight records for a group
  Future<List<WeightRecord>> getWeightRecordsByGroup(String groupId) async {
    try {
      final snapshot = await _firestore
          .collection('weight_records')
          .where('groupId', isEqualTo: groupId)
          .get();

      final records = snapshot.docs
          .map((doc) => WeightRecord.fromMap(doc.data(), doc.id))
          .toList();

      // Sort by date descending (most recent first)
      records.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

      return records;
    } catch (e) {
      throw Exception('Failed to fetch weight records: $e');
    }
  }

  // Get weight records for a specific EcoSpot
  Future<List<WeightRecord>> getWeightRecordsByEcoSpot(String ecoSpotId) async {
    try {
      final snapshot = await _firestore
          .collection('weight_records')
          .where('ecoSpotId', isEqualTo: ecoSpotId)
          .get();

      final records = snapshot.docs
          .map((doc) => WeightRecord.fromMap(doc.data(), doc.id))
          .toList();

      // Sort by date descending
      records.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

      return records;
    } catch (e) {
      throw Exception('Failed to fetch EcoSpot weight records: $e');
    }
  }

  // Get weight records by material type
  Future<List<WeightRecord>> getWeightRecordsByMaterial(
    String groupId,
    MaterialType materialType,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('weight_records')
          .where('groupId', isEqualTo: groupId)
          .where(
            'materialType',
            isEqualTo: materialType.toString().split('.').last,
          )
          .get();

      final records = snapshot.docs
          .map((doc) => WeightRecord.fromMap(doc.data(), doc.id))
          .toList();

      // Sort by date descending
      records.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

      return records;
    } catch (e) {
      throw Exception('Failed to fetch material weight records: $e');
    }
  }

  // Get total weight by material type for a group (optimized)
  Future<Map<MaterialType, double>> getTotalWeightByMaterial(
    String groupId,
  ) async {
    try {
      // Fetch records with server-side filtering
      final snapshot = await _firestore
          .collection('weight_records')
          .where('groupId', isEqualTo: groupId)
          .get();

      final Map<MaterialType, double> totals = {};

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          final materialTypeStr = data['materialType'] as String?;
          final weightInKg = (data['weightInKg'] ?? 0).toDouble();

          if (materialTypeStr != null) {
            final materialType = MaterialType.values.firstWhere(
              (e) => e.name == materialTypeStr,
              orElse: () => MaterialType.mixed,
            );
            totals[materialType] = (totals[materialType] ?? 0) + weightInKg;
          }
        } catch (e) {
          debugPrint('Error processing weight record ${doc.id}: $e');
          continue;
        }
      }

      return totals;
    } catch (e) {
      throw Exception('Failed to calculate material totals: $e');
    }
  }

  // Get total weight for a time period (optimized with server-side filtering)
  Future<double> getTotalWeightForPeriod(
    String groupId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // Use Firestore range queries for better performance
      final snapshot = await _firestore
          .collection('weight_records')
          .where('groupId', isEqualTo: groupId)
          .where(
            'recordedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where('recordedAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      double total = 0;
      for (var doc in snapshot.docs) {
        final weightInKg = (doc.data()['weightInKg'] ?? 0).toDouble();
        total += weightInKg;
      }

      return total;
    } catch (e) {
      // Fallback to client-side filtering if Firestore composite index is not available
      debugPrint(
        'Using client-side filtering (create composite index for better performance): $e',
      );
      final records = await getWeightRecordsByGroup(groupId);

      final filteredRecords = records
          .where(
            (record) =>
                !record.recordedAt.isBefore(startDate) &&
                !record.recordedAt.isAfter(endDate),
          )
          .toList();

      double total = 0;
      for (var record in filteredRecords) {
        total += record.weightInKg;
      }

      return total;
    }
  }

  // Get recent weight records (last N records)
  Future<List<WeightRecord>> getRecentWeightRecords(
    String groupId,
    int limit,
  ) async {
    try {
      final records = await getWeightRecordsByGroup(groupId);
      return records.take(limit).toList();
    } catch (e) {
      throw Exception('Failed to fetch recent records: $e');
    }
  }

  // Update a weight record
  Future<void> updateWeightRecord(
    String recordId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _firestore
          .collection('weight_records')
          .doc(recordId)
          .update(updates);
    } catch (e) {
      throw Exception('Failed to update weight record: $e');
    }
  }

  // Delete a weight record
  Future<void> deleteWeightRecord(String recordId) async {
    try {
      await _firestore.collection('weight_records').doc(recordId).delete();
    } catch (e) {
      throw Exception('Failed to delete weight record: $e');
    }
  }

  // Get statistics for the group
  Future<Map<String, dynamic>> getGroupStatistics(String groupId) async {
    try {
      final records = await getWeightRecordsByGroup(groupId);

      if (records.isEmpty) {
        return {
          'totalWeight': 0.0,
          'totalRecords': 0,
          'averageWeight': 0.0,
          'mostCommonMaterial': MaterialType.mixed,
          'thisMonthWeight': 0.0,
        };
      }

      double totalWeight = 0;
      Map<MaterialType, int> materialCounts = {};

      for (var record in records) {
        totalWeight += record.weightInKg;
        materialCounts[record.materialType] =
            (materialCounts[record.materialType] ?? 0) + 1;
      }

      // Find most common material
      MaterialType mostCommon = MaterialType.mixed;
      int maxCount = 0;
      materialCounts.forEach((material, count) {
        if (count > maxCount) {
          maxCount = count;
          mostCommon = material;
        }
      });

      // Calculate this month's weight
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final thisMonthRecords = records
          .where((r) => r.recordedAt.isAfter(startOfMonth))
          .toList();

      double thisMonthWeight = 0;
      for (var record in thisMonthRecords) {
        thisMonthWeight += record.weightInKg;
      }

      return {
        'totalWeight': totalWeight,
        'totalRecords': records.length,
        'averageWeight': totalWeight / records.length,
        'mostCommonMaterial': mostCommon,
        'thisMonthWeight': thisMonthWeight,
      };
    } catch (e) {
      throw Exception('Failed to calculate statistics: $e');
    }
  }
}
