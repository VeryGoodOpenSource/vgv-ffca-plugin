# Presentation Layer Templates

Ready-to-adapt code for a `{feature}_presentation` package. Extracted from `references/ffca_architecture.md`, sections *Presentation Layer* and *Routing & Navigation*. Each screen or independently loadable widget gets a `{screen}/bloc/`, `{screen}/views/`, and a `{screen}/{screen}_module.dart`.

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

The feature's entry point. Declares all dependencies, wires the Provider and BlocProvider tree, and exposes navigation callbacks. Construct dependencies with Provider, get_it, riverpod, or prop drilling, as long as the dependencies are explicit.

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

Alternative with Actions and Intents (no prop drilling, no Provider needed in deep widgets):

```dart
return Actions(
  actions: {
    ProductTappedIntent: CallbackAction<ProductTappedIntent>(
      handler: (intent) => onProductTapped(intent.productId),
    ),
  },
  child: BlocProvider(
    create: (_) => CartListCubit(...),
    child: const CartListScreen(),
  ),
);

// Deep in the tree:
InkWell(
  onTap: () => Actions.invoke(context, ProductTappedIntent(product.id)),
  child: ProductCard(...),
)
```

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
