# Presentation Layer

> Modules, localizations, and subfeature barrel files in a feature's presentation package.

- Source: https://engineering.verygood.ventures/architecture/ffca/presentation/

---

The presentation layer of each feature is responsible for defining the user interface and glueing everything together to display that UI. Generally, that will be a series of Flutter widgets. However, since the domain and data layers are headless, you could adapt it for a CLI app as well.

In the context of a Flutter application, the presentation layer will:

- Define an entry point for the feature, or parts of the feature.
- Define the various screens and widgets needed to implement a feature.
- Define the blocs that tie your domain layer to your widgets.

## The module

Each feature, or part of a feature, should be defined by a **module**. If a feature has many screens, or complex subcomponents, each one can define its own module. A module is responsible for defining and setting up the dependencies required by a feature, or part of a feature. This achieves three goals:

1. Each module clearly defines all of its dependencies. No surprises.
2. It moves registration of dependency injection for that part of a feature to a common location.
3. It enables the use of [deferred imports](/architecture/ffca/project_structure/#deferred-loading), which are important for splitting web bundles into smaller parts and enabling Android dynamic modules.

Construct the dependencies with [`Provider`](https://pub.dev/packages/provider). Several packages can achieve the goals above, and we standardize on one so that every module in every feature reads the same way. A module looks like this:

```dart
/// The module that loads the cart screen and its dependencies.
class CartListModule extends StatelessWidget {
  /// Constructs the module that loads a user's cart.
  const CartListModule({
    required this.id,
    required this.cartsRepository,
    required this.productsRepository,
    required this.onProductTapped,
    required this.onCheckoutStarted,
    super.key,
  });

  /// The repository for carts.
  final ICartsRepository cartsRepository;

  /// The repository for products.
  final IProductsRepository productsRepository;

  /// The id of the cart to load.
  final String id;

  /// Called when the user taps a product. The app decides where that goes.
  final void Function(String productId) onProductTapped;

  /// Called when the user starts checkout.
  final VoidCallback onCheckoutStarted;

  @override
  Widget build(BuildContext context) {
    // The carts and products repositories are used on many screens, so assume
    // they have been constructed in a Provider at a level above.
    return Provider(
      create: (context) => GetCartByIdQuery(
        cartsRepository: cartsRepository,
        productsRepository: productsRepository,
      ),
      child: BlocProvider<CartListCubit>(
        create: (context) {
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

## Localizations

Localizations can be either shared or per-feature. There are pros and cons to both approaches. To keep it simple, start with a Flutter package in the `shared` folder, and use it amongst all of your features in the presentation layer.

If your app is more complex and very large, it may be worthwhile for each feature to define their own localizations. However, this introduces additional complexity.

## Widgets that own state

A widget that owns a `Cubit` is not a separate feature. It lives in its own feature's presentation package, and it is exported through a barrel file.

`CartBadge` depends on `cart_domain`, its own feature's domain. What makes it worth discussing is that it renders inside a screen owned by a different feature. The question is not whether a widget may reach across domains. It is who places it, and what the dependency costs.

```dart
// cart_presentation/lib/cart_badge/bloc/cart_badge_cubit.dart

class CartBadgeCubit extends Cubit<CartBadgeState> {
  CartBadgeCubit({required ICartsRepository cartsRepository})
      : _cartsRepository = cartsRepository,
        super(const CartBadgeInitial());

  final ICartsRepository _cartsRepository;

  Future<void> loadItemCount(String cartId) async {
    emit(const CartBadgeLoading());
    try {
      final cartSummary = await _cartsRepository.getCartById(cartId);
      emit(CartBadgeLoaded(itemCount: cartSummary.productIds.length));
    } catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(CartBadgeError(message: error.toString()));
    }
  }
}
```

### Sharing a widget across features

A presentation package may depend on another feature's presentation package and use a public widget from it. Three conditions apply.

**The widget gets its own barrel.** Consumers import `package:cart_presentation/cart_badge.dart`, never the primary `package:cart_presentation/cart_presentation.dart` barrel.

**The barrel stays narrow.** Its transitive imports must not reach the feature's modules or screens. A widget barrel that pulls in `cart_domain` and the design system costs a consumer a widget. One that goes through the primary barrel costs them every screen and `Cubit` the cart feature owns, and it breaks [deferred loading](/architecture/ffca/project_structure/#deferred-loading) downstream.

**No cycles.** If two features each need a widget from the other, they share something that belongs underneath both of them rather than beside either. Extract it downward instead of importing sideways.

### Or let the app place it

The alternative is that the consuming feature never learns the other feature exists. It declares a slot, and the app fills it. This is the same inversion we use for [navigation](/architecture/ffca/navigation/). The feature declares the extension point, and the app supplies the implementation.

```dart
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
class ProductDetailRoute extends GoRouteData with $ProductDetailRoute {
  const ProductDetailRoute({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ProductDetailModule(
      productId: id,
      productsRepository: context.read(),
      // The app owns composition, so cart_presentation is imported here
      // rather than by product_presentation.
      trailingAction: CartBadge(cartsRepository: context.read()),
    );
  }
}
```

A plain `Widget` parameter is enough in most cases. Reach for a `WidgetBuilder` when construction has to wait until the slot is built, or when it needs the `BuildContext` available at fill time.

Name the slot for its position rather than for the widget you expect to fill it. `trailingAction` keeps the API honest, and `cartBadgeBuilder` leaks the other feature straight back in.

Default the slot to nothing rather than making it required, so the feature stays runnable and golden-testable without the other feature's repositories in the widget tree.

More than two slots on one module is a sign the composition belongs one level up, in a shell owned by the app.

### Choosing between them

Use a slot when the widget is app chrome. A cart badge in an app bar belongs to the shell rather than to the product feature, and in a shell layout the app builds it with a repository already in scope.

Use a direct import behind a narrow barrel when the widget is genuinely part of what the consuming screen _is_, rather than something placed around it.

### Where the widget should live

When the same widget is wanted in more than one feature, work through this in order.

1. **Does it need a repository or a domain type?** If not, it is a pure presentational component, and it belongs in `ui_kit`. This test is mechanical rather than stylistic. [Shared packages depend on external packages only](/architecture/ffca/project_structure/#dependency-rules), so a widget that needs a repository cannot compile there.
2. **If it does, split it.** `CartBadgeView`, taking a plain count, goes in `ui_kit`. `CartBadge`, the `Cubit` plus that view, stays in `cart_presentation` behind its own barrel. In practice, a widget that gets genuinely reused across features is usually a presentational leaf with the stateful part left behind, which means the reuse pressure was pointing at `ui_kit` all along.

It becomes its own feature when it grows its own business logic, and a [presentation-only feature](/architecture/ffca/overview/#presentation-only-features) when it composes several features without owning business logic of its own.

## Subfeature barrel files

A single feature may expose multiple independent entry points. For example, `favorites_presentation` might have a list screen and a detail screen that apps import separately. Each subfeature gets its own barrel file, and the primary barrel re-exports everything:

- features/favorites/
  - favorites_presentation/
    - lib/
      - favorites_list/
      - favorites_detail/
      - favorites_list.dart (subfeature barrel)
      - favorites_detail.dart (subfeature barrel)
      - favorites_presentation.dart (primary barrel, re-exports all)

This is essential for **deferred imports**. An app that wants to lazy-load the favorites detail screen imports only its subfeature barrel with a deferred prefix:

```dart
import 'package:favorites_presentation/favorites_detail.dart'
    deferred as favorites_detail;
```

With a single barrel file, you can't defer-load part of a package, because importing anything pulls in everything. Subfeature barrels enable fine-grained code splitting for web bundles and Android dynamic modules. See [deferred loading](/architecture/ffca/project_structure/#deferred-loading) for the constraint this places on cross-feature imports, and for when it gains you nothing. For more on barrel files generally, see [barrel files](/architecture/barrel_files/).

Next, [navigation](/architecture/ffca/navigation/) covers how a module moves the user to another feature without importing it.
