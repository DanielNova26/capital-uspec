import 'package:flutter/material.dart';

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool dense = compact ||
            (constraints.hasBoundedHeight && constraints.maxHeight < 220);

        final content = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12 : 24,
            vertical: dense ? 8 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: dense ? 20 : 28,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  icon,
                  color: scheme.onPrimaryContainer,
                  size: dense ? 22 : 28,
                ),
              ),
              SizedBox(height: dense ? 8 : 12),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: dense ? 4 : 6),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: dense ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: dense ? 1.25 : null,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: dense ? 8 : 14),
                FilledButton.icon(
                  onPressed: onAction,
                  style: dense
                      ? FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  )
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        );

        return Center(child: content);
      },
    );
  }
}