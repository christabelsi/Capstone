import 'package:flutter/material.dart';


class MoreOptionsButton extends StatelessWidget {
  const MoreOptionsButton({
    super.key,
    this.tooltip = 'More options',
    this.enabled = true,
    required this.onSelected,
    required this.itemBuilder,
  });

  final String tooltip;
  final bool enabled;
  final PopupMenuItemSelected<String> onSelected;
  final List<PopupMenuEntry<String>> Function(BuildContext context) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              offset: const Offset(0, 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onSelected: onSelected,
              itemBuilder: itemBuilder,
              icon: const Icon(Icons.more_vert),
            ),
          ),
        ),
      ),
    );
  }
}

PopupMenuItem<String> moreMenuItem(
  BuildContext context, {
  required String value,
  required String label,
  IconData? icon,
  bool destructive = false,
}) {
  final theme = Theme.of(context);
  final color = destructive ? theme.colorScheme.error : null;
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            label,
            style: color != null ? TextStyle(color: color) : null,
          ),
        ),
      ],
    ),
  );
}
