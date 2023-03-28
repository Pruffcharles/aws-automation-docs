from django.forms import ModelForm
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth.models import User
# from chosen import forms as chosenforms
from django_select2 import forms as s2forms
from .models import Order, Requests
from datetime import date

class req_Form(ModelForm):
    class Meta:
        model = Requests
        fields = '__all__'

class CreateUserForm(UserCreationForm):
    class Meta:
        model = User
        fields = ['username', 'email','password1','password2']


