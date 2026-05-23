import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/system_config_provider.dart';

class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _targetController;
  late TextEditingController _salaryController;
  late TextEditingController _baseRateController;
  late TextEditingController _excessRateController;
  late TextEditingController _teamLeaderRateController;
  late TextEditingController _directorRateController;
  late TextEditingController _directorTargetRecruitsController;
  late TextEditingController _bonusController;
  
  
  bool _allowRegistration = true;
  bool _maintenanceMode = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<SystemConfigProvider>().config;
    _targetController = TextEditingController(text: config['targetAmount']?.toString() ?? '200000');
    _salaryController = TextEditingController(text: config['baseSalaryAtTarget']?.toString() ?? '25000');
    _baseRateController = TextEditingController(text: config['baseCommissionRate']?.toString() ?? '10');
    _excessRateController = TextEditingController(text: config['excessCommissionRate']?.toString() ?? '20');
    _teamLeaderRateController = TextEditingController(text: config['teamLeaderOverrideRate']?.toString() ?? '5');
    _directorRateController = TextEditingController(text: config['directorPoolRate']?.toString() ?? '12');
    _directorTargetRecruitsController = TextEditingController(text: (config['directorPromotionQuota'] ?? config['directorTargetRecruits'] ?? 10).toString());
    _bonusController = TextEditingController(text: config['targetBonus']?.toString() ?? '5000');
    
    _allowRegistration = config['allowNewRegistrations'] ?? true;
    _maintenanceMode = config['maintenanceMode'] ?? false;
  }

  @override
  void dispose() {
    _targetController.dispose();
    _salaryController.dispose();
    _baseRateController.dispose();
    _excessRateController.dispose();
    _teamLeaderRateController.dispose();
    _directorRateController.dispose();
    _directorTargetRecruitsController.dispose();
    _bonusController.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configProvider = context.watch<SystemConfigProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: configProvider.isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('Commission Configuration'),
                    _buildNumberField('Monthly Sales Target (₹)', _targetController),
                    _buildNumberField('Base Salary at Target (₹)', _salaryController),
                    _buildNumberField('Base Commission Rate (%)', _baseRateController),
                    _buildNumberField('Excess Commission Rate (%)', _excessRateController),
                    _buildNumberField('Team Leader Override Rate (%)', _teamLeaderRateController),
                    _buildNumberField('Director Global Pool Rate (%)', _directorRateController),
                    _buildNumberField('Director Promotion Target (Successful Recruits)', _directorTargetRecruitsController),
                    _buildNumberField('Target Achievement Bonus (₹)', _bonusController),
                    
                    
                    const SizedBox(height: 32),
                    _buildSectionHeader('Login & Registration'),
                    SwitchListTile(
                      title: const Text('Allow New User Registration'),
                      subtitle: const Text('If disabled, only admins can create accounts'),
                      value: _allowRegistration,
                      onChanged: (val) => setState(() => _allowRegistration = val),
                    ),
                    SwitchListTile(
                      title: const Text('Maintenance Mode'),
                      subtitle: const Text('Prevent all users except admins from logging in'),
                      value: _maintenanceMode,
                      onChanged: (val) => setState(() => _maintenanceMode = val),
                    ),
                    
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _saveSettings,
                        child: const Text('SAVE GLOBAL SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildNumberField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Required';
          if (double.tryParse(value) == null) return 'Invalid number';
          return null;
        },
      ),
    );
  }

  void _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final newConfig = {
      'targetAmount': double.parse(_targetController.text),
      'baseSalaryAtTarget': double.parse(_salaryController.text),
      'baseCommissionRate': double.parse(_baseRateController.text),
      'excessCommissionRate': double.parse(_excessRateController.text),
      'teamLeaderOverrideRate': double.parse(_teamLeaderRateController.text),
      'directorPoolRate': double.parse(_directorRateController.text),
      'directorPromotionQuota': int.parse(_directorTargetRecruitsController.text),
      'targetBonus': double.parse(_bonusController.text),
      
      'allowNewRegistrations': _allowRegistration,
      'maintenanceMode': _maintenanceMode,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    final success = await context.read<SystemConfigProvider>().updateConfig(newConfig);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Settings updated successfully' : 'Failed to update settings'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) Navigator.pop(context);
    }
  }
}
