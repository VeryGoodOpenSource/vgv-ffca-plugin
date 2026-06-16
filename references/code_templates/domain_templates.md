# Domain Layer Templates

Ready-to-adapt code for a `{feature}_domain` package. Extracted from `references/ffca_architecture.md`. Read sections *Domain Layer* and *Combining Different Features* for the rules these shapes follow. Rename `Product`/`Cart` to your aggregate and drop the package name into the barrel.

## Model (`models/`)

A plain Dart object representing a domain concept. No `Model` or `Entity` suffix.

```dart
class Product {
  Product({required this.id, required this.title, required this.description});

  final String id;
  final String title;
  final String description;
}
```

## Repository interface (`repositories/`)

An `abstract interface class`, one per feature, named for the feature's own aggregate. A feature's domain never declares another feature's repository.

```dart
abstract interface class IProductsRepository {
  Future<void> saveProduct(Product product);
  Future<Product> getProductById(String productId);
  Stream<Product> watchProductById(String productId);
  Future<void> updateProduct(Product product);
  Future<void> deleteProduct(String productId);
}
```

## The Summary pattern (cross-feature reads)

The read model holds full objects; the stored shape holds ids only. Use this when a feature references another feature's models.

```dart
class Cart {
  Cart({required this.id, required this.products});

  final String id;
  final List<Product> products;
}

class CartSummary {
  CartSummary({required this.id, required this.productIds});

  final String id;
  final List<String> productIds;
}
```

The repository works with summaries:

```dart
abstract interface class ICartsRepository {
  Future<void> createCart(Cart cart);
  Future<CartSummary> getCartById(String cartId);
  Stream<CartSummary> watchCartById(String cartId);
  Future<void> addProductToCart(String cartId, String productId);
  Future<void> removeProductFromCart(String cartId, String productId);
  Future<void> deleteCart(String cartId);
}
```

## Use case combining repositories (`use_cases/`)

Add a `Query` or `Command` only when you combine multiple repositories or repeat work across Blocs. Verbs: `get`/`watch` for queries, `execute` for commands. Never callable classes.

```dart
class GetCartByIdQuery {
  GetCartByIdQuery({
    required ICartsRepository cartsRepository,
    required IProductsRepository productsRepository,
  })  : _cartsRepository = cartsRepository,
        _productsRepository = productsRepository;

  final ICartsRepository _cartsRepository;
  final IProductsRepository _productsRepository;

  Future<Cart> get(String cartId) async {
    final cartSummary = await _cartsRepository.getCartById(cartId);

    return Cart(
      id: cartSummary.id,
      products: [
        for (final productId in cartSummary.productIds)
          await _productsRepository.getProductById(productId),
      ],
    );
  }
}
```

## Identity versus entity (separate domains)

Authentication and profile are separate features. The consuming feature's domain glues them with a query. See the FAQ entry *How do I handle Auth and User Profiles?*.

```dart
// auth_domain
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.isEmailVerified = false,
  });

  final String id;
  final String email;
  final bool isEmailVerified;
}

abstract interface class IAuthRepository {
  Future<AuthUser> getCurrentUser();
  Stream<AuthUser> watchCurrentUser();
}
```

```dart
// user_profile_domain (the consuming feature)
class WatchCurrentUserProfileQuery {
  WatchCurrentUserProfileQuery({
    required IAuthRepository authRepository,
    required IUserProfilesRepository userProfilesRepository,
  })  : _authRepository = authRepository,
        _userProfilesRepository = userProfilesRepository;

  final IAuthRepository _authRepository;
  final IUserProfilesRepository _userProfilesRepository;

  Stream<UserProfile?> watch() {
    return _authRepository.watchCurrentUser().switchMap((authUser) {
      if (authUser == null) {
        return Stream.value(null);
      } else {
        return _userProfilesRepository.watchUserProfile(authUser.id);
      }
    });
  }
}
```

## Barrel (`lib/{feature}_domain.dart`)

```dart
export 'models/product.dart';
export 'repositories/i_products_repository.dart';
// export 'use_cases/get_cart_by_id_query.dart';
```
