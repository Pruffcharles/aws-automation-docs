from django.shortcuts import render, redirect
from .models import *
from django.forms import inlineformset_factory
from django.http import JsonResponse
import json
import datetime
from . utils import cookieCart, cartData, guestOrder
from django.views.decorators.csrf import csrf_exempt
from django.forms import inlineformset_factory
from django.contrib.auth.forms import UserCreationForm
from .forms import CreateUserForm, req_Form
from django.contrib import messages
from django.contrib.auth import authenticate, login, logout

# Create your views here.

def registerPage(request):
    form = CreateUserForm()
    if request.method == 'POST':
        form = CreateUserForm(request.POST)
        if form.is_valid():
            user = form.save()
            username = form.cleaned_data.get('username')
            email = form.cleaned_data.get('email')
            b = Customer(user=user, name=username, email=email)
            b.save()
            messages.success(request, "Account was created for " + username)
            return redirect('login')
    context = {'form': form}
    return render(request, 'store/register.html', context)
    
def loginPage(request):
    if request.method == 'POST':
        username = request.POST.get('username') 
        password = request.POST.get('password') 
        user = authenticate(request, username=username, password=password)
        print(user)
        print(username)
        if user is not None:
            login(request, user)
            return redirect('store')
        else:
            messages.info(request, 'Username OR password is incorrect')
    context = {}
    return render(request, 'store/login.html', context)

def logoutUser(request):
    logout(request)
    return redirect('login')

def store(request):
    if 'term' in request.GET:
        queryset = Product.objects.filter(location__icontains=request.GET.get('term')).distinct()
        results = list()
        for r in queryset:
            results.append(r.location)
        return JsonResponse(results, safe=False)
    elif 'spec' in request.GET:
        errors = []
        data = cartData(request)
        cartItems = data['cartItems']
        results = None
        context = {'products':results, 'cartItems': cartItems}
        if 'spec' in request.GET:
            # spec = request.GET['spec']
            # mode = request.GET['mode']
            location = request.GET['location']
            bedrooms = request.GET['bedroom']
            print(bedrooms, location)
            if not ((location or bedrooms) or location):
                print("errors")
                errors.append('Enter a search term.')
            else:
                results = Product.objects.filter(bedrooms__icontains=str(bedrooms)
                ).filter(
                    location__icontains=str(location)
                )
                # query = "spec: %s, mode: %s, location: %s" % (spec, mode, location)
                query = "bedrooms: %s, location: %s" % (bedrooms, location)
                print(len(results))
                context = {'products':results, 'cartItems': cartItems, 'query': query}
                return render(request, 'store/search.html', context)
        print("results")
        context = {'products':results, 'cartItems': cartItems, 'query': query}
        return render(request, 'store/search.html', context)
    data = cartData(request)
    cartItems = data['cartItems']
    Products = Product.objects.all()
    context = {'products':Products, 'cartItems': cartItems}
    return render(request, 'store/store.html', context)

def rental_store(request):
    data = cartData(request)
    cartItems = data['cartItems']
    Products = Product.objects.filter(mode="1")
    context = {'products':Products, 'cartItems': cartItems}
    return render(request, 'store/store.html', context)

def sale_store(request):
    data = cartData(request)
    cartItems = data['cartItems']
    Products = Product.objects.filter(mode="2")
    context = {'products':Products, 'cartItems': cartItems}
    return render(request, 'store/store.html', context)

def property_type(request, id=0):
    prop = Product.objects.get(pk=id)
    data = cartData(request)
    cartItems = data['cartItems']
    print(prop)
    context = {'product':prop, 'cartItems': cartItems}
    return render(request, 'store/property.html', context)

def cart(request):
    if request.user.is_authenticated:
        customer = request.user.customer
        order, created = Order.objects.get_or_create(customer=customer, complete=False)
        items = order.orderitem_set.all()
        cartItems = order.get_cart_items
    else:
        cookieData = cookieCart(request)
        cartItems = cookieData['cartItems']
        order = cookieData['order']
        print(order)
        items = cookieData['items']
        
    context = {'items':items, 'order':order,'cartItems': cartItems}
    # print(order.get_cart_total)
    return render(request, 'store/cart.html', context)



@csrf_exempt
def checkout(request):
    data = cartData(request)
    cartItems = data['cartItems']
    order = data['order']
    items = data['items']
    Products = Product.objects.all()
    context = {'products':Products, 'cartItems': cartItems}
        
    context = {'items':items, 'order':order, 'cartItems': cartItems}
    return render(request, 'store/checkout.html', context)

def updateItem(request):
    data = json.loads(request.body)
    productId = data['productId']
    action = data['action']
    print('Action:', action)
    print('Product:', productId)

    customer = request.user.customer
    product = Product.objects.get(id=productId)
    order, created = Order.objects.get_or_create(customer=customer, complete=False)
    orderItem, created = OrderItem.objects.get_or_create(order=order, product=product)

    if action == 'add':
        orderItem.quantity = (orderItem.quantity +1)
    elif action == 'remove':
        orderItem.quantity = (orderItem.quantity -1)
    orderItem.save()
    if orderItem.quantity <=0:
        orderItem.delete()

    return JsonResponse('Item was added', safe=False)
@csrf_exempt
def processOrder(request):
    transaction_id  = datetime.datetime.now().timestamp()
    data = json.loads(request.body)

    if request.user.is_authenticated:
        customer = request.user.customer
        order, created = Order.objects.get_or_create(customer=customer, complete=False)
        total = float(data['form']['total'])
        order.transaction_id = transaction_id
        if total == order.get_cart_total:
            order.complete = True
        order.save()
    else:
        customer, order = guestOrder(request, data)

    total = float(data['form']['total'])
    order.transaction_id = transaction_id
    if total == order.get_cart_total:
        order.complete = True
    order.save()
    if order.shipping == True:
        ShippingAddress.objects.create(
            customer=customer,
            order=order,
            address = data['shipping']['address'],
            city = data['shipping']['city'],
            state = data['shipping']['state'],
            zipcode = data['shipping']['zipcode'],
            )

    return JsonResponse('Payment submitted..', safe=False)

def search(request):
    errors = []
    data = cartData(request)
    cartItems = data['cartItems']
    results = None
    context = {'products':results, 'cartItems': cartItems}
    print("xyz")
    if 'spec' in request.GET:
        spec = request.GET['spec']
        mode = request.GET['mode']
        location = request.GET['location']
        bedrooms = request.GET['bedrooms']
        if not ((spec or mode) or location):
            print("errors")
            errors.append('Enter a search term.')
        else:
            results = Product.objects.filter(
                spec__icontains=spec
            ).filter(
                mode__icontains=mode
            ).filter(
                location__icontains=location
            )
            query = "spec: %s, mode: %s, location: %s" % (spec, mode, location)
            print(results)
            context = {'products':results, 'cartItems': cartItems, 'query': query}
            return render(request, 'store/search.html', context)
    print("results")
    context = {'products':results, 'cartItems': cartItems, 'query': query}
    return render(request, 'store/search.html', context)

def req(request, id=0):
    data = cartData(request)
    cartItems = data['cartItems']
    form = req_Form()
    context = {'form': form, 'cartItems': cartItems,}
    if request.method == "GET":
        if id == 0:
            context = {'form': form,'cartItems': cartItems}
        else:
            itt = Requests.objects.get(pk=id)
            form = req_Form(instance=itt)
            context = {'form': form,'cartItems': cartItems,}
    if request.method == "POST":
        if id == 0:
            form = req_Form(request.POST)
        else:
            job = Requests.objects.get(pk=id)
            form = req_Form(request.POST,instance=job)
        if form.is_valid():
            form.save()
            # form.save_m2m()
        return render(request, "store/req_saved.html", context)
    return render(request, "store/req_form.html", context)