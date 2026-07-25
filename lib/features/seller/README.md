# Seller module

The seller experience is implemented with clean feature boundaries:

- `domain/` contains immutable seller/shop entities and the repository contract.
- `data/` contains an in-memory repository for simulated OTP, profiles, inventory,
  buyer requests, seller responses, product requests, and insights. No network or
  backend integration is used.
- `application/` exposes the Riverpod state controller for authentication,
  registration, inventory, requests, responses, insights, and dashboard totals.
- `presentation/` contains the Material 3 login, registration, dashboard, master
  catalog selection, product-management, nearby requests, insights, and shop
  profile flows. A responsive seller shell provides dashboard, products, requests,
  insights, and profile navigation.

For demo purposes the accepted OTP is `123456`. Seller inventory is held only in
memory and resets when the application restarts. Products missing from the Sprint
2 master catalog are stored as pending admin-verification requests rather than
being added directly to seller inventory.
