"""
Classes de paginação customizadas para o SKU+.

Permite diferentes tamanhos de página para diferentes endpoints.
"""

from rest_framework.pagination import PageNumberPagination


class SKUPagination(PageNumberPagination):
    """
    Paginação para listagem de SKUs.
    20 itens por página.
    """
    page_size = 20
    page_size_query_param = 'page_size'
    max_page_size = 100


class CriticidadePagination(PageNumberPagination):
    """
    Paginação para relatório de criticidade.
    10 itens por página por categoria.
    """
    page_size = 10
    page_size_query_param = 'page_size'
    max_page_size = 50


class HistoricoUploadPagination(PageNumberPagination):
    """
    Paginação para histórico de uploads.
    15 itens por página.
    """
    page_size = 15
    page_size_query_param = 'page_size'
    max_page_size = 50


class LotePagination(PageNumberPagination):
    """
    Paginação para listagem de lotes.
    20 itens por página.
    """
    page_size = 20
    page_size_query_param = 'page_size'
    max_page_size = 100
