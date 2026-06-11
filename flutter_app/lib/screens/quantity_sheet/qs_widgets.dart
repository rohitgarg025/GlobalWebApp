// Shared helpers used across Quantity Sheet tabs.
import 'package:flutter/material.dart';

const Color kBrand = Color(0xFF0066CC);
const Color kError = Color(0xFFD32F2F);
const Color kSuccess = Color(0xFF2E7D32);

// ─── Project + Month selector bar ────────────────────────────────────────────

class QsSelector extends StatelessWidget {
  final List<Map<String, dynamic>> projects; // {id, name}
  final int? selectedProjectId;
  final String selectedMonth;
  final ValueChanged<int?> onProjectChanged;
  final ValueChanged<String> onMonthChanged;
  final Widget? trailing;

  const QsSelector({
    super.key,
    required this.projects,
    required this.selectedProjectId,
    required this.selectedMonth,
    required this.onProjectChanged,
    required this.onMonthChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          _label('Project'),
          const SizedBox(width: 8),
          _projectDropdown(context),
          const SizedBox(width: 24),
          _label('Month'),
          const SizedBox(width: 8),
          _monthPicker(context),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
      );

  Widget _projectDropdown(BuildContext context) {
    return DropdownButton<int>(
      value: selectedProjectId,
      hint: const Text('Select project', style: TextStyle(fontSize: 13)),
      underline: const SizedBox(),
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      items: projects
          .map((p) => DropdownMenuItem<int>(
                value: p['id'],
                child: Text(p['name']),
              ))
          .toList(),
      onChanged: onProjectChanged,
    );
  }

  Widget _monthPicker(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final parts = selectedMonth.split('-');
        final initial = DateTime(int.parse(parts[0]), int.parse(parts[1]));
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          initialEntryMode: DatePickerEntryMode.input,
          helpText: 'Select month',
        );
        if (picked != null) {
          final m = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
          onMonthChanged(m);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, size: 16, color: kBrand),
            const SizedBox(width: 6),
            Text(selectedMonth,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}

// ─── Error banner ─────────────────────────────────────────────────────────────

class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorBanner({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kError.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: kError),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: kError, fontSize: 13))),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ─── Loading overlay ──────────────────────────────────────────────────────────

class LoadingCenter extends StatelessWidget {
  final String? message;

  const LoadingCenter({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: const TextStyle(color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

// ─── Primary button ───────────────────────────────────────────────────────────

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon ?? Icons.check, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
