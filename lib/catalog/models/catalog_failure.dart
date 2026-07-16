/// Thrown by [CatalogRepository.fetchDetail] when no item matches the given
/// id. Mirrors the typed-exception approach used for auth (SignUpFailure /
/// LogInFailure) rather than returning null or a raw Exception.
class CatalogItemNotFound implements Exception {
  const CatalogItemNotFound(this.itemId);

  final String itemId;

  @override
  String toString() => 'CatalogItemNotFound: no catalog item with id "$itemId"';
}
