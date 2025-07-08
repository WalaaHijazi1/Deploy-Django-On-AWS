import os
import environ

# Load .env
# Initializes the environment variable handler.
# Loads variables from the .env file in the root of your Django project into memory.
env = environ.ENV()
environ.Env.read_env()

# Base Directory:
# This is used to build paths for static files, media files, templates, etc.
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# Reads the value of DJANGO_DEBUG from your .env file.
# If not found, it defaults to False.
# When DEBUG = False, Django hides detailed error pages — critical for production security.
DEBUG = env.bool('DJANGO_DEBUG','False') == 'True'

# Ensures that only requests from specific hosts (like your ALB DNS name) are allowed.
# Prevents HTTP Host header attacks.
ALLOWED_HOSTS = [env('ALOWED_HOST')]  # Or specify your domain / ALB DNS

# PostgreSQL Database Configuration
# Configures Django to connect to a PostgreSQL database.
# Loads credentials securely from .env:
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': env('DB_NAME'),
        'USER': env('DB_USER'),
        'PASSWORD': env('DB_PASSWORD'),
        'HOST': env('DB_HOST'),
        'PORT': env('DB_PORT', default='5432'),
    }
}

# Static and Media files:
# These are the URL prefixes used when accessing static and media files in the browser.
STATIC_URL = '/static/'
MEDIA_URL= '/media/'

# Tells Django where to collect and store these files on the server or container.
MEDIA_ROOT= os.path.join(BASE_DIR, 'media')
STATIC_ROOT= os.path.join(BASE_DIR, 'static')


