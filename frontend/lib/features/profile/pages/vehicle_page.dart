import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../router.dart';
import '../../../core/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VehiclePage extends StatefulWidget {
  const VehiclePage({super.key});

  @override
  State<VehiclePage> createState() => _VehiclePageState();
}

class _VehiclePageState extends State<VehiclePage> {
  final _formKey = GlobalKey<FormState>();

  String? _make;
  String? _model;
  final _colorC = TextEditingController();
  final _plateC = TextEditingController();
  final _seatsC = TextEditingController();

  bool _saving = false;

  static const _navy = Color(0xFF0A2540);

  // Make → Model map for Pakistani car market
  static const Map<String, List<String>> _makeModels = {
    'Suzuki': ['Alto', 'Cultus', 'Swift', 'Wagon R', 'Bolan', 'Ravi', 'Jimny', 'Ciaz'],
    'Toyota': ['Corolla', 'Yaris', 'Camry', 'Fortuner', 'Hilux', 'Prado', 'Land Cruiser', 'Prius'],
    'Honda': ['City', 'Civic', 'BR-V', 'HR-V', 'Accord', 'CR-V', 'Fit'],
    'Kia': ['Picanto', 'Stonic', 'Sportage', 'Sorento', 'Carnival', 'Stinger'],
    'Hyundai': ['Tucson', 'Elantra', 'Sonata', 'Santa Fe', 'Ioniq 5'],
    'Changan': ['Alsvin', 'Uni-T', 'Uni-V', 'M9', 'CS35 Plus'],
    'MG': ['HS', 'ZS', 'ZS EV', 'RX5', 'GT'],
    'Nissan': ['Sunny', 'Dayz', 'X-Trail', 'Patrol', 'Navara'],
    'Daihatsu': ['Mira', 'Move', 'Cuore', 'Hijet'],
    'Other': ['Other'],
  };

  static List<String> get _makes => _makeModels.keys.toList();

  List<String> get _modelsForMake =>
      _make != null ? (_makeModels[_make] ?? ['Other']) : [];

  // ---------- Responsive helpers ----------
  double _scale(BuildContext c) => (MediaQuery.sizeOf(c).width / 375).clamp(0.82, 1.18);
  double _gap(BuildContext c, double base) => base * _scale(c);
  double _hPad(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return math.max(16, math.min(28, w * 0.06));
  }
  double _buttonHeight(BuildContext c) => (_gap(c, 54)).clamp(46, 64);

  InputDecoration _dec(BuildContext c, {String? label, String? hint, Widget? suffix}) {
    final r = BorderRadius.circular(12 * _scale(c));
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: _gap(c, 18),
        vertical: _gap(c, 14),
      ),
      suffixIcon: suffix,
    );
  }

  Future<void> _pickFromList(String title, List<String> items, void Function(String) onSelected) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return ListTile(
                      title: Text(item),
                      onTap: () => Navigator.pop(ctx, item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (result != null) onSelected(result);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (_make == null || _make!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select vehicle make')));
      return;
    }
    if (_model == null || _model!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select vehicle model')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      // FIX: user_id is NOT needed here — the backend reads the user ID
      // from the JWT Bearer token. Removing the userId null-check that was
      // blocking the save even for fully logged-in users.
      final Map<String, String> data = {
        'make': _make!,
        'model': _model!,
        'color': _colorC.text.trim(),
        'plate_no': _plateC.text.trim(),
        'seats': _seatsC.text.trim(),
      };

      final resp = await Api.saveVehicle(data);

      if (!mounted) return;

      if (resp != null && resp['ok'] == true) {
        await prefs.setString('vehicle_make', data['make']!);
        await prefs.setString('vehicle_model', data['model']!);
        await prefs.setString('vehicle_color', data['color']!);
        await prefs.setString('vehicle_plate', data['plate_no']!);
        await prefs.setString('vehicle_total_seats', data['seats']!);

        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.driverDashboard,
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save vehicle. Please try again.')));
      }
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _colorC.dispose();
    _plateC.dispose();
    _seatsC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: Colors.black87,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Add Your Vehicle',
          style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final pad = _hPad(context);
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(pad, _gap(context, 12), pad, _gap(context, 12)),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - bottomInset),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Please provide the details of the vehicle you'll\nbe using for rides.",
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54, height: 1.4),
                      ),
                      SizedBox(height: _gap(context, 16)),

                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [

                            // ── Vehicle Make (bottom-sheet picker) ──
                            Text('Vehicle Make', style: theme.textTheme.bodyMedium),
                            SizedBox(height: _gap(context, 8)),
                            GestureDetector(
                              onTap: () => _pickFromList('Select Make', _makes, (val) {
                                setState(() {
                                  _make = val;
                                  _model = null; // reset model when make changes
                                });
                              }),
                              child: AbsorbPointer(
                                child: TextFormField(
                                  controller: TextEditingController(text: _make ?? ''),
                                  decoration: _dec(
                                    context,
                                    hint: 'Select make',
                                    suffix: const Icon(Icons.arrow_drop_down),
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(height: _gap(context, 12)),

                            // ── Vehicle Model (dropdown based on make) ──
                            Text('Vehicle Model', style: theme.textTheme.bodyMedium),
                            SizedBox(height: _gap(context, 8)),
                            GestureDetector(
                              onTap: _make == null
                                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please select a make first')))
                                  : () => _pickFromList('Select Model', _modelsForMake, (val) {
                                        setState(() => _model = val);
                                      }),
                              child: AbsorbPointer(
                                child: TextFormField(
                                  controller: TextEditingController(text: _model ?? ''),
                                  decoration: _dec(
                                    context,
                                    hint: _make == null ? 'Select make first' : 'Select model',
                                    suffix: const Icon(Icons.arrow_drop_down),
                                  ),
                                  style: TextStyle(
                                    color: _make == null ? Colors.grey : Colors.black87,
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(height: _gap(context, 12)),

                            // ── Color ──
                            Text('Color', style: theme.textTheme.bodyMedium),
                            SizedBox(height: _gap(context, 8)),
                            TextFormField(
                              controller: _colorC,
                              textInputAction: TextInputAction.next,
                              decoration: _dec(context, hint: 'e.g. White, Silver, Red'),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Color is required' : null,
                            ),

                            SizedBox(height: _gap(context, 12)),

                            // ── Plate Number ──
                            Text('Plate Number', style: theme.textTheme.bodyMedium),
                            SizedBox(height: _gap(context, 8)),
                            TextFormField(
                              controller: _plateC,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.characters,
                              decoration: _dec(context, hint: 'e.g. ABC-123'),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Plate number is required' : null,
                            ),

                            SizedBox(height: _gap(context, 12)),

                            // ── Number of Seats ──
                            Text('Number of Seats', style: theme.textTheme.bodyMedium),
                            SizedBox(height: _gap(context, 8)),
                            TextFormField(
                              controller: _seatsC,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              decoration: _dec(context, hint: 'e.g. 4'),
                              validator: (v) {
                                final val = int.tryParse(v ?? '');
                                if (val == null) return 'Enter a valid number';
                                if (val < 1 || val > 9) return 'Seats must be between 1 and 9';
                                return null;
                              },
                              onFieldSubmitted: (_) => _save(),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: _gap(context, 20)),

                      SizedBox(
                        height: _buttonHeight(context),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _navy,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(_gap(context, 12)),
                            ),
                          ),
                          onPressed: _saving ? null : () => _save(),
                          child: _saving
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                )
                              : const Text('Save Vehicle'),
                        ),
                      ),

                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
