import '../models/catalog_constants.dart';

/// ILIKE-паттерны для PostgREST (`metal.ilike.*`) по семейству металла.
List<String> metalFamilyToIlikePatterns(Set<String> families) {
  if (families.isEmpty) return const [];

  final patterns = <String>{};
  for (final family in families) {
    switch (family) {
      case CatalogMetalFamilies.gold:
        patterns.addAll(['%золот%', '%gold%', '%au%']);
      case CatalogMetalFamilies.platinum:
        patterns.addAll(['%платин%', '%platinum%', '%pt%']);
      case CatalogMetalFamilies.silver:
        patterns.addAll(['%серебр%', '%silver%', '%ag%']);
    }
  }
  return patterns.toList();
}
