import '../entities/catalog.dart';

abstract interface class CatalogRepository {
  Future<Catalog> loadCatalog();
}
