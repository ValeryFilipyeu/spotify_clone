import 'package:flutter/material.dart';

import '../../catalog/models/catalog_section.dart';
import 'catalog_card.dart';

/// A section title above a horizontally-scrolling row of [CatalogCard]s.
class CatalogSectionRow extends StatelessWidget {
  const CatalogSectionRow({super.key, required this.section, this.onItemTap});

  final CatalogSection section;
  final void Function(String itemId)? onItemTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(section.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: section.items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final item = section.items[index];
              return CatalogCard(
                item: item,
                onTap: onItemTap == null ? null : () => onItemTap!(item.id),
              );
            },
          ),
        ),
      ],
    );
  }
}
