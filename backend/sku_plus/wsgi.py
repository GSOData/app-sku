"""
WSGI config for sku_plus project.
"""

import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'sku_plus.settings')

application = get_wsgi_application()
