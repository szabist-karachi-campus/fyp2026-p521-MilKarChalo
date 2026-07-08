import 'package:flutter/material.dart';

/// LegSelector displays a toggle for selecting which legs of a round-trip to include.
///
/// For round-trip rides, this widget allows passengers to choose between:
/// - Departure: Only the outbound leg
/// - Return: Only the return leg
/// - Both: Both departure and return legs (default)
///
/// Acceptance Criteria:
/// - Shows: Departure | Return | Both (radio buttons or toggle buttons)
/// - Enabled: Only if ride.is_round_trip == true
/// - Returns: bool include_return_leg via [onChanged] callback
/// - Default: Both if is_round_trip, else greyed out
///
/// Inputs:
/// - [isRoundTrip]: Whether the ride is a round-trip (enables/disables widget)
/// - [includeReturnLeg]: Current selection state
/// - [onChanged]: Callback fired when selection changes, passes the new include_return_leg bool
class LegSelector extends StatelessWidget {
  final bool isRoundTrip;
  final bool includeReturnLeg;
  final Function(bool)? onChanged;

  const LegSelector({
    super.key,
    required this.isRoundTrip,
    required this.includeReturnLeg,
    this.onChanged,
  });

  /// Determine which leg option is currently selected
  /// Returns: 'departure', 'return', or 'both'
  String _getCurrentSelection() {
    if (includeReturnLeg) {
      return 'both';
    } else {
      return 'departure';
    }
  }

  /// Handle leg selection change
  /// Updates includeReturnLeg based on selected leg
  void _onSelectionChanged(String? value) {
    if (value != null && onChanged != null) {
      // When 'both' is selected, includeReturnLeg = true
      // When 'departure' or 'return' is selected, includeReturnLeg = false
      final newIncludeReturnLeg = (value == 'both');
      onChanged!(newIncludeReturnLeg);
    }
  }

  @override
  Widget build(BuildContext context) {
    const navyColor = Color(0xFF0A2540);
    const disabledColor = Colors.grey;
    final currentSelection = _getCurrentSelection();
    final effectiveColor = isRoundTrip ? navyColor : disabledColor;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.airplanemode_active,
                  size: 20,
                  color: effectiveColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Trip Legs',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: effectiveColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Radio buttons or toggle for leg selection
            if (isRoundTrip)
              // Show radio button options when round-trip
              Column(
                children: [
                  // Departure option
                  _buildLegOption(
                    context,
                    value: 'departure',
                    label: 'Departure Only',
                    isSelected: currentSelection == 'departure',
                    onChanged: _onSelectionChanged,
                  ),
                  const SizedBox(height: 8),

                  // Return option
                  _buildLegOption(
                    context,
                    value: 'return',
                    label: 'Return Only',
                    isSelected: currentSelection == 'return',
                    onChanged: _onSelectionChanged,
                  ),
                  const SizedBox(height: 8),

                  // Both option (default)
                  _buildLegOption(
                    context,
                    value: 'both',
                    label: 'Both Legs (Recommended)',
                    isSelected: currentSelection == 'both',
                    onChanged: _onSelectionChanged,
                  ),
                ],
              )
            else
              // Show disabled state message when not a round-trip
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: disabledColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This ride is one-way only.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build a single leg selection option (radio button with label)
  Widget _buildLegOption(
    BuildContext context, {
    required String value,
    required String label,
    required bool isSelected,
    required Function(String?) onChanged,
  }) {
    const navyColor = Color(0xFF0A2540);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isRoundTrip ? () => onChanged(value) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: [
              // Radio button
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? navyColor : Colors.grey.shade400,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: navyColor,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Label
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? navyColor : Colors.grey.shade700,
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
