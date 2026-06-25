import 'package:flutter/material.dart';

/// 分段选择控件（原型设置页的 SegGroup）。
///
/// 水平排列的 Pill 按钮组，单选。
class SegGroup<T> extends StatelessWidget {
  const SegGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelBuilder,
  });

  final List<SegOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: options.map((SegOption<T> opt) {
        final bool selected = opt.value == value;
        return GestureDetector(
          onTap: () => onChanged(opt.value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFF374151),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              labelBuilder != null
                  ? labelBuilder!(opt.value)
                  : opt.label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey.shade300,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class SegOption<T> {
  const SegOption({required this.value, required this.label});
  final T value;
  final String label;
}
