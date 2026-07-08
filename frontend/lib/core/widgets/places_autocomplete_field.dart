import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';

/// A text field with Google Places Autocomplete suggestions shown in an
/// inline list below the field — no overlay positioning required.
///
/// Usage:
/// ```dart
/// PlacesAutocompleteField(
///   controller: _pickupC,
///   hint: 'Where are you leaving from?',
///   prefixIcon: Icons.my_location,
///   onSelected: (description) { /* optional callback */ },
/// )
/// ```
class PlacesAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final Color accentColor;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSelected;

  const PlacesAutocompleteField({
    super.key,
    required this.controller,
    required this.hint,
    this.prefixIcon = Icons.location_on,
    this.accentColor = const Color(0xFF042D4A),
    this.validator,
    this.onSelected,
  });

  @override
  State<PlacesAutocompleteField> createState() =>
      _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  final _focusNode = FocusNode();

  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _loading = false;
  bool _showSuggestions = false;
  bool _suppressFetch = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Small delay so a tap on a suggestion registers before hiding
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _showSuggestions = false);
      });
    }
  }

  void _onTextChanged() {
    if (_suppressFetch) {
      _suppressFetch = false;
      return;
    }
    _debounce?.cancel();
    final text = widget.controller.text;
    if (text.trim().length < 2) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _showSuggestions = false;
          _loading = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetch(text));
  }

  Future<void> _fetch(String input) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Api.getPlaces(input);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
        _showSuggestions = results.isNotEmpty && _focusNode.hasFocus;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _showSuggestions = false; });
    }
  }

  void _onSuggestionTapped(String description) {
    _suppressFetch = true;
    widget.controller.text = description;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: description.length),
    );
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
    });
    _focusNode.unfocus();
    widget.onSelected?.call(description);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Text field ──────────────────────────────────────────────────────
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          validator: widget.validator,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: Icon(widget.prefixIcon, color: widget.accentColor),
            suffixIcon: _loading
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.accentColor,
                      ),
                    ),
                  )
                : widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _suppressFetch = true;
                          widget.controller.clear();
                          setState(() {
                            _suggestions = [];
                            _showSuggestions = false;
                          });
                        },
                      )
                    : null,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: widget.accentColor, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),

        // ── Suggestions dropdown ────────────────────────────────────────────
        if (_showSuggestions && _suggestions.isNotEmpty)
          Material(
            elevation: 6,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            color: Colors.white,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions.map((s) {
                  final desc = s['description']?.toString() ?? '';
                  final parts = desc.split(',');
                  final main = parts.first.trim();
                  final secondary = parts.length > 1
                      ? parts.skip(1).join(',').trim()
                      : '';

                  return InkWell(
                    onTap: () => _onSuggestionTapped(desc),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 18,
                                color: widget.accentColor
                                    .withValues(alpha: 0.65),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      main,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (secondary.isNotEmpty)
                                      Text(
                                        secondary,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (s != _suggestions.last)
                          Divider(
                              height: 1,
                              indent: 42,
                              color: Colors.grey.shade200),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}
