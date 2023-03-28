from django.db import models
from django.contrib.auth.models import User
from datetime import date

# Create your models here.
class Mode(models.Model):
    modes = models.CharField(max_length=20)

    def __str__(self):
        return self.modes

class product_spec(models.Model):
    specs = models.CharField(max_length=20)

    def __str__(self):
        return self.specs

class Customer(models.Model):
    user = models.OneToOneField(User, null=True, blank=True, on_delete=models.CASCADE)
    name = models.CharField(max_length=200, null=True)
    email = models.CharField(max_length=200)
    # password 

    def __str__(self):
        return self.name

class Requests(models.Model):
    name = models.CharField(max_length=200, null=True)
    email = models.CharField(max_length=200)
    phone = models.CharField(max_length=200)
    request = models.CharField(max_length=500)
    # password 

    def __str__(self):
        return self.name

class Product(models.Model):
    name = models.CharField(max_length=40)
    price = models.FloatField()
    digital = models.BooleanField(default=False, null=True, blank=True)
    bedrooms = models.IntegerField(max_length=10, blank=True, null=True) 
    bathrooms = models.IntegerField(max_length=10, blank=True, null=True) 
    toilets =  models.IntegerField(max_length=10, blank=True, null=True) 
    location = models.CharField(max_length=200)
    description = models.IntegerField(max_length=10, blank=True, null=True)
    mode = models.ForeignKey(Mode, on_delete=models.CASCADE, blank=True, null=True)
    spec = models.ForeignKey(product_spec, on_delete=models.CASCADE, blank=True, null=True)
    featured = models.ImageField(null=True, blank=True)

    def __str__(self):
        return self.name
    
    @property
    def imageURL(self):
        try:
            url = self.featured.url
        except:
            url = ""
        return url

class Image(models.Model):
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    name = models.CharField(max_length=200)
    image = models.ImageField(null=True, blank=True)

    def __str__(self):
        return self.name
    
    @property
    def imageURL(self):
        try:
            url = self.image.url
        except:
            url = ""
        print('URL: ', url)
        return url

class Order(models.Model):
    customer = models.ForeignKey(Customer, on_delete=models.SET_NULL, null=True)
    date_ordered = models.DateTimeField(auto_now_add=True)
    complete = models.BooleanField(default=False)
    transaction_id = models.CharField(max_length=100, null=True)

    def __str__(self):
        return str(self.id)

    @property
    def get_cart_total(self):
        orderitems = self.orderitem_set.all()
        total = sum([item.get_total for item in orderitems])
        return total
    
    @property
    def get_cart_items(self):
        orderitems = self.orderitem_set.all()
        total = sum([item.quantity for item in orderitems])
        return total

    @property
    def shipping(self):
        shipping = False
        orderitems = self.orderitem_set.all()
        # j=0
        for i in orderitems:
            if (i.product.digital == False) or (i.product.digital == "false"):
                shipping = True
            # j+=1
        return shipping

class OrderItem(models.Model):
    product = models.ForeignKey(Product, on_delete=models.SET_NULL, null=True)
    order = models.ForeignKey(Order, on_delete=models.SET_NULL, null=True)
    quantity = models.IntegerField(default=0, null=True, blank=True)
    date_added = models.DateTimeField(auto_now_add=True)

    @property
    def get_total(self):
        total = self.product.price * self.quantity
        return total

class ShippingAddress(models.Model):
    customer = models.ForeignKey(Customer, on_delete=models.SET_NULL, null=True)
    order = models.ForeignKey(Order, on_delete=models.SET_NULL, null=True)
    address = models.CharField(max_length=200, null=False)
    city = models.CharField(max_length=200, null=False)
    state = models.CharField(max_length=200, null=False)
    zipcode = models.CharField(max_length=200, null=False)
    date_added = models.DateTimeField(auto_now_add=True)

    def __sstr__(self):
        return self.address

