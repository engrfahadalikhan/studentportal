import 'package:flutter/material.dart';
import '../models/student.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final RequestStatus status;

  const StatusBadge({
    Key? key,
    required this.label,
    required this.status,
  }) : super(key: key);

  Color _getColor() {
    switch (status) {
      case RequestStatus.approved:
        return Colors.green;
      case RequestStatus.pending:
        return Colors.orange;
      case RequestStatus.rejected:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getColor().withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _getColor(),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
