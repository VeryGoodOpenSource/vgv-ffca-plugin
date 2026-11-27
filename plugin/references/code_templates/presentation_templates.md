# Presentation Layer Templates

Ready-to-adapt code for a `{feature}_presentation` package. Extracted from `references/ffca/presentation.md` and `references/ffca/navigation.md`. Each screen or independently loadable widget gets a `{screen}/bloc/`, `{screen}/views/`, and a `{screen}/{screen}_module.dart`.

## Cubit and sealed states (`{screen}/bloc/`)

Sealed states with an Initial, Loading, Loaded, and Error case. The screen switches on the state. FFCA uses a Cubit here; for an event-driven Bloc, sealed events, event transformers, and `blocTest`, use the vgv-ai-flutter-plugin bloc skill.

```dart
sealed class CartBadgeState {
  const CartBadgeState();
}

class CartBadgeInitial extends CartBadgeState {
  const CartBadgeInitial();
}

class CartBadgeLoading extends CartBadgeState {
  const CartBadgeLoading();
}

class CartBadgeLoaded extends CartBadgeState {
  const CartBadgeLoaded({required this.itemCount});
  final int itemCount;
}

class CartBadgeError extends CartBadgeState {
  const CartBadgeError({required this.message});
  final String message;
}
```

```dart
class CartBadgeCubit extends Cubit<CartBadgeState> {
  CartBadgeCubit({required ICartsRepository cartsRepository})
      : _cartsRepository = cartsRepository,
        super(const CartBadgeInitial());

  final ICartsRepository _cartsRepository;

  Future<void> loadItemCount(String cartId) async {
    emit(const CartBadgeLoading());
    try {
      final cart = await _cartsRepository.getCartById(cartId);
      emit(CartBadgeLoaded(itemCount: cart.productIds.length));
    } catch (e, st) {
      addError(e, st);
      emit(CartBadgeError(message: e.toString()));
    }
  }
}
```

## Module (`{screen}/{screen}_module.dart`)

The feature's entry point. Declares all dependencies, wires the Provider and BlocProvider tree, and exposes navigation callbacks. Construct dependencies with [`Provider`](https://pub.dev/packages/provider). Several packages could do the job; standardizing on one is the point, so that every module in every feature reads the same way.

```dart
/// The module that loads the cart screen and dependencies
class CartListModule extends StatelessWidget {
  const CartListModule({
    required this.id,
    required this.cartsRepository,
    required this.productsRepository,
    super.key,
  });

  final ICartsRepository cartsRepository;
  final IProductsRepository productsRepository;
  final String id;

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (context) => GetCartByIdQuery(
        cartsRepository: cartsRepository,
        productsRepository: productsRepository,
      ),
      child: BlocProvider<CartListCubit>(
        create: (BuildContext context) {
          return CartListCubit(
            getCartByIdQuery: context.read(),
            cartsRepository: cartsRepository,
          );
        },
        child: CartListScreen(id: id),
      ),
    );
  }
}
```

## Navigation: callback injection

Features never import the app router or another feature's routes. The app layer injects what happens next; the feature detects when.

For shallow trees, pass callbacks into the Module constructor (add `onProductTapped`, `onCheckoutStarted`, and so on alongside the dependencies above). For deep trees, define a Navigation class in the feature's presentation package and provide it to the subtree:

```dart
class CartNavigation {
  CartNavigation({
    required this.onProductTapped,
    required this.onCheckoutStarted,
  });

  final void Function(String productId) onProductTapped;
  final VoidCallback onCheckoutStarted;
}
```

```dart
// Inside a deeply nested widget
InkWell(
  onTap: () => context.read<CartNavigation>().onProductTapped(product.id),
  child: ProductCard(...),
)
```

## Widget slots (visual extension points)

The same inversion applied to widgets. Rather than importing another feature to display one of its widgets, the module reserves a slot and the app fills it. Name the slot for its position, never for the widget you expect, and default it to nothing so the feature stays runnable and golden-testable on its own. Stop at two slots per module; beyond that, the composition belongs in an app-owned shell.

```dart
// product_presentation: knows nothing about the cart feature.
class ProductDetailModule extends StatelessWidget {
  const ProductDetailModule({
    required this.productId,
    required this.productsRepository,
    this.trailingAction,
    super.key,
  });

  /// Filled by the app. Reserves a slot without knowing what goes in it.
  final Widget? trailingAction;

  // ...
}
```

```dart
// The app layer owns composition, so it is the app that imports cart_presentation.
class ProductDetailRoute extends GoRouteData with $ProductDetailRoute {
  const ProductDetailRoute({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ProductDetailModule(
      productId: id,
      productsRepository: context.read(),
      trailingAction: CartBadge(cartsRepository: context.read()),
    );
  }
}
```

Use a `WidgetBuilder` instead of a plain `Widget` only when construction has to wait until the slot is built, or when it needs the `BuildContext` available at fill time.

## Routes (app layer, go_router_builder)

`GoRouteData` classes live in the app layer and instantiate feature Modules with callback wiring. Navigate with generated route classes, never string paths.

```dart
@TypedGoRoute<CartListRoute>(path: '/cart')
class CartListRoute extends GoRouteData {
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return CartListModule(
      cartsRepository: context.read(),
      productsRepository: context.read(),
      onProductSelected: (id) => ProductDetailRoute(id: id).go(context),
      onCheckoutRequested: () => CheckoutRoute().go(context),
    );
  }
}
```

### Splitting the routing table across files

One routing file per feature, but they must all be `part` of a single library. `go_router_builder` collects `@TypedGoRoute` annotations per library, and routes declared in a separate library are silently dropped: the build succeeds and the routes do not exist.

```text
apps/my_app/lib/app_router/
  routes.dart            the library: imports, part directives, root route
  favorites_routes.dart  part
  ideas_routes.dart      part
  routes.g.dart          generated part
```

```dart
// routes.dart holds every import and every part directive.
library;

import 'package:favorites_presentation/favorites_list.dart'
    deferred as favorites_list;
import 'package:ideas_presentation/ideas_presentation.dart' deferred as ideas;

part 'favorites_routes.dart';
part 'ideas_routes.dart';
part 'routes.g.dart';
```

```dart
// favorites_routes.dart
part of 'routes.dart';

class FavoritesListRoute extends GoRouteData with $FavoritesListRoute {
  const FavoritesListRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return favorites_list.FavoritesListModule(
      favoritesRepository: context.read(),
      // The feature reports that a row was tapped. The app decides that this
      // means navigation.
      onFavoriteTapped: (id) => FavoriteDetailsRoute(id: id).go(context),
    );
  }
}
```

Adding a feature is two lines in `routes.dart`, its deferred import and its `part` directive, plus a new file nobody else is editing. Centralizing the imports is also what gives each subfeature barrel its `deferred as` prefix in one place.

## Deep links and the $extra hydration pattern

Screens must rebuild from URL parameters alone. `$extra` is a volatile optimization (lost on refresh, process death, cold-start deep links), so it is nullable and the Bloc treats it as optional.

```dart
@TypedGoRoute<ProductDetailRoute>(path: '/product/:id')
class ProductDetailRoute extends GoRouteData {
  const ProductDetailRoute({required this.id, this.$extra});

  final String id;
  final Product? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ProductDetailModule(
      productId: id,
      initialProduct: $extra, // performance optimization, may be null
    );
  }
}
```

The Bloc emits `Loaded` immediately when `initialProduct` is present, otherwise fetches by `productId` and shows a loading state.

## Barrels

A primary barrel `lib/{feature}_presentation.dart` re-exports everything; each independently loadable screen gets its own subfeature barrel so it can be deferred-imported.

```dart
// favorites_presentation.dart (primary barrel)
export 'favorites_list.dart';
export 'favorites_detail.dart';
```
