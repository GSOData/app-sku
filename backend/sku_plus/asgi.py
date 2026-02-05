"""
ASGI config for sku_plus project.
"""

import os

from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'sku_plus.settings')

application = get_asgi_application()
