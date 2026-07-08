import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// OccurrenceSelector displays available occurrences as multi-select date pills.
///
/// Features:
/// - Shows occurrence date, available seats, and time for each occurrence
/// - Allows multi-select for recurring rides
/// - Highlights selected dates visually
/// - Shows seat availability count
/// - Returns array of selected occurrence IDs and occurrence data
///
/// Parameters:
/// - [occurrences]: List of occurrence maps with id, occurrence_date, departure_datetime, available_seats
/// - [selectedOccurrenceIds]: Currently selected occurrence IDs (for two-way binding)
/// - [onSelectionChanged]: Callback when selection changes, passes list of selected occurrence IDs
/// - [onOccurrencesDataChanged]: Optional callback to receive full occurrence data of selected items
/// - [maxSelectable]: Optional limit on how many occurrences can be selected (null = unlimited)
/// - [emptyMessage]: Message to show when no occurrences are available
class OccurrenceSelector extends StatefulWidget {
  final List<dynamic> occurrences;
  final List<int> selectedOccurrenceIds;
  final Function(List<int>) onSelectionChanged;
  final Function(List<dynamic>)? onOccurrencesDataChanged;
  final int? maxSelectable;
  final String emptyMessage;

  const OccurrenceSelector({
    super.key,
    required this.occurrences,
    required this.selectedOccurrenceIds,
    required this.onSelectionChanged,
    this.onOccurrencesDataChanged,
    this.maxSelectable,
    this.emptyMessage = 'No occurrences available',
  });

  @override
  State<OccurrenceSelector> createState() => _OccurrenceSelectorState();
}

class _OccurrenceSelectorState extends State<OccurrenceSelector> {
  late List<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.selectedOccurrenceIds);
  }

  @override
  void didUpdateWidget(OccurrenceSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedOccurrenceIds != widget.selectedOccurrenceIds) {
      _selectedIds = List.from(widget.selectedOccurrenceIds);
    }
  }

  /// Format a date string to readable format (e.g., "Mon, Jan 20")
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('EEE, MMM d').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  /// Format a datetime string to show time (e.g., "8:00 AM")
  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse(dateTimeStr);
      return DateFormat('h:mm a').format(dt);
    } catch (e) {
      return '--:--';
    }
  }

  /// Get occurrence ID from occurrence map (handle different field names)
  int _getOccurrenceId(dynamic occ) {
    if (occ is! Map) return 0;
    final id = occ['id'] ?? occ['occurrence_id'];
    if (id is int) return id;
    if (id is String) return int.tryParse(id) ?? 0;
    return 0;
  }

  /// Get available seats from occurrence map
  int _getAvailableSeats(dynamic occ) {
    if (occ is! Map) return 0;
    final seats = occ['available_seats'];
    if (seats is int) return seats;
    if (seats is String) return int.tryParse(seats) ?? 0;
    return 0;
  }

  /// Toggle selection of an occurrence
  void _toggleOccurrence(dynamic occurrence) {
    final occId = _getOccurrenceId(occurrence);
    if (occId == 0) return;

    setState(() {
      if (_selectedIds.contains(occId)) {
        _selectedIds.remove(occId);
      } else {
        // Check max selectable limit
        if (widget.maxSelectable != null && _selectedIds.length >= widget.maxSelectable!) {
          // Show snackbar indicating max reached
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot select more than ${widget.maxSelectable} occurrences'),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        _selectedIds.add(occId);
      }
    });

    // Notify parent of selection change
    widget.onSelectionChanged(_selectedIds);

    // If caller wants full occurrence data, provide it
    if (widget.onOccurrencesDataChanged != null) {
      final selectedOccurrences = widget.occurrences
          .where((occ) => _selectedIds.contains(_getOccurrenceId(occ)))
          .toList();
      widget.onOccurrencesDataChanged!(selectedOccurrences);
    }
  }

  /// Select all occurrences
  void _selectAll() {
    setState(() {
      _selectedIds = widget.occurrences
          .map((occ) => _getOccurrenceId(occ))
          .where((id) => id != 0)
          .toList();
      
      // Respect max selectable if set
      if (widget.maxSelectable != null && _selectedIds.length > widget.maxSelectable!) {
        _selectedIds = _selectedIds.take(widget.maxSelectable!).toList();
      }
    });

    widget.onSelectionChanged(_selectedIds);

    if (widget.onOccurrencesDataChanged != null) {
      final selectedOccurrences = widget.occurrences
          .where((occ) => _selectedIds.contains(_getOccurrenceId(occ)))
          .toList();
      widget.onOccurrencesDataChanged!(selectedOccurrences);
    }
  }

  /// Clear all selections
  void _clearAll() {
    setState(() {
      _selectedIds.clear();
    });
    widget.onSelectionChanged(_selectedIds);
    if (widget.onOccurrencesDataChanged != null) {
      widget.onOccurrencesDataChanged!([]);
    }
  }

  /// Build a single occurrence pill
  Widget _buildOccurrencePill(dynamic occurrence) {
    final occId = _getOccurrenceId(occurrence);
    final isSelected = _selectedIds.contains(occId);
    final availableSeats = _getAvailableSeats(occurrence);
    final date = occurrence['occurrence_date']?.toString() ?? '';
    final time = occurrence['departure_datetime']?.toString() ?? '';
    final isSoldOut = availableSeats <= 0;

    const navyColor = Color(0xFF0A2540);
    const selectedColor = Color(0xFF0066CC);
    const disabledColor = Colors.grey;

    return GestureDetector(
      onTap: isSoldOut ? null : () => _toggleOccurrence(occurrence),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSoldOut
              ? disabledColor.withValues(alpha: 0.1)
              : isSelected
                  ? selectedColor.withValues(alpha: 0.1)
                  : Colors.white,
          border: Border.all(
            color: isSoldOut
                ? disabledColor.withValues(alpha: 0.3)
                : isSelected
                    ? selectedColor
                    : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Date and selection indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected && !isSoldOut)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: selectedColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(date),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSoldOut ? disabledColor : navyColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(time),
                        style: TextStyle(
                          fontSize: 12,
                          color: isSoldOut ? disabledColor : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Seats availability
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSoldOut
                    ? Colors.red.shade50
                    : availableSeats <= 2
                        ? Colors.orange.shade50
                        : Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isSoldOut
                    ? 'Sold Out'
                    : '$availableSeats seat${availableSeats != 1 ? 's' : ''} left',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSoldOut
                      ? Colors.red
                      : availableSeats <= 2
                          ? Colors.orange
                          : Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.occurrences.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            widget.emptyMessage,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with selection info and quick actions
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Dates (${_selectedIds.length}/${widget.occurrences.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0A2540),
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _selectAll,
                    child: const Text(
                      'Select All',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _clearAll,
                    child: const Text(
                      'Clear',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Grid of date pills
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: widget.occurrences.length,
          itemBuilder: (context, index) {
            return _buildOccurrencePill(widget.occurrences[index]);
          },
        ),
      ],
    );
  }
}
