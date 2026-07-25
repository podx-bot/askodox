# Seller module

The seller experience is implemented with clean feature boundaries:

- `domain/` contains immutable seller/shop entities and the repository contract.
- `data/` contains the simulated OTP and profile repository. No network or backend
  integration is used.
- `application/` exposes the Riverpod state controller for authentication,
  registration, inventory, and dashboard totals.
- `presentation/` contains the Material 3 login, registration, dashboard, master
  catalog selection, and product-management flows.

For demo purposes the accepted OTP is `123456`. Seller inventory is held only in
memory and resets when the application restarts.
