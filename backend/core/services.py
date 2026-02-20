"""
Services para processamento de dados do SKU+.

Inclui:
- EstoqueImportService: Importação de planilhas de estoque
"""

import pandas as pd
from io import BytesIO
from datetime import datetime
from typing import Tuple, Dict, Any
from django.db import transaction
from django.utils import timezone

from .models import SKU, LoteValidade, UnidadeNegocio


class EstoqueImportService:
    """
    Service para importação de planilhas de estoque.
    
    Processa dois tipos de arquivo:
    1. Grade 020502: Estoque total diário (sem validade)
    2. Contagens: Conciliação de validades semanais
    """
    
    # Mapeamento de colunas para Grade 020502
    COLUNAS_GRADE_020502 = {
        'Produto': 'codigo_sku',
        'Descricao': 'nome_produto',
        'Unidade': 'unidade_medida',
        'Fator': 'fator_conversao',
        'Inventario': 'estoque_display',
        'Qtd Contagem': 'qtd_estoque',
    }
    
    # Mapeamento de colunas para Contagens
    COLUNAS_CONTAGENS = {
        'Código Item': 'codigo_sku',
        'Validade Aferida': 'data_validade',
        'Quantidade Cx': 'qtd_caixas',
        'Quantidade Unidade': 'qtd_unidades',
    }
    
    def __init__(self, unidade_negocio_id: int):
        """
        Inicializa o service com a unidade de negócio.
        
        Args:
            unidade_negocio_id: ID da unidade de negócio para vincular os dados
        """
        self.unidade_negocio = UnidadeNegocio.objects.get(id=unidade_negocio_id)
        self.errors = []
        self.warnings = []
        self.processed_count = 0
        self.created_count = 0
        self.updated_count = 0
    
    def _read_file(self, file) -> pd.DataFrame:
        """
        Lê arquivo Excel ou CSV e retorna DataFrame.
        
        Args:
            file: Arquivo upload (InMemoryUploadedFile)
            
        Returns:
            DataFrame com os dados do arquivo
        """
        filename = file.name.lower()
        
        try:
            if filename.endswith('.csv'):
                # Tenta diferentes encodings
                for encoding in ['utf-8', 'latin-1', 'cp1252']:
                    try:
                        file.seek(0)
                        df = pd.read_csv(file, encoding=encoding, sep=None, engine='python')
                        break
                    except UnicodeDecodeError:
                        continue
                else:
                    raise ValueError("Não foi possível decodificar o arquivo CSV")
            else:
                # Excel (.xlsx, .xls)
                file.seek(0)
                df = pd.read_excel(file)
            
            return df
            
        except Exception as e:
            raise ValueError(f"Erro ao ler arquivo: {str(e)}")
    
    def _normalize_columns(self, df: pd.DataFrame, column_mapping: dict) -> pd.DataFrame:
        """
        Normaliza nomes de colunas do DataFrame.
        
        Args:
            df: DataFrame original
            column_mapping: Dicionário de mapeamento fonte->destino
            
        Returns:
            DataFrame com colunas renomeadas
        """
        # Remove espaços extras dos nomes das colunas
        df.columns = df.columns.str.strip()
        
        # Mapeia colunas encontradas
        rename_map = {}
        for source, target in column_mapping.items():
            # Busca case-insensitive
            matches = [col for col in df.columns if col.lower() == source.lower()]
            if matches:
                rename_map[matches[0]] = target
        
        return df.rename(columns=rename_map)
    
    def _parse_date(self, value) -> datetime.date:
        """
        Converte valor para date.
        
        Args:
            value: Valor a ser convertido (string, datetime, date)
            
        Returns:
            Date ou None se inválido
        """
        if pd.isna(value) or value is None or value == '':
            return None
        
        # Se já for date/datetime
        if isinstance(value, datetime):
            return value.date()
        if hasattr(value, 'date'):
            return value.date()
        
        # Tenta parsear string
        date_formats = [
            '%d/%m/%Y', '%Y-%m-%d', '%d-%m-%Y',
            '%d/%m/%y', '%Y/%m/%d', '%m/%d/%Y'
        ]
        
        value_str = str(value).strip()
        for fmt in date_formats:
            try:
                return datetime.strptime(value_str, fmt).date()
            except ValueError:
                continue
        
        return None
    
    @transaction.atomic
    def processar_grade_020502(self, file) -> Dict[str, Any]:
        """
        Processa planilha de Grade 020502 (Estoque Total Diário).
        
        Colunas esperadas:
        - Produto: Código SKU
        - Descricao: Nome do produto
        - Unidade: Unidade de medida (cx, un, etc)
        - Fator: Fator de conversão
        - Inventario: Texto original (ex: "388/06")
        - Qtd Contagem: Quantidade total em unidades
        
        Args:
            file: Arquivo upload
            
        Returns:
            Dict com resultado do processamento
        """
        self._reset_counters()
        
        try:
            df = self._read_file(file)
            df = self._normalize_columns(df, self.COLUNAS_GRADE_020502)
            
            # Verifica colunas obrigatórias
            required_cols = ['codigo_sku', 'qtd_estoque']
            missing_cols = [col for col in required_cols if col not in df.columns]
            if missing_cols:
                raise ValueError(f"Colunas obrigatórias não encontradas: {missing_cols}")
            
            # Preenche NaN com valores padrão
            df['qtd_estoque'] = pd.to_numeric(df['qtd_estoque'], errors='coerce').fillna(0).astype(int)
            df['fator_conversao'] = pd.to_numeric(df.get('fator_conversao', 1), errors='coerce').fillna(1).astype(int)
            df['nome_produto'] = df.get('nome_produto', '').fillna('Sem descrição')
            df['unidade_medida'] = df.get('unidade_medida', 'UN').fillna('UN')
            df['estoque_display'] = df.get('estoque_display', '').fillna('')
            
            for idx, row in df.iterrows():
                try:
                    codigo_sku = str(row['codigo_sku']).strip()
                    if not codigo_sku or codigo_sku == 'nan':
                        continue
                    
                    # Busca ou cria SKU
                    sku, created = SKU.objects.get_or_create(
                        codigo_sku=codigo_sku,
                        unidade_negocio=self.unidade_negocio,
                        defaults={
                            'nome_produto': str(row['nome_produto']).strip(),
                            'unidade_medida': str(row['unidade_medida']).strip().upper(),
                            'fator_conversao': int(row['fator_conversao']),
                        }
                    )
                    
                    if not created:
                        # Atualiza dados do SKU
                        sku.nome_produto = str(row['nome_produto']).strip()
                        sku.unidade_medida = str(row['unidade_medida']).strip().upper()
                        sku.fator_conversao = int(row['fator_conversao'])
                        sku.save()
                        self.updated_count += 1
                    else:
                        self.created_count += 1
                    
                    # Busca ou cria Lote BASE (sem validade)
                    lote, lote_created = LoteValidade.objects.get_or_create(
                        sku=sku,
                        numero_lote='BASE',
                        data_validade=None,
                        defaults={
                            'qtd_estoque': int(row['qtd_estoque']),
                            'estoque_display': str(row['estoque_display']).strip(),
                        }
                    )
                    
                    if not lote_created:
                        # Atualiza quantidade
                        lote.qtd_estoque = int(row['qtd_estoque'])
                        lote.estoque_display = str(row['estoque_display']).strip()
                        lote.save()
                    
                    self.processed_count += 1
                    
                except Exception as e:
                    self.errors.append(f"Linha {idx + 2}: {str(e)}")
            
            return self._build_result('Grade 020502')
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'processed': 0,
            }
    
    @transaction.atomic
    def processar_contagens(self, file) -> Dict[str, Any]:
        """
        Processa planilha de Contagens (Conciliação de Validades).
        
        Colunas esperadas:
        - Código Item: Código SKU
        - Validade Aferida: Data de validade
        - Quantidade Cx: Quantidade em caixas
        - Quantidade Unidade: Quantidade em unidades
        
        Args:
            file: Arquivo upload
            
        Returns:
            Dict com resultado do processamento
        """
        self._reset_counters()
        
        try:
            df = self._read_file(file)
            df = self._normalize_columns(df, self.COLUNAS_CONTAGENS)
            
            # Verifica colunas obrigatórias
            required_cols = ['codigo_sku', 'data_validade']
            missing_cols = [col for col in required_cols if col not in df.columns]
            if missing_cols:
                raise ValueError(f"Colunas obrigatórias não encontradas: {missing_cols}")
            
            # Preenche NaN com valores padrão
            df['qtd_caixas'] = pd.to_numeric(df.get('qtd_caixas', 0), errors='coerce').fillna(0).astype(int)
            df['qtd_unidades'] = pd.to_numeric(df.get('qtd_unidades', 0), errors='coerce').fillna(0).astype(int)
            
            for idx, row in df.iterrows():
                try:
                    codigo_sku = str(row['codigo_sku']).strip()
                    if not codigo_sku or codigo_sku == 'nan':
                        continue
                    
                    # Busca SKU existente
                    try:
                        sku = SKU.objects.get(
                            codigo_sku=codigo_sku,
                            unidade_negocio=self.unidade_negocio,
                            ativo=True
                        )
                    except SKU.DoesNotExist:
                        self.warnings.append(
                            f"Linha {idx + 2}: SKU '{codigo_sku}' não encontrado"
                        )
                        continue
                    
                    # Parseia data de validade
                    data_validade = self._parse_date(row['data_validade'])
                    if data_validade is None:
                        self.warnings.append(
                            f"Linha {idx + 2}: Data de validade inválida para SKU '{codigo_sku}'"
                        )
                        continue
                    
                    # Calcula quantidade total em unidades
                    qtd_caixas = int(row['qtd_caixas'])
                    qtd_unidades = int(row['qtd_unidades'])
                    qtd_total = (qtd_caixas * sku.fator_conversao) + qtd_unidades
                    
                    # Gera número de lote baseado na validade
                    numero_lote = f"VAL_{data_validade.strftime('%Y%m%d')}"
                    
                    # Busca ou cria Lote com validade
                    lote, lote_created = LoteValidade.objects.get_or_create(
                        sku=sku,
                        data_validade=data_validade,
                        defaults={
                            'numero_lote': numero_lote,
                            'qtd_estoque': qtd_total,
                        }
                    )
                    
                    if not lote_created:
                        # Soma à quantidade existente ou substitui (depende do requisito)
                        # Por padrão, substituímos
                        lote.qtd_estoque = qtd_total
                        lote.numero_lote = numero_lote  # Atualiza se necessário
                        lote.save()
                        self.updated_count += 1
                    else:
                        self.created_count += 1
                    
                    self.processed_count += 1
                    
                except Exception as e:
                    self.errors.append(f"Linha {idx + 2}: {str(e)}")
            
            return self._build_result('Contagens')
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'processed': 0,
            }
    
    def _reset_counters(self):
        """Reseta contadores para novo processamento."""
        self.errors = []
        self.warnings = []
        self.processed_count = 0
        self.created_count = 0
        self.updated_count = 0
    
    def _build_result(self, tipo: str) -> Dict[str, Any]:
        """Constrói dicionário de resultado."""
        return {
            'success': len(self.errors) == 0 or self.processed_count > 0,
            'tipo': tipo,
            'unidade': str(self.unidade_negocio),
            'processed': self.processed_count,
            'created': self.created_count,
            'updated': self.updated_count,
            'errors': self.errors,
            'warnings': self.warnings,
            'timestamp': timezone.now().isoformat(),
        }
