from django.urls import path, include


from . import views

urlpatterns = [
        #Leave as empty string for base url
	path('', views.store, name="store"),
	path('rentals/', views.rental_store, name="rental_store"),
	path('sales/', views.sale_store, name="sale_store"),
	path('cart/', views.cart, name="cart"),
	path('checkout/', views.checkout, name="checkout"),
	path('property/<int:id>', views.property_type, name="property_type"),
	path('update_item/', views.updateItem, name="update_item"),
	path('process_order/', views.processOrder, name="process_order"),
	path('register/', views.registerPage, name="register"),
	path('login/', views.loginPage, name="login"),
	path('logout/', views.logoutUser, name="logout"),
	path('search/', views.search, name="search"),
	path('x/', views.store, name="Location_insert"),
	path('request/', views.req, name="request"),
	path('req_saved/', views.req, name="req_saved"),
]
