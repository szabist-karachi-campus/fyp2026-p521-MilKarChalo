import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api.dart';

const Color kNavy = Color(0xFF0A2540);
const Color kGreyText = Color(0xFF6C757D);

class EditVehiclePage extends StatefulWidget {
  const EditVehiclePage({super.key});

  @override
  State<EditVehiclePage> createState() => _EditVehiclePageState();
}

class _EditVehiclePageState extends State<EditVehiclePage> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  String? _make;
  String? _model;
  final _colorC = TextEditingController();
  final _plateC = TextEditingController();
  final _seatsC = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _loadVehicle();
  }

  @override
  void dispose() {
    _colorC.dispose();
    _plateC.dispose();
    _seatsC.dispose();
    super.dispose();
  }

  void _loadVehicle() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMake = prefs.getString('vehicle_make') ?? '';
    final savedModel = prefs.getString('vehicle_model') ?? '';
    setState(() {
      _make = _makes.contains(savedMake) ? savedMake : null;
      _model = (_make != null && _modelsForMake.contains(savedModel)) ? savedModel : null;
      _colorC.text = prefs.getString('vehicle_color') ?? '';
      _plateC.text = prefs.getString('vehicle_plate') ?? '';
      _seatsC.text = prefs.getString('vehicle_total_seats') ?? '';
    });
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
                      trailing: (item == _make || item == _model)
                          ? const Icon(Icons.check, color: kNavy)
                          : null,
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

  Future<void> _submit() async {
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

    setState(() => _loading = true);
    try {
      final Map<String, String> data = {
        'make': _make!,
        'model': _model!,
        'color': _colorC.text.trim(),
        'plate_no': _plateC.text.trim(),
        'seats': _seatsC.text.trim(),
      };

      await Api.saveVehicle(data);
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vehicle_make', _make!);
      await prefs.setString('vehicle_model', _model!);
      await prefs.setString('vehicle_color', _colorC.text.trim());
      await prefs.setString('vehicle_plate', _plateC.text.trim());
      await prefs.setString('vehicle_total_seats', _seatsC.text.trim());

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle updated successfully!')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec({String? hint, Widget? suffix}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        suffixIcon: suffix,
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: kGreyText, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: kNavy), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Edit Vehicle', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Update your vehicle information to help passengers identify you easily.',
                        style: TextStyle(color: kGreyText, fontSize: 15)),
                    const SizedBox(height: 28),

                    _label('VEHICLE MAKE'),
                    GestureDetector(
                      onTap: () => _pickFromList('Select Make', _makes, (val) {
                        setState(() { _make = val; _model = null; });
                      }),
                      child: AbsorbPointer(
                        child: TextFormField(
                          controller: TextEditingController(text: _make ?? ''),
                          decoration: _dec(hint: 'Select make', suffix: const Icon(Icons.arrow_drop_down)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _label('MODEL'),
                    GestureDetector(
                      onTap: _make == null
                          ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a make first')))
                          : () => _pickFromList('Select Model', _modelsForMake, (val) { setState(() => _model = val); }),
                      child: AbsorbPointer(
                        child: TextFormField(
                          controller: TextEditingController(text: _model ?? ''),
                          decoration: _dec(hint: _make == null ? 'Select make first' : 'Select model', suffix: const Icon(Icons.arrow_drop_down)),
                          style: TextStyle(color: _make == null ? Colors.grey : Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _label('COLOR'),
                    TextFormField(
                      controller: _colorC,
                      textInputAction: TextInputAction.next,
                      decoration: _dec(hint: 'e.g. White, Silver, Red'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Color is required' : null,
                    ),
                    const SizedBox(height: 20),

                    _label('PLATE NUMBER'),
                    TextFormField(
                      controller: _plateC,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _dec(hint: 'e.g. ABC-123'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Plate number is required' : null,
                    ),
                    const SizedBox(height: 20),

                    _label('TOTAL SEATS'),
                    TextFormField(
                      controller: _seatsC,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: _dec(hint: 'e.g. 4', suffix: const Icon(Icons.event_seat_outlined, color: kGreyText)),
                      validator: (v) {
                        final val = int.tryParse(v ?? '');
                        if (val == null) return 'Enter a valid number';
                        if (val < 1 || val > 9) return 'Seats must be between 1 and 9';
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 36),

                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kNavy,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white))
                          : const Text('Update Vehicle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
