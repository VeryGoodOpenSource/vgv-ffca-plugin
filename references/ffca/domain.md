# Domain Layer

> Models, Commands and Queries, repository interfaces, and combining one feature with another.

- Source: https://engineering.verygood.ventures/architecture/ffca/domain/

---

The heart of the application. This layer is pure Dart, and entirely separate from "the outside world" of Flutter or concrete data sources, such as Firebase or http APIs. The domain layer defines the business models and operations of the given problem space, as well as the repositories required to perform those operations.

## Models

Models, sometimes called "entities," are objects that contain the information you are trying to represent in the problem space. For example, in the context of an online store app, the domain models might include a `Product` and a `Cart`. A `Product` class contains `id`, `title`, and `description` information.

Do not add the word `Model` or `Entity` to this class. This is the core of the domain, and it should be easy to read and understand.

## Business rules

There are generally two types of rules in the domain space: commands and queries. _Commands_ make modifications to the domain models and often store them in a data source. _Queries_ retrieve domain models from a data source. Combined, these are often referred to as "use cases."

For the purposes of our codebase, we recommend avoiding the term "use case" and instead prefer **Command** and **Query** classes for clarity. For example:

- `UpdateProductTitleCommand`: updates the title of a product and stores it in the data source.
- `GetProductByIdQuery`: fetches product information based on the product id. It returns a `Future<Product>`.
- `WatchProductByIdQuery`: returns a new instance of a `Product` object any time the `Product` changes. It returns a `Stream<Product>`.

If a Command or Query only serves to call out to the repository, there is no need to introduce the class at all. Most often, these classes are important when you need to combine several data sources together from different features through repositories, or if you find yourself performing the exact same work in several blocs.

## Repositories

You may need to load a `Product` from a local database or api. Therefore, the domain layer for the "Product feature" must define a way to fetch that information, without knowing how it is done.

For this purpose, the domain defines repositories. In the domain layer, these classes are `abstract interface class` definitions. Repositories for each feature must be independent. The `Cart` domain should not define an `IProductsRepository` and vice-versa. This leads to coupling which makes refactors and data migrations difficult or impossible. An example of such a class might look like the following:

```dart
abstract interface class IProductsRepository {
  Future<void> saveProduct(Product product);
  Future<Product> getProductById(String productId);
  Stream<Product> watchProductById(String productId);
  Future<void> updateProduct(Product product);
  Future<void> deleteProduct(String productId);
}
```

## Composing features

In the domain layer, features often combine information and actions from other features. To solve this problem, feature domains may depend on other feature domains. For example, the Cart domain may rely on the Product domain, so that you can watch a `Cart` with populated `Product` information.

There are two parts to consider here: how to make that data easy to read, and how to store the data.

### Storing data

To make it easy to work with `Cart` data, we want to store the `List<Product>` in the Cart. Therefore, a `Cart` object would look like this:

```dart
class Cart {
  Cart({required this.id, required this.products});

  final String id;
  final List<Product> products;
}
```

However, the Cart data layer should not know how to store or retrieve `Products`. Therefore, in order to populate the `List<Product>`, we must store it as a `List<Id>`, often times a UUID String, making it a `List<String>`. To represent the class we want to store in our repository, we call this a **summary** object. For example, the `CartSummary` has the following shape:

```dart
class CartSummary {
  CartSummary({required this.id, required this.productIds});

  final String id;
  final List<String> productIds;
}
```

The cart repository then reads and writes summaries, and only takes a full `Cart` when one is being created:

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

### Reading the populated object

Now, in order to read a populated cart, introduce a Query that combines the `ICartsRepository` and the `IProductsRepository`:

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

Notice that the cart feature never learns how products are stored, and the product feature never learns that carts exist.

Next, the [data layer](/architecture/ffca/data/) provides a concrete implementation of the repositories you just defined.
