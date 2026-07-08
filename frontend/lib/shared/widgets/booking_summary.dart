import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// BookingSummary displays a summary of a booking before confirmation.
///
/// For recurring round-trips, shows:
/// - Departure dates with their occurrences
/// - Return dates with their occurrences
/// - Total legs (departure + return legs)
/// - Seat count
/// - Total fare calculation: (departure_fare + return_fare) × leg_count × seat_count
///
/// Inputs:
/// - [ride]: The ride map containing fare, leg_type, is_round_trip, etc.
/// - [selectedOccurrenceIds]: List of selected departure occurrence IDs (for recurring rides)
/// - [returnOccurrenceIds]: List of selected return occurrence IDs (for round-trips)
/// - [seatsRequested]: Number of seats to book
/// - [includeReturnLeg]: Whether return leg is included (for round-trips)
/// - [onConfirm]: Callback when "Confirm Booking" is pressed
/// - [isLoading]: Whether the confirm action is in progress
/// - [departureOccurrences]: Optional list of departure occurrence maps with date/time info
/// - [returnOccurrences]: Optional list of return occurrence maps with date/time info
class BookingSummary extends StatelessWidget {
  final Map<String, dynamic> ride;
  final List<int> selectedOccurrenceIds;
  final List<int> returnOccurrenceIds;
  final int seatsRequested;
  final bool includeReturnLeg;
  final VoidCallback? onConfirm;
  final bool isLoading;
  final List<dynamic>? departureOccurrences;
  final List<dynamic>? returnOccurrences;

  const BookingSummary({
    super.key,
    required this.ride,
    required this.selectedOccurrenceIds,
    required this.returnOccurrenceIds,
    required this.seatsRequested,
    required this.includeReturnLeg,
    this.onConfirm,
    this.isLoading = false,
    this.departureOccurrences,
    this.returnOccurrences,
  });

  /// Extract fare from ride map (handle different possible field names)
  double _getFare(Map<String, dynamic> rideMap) {
    final fareValue = rideMap['fare'] ?? rideMap['price'] ?? 0;
    if (fareValue is num) return fareValue.toDouble();
    if (fareValue is String) return double.tryParse(fareValue) ?? 0.0;
    return 0.0;
  }

  /// Format a date string to a readable format
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      // Handle ISO format dates (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS)
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  /// Format a datetime string to show time
  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse(dateTimeStr);
      return DateFormat('h:mm a').format(dt);
    } catch (e) {
      return '--:--';
    }
  }

  /// Get unique dates from occurrence list
  List<String> _getUniqueDates(List<dynamic>? occurrences, List<int>? selectedIds) {
    if (occurrences == null || selectedIds == null) return [];
    
    final dates = <String>{};
    for (final occ in occurrences) {
      if (occ is Map) {
        final occId = occ['id'] ?? occ['occurrence_id'];
        if (selectedIds.contains(occId)) {
          final date = occ['occurrence_date']?.toString() ?? '';
          if (date.isNotEmpty) dates.add(date);
        }
      }
    }
    return dates.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final isRoundTrip = includeReturnLeg && returnOccurrenceIds.isNotEmpty;
    final depFare = _getFare(ride);
    
    // For round-trips, assume return fare is same as departure fare (or can be customized)
    final retFare = isRoundTrip ? depFare : 0.0;
    
    // Calculate leg count
    final depLegCount = selectedOccurrenceIds.length;
    final retLegCount = returnOccurrenceIds.length;
    final totalLegs = depLegCount + retLegCount;
    
    // Calculate total fare
    // Total = (departure_fare × seat_count × dep_leg_count) + (return_fare × seat_count × ret_leg_count)
    final depTotal = depFare * seatsRequested * depLegCount;
    final retTotal = retFare * seatsRequested * retLegCount;
    final totalFare = depTotal + retTotal;
    
    // Get unique dates
    final depDates = _getUniqueDates(departureOccurrences, selectedOccurrenceIds);
    final retDates = _getUniqueDates(returnOccurrences, returnOccurrenceIds);
    
    const navyColor = Color(0xFF0A2540);

    return SingleChildScrollView(
      child: Card(
        margin: const EdgeInsets.all(16),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Booking Summary',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: navyColor,
                    ),
              ),
              const SizedBox(height: 16),
              
              // Ride details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: navyColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pickup & destination
                    Row(
                      children: [
                        const Icon(Icons.my_location, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ride['pickup_location']?.toString() ?? 'Pickup',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ride['destination']?.toString() ?? 'Destination',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Departure leg dates
              if (depDates.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flight_takeoff, size: 18, color: navyColor),
                        const SizedBox(width: 8),
                        Text(
                          'Departure Legs ($depLegCount)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: navyColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...depDates.map((date) {
                      // Find occurrence with this date to get time
                      String time = '--:--';
                      if (departureOccurrences != null) {
                        for (final occ in departureOccurrences!) {
                          if (occ is Map && 
                              occ['occurrence_date']?.toString() == date &&
                              selectedOccurrenceIds.contains(occ['id'] ?? occ['occurrence_id'])) {
                            time = _formatTime(occ['departure_datetime']?.toString());
                            break;
                          }
                        }
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event, size: 14, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                _formatDate(date),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'at $time',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 12),
                  ],
                ),
              
              // Return leg dates
              if (isRoundTrip && retDates.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flight_land, size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          'Return Legs ($retLegCount)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...retDates.map((date) {
                      // Find occurrence with this date to get time
                      String time = '--:--';
                      if (returnOccurrences != null) {
                        for (final occ in returnOccurrences!) {
                          if (occ is Map && 
                              occ['occurrence_date']?.toString() == date &&
                              returnOccurrenceIds.contains(occ['id'] ?? occ['occurrence_id'])) {
                            time = _formatTime(occ['departure_datetime']?.toString());
                            break;
                          }
                        }
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event, size: 14, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                _formatDate(date),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'at $time',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 12),
                  ],
                ),
              
              const Divider(height: 24),
              
              // Cost breakdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Seat count
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Seats', style: TextStyle(fontSize: 14)),
                        Text(
                          '$seatsRequested seat${seatsRequested > 1 ? 's' : ''}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Total legs
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Legs', style: TextStyle(fontSize: 14)),
                        Text(
                          '$totalLegs leg${totalLegs > 1 ? 's' : ''}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Departure subtotal
                    if (depLegCount > 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Departure ($depLegCount × $seatsRequested × Rs${depFare.toStringAsFixed(0)})',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            'Rs ${depTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    
                    // Return subtotal
                    if (isRoundTrip && retLegCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Return ($retLegCount × $seatsRequested × Rs${retFare.toStringAsFixed(0)})',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            'Rs ${retTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              const Divider(height: 24),
              
              // Total fare
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Fare',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: navyColor,
                    ),
                  ),
                  Text(
                    'Rs ${totalFare.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: navyColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Confirm button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navyColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Confirm Booking',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
