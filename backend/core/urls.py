"""
URLs do app core - API SKU+.

Estrutura:
- /api/auth/          -> Autenticação (login, logout, me, token)
- /api/unidades/      -> CRUD Unidades de Negócio
- /api/skus/          -> CRUD SKUs + Consulta Validade
- /api/lotes/         -> CRUD Lotes
- /api/estoque/       -> Estoque Inicial (read-only)
- /api/criticidade/   -> Relatório de Criticidade
- /api/movimentacoes/ -> Movimentações de Estoque
- /api/configuracoes/ -> Configurações de Alerta
- /api/logs/          -> Logs de Consulta (admin)
"""

from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    # Auth
    LoginView,
    LogoutView,
    MeView,
    # ViewSets
    UnidadeNegocioViewSet,
    SKUViewSet,
    LoteValidadeViewSet,
    EstoqueViewSet,
    ConfiguracaoAlertaViewSet,
    MovimentacaoEstoqueViewSet,
    LogConsultaViewSet,
    # APIViews
    RelatorioCriticidadeView,
)

app_name = 'core'

# Router para ViewSets
router = DefaultRouter()
router.register(r'unidades', UnidadeNegocioViewSet, basename='unidades')
router.register(r'skus', SKUViewSet, basename='skus')
router.register(r'lotes', LoteValidadeViewSet, basename='lotes')
router.register(r'estoque', EstoqueViewSet, basename='estoque')
router.register(r'configuracoes', ConfiguracaoAlertaViewSet, basename='configuracoes')
router.register(r'movimentacoes', MovimentacaoEstoqueViewSet, basename='movimentacoes')
router.register(r'logs', LogConsultaViewSet, basename='logs')

# URLs de autenticação
auth_urls = [
    path('login/', LoginView.as_view(), name='login'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('me/', MeView.as_view(), name='me'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
]

urlpatterns = [
    # Auth
    path('auth/', include((auth_urls, 'auth'))),
    
    # Relatório de Criticidade (endpoint customizado)
    path('relatorio-criticidade/', RelatorioCriticidadeView.as_view(), name='relatorio-criticidade'),
    
    # ViewSets (router)
    path('', include(router.urls)),
]
